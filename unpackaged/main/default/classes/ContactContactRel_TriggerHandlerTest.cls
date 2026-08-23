@isTest
public class ContactContactRel_TriggerHandlerTest {
    @testSetup
    public static void setup(){
        Id roleRecTypeId = Schema.sObjectType.FinServ__ReciprocalRole__c.getRecordTypeInfosByName().get('Contact Role').getRecordTypeId();
        
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
            IsActive = true
        ));
        usrList.add(new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name='Wizard Only'].Id,
            LastName = 'testUser2',
            Email = 'test@email02.com',
            Username = 'user3@test.com'+System.currentTimeMillis(),
            CompanyName = 'Test',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true 
        ));
        insert usrList;
        
        System.runAs(usrList[0]){
            FinServ__ReciprocalRole__c role = new FinServ__ReciprocalRole__c(Name = 'Test Role', FinServ__InverseRole__c = 'Trustee', RecordTypeId = roleRecTypeId);
            insert role;
        }
        
        System.runAs(usrList[1]){
            List<Account> contacts = new List<Account>();
            contacts.add(new Account(LastName = 'Test Contact1', PersonEmail = 'test.test@dfpg.com')) ;
            contacts.add(new Account(LastName = 'Test Contact2', PersonEmail = 'test2.test@dfpg.com')) ;
            insert contacts;
        }
    }
    
    
    @isTest
    private static void createAndUpdateFinContactRel_Test(){
        FinServ__ReciprocalRole__c role = [SELECT Id, Name FROM FinServ__ReciprocalRole__c
                                           WHERE Name = 'Test Role' LIMIT 1];
        User usr = [SELECT Id FROM User WHERE LastName = 'testUser2' LIMIT 1];
        List<Account> testContacts = [SELECT Id, Name, PersonContactId FROM Account WHERE Name LIKE 'Test Contact%' LIMIT 2];
        Contact_Contact_Relationship__c ccr = new Contact_Contact_Relationship__c(Active__c = true,
                                                                                  Contact__c = testContacts[0].PersonContactId,
                                                                                  Related_Contact__c = testContacts[1].PersonContactId,
                                                                                  Related_Role_ID__c = role.Id,
                                                                                  Percentage_of_Ownership__c = 10);
        Test.startTest(); 
        System.runAs(usr){
            insert ccr;
        }
        Test.stopTest();

        List<FinServ__ContactContactRelation__c> finservContactContactRel = [SELECT Id, Name FROM
                                                                             FinServ__ContactContactRelation__c WHERE Contact_Contact_Relationship__c = :ccr.Id];
        Assert.areEqual(2, finservContactContactRel.size());
    }
    
    @isTest
    private static void updateFinContactRel_Test(){
        FinServ__ReciprocalRole__c role = [SELECT Id, Name FROM FinServ__ReciprocalRole__c
                                           WHERE Name = 'Test Role' LIMIT 1];
        User usr = [SELECT Id FROM User WHERE LastName = 'testUser2' LIMIT 1];
        List<Account> testContacts = [SELECT Id, Name, PersonContactId FROM Account WHERE Name LIKE 'Test Contact%' LIMIT 2];
        Contact_Contact_Relationship__c ccr = new Contact_Contact_Relationship__c(Active__c = true,
                                                                                  Contact__c = testContacts[0].PersonContactId,
                                                                                  Related_Contact__c = testContacts[1].PersonContactId,
                                                                                  Related_Role_ID__c = role.Id,
                                                                                  Percentage_of_Ownership__c = 10);
        System.runAs(usr){
            Test.startTest();
            insert ccr;
            Test.stopTest();
        }
        ccr.Percentage_of_Ownership__c = 20;
		update ccr;
        List<FinServ__ContactContactRelation__c> finservContactContactRel = [SELECT Id, Name FROM
                                                                             FinServ__ContactContactRelation__c WHERE Contact_Contact_Relationship__c = :ccr.Id];
        Assert.areEqual(2, finservContactContactRel.size());
        //for coverage
        delete ccr;
        undelete ccr;
    }
}