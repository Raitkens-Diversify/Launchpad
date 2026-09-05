/**
 * Direct coverage for FieldDetailController.
 *
 * The controller is driven by Envelope_Field__mdt / Section__mdt custom metadata, which a test
 * cannot insert. The rows ship with the package, so each test reads the same rows the controller
 * reads and derives its expectations from them (labels, order, formats, bounds, picklist sources,
 * filter criteria) rather than pinning any one row. Record-backed methods build their own data.
 */
@IsTest
private class FieldDetailControllerTest {

    private static final String PERSON_LAST_NAME = 'FieldDetailPerson';

    @TestSetup
    static void setup() {
        Account person = newPersonAccount('Jane', PERSON_LAST_NAME);
        person.PersonEmail = 'jane.fielddetail@example.com';
        person.PersonMobilePhone = '555-0100';
        insert person;
    }

    // ------------------------------------------------------------------ getFieldsByType

    @IsTest
    static void getFieldsByTypeRejectsBlankObjectName() {
        try {
            FieldDetailController.getFieldsByType('', 'Any Type');
            Assert.fail('Blank object name should throw');
        } catch (AuraHandledException e) {
            // AuraHandledException.getMessage() always returns the generic "Script-thrown
            // exception" text unless the throwing code calls setMessage() explicitly (a
            // well-known Apex limitation); the controller does not, so the exception type
            // reaching the catch clause is the only verifiable outcome here.
        }
    }

    @IsTest
    static void getFieldsByTypeRejectsUnknownObject() {
        try {
            FieldDetailController.getFieldsByType('No_Such_Object_XYZ__c', 'Any Type');
            Assert.fail('Unknown object should throw');
        } catch (AuraHandledException e) {
            // See getFieldsByTypeRejectsBlankObjectName: message content is not verifiable.
        }
    }

    @IsTest
    static void getFieldsByTypeReturnsEmptyMapForUnknownType() {
        Map<String, List<FieldDetailController.FieldMetadata>> result =
            FieldDetailController.getFieldsByType('Account', 'No Such Type 4242');
        Assert.areEqual(0, result.size(), 'A type with no metadata rows should produce no sections');
    }

    @IsTest
    static void getFieldsByTypeGroupsConfiguredFieldsBySection() {
        String type = mostConfiguredTypeFor('Account');
        List<Envelope_Field__mdt> rows = rowsFor('Account', type);
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();

        Test.startTest();
        Map<String, List<FieldDetailController.FieldMetadata>> result =
            FieldDetailController.getFieldsByType('Account', type);
        Test.stopTest();

        Integer expectedFields = 0;
        Set<String> expectedSections = new Set<String>();
        for (Envelope_Field__mdt row : rows) {
            if (String.isNotBlank(row.Field_API__c) && accountFields.containsKey(row.Field_API__c)) {
                expectedFields++;
                expectedSections.add(row.Section_Name__c);
            }
        }
        Assert.isTrue(expectedFields > 0, 'Precondition: type ' + type + ' configures Account fields');
        Assert.areEqual(expectedSections, result.keySet(), 'Sections should be keyed by Section_Name__c');

        Integer actualFields = 0;
        for (String section : result.keySet()) {
            for (FieldDetailController.FieldMetadata meta : result.get(section)) {
                actualFields++;
                Assert.isTrue(accountFields.containsKey(meta.fieldPath), 'Only real fields are served: ' + meta.fieldPath);
                Assert.isTrue(String.isNotBlank(meta.inputType), 'Every field resolves an input type');
                Assert.isTrue(String.isNotBlank(meta.label), 'Every field resolves a label');
            }
        }
        Assert.areEqual(expectedFields, actualFields, 'Every configured, describable field is served exactly once');

        // A row that names no field is skipped rather than served (covers the blank-field guard).
        List<Envelope_Field__mdt> blankFieldRows = [
            SELECT Object__c, Type__c FROM Envelope_Field__mdt
            WHERE Field_API__c = null AND Add_Record__c = false AND Object__c != null LIMIT 1
        ];
        if (!blankFieldRows.isEmpty()) {
            Map<String, List<FieldDetailController.FieldMetadata>> sparse =
                FieldDetailController.getFieldsByType(blankFieldRows[0].Object__c, blankFieldRows[0].Type__c);
            for (String section : sparse.keySet()) {
                for (FieldDetailController.FieldMetadata meta : sparse.get(section)) {
                    Assert.isTrue(String.isNotBlank(meta.fieldPath), 'Blank Field_API__c rows are skipped');
                }
            }
        }
    }

    // ------------------------------------------------------------------ getFormSchema

    @IsTest
    static void getFormSchemaRejectsBlankObjectName() {
        try {
            FieldDetailController.getFormSchema(null, 'Any Type');
            Assert.fail('Blank object name should throw');
        } catch (AuraHandledException e) {
            // See getFieldsByTypeRejectsBlankObjectName: message content is not verifiable.
        }
    }

    @IsTest
    static void getFormSchemaRejectsUnknownObject() {
        try {
            FieldDetailController.getFormSchema('No_Such_Object_XYZ__c', 'Any Type');
            Assert.fail('Unknown object should throw');
        } catch (AuraHandledException e) {
            // See getFieldsByTypeRejectsBlankObjectName: message content is not verifiable.
        }
    }

    @IsTest
    static void getFormSchemaReturnsNoSectionsForUnknownType() {
        List<FieldDetailController.FormSection> sections =
            FieldDetailController.getFormSchema('Account', 'No Such Type 4242');
        Assert.areEqual(0, sections.size(), 'A type with no rows has no sections');
    }

