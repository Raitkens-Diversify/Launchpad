/**
 * TutorialTourControllerTest
 *
 * Org prerequisites: custom metadata records cannot be inserted from tests,
 * but deployed records ARE visible to tests without SeeAllData. The getTour
 * tests therefore read the source-deployed `nexus_help` sample tour
 * (Tutorial_Tour.nexus_help + Tutorial_Step.nexus_help_*) and assert RELATIVE
 * to the deployed Tutorial_Step__mdt rows, never against a hard-coded step
 * count — the sample tour grows with the product. If the tour is absent from
 * the org, the getTour test asserts the documented "no tour" contract instead. */
@isTest
private class TutorialTourControllerTest {

    private static final String SAMPLE_KEY = 'nexus_help';

    @isTest
    static void getTourReturnsPublishedTourWithOrderedSteps() {
        // The expectation comes from the deployed metadata, not a literal.
        List<Tutorial_Step__mdt> publishedSteps = [
            SELECT Target_Selector__c, Order__c
            FROM Tutorial_Step__mdt
            WHERE Tour__r.Tour_Key__c = :SAMPLE_KEY AND Tour__r.Active__c = true AND Active__c = true
            ORDER BY Order__c ASC
        ];

        Test.startTest();
        TutorialTourController.TourDTO tour = TutorialTourController.getTour(SAMPLE_KEY);
        Test.stopTest();

        if (publishedSteps.isEmpty()
            && [SELECT COUNT() FROM Tutorial_Tour__mdt WHERE Tour_Key__c = :SAMPLE_KEY AND Active__c = true] == 0) {
            System.assertEquals(null, tour, 'No active tour for the key resolves to null (client stays inert)');
            return;
        }

        System.assertNotEquals(null, tour, 'The deployed nexus_help tour should resolve');
        System.assertEquals(SAMPLE_KEY, tour.tourKey);
        System.assertEquals(true, tour.active);
        System.assertNotEquals(null, tour.version);
        System.assertEquals(publishedSteps.size(), tour.steps.size(),
            'Every active published step of the tour is returned');
        Integer previousOrder = 0;
        for (TutorialTourController.StepDTO step : tour.steps) {
            System.assert(step.stepOrder > previousOrder, 'Steps must be ordered ascending');
            previousOrder = step.stepOrder;
            System.assert(String.isNotBlank(step.targetSelector));
            System.assert(String.isNotBlank(step.title));
            System.assert(String.isNotBlank(step.placement), 'Placement always defaults');
            System.assert(String.isNotBlank(step.advanceOn), 'Advance mode always defaults');
        }
        if (!publishedSteps.isEmpty()) {
            System.assertEquals(publishedSteps[0].Target_Selector__c, tour.steps[0].targetSelector,
                'First step is the lowest-ordered published step');
        }
    }

    @isTest
    static void getTourUnknownKeyReturnsNull() {
        System.assertEquals(null, TutorialTourController.getTour('no_such_tour_zz'));
    }

