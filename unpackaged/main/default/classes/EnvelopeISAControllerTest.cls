@IsTest
private class EnvelopeISAControllerTest {

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Household')
            .getRecordTypeId();
    }

    // Financial_Advisor_Team_TriggerHandler.updateRepCode (fired via the dlrs real-time rollup
    // whenever a Financial_Advisor_Team_Member__c is inserted) unconditionally queries a team named
    // 'Default Team' with no LIMIT 1. Tests are isolated from org data, so without a seeded row here
    // that query throws "List has no rows for assignment to SObject" for every test in this class
    // that inserts a team member. Seeding it once keeps the assignment satisfied.
    private static void ensureDefaultAdvisorTeamSeed() {
        if ([SELECT count() FROM Financial_Advisor_Team__c WHERE Name = 'Default Team'] == 0) {
            insert new Financial_Advisor_Team__c(Name = 'Default Team');
        }
    }

    private static Financial_Advisor_Team__c makeTeam(String name) {
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(Name = name);
        insert team;
        return team;
    }

    private static Account makeHousehold(String name, Id teamId) {
        Account household = new Account(
            Name = name,
            RecordTypeId = householdRecordTypeId(),
            Type = 'Prospect'
        );
        if (teamId != null) {
            household.Financial_Advisor_Team__c = teamId;
        }
        insert household;
        return household;
    }

    // ---------------------------------------------------------------------
    // getRepCodesRelatedToFAT
    // ---------------------------------------------------------------------

    @IsTest
    static void getRepCodesReturnsEmptyWithNoHouseholdOrMembership() {
        Test.startTest();
        List<Rep_Code__c> result = EnvelopeISAController.getRepCodesRelatedToFAT(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getRepCodesReturnsHouseholdTeamCode() {
        ensureDefaultAdvisorTeamSeed();
        Financial_Advisor_Team__c team = makeTeam('ISA Household Team');
        Account household = makeHousehold('ISA Household', team.Id);
        insert new Rep_Code__c(Name = 'ISA-RC-1', Financial_Advisor_Team__c = team.Id);

        Test.startTest();
        List<Rep_Code__c> result = EnvelopeISAController.getRepCodesRelatedToFAT(household.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(team.Id, result[0].Financial_Advisor_Team__c);
    }

    @IsTest
    static void getRepCodesIncludesRunningUsersActiveTeamMembership() {
        ensureDefaultAdvisorTeamSeed();
        Financial_Advisor_Team__c myTeam = makeTeam('My Active Team');
        insert new Rep_Code__c(Name = 'ISA-RC-Mine', Financial_Advisor_Team__c = myTeam.Id);
        insert new Financial_Advisor_Team_Member__c(
            Financial_Advisor_Team__c = myTeam.Id,
            User__c = UserInfo.getUserId(),
            Active__c = true
        );

        Test.startTest();
        List<Rep_Code__c> result = EnvelopeISAController.getRepCodesRelatedToFAT(null);
        Test.stopTest();

        Boolean found = false;
        for (Rep_Code__c rc : result) {
            if (rc.Financial_Advisor_Team__c == myTeam.Id) {
                found = true;
            }
        }
        System.assertEquals(true, found,
            'Rep codes from the running user\'s active team membership should be included.');
    }

    // ---------------------------------------------------------------------
    // createOrUpdateFinancialAccountWithEnvelope
    // ---------------------------------------------------------------------

    @IsTest
    static void createOrUpdateThrowsOnBlankNicknameOrNullEnvelope() {
        Boolean threwBlankNickname = false;
        Boolean threwNullEnvelope = false;
        Test.startTest();
        try {
            EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope(
                Id.valueOf('001000000000000AAA'), '', null, false);
        } catch (AuraHandledException e) {
            threwBlankNickname = true;
        }
        try {
            EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope(
                null, 'Nickname', null, false);
        } catch (AuraHandledException e) {
            threwNullEnvelope = true;
        }
        Test.stopTest();
        System.assertEquals(true, threwBlankNickname, 'A blank nickname should throw.');
        System.assertEquals(true, threwNullEnvelope, 'A null envelope id should throw.');
    }

    @IsTest
    static void createOrUpdateThrowsWhenNoHouseholdRecordTypeRowLinked() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        // No Household-record-type Envelope_Content__c row exists for this envelope, so the
        // Account__r.RecordType.Name = 'Household' filter finds nothing.

        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope(
                envelope.Id, 'Nickname', null, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'A missing household link should throw.');
    }

    @IsTest
    static void createOrUpdateCreatesNewAccountCaseAndRequiredDocument() {
        Financial_Advisor_Team__c team = makeTeam('ISA New FA Team');
        Account household = makeHousehold('ISA New FA Household', team.Id);
        Envelope__c envelope = new Envelope__c(Status__c = 'New', Household__c = household.Id);
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Test.startTest();
        String finAccountId = EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'ISA Account', null, true);
        Test.stopTest();

        Financial_Account__c created = [
            SELECT Id, Name, Household__c, Financial_Advisor_Team__c, Submitted__c, DPI__c
            FROM Financial_Account__c
            WHERE Id = :finAccountId
        ];
        System.assertEquals('ISA Account', created.Name);
        System.assertEquals(household.Id, created.Household__c);
        System.assertEquals(team.Id, created.Financial_Advisor_Team__c);
        System.assertEquals(false, created.Submitted__c);
        System.assertEquals(true, created.DPI__c, 'isDpi=true should be stamped on the new account.');

        List<Case> cases = [
            SELECT Id, Household__c, Wizard_Financial_Account__c, Type, Origin, Status
            FROM Case
            WHERE Wizard_Financial_Account__c = :finAccountId
        ];
        System.assertEquals(1, cases.size(), 'An account opening case should be created.');
        System.assertEquals(household.Id, cases[0].Household__c);
        System.assertEquals('Account Opening', cases[0].Type);
        System.assertEquals('Wizard', cases[0].Origin);

        List<Required_Documents__c> reqDocs = [
            SELECT Id, Name, Financial_Account__c
            FROM Required_Documents__c
            WHERE Financial_Account__c = :finAccountId
        ];
        System.assertEquals(1, reqDocs.size(), 'A required document should be created for the new account.');

        List<Envelope_Content__c> links = [
            SELECT Id, Wizard_Financial_Account__c, Case__c, Required_Document__c
            FROM Envelope_Content__c
            WHERE Envelope__c = :envelope.Id
        ];
        Boolean hasFAlink = false;
        Boolean hasCaseLink = false;
        Boolean hasReqDocLink = false;
        for (Envelope_Content__c ec : links) {
            if (ec.Wizard_Financial_Account__c == finAccountId) { hasFAlink = true; }
            if (ec.Case__c != null) { hasCaseLink = true; }
            if (ec.Required_Document__c != null) { hasReqDocLink = true; }
        }
        System.assertEquals(true, hasFAlink, 'A content row should link the new Financial Account.');
        System.assertEquals(true, hasCaseLink, 'A content row should link the new Case.');
        System.assertEquals(true, hasReqDocLink, 'A content row should link the new Required Document.');
    }

    @IsTest
    static void createOrUpdateUpdatesExistingAccountName() {
        Account household = makeHousehold('ISA Existing FA Household', null);
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Financial_Account__c existing = new Financial_Account__c(
            Name = 'Old ISA Name', Household__c = household.Id, Submitted__c = false
        );
        insert existing;

        Test.startTest();
        String returnedId = EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'Renamed ISA', existing.Id, false);
        Test.stopTest();

        System.assertEquals(existing.Id, returnedId);
        Financial_Account__c updated = [SELECT Name FROM Financial_Account__c WHERE Id = :existing.Id];
        System.assertEquals('Renamed ISA', updated.Name);
    }

    // ---------------------------------------------------------------------
    // getAccountTypesFromMetadata / getRegistrationTypeAttributes
    // ---------------------------------------------------------------------

    @IsTest
    static void getAccountTypesFromMetadataReturnsMap() {
        Test.startTest();
        Map<String, List<String>> result = EnvelopeISAController.getAccountTypesFromMetadata();
        Test.stopTest();
        System.assertNotEquals(null, result, 'The method should always return a map, never null.');
    }

    @IsTest
    static void getRegistrationTypeAttributesReturnsEveryConfiguredRegistration() {
        Test.startTest();
        Map<String, EnvelopeISAController.RegistrationTypeAttributes> result =
            EnvelopeISAController.getRegistrationTypeAttributes();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isEmpty(),
            'Registration_Type__mdt records ship with the package.');
        for (String key : result.keySet()) {
            EnvelopeISAController.RegistrationTypeAttributes attrs = result.get(key);
            System.assertNotEquals(null, attrs, 'Every entry should carry its attributes wrapper.');
        }
    }
}