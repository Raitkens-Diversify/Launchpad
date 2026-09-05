/**
 * Direct coverage for RecordQueryUtil: related-object discovery from a form schema, lookup
 * resolution from a primary record, and merging related record values.
 *
 * Form sections are built by hand (the DTOs are public), so no custom metadata is needed for the
 * schema side. The primary record is a Financial_Account__c whose Account lookup is chosen the same
 * way the util chooses it, so the resolved relationship is deterministic in any org.
 */
@IsTest
private class RecordQueryUtilTest {

    private static final String PRIMARY_OBJECT = 'Financial_Account__c';
    private static final String PERSON_LAST_NAME = 'RecordQueryPerson';

    @TestSetup
    static void setup() {
        Account person = new Account(
            FirstName = 'Jane',
            LastName = PERSON_LAST_NAME,
            Type = 'Prospect',
            RecordTypeId = personAccountRecordTypeId()
        );
        insert person;

        Financial_Account__c fa = new Financial_Account__c(Name = 'Primary FA');
        fa.put(accountLookupField(), person.Id);
        insert fa;
    }

    // ------------------------------------------------------------------ collectRelatedObjectApiNames

    @IsTest
    static void collectRelatedObjectApiNamesReturnsEmptyForMissingInput() {
        Assert.areEqual(0, RecordQueryUtil.collectRelatedObjectApiNames(null, PRIMARY_OBJECT).size(), 'null sections');
        Assert.areEqual(0, RecordQueryUtil.collectRelatedObjectApiNames(
            new List<FieldDetailController.FormSection>(), PRIMARY_OBJECT).size(), 'empty sections');
        Assert.areEqual(0, RecordQueryUtil.collectRelatedObjectApiNames(
            sections(new List<FieldDetailController.FieldMetadata>{ field('Account', 'Name') }), '').size(),
            'blank primary');
    }

    @IsTest
    static void collectRelatedObjectApiNamesSkipsAddRecordBlankPathAndPrimaryFields() {
        FieldDetailController.FieldMetadata addRecord = field('Case', 'AddRecord_Trustee');
        addRecord.addRecord = true;
        FieldDetailController.FieldMetadata blankPath = field('Case', '');
        FieldDetailController.FieldMetadata defaultsToPrimary = field(null, 'Name');
        FieldDetailController.FieldMetadata onPrimary = field(PRIMARY_OBJECT, 'Account_Number__c');
        FieldDetailController.FieldMetadata related = field('Account', 'LastName');
        FieldDetailController.FieldMetadata relatedAgain = field('Account', 'FirstName');
        FieldDetailController.FieldMetadata otherRelated = field('Case', 'Subject');

        Set<String> result = RecordQueryUtil.collectRelatedObjectApiNames(
            sections(new List<FieldDetailController.FieldMetadata>{
                addRecord, blankPath, defaultsToPrimary, onPrimary, related, relatedAgain, otherRelated
            }),
            PRIMARY_OBJECT
        );

        Assert.areEqual(new Set<String>{ 'Account', 'Case' }, result,
            'Only bound fields on objects other than the primary are collected, once each');
    }

    // ------------------------------------------------------------------ resolveRelatedRecordIdsFromPrimary

