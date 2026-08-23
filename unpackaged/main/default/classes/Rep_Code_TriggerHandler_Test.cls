@isTest
public class Rep_Code_TriggerHandler_Test {    
    @testSetup
    private static void setup(){
        User usr = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name='System Administrator'].Id,
            FirstName = 'FirstName',
            LastName = 'LastName',
            Username = 'user@test.com' + System.currentTimeMillis(),
            Email = 'test@none.com',
            CompanyName = 'test',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true);
        insert usr;
        
        List<Financial_Advisor_Team_Member__c> fatmList = new List<Financial_Advisor_Team_Member__c>();
        Financial_Advisor_Team__c defaultTeam = new Financial_Advisor_Team__c(Name = 'Default Team');
        insert defaultTeam;
        
        Group grp = new Group(Name='Test Group');
        insert grp;
        
        System.runAs(usr){
            Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c();
            faTeam.Name = 'Test Fin Advisor Team';
            // faTeam.Public_Group_Id__c=grp.Id;
            insert faTeam;
            
            Id accRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
            Id hhRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Household').getRecordTypeId();
            List<Account> accList = new List<Account>();
            accList.add(new Account(FirstName = 'Primary', LastName = 'Owner', RecordTypeId = accRecTypeId, Financial_Advisor_Team__c = faTeam.Id));
            accList.add(new Account(FirstName = 'Joint', LastName = 'Owner', RecordTypeId = accRecTypeId, Financial_Advisor_Team__c = faTeam.Id));
            accList.add(new Account(Name = 'Test Household', RecordTypeId = hhRecTypeId, Financial_Advisor_Team__c = faTeam.Id));
            insert accList;
            
            Account person1 = [SELECT Id, PersonContactId FROM Account WHERE Id =: accList[0].Id];
            Account person2 = [SELECT Id, PersonContactId FROM Account WHERE Id =: accList[1].Id];
            List<AccountContactRelation> acrList = new List<AccountContactRelation>();
            acrList.add(new AccountContactRelation(AccountId = accList[2].Id, ContactId = person1.PersonContactId, FinServ__PrimaryGroup__c = true));
            acrList.add(new AccountContactRelation(AccountId = accList[2].Id, ContactId = person2.PersonContactId, FinServ__PrimaryGroup__c = true));
            insert acrList;
            
            DateTime now = DateTime.now();
            Event evt = new Event(WhatId = accList[2].Id, Subject = 'Test Event', DurationInMinutes = 60, ActivityDateTime = now, Financial_Advisor_Team__c = faTeam.Id);
            insert evt;
            
            
            
            Rep_Code__c repCode = new Rep_Code__c(Name = '123', Financial_Advisor_Team__c = faTeam.Id);
            insert repCode;
            
            FinServ__FinancialAccount__c finAccount = new FinServ__FinancialAccount__c();
            finAccount.Name = 'Test Fin Account';
            finAccount.FinServ__PrimaryOwner__c = accList[0].Id;
            finAccount.FinServ__JointOwner__c = accList[1].Id;
            finAccount.Financial_Advisor_Team__c = faTeam.Id;
            finAccount.Rep_Code_Lookup__c = repCode.Id;
            finAccount.FinServ__Household__c = accList[2].Id;
            insert finAccount;
            System.debug('finAcct Inserted: ' + finAccount);
            
        }
        
        Id fatId = [SELECT Id FROM Financial_Advisor_Team__c WHERE Name='Test Fin Advisor Team'][0].Id;
        
        
        Financial_Advisor_Team_Member__c fatmember = new Financial_Advisor_Team_Member__c();
        fatmember.Active__c = true;
        fatmember.Financial_Advisor_Team__c = fatId;
        fatmember.Role__c = 'Financial Advisor';
        fatmember.User__c = usr.Id;
        fatmList.add(fatmember);
        Financial_Advisor_Team_Member__c fatmember1 = new Financial_Advisor_Team_Member__c();
        fatmember1.Active__c = true;
        fatmember1.Financial_Advisor_Team__c = fatId;
        fatmember1.Role__c = 'Financial Advisor';
        fatmember1.User__c = UserInfo.getUserId();
        fatmList.add(fatmember1);
        insert fatmList;
        
    }
    
    @isTest
    private static void updateRepCodeTest(){
        Id faTeamId = [SELECT Id FROM Financial_Advisor_Team__c WHERE Name = 'Test Fin Advisor Team'][0].Id;
        Rep_Code__c repCode = [SELECT Id, Financial_Advisor_Team__c FROM Rep_Code__c LIMIT 1];
        Financial_Advisor_Team__c defaultTeam = [SELECT Id FROM Financial_Advisor_Team__c WHERE Name = 'Default Team' LIMIT 1];
        Test.startTest();
        repCode.Financial_Advisor_Team__c = defaultTeam.Id;
        update repCode;
        Test.stopTest();
        //System.assertEquals(UserInfo.getUserId(), [SELECT Id, OwnerId FROM FinServ__FinancialAccount__c][0].OwnerId);
        //System.assertEquals(UserInfo.getUserId(), [SELECT Id, OwnerId FROM Account][0].OwnerId);
        //for coverage
        //delete fatmember;
        //undelete fatmember;
    }
}