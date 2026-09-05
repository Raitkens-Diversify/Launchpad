@IsTest
private class EnvelopeLandingApexTest {

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

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Household')
            .getRecordTypeId();
    }

    private static Id businessRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Business')
            .getRecordTypeId();
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

    // A Financial Advisor Team the running user belongs to, with `names.size()` Household accounts
    // on it.
    private static Financial_Advisor_Team__c makeTeamForRunningUser(String teamName) {
        ensureDefaultAdvisorTeamSeed();
        Group grp = new Group(Name = teamName + ' Group', Type = 'Regular');
        insert grp;
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
            Name = teamName,
            Public_Group_Id__c = grp.Id
        );
        insert team;
        insert new Financial_Advisor_Team_Member__c(
            Financial_Advisor_Team__c = team.Id,
            User__c = UserInfo.getUserId()
        );
        return team;
    }

    private static List<Account> makeHouseholds(Id teamId, List<String> names) {
        List<Account> households = new List<Account>();
        for (String name : names) {
            households.add(new Account(
                Name = name,
                RecordTypeId = householdRecordTypeId(),
                Financial_Advisor_Team__c = teamId,
                Type = 'Prospect'
            ));
        }
        insert households;
        return households;
    }

    // ---------------------------------------------------------------------------------------------
    // exgetWizEnvelopes
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void exGetWizEnvelopesReturnsOnlyOpenEnvelopes() {
        Envelope__c inProgress = new Envelope__c(Name = 'Ex Resume Envelope', Status__c = 'In Progress');
        Envelope__c complete = new Envelope__c(Name = 'Ex Complete Envelope', Status__c = 'Complete');
        insert new List<Envelope__c>{ inProgress, complete };

        Test.startTest();
        List<Envelope__c> result = EnvelopeLandingApex.exgetWizEnvelopes();
        Test.stopTest();

        Set<Id> ids = new Map<Id, Envelope__c>(result).keySet();
        System.assert(ids.contains(inProgress.Id), 'In Progress envelope should be returned.');
        System.assert(!ids.contains(complete.Id), 'Complete envelope should not be returned.');
    }

    // ---------------------------------------------------------------------------------------------
    // getWizEnvelopes (legacy V1 list)
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void returnsOwnedEnvelopesWhenNoTeamMapping() {
        Envelope__c inProgress = new Envelope__c(
            Name = 'Resume Envelope',
            Status__c = 'In Progress'
        );
        insert inProgress;

        Envelope__c complete = new Envelope__c(
            Name = 'Complete Envelope',
            Status__c = 'Complete'
        );
        insert complete;

        Test.startTest();
        EnvelopeLandingApex.WizardDataWrapper dto = EnvelopeLandingApex.getWizEnvelopes();
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should be returned.');
        System.assertNotEquals(null, dto.envelopes, 'Envelope list should be initialized.');
        Boolean hasInProgress = false;
        Boolean hasComplete = false;
        for (Envelope__c env : dto.envelopes) {
            if (env.Id == inProgress.Id) {
                hasInProgress = true;
            }
            if (env.Id == complete.Id) {
                hasComplete = true;
            }
        }
        System.assertEquals(true, hasInProgress,
            'In Progress envelope should be returned for current owner.');
        System.assertEquals(false, hasComplete,
            'Complete envelope should not be returned.');
    }

    @IsTest
    static void getWizEnvelopesResolvesTeamHouseholdsRepCodesAndMetrics() {
        Financial_Advisor_Team__c team = makeTeamForRunningUser('Wiz Envelopes Team');
        Account household = makeHousehold('Wiz Envelopes Household', team.Id);
        insert new Rep_Code__c(Name = 'Wiz-RC-1', Financial_Advisor_Team__c = team.Id);

        Envelope__c envelope = new Envelope__c(Name = 'Team Linked Envelope', Status__c = 'New');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);

        Test.startTest();
        EnvelopeLandingApex.WizardDataWrapper dto = EnvelopeLandingApex.getWizEnvelopes();
        Test.stopTest();

        System.assertNotEquals(null, dto.financialAdvisorTeams);
        Boolean hasTeam = false;
        for (Financial_Advisor_Team__c t : dto.financialAdvisorTeams) {
            if (t.Id == team.Id) { hasTeam = true; }
        }
        System.assertEquals(true, hasTeam, 'The user\'s team should be returned.');

        Boolean hasHousehold = false;
        for (Account acc : dto.households) {
            if (acc.Id == household.Id) { hasHousehold = true; }
        }
        System.assertEquals(true, hasHousehold, 'The team\'s household should be returned.');

        Boolean hasRepCode = false;
        for (Rep_Code__c rc : dto.repCodes) {
            if (rc.Financial_Advisor_Team__c == team.Id) { hasRepCode = true; }
        }
        System.assertEquals(true, hasRepCode, 'The team\'s rep code should be returned.');

        Boolean hasEnvelope = false;
        for (Envelope__c env : dto.envelopes) {
            if (env.Id == envelope.Id) { hasEnvelope = true; }
        }
        System.assertEquals(true, hasEnvelope,
            'An envelope linked through the household junction row should be returned.');

        Boolean hasMetrics = false;
        for (EnvelopeLandingApex.EnvelopeMetrics metrics : dto.envelopeMetrics) {
            if (metrics.envelopeId == envelope.Id) { hasMetrics = true; }
        }
        System.assertEquals(true, hasMetrics, 'Metrics should be computed for the listed envelope.');
    }

    // buildEntityCounts (shared by getWizEnvelopes, getEnvelopeListData and searchEnvelopeListData)
    // reads five more objects once a listed envelope resolves to a household: member accounts via
    // Account_Account_Relationship__c, submitted Financial_Account__c/Service__c rows scoped to the
    // whole household, and a visibility re-check on any Financial_Account__c/Service__c the envelope
    // links directly. None of those tables have rows in the other tests in this file, so those
    // query/loop bodies -- and the Envelope_JSON__c "entities no record holds yet" branch in
    // buildEnvelopeMetrics -- are only exercised here.
    @IsTest
    static void buildEntityCountsCoversHouseholdWideAndDirectlyLinkedRecords() {
        Financial_Advisor_Team__c team = makeTeamForRunningUser('Entity Counts Team');
        Account household = makeHousehold('Entity Counts Household', team.Id);

        // A household member reached only through Account_Account_Relationship__c (submitted, so
        // it counts even though the envelope never links it directly).
        Account householdWideMember = new Account(
            Name = 'Household Wide Member', RecordTypeId = businessRecordTypeId(),
            Type = 'Prospect', Submitted__c = true
        );
        insert householdWideMember;
        insert new Account_Account_Relationship__c(
            Account__c = household.Id, Related_Account__c = householdWideMember.Id
        );

        // A second member the envelope links directly (the outline's "unconditional" pass).
        Account directMember = new Account(
            Name = 'Direct Member', RecordTypeId = businessRecordTypeId(), Type = 'Prospect'
        );
        insert directMember;

        // A submitted Financial Account and Service reached only through the household (not linked
        // to this envelope), plus one of each the envelope links directly.
        Financial_Account__c householdWideFA = new Financial_Account__c(
            Name = 'Household Wide FA', Household__c = household.Id, Submitted__c = true
        );
        Financial_Account__c directFA = new Financial_Account__c(
            Name = 'Direct FA', Household__c = household.Id, Submitted__c = false
        );
        insert new List<Financial_Account__c>{ householdWideFA, directFA };

        Service__c householdWideService = new Service__c(
            Name = 'Household Wide Service', Household__c = household.Id, Submitted__c = true
        );
        Service__c directService = new Service__c(
            Name = 'Direct Service', Household__c = household.Id, Submitted__c = false
        );
        insert new List<Service__c>{ householdWideService, directService };

        Map<String, Object> savedModel = new Map<String, Object>{
            'householdMembers' => new List<Object>{
                new Map<String, Object>{ 'id' => 'local-member-not-yet-saved' },
                // An entity carrying a real record id is treated as already counted via the record
                // and must not be double-counted from the saved model.
                new Map<String, Object>{ 'id' => String.valueOf(directMember.Id) }
            },
            'accounts' => new List<Object>{
                new Map<String, Object>{ 'id' => 'local-isa-not-yet-saved' }
            },
            'dpisSponsor' => new List<Object>{},
            'serviceAgreements' => new List<Object>{}
        };

        Envelope__c envelope = new Envelope__c(
            Name = 'Entity Counts Envelope',
            Status__c = 'New',
            Household__c = household.Id,
            Missing_Items_Count__c = 3,
            Missing_Items_Has_Plus__c = true,
            Envelope_JSON__c = JSON.serialize(savedModel)
        );
        insert envelope;
        insert new List<Envelope_Content__c>{
            new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id),
            new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = directMember.Id),
            new Envelope_Content__c(Envelope__c = envelope.Id, Wizard_Financial_Account__c = directFA.Id),
            new Envelope_Content__c(Envelope__c = envelope.Id, Service__c = directService.Id)
        };

        Test.startTest();
        EnvelopeLandingApex.WizardDataWrapper dto = EnvelopeLandingApex.getWizEnvelopes();
        Test.stopTest();

        EnvelopeLandingApex.EnvelopeMetrics metrics;
        for (EnvelopeLandingApex.EnvelopeMetrics m : dto.envelopeMetrics) {
            if (m.envelopeId == envelope.Id) {
                metrics = m;
            }
        }
        System.assertNotEquals(null, metrics, 'Metrics should be computed for this envelope.');
        System.assertEquals(true, metrics.hasCounts, 'Entity counts should have been built.');
        // Members: the direct pass (directMember) + the household-wide submitted pass
        // (householdWideMember), plus one not-yet-saved entity from the model. directMember's own
        // saved-model entry is skipped because it already carries a record id.
        System.assertEquals(3, metrics.members,
            'Direct + household-wide + one unsaved local member should all be counted once each.');
        // ISAs: directFA + householdWideFA + directService + householdWideService, plus one
        // not-yet-saved local ISA entity from the model.
        System.assertEquals(5, metrics.isas);
        System.assertEquals(3, metrics.missingItemsCount);
        System.assertEquals(true, metrics.missingItemsHasPlus);
    }

    // ---------------------------------------------------------------------------------------------
    // getWizEnvelopeRecords / createWizEnvelope / getEligibleAccounts
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void createAndFetchEnvelopeRecords() {
        Account household = makeHousehold('Create Fetch Household', null);

        Test.startTest();
        EnvelopeLandingApex.EnvelopeCreateResult createResult =
            EnvelopeLandingApex.createWizEnvelope(household.Id, household.Name);
        Id envelopeId = createResult.id;
        List<Envelope_Content__c> records = EnvelopeLandingApex.getWizEnvelopeRecords(envelopeId);
        Test.stopTest();

        System.assertEquals(true, records.size() > 0, 'Envelope record should be created.');

        Account otherAccount = makeHousehold('Create Fetch Other Household', null);

        Envelope_Content__c extraRecord = new Envelope_Content__c(
            Envelope__c = envelopeId,
            Account__c = otherAccount.Id
        );
        insert extraRecord;

        List<Envelope_Content__c> payload = new List<Envelope_Content__c>{ extraRecord };
        List<Account> eligible = EnvelopeLandingApex.getEligibleAccounts(
            household.Id,
            JSON.serialize(payload)
        );

        System.assertEquals(true, eligible.size() > 0, 'Eligible accounts should be returned.');
    }

    // ---------------------------------------------------------------------------------------------
    // renameWizEnvelope / deleteWizEnvelope
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void renamePersistsNewName() {
        Envelope__c env = new Envelope__c(
            Name = 'Old Name',
            Status__c = 'In Progress'
        );
        insert env;

        Test.startTest();
        EnvelopeLandingApex.renameWizEnvelope(env.Id, '  New Name  ');
        Test.stopTest();

        Envelope__c renamed = [SELECT Id, Name FROM Envelope__c WHERE Id = :env.Id LIMIT 1];
        System.assertEquals('New Name', renamed.Name,
            'Rename should persist the trimmed name.');
    }

    @IsTest
    static void renameBlankNameThrows() {
        Envelope__c env = new Envelope__c(
            Name = 'Keep Me',
            Status__c = 'In Progress'
        );
        insert env;

        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeLandingApex.renameWizEnvelope(env.Id, '   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Blank name should throw AuraHandledException.');
    }

    @IsTest
    static void renameNullIdIsANoOp() {
        Test.startTest();
        EnvelopeLandingApex.renameWizEnvelope(null, 'Whatever');
        Test.stopTest();
        System.assert(true, 'A null envelope id should simply return.');
    }

    @IsTest
    static void deleteRemovesDraftEnvelope() {
        Envelope__c env = new Envelope__c(Name = 'Delete Me', Status__c = 'New');
        insert env;

        Test.startTest();
        EnvelopeLandingApex.deleteWizEnvelope(env.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT count() FROM Envelope__c WHERE Id = :env.Id]);
    }

    @IsTest
    static void deleteNullIdIsANoOp() {
        Test.startTest();
        EnvelopeLandingApex.deleteWizEnvelope(null);
        Test.stopTest();
        System.assert(true, 'A null envelope id should simply return.');
    }

    // ---------------------------------------------------------------------------------------------
    // createWizEnvelopeV2
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void createV2ExistingHouseholdUsesTitle() {
        Account household = makeHousehold('Existing Household V2', null);

        Test.startTest();
        EnvelopeLandingApex.EnvelopeCreateResult result = EnvelopeLandingApex.createWizEnvelopeV2(
            '  My Envelope Title  ',
            'existing',
            household.Id,
            null,
            null
        );
        Test.stopTest();

        Envelope__c created = [SELECT Id, Name, Status__c FROM Envelope__c WHERE Id = :result.id LIMIT 1];
        System.assertEquals('My Envelope Title', created.Name,
            'Envelope name should be the trimmed title.');
        System.assertEquals('New', created.Status__c,
            'New envelope should have status New so it appears in the list.');
        System.assertEquals(household.Id, result.householdId);
        System.assertEquals('Existing Household V2', result.householdName);

        List<Envelope_Content__c> records = [
            SELECT Id, Account__c FROM Envelope_Content__c WHERE Envelope__c = :result.id
        ];
        System.assertEquals(1, records.size(), 'One content record should link the household.');
        System.assertEquals(household.Id, records[0].Account__c,
            'Content record should link the chosen household.');
    }

    @IsTest
    static void createV2NewHouseholdCreatesAccount() {
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(Name = 'New HH V2 Team');
        insert team;
        String newHouseholdName = 'Test V2 Household ' + DateTime.now().getTime();

        Test.startTest();
        EnvelopeLandingApex.EnvelopeCreateResult result = EnvelopeLandingApex.createWizEnvelopeV2(
            'New HH Envelope',
            'new',
            null,
            newHouseholdName,
            team.Id
        );
        Test.stopTest();

        Envelope__c created = [SELECT Id, Name FROM Envelope__c WHERE Id = :result.id LIMIT 1];
        System.assertEquals('New HH Envelope', created.Name, 'Envelope name should be the title.');

        Envelope_Content__c record = [
            SELECT Id, Account__c FROM Envelope_Content__c WHERE Envelope__c = :result.id LIMIT 1
        ];
        Account newHousehold = [
            SELECT Id, Name, Financial_Advisor_Team__c, RecordType.DeveloperName
            FROM Account WHERE Id = :record.Account__c LIMIT 1
        ];
        System.assertEquals(newHouseholdName, newHousehold.Name,
            'A new household should be created with the given name.');
        System.assertEquals('Household', newHousehold.RecordType.DeveloperName,
            'New household should use the Household record type the list filters on.');
        System.assertEquals(team.Id, newHousehold.Financial_Advisor_Team__c,
            'New household should carry the chosen advisor team.');
        System.assertEquals(team.Id, result.householdId == null ? null : newHousehold.Financial_Advisor_Team__c);
        System.assertEquals(newHouseholdName, result.householdName);
    }

    @IsTest
    static void createV2BlankTitleThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeLandingApex.createWizEnvelopeV2('   ', 'existing', null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Blank title should throw AuraHandledException.');
    }

    @IsTest
    static void createV2NewHouseholdBlankNameThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeLandingApex.createWizEnvelopeV2('Title', 'new', null, '   ', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'A blank household name in new-household mode should throw.');
    }

    @IsTest
    static void createV2NewHouseholdMissingTeamThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeLandingApex.createWizEnvelopeV2('Title', 'new', null, 'Some Household', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'New-household mode requires an advisor team.');
    }

    @IsTest
    static void createV2MissingHouseholdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            EnvelopeLandingApex.createWizEnvelopeV2('Title', 'existing', null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Existing mode with no household id should throw.');
    }

    // ---------------------------------------------------------------------------------------------
    // V2 list page: getEnvelopeListData / searchEnvelopeListData / searchHouseholds
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void listDataResolvesTeamAndHouseholdPerRowWithoutShippingHouseholds() {
        Financial_Advisor_Team__c team = makeTeamForRunningUser('List Data Team');
        List<Account> households = makeHouseholds(team.Id, new List<String>{ 'List Data Household' });

        Envelope__c teamEnvelope = new Envelope__c(
            Name = 'Team Envelope', Status__c = 'New', Household_Name__c = 'List Data Household'
        );
        Envelope__c ownedEnvelope = new Envelope__c(Name = 'Owned Envelope', Status__c = 'In Progress');
        Envelope__c closedEnvelope = new Envelope__c(Name = 'Closed Envelope', Status__c = 'Complete');
        insert new List<Envelope__c>{ teamEnvelope, ownedEnvelope, closedEnvelope };
        insert new Envelope_Content__c(Envelope__c = teamEnvelope.Id, Account__c = households[0].Id);

        Test.startTest();
        EnvelopeLandingApex.EnvelopeListData data = EnvelopeLandingApex.getEnvelopeListData();
        Test.stopTest();

        Map<Id, EnvelopeLandingApex.EnvelopeRow> rowsById = new Map<Id, EnvelopeLandingApex.EnvelopeRow>();
        for (EnvelopeLandingApex.EnvelopeRow row : data.envelopes) {
            rowsById.put(row.id, row);
        }
        System.assert(rowsById.containsKey(teamEnvelope.Id), 'The team envelope should be listed.');
        System.assert(rowsById.containsKey(ownedEnvelope.Id), 'An owned envelope should be listed.');
        System.assert(!rowsById.containsKey(closedEnvelope.Id), 'A Complete envelope should not be listed.');

        EnvelopeLandingApex.EnvelopeRow teamRow = rowsById.get(teamEnvelope.Id);
        System.assertEquals('Team Envelope', teamRow.name);
        System.assertEquals('List Data Household', teamRow.householdName);
        System.assertEquals(households[0].Id, teamRow.householdId,
            'The household id should come from the junction row.');
        System.assertEquals('List Data Team', teamRow.advisorTeamName,
            'The advisor team should be resolved server-side through the household.');
        System.assertNotEquals(null, teamRow.createdDate);
        System.assertNotEquals(null, teamRow.lastModifiedByName);

        EnvelopeLandingApex.EnvelopeRow ownedRow = rowsById.get(ownedEnvelope.Id);
        System.assertEquals(null, ownedRow.householdId, 'No junction row, no household.');
        System.assertEquals(null, ownedRow.advisorTeamName, 'No household, no team.');

        Boolean hasTeamOption = false;
        for (EnvelopeLandingApex.Option option : data.advisorTeamOptions) {
            if (option.value == team.Id) {
                hasTeamOption = true;
                System.assertEquals('List Data Team', option.label);
            }
        }
        System.assert(hasTeamOption, 'The user\'s team should be offered for a new household.');

        Boolean hasMetrics = false;
        for (EnvelopeLandingApex.EnvelopeMetrics metrics : data.envelopeMetrics) {
            if (metrics.envelopeId == teamEnvelope.Id) {
                hasMetrics = true;
            }
        }
        System.assert(hasMetrics, 'Metrics should be computed for every listed envelope.');
    }

    @IsTest
    static void searchListDataFindsTeamEnvelopeByFixedSearchResult() {
        Financial_Advisor_Team__c team = makeTeamForRunningUser('Search List Data Team');
        List<Account> households = makeHouseholds(
            team.Id,
            new List<String>{ 'Search List Data Household' }
        );

        Envelope__c teamEnvelope = new Envelope__c(
            Name = 'Zephyr Team Envelope',
            Status__c = 'New',
            Household_Name__c = 'Search List Data Household'
        );
        insert teamEnvelope;
        insert new Envelope_Content__c(Envelope__c = teamEnvelope.Id, Account__c = households[0].Id);

        Test.setFixedSearchResults(new List<Id>{ teamEnvelope.Id });

        Test.startTest();
        EnvelopeLandingApex.EnvelopeListData data = EnvelopeLandingApex.searchEnvelopeListData(
            'Zephyr'
        );
        Test.stopTest();

        System.assertEquals(1, data.envelopes.size(),
            'Search should return the matching envelope.');
        EnvelopeLandingApex.EnvelopeRow row = data.envelopes[0];
        System.assertEquals(teamEnvelope.Id, row.id);
        System.assertEquals('Search List Data Team', row.advisorTeamName,
            'Search results should resolve the advisor team the same way getEnvelopeListData does.');
    }

    @IsTest
    static void searchListDataBelowMinLengthReturnsNoEnvelopes() {
        Test.startTest();
        EnvelopeLandingApex.EnvelopeListData data = EnvelopeLandingApex.searchEnvelopeListData('a');
        Test.stopTest();

        System.assertEquals(0, data.envelopes.size(),
            'A term below the minimum length should not reach the server search.');
    }

    @IsTest
    static void searchHouseholdsMatchesTermWithinUsersTeams() {
        Financial_Advisor_Team__c mine = makeTeamForRunningUser('Search Team');
        makeHouseholds(mine.Id, new List<String>{
            'Zq Alpha Search Household', 'Zq Beta Search Household', 'Unrelated Name'
        });
        // A household on a team the user is not on must never come back.
        Group otherGroup = new Group(Name = 'Other Search Group', Type = 'Regular');
        insert otherGroup;
        Financial_Advisor_Team__c other = new Financial_Advisor_Team__c(
            Name = 'Other Search Team', Public_Group_Id__c = otherGroup.Id
        );
        insert other;
        makeHouseholds(other.Id, new List<String>{ 'Zq Gamma Search Household' });

        Test.startTest();
        List<EnvelopeLandingApex.Option> matches = EnvelopeLandingApex.searchHouseholds('zq ');
        List<EnvelopeLandingApex.Option> tooShort = EnvelopeLandingApex.searchHouseholds('z');
        List<EnvelopeLandingApex.Option> blank = EnvelopeLandingApex.searchHouseholds(null);
        Test.stopTest();

        Set<String> labels = new Set<String>();
        for (EnvelopeLandingApex.Option option : matches) {
            labels.add(option.label);
        }
        System.assert(labels.contains('Zq Alpha Search Household'), 'Alpha should match: ' + labels);
        System.assert(labels.contains('Zq Beta Search Household'), 'Beta should match: ' + labels);
        System.assert(!labels.contains('Unrelated Name'), 'A non-matching name should not come back.');
        System.assert(!labels.contains('Zq Gamma Search Household'),
            'A household on another team should not come back.');
        System.assertEquals('Zq Alpha Search Household', matches[0].label,
            'Results should be ordered by name.');
        System.assertEquals(0, tooShort.size(), 'Under two characters returns nothing.');
        System.assertEquals(0, blank.size(), 'A null term returns nothing.');
    }

    @IsTest
    static void searchHouseholdsTreatsWildcardsLiterallyAndCapsThePage() {
        Financial_Advisor_Team__c team = makeTeamForRunningUser('Wildcard Team');
        List<String> names = new List<String>{ 'Zq 100% Trust', 'Zq 100 Trust', 'Zq_Under Trust', 'ZqXUnder Trust' };
        for (Integer i = 0; i < 55; i++) {
            names.add('Zq Bulk Household ' + String.valueOf(i).leftPad(3, '0'));
        }
        makeHouseholds(team.Id, names);

        Test.startTest();
        List<EnvelopeLandingApex.Option> percent = EnvelopeLandingApex.searchHouseholds('100%');
        List<EnvelopeLandingApex.Option> underscore = EnvelopeLandingApex.searchHouseholds('zq_under');
        List<EnvelopeLandingApex.Option> paged = EnvelopeLandingApex.searchHouseholds('Zq Bulk Household');
        Test.stopTest();

        System.assertEquals(1, percent.size(), '% is a literal, not a wildcard: ' + percent);
        System.assertEquals('Zq 100% Trust', percent[0].label);
        System.assertEquals(1, underscore.size(), '_ is a literal, not a wildcard: ' + underscore);
        System.assertEquals('Zq_Under Trust', underscore[0].label);
        System.assertEquals(50, paged.size(), 'The page is capped at 50 of the 55 matches.');
    }

    @IsTest
    static void searchHouseholdsReturnsNothingWhenUserHasNoTeam() {
        Test.startTest();
        List<EnvelopeLandingApex.Option> result = EnvelopeLandingApex.searchHouseholds('anything');
        Test.stopTest();
        System.assertEquals(0, result.size(), 'A user on no team has nothing to search.');
    }
}