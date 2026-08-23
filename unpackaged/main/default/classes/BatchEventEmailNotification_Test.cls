@isTest
public class BatchEventEmailNotification_Test {
    
    @testSetup
    public static void setup(){
        User usr = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
            FirstName = 'Test',
            LastName = 'User',
            Email = 'test@email01.com',
            Username = 'user@test.com' + System.currentTimeMillis(),
            CompanyName = 'TEST',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US'
        );
        insert usr;
        
        System.runAs(usr){
            Advertising_Item__c adItem = new Advertising_Item__c(Name = 'Test Advertisement', Event_Type__c = 'Accredited Investor Association',
                                                                 Date_of_Event__c = Date.today().addDays(-1));
            insert adItem;
        }
    }
    
    @isTest
    public static void testBatch(){
        Test.startTest();
        BatchEventEmailNotification batch = new BatchEventEmailNotification();
        String sch = '0 0 2 * * ?'; 
        String jobId = System.schedule('Test Batch', sch, batch); 
        Test.stopTest();
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, NextFireTime
                          FROM CronTrigger WHERE id = :jobId];
        Assert.isNotNull(ct);
        Assert.areEqual(sch, ct.CronExpression);
    }
}