    @IsTest
    static void getFormSchemaBuildsFieldMetadataFromRowsAndDescribe() {
        String type = mostConfiguredTypeFor('Account');
        List<Envelope_Field__mdt> rows = rowsForType(type);

        Test.startTest();
        List<FieldDetailController.FormSection> sections =
            FieldDetailController.getFormSchema('Account', type);
        Test.stopTest();

        Assert.isFalse(sections.isEmpty(), 'Type ' + type + ' should produce sections');

        Map<String, Envelope_Field__mdt> rowByKey = new Map<String, Envelope_Field__mdt>();
        Set<String> expectedSections = new Set<String>();
        for (Envelope_Field__mdt row : rows) {
            String rowObject = String.isNotBlank(row.Object__c) ? row.Object__c : 'Account';
            Map<String, Schema.SObjectField> fieldMap = fieldMapOf(rowObject);
            if (row.Add_Record__c == true || fieldMap == null
                || String.isBlank(row.Field_API__c) || !fieldMap.containsKey(row.Field_API__c)) {
                continue;
            }
            String key = dedupKey(rowObject, row.Field_API__c, row);
            if (!rowByKey.containsKey(key)) {
                rowByKey.put(key, row);
                expectedSections.add(String.isNotBlank(row.Section_Name__c) ? row.Section_Name__c : 'Other');
            }
        }

        Set<String> seenKeys = new Set<String>();
        Set<String> actualSections = new Set<String>();
        for (FieldDetailController.FormSection section : sections) {
            actualSections.add(section.name);
            Assert.isFalse(section.fields.isEmpty(), 'Sections are only created for served fields: ' + section.name);
            for (FieldDetailController.FieldMetadata meta : section.fields) {
                String key = dedupKey(meta.objectApiName, meta.fieldPath, meta.accountType, meta.shownWhereStatement);
                Assert.isTrue(seenKeys.add(key), 'A field/condition pair is served once: ' + key);
                Envelope_Field__mdt row = rowByKey.get(key);
                Assert.isNotNull(row, 'Served field maps to a metadata row: ' + key);
                assertFieldMatchesRow(meta, row, fieldMapOf(meta.objectApiName).get(meta.fieldPath).getDescribe());
            }
        }
        Assert.areEqual(expectedSections, actualSections, 'Sections follow Section_Name__c (blank -> Other)');
        Assert.areEqual(rowByKey.size(), seenKeys.size(), 'Every distinct field/condition row is served');
    }

    @IsTest
    static void getFormSchemaFallsBackToDefaultSectionForBlankSectionName() {
        List<Envelope_Field__mdt> rows = [
            SELECT Object__c, Type__c, Field_API__c FROM Envelope_Field__mdt
            WHERE Section_Name__c = null AND Add_Record__c = false AND Object__c != null AND Field_API__c != null
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return; // Nothing configured with a blank section in this org; branch not exercisable here.
        }
        Envelope_Field__mdt row = rows[0];
        if (!fieldMapOf(row.Object__c).containsKey(row.Field_API__c)) {
            return;
        }

        List<FieldDetailController.FormSection> sections =
            FieldDetailController.getFormSchema(row.Object__c, row.Type__c);

        Boolean found = false;
        for (FieldDetailController.FormSection section : sections) {
            for (FieldDetailController.FieldMetadata meta : section.fields) {
                if (meta.fieldPath == row.Field_API__c && meta.objectApiName == row.Object__c) {
                    found = true;
                    Assert.areEqual('Other', section.name, 'Blank Section_Name__c falls back to the default section');
                }
            }
        }
        Assert.isTrue(found, 'The blank-section field is still served');
    }

    @IsTest
    static void getFormSchemaCopiesPicklistPresentationFromAccountSourceField() {
        List<Envelope_Field__mdt> sample = [
            SELECT Object__c, Type__c FROM Envelope_Field__mdt
            WHERE Original_Account_Field__c != null AND Object__c != null LIMIT 1
        ];
        if (sample.isEmpty()) {
            return; // No change-request rows configured; source-field presentation not exercisable here.
        }
        String type = sample[0].Type__c;
        String objectName = sample[0].Object__c;
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> ownFields = fieldMapOf(objectName);

        Test.startTest();
        List<FieldDetailController.FormSection> sections =
            FieldDetailController.getFormSchema(objectName, type);
        Test.stopTest();

        Integer copied = 0;
        Integer untouched = 0;
        for (FieldDetailController.FormSection section : sections) {
            for (FieldDetailController.FieldMetadata meta : section.fields) {
                if (String.isBlank(meta.originalAccountField) || meta.objectApiName != objectName) {
                    continue;
                }
                Schema.DescribeFieldResult own = ownFields.get(meta.fieldPath).getDescribe();
                if (isPicklist(own.getType())) {
                    continue; // Own options win; the source is never consulted.
                }
                String source = meta.originalAccountField.trim();
                Schema.DescribeFieldResult sourceDescribe = accountFields.containsKey(source)
                    ? accountFields.get(source).getDescribe() : null;
                if (sourceDescribe != null && isPicklist(sourceDescribe.getType())
                    && !activeOptions(sourceDescribe).isEmpty()) {
                    copied++;
                    Assert.areEqual(String.valueOf(sourceDescribe.getType()), meta.type,
                        'Type is taken from the Account source: ' + meta.fieldPath);
                    Assert.areEqual(activeOptions(sourceDescribe), optionValues(meta.picklistOptions),
                        'Options are copied from the Account source: ' + meta.fieldPath);
                    Assert.areEqual(expectedInputType(sourceDescribe.getType()), meta.inputType,
                        'Control follows the source when no override is configured: ' + meta.fieldPath);
                } else {
                    untouched++;
                    Assert.areEqual(String.valueOf(own.getType()), meta.type,
                        'A non-picklist or unknown source leaves the field as its own type: ' + meta.fieldPath);
                    Assert.isTrue(meta.picklistOptions == null || meta.picklistOptions.isEmpty(),
                        'No options are invented for ' + meta.fieldPath);
                }
            }
        }
        Assert.isTrue(copied + untouched > 0, 'Change-request fields were served for ' + type);
    }

