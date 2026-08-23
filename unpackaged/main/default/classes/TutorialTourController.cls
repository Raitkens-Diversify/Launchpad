/**
 * TutorialTourController
 *
 * Runtime read/state API for the guided tutorial tour framework. Context-agnostic:
 * the same methods back the Experience Cloud (LWR) surface — guest and
 * authenticated — and the core Lightning App surface.
 *
 * Conventions:
 *  - `with sharing` + explicit CRUD/FLS guards on Tutorial_State__c. The custom
 *    metadata reads (Tutorial_Tour__mdt / Tutorial_Step__mdt) need no guards:
 *    custom metadata is readable from Apex without object or field grants.
 *  - Guest guard: guest users cannot own records, so getUserState/saveState
 *    short-circuit with isGuest=true and zero SOQL/DML — the client persists to
 *    localStorage instead. Never throws for guests.
 *  - Tour keys are validated against an allow-list pattern before use in SOQL.
 */
public with sharing class TutorialTourController {

    private static final String KEY_PATTERN = '^[A-Za-z0-9_]{1,40}$';

    /** Test seam: UserInfo.getUserType() can't be simulated in tests. */
    @TestVisible private static Boolean guestOverride;

    // ---- Wrappers exposed to LWC --------------------------------------------

    public class TourDTO {
        @AuraEnabled public String tourKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer version;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Boolean autoStart;
        @AuraEnabled public List<StepDTO> steps;
    }

    public class StepDTO {
        // 'order' is a reserved word in SOQL and confuses tooling — use stepOrder.
        @AuraEnabled public Integer stepOrder;
        @AuraEnabled public String targetSelector;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String placement;
        @AuraEnabled public String advanceOn;
    }

    public class StateDTO {
        @AuraEnabled public String tourKey;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Boolean dismissed;
        @AuraEnabled public Integer versionSeen;
        @AuraEnabled public Boolean isGuest;
    }

    // ---- Public API ----------------------------------------------------------

    /**
     * The published tour plus its ordered steps, or null when no active tour
     * exists for the key (client treats null as "no tour" and stays inert).
     */
    @AuraEnabled(cacheable=true)
    public static TourDTO getTour(String tourKey) {
        validateKey(tourKey);

        List<Tutorial_Tour__mdt> tours = [
            SELECT MasterLabel, Tour_Key__c, Active__c, Auto_Start__c, Version__c
            FROM Tutorial_Tour__mdt
            WHERE Tour_Key__c = :tourKey AND Active__c = true
            LIMIT 1
        ];
        if (tours.isEmpty()) {
            return null;
        }
        Tutorial_Tour__mdt tour = tours[0];

        TourDTO dto = new TourDTO();
        dto.tourKey = tour.Tour_Key__c;
        dto.label = tour.MasterLabel;
        dto.version = tour.Version__c == null ? 1 : Integer.valueOf(tour.Version__c);
        dto.active = tour.Active__c;
        dto.autoStart = tour.Auto_Start__c;
        dto.steps = new List<StepDTO>();

        for (Tutorial_Step__mdt step : [
            SELECT Order__c, Target_Selector__c, Title__c, Body__c, Placement__c, Advance_On__c
            FROM Tutorial_Step__mdt
            WHERE Tour__r.Tour_Key__c = :tourKey AND Active__c = true
            ORDER BY Order__c ASC
        ]) {
            StepDTO s = new StepDTO();
            s.stepOrder = step.Order__c == null ? dto.steps.size() + 1 : Integer.valueOf(step.Order__c);
            s.targetSelector = step.Target_Selector__c;
            s.title = step.Title__c;
            s.body = step.Body__c;
            s.placement = String.isBlank(step.Placement__c) ? 'auto' : step.Placement__c;
            s.advanceOn = String.isBlank(step.Advance_On__c) ? 'button' : step.Advance_On__c;
            dto.steps.add(s);
        }
        return dto;
    }

    /**
     * The running user's saved progress for a tour. NOT cacheable on purpose:
     * saveState mutates it within a session and a stale cached read would
     * re-show a just-dismissed tour.
     */
    @AuraEnabled
    public static StateDTO getUserState(String tourKey) {
        validateKey(tourKey);

        if (isGuest()) {
            return guestState(tourKey);
        }
        assertStateReadable();

        StateDTO dto = emptyState(tourKey);
        for (Tutorial_State__c row : [
            SELECT Completed__c, Dismissed__c, Version_Seen__c
            FROM Tutorial_State__c
            WHERE State_Key__c = :stateKey(tourKey)
            LIMIT 1
        ]) {
            dto.completed = row.Completed__c;
            dto.dismissed = row.Dismissed__c;
            dto.versionSeen = row.Version_Seen__c == null ? null : Integer.valueOf(row.Version_Seen__c);
        }
        return dto;
    }

    /**
     * Upserts the running user's progress. Guest context returns gracefully
     * with isGuest=true and performs no DML.
     */
    @AuraEnabled
    public static StateDTO saveState(String tourKey, Boolean completed, Boolean dismissed, Integer versionSeen) {
        validateKey(tourKey);

        if (isGuest()) {
            return guestState(tourKey);
        }
        assertStateWritable();

        Tutorial_State__c rec = new Tutorial_State__c(
            User__c = UserInfo.getUserId(),
            Tour_Key__c = tourKey,
            State_Key__c = stateKey(tourKey),
            Completed__c = completed == true,
            Dismissed__c = dismissed == true,
            Version_Seen__c = versionSeen
        );
        try {
            Database.upsert(rec, Tutorial_State__c.State_Key__c, true);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not save tour progress: ' + e.getDmlMessage(0));
        }

        StateDTO dto = emptyState(tourKey);
        dto.completed = rec.Completed__c;
        dto.dismissed = rec.Dismissed__c;
        dto.versionSeen = versionSeen;
        return dto;
    }

    // ---- Internals -----------------------------------------------------------

    private static Boolean isGuest() {
        return guestOverride != null ? guestOverride : UserInfo.getUserType() == 'Guest';
    }

    private static String stateKey(String tourKey) {
        return UserInfo.getUserId() + '_' + tourKey;
    }

    private static StateDTO emptyState(String tourKey) {
        StateDTO dto = new StateDTO();
        dto.tourKey = tourKey;
        dto.completed = false;
        dto.dismissed = false;
        dto.versionSeen = null;
        dto.isGuest = false;
        return dto;
    }

    private static StateDTO guestState(String tourKey) {
        StateDTO dto = emptyState(tourKey);
        dto.isGuest = true;
        return dto;
    }

    private static void validateKey(String tourKey) {
        if (String.isBlank(tourKey) || !Pattern.matches(KEY_PATTERN, tourKey)) {
            throw new AuraHandledException('Invalid tour key.');
        }
    }

    private static void assertStateReadable() {
        if (!Schema.sObjectType.Tutorial_State__c.isAccessible()
            || !Schema.sObjectType.Tutorial_State__c.fields.Completed__c.isAccessible()
            || !Schema.sObjectType.Tutorial_State__c.fields.Dismissed__c.isAccessible()
            || !Schema.sObjectType.Tutorial_State__c.fields.Version_Seen__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to tutorial state.');
        }
    }

    private static void assertStateWritable() {
        assertStateReadable();
        if (!Schema.sObjectType.Tutorial_State__c.isCreateable()
            || !Schema.sObjectType.Tutorial_State__c.isUpdateable()) {
            throw new AuraHandledException('You do not have access to save tutorial state.');
        }
    }
}