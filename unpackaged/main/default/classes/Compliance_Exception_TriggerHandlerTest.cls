@isTest
private class Compliance_Exception_TriggerHandlerTest {
    
    @testSetup
    static void setupData() {
        ContentVersion cv = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Sample Data'),
            Flow_Interview_Id__c = 'FLOW123'
        );
        insert cv;
    }
    
    @isTest
    static void testCDLCreatedOnInsert() {
        // Insert Compliance Exception with matching Flow Interview Id
        Compliance_Exception__c ce = new Compliance_Exception__c(
            Name = 'Test Compliance Exception',
            Flow_Interview_Id__c = 'FLOW123'
        );
        
        Test.startTest();
        insert ce; 
        Test.stopTest();
        
        List<ContentDocumentLink> cdls = [SELECT Id, LinkedEntityId, ContentDocumentId
                                            FROM ContentDocumentLink
                                            WHERE LinkedEntityId = :ce.Id
                                         ];
        
        System.assert(!cdls.isEmpty(), 'ContentDocumentLink should have been created');
        System.assertEquals(ce.Id, cdls[0].LinkedEntityId, 'CDL should link to Compliance Exception');
    }
    
    @isTest
    static void testNoCDLWhenNoFlowInterviewId() {
        // Insert Compliance Exception without Flow Interview Id
        Compliance_Exception__c ce = new Compliance_Exception__c(
            Name = 'No Flow Id Exception'
        );
        
        Test.startTest();
        insert ce; 
        Test.stopTest();
        
        List<ContentDocumentLink> cdls = [SELECT Id 
                                          FROM ContentDocumentLink 
                                          WHERE LinkedEntityId = :ce.Id
                                         ];
        System.assertEquals(0, cdls.size(), 'No CDL should be created if Flow Interview Id is missing');
    }
    
    @isTest
    static void testHandlerOnUpdate() {
        // Insert Compliance Exception with matching Flow Interview Id
        Compliance_Exception__c ce = new Compliance_Exception__c(
            Name = 'Test Compliance Exception',
            Flow_Interview_Id__c = 'FLOW123'
        );
        
        insert ce; 
        
        ce.Name = 'Test Compliance Exception 1';
        Test.startTest();
        update ce;
        Test.stopTest();
        
        System.assertEquals([SELECT Id, Name FROM Compliance_Exception__c WHERE Id = :ce.Id LIMIT 1].Name, 'Test Compliance Exception 1', 'The exception name must have updated');
    }

    @isTest
    static void testHandlerOnDelete() {
        // Insert Compliance Exception with matching Flow Interview Id
        Compliance_Exception__c ce = new Compliance_Exception__c(
            Name = 'Test Compliance Exception',
            Flow_Interview_Id__c = 'FLOW123'
        );
        
        insert ce; 
        
        Test.startTest();
        delete ce;
        Test.stopTest();
        
        System.assertEquals([SELECT COUNT() FROM Compliance_Exception__c WHERE Id = :ce.Id], 0, 'the exception must be deleted');
    }

    @isTest
    static void testHandlerOnUnDelete() {
        // Insert Compliance Exception with matching Flow Interview Id
        Compliance_Exception__c ce = new Compliance_Exception__c(
            Name = 'Test Compliance Exception',
            Flow_Interview_Id__c = 'FLOW123'
        );
        insert ce; 
        delete ce;
        Test.startTest();
        undelete ce;
        Test.stopTest();
        
        System.assertEquals([SELECT COUNT() FROM Compliance_Exception__c WHERE Id = :ce.Id], 1, 'the exception must be restored again');

    }
    
}