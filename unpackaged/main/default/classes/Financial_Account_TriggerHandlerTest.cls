@IsTest
private class Financial_Account_TriggerHandlerTest {

    // Builds the pieces updateRelatedCase joins on: an envelope, a wizard Financial Account, its
    // 'Account Opening' wizard Case, and the two Envelope_Content rows that link both to the SAME
    // envelope (the match updateRelatedCase requires before it will touch the Case).
    private static Financial_Account__c setupDpi(String productType, Boolean isDpi) {
        Envelope__c envelope = new Envelope__c(Status__c = 'In Progress');
        insert envelope;

        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Wizard FA',
            Submitted__c = false,
            DPI__c = isDpi,
            Product_Type__c = productType
        );
        insert fa;

        Case wizardCase = new Case(
            Subject = 'New Financial Account',
            Origin = 'Wizard',
            Type = 'Account Opening',
            Status = 'New',
            Wizard_Financial_Account__c = fa.Id,
            Submitted__c = false
        );
        insert wizardCase;

        insert new List<Envelope_Content__c>{
            new Envelope_Content__c(Envelope__c = envelope.Id, Wizard_Financial_Account__c = fa.Id),
            new Envelope_Content__c(Envelope__c = envelope.Id, Case__c = wizardCase.Id)
        };

        return fa;
    }

    private static String caseTypeFor(Id faId) {
        return [
            SELECT Type FROM Case WHERE Wizard_Financial_Account__c = :faId LIMIT 1
        ].Type;
    }

    @IsTest
    static void dpiVariableAnnuityCaseIsRetypedOnSubmit() {
        Financial_Account__c fa = setupDpi('Variable Annuity', true);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Purchase a Variable Annuity', caseTypeFor(fa.Id),
            'A submitted DPI with Product Type Variable Annuity should retype its Case.');
    }

    @IsTest
    static void nonDpiVariableAnnuityCaseKeepsAccountOpening() {
        Financial_Account__c fa = setupDpi('Variable Annuity', false);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Account Opening', caseTypeFor(fa.Id),
            'The retype is DPI-only; a regular account keeps the type it opened with.');
    }

    @IsTest
    static void dpiUnmappedProductTypeKeepsAccountOpening() {
        Financial_Account__c fa = setupDpi('Mutual Fund', true);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Account Opening', caseTypeFor(fa.Id),
            'A product type with no mapping leaves the Case type untouched.');
    }
}