    @IsTest
    static void getFormSchemaResolvesFilterCriteriaIntoSelectOptions() {
        List<Envelope_Field__mdt> criteriaRows = [
            SELECT Object__c, Type__c, Field_API__c, Filter_Criteria__c, Account_Type__c, Shown_WHERE_Statement__c
            FROM Envelope_Field__mdt
            WHERE Filter_Criteria__c != null AND Object__c != null AND Field_API__c != null
        ];
        if (criteriaRows.isEmpty()) {
            return; // No filter criteria configured; option resolution not exercisable here.
        }
        insertProductsForEveryAssetCategory();

        String type = criteriaRows[0].Type__c;
        String objectName = criteriaRows[0].Object__c;
        Map<String, Envelope_Field__mdt> criteriaByKey = new Map<String, Envelope_Field__mdt>();
        for (Envelope_Field__mdt row : criteriaRows) {
            if (row.Type__c == type) {
                criteriaByKey.put(dedupKey(row.Object__c, row.Field_API__c, row), row);
            }
        }

        Test.startTest();
        List<FieldDetailController.FormSection> sections =
            FieldDetailController.getFormSchema(objectName, type);
        // Second call for the same type: every criteria is now answered from the per-transaction cache.
        List<FieldDetailController.FormSection> again =
            FieldDetailController.getFormSchema(objectName, type);
        Test.stopTest();

        Integer resolved = 0;
        Integer checked = 0;
        for (FieldDetailController.FormSection section : sections) {
            for (FieldDetailController.FieldMetadata meta : section.fields) {
                Envelope_Field__mdt row = criteriaByKey.get(
                    dedupKey(meta.objectApiName, meta.fieldPath, meta.accountType, meta.shownWhereStatement));
                if (row == null) {
                    continue;
                }
                checked++;
                List<String> selected = selectedFieldsOf(row.Filter_Criteria__c);
                List<SObject> expected = Database.query(row.Filter_Criteria__c.trim());
                if (expected.isEmpty()) {
                    Assert.isTrue(meta.picklistOptions == null || meta.picklistOptions.isEmpty(),
                        'An empty filter leaves the field untouched: ' + meta.fieldPath);
                    continue;
                }
                resolved++;
                Assert.areEqual('PICKLIST', meta.type, 'Filtered lookups are served as a picklist');
                Assert.areEqual('select', meta.inputType, 'Filtered lookups render as a select');
                Assert.areEqual(expected.size(), meta.picklistOptions.size(), 'One option per matching record');
                Set<String> expectedValues = new Set<String>();
                Set<String> expectedLabels = new Set<String>();
                String labelField = selected.size() > 1 ? selected[1] : selected[0];
                for (SObject record : expected) {
                    expectedValues.add(String.valueOf(record.get(selected[0])));
                    expectedLabels.add(String.valueOf(record.get(labelField)));
                }
                for (FieldDetailController.PicklistOption option : meta.picklistOptions) {
                    Assert.isTrue(expectedValues.contains(option.value), 'Option value is the first selected field');
                    Assert.isTrue(expectedLabels.contains(option.label), 'Option label is the second selected field');
                }
            }
        }
        Assert.isTrue(checked > 0, 'Filtered fields were served for ' + type);
        Assert.isTrue(resolved > 0, 'At least one filter resolved options against the inserted products');
        Assert.areEqual(sections.size(), again.size(), 'A cached criteria builds the same sections');
    }

    // ------------------------------------------------------------------ getAllFormSchemas

    @IsTest
    static void getAllFormSchemasKeysEveryTypeByEachObjectItTargets() {
        List<Envelope_Field__mdt> rows = [
            SELECT Object__c, Type__c FROM Envelope_Field__mdt WHERE Type__c != null
        ];
        Map<String, Set<String>> objectsByType = new Map<String, Set<String>>();
        Map<String, Map<String, Integer>> votesByType = new Map<String, Map<String, Integer>>();
        for (Envelope_Field__mdt row : rows) {
            if (!objectsByType.containsKey(row.Type__c)) {
                objectsByType.put(row.Type__c, new Set<String>());
                votesByType.put(row.Type__c, new Map<String, Integer>());
            }
            if (String.isNotBlank(row.Object__c)) {
                objectsByType.get(row.Type__c).add(row.Object__c);
                Map<String, Integer> votes = votesByType.get(row.Type__c);
                votes.put(row.Object__c, (votes.containsKey(row.Object__c) ? votes.get(row.Object__c) : 0) + 1);
            }
        }

        Test.startTest();
        Map<String, List<FieldDetailController.FormSection>> schemas = FieldDetailController.getAllFormSchemas();
        Test.stopTest();

        Set<String> expectedKeys = new Set<String>();
        for (String type : objectsByType.keySet()) {
            for (String objectName : objectsByType.get(type)) {
                expectedKeys.add(objectName + '|' + type);
            }
        }
        Assert.areEqual(expectedKeys, schemas.keySet(), 'One key per object|type pair present in the metadata');

        for (String type : objectsByType.keySet()) {
            Set<String> objects = objectsByType.get(type);
            if (objects.isEmpty()) {
                continue;
            }
            String primary = null;
            Integer best = -1;
            for (String objectName : votesByType.get(type).keySet()) {
                if (votesByType.get(type).get(objectName) > best) {
                    best = votesByType.get(type).get(objectName);
                    primary = objectName;
                }
            }
            List<FieldDetailController.FormSection> perType = FieldDetailController.getFormSchema(primary, type);
            for (String objectName : objects) {
                List<FieldDetailController.FormSection> stored = schemas.get(objectName + '|' + type);
                Assert.areEqual(sectionSignature(perType), sectionSignature(stored),
                    'The prefetched schema matches the per-type schema for ' + objectName + '|' + type);
                for (FieldDetailController.FormSection section : stored) {
                    for (FieldDetailController.FieldMetadata meta : section.fields) {
                        Assert.isTrue(objects.contains(meta.objectApiName),
                            'Each field is described against an object of its own type: ' + meta.fieldPath);
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ getSectionLayouts

    @IsTest
    static void getSectionLayoutsGroupsChildSectionsUnderOrderedParents() {
        List<Section__mdt> rows = [
            SELECT Type__c, Parent_Section_Name__c, Parent_Section_Order__c, Child_Section_Name__c, Order__c
            FROM Section__mdt
            ORDER BY Type__c, Parent_Section_Order__c NULLS LAST, Order__c NULLS LAST
        ];

        Test.startTest();
        Map<String, List<FieldDetailController.SectionGroup>> layouts = FieldDetailController.getSectionLayouts();
        Test.stopTest();

        Map<String, List<String>> expectedParents = new Map<String, List<String>>();
        Map<String, List<String>> expectedChildren = new Map<String, List<String>>();
        for (Section__mdt row : rows) {
            if (String.isBlank(row.Type__c) || String.isBlank(row.Child_Section_Name__c)) {
                continue;
            }
            if (!expectedParents.containsKey(row.Type__c)) {
                expectedParents.put(row.Type__c, new List<String>());
            }
            String parentKey = row.Type__c + '|' + row.Parent_Section_Name__c;
            if (!expectedChildren.containsKey(parentKey)) {
                expectedChildren.put(parentKey, new List<String>());
                expectedParents.get(row.Type__c).add(row.Parent_Section_Name__c);
            }
            expectedChildren.get(parentKey).add(row.Child_Section_Name__c);
        }

        Assert.areEqual(expectedParents.keySet(), layouts.keySet(), 'Layouts exist for exactly the configured types');
        for (String type : layouts.keySet()) {
            List<String> parents = new List<String>();
            for (FieldDetailController.SectionGroup grp : layouts.get(type)) {
                parents.add(grp.parentName);
                Assert.areEqual(expectedChildren.get(type + '|' + grp.parentName), grp.childSections,
                    'Children are listed in Order__c order under ' + grp.parentName);
            }
            Assert.areEqual(expectedParents.get(type), parents, 'Parents are listed in display order for ' + type);
        }
        Assert.isFalse(layouts.containsKey('No Such Type 4242'), 'Unconfigured types are absent');
    }

    // ------------------------------------------------------------------ getRecordValuesForType

    @IsTest
    static void getRecordValuesForTypeReturnsEmptyForBadInput() {
        Account person = person();
        List<Id> ids = new List<Id>{ person.Id };

        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('', 'Any', ids).size(), 'blank object');
        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('Account', '', ids).size(), 'blank type');
        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('Account', 'Any', null).size(), 'null ids');
        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('Account', 'Any', new List<Id>()).size(), 'empty ids');
        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('No_Such_Object_XYZ__c', 'Any', ids).size(), 'unknown object');
        Assert.areEqual(0, FieldDetailController.getRecordValuesForType('Account', 'No Such Type 4242', ids).size(), 'type without rows');
    }

