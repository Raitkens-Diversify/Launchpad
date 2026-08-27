@IsTest
private class EnvelopeHouseholdResolverTest {

    private static Account newHousehold(String name) {
        Account household = new Account(
            Name = name, Type = 'Other', Classification__c = 'Vendor;'
        );
        insert household;
        return household;
    }

    @IsTest
    static void returnsNullForBlankEnvelope() {
        System.assertEquals(null, EnvelopeHouseholdResolver.resolveHouseholdId((String) null));
        System.assertEquals(null, EnvelopeHouseholdResolver.resolveHouseholdId(''));
    }

    @IsTest
    static void returnsNullWhenEnvelopeHasNoResolvableHousehold() {
        Envelope__c env = new Envelope__c(Name = 'No Household');
        insert env;
        System.assertEquals(null, EnvelopeHouseholdResolver.resolveHouseholdId(env.Id));
    }

    @IsTest
    static void prefersEnvelopeHouseholdField() {
        Account household = newHousehold('Field Household');
        Envelope__c env = new Envelope__c(Name = 'Field Env', Household__c = household.Id);
        insert env;
        System.assertEquals(
            household.Id, EnvelopeHouseholdResolver.resolveHouseholdId(env.Id)
        );
    }

    @IsTest
    static void fallsBackToHouseholdJunctionRow() {
        Schema.RecordTypeInfo householdType = Account.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Household');
        // The junction fallback keys on the Household Account record type; if the org has none, the
        // field-first path is the only one exercisable and the other tests already cover it.
        if (householdType == null || !householdType.isActive()) {
            return;
        }
        Account household = new Account(
            Name = 'Junction Household', RecordTypeId = householdType.getRecordTypeId()
        );
        insert household;
        Envelope__c env = new Envelope__c(Name = 'Junction Env');
        insert env;
        insert new Envelope_Content__c(Envelope__c = env.Id, Account__c = household.Id);

        System.assertEquals(
            household.Id, EnvelopeHouseholdResolver.resolveHouseholdId(env.Id)
        );
    }
}