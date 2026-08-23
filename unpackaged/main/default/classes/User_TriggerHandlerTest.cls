@isTest
private class User_TriggerHandlerTest {
    
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
    }
    
    @isTest
    private static void positiveDataInsert() {
        
        Financial_Advisor_Team__c record = new Financial_Advisor_Team__c(Name = 'Test FAT');
        insert record;
        Financial_Advisor_Team__c record2 = new Financial_Advisor_Team__c(Name = 'Default Team');
        insert record2;

        Financial_Advisor_Team_Member__c fatMemberRec = new Financial_Advisor_Team_Member__c(Active__c = true, Financial_Advisor_Team__c = record.Id,
                                                                 Employment_Status__c = 'W2 Employee', User_SSN__c = '12345');
        insert fatMemberRec;
        
        Profile pf = [SELECT Id FROM Profile WHERE Name = 'System Administrator'];
        String orgId = UserInfo.getOrganizationId();
        
        Test.startTest();
        User testUser = new User(Firstname = 'Test FirstName', lastName = 'Test LastName', Email = 'TestFirstName' + '@test' + orgId + '.org',
                                 Username = 'TestFirstName' + '@test' + orgId + '.org', EmailEncodingKey = 'ISO-8859-1',
                                 Alias = 'Test', TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
                                 LanguageLocaleKey = 'en_US', ProfileId = pf.Id, Advisor_SSN__c = '12345');
        insert testUser;
        Test.stopTest();
        
        List<Financial_Advisor_Team_Member__c> fatmUpdate = [SELECT Id, User__c, Name, User_SSN__c FROM Financial_Advisor_Team_Member__c];
        Assert.areEqual(testUser.Id, fatmUpdate[0].User__c, 'User field should be updated according to User SSN Matching');
        update testUser;
    }
    
    @isTest
    private static void testAfterUpdate(){
        Financial_Advisor_Team__c record = new Financial_Advisor_Team__c(Name = 'Test FAT');
        insert record;
        Financial_Advisor_Team__c record2 = new Financial_Advisor_Team__c(Name = 'Default Team');
        insert record2;
        
        Profile pf = [SELECT Id FROM Profile WHERE Name = 'System Administrator'];
        User user=new User(
            ProfileId=pf.Id,
            LastName='testuser',
            Email='test@email01.com',
            Username='user@test.com'+system.currentTimeMillis(),
            Title='title',
            CompanyName='Test',
            Alias='alias',
            TimeZoneSidKey='America/Los_Angeles',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            IsActive=true,
            Registered_States__c='test1,test2'
            
        );
        insert user;
        Financial_Advisor_Team_Member__c fatMemberRec = new Financial_Advisor_Team_Member__c(Active__c = true, Financial_Advisor_Team__c = record.Id, User__c=user.Id, Employment_Status__c = 'W2 Employee');
        insert fatMemberRec;
        Test.startTest();
        user.Registered_States__c='test1,test2,test3';
        update user;
        Test.stopTest();
        Assert.areEqual('test1,test2,test3', [SELECT Id, Registered_States__c FROM Financial_Advisor_Team_Member__c][0].Registered_States__c);      
    }
}