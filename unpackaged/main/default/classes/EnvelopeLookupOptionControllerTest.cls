@IsTest
public class EnvelopeLookupOptionControllerTest {
    
    @IsTest
    static void testSubmitEnvelope() {
        
        // Create Envelope
        Envelope__c envelope = new Envelope__c(
            Status__c = 'In Progress'
        );
        insert envelope;
        
        // Create Household Account
        Account household = new Account(
            Name = 'Test Household',
            recordTypeId = getHouseholdRecordTypeId()
        );
        insert household;
        
        Test.startTest();
        
        Map<String, List<FieldDetailController.PicklistOption>> result =  EnvelopeLookupOptionController.getLookupOptions(envelope.Id,household.Id);
        
        Test.stopTest();
        
        System.assertNotEquals(
            null,
            result,
            'Result Should not null'
        );
    }
    
    private static Id getHouseholdRecordTypeId() {
        
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND developername = 'Household'
            LIMIT 1
        ].Id;
    }    
}