@isTest
private class TutorialPublishCallbackTest {

    private class TestContext extends Metadata.DeployCallbackContext {
        public override Id getCallbackJobId() {
            return '0Af000000000001AAA';
        }
    }

    private static Id makeDraft() {
        Id tourId = TutorialAdminController.saveDraftTour(null, 'cb_tour', 'Callback Tour', true, true, 1);
        TutorialAdminController.saveDraftStep(
            null, tourId, 1, '[data-tour-id="cb"]', 'Step One', '<p>Body</p>', 'auto', 'button');
        return tourId;
    }

    @isTest
    static void successMarksTourAndStepsPublished() {
        Id tourId = makeDraft();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;

        Test.startTest();
        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());
        Test.stopTest();

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Last_Published__c, Publish_Error__c
            FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(true, tour.Published__c);
        System.assertNotEquals(null, tour.Last_Published__c);
        System.assertEquals(null, tour.Publish_Error__c);

        for (Tutorial_Step_Draft__c step : [
            SELECT Published__c, Last_Published__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]) {
            System.assertEquals(true, step.Published__c);
            System.assertNotEquals(null, step.Last_Published__c);
        }
    }

    @isTest
    static void failureWritesErrorAndLeavesPublishedFlag() {
        Id tourId = makeDraft();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;

        Test.startTest();
        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());
        Test.stopTest();

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(false, tour.Published__c, 'Failed deploy must not mark published');
        System.assert(tour.Publish_Error__c.containsIgnoreCase('failed'), 'Status captured: ' + tour.Publish_Error__c);
    }

    @isTest
    static void nullResultTreatedAsFailure() {
        Id tourId = makeDraft();

        new TutorialPublishCallback(tourId).handleResult(null, new TestContext());

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(false, tour.Published__c);
        System.assertNotEquals(null, tour.Publish_Error__c);
    }

    @isTest
    static void deletedDraftIsIgnored() {
        Id tourId = makeDraft();
        TutorialAdminController.deleteDraftTour(tourId);

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;

        // Must not throw.
        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Tour_Draft__c WHERE Id = :tourId]);
    }
}