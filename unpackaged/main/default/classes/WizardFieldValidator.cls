/**
 * Server-side backstop for the wizard's format rules (Envelope_Field__mdt Format__c — a named
 * entry in FORMATS — or the raw Pattern__c escape hatch, plus Min__c / Max__c bounds). The client
 * renders party-precise rules per row; the server can't always tell which
 * wizard party a payload came from, so a value passes when it fully satisfies AT LEAST ONE
 * configured rule row for its object+field (union semantics). Blank values always pass —
 * requiredness is not this class's job, and untouched existing bad data must never block a save.
 *
 * One concrete special case: Tax_ID__c narrows to the SSN or EIN shape when the same payload
 * carries a TIN_or_SSN__c choice.
 */
public inherited sharing class WizardFieldValidator {

    public class FieldError {
        @AuraEnabled public String fieldApi;
        @AuraEnabled public String label;
        @AuraEnabled public String message;

        public FieldError(String fieldApi, String label, String message) {
            this.fieldApi = fieldApi;
            this.label = label;
            this.message = message;
        }
    }

    public class FormatDef {
        public String pattern;
        public String errorMessage;

        public FormatDef(String pattern, String errorMessage) {
            this.pattern = pattern;
            this.errorMessage = errorMessage;
        }
    }

    // The named-format library behind Envelope_Field__mdt.Format__c. One entry per picklist value;
    // the schema builder (FieldDetailController) and this validator both read it, and the client
    // keys its input masks off the same names. Change a format here and every layer follows.
    // Patterns are also shipped to the browser's HTML pattern attribute, which compiles them with
    // the JS 'v' regex flag — keep them v-compatible (e.g. escape '-' inside character classes),
    // or the browser silently drops the constraint and the field never shows its error.
    public static final Map<String, FormatDef> FORMATS = new Map<String, FormatDef>{
        'SSN' => new FormatDef(
            '^\\d{3}-?\\d{2}-?\\d{4}$',
            'Enter a Social Security Number as XXX-XX-XXXX or 9 digits.'),
        // The dash is optional here for the same reason it is in SSN above: people paste tax ids
        // both ways, and rejecting the undashed form made a valid nine-digit entry unenterable.
        'EIN' => new FormatDef(
            '^\\d{2}-?\\d{7}$',
            'Enter an EIN as XX-XXXXXXX or 9 digits.'),
        // Nine bare digits satisfy either branch, which is correct: until TIN_or_SSN__c is chosen
        // the dash position is genuinely ambiguous, so the undashed form cannot be attributed to
        // one shape over the other. resolvedFormat narrows this to SSN or EIN once it is chosen.
        'SSN or EIN' => new FormatDef(
            '^(\\d{3}-?\\d{2}-?\\d{4}|\\d{2}-?\\d{7})$',
            'Enter a valid SSN (XXX-XX-XXXX) or EIN (XX-XXXXXXX), with or without dashes.'),
        'US ZIP' => new FormatDef(
            '^\\d{5}(-\\d{4})?$',
            'Enter a ZIP code as 12345 or 12345-6789.'),
        'US Phone' => new FormatDef(
            '^(\\+?1[ .\\-]?)?(\\(\\d{3}\\)|\\d{3})[ .\\-]?\\d{3}[ .\\-]?\\d{4}$',
            'Enter a 10-digit US phone number.')
    };

    // Test seam: CMT records cannot be inserted in tests, so tests inject rule rows here.
    @TestVisible
    private static List<Envelope_Field__mdt> ruleRowsOverride;

    // 'objectname|fieldapi' (lowercase) -> configured rule rows for that field.
    private static Map<String, List<Envelope_Field__mdt>> rulesByKey;

    /**
     * Check every present, non-blank key in the payload against its configured rules.
     * Keys without rules pass; requiredness is never checked here.
     */
    public static List<FieldError> validate(String objectName, Map<String, Object> values) {
        List<FieldError> errors = new List<FieldError>();
        if (values == null || values.isEmpty()) {
            return errors;
        }

        Map<String, List<Envelope_Field__mdt>> rules = loadRules();

        for (String key : values.keySet()) {
            Object raw = values.get(key);
            String value = raw == null ? null : String.valueOf(raw);
            if (String.isBlank(value)) {
                continue;
            }

            List<Envelope_Field__mdt> fieldRules =
                rules.get(objectName.toLowerCase() + '|' + key.toLowerCase());
            if (fieldRules == null || fieldRules.isEmpty()) {
                continue;
            }

            String narrowed = narrowedTaxIdPattern(key, values);
            if (narrowed != null) {
                if (!Pattern.matches(narrowed, value)) {
                    errors.add(new FieldError(key, fieldRules[0].Label__c,
                        firstError(fieldRules, 'Invalid value.')));
                }
                continue;
            }

            if (!passesAnyRule(fieldRules, value)) {
                errors.add(new FieldError(key, fieldRules[0].Label__c,
                    firstError(fieldRules, 'Invalid value.')));
            }
        }
        return errors;
    }

    /** validate() and throw a single AuraHandledException naming every failing field. */
    public static void enforce(String objectName, Map<String, Object> values) {
        List<FieldError> errors = validate(objectName, values);
        if (errors.isEmpty()) {
            return;
        }
        List<String> parts = new List<String>();
        for (FieldError err : errors) {
            String label = String.isNotBlank(err.label) ? err.label : err.fieldApi;
            parts.add(label + ': ' + err.message);
        }
        String message = String.join(parts, ' ');
        // setMessage so getMessage() carries the real text server-side too (an AuraHandledException
        // constructed without it reads "Script-thrown exception" in Apex, e.g. in tests).
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }

    /**
     * Strips separator characters from a value about to be written to storage, when that
     * value's resolved format is 'SSN' — so the database always holds raw digits regardless
     * of whether the user (or a prefill round-trip) supplied dashes. Other formats (EIN, ZIP,
     * Phone) are left exactly as submitted; only SSN is normalized for storage today. Mutates
     * `values` in place. Call this AFTER enforce() has validated the payload and BEFORE the
     * caller copies values onto the record.
     */
    public static void normalizeForStorage(String objectName, Map<String, Object> values) {
        if (values == null || values.isEmpty()) {
            return;
        }
        Map<String, List<Envelope_Field__mdt>> rules = loadRules();
        for (String key : values.keySet()) {
            Object raw = values.get(key);
            if (!(raw instanceof String)) {
                continue;
            }
            String value = (String) raw;
            if (String.isBlank(value)) {
                continue;
            }
            if (resolvedFormat(objectName, key, values, rules) == 'SSN') {
                values.put(key, value.replaceAll('[^0-9]', ''));
            }
        }
    }

    // The format name actually governing a key for this payload — same Tax_ID__c/TIN_or_SSN__c
    // narrowing as narrowedTaxIdPattern(), but returning the format's name (not its pattern) so
    // callers other than validate() can key off it too.
    private static String resolvedFormat(
        String objectName, String key, Map<String, Object> values,
        Map<String, List<Envelope_Field__mdt>> rules
    ) {
        if (key.toLowerCase() == 'tax_id__c') {
            String kind = null;
            for (String candidate : values.keySet()) {
                if (candidate.toLowerCase() == 'tin_or_ssn__c' && values.get(candidate) != null) {
                    kind = String.valueOf(values.get(candidate));
                }
            }
            if (kind == 'SSN') {
                return 'SSN';
            }
            if (kind == 'TIN') {
                return 'EIN';
            }
        }
        List<Envelope_Field__mdt> fieldRules = rules.get(objectName.toLowerCase() + '|' + key.toLowerCase());
        if (fieldRules == null || fieldRules.isEmpty()) {
            return null;
        }
        return fieldRules[0].Format__c;
    }

    // A value passes a single rule row only when it satisfies everything that row configures
    // (pattern and bounds); it passes the field when any one row passes.
    private static Boolean passesAnyRule(List<Envelope_Field__mdt> fieldRules, String value) {
        for (Envelope_Field__mdt rule : fieldRules) {
            if (passesRule(rule, value)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean passesRule(Envelope_Field__mdt rule, String value) {
        String effectivePattern = patternFor(rule);
        if (effectivePattern != null && !Pattern.matches(effectivePattern, value)) {
            return false;
        }
        if (!withinBound(rule.Min__c, value, true)) {
            return false;
        }
        if (!withinBound(rule.Max__c, value, false)) {
            return false;
        }
        return true;
    }

    // A named Format__c supersedes the raw Pattern__c escape hatch.
    private static String patternFor(Envelope_Field__mdt rule) {
        if (String.isNotBlank(rule.Format__c) && FORMATS.containsKey(rule.Format__c)) {
            return FORMATS.get(rule.Format__c).pattern;
        }
        return String.isNotBlank(rule.Pattern__c) ? rule.Pattern__c.trim() : null;
    }

    // Bound grammar: decimal literal, ISO date, or TODAY. A value that can't be parsed into the
    // bound's own type is left to the pattern/coercion layers rather than failed here (e.g. a
    // multi-select's joined 'A;B' against the selection cap the client already enforces).
    private static Boolean withinBound(String boundText, String value, Boolean isMin) {
        if (String.isBlank(boundText)) {
            return true;
        }
        String bound = boundText.trim();

        if (bound.equalsIgnoreCase('TODAY') || Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', bound)) {
            Date boundDate = bound.equalsIgnoreCase('TODAY') ? Date.today() : Date.valueOf(bound);
            Date candidate;
            try {
                candidate = Date.valueOf(value.trim());
            } catch (Exception ignored) {
                return true;
            }
            return isMin ? candidate >= boundDate : candidate <= boundDate;
        }

        Decimal boundNumber;
        Decimal candidateNumber;
        try {
            System.debug('bound: ' + bound);
            boundNumber = Decimal.valueOf(bound);
            System.debug('boundNumber: ' + boundNumber);
            candidateNumber = Decimal.valueOf(value.trim());
            System.debug('candidateNumber: ' + candidateNumber);
        } catch (Exception ignored) {
            return true;
        }
        return isMin ? candidateNumber >= boundNumber : candidateNumber <= boundNumber;
    }

    // When the payload states which kind of Tax ID it carries, hold Tax_ID__c to that exact shape
    // instead of the union of configured patterns.
    private static String narrowedTaxIdPattern(String key, Map<String, Object> values) {
        if (key.toLowerCase() != 'tax_id__c') {
            return null;
        }
        String kind = null;
        for (String candidate : values.keySet()) {
            if (candidate.toLowerCase() == 'tin_or_ssn__c' && values.get(candidate) != null) {
                kind = String.valueOf(values.get(candidate));
            }
        }
        if (kind == 'SSN') {
            return FORMATS.get('SSN').pattern;
        }
        if (kind == 'TIN') {
            return FORMATS.get('EIN').pattern;
        }
        return null;
    }

    private static String firstError(List<Envelope_Field__mdt> fieldRules, String fallback) {
        for (Envelope_Field__mdt rule : fieldRules) {
            if (String.isNotBlank(rule.Format__c) && FORMATS.containsKey(rule.Format__c)) {
                return FORMATS.get(rule.Format__c).errorMessage;
            }
            if (String.isNotBlank(rule.Pattern_Error__c)) {
                return rule.Pattern_Error__c;
            }
        }
        return fallback;
    }

    private static Map<String, List<Envelope_Field__mdt>> loadRules() {
        // The cache is skipped while a test has rules injected, so consecutive validate calls in
        // one test transaction always see the current override.
        if (rulesByKey != null && ruleRowsOverride == null) {
            return rulesByKey;
        }
        rulesByKey = new Map<String, List<Envelope_Field__mdt>>();

        List<Envelope_Field__mdt> rows = ruleRowsOverride != null
            ? ruleRowsOverride
            : Envelope_Field__mdt.getAll().values();

        for (Envelope_Field__mdt row : rows) {
            if (String.isBlank(row.Field_API__c) || String.isBlank(row.Object__c)) {
                continue;
            }
            if (String.isBlank(row.Format__c)
                && String.isBlank(row.Pattern__c)
                && String.isBlank(row.Min__c)
                && String.isBlank(row.Max__c)) {
                continue;
            }
            String key = row.Object__c.toLowerCase() + '|' + row.Field_API__c.toLowerCase();
            if (!rulesByKey.containsKey(key)) {
                rulesByKey.put(key, new List<Envelope_Field__mdt>());
            }
            rulesByKey.get(key).add(row);
        }
        return rulesByKey;
    }
}