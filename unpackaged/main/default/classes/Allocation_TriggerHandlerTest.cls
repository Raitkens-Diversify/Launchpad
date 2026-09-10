/**
 * Allocation_TriggerHandler: what a new allocation does on arrival (copies its ticket's orders
 * onto itself as strategies, shares itself with the team public group, retires the account's
 * previous current allocation) and how the manual share follows a team change on update.
 *
 * Every Funding_Basis__c reference is kept on its own line on purpose:
 * the prod build of this class is derived by dropping each line that names that field
 * (see manifest/order-ticket-allocation).
 */
@isTest
private class Allocation_TriggerHandlerTest {

    @testSetup
    static void setup() {
        // Financial_Advisor_Team_Trigger creates each team public group on insert and stores its
        // Id in Public_Group_ID__c, which is what the allocation share row points at.
        insert new List<Financial_Advisor_Team__c>{
            new Financial_Advisor_Team__c(Name = 'Alloc Team A'),
            new Financial_Advisor_Team__c(Name = 'Alloc Team B')
        };
        insert new List<Financial_Account__c>{
            new Financial_Account__c(Name = 'Alloc Wiz FA 1'),
            new Financial_Account__c(Name = 'Alloc Wiz FA 2')
        };
        insert new Strategy__c(Name = 'Alloc Core Equity', Status__c = 'Active', Strategy_Code__c = 'CE');
        // Two tickets, told apart by Amount__c (Advisor_Notes__c is a long text area and cannot be
        // filtered on): 200 carries the orders to copy, 50 has none.
        insert new List<Order_Ticket__c>{
            new Order_Ticket__c(Status__c = 'New', Amount__c = 200, of_Orders__c = 2, Advisor_Notes__c = 'With orders'),
            new Order_Ticket__c(Status__c = 'New', Amount__c = 50, of_Orders__c = 0, Advisor_Notes__c = 'No orders')
        };
        Id ticketId = ticketId(200);
        Id strategyId = [SELECT Id FROM Strategy__c WHERE Name = 'Alloc Core Equity' LIMIT 1].Id;
        insert new List<Order__c>{
            new Order__c(
                Order_Ticket__c = ticketId,
                Strategy__c = strategyId,
                Strategy_Code__c = 201,
                Order_Type__c = 'Buy',
                Funding_Basis__c = 'Percent',
                Initial_Funding_Percentage__c = 60,
                Principal_Amount__c = 6000,
                Share_Price__c = 12.5,
                Share_Quantity__c = 480,
                Total_Initial_Funding_Amount__c = 10000,
                Excluded_From_Allocation__c = false
            ),
            new Order__c(
                Order_Ticket__c = ticketId,
                Strategy__c = strategyId,
                Strategy_Code__c = 202,
                Order_Type__c = 'Sel',   // Order_Type__c is 3 chars wide
                Funding_Basis__c = 'Dollar',
                Initial_Funding_Amount__c = 4000,
                Principal_Amount__c = 4000,
                Share_Price__c = 20,
                Share_Quantity__c = 200,
                Total_Initial_Funding_Amount__c = 10000,
                Excluded_From_Allocation__c = true
            )
        };
    }

    /** Integer literal vs Decimal field: Assert.areEqual compares types too, == compares values. */
    private static void assertNumber(Decimal expected, Decimal actual, String label) {
        Assert.isTrue(expected == actual, label + ' expected ' + expected + ' but was ' + actual);
    }

    private static Financial_Advisor_Team__c team(String name) {
        return [SELECT Id, Public_Group_ID__c FROM Financial_Advisor_Team__c WHERE Name = :name LIMIT 1];
    }

    private static Id wizardAccountId(String name) {
        return [SELECT Id FROM Financial_Account__c WHERE Name = :name LIMIT 1].Id;
    }

    private static Id ticketId(Decimal amount) {
        return [SELECT Id FROM Order_Ticket__c WHERE Amount__c = :amount LIMIT 1].Id;
    }

    private static Allocation__c newAllocation(Id wizardAccountId, Id originatingTicketId, Id teamId, Date implemented) {
        return new Allocation__c(
            Current_Allocation__c = true,
            Date_Implemented__c = implemented,
            Wizard_Financial_Account__c = wizardAccountId,
            Request_Allocation_Originated_From__c = originatingTicketId,
            Financial_Advisor_Team__c = teamId
        );
    }

    private static List<Allocation__Share> manualShares(Id allocationId) {
        return [
            SELECT UserOrGroupId, AccessLevel FROM Allocation__Share
            WHERE ParentId = :allocationId AND RowCause = 'Manual'
        ];
    }

    private static Allocation__c reload(Id allocationId) {
        return [
            SELECT Id, Current_Allocation__c, Date_Inactivated__c, Request_Allocation_Inactivated_From__c
            FROM Allocation__c WHERE Id = :allocationId
        ];
    }