    @IsTest
    static void resolveRelatedRecordIdsReturnsEmptyForMissingInput() {
        Financial_Account__c fa = primary();
        Set<String> related = new Set<String>{ 'Account' };
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(null, PRIMARY_OBJECT, related).size(), 'null id');
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, '', related).size(), 'blank object');
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, null).size(), 'null related');
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, new Set<String>()).size(),
            'empty related');
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, 'No_Such_Object_XYZ__c', related).size(),
            'unknown primary object');
        Assert.areEqual(0, RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(
            fa.Id, PRIMARY_OBJECT, new Set<String>{ 'No_Such_Object_XYZ__c' }).size(),
            'related object without a lookup from the primary');
    }

    @IsTest
    static void resolveRelatedRecordIdsReadsLookupsOffThePrimaryRecord() {
        Financial_Account__c fa = primary();
        Account person = person();
        Set<String> related = new Set<String>{ 'Account', 'No_Such_Object_XYZ__c' };

        Test.startTest();
        Map<String, Id> first = RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, related);
        // Second call resolves both objects from the lookup cache (one hit, one cached miss).
        Map<String, Id> second = RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, related);
        Test.stopTest();

        Assert.areEqual(1, first.size(), 'Only objects the primary can reach are resolved');
        Assert.areEqual(person.Id, first.get('Account'), 'The Account lookup resolves to the linked person');
        Assert.areEqual(first, second, 'The cached resolution matches the first');
    }

    @IsTest
    static void resolveRelatedRecordIdsReturnsEmptyWhenPrimaryRecordIsGone() {
        Financial_Account__c gone = new Financial_Account__c(Name = 'Deleted FA');
        insert gone;
        Id goneId = gone.Id;
        delete gone;

        Map<String, Id> result = RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(
            goneId, PRIMARY_OBJECT, new Set<String>{ 'Account' });

        Assert.areEqual(0, result.size(), 'A primary that no longer exists resolves nothing');
    }

    @IsTest
    static void resolveRelatedRecordIdsRejectsTooManyRelatedObjects() {
        Financial_Account__c fa = primary();
        Set<String> tooMany = new Set<String>();
        for (Integer i = 0; i <= ARCConstants.MAX_RELATED_OBJECTS_PER_PRIMARY; i++) {
            tooMany.add('Fake_Object_' + i + '__c');
        }

        try {
            RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, tooMany);
            Assert.fail('More related objects than the ceiling should throw');
        } catch (AuraHandledException e) {
            // AuraHandledException.getMessage() always returns the generic "Script-thrown
            // exception" text unless the throwing code calls setMessage() explicitly (a
            // well-known Apex limitation); RecordQueryUtil does not, so the exception type
            // reaching the catch clause is the only verifiable outcome here.
        }
    }

    @IsTest
    static void resolveRelatedRecordIdsRejectsWhenQueryHeadroomIsExhausted() {
        Financial_Account__c fa = primary();

        Test.startTest();
        // Leave exactly one query of headroom; the util needs one plus its safety buffer.
        while (Limits.getQueries() < Limits.getLimitQueries() - 1) {
            List<User> probe = [SELECT Id FROM User LIMIT 1];
        }
        try {
            RecordQueryUtil.resolveRelatedRecordIdsFromPrimary(fa.Id, PRIMARY_OBJECT, new Set<String>{ 'Account' });
            Assert.fail('Insufficient query headroom should throw before querying');
        } catch (AuraHandledException e) {
            // See resolveRelatedRecordIdsRejectsTooManyRelatedObjects: message content is not
            // verifiable through AuraHandledException.getMessage().
        }
        Test.stopTest();
    }

    // ------------------------------------------------------------------ resolveRecordIdFromLookupField

    @IsTest
    static void resolveRecordIdFromLookupFieldReturnsNullForMissingPrimary() {
        Financial_Account__c fa = primary();
        String lookup = accountLookupField();
        Assert.isNull(RecordQueryUtil.resolveRecordIdFromLookupField(null, PRIMARY_OBJECT, lookup), 'null id');
        Assert.isNull(RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, ' ', lookup), 'blank object');
    }

    @IsTest
    static void resolveRecordIdFromLookupFieldRejectsBadLookupConfiguration() {
        Financial_Account__c fa = primary();

        // AuraHandledException.getMessage() always returns the generic "Script-thrown exception"
        // text unless the throwing code calls setMessage() explicitly (a well-known Apex
        // limitation); RecordQueryUtil does not, so only the exception type is verifiable below.
        try {
            RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, PRIMARY_OBJECT, '');
            Assert.fail('Blank lookup field should throw');
        } catch (AuraHandledException e) {
        }
        try {
            RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, 'No_Such_Object_XYZ__c', 'Account__c');
            Assert.fail('Unknown primary object should throw');
        } catch (AuraHandledException e) {
        }
        try {
            RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, PRIMARY_OBJECT, 'No_Such_Field_XYZ__c');
            Assert.fail('Unknown lookup field should throw');
        } catch (AuraHandledException e) {
        }
        try {
            RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, PRIMARY_OBJECT, 'Name');
            Assert.fail('A non-lookup field should throw');
        } catch (AuraHandledException e) {
        }
    }

    @IsTest
    static void resolveRecordIdFromLookupFieldReadsTheLookupValue() {
        Financial_Account__c fa = primary();
        Account person = person();
        String lookup = accountLookupField();

        Id resolved = RecordQueryUtil.resolveRecordIdFromLookupField(fa.Id, PRIMARY_OBJECT, lookup);
        Assert.areEqual(person.Id, resolved, 'The lookup value is returned');

        Financial_Account__c unlinked = new Financial_Account__c(Name = 'Unlinked FA');
        insert unlinked;
        Assert.isNull(RecordQueryUtil.resolveRecordIdFromLookupField(unlinked.Id, PRIMARY_OBJECT, lookup),
            'An empty lookup resolves to null');

        Id unlinkedId = unlinked.Id;
        delete unlinked;
        Assert.isNull(RecordQueryUtil.resolveRecordIdFromLookupField(unlinkedId, PRIMARY_OBJECT, lookup),
            'A missing primary resolves to null');
    }

    // ------------------------------------------------------------------ mergeRelatedRecordValues

    @IsTest
    static void mergeRelatedRecordValuesLeavesValuesAloneWhenNothingResolves() {
        Financial_Account__c fa = primary();
        Map<String, Object> values = new Map<String, Object>{ 'Name' => 'Primary FA' };

        // Nothing related in the schema.
        RecordQueryUtil.mergeRelatedRecordValues(fa.Id, PRIMARY_OBJECT, 'Any Type',
            sections(new List<FieldDetailController.FieldMetadata>{ field(PRIMARY_OBJECT, 'Name') }), values);
        Assert.areEqual(1, values.size(), 'No related objects: values untouched');

        // Related objects, but no values map to merge into.
        RecordQueryUtil.mergeRelatedRecordValues(fa.Id, PRIMARY_OBJECT, 'Any Type',
            sections(new List<FieldDetailController.FieldMetadata>{ field('Account', 'LastName') }), null);

        // Related object the primary has no lookup to.
        RecordQueryUtil.mergeRelatedRecordValues(fa.Id, PRIMARY_OBJECT, 'Any Type',
            sections(new List<FieldDetailController.FieldMetadata>{ field('No_Such_Object_XYZ__c', 'Name') }), values);
        Assert.areEqual(1, values.size(), 'Unresolvable related object: values untouched');
    }

    @IsTest
    static void mergeRelatedRecordValuesMergesTheRelatedRecordsConfiguredFields() {
        Financial_Account__c fa = primary();
        Account person = person();
        String schemaType = mostConfiguredTypeFor('Account');
        Set<String> configured = configuredAccountFields(schemaType);
        Assert.isFalse(configured.isEmpty(), 'Precondition: ' + schemaType + ' configures Account fields');

        // One real related object plus enough unresolvable ones to force more than one chunk. The
        // primary's own field is a made-up path (not a real Financial_Account__c field): it only
        // has to be distinct from every field the merge could bring in, and merged values are
        // keyed by raw field API name with no per-object namespace, so a real field shared by
        // both objects (e.g. Name) would collide with this sentinel by coincidence.
        String primarySentinel = 'PrimarySentinelField';
        List<FieldDetailController.FieldMetadata> fields = new List<FieldDetailController.FieldMetadata>{
            field(PRIMARY_OBJECT, primarySentinel),
            field('Account', new List<String>(configured)[0])
        };
        for (Integer i = 0; i <= ARCConstants.RELATED_OBJECT_VALUES_QUERY_CHUNK_SIZE; i++) {
            fields.add(field('Fake_Object_' + i + '__c', 'Name'));
        }
        Map<String, Object> values = new Map<String, Object>{ primarySentinel => 'Primary FA' };

        Test.startTest();
        RecordQueryUtil.mergeRelatedRecordValues(fa.Id, PRIMARY_OBJECT, schemaType, sections(fields), values);
        Test.stopTest();

        Assert.areEqual('Primary FA', values.get(primarySentinel), 'Primary values survive the merge');
        Assert.isTrue(values.size() > 1, 'Related Account values were merged in');
        if (configured.contains('LastName')) {
            Assert.areEqual(PERSON_LAST_NAME, values.get('LastName'), 'The linked person supplies its values');
        }
        for (String key : values.keySet()) {
            Assert.isTrue(key == primarySentinel || configured.contains(key), 'Only configured related fields merge: ' + key);
        }
    }

    // ------------------------------------------------------------------ findPrimaryLookupField

    @IsTest
    static void findPrimaryLookupFieldReturnsNullForMissingInput() {
        Map<String, Schema.SObjectField> caseFields = Case.SObjectType.getDescribe().fields.getMap();
        Assert.isNull(RecordQueryUtil.findPrimaryLookupField(null, 'Account'), 'null map');
        Assert.isNull(RecordQueryUtil.findPrimaryLookupField(new Map<String, Schema.SObjectField>(), 'Account'), 'empty map');
        Assert.isNull(RecordQueryUtil.findPrimaryLookupField(caseFields, ''), 'blank related object');
        Assert.isNull(RecordQueryUtil.findPrimaryLookupField(caseFields, 'No_Such_Object_XYZ__c'), 'unknown related object');
    }

    @IsTest
    static void findPrimaryLookupFieldPrefersAFieldNamedAfterTheObject() {
        Map<String, Schema.SObjectField> farpFields =
            Financial_Account_Related_Product__c.SObjectType.getDescribe().fields.getMap();

        String lookup = RecordQueryUtil.findPrimaryLookupField(farpFields, 'Product__c');

        Assert.isNotNull(lookup, 'A lookup to Product__c exists on the related-product object');
        Assert.isTrue(lookup.equalsIgnoreCase('Product__c'), 'The field named after the object wins: ' + lookup);
    }

    @IsTest
    static void findPrimaryLookupFieldFallsBackToFirstReferencingField() {
        Map<String, Schema.SObjectField> caseFields = Case.SObjectType.getDescribe().fields.getMap();

        String lookup = RecordQueryUtil.findPrimaryLookupField(caseFields, 'Account');

        Assert.isNotNull(lookup, 'Case has at least one Account lookup');
        Schema.DescribeFieldResult describe = caseFields.get(lookup).getDescribe();
        Assert.areEqual(Schema.DisplayType.REFERENCE, describe.getType(), 'A reference field is chosen');
        Boolean referencesAccount = false;
        for (Schema.SObjectType target : describe.getReferenceTo()) {
            if (target == Account.SObjectType) {
                referencesAccount = true;
            }
        }
        Assert.isTrue(referencesAccount, 'The chosen field references Account: ' + lookup);
        Assert.areEqual(lookup, RecordQueryUtil.findCaseLookupField(caseFields, 'Account'),
            'findCaseLookupField delegates to the same discovery');
    }

    @IsTest
    static void findPrimaryLookupFieldReturnsNullWhenNothingReferencesTheObject() {
        Map<String, Schema.SObjectField> userFields = User.SObjectType.getDescribe().fields.getMap();
        Assert.isNull(RecordQueryUtil.findPrimaryLookupField(userFields, 'Financial_Account_Related_Product__c'),
            'User has no lookup to the related-product object');
    }

    // ------------------------------------------------------------------ helpers

    private static Financial_Account__c primary() {
        return [SELECT Id FROM Financial_Account__c WHERE Name = 'Primary FA' LIMIT 1];
    }

    // The standard Person Account record type has no fixed DeveloperName across orgs, so it is
    // resolved the same way the repo's own test data factory does (FscDataTestDataFactory).
    private static Id cachedPersonAccountRecordTypeId;

    private static Id personAccountRecordTypeId() {
        if (cachedPersonAccountRecordTypeId == null) {
            List<RecordType> personTypes = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
                LIMIT 1
            ];
            Assert.isFalse(personTypes.isEmpty(), 'Precondition: org has an active Person Account record type');
            cachedPersonAccountRecordTypeId = personTypes[0].Id;
        }
        return cachedPersonAccountRecordTypeId;
    }

    private static Account person() {
        return [SELECT Id FROM Account WHERE LastName = :PERSON_LAST_NAME LIMIT 1];
    }

    // The Account lookup the util itself discovers on the primary object, so the test links the
    // record through the same field the util will read.
    private static String accountLookupField() {
        String lookup = RecordQueryUtil.findPrimaryLookupField(
            Financial_Account__c.SObjectType.getDescribe().fields.getMap(), 'Account');
        Assert.isNotNull(lookup, 'Precondition: Financial_Account__c has an Account lookup');
        return lookup;
    }

    private static FieldDetailController.FieldMetadata field(String objectApiName, String fieldPath) {
        FieldDetailController.FieldMetadata meta = new FieldDetailController.FieldMetadata();
        meta.objectApiName = objectApiName;
        meta.fieldPath = fieldPath;
        meta.label = fieldPath;
        meta.type = 'STRING';
        meta.inputType = 'text';
        return meta;
    }

    private static List<FieldDetailController.FormSection> sections(List<FieldDetailController.FieldMetadata> fields) {
        FieldDetailController.FormSection section = new FieldDetailController.FormSection('Details');
        section.fields.addAll(fields);
        return new List<FieldDetailController.FormSection>{ section };
    }

    // Counted in Apex rather than with a SOQL aggregate: Envelope_Field__mdt (like other custom
    // metadata types) does not support COUNT(Id).
    private static String mostConfiguredTypeFor(String objectName) {
        Map<String, Integer> countByType = new Map<String, Integer>();
        for (Envelope_Field__mdt row : [
            SELECT Type__c FROM Envelope_Field__mdt WHERE Object__c = :objectName AND Type__c != null
        ]) {
            countByType.put(row.Type__c, (countByType.containsKey(row.Type__c) ? countByType.get(row.Type__c) : 0) + 1);
        }
        String best = null;
        Integer bestCount = -1;
        for (String type : countByType.keySet()) {
            if (countByType.get(type) > bestCount) {
                bestCount = countByType.get(type);
                best = type;
            }
        }
        Assert.isNotNull(best, 'Precondition: Envelope_Field__mdt configures ' + objectName);
        return best;
    }

    private static Set<String> configuredAccountFields(String type) {
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
        Set<String> configured = new Set<String>();
        for (Envelope_Field__mdt row : [
            SELECT Field_API__c FROM Envelope_Field__mdt WHERE Object__c = 'Account' AND Type__c = :type
        ]) {
            if (String.isNotBlank(row.Field_API__c) && accountFields.containsKey(row.Field_API__c)) {
                configured.add(row.Field_API__c);
            }
        }
        return configured;
    }
}