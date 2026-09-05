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
            recordTypeId = getHouseholdRecordTypeId(),
            Type = 'Prospect'
        );
        insert household;

        Test.startTest();

        Map<String, List<FieldDetailController.PicklistOption>> result =
            EnvelopeLookupOptionController.getLookupOptions(household.Id, envelope.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Result Should not null'
        );
    }

    @IsTest
    static void getLookupOptionsReturnsFinancialAccountsForHousehold() {
        Envelope__c envelope = new Envelope__c(Status__c = 'In Progress');
        insert envelope;

        Account household = new Account(
            Name = 'Lookup Options Household',
            recordTypeId = getHouseholdRecordTypeId(),
            Type = 'Prospect'
        );
        insert household;

        Financial_Account__c finAccount = new Financial_Account__c(
            Name = 'Lookup Financial Account',
            Household__c = household.Id
        );
        insert finAccount;

        Test.startTest();
        Map<String, List<FieldDetailController.PicklistOption>> result =
            EnvelopeLookupOptionController.getLookupOptions(household.Id, envelope.Id);
        Test.stopTest();

        String key = 'Case|AA_Account_Number_Wizard__c';
        System.assert(result.containsKey(key),
            'A household with an eligible Financial Account should populate this lookup source.');
        Boolean found = false;
        for (FieldDetailController.PicklistOption opt : result.get(key)) {
            if (opt.value == finAccount.Id) {
                found = true;
                System.assertEquals('Lookup Financial Account', opt.label);
            }
        }
        System.assertEquals(true, found, 'The household\'s Financial Account should be an option.');
    }

    @IsTest
    static void getLookupOptionsOmitsSourceWhenRequiredBindIsMissing() {
        Envelope__c envelope = new Envelope__c(Status__c = 'In Progress');
        insert envelope;

        Test.startTest();
        Map<String, List<FieldDetailController.PicklistOption>> result =
            EnvelopeLookupOptionController.getLookupOptions(null, envelope.Id);
        Test.stopTest();

        System.assertEquals(false, result.containsKey('Case|AA_Account_Number_Wizard__c'),
            'Without a household id the source has no bind to run with, so it is omitted entirely.');
    }

    @IsTest
    static void getLookupOptionsOmitsSourceWhenHouseholdHasNoEligibleRecords() {
        Account household = new Account(
            Name = 'Empty Lookup Options Household',
            recordTypeId = getHouseholdRecordTypeId(),
            Type = 'Prospect'
        );
        insert household;

        Test.startTest();
        Map<String, List<FieldDetailController.PicklistOption>> result =
            EnvelopeLookupOptionController.getLookupOptions(household.Id, null);
        Test.stopTest();

        System.assertEquals(false, result.containsKey('Case|AA_Account_Number_Wizard__c'),
            'A source that resolves to no records is omitted rather than returned empty.');
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