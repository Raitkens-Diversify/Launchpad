@isTest
public class DocuSign_OppEnvelopesTest {
    @testSetup
    public static void testData(){
        //create user
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User testUser = new User(LastName = 'Test User', 
                                 ProfileId = adminProfileId, 
                                 Username = System.now().millisecond() + 'testuser@test.com', 
                                 Email = 'testinguser5309@testing.invalid', 
                                 Alias = 'testuser',
                                 LanguageLocaleKey='en_US',
                                 LocaleSidKey='en_US',
                                 TimeZoneSidKey='America/Chicago',
                                 EmailEncodingKey = 'UTF-8');
        insert testUser;
        System.runAs(testuser){
            
            String householdRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Household').getRecordTypeId();
            String paRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
            List<Account> accList = new List<Account>();
            accList.add(new Account(Name = 'Test Account', RecordTypeId = householdRecTypeId, Type ='Other', Classification__c = 'Vendor;'));
            accList.add(new Account(FirstName = 'Test', LastName = 'Person Account 1', PersonEmail = 'test@test1.com', RecordTypeId = paRecTypeId, Type ='Other', Classification__c = 'Vendor;'));
            accList.add(new Account(FirstName = 'Test', LastName = 'Person Account 2', PersonEmail = 'test@test2.com', RecordTypeId = paRecTypeId, Type ='Other', Classification__c = 'Vendor;'));
            insert accList;
            
            List<Account> personAccounts =  [SELECT PersonContactId FROM Account WHERE LastName LIKE 'Person Account%'];
            List<AccountContactRelation> acrs = new List<AccountContactRelation>();
            acrs.add(new AccountContactRelation(ContactId = personAccounts[0].PersonContactId, AccountId = accList[0].Id, IsActive = true, Roles = 'Client'));
            acrs.add(new AccountContactRelation(ContactId = personAccounts[1].PersonContactId, AccountId = accList[0].Id, IsActive = true, Roles = 'Client'));
            insert acrs;
            
            Opportunity opp;
            opp = new Opportunity(Name = 'Test Opportunity', AccountId = accList[1].Id, 
                                  StageName = 'Qualification', CloseDate = Date.today());
            insert opp;
            
            List<dfsle__EnvelopeConfiguration__c> envelopConfig = new List<dfsle__EnvelopeConfiguration__c>();
            envelopConfig.add(new dfsle__EnvelopeConfiguration__c(
                Name = 'DocusignConfig',
                dfsle__DocuSignId__c = String.valueOf(dfsle.UUID.randomUUID())
            ));
            insert envelopConfig;
            
            List<DocuSign_Document__c> docs = new List<DocuSign_Document__c>();
            docs.add(new DocuSign_Document__c(
                Opportunity__c=opp.Id,
                Template_Type__c = envelopConfig[0].Id,
                Send_to_Primary_Owner__c = true
            ));
            
            
            docs.add(new DocuSign_Document__c(
                Opportunity__c=opp.Id,
                Template_Type__c = envelopConfig[0].Id,
                Send_to_Joint_Owner__c = true
            ));
            
            docs.add(new DocuSign_Document__c(
                Opportunity__c = opp.Id,
                Template_Type__c = envelopConfig[0].Id,
                Send_to_Primary_Owner__c = true,
                Send_to_Joint_Owner__c = true
            ));        
            
            insert docs;
        }
    }
    
    @isTest
    public static void test_sendOppEnvelopes(){
        Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];
        // Mock the DocuSign eSignature API
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        Test.startTest();
        User testUser = [SELECT Id FROM User  WHERE Email='testinguser5309@testing.invalid'];
        User testDSUser = new User();
        System.runAs(testUser) {
                 testDSUser = dfsle.UserMock.createDocuSignAdministrator();
            }
        // Run the test as a DocuSign Sender. This is required by dfsle.EnvelopeService.sendEnvelope
        System.runAs(testDSUser) {
            DocuSign_OppEnvelopes.sendOppEnvelopes(opp.Id);
        }
        Test.stopTest();
        
        List<dfsle__Envelope__c> envs = [SELECT Id FROM dfsle__Envelope__c];
        System.Assert.isNotNull(envs);
    }
}