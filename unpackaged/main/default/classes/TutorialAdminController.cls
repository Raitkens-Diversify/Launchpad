/**
 * TutorialAdminController
 *
 * Authoring API for the Tour Builder: CRUD on the draft objects
 * (Tutorial_Tour_Draft__c / Tutorial_Step_Draft__c), step reordering, and
 * publishing drafts to the runtime custom metadata (Tutorial_Tour__mdt /
 * Tutorial_Step__mdt) via the Apex Metadata API.
 *
 * Publish limitations (by platform design — documented for maintainers):
 *  - Custom metadata cannot be written with normal DML; publish() builds a
 *    Metadata.DeployContainer and enqueues it with Metadata.Operations. The
 *    deployment is ASYNCHRONOUS: Published__c/Last_Published__c flip only when
 *    TutorialPublishCallback fires, so the UI polls getDraftTour after publish.
 *  - The publishing user needs the "Modify Metadata Through Metadata API
 *    Functions" permission (granted by the Tutorial_Tours_Admin permission
 *    set) and, in practice, Customize Application — publishers should be admins.
 *  - Custom metadata records cannot be DELETED from Apex. Republishing a tour
 *    with fewer steps re-emits the orphaned step records with Active__c=false
 *    instead; the runtime reads only active steps. Deleting a whole tour draft
 *    likewise leaves the published CMDT behind — deactivate (Active__c=false)
 *    and republish first, or hard-delete the records in Setup.
 *  - Guests cannot publish (guarded). Only one publish per tour should be in
 *    flight at a time; concurrent publishes are last-write-wins.
 */
