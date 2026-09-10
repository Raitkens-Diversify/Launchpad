/**
 * Order_Ticket_TriggerHandler: the Completed-transition snapshot. A ticket that first reaches
 * Completed with orders and a wizard Financial Account becomes that account's current
 * Allocation__c; Allocation_TriggerHandler then copies the orders onto it as strategies.
 *
 * Every Funding_Basis__c reference is kept on its own line on purpose:
 * the prod build of this class is derived by dropping each line that names that field
 * (see manifest/order-ticket-allocation).
 */
@isTest
private class Order_Ticket_TriggerHandlerTest {

    @testSetup
    static void setup() {
        // Financial_Advisor_Team_Trigger creates the team public group on insert; the wizard
        // Financial Account carries the team so the allocation can inherit it.
        insert new Financial_Advisor_Team__c(Name = 'OT Test Team');
        Financial_Advisor_Team__c team = [SELECT Id FROM Financial_Advisor_Team__c WHERE Name = 'OT Test Team' LIMIT 1];
        insert new List<Financial_Account__c>{
            new Financial_Account__c(Name = 'OT Wiz FA With Team', Financial_Advisor_Team__c = team.Id),
            new Financial_Account__c(Name = 'OT Wiz FA No Team')
        };
        insert new Strategy__c(Name = 'OT Core Equity', Status__c = 'Active', Strategy_Code__c = 'CE');
    }

    private static Financial_Account__c wizardAccount(String name) {
        return [SELECT Id, Financial_Advisor_Team__c FROM Financial_Account__c WHERE Name = :name LIMIT 1];
    }

    private static Order_Ticket__c newTicket(Id wizardAccountId, Decimal orderCount) {
        return new Order_Ticket__c(
            Status__c = 'New',
            Amount__c = 100,
            of_Orders__c = orderCount,
            Wizard_Financial_Account__c = wizardAccountId,
            Advisor_Notes__c = 'Please allocate'
        );
    }

    private static List<Order__c> ordersFor(Id ticketId) {
        Id strategyId = [SELECT Id FROM Strategy__c WHERE Name = 'OT Core Equity' LIMIT 1].Id;
        return new List<Order__c>{
            new Order__c(
                Order_Ticket__c = ticketId,
                Strategy__c = strategyId,
                Strategy_Code__c = 101,
                Order_Type__c = 'Buy',
                Funding_Basis__c = 'Percent',
                Initial_Funding_Percentage__c = 60
            ),
            new Order__c(
                Order_Ticket__c = ticketId,
                Strategy__c = strategyId,
                Strategy_Code__c = 102,
                Order_Type__c = 'Buy',
                Funding_Basis__c = 'Dollar',
                Initial_Funding_Amount__c = 4000
            )
        };
    }

    private static List<Allocation__c> allocationsFor(Id ticketId) {
        return [
            SELECT Id, Current_Allocation__c, Date_Implemented__c, Wizard_Financial_Account__c,
                   Financial_Advisor_Team__c, Advisor_Notes__c, Request_Allocation_Originated_From__c
            FROM Allocation__c
            WHERE Request_Allocation_Originated_From__c = :ticketId
        ];
    }

    @isTest
    static void completionCreatesCurrentAllocationWithStrategies() {
        Financial_Account__c wizFa = wizardAccount('OT Wiz FA With Team');
        Order_Ticket__c ticket = newTicket(wizFa.Id, 2);
        insert ticket;
        insert ordersFor(ticket.Id);

        Test.startTest();
        ticket.Status__c = 'Completed';
        update ticket;
        Test.stopTest();

        List<Allocation__c> allocs = allocationsFor(ticket.Id);
        Assert.areEqual(1, allocs.size(), 'Completing a ticket with orders creates one allocation.');
        Allocation__c alloc = allocs[0];
        Assert.isTrue(alloc.Current_Allocation__c, 'The new allocation is the current one.');
        Assert.areEqual(Date.today(), alloc.Date_Implemented__c, 'Implemented today.');
        Assert.areEqual(wizFa.Id, alloc.Wizard_Financial_Account__c, 'Keyed on the ticket wizard account.');
        Assert.areEqual(wizFa.Financial_Advisor_Team__c, alloc.Financial_Advisor_Team__c, 'Team inherited from the wizard account.');
        Assert.areEqual('Please allocate', alloc.Advisor_Notes__c, 'Advisor notes carried over.');

        List<Allocation_Strategy__c> strategies = [
            SELECT Strategy_Code__c FROM Allocation_Strategy__c WHERE Allocation__c = :alloc.Id ORDER BY Strategy_Code__c
        ];
        Assert.areEqual(2, strategies.size(), 'Allocation_TriggerHandler copied both orders onto the allocation.');
        Assert.isTrue(strategies[0].Strategy_Code__c == 101, 'First strategy code copied, was ' + strategies[0].Strategy_Code__c);
        Assert.isTrue(strategies[1].Strategy_Code__c == 102, 'Second strategy code copied, was ' + strategies[1].Strategy_Code__c);
    }

