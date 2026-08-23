@isTest
public class FlowCreateMultipleController_Test {
    /*@testSetup
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
        
        List<Financial_Advisor_Team__c> fatList = new List<Financial_Advisor_Team__c>();
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 1', Orion_ID__c = 1234));
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 2', Orion_ID__c = 12345));
        fatList.add(new Financial_Advisor_Team__c(Name='Default Team'));
        insert fatList;
        
        List<Order_Ticket__c> otList = new List<Order_Ticket__c>();
        otList.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 40.5, Financial_Account__c = finAccs[0].Id));
        otList.add(new Order_Ticket__c(Initial_Funding_Percentage__c = 30, Financial_Account__c = finAccs[0].Id));
        insert otList;
        
        List<Order__c> orderList = new List<Order__c>();
        orderList.add(new Order__c(Order_Ticket__c = otList[0].Id));
        insert orderList;
        
        List<Allocation__c> allocList = new List<Allocation__c>();
        allocList.add(new Allocation__c(Financial_Account__c = finAccs[0].Id, Request_Allocation_Originated_From__c = otList[0].Id, Financial_Advisor_Team__c = fatList[0].Id));
        insert allocList;
        
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
        List<FlowCreateMultipleController.FieldObj> headerList = FlowCreateMultipleController.getFieldAndDatatype(sobjectName,sObjectFields, null);
        Test.stopTest();
        Assert.isTrue(headerList.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void getPicklistOptionsTest(){
        String sobjectName = 'Account';
        String sObjectField = 'Salutation';
        Test.startTest();
        List<String> picklistOptions = FlowCreateMultipleController.getPicklistOptions(sobjectName,sObjectField);
        Test.stopTest();
        Assert.isTrue(picklistOptions.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void setCurrentAllocationTest(){
        Order_Ticket__c ot = [SELECT Id, Status__c FROM Order_Ticket__c LIMIT 1];
        ot.Status__c = 'Completed';
        update ot;
    }
    
    @isTest
    private static void getExistingRecordsTest(){
        String sobjectName = 'Contact';
        String parentRecordId = [SELECT Id, LastName, FirstName, AccountId FROM Contact Limit 1].AccountId;
        String parentLookup = 'AccountId' ;
        List<String> sObjectFields = new List<String>{'FirstName', 'LastName'};
            Test.startTest();
        List<SObject> lstRecords = FlowCreateMultipleController.getExistingRecords(parentRecordId,sobjectName,parentLookup,sObjectFields,null);
        Test.stopTest();
        Assert.isTrue(lstRecords.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void getExistingRecordsTestNewAllocation(){
        String sobjectName = 'Allocation__c';
        String parentRecordId = [SELECT Id FROM Allocation__c Limit 1].Id;
        List<String> sObjectFields = new List<String>{'FirstName', 'LastName'};
            Test.startTest();
        List<SObject> lstRecords = NewAllocationCreateMultipleController.getExistingRecordsToCreateNew(parentRecordId,sobjectName,sObjectFields,null);
        Test.stopTest();
        Assert.isTrue(lstRecords.size() > 0, 'Method should return list.');
    }
    
    @isTest
    private static void upsertRecordTest(){
        String sobjectName = 'Account';
        Map<String, String> recordValues = new Map<String, String>();
        recordValues.put('Name' , 'Testing');
        recordValues.put('IsDeleted' , 'false');
        recordValues.put('Salutation' , 'Mr');
        Test.startTest();
        SObject returnedSObjectRecord = FlowCreateMultipleController.upsertRecord(sobjectName,recordValues,null);
        Test.stopTest();
        List<Account> accsAfterUpsert = [SELECT Id, Name FROM Account];
        Assert.isTrue(returnedSObjectRecord != Null, 'Method should return a value.');
        Assert.areEqual(2, accsAfterUpsert.size());
    }
    
    @isTest
    private static void getExistingRecordsEventsTest(){
        List<String> fieldNames = new List<String>{'Advertising_Type__c'};
            Test.startTest();
        List<Advertising_Item__c> sObjectRecord = FlowCreateMultipleController.getExistingRecordsEvents('testFlowInt234','Advertising_Item__c',null,fieldNames, null);
        Test.stopTest();
        Assert.isTrue(sObjectRecord[0].Advertising_Type__c == 'Social Media Content');
    }
    
    @isTest
    private static void getTotalFieldSumTest(){
        FinServ__FinancialAccount__c finAcc = [SELECT Id FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1'];
        Test.startTest();
        Decimal totalPercent = FlowCreateMultipleController.getTotalFieldSum('Financial_Account__c', finAcc.Id, 'Initial_Funding_Percentage__c');
        FlowCreateMultipleController.FieldTotalAgrObj fldAgrObj = FlowCreateMultipleController.getTotalAmount('Order_Ticket__c','Financial_Account__c', finAcc.Id, 'Initial_Funding_Percentage__c');
        Test.stopTest();
        Assert.isTrue(totalPercent == 70.5);
        Assert.isNotNull(fldAgrObj);
        Assert.isTrue(fldAgrObj.totalSum == 70.5);
    }
    
    @isTest
    private static void getBondLadderTest() {
        Account acc = [Select Id from account where LastName = 'Account' LIMIT 1];
        FinServ__FinancialAccount__c finAcc = new FinServ__FinancialAccount__c(Name = 'Test FA', FinServ__PrimaryOwner__c = acc.Id);
        insert finAcc;
        Order_Ticket__c ot = new Order_Ticket__c(Financial_Account__c = finAcc.Id);
        insert ot;
        Test.startTest();
        Boolean bondLadder = FlowCreateMultipleController.getBondLadder('Financial_Account__c', finAcc.Id);
        Test.stopTest();
        System.assertEquals(null, bondLadder, 'Bond Ladder should be null');
    }
    
    /*@isTest
    private static void getTotalFieldSumBLSTCMTest(){
        FinServ__FinancialAccount__c finAcc = [SELECT Id FROM FinServ__FinancialAccount__c WHERE Name = 'Test FA1'];
        Test.startTest();
        FlowCreateMultipleController.SumObj sumObj = FlowCreateMultipleController.getTotalFieldSumBLSTCM('Financial_Account__c', finAcc.Id);
        Test.stopTest();
        Assert.isTrue(sumObj.result == 70.5);
        
    }*/
    /*@isTest
    private static void getExistingRecordsForFARPsTest(){
        Account acct = [Select Id From Account];
        Product__c prod = new Product__c(Name = 'Test Product');
        Insert prod;
        List<Wizard_Financial_Account__c> wFAList = new List<Wizard_Financial_Account__c>();
        wFAList.add(new Wizard_Financial_Account__c(Name ='Test 1 Wizard Financial Account',Primary_Owner__c=acct.Id ));
        wFAList.add(new Wizard_Financial_Account__c(Name ='Test 2 Wizard Financial Account',Primary_Owner__c=acct.Id));
        Insert wFAList;
        List<Financial_Account_Related_Product__c> farpList = new List<Financial_Account_Related_Product__c>();
        farpList.add(new Financial_Account_Related_Product__c(Product__c =prod.Id, Wizard_Financial_Account__c =wFAList[0].Id,Flow_Interview_Id__c='Test 123'));
        farpList.add(new Financial_Account_Related_Product__c(Product__c =prod.Id, Wizard_Financial_Account__c =wFAList[1].Id,Flow_Interview_Id__c='Test 123'));
        Insert farpList;
        String flowInterviewId ='Test 123';
        String flowInterviewFieldName = 'Flow_Interview_Id__c';
        String sobjectName = 'Financial_Account_Related_Product__c';
        String wFAFieldName = 'Wizard_Financial_Account__c';
        List<String> sObjectFields = new List<String>{'Product_Name__c', 'Amount__c'};
        List<Id> wFAIds = new List<Id>{wFAList[0].Id, wFAList[1].Id};
        Test.startTest();
        List<SObject> lstRecords = FlowCreateMultipleController.getExistingRecordsForFARPs(flowInterviewId,sobjectName,flowInterviewFieldName,sObjectFields,null,wFAIds,wFAFieldName);
        Test.stopTest();
        Assert.areEqual(2, lstRecords.size());
    }
    @isTest
    private static void  getSTCMTest() {
        Account acc = [Select Id from account where LastName = 'Account' LIMIT 1];
        FinServ__FinancialAccount__c finAcc = new FinServ__FinancialAccount__c(Name = 'Test FA', FinServ__PrimaryOwner__c = acc.Id);
        insert finAcc;
        Order_Ticket__c ot = new Order_Ticket__c(Financial_Account__c = finAcc.Id);
        insert ot;
        Test.startTest();
        Boolean stcm = FlowCreateMultipleController.getSTCM('Financial_Account__c', finAcc.Id);
        Test.stopTest();
        Assert.areEqual(null, stcm);
    }
    
    @isTest
    private static void updateAlloc(){
        Allocation__c alloc = [SELECT Id, Financial_Advisor_Team__c FROM Allocation__c LIMIT 1];
        Financial_Advisor_Team__c faTeam = [SELECT Id FROM Financial_Advisor_Team__c WHERE Id !=: alloc.Financial_Advisor_Team__c LIMIT 1];
        alloc.Financial_Advisor_Team__c = faTeam.Id;
        update alloc;
        delete alloc;
        undelete alloc;
    }*/
    
    
}