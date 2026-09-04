@isTest
public class AccountContactRelationTriggerHandlerTest {
    @testSetup
    static void setupData() {
         List<Financial_Advisor_Team__c> fatList = new List<Financial_Advisor_Team__c>();
            fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 1'));
            fatList.add(new Financial_Advisor_Team__c(Name = 'Test FAT 2'));
            insert fatList;
        // Create Accounts
        Account account1 = new Account(Name = 'Account 1', Financial_Advisor_Team__c = fatList[0].Id, Classification__c = 'Unclassified');
        Account account2 = new Account(Name = 'Account 2', Classification__c = 'Unclassified');
        insert new List<Account>{account1, account2};
        
        // Create Contacts
        Contact contact1 = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = account2.Id);
        Contact contact2 = new Contact(FirstName = 'Jane', LastName = 'Smith', AccountId = account1.Id);
        insert new List<Contact>{contact1, contact2};
          
    }

    @isTest
    static void testIsAfterInsert() {
        // Retrieve test data
        Account account1 = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Name = 'Account 1' LIMIT 1];
        Account account2 = [SELECT Id FROM Account WHERE Name = 'Account 2' LIMIT 1];
        Contact contact1 = [SELECT Id, AccountId FROM Contact WHERE FirstName = 'John' AND LastName = 'Doe' LIMIT 1];
        Contact contact2 = [SELECT Id FROM Contact WHERE FirstName = 'Jane' AND LastName = 'Smith' LIMIT 1];
        
        // Create AccountContactRelation records
        AccountContactRelation acr1 = new AccountContactRelation(AccountId = account1.Id, ContactId = contact1.Id);
        AccountContactRelation acr2 = new AccountContactRelation(AccountId = account2.Id, ContactId = contact2.Id);
        
        Test.startTest();
        insert new List<AccountContactRelation>{acr1, acr2};
        Test.stopTest();
        
        // Validate the results
        Account updatedContactAccount = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Id = :contact1.AccountId LIMIT 1];
        System.assertEquals(account1.Financial_Advisor_Team__c, updatedContactAccount.Financial_Advisor_Team__c, 
                            'The financial advisor team should be updated on the contact\'s account.');
        update acr1;
        delete acr1;
    }
    
    @isTest
    private static void getHouseholdMembersTest(){
        Account account1 = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Name = 'Account 1' LIMIT 1];
        List<AccountContactRelation> acrList = SelectPrimaryAndJointController.getHouseholdMembers(account1.Id);
        System.AssertEquals(1, acrList.size());
    }
    
    @isTest
    private static void getHouseholdMembersMinusPrimaryTest(){
        Account account1 = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Name = 'Account 1' LIMIT 1];
        Contact contact1 = [SELECT Id, AccountId FROM Contact WHERE FirstName = 'John' AND LastName = 'Doe' LIMIT 1];
        List<AccountContactRelation> acrList = SelectPrimaryAndJointController.getHouseholdMembersMinusPrimary(account1.Id, contact1.AccountId);
        //System.AssertEquals(0, acrList.size());
    }
}