public with sharing class TutorialAdminController {

    // CMDT DeveloperName is max 40, must start with a letter, no consecutive or
    // trailing underscores. Cap at 30 to leave room for the '_<n>' step suffix.
    private static final String TOUR_KEY_PATTERN = '^[a-z][a-z0-9]*(_[a-z0-9]+)*$';
    private static final Integer TOUR_KEY_MAX = 30;
    private static final Integer LABEL_MAX = 40;
    private static final Set<String> PLACEMENTS = new Set<String>{ 'auto', 'top', 'bottom', 'left', 'right' };
    private static final Set<String> ADVANCE_MODES = new Set<String>{ 'button', 'click', 'none' };
    private static final Decimal ORPHAN_ORDER = 9999;

    /** Test seam: UserInfo.getUserType() can't be simulated in tests. */
    @TestVisible private static Boolean guestOverride;

    // ---- Metadata deploy seam ------------------------------------------------
    // Metadata.Operations.enqueueDeployment throws in test context, so the
    // deployer is injectable: tests swap in a mock that captures the container.

    public interface MetadataDeployer {
        Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback);
    }

    public class RealDeployer implements MetadataDeployer {
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            return Metadata.Operations.enqueueDeployment(container, callback);
        }
    }

    @TestVisible private static MetadataDeployer deployer = new RealDeployer();

    // ---- Wrappers exposed to LWC --------------------------------------------

    public class TourDraftDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String tourKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Boolean autoStart;
        @AuraEnabled public Integer version;
        @AuraEnabled public Boolean published;
        @AuraEnabled public Datetime lastPublished;
        @AuraEnabled public String publishError;
        @AuraEnabled public List<StepDraftDTO> steps;
    }

    public class StepDraftDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Integer stepOrder;
        @AuraEnabled public String targetSelector;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String placement;
        @AuraEnabled public String advanceOn;
    }

    // ---- Draft reads ---------------------------------------------------------

    @AuraEnabled
    public static List<TourDraftDTO> getDraftTours() {
        assertDraftsReadable();
        List<TourDraftDTO> dtos = new List<TourDraftDTO>();
        for (Tutorial_Tour_Draft__c tour : [
            SELECT Id, Tour_Key__c, Label__c, Active__c, Auto_Start__c, Version__c,
                   Published__c, Last_Published__c, Publish_Error__c
            FROM Tutorial_Tour_Draft__c
            ORDER BY Label__c ASC
        ]) {
            dtos.add(toTourDTO(tour, null));
        }
        return dtos;
    }

    @AuraEnabled
    public static TourDraftDTO getDraftTour(Id tourId) {
        assertDraftsReadable();
        List<Tutorial_Tour_Draft__c> tours = [
            SELECT Id, Tour_Key__c, Label__c, Active__c, Auto_Start__c, Version__c,
                   Published__c, Last_Published__c, Publish_Error__c,
                   (SELECT Id, Order__c, Target_Selector__c, Title__c, Body__c,
                           Placement__c, Advance_On__c
                    FROM Tutorial_Step_Drafts__r
                    ORDER BY Order__c ASC)
            FROM Tutorial_Tour_Draft__c
            WHERE Id = :tourId
            LIMIT 1
        ];
        if (tours.isEmpty()) {
            throw new AuraHandledException('Tour draft not found.');
        }
        return toTourDTO(tours[0], tours[0].Tutorial_Step_Drafts__r);
    }

    // ---- Draft writes --------------------------------------------------------

    @AuraEnabled
    public static Id saveDraftTour(Id recordId, String tourKey, String label,
                                   Boolean active, Boolean autoStart, Decimal version) {
        String cleanKey = tourKey == null ? null : tourKey.trim().toLowerCase();
        if (String.isBlank(cleanKey) || cleanKey.length() > TOUR_KEY_MAX
            || !Pattern.matches(TOUR_KEY_PATTERN, cleanKey)) {
            throw new AuraHandledException(
                'Tour key must be 1-' + TOUR_KEY_MAX + ' characters of lowercase letters, '
                + 'digits and single underscores, starting with a letter (e.g. nexus_help).');
        }
        if (String.isBlank(label) || label.trim().length() > LABEL_MAX) {
            throw new AuraHandledException('Label is required, max ' + LABEL_MAX + ' characters.');
        }

        Tutorial_Tour_Draft__c tour = new Tutorial_Tour_Draft__c(
            Name = label.trim(),
            Tour_Key__c = cleanKey,
            Label__c = label.trim(),
            Active__c = active == true,
            Auto_Start__c = autoStart == true,
            Version__c = version == null ? 1 : version,
            Published__c = false
        );

        try {
            if (recordId == null) {
                assertDraftsCreateable();
                insert tour;
            } else {
                assertDraftsUpdateable();
                Tutorial_Tour_Draft__c existing = [
                    SELECT Tour_Key__c, Published__c, Last_Published__c
                    FROM Tutorial_Tour_Draft__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                if (existing.Last_Published__c != null && existing.Tour_Key__c != cleanKey) {
                    // The key is the published CMDT identity; renaming would orphan
                    // the records published under the old key.
                    throw new AuraHandledException(
                        'This tour has been published — its key cannot change. Create a new tour instead.');
                }
                tour.Id = recordId;
                update tour;
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save tour: ' + e.getDmlMessage(0));
        }
        return tour.Id;
    }

    @AuraEnabled
    public static void deleteDraftTour(Id tourId) {
        assertDraftsDeletable();
        try {
            // Master-detail cascades the step drafts.
            delete new Tutorial_Tour_Draft__c(Id = tourId);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not delete tour: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static Id saveDraftStep(Id recordId, Id tourId, Decimal stepOrder,
                                   String targetSelector, String title, String body,
                                   String placement, String advanceOn) {
        if (tourId == null) {
            throw new AuraHandledException('A step needs a tour.');
        }
        if (String.isBlank(title)) {
            throw new AuraHandledException('Step title is required.');
        }
        if (String.isBlank(targetSelector)) {
            throw new AuraHandledException('Step target selector is required.');
        }
        String cleanPlacement = String.isBlank(placement) ? 'auto' : placement.trim().toLowerCase();
        if (!PLACEMENTS.contains(cleanPlacement)) {
            throw new AuraHandledException('Placement must be one of: auto, top, bottom, left, right.');
        }
        String cleanAdvance = String.isBlank(advanceOn) ? 'button' : advanceOn.trim().toLowerCase();
        if (!ADVANCE_MODES.contains(cleanAdvance)) {
            throw new AuraHandledException('Advance On must be one of: button, click, none.');
        }

        Decimal resolvedOrder = stepOrder;
        if (resolvedOrder == null) {
            AggregateResult agg = [
                SELECT MAX(Order__c) maxOrder
                FROM Tutorial_Step_Draft__c
                WHERE Tour__c = :tourId
            ];
            Decimal maxOrder = (Decimal) agg.get('maxOrder');
            resolvedOrder = maxOrder == null ? 1 : maxOrder + 1;
        }

        Tutorial_Step_Draft__c step = new Tutorial_Step_Draft__c(
            Order__c = resolvedOrder,
            Target_Selector__c = targetSelector.trim(),
            Title__c = title.trim(),
            Body__c = body,
            Placement__c = cleanPlacement,
            Advance_On__c = cleanAdvance
        );

        try {
            if (recordId == null) {
                assertDraftsCreateable();
                step.Tour__c = tourId;
                insert step;
            } else {
                // Master-detail is not reparentable, so Tour__c is set only on
                // insert and deliberately omitted from the update.
                assertDraftsUpdateable();
                step.Id = recordId;
                update step;
            }
            markUnpublished(tourId);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save step: ' + e.getDmlMessage(0));
        }
        return step.Id;
    }

    @AuraEnabled
    public static void deleteDraftStep(Id stepId) {
        assertDraftsDeletable();
        List<Tutorial_Step_Draft__c> steps = [
            SELECT Id, Tour__c FROM Tutorial_Step_Draft__c WHERE Id = :stepId LIMIT 1
        ];
        if (steps.isEmpty()) {
            return;
        }
        try {
            delete steps[0];
            markUnpublished(steps[0].Tour__c);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not delete step: ' + e.getDmlMessage(0));
        }
    }

    /**
     * Reorder API: the FULL ordered list of the tour's step Ids (simplest
     * contract for drag-and-drop — one idempotent call). The Id set must match
     * the tour's steps exactly.
     */
    @AuraEnabled
    public static void reorderSteps(Id tourId, List<Id> orderedStepIds) {
        assertDraftsUpdateable();
        Map<Id, Tutorial_Step_Draft__c> existing = new Map<Id, Tutorial_Step_Draft__c>([
            SELECT Id FROM Tutorial_Step_Draft__c WHERE Tour__c = :tourId
        ]);
        if (orderedStepIds == null || existing.size() != orderedStepIds.size()
            || !existing.keySet().containsAll(orderedStepIds)) {
            throw new AuraHandledException('Step list is out of date — reload the tour and try again.');
        }

        List<Tutorial_Step_Draft__c> updates = new List<Tutorial_Step_Draft__c>();
        for (Integer i = 0; i < orderedStepIds.size(); i++) {
            updates.add(new Tutorial_Step_Draft__c(Id = orderedStepIds[i], Order__c = i + 1));
        }
        try {
            update updates;
            markUnpublished(tourId);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not reorder steps: ' + e.getDmlMessage(0));
        }
    }

    // ---- Publish -------------------------------------------------------------

    /**
     * Promotes a draft tour to custom metadata. Returns the async deployment
     * job Id; the callback writes the outcome to Published__c / Publish_Error__c.
     */
    @AuraEnabled
    public static String publish(Id tourId) {
        if (isGuest()) {
            throw new AuraHandledException('Publishing is not available to guest users.');
        }
        assertDraftsReadable();

        TourDraftDTO draft = getDraftTour(tourId);
        if (draft.steps == null || draft.steps.isEmpty()) {
            throw new AuraHandledException('Add at least one step before publishing.');
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();

        // Tour record: fullName = Tutorial_Tour.<key>; same fullName on a later
        // publish updates the record in place.
        Metadata.CustomMetadata tourMd = new Metadata.CustomMetadata();
        tourMd.fullName = 'Tutorial_Tour.' + draft.tourKey;
        tourMd.label = draft.label;
        addValue(tourMd, 'Tour_Key__c', draft.tourKey);
        addValue(tourMd, 'Active__c', draft.active == true);
        addValue(tourMd, 'Auto_Start__c', draft.autoStart == true);
        addValue(tourMd, 'Version__c', draft.version == null ? 1.0 : Double.valueOf(draft.version));
        container.addMetadata(tourMd);

        // Steps are keyed by position so republish deterministically overwrites.
        Set<String> liveNames = new Set<String>();
        for (Integer i = 0; i < draft.steps.size(); i++) {
            StepDraftDTO step = draft.steps[i];
            String devName = draft.tourKey + '_' + (i + 1);
            liveNames.add(devName);

            Metadata.CustomMetadata stepMd = new Metadata.CustomMetadata();
            stepMd.fullName = 'Tutorial_Step.' + devName;
            stepMd.label = step.title.abbreviate(LABEL_MAX);
            addValue(stepMd, 'Tour__c', draft.tourKey);
            addValue(stepMd, 'Order__c', Double.valueOf(i + 1));
            addValue(stepMd, 'Target_Selector__c', step.targetSelector);
            addValue(stepMd, 'Title__c', step.title);
            addValue(stepMd, 'Body__c', step.body);
            addValue(stepMd, 'Placement__c', step.placement);
            addValue(stepMd, 'Advance_On__c', step.advanceOn);
            addValue(stepMd, 'Active__c', true);
            container.addMetadata(stepMd);
        }

        // Custom metadata records can't be deleted from Apex, so steps that
        // dropped off the draft are re-emitted deactivated. A CMDT record deploy
        // is a full replace, so every field is re-emitted from the live values.
        for (Tutorial_Step__mdt orphan : [
            SELECT DeveloperName, MasterLabel, Target_Selector__c, Title__c, Body__c,
                   Placement__c, Advance_On__c
            FROM Tutorial_Step__mdt
            WHERE Tour__r.Tour_Key__c = :draft.tourKey
        ]) {
            if (liveNames.contains(orphan.DeveloperName)) {
                continue;
            }
            Metadata.CustomMetadata orphanMd = new Metadata.CustomMetadata();
            orphanMd.fullName = 'Tutorial_Step.' + orphan.DeveloperName;
            orphanMd.label = orphan.MasterLabel;
            addValue(orphanMd, 'Tour__c', draft.tourKey);
            addValue(orphanMd, 'Order__c', Double.valueOf(ORPHAN_ORDER));
            addValue(orphanMd, 'Target_Selector__c', orphan.Target_Selector__c);
            addValue(orphanMd, 'Title__c', orphan.Title__c);
            addValue(orphanMd, 'Body__c', orphan.Body__c);
            addValue(orphanMd, 'Placement__c', orphan.Placement__c);
            addValue(orphanMd, 'Advance_On__c', orphan.Advance_On__c);
            addValue(orphanMd, 'Active__c', false);
            container.addMetadata(orphanMd);
        }

        try {
            Id jobId = deployer.enqueue(container, new TutorialPublishCallback(tourId));
            return String.valueOf(jobId);
        } catch (Exception e) {
            throw new AuraHandledException('Could not start publish: ' + e.getMessage());
        }
    }

    /**
     * Seeds draft records from already-published custom metadata. Used to
     * bootstrap drafts for tours that shipped as source (e.g. nexus_help) and
     * as a recovery tool when drafts are lost.
     */
    @AuraEnabled
    public static Id importFromPublished(String tourKey) {
        assertDraftsCreateable();

        List<Tutorial_Tour__mdt> tours = [
            SELECT MasterLabel, Tour_Key__c, Active__c, Auto_Start__c, Version__c
            FROM Tutorial_Tour__mdt
            WHERE Tour_Key__c = :tourKey
            LIMIT 1
        ];
        if (tours.isEmpty()) {
            throw new AuraHandledException('No published tour found for key: ' + tourKey);
        }
        if (![SELECT Id FROM Tutorial_Tour_Draft__c WHERE Tour_Key__c = :tourKey LIMIT 1].isEmpty()) {
            throw new AuraHandledException('A draft already exists for key: ' + tourKey);
        }
        Tutorial_Tour__mdt tour = tours[0];

        Datetime now = System.now();
        Tutorial_Tour_Draft__c draft = new Tutorial_Tour_Draft__c(
            Name = tour.MasterLabel,
            Tour_Key__c = tour.Tour_Key__c,
            Label__c = tour.MasterLabel,
            Active__c = tour.Active__c,
            Auto_Start__c = tour.Auto_Start__c,
            Version__c = tour.Version__c,
            Published__c = true,
            Last_Published__c = now
        );

        List<Tutorial_Step_Draft__c> steps = new List<Tutorial_Step_Draft__c>();
        try {
            insert draft;
            for (Tutorial_Step__mdt step : [
                SELECT Order__c, Target_Selector__c, Title__c, Body__c, Placement__c, Advance_On__c
                FROM Tutorial_Step__mdt
                WHERE Tour__r.Tour_Key__c = :tourKey AND Active__c = true
                ORDER BY Order__c ASC
            ]) {
                steps.add(new Tutorial_Step_Draft__c(
                    Tour__c = draft.Id,
                    Order__c = step.Order__c,
                    Target_Selector__c = step.Target_Selector__c,
                    Title__c = step.Title__c,
                    Body__c = step.Body__c,
                    Placement__c = step.Placement__c,
                    Advance_On__c = step.Advance_On__c,
                    Published__c = true,
                    Last_Published__c = now
                ));
            }
            insert steps;
        } catch (DmlException e) {
            throw new AuraHandledException('Could not import tour: ' + e.getDmlMessage(0));
        }
        return draft.Id;
    }

    // ---- Internals -----------------------------------------------------------

    private static Boolean isGuest() {
        return guestOverride != null ? guestOverride : UserInfo.getUserType() == 'Guest';
    }

    private static void addValue(Metadata.CustomMetadata md, String field, Object value) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = field;
        v.value = value;
        md.values.add(v);
    }

    private static void markUnpublished(Id tourId) {
        update new Tutorial_Tour_Draft__c(Id = tourId, Published__c = false);
    }

    private static TourDraftDTO toTourDTO(Tutorial_Tour_Draft__c tour, List<Tutorial_Step_Draft__c> steps) {
        TourDraftDTO dto = new TourDraftDTO();
        dto.recordId = tour.Id;
        dto.tourKey = tour.Tour_Key__c;
        dto.label = tour.Label__c;
        dto.active = tour.Active__c;
        dto.autoStart = tour.Auto_Start__c;
        dto.version = tour.Version__c == null ? 1 : Integer.valueOf(tour.Version__c);
        dto.published = tour.Published__c;
        dto.lastPublished = tour.Last_Published__c;
        dto.publishError = tour.Publish_Error__c;
        if (steps != null) {
            dto.steps = new List<StepDraftDTO>();
            for (Tutorial_Step_Draft__c step : steps) {
                StepDraftDTO s = new StepDraftDTO();
                s.recordId = step.Id;
                s.stepOrder = step.Order__c == null ? dto.steps.size() + 1 : Integer.valueOf(step.Order__c);
                s.targetSelector = step.Target_Selector__c;
                s.title = step.Title__c;
                s.body = step.Body__c;
                s.placement = String.isBlank(step.Placement__c) ? 'auto' : step.Placement__c;
                s.advanceOn = String.isBlank(step.Advance_On__c) ? 'button' : step.Advance_On__c;
                dto.steps.add(s);
            }
        }
        return dto;
    }

    private static void assertDraftsReadable() {
        if (!Schema.sObjectType.Tutorial_Tour_Draft__c.isAccessible()
            || !Schema.sObjectType.Tutorial_Step_Draft__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to tour drafts.');
        }
    }

    private static void assertDraftsCreateable() {
        if (!Schema.sObjectType.Tutorial_Tour_Draft__c.isCreateable()
            || !Schema.sObjectType.Tutorial_Step_Draft__c.isCreateable()) {
            throw new AuraHandledException('You do not have access to create tour drafts.');
        }
    }

    private static void assertDraftsUpdateable() {
        if (!Schema.sObjectType.Tutorial_Tour_Draft__c.isUpdateable()
            || !Schema.sObjectType.Tutorial_Step_Draft__c.isUpdateable()) {
            throw new AuraHandledException('You do not have access to edit tour drafts.');
        }
    }

    private static void assertDraftsDeletable() {
        if (!Schema.sObjectType.Tutorial_Tour_Draft__c.isDeletable()
            || !Schema.sObjectType.Tutorial_Step_Draft__c.isDeletable()) {
            throw new AuraHandledException('You do not have access to delete tour drafts.');
        }
    }
}