    @IsTest
    static void getRecordValuesForTypeReturnsOnlyNonNullConfiguredValues() {
        Account person = person();
        Id personId = person.Id; // Dynamic SOQL bind expressions can't dot into a variable's field.
        String type = mostConfiguredTypeFor('Account');
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
        Set<String> configured = new Set<String>();
        for (Envelope_Field__mdt row : rowsFor('Account', type)) {
            if (String.isNotBlank(row.Field_API__c) && accountFields.containsKey(row.Field_API__c)) {
                configured.add(row.Field_API__c);
            }
        }
        SObject expected = Database.query('SELECT ' + String.join(new List<String>(configured), ', ')
            + ' FROM Account WHERE Id = :personId' );

        Test.startTest();
        Map<Id, Map<String, Object>> result =
            FieldDetailController.getRecordValuesForType('Account', type, new List<Id>{ person.Id });
        Test.stopTest();

        Assert.isTrue(result.containsKey(person.Id), 'The record is keyed by its Id');
        Map<String, Object> values = result.get(person.Id);
        for (String fieldApi : configured) {
            Object value = expected.get(fieldApi);
            if (value == null) {
                Assert.isFalse(values.containsKey(fieldApi), 'Null values are omitted: ' + fieldApi);
            } else {
                // String.valueOf rather than direct object equality: a compound field (e.g. a
                // billing Address) can come back as two instances that print identically but do
                // not satisfy System.Address equality, a known quirk of that type.
                Assert.areEqual(String.valueOf(value), String.valueOf(values.get(fieldApi)),
                    'Configured value is returned: ' + fieldApi);
            }
        }
        for (String key : values.keySet()) {
            Assert.isTrue(configured.contains(key), 'Only configured fields are returned: ' + key);
        }
        if (configured.contains('LastName')) {
            Assert.areEqual(PERSON_LAST_NAME, values.get('LastName'), 'LastName is read from the record');
        }
    }

    // ------------------------------------------------------------------ getOriginalAccountValues

    @IsTest
    static void getOriginalAccountValuesReturnsEmptyForBadInput() {
        Account person = person();
        List<Id> ids = new List<Id>{ person.Id };
        Assert.areEqual(0, FieldDetailController.getOriginalAccountValues('', ids).size(), 'blank type');
        Assert.areEqual(0, FieldDetailController.getOriginalAccountValues('Any', null).size(), 'null ids');
        Assert.areEqual(0, FieldDetailController.getOriginalAccountValues('Any', new List<Id>()).size(), 'empty ids');
        Assert.areEqual(0, FieldDetailController.getOriginalAccountValues('No Such Type 4242', ids).size(),
            'type without source rows');
    }

