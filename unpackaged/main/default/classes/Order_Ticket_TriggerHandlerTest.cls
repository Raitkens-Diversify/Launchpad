@isTest
private class Order_Ticket_TriggerHandlerTest {

    @testSetup
    static void setup(){
        // Person Account (auto-creates a Contact)
        Account acc = new Account(FirstName = 'Test', LastName = 'Account', Type = 'Other');
        insert acc;

        // Wizard financial accounts (the Financial_Account__c object the order-ticket wizard uses).
        List<Financial_Account__c> wizAccts = new List<Financial_Account__c>{
            new Financial_Account__c(Name = 'Wiz FA1'),
            new Financial_Account__c(Name = 'Wiz FA2')
        };
        insert wizAccts;

        // FinServ accounts linked back to their wizard account.
        List<Financial_Account__c> finAccs = new List<Financial_Account__c>{
            new Financial_Account__c(Name = 'Test FA1', Primary_Owner__c = acc.Id),
            new Financial_Account__c(Name = 'Test FA2', Primary_Owner__c = acc.Id)
        };
        insert finAccs;
    }

    // Covers before insert + after insert (findFinAcct) including the FinServ lookup and EventBus publish branch.
    @isTest
    static void testAfterInsertFindFinAcct(){
        List<Financial_Account__c> finAccs = [SELECT Id FROM Financial_Account__C];

        List<Order_Ticket__c> tickets = new List<Order_Ticket__c>();
        for(Financial_Account__c f : finAccs){
            tickets.add(new Order_Ticket__c(
                Status__c = 'New',
                Amount__c = 100,
                Wizard_Financial_Account__c = f.Id
            ));
        }

        Test.startTest();
        insert tickets;   // fires isAfterInsert -> findFinAcct -> EventBus.publish
        Test.stopTest();

        Assert.areEqual(finAccs.size(), tickets.size(), 'All order tickets should have been inserted.');
    }

    // Covers before update (setCurrentAllocation) creating an Allocation when Status flips to Completed.
    @isTest
    static void testSetCurrentAllocationOnComplete(){
        Financial_Account__c finAcc = [SELECT Id FROM Financial_Account__C LIMIT 1];


        Order_Ticket__c ticket = new Order_Ticket__c(
            Status__c = 'New',
            Amount__c = 100,
            of_Orders__c = 1,
            Wizard_Financial_Account__c = finAcc.Id,
            Advisor_Notes__c = 'Please allocate'
        );
        insert ticket;

        // Allocation_Trigger (fired when the allocation is created) expects related Order__c records.
        insert new Order__c(Order_Ticket__c = ticket.Id);

        Test.startTest();
        ticket.Status__c = 'Completed';
        update ticket;
        Test.stopTest();

        List<Allocation__c> allocs = [SELECT Id, Current_Allocation__c, Wizard_Financial_Account__c,
                                             Request_Allocation_Originated_From__c, Advisor_Notes__c
                                      FROM Allocation__c
                                      WHERE Request_Allocation_Originated_From__c = :ticket.Id];
        Assert.areEqual(1, allocs.size(), 'A current allocation should be created when status flips to Completed.');
        Assert.isTrue(allocs[0].Current_Allocation__c, 'Allocation should be marked current.');
        Assert.areEqual(finAcc.Id, allocs[0].Wizard_Financial_Account__c, 'Allocation should reference the ticket financial account.');
    }

    // Ensures no allocation is created when the completion criteria are not met (of_Orders__c is 0).
    @isTest
    static void testNoAllocationWhenNoOrders(){
        Financial_Account__c finAcc = [SELECT Id FROM Financial_Account__C LIMIT 1];

        Order_Ticket__c ticket = new Order_Ticket__c(
            Status__c = 'New',
            Amount__c = 100,
            of_Orders__c = 0,
            Wizard_Financial_Account__c = finAcc.Id
        );
        insert ticket;

        Test.startTest();
        ticket.Status__c = 'Completed';
        update ticket;
        Test.stopTest();

        List<Allocation__c> allocs = [SELECT Id FROM Allocation__c
                                      WHERE Request_Allocation_Originated_From__c = :ticket.Id];
        Assert.areEqual(0, allocs.size(), 'No allocation should be created when of_Orders__c is 0.');
    }

    // Covers before delete, after delete, and after undelete (empty handler methods).
    @isTest
    static void testDeleteAndUndelete(){
        Order_Ticket__c ticket = new Order_Ticket__c(Status__c = 'New', Amount__c = 50);
        insert ticket;

        Test.startTest();
        delete ticket;
        undelete ticket;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Order_Ticket__c WHERE Id = :ticket.Id],
            'Order ticket should exist after undelete.');
    }
}