    @isTest
    static void insertCopiesTicketOrdersOntoStrategies() {
        Allocation__c alloc = newAllocation(wizardAccountId('Alloc Wiz FA 1'), ticketId(200), null, Date.today());

        Test.startTest();
        insert alloc;
        Test.stopTest();

        List<Allocation_Strategy__c> strategies = [
            SELECT Strategy__c, Strategy_Code__c, Order_Type__c, Initial_Funding_Amount__c, Initial_Funding_Percentage__c,
                   Principal_Amount__c, Share_Price__c, Share_Quantity__c, Total_Initial_Funding_Amount__c,
                   Funding_Basis__c,
                   Excluded_From_Allocation__c
            FROM Allocation_Strategy__c WHERE Allocation__c = :alloc.Id ORDER BY Strategy_Code__c
        ];
        Assert.areEqual(2, strategies.size(), 'One strategy per order on the originating ticket.');

        Allocation_Strategy__c percentSleeve = strategies[0];
        assertNumber(201, percentSleeve.Strategy_Code__c, 'percentSleeve.Strategy_Code__c');
        Assert.areEqual('Buy', percentSleeve.Order_Type__c);
        assertNumber(60, percentSleeve.Initial_Funding_Percentage__c, 'percentSleeve.Initial_Funding_Percentage__c');
        Assert.isNull(percentSleeve.Initial_Funding_Amount__c);
        assertNumber(6000, percentSleeve.Principal_Amount__c, 'percentSleeve.Principal_Amount__c');
        assertNumber(12.5, percentSleeve.Share_Price__c, 'percentSleeve.Share_Price__c');
        assertNumber(480, percentSleeve.Share_Quantity__c, 'percentSleeve.Share_Quantity__c');
        assertNumber(10000, percentSleeve.Total_Initial_Funding_Amount__c, 'percentSleeve.Total_Initial_Funding_Amount__c');
        Assert.isFalse(percentSleeve.Excluded_From_Allocation__c);
        Assert.areEqual('Percent', percentSleeve.Funding_Basis__c);
        Assert.areEqual([SELECT Id FROM Strategy__c WHERE Name = 'Alloc Core Equity' LIMIT 1].Id, percentSleeve.Strategy__c);

        Allocation_Strategy__c dollarSleeve = strategies[1];
        assertNumber(202, dollarSleeve.Strategy_Code__c, 'dollarSleeve.Strategy_Code__c');
        Assert.areEqual('Sel', dollarSleeve.Order_Type__c);
        assertNumber(4000, dollarSleeve.Initial_Funding_Amount__c, 'dollarSleeve.Initial_Funding_Amount__c');
        Assert.isNull(dollarSleeve.Initial_Funding_Percentage__c);
        Assert.isTrue(dollarSleeve.Excluded_From_Allocation__c, 'Exception-sleeve flag carried forward.');
        Assert.areEqual('Dollar', dollarSleeve.Funding_Basis__c);
    }

