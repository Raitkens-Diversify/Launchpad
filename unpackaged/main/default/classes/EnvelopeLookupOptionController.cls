/**
 * Candidate records for the interview's lookup fields.
 *
 * A lookup carries no values of its own: its describe yields the target object but not the records,
 * so unlike a picklist it needs an option source. This class is that source. Each entry is keyed
 * 'Object__c|Field_API__c' — the field an Envelope_Field__mdt row names — and supplies the criteria
 * that narrow the target object's records. The target object itself is never configured; it is read
 * from the field's describe.
 *
 * Criteria that depend on who is being served — the household's accounts, this envelope's records —
 * can only be resolved at run time, so they are written as a query with named binds and the binds
 * are supplied per call.
 *
 * Criteria may also be declared on the field itself as a lookup filter, and those cannot be read
 * back: Schema.DescribeFieldResult exposes whether a field is filtered, never the filter. Such a
 * field has to have its criteria written out here instead, and nothing detects it when the two drift
 * apart — a lookup filter and its entry here have to be changed together.
 *
 * Queries run in user mode, so a field used in the criteria needs field-level read access for the
 * running user. Without it the query fails with "No such column" rather than an access error.
 */
public with sharing class EnvelopeLookupOptionController {

    // Ceiling on any one option list. The client renders these as a single in-memory select, so a
    // source that can exceed this needs a searching control rather than a longer list.
    private static final Integer DEFAULT_LIMIT = 2000;

    private static final String HOUSEHOLD_BIND = 'householdId';
    private static final String ENVELOPE_BIND = 'envelopeId';

    private class LookupSource {
        String criteria;
        String labelField = 'Name';
        String orderBy = 'Name';
        Integer recordLimit = DEFAULT_LIMIT;
        // Binds the criteria reference. A source whose binds aren't all supplied is skipped rather
        // than run unscoped.
        Set<String> requiredBinds = new Set<String>();
    }

    private static final Map<String, LookupSource> SOURCES = new Map<String, LookupSource>{
        // Case.AA_Account_Number_Wizard__c -> Financial_Account__c. Answers "which advisory account
        // is already at the firm?", so the candidates are the household's accounts.
        //
        // The accounts the envelope in context is opening are deliberately NOT excluded. Narrowing to
        // pre-existing accounts left a household whose only account is the one being opened with
        // nothing to choose, and an empty list makes a required lookup unanswerable rather than
        // merely imprecise. The cost is that an account can be offered as its own source of funds.
        'Case|AA_Account_Number_Wizard__c' => source(
            'Household__c = :' + HOUSEHOLD_BIND,
            new Set<String>{ HOUSEHOLD_BIND }
        )
    };

    private static LookupSource source(String criteria, Set<String> requiredBinds) {
        LookupSource result = new LookupSource();
        result.criteria = criteria;
        result.requiredBinds = requiredBinds;
        return result;
    }

    /**
     * Options for every configured lookup, keyed 'Object__c|Field_API__c' to match the schema rows
     * the client holds. A source is omitted rather than returned empty: on the client an empty list
     * reads as a select with nothing to choose, which would leave a required lookup unanswerable,
     * whereas an absent key leaves the field visibly unsupported — the signal that it still needs a
     * source.
     *
     * @param householdId  household whose records scope the household-bound sources; may be null
     * @param envelopeId   envelope in context, for sources scoped to it; may be null
     */
    @AuraEnabled
    public static Map<String, List<FieldDetailController.PicklistOption>> getLookupOptions(
        Id householdId,
        Id envelopeId
    ) {
        Map<String, List<FieldDetailController.PicklistOption>> options =
            new Map<String, List<FieldDetailController.PicklistOption>>();

        Map<String, Object> binds = new Map<String, Object>{
            HOUSEHOLD_BIND => householdId,
            ENVELOPE_BIND => envelopeId
        };

        for (String key : SOURCES.keySet()) {
            LookupSource entry = SOURCES.get(key);

            if (!bindsSatisfied(entry, binds)) {
                System.debug(LoggingLevel.WARN,
                    'Lookup source skipped, binds unavailable: ' + key);
                continue;
            }

            List<FieldDetailController.PicklistOption> resolved = resolve(key, entry, binds);

            if (resolved.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'Lookup source returned no records: ' + key);
                continue;
            }

            options.put(key, resolved);
        }

        return options;
    }

    private static Boolean bindsSatisfied(LookupSource entry, Map<String, Object> binds) {
        for (String bind : entry.requiredBinds) {
            if (binds.get(bind) == null) {
                return false;
            }
        }
        return true;
    }

    private static List<FieldDetailController.PicklistOption> resolve(
        String key,
        LookupSource entry,
        Map<String, Object> binds
    ) {
        List<FieldDetailController.PicklistOption> options =
            new List<FieldDetailController.PicklistOption>();

        String targetObject = targetObjectFor(key);
        if (String.isBlank(targetObject)) {
            System.debug(LoggingLevel.WARN, 'Lookup source is not a lookup field: ' + key);
            return options;
        }

        // Only the binds this source's criteria reference, so a query is never handed a variable it
        // has no placeholder for.
        Map<String, Object> scopedBinds = new Map<String, Object>();
        for (String bind : entry.requiredBinds) {
            scopedBinds.put(bind, binds.get(bind));
        }

        try {
            for (SObject record : Database.queryWithBinds(
                buildQuery(targetObject, entry), scopedBinds, AccessLevel.USER_MODE
            )) {
                options.add(new FieldDetailController.PicklistOption(
                    String.valueOf(record.get(entry.labelField)),
                    String.valueOf(record.get('Id'))
                ));
            }
        } catch (Exception e) {
            // Non-fatal: one unusable source leaves its own field unsupported rather than failing
            // the whole interview's option load.
            System.debug(LoggingLevel.ERROR,
                'Lookup source query failed for ' + key + ': ' + e.getMessage());
        }

        return options;
    }

    @TestVisible
    private static String buildQuery(String targetObject, LookupSource entry) {
        return 'SELECT Id, ' + entry.labelField +
            ' FROM ' + targetObject +
            ' WHERE ' + entry.criteria +
            ' ORDER BY ' + entry.orderBy +
            ' LIMIT ' + entry.recordLimit;
    }

    /**
     * The object a registered key's field points at, or null when the key names a field that is
     * missing or isn't a lookup. A field pointing at several objects is polymorphic; the interview
     * supports the first, which is the whole target for every single-object lookup.
     */
    private static String targetObjectFor(String key) {
        List<String> parts = key.split('\\|');
        if (parts.size() != 2) {
            return null;
        }

        Schema.SObjectType carrier = Schema.getGlobalDescribe().get(parts[0]);
        if (carrier == null) {
            return null;
        }

        Schema.SObjectField field = carrier.getDescribe().fields.getMap().get(parts[1]);
        if (field == null) {
            return null;
        }

        Schema.DescribeFieldResult describe = field.getDescribe();
        if (describe.getType() != Schema.DisplayType.REFERENCE) {
            return null;
        }

        List<Schema.SObjectType> references = describe.getReferenceTo();
        return references.isEmpty() ? null : String.valueOf(references[0]);
    }
}