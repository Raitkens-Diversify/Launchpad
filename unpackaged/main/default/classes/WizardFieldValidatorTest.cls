@IsTest
private class WizardFieldValidatorTest {

    private static final String SSN = '^\\d{3}-\\d{2}-\\d{4}$';
    private static final String EIN = '^\\d{2}-\\d{7}$';

    private static Envelope_Field__mdt rule(
        String objectName, String fieldApi, String label,
        String pattern, String error, String minText, String maxText
    ) {
        return new Envelope_Field__mdt(
            Object__c = objectName,
            Field_API__c = fieldApi,
            Label__c = label,
            Pattern__c = pattern,
            Pattern_Error__c = error,
            Min__c = minText,
            Max__c = maxText
        );
    }

    @IsTest
    static void patternRejectsAndAccepts() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null)
        };

        List<WizardFieldValidator.FieldError> errors = WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '123' });
        System.assertEquals(1, errors.size(), 'A malformed Tax ID should fail.');
        System.assertEquals('Tax_ID__c', errors[0].fieldApi);
        System.assertEquals('Enter an SSN.', errors[0].message);

        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '123-45-6789' }).size(),
            'A well-formed SSN should pass.');
    }

    @IsTest
    static void unionSemanticsAcrossPartyRows() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null),
            rule('Account', 'Tax_ID__c', 'EIN', EIN, 'Enter an EIN.', null, null)
        };

        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '12-3456789' }).size(),
            'An EIN-shaped value should pass the union even though the SSN row rejects it.');
        System.assertEquals(1, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => 'garbage' }).size(),
            'A value matching no configured pattern should fail.');
    }

    @IsTest
    static void tinOrSsnNarrowsTaxIdShape() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null),
            rule('Account', 'Tax_ID__c', 'EIN', EIN, 'Enter an EIN.', null, null)
        };

        System.assertEquals(1, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Tax_ID__c' => '12-3456789', 'TIN_or_SSN__c' => 'SSN' }).size(),
            'With SSN declared, an EIN-shaped value should fail despite the union.');
        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Tax_ID__c' => '123-45-6789', 'TIN_or_SSN__c' => 'SSN' }).size());
        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Tax_ID__c' => '12-3456789', 'TIN_or_SSN__c' => 'TIN' }).size(),
            'With TIN declared, the EIN shape is the accepted one.');
    }

    @IsTest
    static void blankValuesAndUnknownKeysPass() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null)
        };

        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Tax_ID__c' => '', 'FirstName' => null, 'SomeUnruledField__c' => 'anything' }).size(),
            'Blank values and keys without rules must never fail — requiredness is not this layer.');
        System.assertEquals(0, WizardFieldValidator.validate('Account', null).size());
    }

    @IsTest
    static void numericBounds() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Service__c', 'Hourly_Rate__c', 'Hourly Rate', null, 'Between $0 and $400.', '0', '400')
        };

        System.assertEquals(1, WizardFieldValidator.validate('Service__c',
            new Map<String, Object>{ 'Hourly_Rate__c' => '500' }).size(), 'Above max should fail.');
        System.assertEquals(1, WizardFieldValidator.validate('Service__c',
            new Map<String, Object>{ 'Hourly_Rate__c' => -1 }).size(), 'Below min should fail.');
        System.assertEquals(0, WizardFieldValidator.validate('Service__c',
            new Map<String, Object>{ 'Hourly_Rate__c' => 400 }).size(), 'The bound itself passes.');
    }

    @IsTest
    static void dateBoundsWithTodayToken() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'PersonBirthdate', 'Date of Birth', null, 'Not in the future.', '1900-01-01', 'TODAY')
        };

        System.assertEquals(1, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'PersonBirthdate' => String.valueOf(Date.today().addDays(1)) }).size(),
            'A future date of birth should fail the TODAY cap.');
        System.assertEquals(1, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'PersonBirthdate' => '1899-12-31' }).size(), 'Before the floor should fail.');
        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'PersonBirthdate' => String.valueOf(Date.today()) }).size(), 'Today itself passes.');
    }

    @IsTest
    static void unparseableValueSkipsBounds() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Investment_Objectives__c', 'Investment Objectives', null, null, null, '3')
        };

        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Investment_Objectives__c' => 'Growth;Income' }).size(),
            'A joined multi-select against a selection cap is not a numeric bound failure.');
    }

    @IsTest
    static void namedFormatResolvesFromLibrary() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'BillingPostalCode',
                Label__c = 'Permanent Zip Code',
                Format__c = 'US ZIP'
            )
        };

        List<WizardFieldValidator.FieldError> errors = WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'BillingPostalCode' => 'zip' });
        System.assertEquals(1, errors.size(), 'A named format should reject a nonconforming value.');
        System.assertEquals(WizardFieldValidator.FORMATS.get('US ZIP').errorMessage, errors[0].message,
            'The error message should come from the format library.');

        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'BillingPostalCode' => '84604-1234' }).size());
    }

    @IsTest
    static void usPhoneFormatRejectsAndAccepts() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'PersonMobilePhone',
                Label__c = 'Mobile Phone',
                Format__c = 'US Phone'
            )
        };

        List<WizardFieldValidator.FieldError> errors = WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'PersonMobilePhone' => '(555) 123-456' });
        System.assertEquals(1, errors.size(), 'A 9-digit phone number should fail.');
        System.assertEquals(WizardFieldValidator.FORMATS.get('US Phone').errorMessage, errors[0].message,
            'The error message should come from the format library.');

        System.assertEquals(1, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'PersonMobilePhone' => '5' }).size(),
            'A single digit should fail.');

        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'PersonMobilePhone' => '(555) 123-4567' }).size(),
            'The masked 10-digit form should pass.');
        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'PersonMobilePhone' => '5551234567' }).size(),
            'Bare 10 digits should pass.');
        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'PersonMobilePhone' => '+1 555.123.4567' }).size(),
            'A country-code, dot-separated form should pass.');
    }

    @IsTest
    static void formatWinsOverRawPattern() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'Tax_ID__c',
                Label__c = 'Tax ID',
                Format__c = 'SSN',
                Pattern__c = '^never-matches$',
                Pattern_Error__c = 'Raw pattern message.'
            )
        };

        System.assertEquals(0, WizardFieldValidator.validate('Account', new Map<String, Object>{
            'Tax_ID__c' => '123-45-6789' }).size(),
            'A valid SSN must pass even though the raw Pattern__c would reject everything.');

        List<WizardFieldValidator.FieldError> errors = WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => 'garbage' });
        System.assertEquals(1, errors.size());
        System.assertEquals(WizardFieldValidator.FORMATS.get('SSN').errorMessage, errors[0].message,
            'The format library message wins over Pattern_Error__c.');
    }

    @IsTest
    static void enforceThrowsWithFieldLabelAndMessage() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null)
        };

        try {
            WizardFieldValidator.enforce('Account', new Map<String, Object>{ 'Tax_ID__c' => 'nope' });
            System.assert(false, 'enforce should have thrown.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Tax ID'), 'Message should name the field: ' + e.getMessage());
            System.assert(e.getMessage().contains('Enter an SSN.'), 'Message should carry the configured error.');
        }

        // And a clean payload must not throw.
        WizardFieldValidator.enforce('Account', new Map<String, Object>{ 'Tax_ID__c' => '123-45-6789' });
    }

    @IsTest
    static void ssnFormatAcceptsWithOrWithoutDashes() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'Tax_ID__c',
                Label__c = 'Tax ID',
                Format__c = 'SSN'
            )
        };

        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '123-45-6789' }).size(),
            'The dashed form must still pass.');
        System.assertEquals(0, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '123456789' }).size(),
            'A prefilled, un-dashed 9-digit value must also pass.');
        System.assertEquals(1, WizardFieldValidator.validate(
            'Account', new Map<String, Object>{ 'Tax_ID__c' => '12345678' }).size(),
            '8 digits is still invalid either way.');
    }

    @IsTest
    static void normalizeForStorageStripsDashesFromSsnOnly() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account', Field_API__c = 'SSN_Only__c',
                Label__c = 'SSN', Format__c = 'SSN'
            ),
            new Envelope_Field__mdt(
                Object__c = 'Account', Field_API__c = 'EIN_Only__c',
                Label__c = 'EIN', Format__c = 'EIN'
            )
        };

        Map<String, Object> values = new Map<String, Object>{
            'SSN_Only__c' => '123-45-6789',
            'EIN_Only__c' => '12-3456789'
        };
        WizardFieldValidator.normalizeForStorage('Account', values);

        System.assertEquals('123456789', values.get('SSN_Only__c'),
            'An SSN-format value should be stripped of dashes before storage.');
        System.assertEquals('12-3456789', values.get('EIN_Only__c'),
            'An EIN-format value keeps its required dashes — only SSN is normalized.');
    }

    @IsTest
    static void normalizeForStorageRespectsTinOrSsnNarrowing() {
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            rule('Account', 'Tax_ID__c', 'Tax ID', SSN, 'Enter an SSN.', null, null),
            rule('Account', 'Tax_ID__c', 'EIN', EIN, 'Enter an EIN.', null, null)
        };

        Map<String, Object> ssnPayload = new Map<String, Object>{
            'Tax_ID__c' => '123-45-6789', 'TIN_or_SSN__c' => 'SSN'
        };
        WizardFieldValidator.normalizeForStorage('Account', ssnPayload);
        System.assertEquals('123456789', ssnPayload.get('Tax_ID__c'),
            'Declared as SSN, dashes should be stripped before storage.');

        Map<String, Object> einPayload = new Map<String, Object>{
            'Tax_ID__c' => '12-3456789', 'TIN_or_SSN__c' => 'TIN'
        };
        WizardFieldValidator.normalizeForStorage('Account', einPayload);
        System.assertEquals('12-3456789', einPayload.get('Tax_ID__c'),
            'Declared as TIN/EIN, the value is left exactly as submitted.');
    }
}