    @isTest
    static void accountWithoutTeamStillGetsAllocation() {
        Financial_Account__c wizFa = wizardAccount('OT Wiz FA No Team');
        Order_Ticket__c ticket = newTicket(wizFa.Id, 1);
        insert ticket;
        insert new Order__c(Order_Ticket__c = ticket.Id, Strategy_Code__c = 103, Initial_Funding_Percentage__c = 100);

        Test.startTest();
        ticket.Status__c = 'Completed';
        update ticket;
        Test.stopTest();

        List<Allocation__c> allocs = allocationsFor(ticket.Id);
        Assert.areEqual(1, allocs.size(), 'A teamless wizard account still gets its allocation.');
        Assert.isNull(allocs[0].Financial_Advisor_Team__c, 'No team to inherit.');
    }

    @isTest
    static void noOrdersMeansNoAllocation() {
        Financial_Account__c wizFa = wizardAccount('OT Wiz FA With Team');
        Order_Ticket__c zeroOrders = newTicket(wizFa.Id, 0);
        Order_Ticket__c nullOrders = newTicket(wizFa.Id, null);
        insert new List<Order_Ticket__c>{ zeroOrders, nullOrders };

        Test.startTest();
        zeroOrders.Status__c = 'Completed';
        nullOrders.Status__c = 'Completed';
        update new List<Order_Ticket__c>{ zeroOrders, nullOrders };
        Test.stopTest();

        Assert.areEqual(0, allocationsFor(zeroOrders.Id).size(), 'Zero orders: no allocation.');
        Assert.areEqual(0, allocationsFor(nullOrders.Id).size(), 'Blank order count: no allocation.');
    }

    @isTest
    static void noWizardAccountMeansNoAllocationAndNoError() {
        Order_Ticket__c ticket = newTicket(null, 1);
        insert ticket;
        insert new Order__c(Order_Ticket__c = ticket.Id, Strategy_Code__c = 104, Initial_Funding_Percentage__c = 100);

        Test.startTest();
        ticket.Status__c = 'Completed';
        update ticket;   // used to throw a NullPointerException out of the trigger
        Test.stopTest();

        Assert.areEqual('Completed', [SELECT Status__c FROM Order_Ticket__c WHERE Id = :ticket.Id].Status__c,
            'The ticket still completes.');
        Assert.areEqual(0, allocationsFor(ticket.Id).size(), 'Nothing to key the allocation on, so none is created.');
    }

    @isTest
    static void onlyTheTransitionIntoCompletedCreatesAnAllocation() {
        Financial_Account__c wizFa = wizardAccount('OT Wiz FA With Team');
        Order_Ticket__c ticket = newTicket(wizFa.Id, 1);
        insert ticket;
        insert new Order__c(Order_Ticket__c = ticket.Id, Strategy_Code__c = 105, Initial_Funding_Percentage__c = 100);

        Test.startTest();
        ticket.Status__c = 'Ops Review';
        update ticket;
        Assert.areEqual(0, allocationsFor(ticket.Id).size(), 'Moving to a non-Completed status creates nothing.');

        ticket.Status__c = 'Completed';
        update ticket;
        Assert.areEqual(1, allocationsFor(ticket.Id).size(), 'First arrival at Completed creates the allocation.');

        ticket.Advisor_Notes__c = 'Edited after completion';
        update ticket;
        Test.stopTest();

        Assert.areEqual(1, allocationsFor(ticket.Id).size(), 'Editing an already-Completed ticket does not add another.');
    }

    @isTest
    static void bulkUpdateOnlyAllocatesQualifyingTickets() {
        Financial_Account__c wizFa = wizardAccount('OT Wiz FA With Team');
        Order_Ticket__c qualifying = newTicket(wizFa.Id, 1);
        Order_Ticket__c noOrders = newTicket(wizFa.Id, 0);
        Order_Ticket__c noAccount = newTicket(null, 1);
        Order_Ticket__c staysOpen = newTicket(wizFa.Id, 1);
        List<Order_Ticket__c> tickets = new List<Order_Ticket__c>{ qualifying, noOrders, noAccount, staysOpen };
        insert tickets;
        insert new List<Order__c>{
            new Order__c(Order_Ticket__c = qualifying.Id, Strategy_Code__c = 106, Initial_Funding_Percentage__c = 100),
            new Order__c(Order_Ticket__c = noAccount.Id, Strategy_Code__c = 107, Initial_Funding_Percentage__c = 100),
            new Order__c(Order_Ticket__c = staysOpen.Id, Strategy_Code__c = 108, Initial_Funding_Percentage__c = 100)
        };

        Test.startTest();
        qualifying.Status__c = 'Completed';
        noOrders.Status__c = 'Completed';
        noAccount.Status__c = 'Completed';
        staysOpen.Status__c = 'Ops Complete';
        update tickets;
        Test.stopTest();

        Assert.areEqual(1, allocationsFor(qualifying.Id).size(), 'Only the qualifying ticket allocates.');
        Assert.areEqual(0, allocationsFor(noOrders.Id).size());
        Assert.areEqual(0, allocationsFor(noAccount.Id).size());
        Assert.areEqual(0, allocationsFor(staysOpen.Id).size());
        Assert.areEqual(1, [SELECT COUNT() FROM Allocation__c], 'Exactly one allocation across the whole batch.');
    }

    @isTest
    static void deleteAndUndeleteRunTheEmptyHandlers() {
        Order_Ticket__c ticket = newTicket(null, 0);
        insert ticket;

        Test.startTest();
        delete ticket;
        undelete ticket;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Order_Ticket__c WHERE Id = :ticket.Id], 'Ticket restored.');
    }
}