@isTest
public class BatchUpdateAMLValidOnAccount_Test {

    @testSetup
    public static void setup(){
        List<Account> accts = new List<Account>();
        accts.add(new Account(Name = 'Test Account 1', AML_Expiration_Date__c = Date.today().addDays(-1), AML_Valid__c = true));
        accts.add(new Account(Name = 'Test Account 2', AML_Expiration_Date__c = Date.today().addDays(1), AML_Valid__c = true));
        accts.add(new Account(Name = 'Test Account 3', AML_Expiration_Date__c = Date.today().addDays(-5), AML_Valid__c = false));
        accts.add(new Account(Name = 'Test Account 4', AML_Expiration_Date__c = Date.today(), AML_Valid__c = true));      
        insert accts;
    }
    
    @isTest
    public static void testBatch(){
        Test.startTest();
        Database.executeBatch(new BatchUpdateAMLValidOnAccount());
        Test.stopTest();
        List<Account> acctsWithExpiredAML = [SELECT Id, Name, AML_Expiration_Date__c, AML_Valid__c 
                                             FROM Account WHERE AML_Valid__c = false];
        Assert.isTrue(acctsWithExpiredAML.size() == 2);
    }
}