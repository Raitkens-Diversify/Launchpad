@IsTest
private class EnvelopeFormAccountControllerTest {

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Household')
            .getRecordTypeId();
    }

    private static Financial_Advisor_Team__c makeTeam(String name) {
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(Name = name);
        insert team;
        return team;
    }

    // Financial_Advisor_Team_TriggerHandler.updateRepCode (fired via a dlrs real-time rollup
    // whenever a Rep_Code__c or Financial_Advisor_Team_Member__c child is inserted) unconditionally
    // queries a team named 'Default Team' with no LIMIT 1. Tests are isolated from org data, so
    // without a seeded row here that query throws "List has no rows for assignment to SObject" for
    // every test that inserts such a child record. Seeding it once keeps the assignment satisfied.
    private static void ensureDefaultAdvisorTeamSeed() {
        if ([SELECT count() FROM Financial_Advisor_Team__c WHERE Name = 'Default Team'] == 0) {
            insert new Financial_Advisor_Team__c(Name = 'Default Team');
        }
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
    static void getRepCodesReturnsEmptyForNullHousehold() {
        Test.startTest();
        List<Rep_Code__c> result = EnvelopeFormAccountController.getRepCodesRelatedToFAT(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'A null household should return no rep codes.');
    }

    @IsTest
    static void getRepCodesReturnsEmptyWhenHouseholdHasNoTeam() {
        Account household = makeHousehold('No Team Household', null);

        Test.startTest();
        List<Rep_Code__c> result = EnvelopeFormAccountController.getRepCodesRelatedToFAT(household.Id);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'A household without a team has no rep codes.');
    }

    @IsTest
    static void getRepCodesReturnsCodesForHouseholdsTeam() {
        ensureDefaultAdvisorTeamSeed();
        Financial_Advisor_Team__c team = makeTeam('FormAccount Team');
        Account household = makeHousehold('Rep Code Household', team.Id);
        insert new Rep_Code__c(Name = 'RC-100', Financial_Advisor_Team__c = team.Id);

        Test.startTest();
        List<Rep_Code__c> result = EnvelopeFormAccountController.getRepCodesRelatedToFAT(household.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return the household team\'s rep code.');
        System.assertEquals(team.Id, result[0].Financial_Advisor_Team__c);
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
            EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
                Id.valueOf('001000000000000AAA'), '', null);
        } catch (AuraHandledException e) {
            threwBlankNickname = true;
        }
        try {
            EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
                null, 'Nickname', null);
        } catch (AuraHandledException e) {
            threwNullEnvelope = true;
        }
        Test.stopTest();
        System.assertEquals(true, threwBlankNickname, 'A blank nickname should throw.');
        System.assertEquals(true, threwNullEnvelope, 'A null envelope id should throw.');
    }

    @IsTest
    static void createOrUpdateThrowsWhenNoHouseholdLinked() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        // No Envelope_Content__c row with Account__c populated exists for this envelope.

        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
                envelope.Id, 'Nickname', null);
        } catch (AuraHandledException e) {
            // Note: the controller builds this AuraHandledException without calling setMessage(),
            // so getMessage() reads back as "Script-thrown exception" in a test context (a known
            // Apex quirk documented elsewhere in this codebase, e.g. WizardFieldValidator.enforce).
            // The real message still reaches the client at runtime; only the in-test introspection
            // is affected, so this test only checks that the call throws.
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'A missing household link should throw.');
    }

    @IsTest
    static void createOrUpdateCreatesNewFinancialAccountAndLinksEnvelope() {
        Financial_Advisor_Team__c team = makeTeam('New FA Team');
        Account household = makeHousehold('New FA Household', team.Id);
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Test.startTest();
        String finAccountId = EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'My New Account', null);
        Test.stopTest();

        Financial_Account__c created = [
            SELECT Id, Name, Household__c, Financial_Advisor_Team__c, Submitted__c
            FROM Financial_Account__c
            WHERE Id = :finAccountId
        ];
        System.assertEquals('My New Account', created.Name);
        System.assertEquals(household.Id, created.Household__c);
        System.assertEquals(team.Id, created.Financial_Advisor_Team__c);
        System.assertEquals(false, created.Submitted__c);

        List<Envelope_Content__c> links = [
            SELECT Id
            FROM Envelope_Content__c
            WHERE Envelope__c = :envelope.Id AND Wizard_Financial_Account__c = :finAccountId
        ];
        System.assertEquals(1, links.size(), 'A content row should link the new Financial Account.');
    }

    @IsTest
    static void createOrUpdateUpdatesExistingFinancialAccountName() {
        Account household = makeHousehold('Existing FA Household', null);
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Financial_Account__c existing = new Financial_Account__c(
            Name = 'Old Name', Household__c = household.Id, Submitted__c = false
        );
        insert existing;

        Test.startTest();
        String returnedId = EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'Renamed Account', existing.Id);
        Test.stopTest();

        System.assertEquals(existing.Id, returnedId, 'The existing Id should be returned unchanged.');
        Financial_Account__c updated = [SELECT Name FROM Financial_Account__c WHERE Id = :existing.Id];
        System.assertEquals('Renamed Account', updated.Name);
    }

    // ---------------------------------------------------------------------
    // getAccountTypesFromMetadata
    // ---------------------------------------------------------------------

    @IsTest
    static void getAccountTypesFromMetadataReturnsMap() {
        Test.startTest();
        Map<String, List<String>> result = EnvelopeFormAccountController.getAccountTypesFromMetadata();
        Test.stopTest();
        System.assertNotEquals(null, result, 'The method should always return a map, never null.');
    }

    // ---------------------------------------------------------------------
    // createMember
    // ---------------------------------------------------------------------

    @IsTest
    static void createMemberThrowsForNullOrEmptyAccountData() {
        Boolean threwNull = false;
        Boolean threwEmpty = false;
        Test.startTest();
        try {
            EnvelopeFormAccountController.createMember(null, null);
        } catch (AuraHandledException e) {
            threwNull = true;
        }
        try {
            EnvelopeFormAccountController.createMember(new Map<String, Object>(), null);
        } catch (AuraHandledException e) {
            threwEmpty = true;
        }
        Test.stopTest();
        System.assertEquals(true, threwNull, 'Null account data should throw.');
        System.assertEquals(true, threwEmpty, 'Empty account data should throw.');
    }

    @IsTest
    static void createMemberThrowsForBlankOrUnrecognizedRecordType() {
        Boolean threwBlank = false;
        Boolean threwUnrecognized = false;
        Test.startTest();
        try {
            EnvelopeFormAccountController.createMember(
                new Map<String, Object>{ 'RecordType' => '', 'Name' => 'X' }, null);
        } catch (AuraHandledException e) {
            threwBlank = true;
        }
        try {
            EnvelopeFormAccountController.createMember(
                new Map<String, Object>{ 'RecordType' => 'spaceship', 'Name' => 'X' }, null);
        } catch (AuraHandledException e) {
            threwUnrecognized = true;
        }
        Test.stopTest();
        System.assertEquals(true, threwBlank, 'A blank Record Type should throw.');
        System.assertEquals(true, threwUnrecognized, 'An unrecognized Record Type should throw.');
    }

    @IsTest
    static void createMemberCreatesBusinessAccountWithoutEnvelope() {
        Map<String, Object> acc = new Map<String, Object>{
            'RecordType' => 'business',
            'Name' => 'Test Business ' + Datetime.now().getTime(),
            'Type' => 'Prospect'
        };
        Test.startTest();
        Id newId = EnvelopeFormAccountController.createMember(acc, null);
        Test.stopTest();

        Account created = [SELECT Id, Type, RecordType.DeveloperName FROM Account WHERE Id = :newId];
        System.assertEquals('Business', created.RecordType.DeveloperName);
        System.assertEquals('Prospect', created.Type);
        System.assertEquals(0,
            [SELECT count() FROM Envelope_Content__c WHERE Account__c = :newId],
            'No envelope id was supplied, so no content row should link this account.');
    }

    @IsTest
    static void createMemberCreatesTrustAccountAndLinksEnvelope() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        Map<String, Object> acc = new Map<String, Object>{
            'RecordType' => 'Trust',
            'Name' => 'Test Trust ' + Datetime.now().getTime(),
            'Type' => 'Prospect'
        };
        Test.startTest();
        Id newId = EnvelopeFormAccountController.createMember(acc, envelope.Id);
        Test.stopTest();

        Account created = [SELECT Id, RecordType.DeveloperName FROM Account WHERE Id = :newId];
        System.assertEquals('Trust', created.RecordType.DeveloperName);

        List<Envelope_Content__c> links = [
            SELECT Id FROM Envelope_Content__c WHERE Envelope__c = :envelope.Id AND Account__c = :newId
        ];
        System.assertEquals(1, links.size(), 'An envelope content row should link the new account.');
    }

    @IsTest
    static void createMemberClientPicksUpHouseholdsAdvisorTeam() {
        Financial_Advisor_Team__c team = makeTeam('Client Member Team');
        Account household = makeHousehold('Client Member Household', team.Id);
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Map<String, Object> acc = new Map<String, Object>{
            'RecordType' => 'client',
            'FirstName' => 'Test',
            'LastName' => 'Client' + Datetime.now().getTime(),
            'Type' => 'Prospect'
        };
        Test.startTest();
        Id newId = EnvelopeFormAccountController.createMember(acc, envelope.Id);
        Test.stopTest();

        Account created = [
            SELECT Id, Financial_Advisor_Team__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :newId
        ];
        System.assertEquals('PersonAccount', created.RecordType.DeveloperName);
        System.assertEquals(team.Id, created.Financial_Advisor_Team__c,
            'The new client should inherit the household\'s advisor team.');

        List<Envelope_Content__c> links = [
            SELECT Id FROM Envelope_Content__c WHERE Envelope__c = :envelope.Id AND Account__c = :newId
        ];
        System.assertEquals(1, links.size(), 'An envelope content row should link the new client account.');
    }

    @IsTest
    static void createMemberCollectsUnmappableFieldKeys() {
        Map<String, Object> acc = new Map<String, Object>{
            'RecordType' => 'business',
            'Name' => 'Bad Field Business',
            'Type' => 'Prospect',
            'Not_A_Real_Field__c' => 'x'
        };
        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeFormAccountController.createMember(acc, null);
        } catch (AuraHandledException e) {
            // See the note in createOrUpdateThrowsWhenNoHouseholdLinked: getMessage() reads back as
            // "Script-thrown exception" here since the controller never calls setMessage().
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'An unmappable field key should throw.');
    }
}