    @isTest
    static void insertWithoutOrdersOrTicketCreatesNoStrategiesAndNoError() {
        Allocation__c ticketWithoutOrders = newAllocation(wizardAccountId('Alloc Wiz FA 1'), ticketId(50), null, Date.today());
        Allocation__c noTicket = newAllocation(wizardAccountId('Alloc Wiz FA 2'), null, null, Date.today());

        Test.startTest();
        insert new List<Allocation__c>{ ticketWithoutOrders, noTicket };   // used to throw on the null order list
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Allocation_Strategy__c], 'Nothing to copy, nothing created.');
    }

    @isTest
    static void insertSharesWithTeamPublicGroup() {
        Financial_Advisor_Team__c teamA = team('Alloc Team A');
        Assert.isNotNull(teamA.Public_Group_ID__c, 'Team trigger should have created the public group.');
        Allocation__c withTeam = newAllocation(wizardAccountId('Alloc Wiz FA 1'), null, teamA.Id, Date.today());
        Allocation__c withoutTeam = newAllocation(wizardAccountId('Alloc Wiz FA 2'), null, null, Date.today());

        Test.startTest();
        insert new List<Allocation__c>{ withTeam, withoutTeam };
        Test.stopTest();

        List<Allocation__Share> shares = manualShares(withTeam.Id);
        Assert.areEqual(1, shares.size(), 'One manual share for the team group.');
        Assert.areEqual(teamA.Public_Group_ID__c, shares[0].UserOrGroupId);
        Assert.areEqual('Edit', shares[0].AccessLevel);
        Assert.areEqual(0, manualShares(withoutTeam.Id).size(), 'No team, no share.');
    }

    @isTest
    static void insertRetiresEveryPreviousCurrentAllocationOnTheAccount() {
        Id fa1 = wizardAccountId('Alloc Wiz FA 1');
        Id fa2 = wizardAccountId('Alloc Wiz FA 2');
        Date earlier = Date.today().addDays(-30);
        // Inserted together so neither retires the other (batch members are excluded from the
        // supersede query), leaving fa1 with two current allocations, as prod data does today.
        Allocation__c fa1First = newAllocation(fa1, null, null, earlier);
        Allocation__c fa1Second = newAllocation(fa1, null, null, earlier);
        Allocation__c fa2Current = newAllocation(fa2, null, null, earlier);
        insert new List<Allocation__c>{ fa1First, fa1Second, fa2Current };

        Id newTicket = ticketId(50);
        Allocation__c replacement = newAllocation(fa1, newTicket, null, Date.today());

        Test.startTest();
        insert replacement;
        Test.stopTest();

        for (Allocation__c retired : new List<Allocation__c>{ reload(fa1First.Id), reload(fa1Second.Id) }) {
            Assert.isFalse(retired.Current_Allocation__c, 'Previous allocation on the same account is retired.');
            Assert.areEqual(newTicket, retired.Request_Allocation_Inactivated_From__c, 'Stamped with the superseding ticket.');
            Assert.areEqual(Date.today(), retired.Date_Inactivated__c, 'Inactivated on the replacement implemented date.');
        }
        Assert.isTrue(reload(fa2Current.Id).Current_Allocation__c, 'Another account is untouched.');
        Assert.isTrue(reload(replacement.Id).Current_Allocation__c, 'The replacement stays current.');
    }

    @isTest
    static void twoNewAllocationsForOneAccountRetireThePredecessorOnce() {
        Id fa1 = wizardAccountId('Alloc Wiz FA 1');
        Allocation__c previous = newAllocation(fa1, null, null, Date.today().addDays(-30));
        insert previous;

        Test.startTest();
        insert new List<Allocation__c>{
            newAllocation(fa1, null, null, Date.today()),
            newAllocation(fa1, null, null, Date.today())
        };   // used to fail with a duplicate Id in the update list
        Test.stopTest();

        Assert.isFalse(reload(previous.Id).Current_Allocation__c, 'Predecessor retired.');
        Assert.areEqual(2, [SELECT COUNT() FROM Allocation__c WHERE Wizard_Financial_Account__c = :fa1 AND Current_Allocation__c = true],
            'Both batch members stay current.');
    }

    @isTest
    static void insertWithoutWizardAccountRetiresNothing() {
        Allocation__c unkeyedPrevious = newAllocation(null, null, null, Date.today().addDays(-30));
        insert unkeyedPrevious;

        Test.startTest();
        insert newAllocation(null, null, null, Date.today());
        Test.stopTest();

        Assert.isTrue(reload(unkeyedPrevious.Id).Current_Allocation__c, 'Nothing to key on, so nothing is retired.');
    }

    @isTest
    static void teamChangeMovesTheManualShare() {
        Financial_Advisor_Team__c teamA = team('Alloc Team A');
        Financial_Advisor_Team__c teamB = team('Alloc Team B');
        Allocation__c alloc = newAllocation(wizardAccountId('Alloc Wiz FA 1'), null, teamA.Id, Date.today());
        insert alloc;

        Test.startTest();
        alloc.Financial_Advisor_Team__c = teamB.Id;
        update alloc;
        Test.stopTest();

        List<Allocation__Share> afterMove = manualShares(alloc.Id);
        Assert.areEqual(1, afterMove.size(), 'Old group share revoked, new group share granted.');
        Assert.areEqual(teamB.Public_Group_ID__c, afterMove[0].UserOrGroupId);
    }

    @isTest
    static void updateWithoutTeamChangeLeavesTheShareAlone() {
        Financial_Advisor_Team__c teamA = team('Alloc Team A');
        Allocation__c alloc = newAllocation(wizardAccountId('Alloc Wiz FA 1'), null, teamA.Id, Date.today());
        insert alloc;

        Test.startTest();
        alloc.Advisor_Notes__c = 'Edited';
        update alloc;
        Test.stopTest();

        List<Allocation__Share> shares = manualShares(alloc.Id);
        Assert.areEqual(1, shares.size(), 'Share count unchanged.');
        Assert.areEqual(teamA.Public_Group_ID__c, shares[0].UserOrGroupId);
    }

    @isTest
    static void deleteAndUndeleteRunTheEmptyHandlers() {
        Allocation__c alloc = newAllocation(wizardAccountId('Alloc Wiz FA 1'), ticketId(200), null, Date.today());
        insert alloc;

        Test.startTest();
        delete alloc;
        undelete alloc;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Allocation__c WHERE Id = :alloc.Id], 'Allocation restored.');
        Assert.areEqual(2, [SELECT COUNT() FROM Allocation_Strategy__c WHERE Allocation__c = :alloc.Id], 'Strategies restored with it.');
    }
}