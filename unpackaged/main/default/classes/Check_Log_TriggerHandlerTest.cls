@isTest
public class Check_Log_TriggerHandlerTest {
    
    /*@testSetup
    public static void setup(){
        String paRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
        Account acc = new Account(FirstName = 'Test', 
                                  LastName = 'Person Account', 
                                  PersonEmail = 'test@test1.com', 
                                  RecordTypeId = paRecTypeId);
        insert acc;
        List<Financial_Advisor_Team__c> fatList = new List<Financial_Advisor_Team__c>();
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test Financial Advisor Team'));
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test Financial Advisor Team2'));
        insert fatList;
        
        FinServ__FinancialAccount__c finAcc = new FinServ__FinancialAccount__c(Name = 'Test Financial Account', 
                                                                               FinServ__PrimaryOwner__c = acc.Id);
        insert finAcc;
    }
    
    @isTest
    public static void test_setClientAndFinAdvisor(){
        FinServ__FinancialAccount__c finAcc = [SELECT Id, FinServ__PrimaryOwner__c, Financial_Advisor_Team__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test Financial Account' LIMIT 1];
        List<Check_Log__c> chkLogs = new List<Check_Log__c>();
        chkLogs.add(new Check_Log__c(Financial_Account__c = finAcc.Id, Status__c = 'Received'));
        chkLogs.add(new Check_Log__c(Status__c = 'Received'));
        Test.startTest();
        insert chkLogs;
        Test.stopTest();
        List<Check_Log__c> chkLogsAfterInsert = [SELECT Id, Name, Financial_Account__c, Client__c, Financial_Advisor_Team__c
                                                 FROM Check_Log__c ORDER BY Financial_Account__c NULLS LAST];
        Assert.areEqual(chkLogsAfterInsert[0].Client__c, finAcc.FinServ__PrimaryOwner__c);
        Assert.areEqual(chkLogsAfterInsert[0].Financial_Advisor_Team__c, finAcc.Financial_Advisor_Team__c);
        Assert.isNull(chkLogsAfterInsert[1].Client__c);
        Assert.isNull(chkLogsAfterInsert[1].Financial_Advisor_Team__c);
    }
    
    @isTest
    public static void test_coverUpdateDeleteUnDelete() {
        FinServ__FinancialAccount__c finAcc = [SELECT Id, FinServ__PrimaryOwner__c, Financial_Advisor_Team__c FROM FinServ__FinancialAccount__c WHERE Name = 'Test Financial Account' LIMIT 1];
        List<Check_Log__c> chkLogs = new List<Check_Log__c>();
        chkLogs.add(new Check_Log__c(Financial_Account__c = finAcc.Id, Status__c = 'Received'));
        chkLogs.add(new Check_Log__c(Status__c = 'Received'));
        insert chkLogs;
        chkLogs[0].Status__c = 'Sent';
        Test.startTest();
        update chkLogs[0];
        delete chkLogs[0]; 
        undelete chkLogs[0];
        Test.stopTest();
        Assert.isNotNull([SELECT Id 
                          FROM Check_Log__c 
                          WHERE Id = :chkLogs[0].Id 
                          AND IsDeleted = false]);
    }
    
    @isTest
    public static void test_setClientAndFinAdvisor_WithNullFA(){
        Check_Log__c chkLog = new Check_Log__c(Status__c = 'Received');
        Test.startTest();
        insert chkLog;
        Test.stopTest();
        Check_Log__c chkLogAfterInsert = [SELECT Id, Name, Financial_Account__c, Client__c, Financial_Advisor_Team__c
                                          FROM Check_Log__c WHERE Id = :chkLog.Id];
        Assert.isNull(chkLogAfterInsert.Client__c);
        Assert.isNull(chkLogAfterInsert.Financial_Advisor_Team__c);
    }
    
    @isTest
    public static void test_createShareRecord(){
        List<Financial_Advisor_Team__c> fatList = [SELECT Id FROM Financial_Advisor_Team__c];
        Check_Log__c chkLog = new Check_Log__c(Status__c = 'Received',Financial_Advisor_Team__c=fatList[0].Id);
        Test.startTest();
        insert chkLog;
        chkLog.Financial_Advisor_Team__c = fatList[1].Id; 
        Update chkLog;
        Test.stopTest();
        Assert.areEqual(3,[SELECT id FROM Check_Log__Share].Size());
    }
    
    @isTest
    public static void test_SetFinancialAccount(){
        Account acc = new Account(FirstName = 'FirstName',LastName = 'LastName');
        insert acc;
        Wizard_Financial_Account__c wfa = new Wizard_Financial_Account__c(Name ='Test Account',Do_Not_Create_FinAcct__c=true);
        insert wfa;
        FinServ__FinancialAccount__c fa = new FinServ__FinancialAccount__c(FinServ__PrimaryOwner__c = acc.Id,Name ='Test Account',FinServ__FinancialAccountNumber__c = '1234',Wizard_Financial_Account__c = wfa.Id);
        insert fa;        
        
        Check_Log__c checkLog1 = new Check_Log__c(
            Wizard_Financial_Account__c = wfa.Id,
            Financial_Account__c = null,
            Status__c = 'Received'
        );
        Check_Log__c checkLog2 = new Check_Log__c(
            Wizard_Financial_Account__c = wfa.Id,
            Financial_Account__c = null,
            Status__c = 'Received'
        );
    
        //Call the method to set Financial Account
        Test.startTest();
        insert new List<Check_Log__c>{ checkLog1, checkLog2 };
        Test.stopTest();
        //Retrieve the Check_Log__c records for testing (to ensure they have no Financial_Account__c set)
        List<Check_Log__c> checkLogs = [SELECT Id, Wizard_Financial_Account__c, Financial_Account__c FROM Check_Log__c];
        //Verify the Financial_Account__c field is set correctly
        for (Check_Log__c checkLog : checkLogs) {
            System.assertNotEquals(null, checkLog.Financial_Account__c, 'Financial_Account__c should be set');
            System.assertEquals(fa.Id, checkLog.Financial_Account__c, 'Financial_Account__c should match the related Financial Account ID');
        }
    }*/
}