    @isTest
    static void getTourInvalidKeyThrows() {
        try {
            TutorialTourController.getTour('bad key; DROP');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void stateApisRejectInvalidKeys() {
        for (String bad : new List<String>{ null, '', '   ', 'has spaces', 'semi;colon',
                                            'x'.repeat(41) }) {
            try {
                TutorialTourController.getUserState(bad);
                System.assert(false, 'getUserState must reject key: ' + bad);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            try {
                TutorialTourController.saveState(bad, true, false, 1);
                System.assert(false, 'saveState must reject key: ' + bad);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_State__c], 'Rejected keys never write');
    }

    @isTest
    static void saveStateUpsertsSingleRecord() {
        Test.startTest();
        TutorialTourController.saveState(SAMPLE_KEY, false, true, 1);
        TutorialTourController.StateDTO second = TutorialTourController.saveState(SAMPLE_KEY, true, false, 2);
        Test.stopTest();

        List<Tutorial_State__c> rows = [
            SELECT User__c, Tour_Key__c, State_Key__c, Completed__c, Dismissed__c, Version_Seen__c
            FROM Tutorial_State__c
        ];
        System.assertEquals(1, rows.size(), 'Upsert on State_Key__c must not duplicate');
        System.assertEquals(UserInfo.getUserId() + '_' + SAMPLE_KEY, rows[0].State_Key__c);
        System.assertEquals(UserInfo.getUserId(), rows[0].User__c);
        System.assertEquals(true, rows[0].Completed__c, 'Second write wins');
        System.assertEquals(false, rows[0].Dismissed__c);
        System.assertEquals(2, rows[0].Version_Seen__c);
        System.assertEquals(true, second.completed);
        System.assertEquals(false, second.isGuest);
    }

    @isTest
    static void saveStateNullFlagsPersistAsFalse() {
        TutorialTourController.StateDTO dto = TutorialTourController.saveState(SAMPLE_KEY, null, null, null);
        System.assertEquals(false, dto.completed, 'null completed -> false');
        System.assertEquals(false, dto.dismissed, 'null dismissed -> false');
        System.assertEquals(null, dto.versionSeen);
        Tutorial_State__c row = [SELECT Completed__c, Dismissed__c, Version_Seen__c FROM Tutorial_State__c];
        System.assertEquals(false, row.Completed__c);
        System.assertEquals(false, row.Dismissed__c);
        System.assertEquals(null, row.Version_Seen__c);
    }

    @isTest
    static void getUserStateReturnsSavedState() {
        TutorialTourController.saveState(SAMPLE_KEY, true, false, 3);

        TutorialTourController.StateDTO state = TutorialTourController.getUserState(SAMPLE_KEY);
        System.assertEquals(true, state.completed);
        System.assertEquals(false, state.dismissed);
        System.assertEquals(3, state.versionSeen);
        System.assertEquals(false, state.isGuest);
        System.assertEquals(SAMPLE_KEY, state.tourKey);
    }

    @isTest
    static void getUserStateEmptyReturnsDefaults() {
        TutorialTourController.StateDTO state = TutorialTourController.getUserState(SAMPLE_KEY);
        System.assertEquals(false, state.completed);
        System.assertEquals(false, state.dismissed);
        System.assertEquals(null, state.versionSeen);
        System.assertEquals(false, state.isGuest);
    }

    @isTest
    static void guestPathsSkipDmlAndSoql() {
        TutorialTourController.guestOverride = true;

        Test.startTest();
        TutorialTourController.StateDTO saved = TutorialTourController.saveState(SAMPLE_KEY, true, true, 9);
        TutorialTourController.StateDTO read = TutorialTourController.getUserState(SAMPLE_KEY);
        Test.stopTest();

        System.assertEquals(true, saved.isGuest);
        System.assertEquals(true, read.isGuest);
        System.assertEquals(false, saved.completed, 'Guest DTO carries no persisted flags');
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_State__c], 'Guest must never write state');
    }

    @isTest
    static void saveStateWithoutObjectAccessThrows() {
        User restricted = makeRestrictedUser();
        System.runAs(restricted) {
            try {
                TutorialTourController.saveState(SAMPLE_KEY, true, false, 1);
                System.assert(false, 'Expected AuraHandledException for a user without object access');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void getUserStateWithoutObjectAccessThrows() {
        User restricted = makeRestrictedUser();
        System.runAs(restricted) {
            try {
                TutorialTourController.getUserState(SAMPLE_KEY);
                System.assert(false, 'Expected AuraHandledException for a user without object access');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    /**
     * Standard User with every automation-assigned permission set stripped, so
     * "no access" really is no access (an org flow assigns Help Center sets to
     * every new internal user). Setup-object DML is isolated in runAs to avoid
     * MIXED_DML with any data the test writes afterwards.
     */
    private static User makeRestrictedUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = 'trest',
            Email = 'tour.restricted@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TourRestricted',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'tour.restricted.' + uniq + '@example.com.test'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            delete [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :u.Id
                AND (PermissionSetGroupId != null OR PermissionSet.IsOwnedByProfile = false)
            ];
        }
        return u;
    }
}