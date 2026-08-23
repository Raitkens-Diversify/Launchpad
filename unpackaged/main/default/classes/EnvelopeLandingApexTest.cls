@IsTest(SeeAllData=true)
private class EnvelopeLandingApexTest {
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
    static void createAndFetchEnvelopeRecords() {
        List<Account> households = [
            SELECT Id, Name
            FROM Account
            WHERE RecordType.DeveloperName = 'IndustriesHousehold'
            LIMIT 1
        ];
        System.assertEquals(false, households.isEmpty(), 'Test requires a household account.');
        Account household = households[0];

        Test.startTest();
        EnvelopeLandingApex.EnvelopeCreateResult createResult =
            EnvelopeLandingApex.createWizEnvelope(household.Id, household.Name);
        Id envelopeId = createResult.id;
        List<Envelope_Content__c> records = EnvelopeLandingApex.getWizEnvelopeRecords(envelopeId);
        Test.stopTest();

        System.assertEquals(true, records.size() > 0, 'Envelope record should be created.');

        List<Account> otherAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE Id != :household.Id
            LIMIT 1
        ];
        System.assertEquals(false, otherAccounts.isEmpty(), 'Test requires a second account.');
        Account otherAccount = otherAccounts[0];

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
    static void createV2ExistingHouseholdUsesTitle() {
        List<Account> households = [
            SELECT Id, Name
            FROM Account
            WHERE RecordType.DeveloperName = 'IndustriesHousehold'
            LIMIT 1
        ];
        System.assertEquals(false, households.isEmpty(), 'Test requires a household account.');
        Account household = households[0];

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

        List<Envelope_Content__c> records = [
            SELECT Id, Account__c FROM Envelope_Content__c WHERE Envelope__c = :result.id
        ];
        System.assertEquals(1, records.size(), 'One content record should link the household.');
        System.assertEquals(household.Id, records[0].Account__c,
            'Content record should link the chosen household.');
    }

    @IsTest
    static void createV2NewHouseholdCreatesAccount() {
        // Reuse an existing household's advisor team so the test data is valid in-org.
        List<Account> households = [
            SELECT Id, Financial_Advisor_Team__c
            FROM Account
            WHERE RecordType.DeveloperName = 'IndustriesHousehold'
            AND Financial_Advisor_Team__c != null
            LIMIT 1
        ];
        System.assertEquals(false, households.isEmpty(),
            'Test requires a household with an advisor team.');
        Id teamId = households[0].Financial_Advisor_Team__c;
        String newHouseholdName = 'Test V2 Household ' + DateTime.now().getTime();

        Test.startTest();
        EnvelopeLandingApex.EnvelopeCreateResult result = EnvelopeLandingApex.createWizEnvelopeV2(
            'New HH Envelope',
            'new',
            null,
            newHouseholdName,
            teamId
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
        System.assertEquals(teamId, newHousehold.Financial_Advisor_Team__c,
            'New household should carry the chosen advisor team.');
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

    // ---------------------------------------------------------------------------------------------
    // V2 list page: getEnvelopeListData / searchHouseholds
    // ---------------------------------------------------------------------------------------------

    // A Financial Advisor Team the running user belongs to, with `count` Household accounts on it.
    private static Financial_Advisor_Team__c makeTeamForRunningUser(String teamName) {
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

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Household')
            .getRecordTypeId();
    }

    private static List<Account> makeHouseholds(Id teamId, List<String> names) {
        List<Account> households = new List<Account>();
        for (String name : names) {
            households.add(new Account(
                Name = name,
                RecordTypeId = householdRecordTypeId(),
                Financial_Advisor_Team__c = teamId
            ));
        }
        insert households;
        return households;
    }

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
}