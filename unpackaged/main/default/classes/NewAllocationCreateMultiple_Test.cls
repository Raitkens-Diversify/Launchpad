@isTest
public class NewAllocationCreateMultiple_Test {

    @testSetup
    public static void setup(){
        // create person account
        Account acc = new Account(FirstName = 'Test', LastName='Account');
        insert acc;
        
        Contact con1 = [SELECT Id FROM Contact WHERE AccountId =: acc.Id];  
        
        List<FinServ__FinancialAccount__c> finAccs = new List<FinServ__FinancialAccount__c>();
        finAccs.add(new FinServ__FinancialAccount__c(Name = 'Test FA1',
                                                     FinServ__PrimaryOwner__c = acc.Id));
        finAccs.add(new FinServ__FinancialAccount__c(Name = 'Test FA2',
                                                     FinServ__PrimaryOwner__c = acc.Id));
        insert finAccs;
        
        
        
        
        
        List<Advertising_Item__c> adItemsList = new List<Advertising_Item__c>();
        adItemsList.add(new Advertising_Item__c(Flow_Interview_ID__c = 'testFlowInt132', Advertising_Type__c = 'Social Media Profile'));
        adItemsList.add(new Advertising_Item__c(Flow_Interview_ID__c = 'testFlowInt234', Advertising_Type__c = 'Social Media Content'));        
        insert adItemsList;
    }
    
