@isTest
public class Required_Documents_TriggerHandlerTest {
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
        String householdRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Household').getRecordTypeId();
        String paRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
        List<Account> accList = new List<Account>();
        accList.add(new Account(Name = 'Test Household Account', RecordTypeId = householdRecTypeId));
        accList.add(new Account(FirstName = 'Test', LastName = 'Person Account 1', PersonEmail = 'test@test1.com', RecordTypeId = paRecTypeId));
        insert accList;
        
        Account personAccount =  [SELECT PersonContactId FROM Account WHERE LastName = 'Person Account 1' LIMIT 1];
        List<AccountContactRelation> acrs = new List<AccountContactRelation>();
        acrs.add(new AccountContactRelation(ContactId = personAccount.PersonContactId, AccountId = accList[0].Id, IsActive = true, Roles = 'Client', FinServ__Primary__c = true));
		insert acrs;
        
        Case testCase = new Case(AccountId = accList[0].Id, Status = 'New', Required_Documents__c = 'Test Document');
        insert testCase;
        
        Opportunity opp;
        System.runAs(testuser){
            opp = new Opportunity(Name = 'Test Opportunity', AccountId = accList[0].Id, 
                                              StageName = 'Qualification', CloseDate = Date.today());
            insert opp;}
        
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
        insert docs;
        
        // Create test Required_Documents__c record
        Required_Documents__c testDoc = new Required_Documents__c(
            Name = 'Test Document',
            Status__c = 'Draft',
            Household__c = accList[0].Id
        );
        insert testDoc;
    }
    
    @isTest
    public static void testUpdateRelatedCases(){
        Required_Documents__c reqDoc = [SELECT Id, Status__c, Docusign_Envelope__c FROM Required_Documents__c 
                                        WHERE Name = 'Test Document' LIMIT 1];
        
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Test Household Account' LIMIT 1];
        Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];
        // Mock the DocuSign eSignature API
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        Test.startTest();
        User testDSUser = dfsle.UserMock.createDocuSignAdministrator();
        // Run the test as a DocuSign Sender. This is required by dfsle.EnvelopeService.sendEnvelope
        System.runAs(testDSUser) {
            DocuSign_OppEnvelopes.sendOppEnvelopes(opp.Id);
        }   
        Test.stopTest();
        List<dfsle__Envelope__c> envs = [SELECT Id FROM dfsle__Envelope__c];
        System.debug(envs);

        reqDoc.DocuSign_Envelope__c = envs[0].Id;
    	reqDoc.Status__c = 'Signed';
    	update reqDoc;
        
    	List<Case> updatedCases = [SELECT Id, Documents_Ready__c FROM Case];
        Assert.areEqual(1, updatedCases.size());
        Assert.areEqual(true, updatedCases[0].Documents_Ready__c);
        
        delete reqDoc;
    }
}