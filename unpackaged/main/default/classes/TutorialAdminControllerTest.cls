/**
 * TutorialAdminControllerTest
 *
 * Publish tests use the injectable MetadataDeployer seam — real deployments
 * cannot be enqueued from test context. Orphan/import tests depend on the
 * source-deployed `nexus_help` custom metadata records (see
 * TutorialTourControllerTest header for that org prerequisite).
 */
@isTest
private class TutorialAdminControllerTest {

    private class MockDeployer implements TutorialAdminController.MetadataDeployer {
        Metadata.DeployContainer captured;
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            captured = container;
            return '0Af000000000001AAA';
        }
    }

    private static Id makeTour(String key, String label) {
        return TutorialAdminController.saveDraftTour(null, key, label, true, true, 1);
    }

    private static Id makeStep(Id tourId, Integer stepOrder, String title) {
        return TutorialAdminController.saveDraftStep(
            null, tourId, stepOrder, '[data-tour-id="t' + stepOrder + '"]',
            title, '<p>Body ' + stepOrder + '</p>', 'auto', 'button');
    }

    // ---- Draft CRUD ----------------------------------------------------------

    @isTest
    static void saveDraftTourInsertsAndUpdates() {
        Id tourId = makeTour('my_tour', 'My Tour');

        Tutorial_Tour_Draft__c tour = [
            SELECT Name, Tour_Key__c, Label__c, Active__c, Auto_Start__c, Version__c, Published__c
            FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals('my_tour', tour.Tour_Key__c);
        System.assertEquals('My Tour', tour.Label__c);
        System.assertEquals('My Tour', tour.Name);
        System.assertEquals(true, tour.Active__c);
        System.assertEquals(1, tour.Version__c);

        TutorialAdminController.saveDraftTour(tourId, 'my_tour', 'My Tour v2', false, false, 2);
        tour = [SELECT Label__c, Active__c, Version__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId];
        System.assertEquals('My Tour v2', tour.Label__c);
        System.assertEquals(false, tour.Active__c);
        System.assertEquals(2, tour.Version__c);
    }

    @isTest
    static void saveDraftTourRejectsBadKeys() {
        for (String badKey : new List<String>{ 'Bad Key!', '1leading', 'has__double', 'trailing_',
                                               'wayyyyyy_tooooo_loooong_key_over_30x' }) {
            try {
                makeTour(badKey, 'Bad');
                System.assert(false, 'Expected rejection of key: ' + badKey);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @isTest
    static void saveDraftTourKeyImmutableOncePublished() {
        Id tourId = makeTour('locked_tour', 'Locked');
        update new Tutorial_Tour_Draft__c(Id = tourId, Last_Published__c = System.now());

        try {
            TutorialAdminController.saveDraftTour(tourId, 'renamed_tour', 'Locked', true, true, 1);
            System.assert(false, 'Expected key-change rejection on a published tour');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void saveDraftStepValidatesAndDefaultsOrder() {
        Id tourId = makeTour('step_tour', 'Step Tour');
        makeStep(tourId, 1, 'One');

        // Null order defaults to max+1.
        Id stepId = TutorialAdminController.saveDraftStep(
            null, tourId, null, '[data-tour-id="two"]', 'Two', null, null, null);
        Tutorial_Step_Draft__c step = [
            SELECT Order__c, Placement__c, Advance_On__c FROM Tutorial_Step_Draft__c WHERE Id = :stepId
        ];
        System.assertEquals(2, step.Order__c);
        System.assertEquals('auto', step.Placement__c, 'Blank placement defaults');
        System.assertEquals('button', step.Advance_On__c, 'Blank advance mode defaults');

        // Saving a step flips the parent back to unpublished.
        System.assertEquals(false, [
            SELECT Published__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ].Published__c);

        try {
            TutorialAdminController.saveDraftStep(null, tourId, 3, '[data-x]', 'Bad', null, 'diagonal', 'button');
            System.assert(false, 'Expected placement rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            TutorialAdminController.saveDraftStep(null, tourId, 3, '', 'Bad', null, 'auto', 'button');
            System.assert(false, 'Expected blank-selector rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void deleteDraftTourCascadesSteps() {
        Id tourId = makeTour('doomed', 'Doomed');
        makeStep(tourId, 1, 'One');

        TutorialAdminController.deleteDraftTour(tourId);
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Tour_Draft__c WHERE Id = :tourId]);
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Step_Draft__c], 'Master-detail cascades');
    }

    @isTest
    static void deleteDraftStepMarksParentUnpublished() {
        Id tourId = makeTour('trimmed', 'Trimmed');
        Id stepId = makeStep(tourId, 1, 'One');
        update new Tutorial_Tour_Draft__c(Id = tourId, Published__c = true);

        TutorialAdminController.deleteDraftStep(stepId);
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Step_Draft__c WHERE Id = :stepId]);
        System.assertEquals(false, [
            SELECT Published__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ].Published__c);
    }

    @isTest
    static void reorderStepsAssignsSequentialOrder() {
        Id tourId = makeTour('ordered', 'Ordered');
        Id a = makeStep(tourId, 1, 'A');
        Id b = makeStep(tourId, 2, 'B');
        Id c = makeStep(tourId, 3, 'C');

        TutorialAdminController.reorderSteps(tourId, new List<Id>{ c, b, a });

        Map<Id, Tutorial_Step_Draft__c> rows = new Map<Id, Tutorial_Step_Draft__c>([
            SELECT Order__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]);
        System.assertEquals(1, rows.get(c).Order__c);
        System.assertEquals(2, rows.get(b).Order__c);
        System.assertEquals(3, rows.get(a).Order__c);
    }

    @isTest
    static void reorderStepsRejectsMismatchedIdSet() {
        Id tourId = makeTour('strict', 'Strict');
        Id a = makeStep(tourId, 1, 'A');
        Id otherTour = makeTour('other', 'Other');
        Id foreign = makeStep(otherTour, 1, 'Foreign');

        try {
            TutorialAdminController.reorderSteps(tourId, new List<Id>{ a, foreign });
            System.assert(false, 'Expected mismatch rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ---- Publish -------------------------------------------------------------

    @isTest
    static void publishBuildsCorrectContainer() {
        Id tourId = makeTour('my_tour', 'My Tour');
        makeStep(tourId, 1, 'First');
        makeStep(tourId, 2, 'Second');
        makeStep(tourId, 3, 'Third');

        MockDeployer mock = new MockDeployer();
        TutorialAdminController.deployer = mock;

        Test.startTest();
        String jobId = TutorialAdminController.publish(tourId);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertNotEquals(null, mock.captured, 'Deployment must be enqueued');

        Map<String, Metadata.CustomMetadata> byName = indexContainer(mock.captured);
        System.assertEquals(4, byName.size(), 'Tour + 3 steps');

        Metadata.CustomMetadata tourMd = byName.get('Tutorial_Tour.my_tour');
        System.assertNotEquals(null, tourMd);
        System.assertEquals('My Tour', tourMd.label);
        System.assertEquals('my_tour', valueOf(tourMd, 'Tour_Key__c'));
        System.assertEquals(true, valueOf(tourMd, 'Active__c'));

        for (Integer i = 1; i <= 3; i++) {
            Metadata.CustomMetadata stepMd = byName.get('Tutorial_Step.my_tour_' + i);
            System.assertNotEquals(null, stepMd, 'Step ' + i + ' present');
            System.assertEquals('my_tour', valueOf(stepMd, 'Tour__c'),
                'Metadata relationship value is the tour DeveloperName');
            System.assertEquals(Double.valueOf(i), valueOf(stepMd, 'Order__c'));
            System.assertEquals(true, valueOf(stepMd, 'Active__c'));
        }
    }

    @isTest
    static void publishDeactivatesOrphanedSteps() {
        // Import the deployed 4-step nexus_help tour, trim it to 2 steps, then
        // republish: steps _3 and _4 must be re-emitted deactivated.
        Id tourId = TutorialAdminController.importFromPublished('nexus_help');
        List<Tutorial_Step_Draft__c> steps = [
            SELECT Id FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId ORDER BY Order__c ASC
        ];
        System.assertEquals(4, steps.size());
        delete new List<Tutorial_Step_Draft__c>{ steps[2], steps[3] };

        MockDeployer mock = new MockDeployer();
        TutorialAdminController.deployer = mock;

        Test.startTest();
        TutorialAdminController.publish(tourId);
        Test.stopTest();

        Map<String, Metadata.CustomMetadata> byName = indexContainer(mock.captured);
        System.assertEquals(5, byName.size(), 'Tour + 2 live steps + 2 orphan deactivations');
        System.assertEquals(true, valueOf(byName.get('Tutorial_Step.nexus_help_1'), 'Active__c'));
        System.assertEquals(true, valueOf(byName.get('Tutorial_Step.nexus_help_2'), 'Active__c'));
        System.assertEquals(false, valueOf(byName.get('Tutorial_Step.nexus_help_3'), 'Active__c'));
        System.assertEquals(false, valueOf(byName.get('Tutorial_Step.nexus_help_4'), 'Active__c'));
        System.assertNotEquals(null, valueOf(byName.get('Tutorial_Step.nexus_help_3'), 'Target_Selector__c'),
            'Orphan re-emits its existing field values (record deploy is full-replace)');
    }

    @isTest
    static void publishRequiresAtLeastOneStep() {
        Id tourId = makeTour('empty_tour', 'Empty');
        try {
            TutorialAdminController.publish(tourId);
            System.assert(false, 'Expected empty-tour rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void publishAsGuestThrows() {
        Id tourId = makeTour('guest_tour', 'Guest');
        makeStep(tourId, 1, 'One');
        TutorialAdminController.guestOverride = true;
        try {
            TutorialAdminController.publish(tourId);
            System.assert(false, 'Expected guest rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ---- Import --------------------------------------------------------------

    @isTest
    static void importFromPublishedCreatesDrafts() {
        Test.startTest();
        Id tourId = TutorialAdminController.importFromPublished('nexus_help');
        Test.stopTest();

        TutorialAdminController.TourDraftDTO dto = TutorialAdminController.getDraftTour(tourId);
        System.assertEquals('nexus_help', dto.tourKey);
        System.assertEquals(true, dto.published, 'Imported drafts mirror published state');
        System.assertEquals(4, dto.steps.size());
        System.assertEquals('[data-tour-id="nexus-search"]', dto.steps[0].targetSelector);

        try {
            TutorialAdminController.importFromPublished('nexus_help');
            System.assert(false, 'Expected duplicate-import rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void importFromPublishedUnknownKeyThrows() {
        try {
            TutorialAdminController.importFromPublished('no_such_tour_zz');
            System.assert(false, 'Expected unknown-key rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getDraftToursListsAll() {
        makeTour('alpha', 'Alpha');
        makeTour('beta', 'Beta');
        List<TutorialAdminController.TourDraftDTO> tours = TutorialAdminController.getDraftTours();
        System.assertEquals(2, tours.size());
        System.assertEquals('Alpha', tours[0].label, 'Ordered by label');
    }

    // ---- Helpers -------------------------------------------------------------

    private static Map<String, Metadata.CustomMetadata> indexContainer(Metadata.DeployContainer container) {
        Map<String, Metadata.CustomMetadata> byName = new Map<String, Metadata.CustomMetadata>();
        for (Metadata.Metadata md : container.getMetadata()) {
            Metadata.CustomMetadata cmd = (Metadata.CustomMetadata) md;
            byName.put(cmd.fullName, cmd);
        }
        return byName;
    }

    private static Object valueOf(Metadata.CustomMetadata md, String field) {
        for (Metadata.CustomMetadataValue v : md.values) {
            if (v.field == field) {
                return v.value;
            }
        }
        return null;
    }
}