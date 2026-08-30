public with sharing class FieldDetailController {

    // Section label applied when a metadata row leaves Section_Name__c blank, so those fields
    // still group under a stable, single heading instead of an empty one.
    private static final String DEFAULT_SECTION_NAME = 'Other';

    // Ceiling applied to a Filter_Criteria__c query that sets no limit of its own. The options travel
    // to the client inside the schema and are held there in one in-memory list, so an unbounded filter
    // would break the response long before it broke the query.
    private static final Integer FILTER_CRITERIA_LIMIT = 2000;

    // Options resolved from Filter_Criteria__c, keyed by the criteria itself so one filter costs one
    // query per transaction however many rows or record types share it.
    private static Map<String, List<PicklistOption>> optionsByCriteria =
        new Map<String, List<PicklistOption>>();

    @AuraEnabled(cacheable=true)
    public static Map<String, List<FieldMetadata>> getFieldsByType(
        String objectName,
        String type
    ) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required');
        }

        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectName);

        if (objectType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }

        Map<String, Schema.SObjectField> fieldMap =
            objectType.getDescribe().fields.getMap();

        Map<String, List<FieldMetadata>> result =
            new Map<String, List<FieldMetadata>>();

        List<Envelope_Field__mdt> metadataFields = [
            SELECT
            Object__c,
            Section_Name__c,
            Field_API__c,
            Label__c,
            Required__c,
            Required_WHERE_Statement__c,
            Key_Decision__c,
            Order__c,
            Shown_WHERE_Statement__c,
            Field_Type_Override__c,
            Format__c,
            Pattern__c,
            Pattern_Error__c,
            Min__c,
            Max__c,
            Account_Type__c,
            Original_Account_Field__c
            FROM Envelope_Field__mdt
            WHERE Object__c =:objectName
            AND Type__c =: type
            ORDER BY Order__c
        ];
        for (Envelope_Field__mdt mdt : metadataFields) {

            if (String.isBlank(mdt.Field_API__c)) {
                continue;
            }

            if (!fieldMap.containsKey(mdt.Field_API__c)) {
                continue;
            }

            // Create section if it doesn't exist
            if (!result.containsKey(mdt.Section_Name__c)) {
                result.put(
                    mdt.Section_Name__c,
                    new List<FieldMetadata>()
                );
            }

            Schema.DescribeFieldResult describe =
                fieldMap.get(mdt.Field_API__c).getDescribe();

            FieldMetadata meta = buildFieldMetadata(
                describe,
                mdt,
                objectName
            );

            result.get(mdt.Section_Name__c).add(meta);
        }

        return result;
    }

    /**
     * Ordered form schema for the V2 action-details interview for a single record type. Returns
     * sections in first-seen order while iterating the Order__c-sorted records, with each section's
     * fields ordered the same way. Kept for the shell's lazy-load fallback; the WHERE also admits
     * add-record rows (which carry a blank Object__c) so they are not lost when fetched per type.
     */
    @AuraEnabled(cacheable=true)
    public static List<FormSection> getFormSchema(
        String objectName,
        String type
    ) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name is required');
        }

        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectName);

        if (objectType == null) {
            throw new AuraHandledException('Object not found: ' + objectName);
        }

        List<Envelope_Field__mdt> metadataFields = [
            SELECT
            Object__c,
            Type__c,
            Section_Name__c,
            Field_API__c,
            Label__c,
            Required__c,
            Required_WHERE_Statement__c,
            Order__c,
            Shown_WHERE_Statement__c,
            Add_Record__c,
            Add_Record_Type__c,
            Key_Decision__c,
            Field_Type_Override__c,
            Format__c,
            Pattern__c,
            Pattern_Error__c,
            Min__c,
            Max__c,
            Filter_Criteria__c,
            Account_Type__c,
            Original_Account_Field__c
            FROM Envelope_Field__mdt
            WHERE Type__c = :type
            ORDER BY Order__c NULLS LAST
        ];
        // Keep every row for the type: its fields may target more than one object (e.g. a Financial
        // Account interview whose Source-of-Funds questions are Case fields). Each field is described
        // against its own Object__c; add-record rows (blank Object__c) use the passed-in primary.
        Set<String> objectNames = new Set<String>{ objectName };
        for (Envelope_Field__mdt row : metadataFields) {
            if (String.isNotBlank(row.Object__c)) {
                objectNames.add(row.Object__c);
            }
        }
        Map<String, Map<String, Schema.SObjectField>> describeByObject =
            buildDescribeByObject(objectNames, new Map<String, Map<String, Schema.SObjectField>>());

        return buildSections(metadataFields, describeByObject, objectName);
    }

    /**
     * All configured form schemas in one call, so the shell can prefetch every record type up front.
     * Returns a map keyed 'Object__c|Type__c' (the shell's schema-cache key) to that type's ordered
     * sections. A type may map fields onto more than one object (e.g. Financial_Account__c and Case);
     * all rows are kept and each field is described against its own Object__c. A majority vote picks
     * the type's primary object (for add-record rows, which carry a blank Object__c), and the sections
     * are stored under every object present in the type so the client's lookup resolves whichever
     * object it keys on. Describe maps are cached once per object.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<FormSection>> getAllFormSchemas() {

        List<Envelope_Field__mdt> metadataFields = [
            SELECT
            Object__c,
            Type__c,
            Section_Name__c,
            Field_API__c,
            Label__c,
            Required__c,
            Required_WHERE_Statement__c,
            Order__c,
            Shown_WHERE_Statement__c,
            Add_Record__c,
            Add_Record_Type__c,
            Key_Decision__c,
            Field_Type_Override__c,
            Format__c,
            Pattern__c,
            Pattern_Error__c,
            Min__c,
            Max__c,
            Filter_Criteria__c,
            Account_Type__c,
            Original_Account_Field__c
            FROM Envelope_Field__mdt
            ORDER BY Type__c, Order__c NULLS LAST
        ];

        // Pass 1: rows grouped by type, and per-type object vote (add-record rows have no object).
        Map<String, List<Envelope_Field__mdt>> rowsByType =
            new Map<String, List<Envelope_Field__mdt>>();
        Map<String, Map<String, Integer>> objectVotesByType =
            new Map<String, Map<String, Integer>>();

        for (Envelope_Field__mdt mdt : metadataFields) {
            if (String.isBlank(mdt.Type__c)) {
                continue;
            }
            if (!rowsByType.containsKey(mdt.Type__c)) {
                rowsByType.put(mdt.Type__c, new List<Envelope_Field__mdt>());
                objectVotesByType.put(mdt.Type__c, new Map<String, Integer>());
            }
            rowsByType.get(mdt.Type__c).add(mdt);

            if (String.isNotBlank(mdt.Object__c)) {
                Map<String, Integer> votes = objectVotesByType.get(mdt.Type__c);
                Integer current = votes.containsKey(mdt.Object__c) ? votes.get(mdt.Object__c) : 0;
                votes.put(mdt.Object__c, current + 1);
            }
        }

        // Pass 2: build each type's sections once and store them under its schema-cache key(s). The
        // vote resolves the primary object (add-record rows and the key guarantee); all rows are kept
        // and each field is described against its own Object__c. The sections are stored under every
        // object present in the type so the client's 'Object__c|Type__c' lookup resolves for a mixed
        // type regardless of which object it keys on.
        Map<String, List<FormSection>> schemas = new Map<String, List<FormSection>>();
        Map<String, Map<String, Schema.SObjectField>> fieldMapCache =
            new Map<String, Map<String, Schema.SObjectField>>();

        for (String recordType : rowsByType.keySet()) {
            String primaryObject = resolveObjectName(objectVotesByType.get(recordType));
            if (String.isBlank(primaryObject)) {
                continue;
            }

            List<Envelope_Field__mdt> rows = rowsByType.get(recordType);

            Set<String> objectNames = new Set<String>{ primaryObject };
            for (Envelope_Field__mdt mdt : rows) {
                if (String.isNotBlank(mdt.Object__c)) {
                    objectNames.add(mdt.Object__c);
                }
            }
            Map<String, Map<String, Schema.SObjectField>> describeByObject =
                buildDescribeByObject(objectNames, fieldMapCache);

            List<FormSection> sections = buildSections(rows, describeByObject, primaryObject);
            for (String objectName : objectNames) {
                schemas.put(objectName + '|' + recordType, sections);
            }
        }

        return schemas;
    }

    /**
     * Section layout per record type: how the flat form sections group under ordered parent sections.
     * Returns a map keyed by Type__c to that type's parent groups (ordered by Parent_Section_Order__c),
     * each listing its child section names (ordered by Order__c). The child names match
     * Envelope_Field__mdt.Section_Name__c, so the client joins the flat schema to this layout. A type
     * with no Section__mdt rows is absent from the map (client renders a single default group).
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<SectionGroup>> getSectionLayouts() {

        List<Section__mdt> rows = [
            SELECT
            Type__c,
            Parent_Section_Name__c,
            Parent_Section_Order__c,
            Child_Section_Name__c,
            Order__c
            FROM Section__mdt
            ORDER BY Type__c, Parent_Section_Order__c NULLS LAST, Order__c NULLS LAST
        ];

        Map<String, List<SectionGroup>> layoutsByType = new Map<String, List<SectionGroup>>();
        Map<String, SectionGroup> groupByTypeParent = new Map<String, SectionGroup>();

        for (Section__mdt row : rows) {
            if (String.isBlank(row.Type__c) || String.isBlank(row.Child_Section_Name__c)) {
                continue;
            }

            String parentKey = row.Type__c + '|' + row.Parent_Section_Name__c;
            SectionGroup grp = groupByTypeParent.get(parentKey);
            if (grp == null) {
                grp = new SectionGroup();
                grp.parentName = row.Parent_Section_Name__c;
                grp.parentOrder = row.Parent_Section_Order__c;
                grp.childSections = new List<String>();
                groupByTypeParent.put(parentKey, grp);

                if (!layoutsByType.containsKey(row.Type__c)) {
                    layoutsByType.put(row.Type__c, new List<SectionGroup>());
                }
                // Rows are ordered by Parent_Section_Order__c, so parents append in display order.
                layoutsByType.get(row.Type__c).add(grp);
            }
            // Rows are ordered by Order__c within a parent, so children append in display order.
            grp.childSections.add(row.Child_Section_Name__c);
        }

        return layoutsByType;
    }

    // The object with the most rows for a type wins; a lone or unanimous object is returned directly.
    private static String resolveObjectName(Map<String, Integer> votes) {
        String winner = null;
        Integer best = -1;
        for (String objectName : votes.keySet()) {
            if (votes.get(objectName) > best) {
                best = votes.get(objectName);
                winner = objectName;
            }
        }
        return winner;
    }

    /**
     * Build ordered sections from a type's metadata rows against the object's field map. Add-record
     * rows become synthetic fields (they drive a create-nested-record control, not a bound field);
     * blank/unknown fields are skipped; a blank section name falls back to a default; and a field
     * that repeats within the type under the same visibility condition is kept only once (first
     * wins). The same field under different conditions is kept once per condition — those are
     * deliberate variants of one question, and the client shows whichever one's condition holds.
     */
    private static List<FormSection> buildSections(
        List<Envelope_Field__mdt> rows,
        Map<String, Map<String, Schema.SObjectField>> describeByObject,
        String primaryObject
    ) {
        Map<String, FormSection> sectionsByName = new Map<String, FormSection>();
        List<FormSection> sections = new List<FormSection>();
        Set<String> seenFieldPaths = new Set<String>();

        for (Envelope_Field__mdt mdt : rows) {

            // Add-record rows carry a blank Object__c and belong to the type's primary object; every
            // other row is described (and later written/read) against its own Object__c.
            String rowObject = String.isNotBlank(mdt.Object__c) ? mdt.Object__c : primaryObject;

            FieldMetadata meta;

            if (mdt.Add_Record__c == true) {
                meta = buildAddRecordMetadata(mdt);
            } else {
                Map<String, Schema.SObjectField> fieldMap = describeByObject.get(rowObject);
                if (fieldMap == null
                    || String.isBlank(mdt.Field_API__c)
                    || !fieldMap.containsKey(mdt.Field_API__c)) {
                    continue;
                }
                Schema.DescribeFieldResult describe =
                    fieldMap.get(mdt.Field_API__c).getDescribe();
                meta = buildFieldMetadata(describe, mdt, rowObject);
            }

            meta.objectApiName = rowObject;

            // Dedup is object-qualified: a field API name can legitimately exist on both objects of a
            // mixed type, so keying on the path alone would silently drop the second one.
            //
            // The visibility condition is part of the key because one field can be configured more
            // than once for a type, each row offering a different set of choices under a different
            // condition (e.g. a product picker whose candidates depend on the source of funds). Those
            // rows differ only by their WHERE, so keying without it would drop all but one and leave
            // the field missing entirely for every condition but the survivor's. Two rows sharing a
            // field AND a condition are still a genuine duplicate, and still collapse.
            //
            // Account_Type__c is part of the key for the same reason: an account-type-partitioned
            // type (Proposed Changes) legitimately configures one field once per account type
            // (e.g. Entity Type for both Business and Trust), and the client filters by account
            // type after the fact — so collapsing those rows would drop the field for every
            // account type but the survivor's. The key carries the normalized value: a blank row
            // is served as Person, so a blank row and an explicit Person row address the same
            // audience and must still collapse as duplicates.
            String dedupKey = rowObject + '|' + meta.fieldPath + '|'
                + normalizedAccountType(mdt) + '|' + mdt.Shown_WHERE_Statement__c;
            if (seenFieldPaths.contains(dedupKey)) {
                continue;
            }
            seenFieldPaths.add(dedupKey);

            // After the dedup, so a row that was dropped never costs a query.
            applyFilterCriteria(meta, mdt);

            String sectionName = String.isNotBlank(mdt.Section_Name__c)
                ? mdt.Section_Name__c
                : DEFAULT_SECTION_NAME;

            FormSection section = sectionsByName.get(sectionName);
            if (section == null) {
                section = new FormSection(sectionName);
                sectionsByName.put(sectionName, section);
                sections.add(section);
            }

            section.fields.add(meta);
        }

        return sections;
    }

    // Describe maps for a set of object API names, one entry per describable object, reusing a shared
    // cache so each object is described only once per request. Names that aren't describable are
    // omitted (their rows are then skipped by buildSections).
    private static Map<String, Map<String, Schema.SObjectField>> buildDescribeByObject(
        Set<String> objectNames,
        Map<String, Map<String, Schema.SObjectField>> cache
    ) {
        Map<String, Map<String, Schema.SObjectField>> result =
            new Map<String, Map<String, Schema.SObjectField>>();
        for (String objectName : objectNames) {
            if (String.isBlank(objectName)) {
                continue;
            }
            Map<String, Schema.SObjectField> fieldMap = cache.get(objectName);
            if (fieldMap == null) {
                Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
                if (objectType == null) {
                    continue;
                }
                fieldMap = objectType.getDescribe().fields.getMap();
                cache.put(objectName, fieldMap);
            }
            result.put(objectName, fieldMap);
        }
        return result;
    }

    // Synthetic metadata for an add-record row: it has no bound SObject field, so it carries its own
    // synthetic path and a distinct type/inputType the UI routes to a create-nested-record control.
    private static FieldMetadata buildAddRecordMetadata(Envelope_Field__mdt mdt) {
        FieldMetadata meta = new FieldMetadata();
        String recordType = String.isNotBlank(mdt.Add_Record_Type__c) ? mdt.Add_Record_Type__c : '';
        meta.label = String.isNotBlank(mdt.Label__c) ? mdt.Label__c : recordType;
        meta.fieldPath = 'AddRecord_' + recordType.replaceAll('[^A-Za-z0-9]', '');
        meta.type = 'ADD_RECORD';
        meta.inputType = 'addRecord';
        meta.required = mdt.Required__c;
        meta.requiredWhereStatement = mdt.Required_WHERE_Statement__c;
        meta.shownWhereStatement = mdt.Shown_WHERE_Statement__c;
        meta.keyDecision = mdt.Key_Decision__c;
        meta.addRecord = true;
        meta.addRecordType = mdt.Add_Record_Type__c;
        return meta;
    }

    // Account_Type__c defaults to Person, so a blank row and an explicit Person row address the
    // same audience. Every reading of the field goes through this so the dedup key and the served
    // accountType can never disagree about that.
    private static String normalizedAccountType(Envelope_Field__mdt mdt) {
        return String.isNotBlank(mdt.Account_Type__c) ? mdt.Account_Type__c : 'Person';
    }

    /**
     * Turn a row's Filter_Criteria__c into the field's selectable options.
     *
     * A lookup has no values of its own, so the records it may point at have to be fetched. Where that
     * set is a fixed rule it is configured as a query on the row, which is what this runs. The field is
     * then presented as a single-select over those records: the shape the client already renders and
     * formats, with the record id as each option's value. referenceTo still names the object the value
     * belongs to, so nothing loses track of what the stored value is.
     *
     * Resolving here rather than sending options to the client separately is deliberate. One field can
     * be configured several times for a type, each row filtering differently, and those rows are
     * indistinguishable to the client — it knows a field only by its object and API name. Only this
     * loop can tell them apart, so the options are attached to the row while that is still possible.
     *
     * A query returning nothing leaves the field untouched: an empty option list reads as a select
     * that cannot be answered, whereas a lookup with no options at all is reported by the client as an
     * unsupported field, which is the honest signal that its records did not resolve.
     */
    private static void applyFilterCriteria(FieldMetadata meta, Envelope_Field__mdt mdt) {
        if (String.isBlank(mdt.Filter_Criteria__c)) {
            return;
        }

        List<PicklistOption> options = filterCriteriaOptions(mdt.Filter_Criteria__c.trim());
        if (options.isEmpty()) {
            return;
        }

        meta.picklistOptions = options;
        meta.type = 'PICKLIST';
        meta.inputType = 'select';
    }

    private static List<PicklistOption> filterCriteriaOptions(String criteria) {
        if (optionsByCriteria.containsKey(criteria)) {
            return optionsByCriteria.get(criteria);
        }

        List<PicklistOption> options = new List<PicklistOption>();
        try {
            List<String> selected = selectedFieldsOf(criteria);
            if (selected.isEmpty()) {
                throw new QueryException('No selected fields in: ' + criteria);
            }
            // The first selected field is the stored value and the second is what the user reads; a
            // query naming only one field uses it for both.
            String valueField = selected[0];
            String labelField = selected.size() > 1 ? selected[1] : selected[0];

            String soql = criteria.containsIgnoreCase(' LIMIT ')
                ? criteria
                : criteria + ' LIMIT ' + FILTER_CRITERIA_LIMIT;

            for (SObject record : Database.query(soql, AccessLevel.USER_MODE)) {
                options.add(new PicklistOption(
                    String.valueOf(record.get(labelField)),
                    String.valueOf(record.get(valueField))
                ));
            }
        } catch (Exception e) {
            // One unusable filter costs its own field its options; every other field, and every other
            // record type in the same request, still builds.
            System.debug(LoggingLevel.ERROR,
                'Filter criteria failed [' + criteria + ']: ' + e.getMessage());
        }

        optionsByCriteria.put(criteria, options);
        return options;
    }

    // The field names a query selects, in order, read from between SELECT and FROM.
    private static List<String> selectedFieldsOf(String soql) {
        String upper = soql.toUpperCase();
        Integer selectAt = upper.indexOf('SELECT ');
        Integer fromAt = upper.indexOf(' FROM ');
        List<String> fields = new List<String>();
        if (selectAt < 0 || fromAt <= selectAt) {
            return fields;
        }
        for (String part : soql.substring(selectAt + 7, fromAt).split(',')) {
            if (String.isNotBlank(part)) {
                fields.add(part.trim());
            }
        }
        return fields;
    }

    private static FieldMetadata buildFieldMetadata(
        Schema.DescribeFieldResult describe,
        Envelope_Field__mdt mdt,
        String objectApiName
    ) {

        FieldMetadata meta = new FieldMetadata();

        meta.label = String.isNotBlank(mdt.Label__c)
            ? mdt.Label__c
            : describe.getLabel();

        meta.fieldPath = mdt.Field_API__c;

        meta.type = String.valueOf(describe.getType());

        meta.inputType = determineInputType(describe);

        // A configured Field Type Override wins over the type default (a multi-select picklist renders
        // as a checkbox group, a single-select as radio/select): 'Dual Listbox' opts a multi-select
        // field back into the two-pane picker, 'Radio' forces a radio group. Per Envelope_Field__mdt.
        if (mdt.Field_Type_Override__c == 'Dual Listbox') {
            meta.inputType = 'dualListbox';
        } else if (mdt.Field_Type_Override__c == 'Radio') {
            meta.inputType = 'radio';
        }

        // Requiredness comes from Custom Metadata
        meta.required = mdt.Required__c;

        meta.requiredWhereStatement = mdt.Required_WHERE_Statement__c;

        meta.shownWhereStatement = mdt.Shown_WHERE_Statement__c;

        meta.keyDecision = mdt.Key_Decision__c;

        // The picklist default is applied server-side so the client can tell "no restriction
        // known" (property absent, schema served by an older version) from an authoritative
        // account type — a blank row means Person, per the field's default.
        meta.accountType = normalizedAccountType(mdt);

        meta.originalAccountField = mdt.Original_Account_Field__c;

        meta.maxLength = describe.getLength();
        meta.scale = describe.getScale();
        meta.precision = describe.getPrecision();

        // Format/bounds config from Envelope_Field__mdt. A named Format__c resolves its pattern,
        // message, and client-side input mask from the shared library; raw Pattern__c is the
        // escape hatch for one-off fields. Pattern applies only when the control is a text-family
        // input (the LWC guards the binding); Min/Max apply to number and date controls.
        // On a multi-select, Max caps how many options may be chosen instead of the value range.
        meta.pattern = mdt.Pattern__c;
        meta.patternError = mdt.Pattern_Error__c;
        if (String.isNotBlank(mdt.Format__c)
            && WizardFieldValidator.FORMATS.containsKey(mdt.Format__c)) {
            WizardFieldValidator.FormatDef def = WizardFieldValidator.FORMATS.get(mdt.Format__c);
            meta.format = mdt.Format__c;
            meta.pattern = def.pattern;
            meta.patternError = def.errorMessage;
        }
        if (describe.getType() == Schema.DisplayType.MULTIPICKLIST) {
            if (String.isNotBlank(mdt.Max__c) && mdt.Max__c.trim().isNumeric()) {
                meta.maxSelections = Integer.valueOf(mdt.Max__c.trim());
            }
        } else {
            meta.minValue = resolveBound(mdt.Min__c);
            meta.maxValue = resolveBound(mdt.Max__c);
        }

        // A lookup's candidate records can't come from the describe the way picklist values do, so
        // record the object they must be queried from. A field pointing at several objects is
        // polymorphic (e.g. Task.WhatId); the interview only supports the first, which is the whole
        // target for every single-object lookup.
        if (describe.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> references = describe.getReferenceTo();
            if (!references.isEmpty()) {
                meta.referenceTo = String.valueOf(references[0]);
            }
        }

        if (
            describe.getType() == Schema.DisplayType.PICKLIST ||
            describe.getType() == Schema.DisplayType.MULTIPICKLIST
        ) {

            meta.picklistOptions = new List<PicklistOption>();

            for (Schema.PicklistEntry entry :
                 describe.getPicklistValues()) {

                     if (entry.isActive()) {
                         meta.picklistOptions.add(
                             new PicklistOption(
                                 entry.getLabel(),
                                 entry.getValue()
                             )
                         );
                     }
                 }
        }

        // A change-request row (e.g. Proposed Changes) binds a plain-text Case field standing in
        // for an Account field, so its own describe carries no options. When the Account source
        // field is a picklist, serve its options and control type instead, so the interview
        // renders the same control the member's own form does rather than degrading to free text.
        if ((meta.picklistOptions == null || meta.picklistOptions.isEmpty())
            && String.isNotBlank(mdt.Original_Account_Field__c)) {
            applySourceFieldPresentation(meta, mdt);
        }

        return meta;
    }

    /**
     * Copy a picklist Account source field's presentation onto a text field that stands in for it:
     * active options, type, and — unless the row configures its own override — the input control.
     * A source that is not an Account field, or not a picklist, leaves the field untouched (a bad
     * source name is a metadata data problem; the field still renders, as text).
     */
    private static void applySourceFieldPresentation(FieldMetadata meta, Envelope_Field__mdt mdt) {
        Map<String, Schema.SObjectField> accountFields =
            Account.SObjectType.getDescribe().fields.getMap();
        String sourceApi = mdt.Original_Account_Field__c.trim();
        if (!accountFields.containsKey(sourceApi)) {
            return;
        }

        Schema.DescribeFieldResult source = accountFields.get(sourceApi).getDescribe();
        if (source.getType() != Schema.DisplayType.PICKLIST
            && source.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return;
        }

        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : source.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        if (options.isEmpty()) {
            return;
        }

        meta.picklistOptions = options;
        meta.type = String.valueOf(source.getType());
        if (String.isBlank(mdt.Field_Type_Override__c)) {
            meta.inputType = determineInputType(source);
        }
    }

    // Live record values for the fields a type's interview edits, so record-backed entities
    // prefill from the record rather than only the envelope-state blob. The read set is driven by
    // the same Envelope_Field__mdt rows that drive the form, so it always matches the interview.
    // Returns record id -> { fieldApiName: value } (null values omitted); empty map on bad input.
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getRecordValuesForType(
        String objectName,
        String type,
        List<Id> recordIds
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (String.isBlank(objectName) || String.isBlank(type)
            || recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null) {
            return result;
        }
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        List<Envelope_Field__mdt> rows = [
            SELECT Field_API__c
            FROM Envelope_Field__mdt
            WHERE Object__c = :objectName
            AND Type__c = :type
        ];
        Set<String> fieldApis = new Set<String>();
        for (Envelope_Field__mdt row : rows) {
            if (String.isNotBlank(row.Field_API__c) && fieldMap.containsKey(row.Field_API__c)) {
                fieldApis.add(row.Field_API__c);
            }
        }
        if (fieldApis.isEmpty()) {
            return result;
        }

        String soql = 'SELECT Id, ' + String.join(new List<String>(fieldApis), ', ')
            + ' FROM ' + String.escapeSingleQuotes(objectName)
            + ' WHERE Id IN :recordIds';
        for (SObject record : Database.query(soql)) {
            Map<String, Object> values = new Map<String, Object>();
            for (String fieldApi : fieldApis) {
                Object value = record.get(fieldApi);
                if (value != null) {
                    values.put(fieldApi, value);
                }
            }
            result.put(record.Id, values);
        }
        return result;
    }

    // The member's current Account values for a change-request type, keyed by the CASE field that
    // proposes each change. Envelope_Field__mdt maps the type's Case fields to their Account
    // source via Original_Account_Field__c; this reads the sources off the Account and re-keys
    // them, so the interview can show the current data on load and mark what an edit changed.
    //
    // Returns account id -> { proposedCaseFieldApi: currentAccountValue }, nulls INCLUDED — a
    // blank source value must read as "currently empty", not "untracked" (same contract as
    // getOriginalCaseValues). Rows whose source is not a real Account field are skipped (known
    // metadata data errors must not fail the whole read); when two rows share a Case field
    // (one per account type), the first valid source wins — they name the same source or the
    // duplicate is itself a data error. Person-only sources select as null on non-person
    // Accounts, which the client's baseline lookup ignores.
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getOriginalAccountValues(
        String type,
        List<Id> accountIds
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (String.isBlank(type) || accountIds == null || accountIds.isEmpty()) {
            return result;
        }

        Map<String, Schema.SObjectField> accountFields =
            Account.SObjectType.getDescribe().fields.getMap();

        Map<String, String> sourceByProposed = new Map<String, String>();
        for (Envelope_Field__mdt row : [
            SELECT Field_API__c, Original_Account_Field__c
            FROM Envelope_Field__mdt
            WHERE Type__c = :type
            AND Field_API__c != null
            AND Original_Account_Field__c != null
        ]) {
            String source = row.Original_Account_Field__c.trim();
            if (!accountFields.containsKey(source)) {
                System.debug(LoggingLevel.WARN, 'getOriginalAccountValues: "' + source
                    + '" (source of ' + row.Field_API__c + ') is not an Account field; skipped.');
                continue;
            }
            if (!sourceByProposed.containsKey(row.Field_API__c)) {
                // The describe's own casing, so case variants of one field can't produce a
                // duplicate in the SELECT list below.
                sourceByProposed.put(row.Field_API__c,
                    accountFields.get(source).getDescribe().getName());
            }
        }
        if (sourceByProposed.isEmpty()) {
            return result;
        }

        Set<String> selectFields = new Set<String>{ 'Id' };
        selectFields.addAll(sourceByProposed.values());
        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
            + ' FROM Account WHERE Id IN :accountIds';
        for (SObject record : Database.query(soql)) {
            Map<String, Object> values = new Map<String, Object>();
            for (String proposedField : sourceByProposed.keySet()) {
                values.put(proposedField, record.get(sourceByProposed.get(proposedField)));
            }
            result.put(record.Id, values);
        }
        return result;
    }

    // getRecordValuesForType's counterpart for the Case half of a mixed account interview: an
    // interview type whose rows target both Financial_Account__c and Case reads its Case-targeted
    // values from the account's wizard Case, so those answers prefill from the record like every
    // other field rather than only from the envelope-state blob.
    //
    // Keyed by FINANCIAL ACCOUNT id, not Case id, so the result drops straight into the client's
    // per-account value map alongside the Financial_Account__c values. Returns an empty map for a
    // type with no Case rows configured (e.g. an interview that targets one object).
    //
    // Every configured field is returned, null values included, so the Case is the exact source of
    // truth for its half of the form: a value cleared on the record clears in the interview instead
    // of the stale envelope-blob value showing through the overlay and being written back.
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getCaseValuesForAccounts(
        String type,
        List<Id> financialAccountIds
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (String.isBlank(type) || financialAccountIds == null || financialAccountIds.isEmpty()) {
            return result;
        }

        Map<String, Schema.SObjectField> fieldMap =
            Case.SObjectType.getDescribe().fields.getMap();

        List<Envelope_Field__mdt> rows = [
            SELECT Field_API__c
            FROM Envelope_Field__mdt
            WHERE Object__c = 'Case'
            AND Type__c = :type
        ];
        Set<String> fieldApis = new Set<String>();
        for (Envelope_Field__mdt row : rows) {
            if (String.isNotBlank(row.Field_API__c) && fieldMap.containsKey(row.Field_API__c)) {
                fieldApis.add(row.Field_API__c);
            }
        }
        if (fieldApis.isEmpty()) {
            return result;
        }

        // The account lookup keys the result, so it is always selected — through the same set as the
        // configured fields, since selecting it twice would fail the query outright.
        Set<String> selectFields = new Set<String>{ 'Wizard_Financial_Account__c' };
        selectFields.addAll(fieldApis);

        String origin = WizardEnvelopeStateService.WIZARD_CASE_ORIGIN;
        String caseType = WizardEnvelopeStateService.ACCOUNT_OPENING_CASE_TYPE;
        // Oldest first, and the first row per account wins: an account should only ever have one
        // wizard Case, but nothing enforces that, and the write side resolves the same record the
        // same way — so a duplicate can never leave the two halves editing different Cases.
        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
            + ' FROM Case'
            + ' WHERE Wizard_Financial_Account__c IN :financialAccountIds'
            + ' AND Origin = :origin'
            + ' AND Type = :caseType'
            + ' ORDER BY CreatedDate ASC';
        for (SObject record : Database.query(soql)) {
            Id faId = (Id) record.get('Wizard_Financial_Account__c');
            if (result.containsKey(faId)) {
                continue;
            }
            Map<String, Object> values = new Map<String, Object>();
            for (String fieldApi : fieldApis) {
                values.put(fieldApi, record.get(fieldApi));
            }
            result.put(faId, values);
        }
        return result;
    }

    /**
     * getCaseValuesForAccounts' counterpart for the product an account's interview selected. That
     * answer is a related record rather than a field on the account, so the account read never sees
     * it and it needs its own.
     *
     * Keyed by Financial Account id, so the result merges into the same per-account value map as the
     * account and Case values. Every requested account gets an entry, with null where no row exists:
     * the row is the only place this answer lives, so an account whose product was cleared has to come
     * back cleared rather than keeping whatever the interview last showed.
     *
     * Resolves the same row as WizardEnvelopeStateService.saveRelatedProduct — the wizard is the only
     * path that creates these rows, so Wizard_Financial_Account__c alone resolves it, oldest first,
     * first per account wins.
     */
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getRelatedProductValuesForAccounts(
        String type,
        List<Id> financialAccountIds
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (String.isBlank(type) || financialAccountIds == null || financialAccountIds.isEmpty()) {
            return result;
        }

        String relatedProductObject = WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT;
        Set<String> fieldApis = new Set<String>();
        for (Envelope_Field__mdt row : [
            SELECT Field_API__c
            FROM Envelope_Field__mdt
            WHERE Object__c = :relatedProductObject
            AND Type__c = :type
        ]) {
            if (String.isNotBlank(row.Field_API__c)) {
                fieldApis.add(row.Field_API__c);
            }
        }
        if (fieldApis.isEmpty()) {
            return result;
        }

        for (Id accountId : financialAccountIds) {
            Map<String, Object> values = new Map<String, Object>();
            for (String fieldApi : fieldApis) {
                values.put(fieldApi, null);
            }
            result.put(accountId, values);
        }

        Set<Id> resolved = new Set<Id>();
        for (Financial_Account_Related_Product__c row : [
            SELECT Wizard_Financial_Account__c, Product__c
            FROM Financial_Account_Related_Product__c
            WHERE Wizard_Financial_Account__c IN :financialAccountIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!resolved.add(row.Wizard_Financial_Account__c)) {
                continue;
            }
            Map<String, Object> values = result.get(row.Wizard_Financial_Account__c);
            for (String fieldApi : fieldApis) {
                values.put(fieldApi, row.Product__c);
            }
        }

        return result;
    }

    /**
     * getRelatedProductValuesForAccounts' counterpart for Account Action Items: the product each
     * action's interview selected, keyed by the action's Case rather than the Financial Account.
     *
     * An action's product row is scoped to its own Case (see
     * WizardEnvelopeStateService.saveActionRelatedProduct), so it must be read by Case too — reading by
     * Financial Account (as the account-opening path does) would return the account's opening product
     * instead. Returns caseId -> { fieldApiName: productId }, with the schema's product field(s) seeded
     * null so a cleared selection prefills cleared rather than keeping the interview's last value.
     */
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getActionRelatedProductValues(
        String type,
        List<Id> caseIds
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (String.isBlank(type) || caseIds == null || caseIds.isEmpty()) {
            return result;
        }

        String relatedProductObject = WizardEnvelopeStateService.RELATED_PRODUCT_OBJECT;
        Set<String> fieldApis = new Set<String>();
        for (Envelope_Field__mdt row : [
            SELECT Field_API__c
            FROM Envelope_Field__mdt
            WHERE Object__c = :relatedProductObject
            AND Type__c = :type
        ]) {
            if (String.isNotBlank(row.Field_API__c)) {
                fieldApis.add(row.Field_API__c);
            }
        }
        if (fieldApis.isEmpty()) {
            return result;
        }

        for (Id caseId : caseIds) {
            Map<String, Object> values = new Map<String, Object>();
            for (String fieldApi : fieldApis) {
                values.put(fieldApi, null);
            }
            result.put(caseId, values);
        }

        Set<Id> resolved = new Set<Id>();
        for (Financial_Account_Related_Product__c row : [
            SELECT Case__c, Product__c
            FROM Financial_Account_Related_Product__c
            WHERE Case__c IN :caseIds
            ORDER BY CreatedDate ASC
        ]) {
            if (row.Case__c == null || !resolved.add(row.Case__c)) {
                continue;
            }
            Map<String, Object> values = result.get(row.Case__c);
            for (String fieldApi : fieldApis) {
                values.put(fieldApi, row.Product__c);
            }
        }

        return result;
    }

    // TODAY is the only supported token in Min__c/Max__c; anything else (decimal literal, ISO date)
    // passes through verbatim for the client to bind directly.
    private static String resolveBound(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String trimmed = raw.trim();
        return trimmed.equalsIgnoreCase('TODAY') ? String.valueOf(Date.today()) : trimmed;
    }

    private static String determineInputType(
        Schema.DescribeFieldResult fieldDescribe
    ) {

        switch on fieldDescribe.getType() {

            when STRING, TEXTAREA, ID {
                return 'text';
            }

            when EMAIL {
                return 'email';
            }

            when PHONE {
                return 'tel';
            }

            when URL {
                return 'url';
            }

            when DATE {
                return 'date';
            }

            when DATETIME {
                return 'datetime';
            }

            when TIME {
                return 'time';
            }

            when INTEGER,
                LONG,
                DOUBLE,
                CURRENCY,
                PERCENT {
                    return 'number';
                }

            when BOOLEAN {
                return 'checkbox';
            }

            when PICKLIST {
                return 'combobox';
            }

            when MULTIPICKLIST {
                return 'checkboxGroup';
            }

            when else {
                return 'text';
            }
        }
    }

    public class FormSection {

        @AuraEnabled
        public String name;

        @AuraEnabled
        public List<FieldMetadata> fields;

        public FormSection(String name) {
            this.name = name;
            this.fields = new List<FieldMetadata>();
        }
    }

    public class SectionGroup {

        @AuraEnabled
        public String parentName;

        @AuraEnabled
        public Decimal parentOrder;

        // Child section names in display order; each matches an Envelope_Field__mdt Section_Name__c.
        @AuraEnabled
        public List<String> childSections;
    }

    public class FieldMetadata {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String fieldPath;

        // Target SObject API name this field is written to / read from. A single interview type can
        // map fields onto more than one object (e.g. Financial_Account__c and Case), so the client
        // uses this to route each field to the right record. (Not named 'object' — reserved in Apex.)
        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String type;

        // Target SObject of a lookup field, from the field's describe. Null for every other type.
        // A lookup carries no values of its own, so the candidate records are supplied separately
        // (see EnvelopeLookupOptionController); this names the object they come from.
        @AuraEnabled
        public String referenceTo;

        @AuraEnabled
        public String inputType;

        @AuraEnabled
        public Boolean required;

        @AuraEnabled
        public String requiredWhereStatement;

        @AuraEnabled
        public Boolean keyDecision;

        @AuraEnabled
        public Boolean addRecord;

        @AuraEnabled
        public String addRecordType;

        @AuraEnabled
        public Integer maxLength;

        @AuraEnabled
        public Integer scale;

        @AuraEnabled
        public Integer precision;

        @AuraEnabled
        public List<PicklistOption> picklistOptions;

        @AuraEnabled
        public String shownWhereStatement;

        // Which account type's interview shows this field, for types partitioned by account type
        // (Proposed Changes): Person covers individual members and every related party; Business,
        // Trust and Retirement Plan match their entity kind. Normalized server-side — a blank row
        // is served as Person (the picklist default), so a present value is always authoritative.
        @AuraEnabled
        public String accountType;

        // Account field API name this field proposes a change to. Names where the current value
        // is read from on load (see getOriginalAccountValues) and, when that source field is a
        // picklist, where the options come from. Null for fields with no Account counterpart.
        @AuraEnabled
        public String originalAccountField;

        @AuraEnabled
        public String format;

        @AuraEnabled
        public String pattern;

        @AuraEnabled
        public String patternError;

        @AuraEnabled
        public String minValue;

        @AuraEnabled
        public String maxValue;

        @AuraEnabled
        public Integer maxSelections;
    }

    public class PicklistOption {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public PicklistOption(
            String label,
            String value
        ) {
            this.label = label;
            this.value = value;
        }
    }
}