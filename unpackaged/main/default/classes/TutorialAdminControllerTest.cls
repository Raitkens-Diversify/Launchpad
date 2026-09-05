/**
 * TutorialAdminControllerTest
 *
 * Publish tests use the injectable MetadataDeployer seam — real deployments
 * cannot be enqueued from test context. The orphan/import tests read whatever
 * Tutorial_Tour__mdt / Tutorial_Step__mdt the package ships (nexus_help when
 * present, otherwise any published tour) and assert RELATIVE to those rows —
 * never against a literal step count, which changes as the sample tour grows.
 * With no published tour in the org those two tests assert the not-found
 * contract instead, so the class stays green everywhere.
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

    private class ExplodingDeployer implements TutorialAdminController.MetadataDeployer {
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            throw new System.CalloutException('Metadata API unavailable');
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

    /** A published tour key to import: nexus_help when shipped, else any tour, else null. */
    private static String publishedTourKey() {
        for (Tutorial_Tour__mdt t : [SELECT Tour_Key__c FROM Tutorial_Tour__mdt WHERE Tour_Key__c = 'nexus_help' LIMIT 1]) {
            return t.Tour_Key__c;
        }
        for (Tutorial_Tour__mdt t : [SELECT Tour_Key__c FROM Tutorial_Tour__mdt ORDER BY DeveloperName LIMIT 1]) {
            return t.Tour_Key__c;
        }
        return null;
    }

    private static List<Tutorial_Step__mdt> publishedSteps(String tourKey, Boolean activeOnly) {
        return activeOnly
            ? [SELECT DeveloperName, Target_Selector__c, Order__c FROM Tutorial_Step__mdt
               WHERE Tour__r.Tour_Key__c = :tourKey AND Active__c = true ORDER BY Order__c ASC]
            : [SELECT DeveloperName, Target_Selector__c, Order__c FROM Tutorial_Step__mdt
               WHERE Tour__r.Tour_Key__c = :tourKey ORDER BY Order__c ASC];
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
    static void saveDraftTourNormalizesKeyAndDefaultsVersion() {
        Id tourId = TutorialAdminController.saveDraftTour(null, '  Mixed_Case  ', '  Padded  ', null, null, null);
        Tutorial_Tour_Draft__c tour = [
            SELECT Tour_Key__c, Label__c, Active__c, Auto_Start__c, Version__c
            FROM Tutorial_Tour_Draft__c WHERE Id = :tourId
        ];
        System.assertEquals('mixed_case', tour.Tour_Key__c, 'Key is trimmed and lower-cased');
        System.assertEquals('Padded', tour.Label__c, 'Label is trimmed');
        System.assertEquals(false, tour.Active__c, 'null active -> false');
        System.assertEquals(false, tour.Auto_Start__c, 'null autoStart -> false');
        System.assertEquals(1, tour.Version__c, 'null version -> 1');
    }

    @isTest
    static void saveDraftTourRejectsBadKeys() {
        for (String badKey : new List<String>{ null, '', '   ', 'Bad Key!', '1leading', 'has__double', 'trailing_',
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
    static void saveDraftTourRejectsBadLabels() {
        for (String badLabel : new List<String>{ null, '', '   ', 'x'.repeat(41) }) {
            try {
                makeTour('label_tour', badLabel);
                System.assert(false, 'Expected rejection of label: ' + badLabel);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Tour_Draft__c], 'Nothing saved');
    }

    @isTest
    static void saveDraftTourDuplicateKeySurfacesDmlError() {
        makeTour('dupe_tour', 'First');
        try {
            makeTour('dupe_tour', 'Second');
            System.assert(false, 'Tour_Key__c is unique — expected a DML rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Tutorial_Tour_Draft__c WHERE Tour_Key__c = 'dupe_tour']);
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
        // Same key is fine — only the key is frozen, not the other fields.
        TutorialAdminController.saveDraftTour(tourId, 'locked_tour', 'Locked v2', true, true, 2);
        System.assertEquals('Locked v2', [SELECT Label__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId].Label__c);
    }

    @isTest
    static void getDraftTourUnknownIdThrows() {
        Id tourId = makeTour('gone_tour', 'Gone');
        TutorialAdminController.deleteDraftTour(tourId);
        try {
            TutorialAdminController.getDraftTour(tourId);
            System.assert(false, 'Expected not-found rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void deleteDraftTourUnknownIdSurfacesDmlError() {
        Id tourId = makeTour('twice', 'Twice');
        TutorialAdminController.deleteDraftTour(tourId);
        try {
            TutorialAdminController.deleteDraftTour(tourId); // already deleted
            System.assert(false, 'Expected DML rejection for an already-deleted tour');
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
            TutorialAdminController.saveDraftStep(null, tourId, 3, '[data-x]', 'Bad', null, 'auto', 'hover');
            System.assert(false, 'Expected advance-mode rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            TutorialAdminController.saveDraftStep(null, tourId, 3, '', 'Bad', null, 'auto', 'button');
            System.assert(false, 'Expected blank-selector rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            TutorialAdminController.saveDraftStep(null, tourId, 3, '[data-x]', '  ', null, 'auto', 'button');
            System.assert(false, 'Expected blank-title rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            TutorialAdminController.saveDraftStep(null, null, 3, '[data-x]', 'Bad', null, 'auto', 'button');
            System.assert(false, 'Expected missing-tour rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(2, [SELECT COUNT() FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId],
            'Rejected steps were not saved');
    }

    @isTest
    static void saveDraftStepFirstStepDefaultsToOrderOne() {
        Id tourId = makeTour('first_step', 'First Step');
        Id stepId = TutorialAdminController.saveDraftStep(
            null, tourId, null, '[data-tour-id="only"]', 'Only', null, 'TOP', 'Click');
        Tutorial_Step_Draft__c step = [
            SELECT Order__c, Placement__c, Advance_On__c FROM Tutorial_Step_Draft__c WHERE Id = :stepId
        ];
        System.assertEquals(1, step.Order__c, 'No siblings -> order 1');
        System.assertEquals('top', step.Placement__c, 'Placement normalized to lower case');
        System.assertEquals('click', step.Advance_On__c, 'Advance mode normalized to lower case');
    }

    @isTest
    static void saveDraftStepUpdatesInPlace() {
        Id tourId = makeTour('edit_step', 'Edit Step');
        Id stepId = makeStep(tourId, 1, 'Original');
        update new Tutorial_Tour_Draft__c(Id = tourId, Published__c = true);

        Id sameId = TutorialAdminController.saveDraftStep(
            stepId, tourId, 5, '  [data-tour-id="edited"]  ', '  Edited  ', '<p>New</p>', 'left', 'none');

        System.assertEquals(stepId, sameId, 'Update keeps the record Id');
        Tutorial_Step_Draft__c step = [
            SELECT Tour__c, Order__c, Target_Selector__c, Title__c, Body__c, Placement__c, Advance_On__c
            FROM Tutorial_Step_Draft__c WHERE Id = :stepId
        ];
        System.assertEquals(tourId, step.Tour__c, 'Master-detail parent unchanged');
        System.assertEquals(5, step.Order__c);
        System.assertEquals('[data-tour-id="edited"]', step.Target_Selector__c, 'Selector trimmed');
        System.assertEquals('Edited', step.Title__c, 'Title trimmed');
        System.assertEquals('<p>New</p>', step.Body__c);
        System.assertEquals('left', step.Placement__c);
        System.assertEquals('none', step.Advance_On__c);
        System.assertEquals(1, [SELECT COUNT() FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId], 'No duplicate');
        System.assertEquals(false, [SELECT Published__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId].Published__c,
            'Editing a step marks the tour unpublished');
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

        // Deleting it again is a quiet no-op (the step is simply gone).
        TutorialAdminController.deleteDraftStep(stepId);
        System.assertEquals(0, [SELECT COUNT() FROM Tutorial_Step_Draft__c WHERE Id = :stepId]);
    }

    @isTest
    static void reorderStepsAssignsSequentialOrder() {
        Id tourId = makeTour('ordered', 'Ordered');
        Id a = makeStep(tourId, 1, 'A');
        Id b = makeStep(tourId, 2, 'B');
        Id c = makeStep(tourId, 3, 'C');
        update new Tutorial_Tour_Draft__c(Id = tourId, Published__c = true);

        TutorialAdminController.reorderSteps(tourId, new List<Id>{ c, b, a });

        Map<Id, Tutorial_Step_Draft__c> rows = new Map<Id, Tutorial_Step_Draft__c>([
            SELECT Order__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]);
        System.assertEquals(1, rows.get(c).Order__c);
        System.assertEquals(2, rows.get(b).Order__c);
        System.assertEquals(3, rows.get(a).Order__c);
        System.assertEquals(false, [SELECT Published__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId].Published__c,
            'Reordering marks the tour unpublished');

        TutorialAdminController.TourDraftDTO dto = TutorialAdminController.getDraftTour(tourId);
        System.assertEquals(c, dto.steps[0].recordId, 'DTO steps come back in the new order');
        System.assertEquals(1, dto.steps[0].stepOrder);
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
        try {
            TutorialAdminController.reorderSteps(tourId, null);
            System.assert(false, 'Expected null-list rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            TutorialAdminController.reorderSteps(tourId, new List<Id>());
            System.assert(false, 'Expected short-list rejection');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(1, [SELECT Order__c FROM Tutorial_Step_Draft__c WHERE Id = :a].Order__c, 'Untouched');
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
        System.assertEquals(4, byName.size(), 'Tour + 3 steps (no published rows for a brand-new key)');

        Metadata.CustomMetadata tourMd = byName.get('Tutorial_Tour.my_tour');
        System.assertNotEquals(null, tourMd);
        System.assertEquals('My Tour', tourMd.label);
        System.assertEquals('my_tour', valueOf(tourMd, 'Tour_Key__c'));
        System.assertEquals(true, valueOf(tourMd, 'Active__c'));
        System.assertEquals(true, valueOf(tourMd, 'Auto_Start__c'));
        System.assertEquals(1.0, valueOf(tourMd, 'Version__c'));

        for (Integer i = 1; i <= 3; i++) {
            Metadata.CustomMetadata stepMd = byName.get('Tutorial_Step.my_tour_' + i);
            System.assertNotEquals(null, stepMd, 'Step ' + i + ' present');
            System.assertEquals('my_tour', valueOf(stepMd, 'Tour__c'),
                'Metadata relationship value is the tour DeveloperName');
            System.assertEquals(Double.valueOf(i), valueOf(stepMd, 'Order__c'));
            System.assertEquals(true, valueOf(stepMd, 'Active__c'));
            System.assertEquals('[data-tour-id="t' + i + '"]', valueOf(stepMd, 'Target_Selector__c'));
            System.assertEquals('auto', valueOf(stepMd, 'Placement__c'));
            System.assertEquals('button', valueOf(stepMd, 'Advance_On__c'));
        }
    }

    @isTest
    static void publishDeactivatesOrphanedSteps() {
        // Import the shipped tour, trim its draft, then republish: every
        // published step that is no longer in the draft must be re-emitted
        // with Active__c=false (CMDT can't be deleted from Apex).
        String key = publishedTourKey();
        if (key == null) {
            try {
                TutorialAdminController.importFromPublished('nexus_help');
                System.assert(false, 'No published tour in this org — import must reject');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            return;
        }
        List<Tutorial_Step__mdt> allPublished = publishedSteps(key, false);

        Id tourId = TutorialAdminController.importFromPublished(key);
        List<Tutorial_Step_Draft__c> steps = [
            SELECT Id FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId ORDER BY Order__c ASC
        ];
        System.assertEquals(publishedSteps(key, true).size(), steps.size(),
            'Import mirrors every active published step');

        // Keep at least one live step; drop up to two from the end.
        Integer toDrop = Math.min(2, steps.size() - 1);
        List<Tutorial_Step_Draft__c> dropped = new List<Tutorial_Step_Draft__c>();
        for (Integer i = steps.size() - toDrop; i < steps.size(); i++) {
            dropped.add(steps[i]);
        }
        if (!dropped.isEmpty()) {
            delete dropped;
        }
        Integer live = steps.size() - toDrop;

        Set<String> liveNames = new Set<String>();
        for (Integer i = 1; i <= live; i++) {
            liveNames.add(key + '_' + i);
        }
        Set<String> orphanNames = new Set<String>();
        for (Tutorial_Step__mdt p : allPublished) {
            if (!liveNames.contains(p.DeveloperName)) {
                orphanNames.add(p.DeveloperName);
            }
        }
        System.assert(orphanNames.size() >= toDrop, 'Dropping steps produces orphans to deactivate');
        MockDeployer mock = new MockDeployer();
        TutorialAdminController.deployer = mock;

        Test.startTest();
        TutorialAdminController.publish(tourId);
        Test.stopTest();

        Map<String, Metadata.CustomMetadata> byName = indexContainer(mock.captured);
        System.assertEquals(1 + live + orphanNames.size(), byName.size(),
            'Tour + live steps + one deactivation per orphaned published step');
        for (String name : liveNames) {
            System.assertEquals(true, valueOf(byName.get('Tutorial_Step.' + name), 'Active__c'), name + ' stays live');
        }
        for (String name : orphanNames) {
            Metadata.CustomMetadata orphan = byName.get('Tutorial_Step.' + name);
            System.assertNotEquals(null, orphan, 'Orphan re-emitted: ' + name);
            System.assertEquals(false, valueOf(orphan, 'Active__c'), name + ' deactivated');
            System.assertEquals(9999.0, valueOf(orphan, 'Order__c'), 'Orphans sort last');
            System.assertNotEquals(null, valueOf(orphan, 'Target_Selector__c'),
                'Orphan re-emits its existing field values (record deploy is full-replace)');
        }    }

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

    @isTest
    static void publishWrapsDeployerFailure() {
        Id tourId = makeTour('boom_tour', 'Boom');
        makeStep(tourId, 1, 'One');
        TutorialAdminController.deployer = new ExplodingDeployer();
        try {
            TutorialAdminController.publish(tourId);
            System.assert(false, 'Expected the deployer failure to surface');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(false, [SELECT Published__c FROM Tutorial_Tour_Draft__c WHERE Id = :tourId].Published__c,
            'A failed enqueue never marks the draft published');
    }

    // ---- Import --------------------------------------------------------------

    @isTest
    static void importFromPublishedCreatesDrafts() {
        String key = publishedTourKey();
        if (key == null) {
            try {
                TutorialAdminController.importFromPublished('nexus_help');
                System.assert(false, 'No published tour in this org — import must reject');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            return;
        }
        List<Tutorial_Step__mdt> active = publishedSteps(key, true);

        Test.startTest();
        Id tourId = TutorialAdminController.importFromPublished(key);
        Test.stopTest();

        TutorialAdminController.TourDraftDTO dto = TutorialAdminController.getDraftTour(tourId);
        System.assertEquals(key, dto.tourKey);
        System.assertEquals(true, dto.published, 'Imported drafts mirror published state');
        System.assertNotEquals(null, dto.lastPublished);
        System.assertEquals(active.size(), dto.steps.size(), 'One draft step per active published step');
        if (!active.isEmpty()) {
            System.assertEquals(active[0].Target_Selector__c, dto.steps[0].targetSelector,
                'Steps import in published order');
        }
        for (Tutorial_Step_Draft__c s : [
            SELECT Published__c, Last_Published__c FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]) {
            System.assertEquals(true, s.Published__c, 'Imported steps are flagged published');
            System.assertNotEquals(null, s.Last_Published__c);
        }
        try {
            TutorialAdminController.importFromPublished(key);
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
        System.assertEquals(null, tours[0].steps, 'List view carries no steps');
        System.assertEquals(false, tours[0].published);
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