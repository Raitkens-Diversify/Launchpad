@isTest
public class FinServ_ContactContact_TriggerTest {
    @testSetup
    static void setupTestData() {
        // Create a Public Group
        Group publicGroup = new Group(Name = 'Test Public Group', Type = 'Regular');
        insert publicGroup;
        
        // Create Financial Advisor Team
        Financial_Advisor_Team__c advisorTeam = new Financial_Advisor_Team__c(
            Name = 'Test Advisor Team',
            Public_Group_ID__c = publicGroup.Id
        );
        insert advisorTeam;
        
        // Create Accounts
        Account acc1 = new Account(Name = 'Test Account 1', Classification__c = 'Unclassified');
        insert acc1;
        Account acc2 = new Account(Name = 'Test Account 2', Financial_Advisor_Team__c = advisorTeam.Id, Classification__c = 'Unclassified');
        insert acc2;
        
        // Create Related Contacts
        Contact contact1 = new Contact(LastName = 'Test Contact 1', AccountId = acc1.Id);
        Contact contact2 = new Contact(LastName = 'Test Contact 2', AccountId = acc2.Id);
        insert new List<Contact>{contact1, contact2};
        
        Id ccRoleRecordType = Schema.SObjectType.FinServ__ReciprocalRole__c.getRecordTypeInfosByName().get('Contact Role').getRecordTypeId();
        FinServ__ReciprocalRole__c rr1 = new FinServ__ReciprocalRole__c(Name = 'Test Role', FinServ__RelationshipType__C = 'Contact Contact Relation', FinServ__InverseRole__c = 'Inverse Role', RecordTypeId = ccRoleRecordType);
        insert rr1;
            
            // Create Contact Contact Relationship record
            FinServ__ContactContactRelation__c relation = new FinServ__ContactContactRelation__c(
                FinServ__Contact__c  = contact1.Id,
                FinServ__RelatedContact__c  = contact2.Id,
                FinServ__Role__c = rr1.Id
            );
        insert relation;
    }
    
    @isTest
    static void testAfterInsertSharing() {
        // Fetch the related Contact and Public Group ID
        FinServ__ContactContactRelation__c relation = [
            SELECT Id, FinServ__RelatedContact__r.Account.Financial_Advisor_Team__r.Public_Group_ID__c 
            FROM FinServ__ContactContactRelation__c LIMIT 1
        ];
        
        // Verify the sharing record was created
        List<FinServ__ContactContactRelation__Share> shares = [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel 
            FROM FinServ__ContactContactRelation__Share
            WHERE ParentId = :relation.Id 
            AND UserOrGroupId = :relation.FinServ__RelatedContact__r.Account.Financial_Advisor_Team__r.Public_Group_ID__c
        ];
        
        System.assertEquals(1, shares.size(), 'One sharing record should be created');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Access Level should be Read');
        delete relation;
        undelete relation;
    }
}