    @IsTest
    static void getOriginalAccountValuesRekeysAccountValuesByProposedField() {
        List<Envelope_Field__mdt> sample = [
            SELECT Type__c FROM Envelope_Field__mdt
            WHERE Original_Account_Field__c != null AND Field_API__c != null LIMIT 1
        ];
        if (sample.isEmpty()) {
            return; // No change-request rows configured in this org.
        }
        String type = sample[0].Type__c;
        Account person = person();
        Id personId = person.Id; // Dynamic SOQL bind expressions can't dot into a variable's field.
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();

        Map<String, String> expectedSourceByProposed = new Map<String, String>();
        Set<String> invalidSourceProposed = new Set<String>();
        for (Envelope_Field__mdt row : [
            SELECT Field_API__c, Original_Account_Field__c FROM Envelope_Field__mdt
            WHERE Type__c = :type AND Field_API__c != null AND Original_Account_Field__c != null
        ]) {
            String source = row.Original_Account_Field__c.trim();
            if (!accountFields.containsKey(source)) {
                invalidSourceProposed.add(row.Field_API__c);
                continue;
            }
            if (!expectedSourceByProposed.containsKey(row.Field_API__c)) {
                expectedSourceByProposed.put(row.Field_API__c, accountFields.get(source).getDescribe().getName());
            }
        }
        Assert.isFalse(expectedSourceByProposed.isEmpty(), 'Precondition: ' + type + ' has valid Account sources');
        Set<String> selectFields = new Set<String>{ 'Id' };
        selectFields.addAll(expectedSourceByProposed.values());
        SObject expected = Database.query('SELECT ' + String.join(new List<String>(selectFields), ', ')
            + ' FROM Account WHERE Id = :personId');

        Test.startTest();
        Map<Id, Map<String, Object>> result =
            FieldDetailController.getOriginalAccountValues(type, new List<Id>{ person.Id });
        Test.stopTest();

        Assert.isTrue(result.containsKey(person.Id), 'Values are keyed by account Id');
        Map<String, Object> values = result.get(person.Id);
        Assert.areEqual(expectedSourceByProposed.keySet(), values.keySet(),
            'Every proposed field with a real source is present, nulls included');
        for (String proposed : expectedSourceByProposed.keySet()) {
            // String.valueOf rather than direct object equality: see
            // getRecordValuesForTypeReturnsOnlyNonNullConfiguredValues for why (compound fields).
            Assert.areEqual(String.valueOf(expected.get(expectedSourceByProposed.get(proposed))),
                String.valueOf(values.get(proposed)),
                'Current Account value is served under the Case field ' + proposed);
        }
        for (String proposed : invalidSourceProposed) {
            if (!expectedSourceByProposed.containsKey(proposed)) {
                Assert.isFalse(values.containsKey(proposed), 'Rows with a bad source are skipped: ' + proposed);
            }
        }
        if (expectedSourceByProposed.values().contains('FirstName')) {
            for (String proposed : expectedSourceByProposed.keySet()) {
                if (expectedSourceByProposed.get(proposed) == 'FirstName') {
                    Assert.areEqual('Jane', values.get(proposed), 'FirstName reads through to the proposed field');
                }
            }
        }
    }

    // ------------------------------------------------------------------ getCaseValuesForAccounts

