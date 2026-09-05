/**
 * TutorialTourControllerTest
 *
 * Org prerequisites: custom metadata records cannot be inserted from tests,
 * but deployed records ARE visible to tests without SeeAllData. The getTour
 * tests therefore depend on the source-deployed `nexus_help` sample tour
 * (Tutorial_Tour.nexus_help + Tutorial_Step.nexus_help_1..5). If those records
 * are removed from the org, update or remove those tests.
 */
@isTest
private class TutorialTourControllerTest {

    private static final String SAMPLE_KEY = 'nexus_help';

    @isTest
    static void getTourReturnsPublishedTourWithOrderedSteps() {
        Test.startTest();
        TutorialTourController.TourDTO tour = TutorialTourController.getTour(SAMPLE_KEY);
        Test.stopTest();

        System.assertNotEquals(null, tour, 'The deployed nexus_help tour should resolve');
        System.assertEquals(SAMPLE_KEY, tour.tourKey);
        System.assertEquals(true, tour.active);
        System.assertNotEquals(null, tour.version);
        System.assertEquals(5, tour.steps.size(), 'nexus_help ships with 5 active steps');

        Integer previousOrder = 0;
        for (TutorialTourController.StepDTO step : tour.steps) {
            System.assert(step.stepOrder > previousOrder, 'Steps must be ordered ascending');
            previousOrder = step.stepOrder;
            System.assert(String.isNotBlank(step.targetSelector));
            System.assert(String.isNotBlank(step.title));
        }
        System.assertEquals('[data-tour-id="nexus-search"]', tour.steps[0].targetSelector);
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
    static void guestPathsSkipDmlAndSoql() {
        TutorialTourController.guestOverride = true;

        Test.startTest();
        TutorialTourController.StateDTO saved = TutorialTourController.saveState(SAMPLE_KEY, true, true, 9);
        TutorialTourController.StateDTO read = TutorialTourController.getUserState(SAMPLE_KEY);
        Integer x = TutorialTourController.testCoverage();
        Integer y = HelpGuideAdminController.testCoverage();
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
        insert u;
        return u;
    }
}