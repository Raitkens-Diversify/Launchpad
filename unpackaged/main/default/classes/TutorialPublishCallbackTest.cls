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
        TutorialAdminController.saveDraftStep(
            null, tourId, 2, '[data-tour-id="cb2"]', 'Step Two', '<p>Body</p>', 'top', 'click');
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

        List<Tutorial_Step_Draft__c> steps = [
            SELECT Published__c, Last_Published__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ];
        System.assertEquals(2, steps.size(), 'Both steps written back');
        for (Tutorial_Step_Draft__c step : steps) {
            System.assertEquals(true, step.Published__c);
            System.assertEquals(tour.Last_Published__c, step.Last_Published__c,
                'Tour and steps share one publish instant');
        }
    }

    @isTest
    static void successClearsPreviousError() {
        Id tourId = makeDraft();
        update new Tutorial_Tour_Draft__c(Id = tourId, Publish_Error__c = 'Failed: earlier attempt');

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;
        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(true, tour.Published__c);
        System.assertEquals(null, tour.Publish_Error__c, 'A later success wipes the stale error');
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
        for (Tutorial_Step_Draft__c step : [
            SELECT Published__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]) {
            System.assertEquals(false, step.Published__c, 'Steps untouched on failure');
        }
    }

    @isTest
    static void failureUsesFirstComponentProblem() {
        Id tourId = makeDraft();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;
        Metadata.DeployDetails details = new Metadata.DeployDetails();
        Metadata.DeployMessage first = new Metadata.DeployMessage();
        first.problem = 'Field Body__c is too long';
        Metadata.DeployMessage second = new Metadata.DeployMessage();
        second.problem = 'Second problem is not reported';
        details.componentFailures = new List<Metadata.DeployMessage>{ first, second };
        result.details = details;
        result.errorMessage = 'Generic error is outranked by the component problem';

        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(false, tour.Published__c);
        System.assert(tour.Publish_Error__c.startsWith('Failed: '), 'Status prefix: ' + tour.Publish_Error__c);
        System.assert(tour.Publish_Error__c.contains('Field Body__c is too long'),
            'First component problem captured: ' + tour.Publish_Error__c);
        System.assert(!tour.Publish_Error__c.contains('Second problem'), 'Only the first problem is reported');
        System.assert(!tour.Publish_Error__c.contains('Generic error'), 'Component problem wins over errorMessage');
    }

    @isTest
    static void failureFallsBackToErrorMessageWhenNoComponentFailures() {
        Id tourId = makeDraft();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.CANCELED;
        result.details = new Metadata.DeployDetails(); // componentFailures null
        result.errorMessage = 'Deployment canceled by an administrator';

        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(false, tour.Published__c);
        System.assertEquals('Canceled: Deployment canceled by an administrator', tour.Publish_Error__c);
    }

    @isTest
    static void failureMessageIsAbbreviatedToFieldLength() {
        Id tourId = makeDraft();

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;
        result.errorMessage = 'x'.repeat(600);

        new TutorialPublishCallback(tourId).handleResult(result, new TestContext());

        Tutorial_Tour_Draft__c tour = [SELECT Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId];
        System.assertEquals(255, tour.Publish_Error__c.length(), 'Abbreviated to the 255-char field');
        System.assert(tour.Publish_Error__c.endsWith('...'), 'Abbreviation marker present');
    }

    @isTest
    static void nullResultTreatedAsFailure() {
        Id tourId = makeDraft();

        new TutorialPublishCallback(tourId).handleResult(null, new TestContext());

        Tutorial_Tour_Draft__c tour = [
            SELECT Published__c, Publish_Error__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals(false, tour.Published__c);
        System.assertEquals('Deployment failed (no result returned).', tour.Publish_Error__c);
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