    @isTest
    private static void getFieldAndDatatypeTest(){
        String sobjectName = 'Account';
        List<String> sObjectFields = new List<String>{'FirstName', 'LastName' , 'Salutation'};
            Test.startTest();
        List<NewAllocationCreateMultipleController.FieldObj> headerList = NewAllocationCreateMultipleController.getFieldAndDatatype(sobjectName,sObjectFields,null);
        Test.stopTest();
        Assert.isTrue(headerList.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void getPicklistOptionsTest(){
        String sobjectName = 'Account';
        String sObjectField = 'Salutation';
        Test.startTest();
        List<String> picklistOptions = NewAllocationCreateMultipleController.getPicklistOptions(sobjectName,sObjectField);
        Test.stopTest();
        Assert.isTrue(picklistOptions.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void getExistingRecordsTest(){
        
        List<FinServ__FinancialAccount__c> finAccs = [SELECT Id FROM FinServ__FinancialAccount__c ORDER BY Name Desc];
        Id wizFinId1 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1' LIMIT 1].Wizard_Financial_Account__c;
        System.debug('wizFinId 1: ' + wizFinId1);
        Id wizFinId2 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA2' LIMIT 1].Wizard_Financial_Account__c;

        
        List<Order_Ticket__c> ot2List = new List<Order_Ticket__c>();
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 40.5, Amount__c = 40.5, Financial_Account__c = finAccs[0].Id, Wizard_Financial_Account__c = wizFinId1));
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 30, Amount__c = 30, Financial_Account__c = finAccs[1].Id, Wizard_Financial_Account__c = wizFinId2));
        insert ot2List;
        
        System.debug('ot2List: ' + ot2List);
        
        List<Order__c> oList = new List<Order__c>();
        oList.add(new Order__c(Order_Ticket__c = ot2List[0].Id));
        oList.add(new Order__c(Order_Ticket__c = ot2List[1].Id));
        insert oList;
        
        Allocation__c alloc = new Allocation__c(Request_Allocation_Originated_From__c = ot2List[0].Id);
        insert alloc;
        
        List<Allocation_Strategy__c> otList = new List<Allocation_Strategy__c>();
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 40.5, Initial_Funding_Amount__c = 40.5, Allocation__c = alloc.Id));
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 30, Initial_Funding_Amount__c  = 30, Allocation__c = alloc.Id));
        insert otList;
        
        String sobjectName = 'FinServ__FinancialAccount__c';
        String parentRecordId = [SELECT Id FROM Allocation__c Limit 1].Id;
        String wizFinId = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1' LIMIT 1].Wizard_Financial_Account__c;
        String parentLookup = 'FinServ__PrimaryOwner__c' ;
        List<String> sObjectFields = new List<String>{'Strategy_Name__c', 'Initial_Funding_Percentage__c'};
            Test.startTest();
        List<SObject> lstRecords = NewAllocationCreateMultipleController.getExistingRecordsToCreateNew(parentRecordId,wizFinId,parentLookup,sObjectFields,null);
        Test.stopTest();
        Assert.isTrue(lstRecords.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void upsertRecordTest(){
        List<FinServ__FinancialAccount__c> finAccs = [SELECT Id FROM FinServ__FinancialAccount__c ORDER BY Name Desc];
        Id wizFinId1 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1' LIMIT 1].Wizard_Financial_Account__c;
        System.debug('wizFinId 1: ' + wizFinId1);
        Id wizFinId2 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA2' LIMIT 1].Wizard_Financial_Account__c;

        
        List<Order_Ticket__c> ot2List = new List<Order_Ticket__c>();
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 40.5, Amount__c = 40.5, Financial_Account__c = finAccs[0].Id, Wizard_Financial_Account__c = wizFinId1));
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 30, Amount__c = 30, Financial_Account__c = finAccs[1].Id, Wizard_Financial_Account__c = wizFinId2));
        insert ot2List;
        
        List<Order__c> oList = new List<Order__c>();
        oList.add(new Order__c(Order_Ticket__c = ot2List[0].Id));
        oList.add(new Order__c(Order_Ticket__c = ot2List[1].Id));
        insert oList;
        
        Allocation__c alloc = new Allocation__c(Request_Allocation_Originated_From__c = ot2List[0].Id);
        insert alloc;
        
        List<Allocation_Strategy__c> otList = new List<Allocation_Strategy__c>();
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 40.5, Initial_Funding_Amount__c = 40.5, Allocation__c = alloc.Id));
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 30, Initial_Funding_Amount__c  = 30, Allocation__c = alloc.Id));
        insert otList;
        
        String sobjectName = 'Account';
        Map<String, String> recordValues = new Map<String, String>();
        String parentRecordId = [SELECT Id FROM Allocation__c Limit 1].Id;
        String wizFinId = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1' LIMIT 1].Wizard_Financial_Account__c;
        recordValues.put('Name' , 'Testing');
        recordValues.put('IsDeleted' , 'false');
        recordValues.put('Salutation' , 'Mr');
        Test.startTest();
        SObject returnedSObjectRecord = NewAllocationCreateMultipleController.upsertRecordForCurrentAllocation(recordValues,parentRecordId,wizFinId);
        Test.stopTest();
        List<Account> accsAfterUpsert = [SELECT Id, Name FROM Account];
        Assert.isTrue(returnedSObjectRecord != Null, 'Method should return a value.');
        Assert.areEqual(1, accsAfterUpsert.size());
    }
    
    
    @isTest
    private static void getTotalFieldSumBLSTCMTest(){
        List<FinServ__FinancialAccount__c> finAccs = [SELECT Id FROM FinServ__FinancialAccount__c ORDER BY Name Desc];
        Id wizFinId1 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1' LIMIT 1].Wizard_Financial_Account__c;
        System.debug('wizFinId 1: ' + wizFinId1);
        Id wizFinId2 = [SELECT Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA2' LIMIT 1].Wizard_Financial_Account__c;

        
        List<Order_Ticket__c> ot2List = new List<Order_Ticket__c>();
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 40.5, Amount__c = 40.5, Financial_Account__c = finAccs[0].Id, Wizard_Financial_Account__c = wizFinId1));
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 30, Amount__c = 30, Financial_Account__c = finAccs[1].Id, Wizard_Financial_Account__c = wizFinId2));
        insert ot2List;
        
        System.debug('ot2List: ' + ot2List);
        
        List<Order__c> oList = new List<Order__c>();
        oList.add(new Order__c(Order_Ticket__c = ot2List[0].Id));
        oList.add(new Order__c(Order_Ticket__c = ot2List[1].Id));
        insert oList;
        
        Allocation__c alloc = new Allocation__c(Request_Allocation_Originated_From__c = ot2List[0].Id);
        insert alloc;
        
        List<Allocation_Strategy__c> otList = new List<Allocation_Strategy__c>();
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 40.5, Initial_Funding_Amount__c = 40.5, Allocation__c = alloc.Id));
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 30, Initial_Funding_Amount__c  = 30, Allocation__c = alloc.Id));
        insert otList;
        Order_Ticket__c o = [SELECT Id FROM Order_Ticket__c ORDER BY CreatedDate desc LIMIT 1];
        Test.startTest();
        NewAllocationCreateMultipleController.SumObj sumObj = NewAllocationCreateMultipleController.getTotalFieldSumBLSTCM(o.Id);
        Test.stopTest();
        System.debug('sumObj.result: ' + sumObj.result);
        //Assert.isTrue(sumObj.result == 70.5);
        
    }
    
    @isTest
    private static void deleteAllocs(){
        List<Order_Ticket__c> ot2List = new List<Order_Ticket__c>();
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 40.5, Amount__c = 40.5));
        ot2List.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 30, Amount__c = 30));
        insert ot2List;

		List<Order__c> oList = new List<Order__c>();
        oList.add(new Order__c(Order_Ticket__c = ot2List[0].Id));
        oList.add(new Order__c(Order_Ticket__c = ot2List[1].Id));
        insert oList;
        
        Allocation__c alloc = new Allocation__c(Request_Allocation_Originated_From__c = ot2List[0].Id);
        insert alloc;
        
        List<Allocation_Strategy__c> otList = new List<Allocation_Strategy__c>();
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 40.5, Initial_Funding_Amount__c = 40.5, Allocation__c = alloc.Id));
        otList.add(new Allocation_Strategy__c(Initial_Funding_Percentage__c = 30, Initial_Funding_Amount__c  = 30, Allocation__c = alloc.Id));
        insert otList;
        
        Allocation__c alloc2 = [SELECT Id FROM Allocation__c LIMIT 1];
        delete alloc2;
        undelete alloc2;
    }
}