    @IsTest
    static void getCaseValuesForAccountsReturnsEmptyForBadInput() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'FA Bad Input');
        insert fa;
        List<Id> ids = new List<Id>{ fa.Id };
        Assert.areEqual(0, FieldDetailController.getCaseValuesForAccounts('', ids).size(), 'blank type');
        Assert.areEqual(0, FieldDetailController.getCaseValuesForAccounts('Any', null).size(), 'null ids');
        Assert.areEqual(0, FieldDetailController.getCaseValuesForAccounts('Any', new List<Id>()).size(), 'empty ids');
        Assert.areEqual(0, FieldDetailController.getCaseValuesForAccounts(mostConfiguredTypeFor('Account'), ids).size(),
            'a type with no Case rows yields nothing');
    }

    @IsTest
    static void getCaseValuesForAccountsReadsOldestWizardCasePerAccount() {
        String type = mixedTypeWithCaseRows();
        if (type == null) {
            return; // No interview type maps Case fields in this org.
        }
        Map<String, Schema.SObjectField> caseFields = Case.SObjectType.getDescribe().fields.getMap();
        Set<String> configured = new Set<String>();
        String textField = null;
        for (Envelope_Field__mdt row : rowsFor('Case', type)) {
            if (String.isBlank(row.Field_API__c) || !caseFields.containsKey(row.Field_API__c)) {
                continue;
            }
            configured.add(row.Field_API__c);
            Schema.DescribeFieldResult describe = caseFields.get(row.Field_API__c).getDescribe();
            if (textField == null && describe.getType() == Schema.DisplayType.STRING
                && describe.isCreateable() && describe.isUpdateable()) {
                textField = row.Field_API__c;
            }
        }
        Assert.isFalse(configured.isEmpty(), 'Precondition: ' + type + ' configures real Case fields');

        Financial_Account__c fa = new Financial_Account__c(Name = 'FA With Cases');
        Financial_Account__c lonely = new Financial_Account__c(Name = 'FA Without Cases');
        insert new List<Financial_Account__c>{ fa, lonely };

        Case older = wizardCase(fa.Id);
        Case newer = wizardCase(fa.Id);
        Case unrelated = wizardCase(fa.Id);
        unrelated.Origin = 'Phone';
        if (textField != null) {
            older.put(textField, 'older');
            newer.put(textField, 'newer');
            unrelated.put(textField, 'not a wizard case');
        }
        insert new List<Case>{ older, newer, unrelated };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-3));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
        Test.setCreatedDate(unrelated.Id, Datetime.now().addDays(-5));

        Test.startTest();
        Map<Id, Map<String, Object>> result =
            FieldDetailController.getCaseValuesForAccounts(type, new List<Id>{ fa.Id, lonely.Id });
        Test.stopTest();

        Assert.isTrue(result.containsKey(fa.Id), 'Values are keyed by the Financial Account');
        Assert.isFalse(result.containsKey(lonely.Id), 'An account without a wizard Case has no entry');
        Map<String, Object> values = result.get(fa.Id);
        Assert.areEqual(configured, values.keySet(), 'Every configured Case field is returned, nulls included');
        if (textField != null) {
            Assert.areEqual('older', values.get(textField), 'The oldest wizard Case wins');
        }
    }

    // ------------------------------------------------------------------ related product values

    @IsTest
    static void getRelatedProductValuesForAccountsReturnsEmptyForBadInput() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'FA Bad Input');
        insert fa;
        List<Id> ids = new List<Id>{ fa.Id };
        Assert.areEqual(0, FieldDetailController.getRelatedProductValuesForAccounts('', ids).size(), 'blank type');
        Assert.areEqual(0, FieldDetailController.getRelatedProductValuesForAccounts('Any', null).size(), 'null ids');
        Assert.areEqual(0, FieldDetailController.getRelatedProductValuesForAccounts('Any', new List<Id>()).size(), 'empty ids');
        Assert.areEqual(0, FieldDetailController.getRelatedProductValuesForAccounts(mostConfiguredTypeFor('Account'), ids).size(),
            'a type with no related-product rows yields nothing');
    }

    @IsTest
    static void getRelatedProductValuesForAccountsSeedsNullAndReadsOldestRow() {
        String type = typeWithRowsOn(WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT);
        if (type == null) {
            return; // No interview type maps related-product fields in this org.
        }
        Set<String> configured = configuredFieldApis(WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT, type);

        Product__c first = new Product__c(Name = 'First Product');
        Product__c second = new Product__c(Name = 'Second Product');
        insert new List<Product__c>{ first, second };
        Financial_Account__c fa = new Financial_Account__c(Name = 'FA With Product');
        Financial_Account__c empty = new Financial_Account__c(Name = 'FA Without Product');
        insert new List<Financial_Account__c>{ fa, empty };
        Financial_Account_Related_Product__c older = new Financial_Account_Related_Product__c(
            Product__c = first.Id, Wizard_Financial_Account__c = fa.Id);
        Financial_Account_Related_Product__c newer = new Financial_Account_Related_Product__c(
            Product__c = second.Id, Wizard_Financial_Account__c = fa.Id);
        insert new List<Financial_Account_Related_Product__c>{ older, newer };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-3));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));

        Test.startTest();
        Map<Id, Map<String, Object>> result =
            FieldDetailController.getRelatedProductValuesForAccounts(type, new List<Id>{ fa.Id, empty.Id });
        Test.stopTest();

        Assert.areEqual(2, result.size(), 'Every requested account gets an entry');
        Assert.areEqual(configured, result.get(fa.Id).keySet(), 'Each configured field is present');
        Assert.areEqual(configured, result.get(empty.Id).keySet(), 'Each configured field is seeded');
        for (String fieldApi : configured) {
            Assert.areEqual(first.Id, result.get(fa.Id).get(fieldApi), 'The oldest row supplies the product');
            Assert.isNull(result.get(empty.Id).get(fieldApi), 'No row reads as a cleared selection');
        }
    }

    @IsTest
    static void getActionRelatedProductValuesReturnsEmptyForBadInput() {
        Case action = new Case(Subject = 'Action Bad Input');
        insert action;
        List<Id> ids = new List<Id>{ action.Id };
        Assert.areEqual(0, FieldDetailController.getActionRelatedProductValues('', ids).size(), 'blank type');
        Assert.areEqual(0, FieldDetailController.getActionRelatedProductValues('Any', null).size(), 'null ids');
        Assert.areEqual(0, FieldDetailController.getActionRelatedProductValues('Any', new List<Id>()).size(), 'empty ids');
        Assert.areEqual(0, FieldDetailController.getActionRelatedProductValues(mostConfiguredTypeFor('Account'), ids).size(),
            'a type with no related-product rows yields nothing');
    }

    @IsTest
    static void getActionRelatedProductValuesKeysByCaseAndReadsOldestRow() {
        String type = typeWithRowsOn(WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT);
        if (type == null) {
            return; // No interview type maps related-product fields in this org.
        }
        Set<String> configured = configuredFieldApis(WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT, type);

        Product__c first = new Product__c(Name = 'First Product');
        Product__c second = new Product__c(Name = 'Second Product');
        insert new List<Product__c>{ first, second };
        Case withProduct = new Case(Subject = 'Action With Product');
        Case without = new Case(Subject = 'Action Without Product');
        insert new List<Case>{ withProduct, without };
        Financial_Account_Related_Product__c older = new Financial_Account_Related_Product__c(
            Product__c = first.Id, Case__c = withProduct.Id);
        Financial_Account_Related_Product__c newer = new Financial_Account_Related_Product__c(
            Product__c = second.Id, Case__c = withProduct.Id);
        insert new List<Financial_Account_Related_Product__c>{ older, newer };
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-3));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));

        Test.startTest();
        Map<Id, Map<String, Object>> result =
            FieldDetailController.getActionRelatedProductValues(type, new List<Id>{ withProduct.Id, without.Id });
        Test.stopTest();

        Assert.areEqual(2, result.size(), 'Every requested Case gets an entry');
        for (String fieldApi : configured) {
            Assert.areEqual(first.Id, result.get(withProduct.Id).get(fieldApi), 'The oldest row for the Case wins');
            Assert.isNull(result.get(without.Id).get(fieldApi), 'A Case with no row reads as cleared');
        }
    }

    // ------------------------------------------------------------------ DTOs

    @IsTest
    static void dtoConstructorsSetTheirFields() {
        FieldDetailController.FormSection section = new FieldDetailController.FormSection('Details');
        Assert.areEqual('Details', section.name);
        Assert.areEqual(0, section.fields.size());

        FieldDetailController.PicklistOption option = new FieldDetailController.PicklistOption('Label', 'Value');
        Assert.areEqual('Label', option.label);
        Assert.areEqual('Value', option.value);

        FieldDetailController.SectionGroup grp = new FieldDetailController.SectionGroup();
        grp.parentName = 'Parent';
        grp.parentOrder = 1;
        grp.childSections = new List<String>{ 'Child' };
        Assert.areEqual('Parent', grp.parentName);
    }

    // ------------------------------------------------------------------ helpers

    private static Account person() {
        return [SELECT Id FROM Account WHERE LastName = :PERSON_LAST_NAME LIMIT 1];
    }

    private static Account newPersonAccount(String firstName, String lastName) {
        return new Account(
            FirstName = firstName,
            LastName = lastName,
            Type = 'Prospect',
            RecordTypeId = personAccountRecordTypeId()
        );
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

    private static Case wizardCase(Id financialAccountId) {
        return new Case(
            Subject = 'New Financial Account',
            Origin = WizardEnvelopeStateService.WIZARD_CASE_ORIGIN,
            Type = WizardEnvelopeStateService.ACCOUNT_OPENING_CASE_TYPE,
            Wizard_Financial_Account__c = financialAccountId
        );
    }

    // One Sell/Service product per active Asset_Category__c, so any product filter finds a match.
    private static void insertProductsForEveryAssetCategory() {
        List<Product__c> products = new List<Product__c>();
        for (Schema.PicklistEntry entry : Product__c.Asset_Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                products.add(new Product__c(
                    Name = 'Product ' + entry.getValue(),
                    Status__c = 'Sell/Service',
                    Asset_Category__c = entry.getValue()
                ));
            }
        }
        insert products;
    }

    private static List<Envelope_Field__mdt> rowsForType(String type) {
        return [
            SELECT Object__c, Type__c, Section_Name__c, Field_API__c, Label__c, Required__c,
                Required_WHERE_Statement__c, Order__c, Shown_WHERE_Statement__c, Add_Record__c,
                Add_Record_Type__c, Key_Decision__c, Field_Type_Override__c, Format__c, Pattern__c,
                Pattern_Error__c, Min__c, Max__c, Filter_Criteria__c, Account_Type__c, Original_Account_Field__c
            FROM Envelope_Field__mdt
            WHERE Type__c = :type
            ORDER BY Order__c NULLS LAST
        ];
    }

    private static List<Envelope_Field__mdt> rowsFor(String objectName, String type) {
        List<Envelope_Field__mdt> rows = new List<Envelope_Field__mdt>();
        for (Envelope_Field__mdt row : rowsForType(type)) {
            if (row.Object__c == objectName) {
                rows.add(row);
            }
        }
        return rows;
    }

    // The type with the most rows on the object: the richest exercise of the describe-driven paths.
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

    private static String typeWithRowsOn(String objectName) {
        List<Envelope_Field__mdt> rows = [
            SELECT Type__c FROM Envelope_Field__mdt WHERE Object__c = :objectName AND Field_API__c != null LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Type__c;
    }

    // A type that maps both Case and Financial_Account__c fields, else any type with Case rows.
    private static String mixedTypeWithCaseRows() {
        Set<String> caseTypes = new Set<String>();
        Set<String> faTypes = new Set<String>();
        for (Envelope_Field__mdt row : [
            SELECT Type__c, Object__c FROM Envelope_Field__mdt
            WHERE Object__c IN ('Case', 'Financial_Account__c') AND Field_API__c != null
        ]) {
            if (row.Object__c == 'Case') {
                caseTypes.add(row.Type__c);
            } else {
                faTypes.add(row.Type__c);
            }
        }
        for (String type : caseTypes) {
            if (faTypes.contains(type)) {
                return type;
            }
        }
        return caseTypes.isEmpty() ? null : new List<String>(caseTypes)[0];
    }

    private static Set<String> configuredFieldApis(String objectName, String type) {
        Set<String> fieldApis = new Set<String>();
        for (Envelope_Field__mdt row : rowsFor(objectName, type)) {
            if (String.isNotBlank(row.Field_API__c)) {
                fieldApis.add(row.Field_API__c);
            }
        }
        return fieldApis;
    }

    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache =
        new Map<String, Map<String, Schema.SObjectField>>();

    private static Map<String, Schema.SObjectField> fieldMapOf(String objectName) {
        if (!fieldMapCache.containsKey(objectName)) {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            fieldMapCache.put(objectName, objectType == null ? null : objectType.getDescribe().fields.getMap());
        }
        return fieldMapCache.get(objectName);
    }

    private static String dedupKey(String objectName, String fieldPath, Envelope_Field__mdt row) {
        return dedupKey(objectName, fieldPath,
            String.isNotBlank(row.Account_Type__c) ? row.Account_Type__c : 'Person',
            row.Shown_WHERE_Statement__c);
    }

    private static String dedupKey(String objectName, String fieldPath, String accountType, String shownWhere) {
        return objectName + '|' + fieldPath + '|' + accountType + '|' + shownWhere;
    }

    private static Boolean isPicklist(Schema.DisplayType type) {
        return type == Schema.DisplayType.PICKLIST || type == Schema.DisplayType.MULTIPICKLIST;
    }

    private static List<String> activeOptions(Schema.DescribeFieldResult describe) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static List<String> optionValues(List<FieldDetailController.PicklistOption> options) {
        List<String> values = new List<String>();
        if (options != null) {
            for (FieldDetailController.PicklistOption option : options) {
                values.add(option.value);
            }
        }
        return values;
    }

    private static List<String> selectedFieldsOf(String soql) {
        String upper = soql.toUpperCase();
        Integer selectAt = upper.indexOf('SELECT ');
        Integer fromAt = upper.indexOf(' FROM ');
        List<String> fields = new List<String>();
        for (String part : soql.substring(selectAt + 7, fromAt).split(',')) {
            if (String.isNotBlank(part)) {
                fields.add(part.trim());
            }
        }
        return fields;
    }

    private static String sectionSignature(List<FieldDetailController.FormSection> sections) {
        List<String> parts = new List<String>();
        for (FieldDetailController.FormSection section : sections) {
            List<String> paths = new List<String>();
            for (FieldDetailController.FieldMetadata meta : section.fields) {
                paths.add(meta.objectApiName + '.' + meta.fieldPath);
            }
            parts.add(section.name + '=' + String.join(paths, ','));
        }
        return String.join(parts, ';');
    }

    // The control the controller is expected to pick for a describe type (its documented mapping).
    private static String expectedInputType(Schema.DisplayType type) {
        switch on type {
            when STRING, TEXTAREA, ID { return 'text'; }
            when EMAIL { return 'email'; }
            when PHONE { return 'tel'; }
            when URL { return 'url'; }
            when DATE { return 'date'; }
            when DATETIME { return 'datetime'; }
            when TIME { return 'time'; }
            when INTEGER, LONG, DOUBLE, CURRENCY, PERCENT { return 'number'; }
            when BOOLEAN { return 'checkbox'; }
            when PICKLIST { return 'combobox'; }
            when MULTIPICKLIST { return 'checkboxGroup'; }
            when else { return 'text'; }
        }
    }

    private static void assertFieldMatchesRow(
        FieldDetailController.FieldMetadata meta,
        Envelope_Field__mdt row,
        Schema.DescribeFieldResult describe
    ) {
        String path = meta.objectApiName + '.' + meta.fieldPath;
        Assert.areEqual(String.isNotBlank(row.Label__c) ? row.Label__c : describe.getLabel(), meta.label, 'label ' + path);
        Assert.areEqual(row.Required__c, meta.required, 'required ' + path);
        Assert.areEqual(row.Required_WHERE_Statement__c, meta.requiredWhereStatement, 'requiredWhere ' + path);
        Assert.areEqual(row.Shown_WHERE_Statement__c, meta.shownWhereStatement, 'shownWhere ' + path);
        Assert.areEqual(row.Key_Decision__c, meta.keyDecision, 'keyDecision ' + path);
        Assert.areEqual(String.isNotBlank(row.Account_Type__c) ? row.Account_Type__c : 'Person', meta.accountType,
            'accountType defaults to Person ' + path);
        Assert.areEqual(row.Original_Account_Field__c, meta.originalAccountField, 'originalAccountField ' + path);
        Assert.areEqual(describe.getLength(), meta.maxLength, 'maxLength ' + path);
        Assert.areEqual(describe.getScale(), meta.scale, 'scale ' + path);
        Assert.areEqual(describe.getPrecision(), meta.precision, 'precision ' + path);

        // Format / pattern: a named format from the shared library wins over the raw pattern.
        if (String.isNotBlank(row.Format__c) && WizardFieldValidator.FORMATS.containsKey(row.Format__c)) {
            WizardFieldValidator.FormatDef def = WizardFieldValidator.FORMATS.get(row.Format__c);
            Assert.areEqual(row.Format__c, meta.format, 'format ' + path);
            Assert.areEqual(def.pattern, meta.pattern, 'format pattern ' + path);
            Assert.areEqual(def.errorMessage, meta.patternError, 'format error ' + path);
        } else {
            Assert.isNull(meta.format, 'no format ' + path);
            Assert.areEqual(row.Pattern__c, meta.pattern, 'raw pattern ' + path);
            Assert.areEqual(row.Pattern_Error__c, meta.patternError, 'raw pattern error ' + path);
        }

        // Bounds: multi-selects cap the selection count; everything else binds min/max (TODAY resolved).
        if (describe.getType() == Schema.DisplayType.MULTIPICKLIST) {
            Integer expectedMax = String.isNotBlank(row.Max__c) && row.Max__c.trim().isNumeric()
                ? Integer.valueOf(row.Max__c.trim()) : null;
            Assert.areEqual(expectedMax, meta.maxSelections, 'maxSelections ' + path);
            Assert.isNull(meta.minValue, 'no minValue on multi-select ' + path);
            Assert.isNull(meta.maxValue, 'no maxValue on multi-select ' + path);
        } else {
            Assert.areEqual(expectedBound(row.Min__c), meta.minValue, 'minValue ' + path);
            Assert.areEqual(expectedBound(row.Max__c), meta.maxValue, 'maxValue ' + path);
            Assert.isNull(meta.maxSelections, 'no maxSelections on single-value field ' + path);
        }

        // Lookups carry their target object.
        if (describe.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> references = describe.getReferenceTo();
            Assert.areEqual(references.isEmpty() ? null : String.valueOf(references[0]), meta.referenceTo,
                'referenceTo ' + path);
        } else {
            Assert.isNull(meta.referenceTo, 'referenceTo only on lookups ' + path);
        }

        // Filter criteria resolved to options are asserted by their own test; here the field must at
        // least keep the shape the criteria implies (a picklist with options) or its describe type.
        if (String.isNotBlank(row.Filter_Criteria__c)
            && meta.picklistOptions != null && !meta.picklistOptions.isEmpty() && !isPicklist(describe.getType())) {
            Assert.areEqual('PICKLIST', meta.type, 'filtered lookup served as picklist ' + path);
            Assert.areEqual('select', meta.inputType, 'filtered lookup served as select ' + path);
            return;
        }

        // Presentation: own picklist values, else a picklist Account source, else the describe type.
        String expectedType = String.valueOf(describe.getType());
        String expectedInput = expectedInputType(describe.getType());
        List<String> expectedOptions = isPicklist(describe.getType()) ? activeOptions(describe) : null;
        if (expectedOptions == null && String.isNotBlank(row.Original_Account_Field__c)) {
            Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
            String source = row.Original_Account_Field__c.trim();
            if (accountFields.containsKey(source)) {
                Schema.DescribeFieldResult sourceDescribe = accountFields.get(source).getDescribe();
                if (isPicklist(sourceDescribe.getType()) && !activeOptions(sourceDescribe).isEmpty()) {
                    expectedType = String.valueOf(sourceDescribe.getType());
                    expectedOptions = activeOptions(sourceDescribe);
                    if (String.isBlank(row.Field_Type_Override__c)) {
                        expectedInput = expectedInputType(sourceDescribe.getType());
                    }
                }
            }
        }
        if (row.Field_Type_Override__c == 'Dual Listbox') {
            expectedInput = 'dualListbox';
        } else if (row.Field_Type_Override__c == 'Radio') {
            expectedInput = 'radio';
        }
        Assert.areEqual(expectedType, meta.type, 'type ' + path);
        Assert.areEqual(expectedInput, meta.inputType, 'inputType ' + path);
        if (expectedOptions == null) {
            Assert.isTrue(meta.picklistOptions == null || meta.picklistOptions.isEmpty(), 'no options ' + path);
        } else {
            Assert.areEqual(expectedOptions, optionValues(meta.picklistOptions), 'options ' + path);
        }
    }

    private static String expectedBound(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String trimmed = raw.trim();
        return trimmed.equalsIgnoreCase('TODAY') ? String.valueOf(Date.today()) : trimmed;
    }
}