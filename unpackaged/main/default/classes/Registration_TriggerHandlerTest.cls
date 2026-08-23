@isTest
public class Registration_TriggerHandlerTest {
    @testSetup
    private static void testData(){
        List<User> usrList = new List<User>();
        usrList.add(new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name='System Administrator'].Id,
            LastName = 'testUser',
            Email = 'test@email01.com',
            Username = 'user@test.com'+System.currentTimeMillis(),
            CompanyName = 'Test',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true, 
            CRD__c =  '23456'
        ));
        usrList.add(new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name='System Administrator'].Id,
            LastName = 'testUser2',
            Email = 'test2@email01.com',
            Username = 'user2@test.com'+System.currentTimeMillis(),
            CompanyName = 'Test',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true, 
            CRD__c =  '54321'
        ));
        insert usrList;
        
        List<Financial_Advisor_Team__c> fatList = new List<Financial_Advisor_Team__c>();
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 1'));
        fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 2'));
        //Due to updateRepCode method in FATMember_TriggerHandler
        fatList.add(new Financial_Advisor_Team__c(Name = 'Default Team'));
        insert fatList;
        
        List<Financial_Advisor_Team_Member__c> fatMemberList = new List<Financial_Advisor_Team_Member__c>();
        fatMemberList.add(new Financial_Advisor_Team_Member__c(Financial_Advisor_Team__c = fatList[1].Id,
                                                               User__c = usrList[0].Id, Active__c = true, Role__c = 'Financial Advisor'));
        fatMemberList.add(new Financial_Advisor_Team_Member__c(Financial_Advisor_Team__c = fatList[1].Id,
                                                               User__c = usrList[1].Id, Active__c = true, Role__c = 'Financial Advisor')); 
        insert fatMemberList;
        
        Registration__c reg = new Registration__c(CRD__c = '23456', State__c = 'California');
        insert reg;
    }

    @isTest
    private static void test_OnInsert(){
        List<Registration__c> regs = new List<Registration__c>();
        regs.add(new Registration__c(CRD__c = '23456', State__c = 'California'));
        regs.add(new Registration__c(CRD__c = '54321', State__c = 'California'));
        regs.add(new Registration__c(CRD__c = '54321', State__c = 'Alabama'));
        Test.startTest();
        Database.insert(regs, false);
        Test.stopTest();
        List<Registration__c> regsAfterInsert = [SELECT Id, CRD__c, State__c, End_Date__c, Active__c,
                                                 User__c, User__r.Name FROM Registration__c ORDER BY CRD__c, State__c];
        List<Financial_Advisor_Team__c> fatLstAfterUpdate = [SELECT Id, Name, Registered_States__c FROM Financial_Advisor_Team__c
                                                             ORDER BY Name];
        Assert.areEqual(3, regsAfterInsert.size());
        Assert.areEqual('testUser2', regsAfterInsert[1].User__r.Name);
        Assert.areEqual('California', fatLstAfterUpdate[2].Registered_States__c);
        //for coverage
        regsAfterInsert[0].End_Date__c = Date.today().addDays(2);
        update regsAfterInsert[0];
        delete regsAfterInsert[0];
        undelete regsAfterInsert[0];
    }
}