@IsTest
private class SynonymAdminControllerTest {

    /** Captures the deploy container instead of enqueueing (which throws in tests). */
    private class FakeDeployer implements SynonymAdminController.MetadataDeployer {
        Metadata.DeployContainer lastContainer;
        Integer calls = 0;
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            this.lastContainer = container;
            this.calls++;
            return '0Af000000000001AAA';
        }
    }

    private class ExplodingDeployer implements SynonymAdminController.MetadataDeployer {
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            throw new System.NoAccessException();
        }
    }

    private static Search_Synonym__mdt row(String devName, String term, String synonyms,
            Boolean bidirectional, Boolean active) {
        return new Search_Synonym__mdt(
            DeveloperName = devName,
            Term__c = term,
            Synonyms__c = synonyms,
            Bidirectional__c = bidirectional,
            Is_Active__c = active
        );
    }

    private static Metadata.CustomMetadata onlyRecord(FakeDeployer fake) {
        System.assertEquals(1, fake.lastContainer.getMetadata().size(), 'One record per deploy');
        return (Metadata.CustomMetadata) fake.lastContainer.getMetadata()[0];
    }

    private static Map<String, Object> valueMap(Metadata.CustomMetadata md) {
        Map<String, Object> out = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : md.values) {
            out.put(v.field, v.value);
        }
        return out;
    }

    @IsTest
    static void getSynonymsSortsAndFlagsInactive() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>{
            'Zeta' => row('Zeta', 'zeta', 'omega', true, true),
            'Alpha' => row('Alpha', 'alpha', 'beta', false, false)
        };

        List<SynonymAdminController.SynonymDTO> out = SynonymAdminController.getSynonyms();

        System.assertEquals(2, out.size());
        System.assertEquals('Alpha', out[0].developerName, 'Sorted by developer name');
        System.assertEquals(false, out[0].active, 'Inactive flag surfaces');
        System.assertEquals(false, out[0].bidirectional);
        System.assertEquals(true, out[1].active);
    }

    @IsTest
    static void saveNewSynonymDeploysNormalizedRecord() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>();
        FakeDeployer fake = new FakeDeployer();
        SynonymAdminController.deployer = fake;

        String devName = SynonymAdminController.saveSynonym(
            null, '  Rollover ', 'ACAT, Transfer-In', true);

        System.assertEquals('Rollover', devName, 'DeveloperName derived from the term');
        Metadata.CustomMetadata md = onlyRecord(fake);
        System.assertEquals('Search_Synonym.Rollover', md.fullName);
        System.assertEquals('rollover', md.label, 'Label = normalized term');
        Map<String, Object> vals = valueMap(md);
        System.assertEquals('rollover', vals.get('Term__c'), 'Term trimmed + lowercased');
        System.assertEquals('acat, transfer-in', vals.get('Synonyms__c'));
        System.assertEquals(true, vals.get('Bidirectional__c'));
        System.assertEquals(true, vals.get('Is_Active__c'), 'New records deploy active');
    }

    @IsTest
    static void developerNameDerivationCleansAndDeduplicates() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>{
            'Roll_over_cash' => row('Roll_over_cash', 'x', 'y', true, true)
        };

        System.assertEquals('Roll_over_cash_2',
            SynonymAdminController.deriveDeveloperName('roll-over cash!'),
            'Non-alphanumerics collapse to underscores; collisions get a numeric suffix');
        System.assertEquals('S_401k',
            SynonymAdminController.deriveDeveloperName('401k'),
            'Names must start with a letter');
    }

    @IsTest
    static void deactivateReemitsFullRecordInactive() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>{
            'Advisor' => row('Advisor', 'advisor', 'adviser,rep', true, true)
        };
        FakeDeployer fake = new FakeDeployer();
        SynonymAdminController.deployer = fake;

        SynonymAdminController.setSynonymActive('Advisor', false);

        Map<String, Object> vals = valueMap(onlyRecord(fake));
        System.assertEquals(false, vals.get('Is_Active__c'));
        System.assertEquals('advisor', vals.get('Term__c'),
            'Deploys replace all values, so the full record is re-emitted');
        System.assertEquals('adviser,rep', vals.get('Synonyms__c'));
        System.assertEquals(true, vals.get('Bidirectional__c'));
    }

    @IsTest
    static void updateUnknownRecordThrows() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>();
        try {
            SynonymAdminController.saveSynonym('Missing', 'term', 'syn', true);
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            SynonymAdminController.setSynonymActive('Missing', false);
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void blankAndOversizeInputRejected() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>();
        SynonymAdminController.deployer = new FakeDeployer();

        try {
            SynonymAdminController.saveSynonym(null, '  ', 'syn', true);
            System.assert(false, 'Blank term must throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            SynonymAdminController.saveSynonym(null, 'term', 'x'.repeat(256), true);
            System.assert(false, 'Oversize synonyms must throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void deployFailureSurfacesFriendlyError() {
        SynonymAdminController.testRows = new Map<String, Search_Synonym__mdt>();
        SynonymAdminController.deployer = new ExplodingDeployer();
        try {
            SynonymAdminController.saveSynonym(null, 'term', 'syn', true);
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void minimalUserIsRejected() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            Alias = 'synmin',
            Email = 'syn.min@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SynMin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'syn.min.' + System.currentTimeMillis() + '@example.com.cosmosdev'
        );
        insert u;
        System.runAs(u) {
            try {
                SynonymAdminController.getSynonyms();
                System.assert(false, 'Expected an access exception');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }
}