/**
 * Keeps an Advisor Group (Branch) and its Primary Branch Opportunity mirrored while the
 * Opportunity is open.
 *
 * - The synced field pairs live in Branch_Sync_Field__mdt: each record names the field on
 *   BOTH objects (they need not match, e.g. Lead_Source__c on the Branch <-> LeadSource).
 * - AG -> Opp: fires when a Branch with Primary_Branch_Opportunity__c set changes a synced field.
 * - Opp -> AG: fires when a Branch-record-type Opportunity that IS some Branch's primary
 *   changes a synced field. Other Opportunities never write back to the Branch.
 * - Freeze: no sync in either direction once the primary Opportunity is closed
 *   (the lookup remains as a historical pointer) or while the Branch is in a terminal status.
 * - Recursion guard: record Ids written by this service in the current transaction are
 *   skipped when their own triggers re-fire.
 */
public without sharing class BranchOpportunitySyncService {

    /**
     * AG statuses that freeze the mirror in both directions (terminal / non-nurture
     * states). Funnel statuses and blank status sync; new picklist values sync by default.
     */
    private static final Set<String> BLOCKED_STATUSES =
        new Set<String>{ 'Active', 'Disqualified', 'Inactive' };

    /** One synced field pair: the Advisor Group field and its Opportunity counterpart. */
    private class FieldPair {
        String agField;
        String oppField;
        FieldPair(String agField, String oppField) {
            this.agField = agField;
            this.oppField = oppField;
        }
    }

    /**
     * Ids the service has written whose resulting (echo) trigger firing hasn't been
     * consumed yet. Consuming — rather than blacklisting for the whole transaction —
     * means a later GENUINE edit of the same record in the same transaction still syncs.
     */
    private static Set<Id> pendingEchoIds = new Set<Id>();

    /** True exactly once per service-caused write: this trigger firing is our own echo. */
    private static Boolean consumeEcho(Id recordId) {
        return pendingEchoIds.remove(recordId);
    }

    /** Cached, validated sync field pairs. */
    private static List<FieldPair> syncPairs {
        get {
            if (syncPairs == null) {
                syncPairs = new List<FieldPair>();
                Map<String, Schema.SObjectField> agFields =
                    Schema.SObjectType.Advisor_Group__c.fields.getMap();
                Map<String, Schema.SObjectField> oppFields =
                    Schema.SObjectType.Opportunity.fields.getMap();
                for (Branch_Sync_Field__mdt row : [
                    SELECT Advisor_Group_Field_API_Name__c, Opportunity_Field_API_Name__c
                    FROM Branch_Sync_Field__mdt WHERE Active__c = true
                ]) {
                    String agName = row.Advisor_Group_Field_API_Name__c == null
                        ? null : row.Advisor_Group_Field_API_Name__c.trim();
                    String oppName = row.Opportunity_Field_API_Name__c == null
                        ? null : row.Opportunity_Field_API_Name__c.trim();
                    if (String.isBlank(agName) || String.isBlank(oppName)) { continue; }
                    Schema.SObjectField agField = agFields.get(agName.toLowerCase());
                    Schema.SObjectField oppField = oppFields.get(oppName.toLowerCase());
                    // Skip entries that don't exist or aren't writeable on their object.
                    if (agField == null || oppField == null
                        || !agField.getDescribe().isUpdateable()
                        || !oppField.getDescribe().isUpdateable()) {
                        continue;
                    }
                    syncPairs.add(new FieldPair(agName, oppName));
                }
            }
            return syncPairs;
        }
        set;
    }

    private static Id branchRecordTypeId {
        get {
            if (branchRecordTypeId == null) {
                Schema.RecordTypeInfo info = Schema.SObjectType.Opportunity
                    .getRecordTypeInfosByDeveloperName().get('Branch');
                branchRecordTypeId = info == null ? null : info.getRecordTypeId();
            }
            return branchRecordTypeId;
        }
        set;
    }

    /** Advisor Group (after update) -> push changed synced fields to the open primary Opp. */
    public static void syncFromAdvisorGroups(
        List<Advisor_Group__c> newGroups, Map<Id, Advisor_Group__c> oldGroups
    ) {
        if (syncPairs.isEmpty()) { return; }

        // Only Branches that have a primary Opp and actually changed a synced field,
        // and that weren't just written by the Opp -> AG direction.
        Map<Id, Advisor_Group__c> groupByOppId = new Map<Id, Advisor_Group__c>();
        for (Advisor_Group__c ag : newGroups) {
            if (consumeEcho(ag.Id)
                || ag.Primary_Branch_Opportunity__c == null
                || BLOCKED_STATUSES.contains(ag.Status__c)) { // terminal AG: mirror frozen
                continue;
            }
            if (hasSyncedFieldChange(ag, oldGroups.get(ag.Id), true)) {
                groupByOppId.put(ag.Primary_Branch_Opportunity__c, ag);
            }
        }
        if (groupByOppId.isEmpty()) { return; }

        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Opportunity opp : queryOpportunities(groupByOppId.keySet())) {
            if (opp.IsClosed || pendingEchoIds.contains(opp.Id)) { continue; } // freeze / mid-write
            Advisor_Group__c source = groupByOppId.get(opp.Id);
            SObject delta = buildDelta(source, opp, new Opportunity(Id = opp.Id), true);
            if (delta != null) {
                toUpdate.add((Opportunity) delta);
            }
        }
        writeTargets(toUpdate);
    }

    /** Opportunity (after update) -> push changed synced fields back to the Branch it is primary for. */
    public static void syncFromOpportunities(
        List<Opportunity> newOpps, Map<Id, Opportunity> oldOpps
    ) {
        if (syncPairs.isEmpty() || branchRecordTypeId == null) { return; }

        Map<Id, Opportunity> changedByOppId = new Map<Id, Opportunity>();
        for (Opportunity opp : newOpps) {
            if (consumeEcho(opp.Id)                   // echo from AG -> Opp direction
                || opp.RecordTypeId != branchRecordTypeId
                || opp.IsClosed) {                    // freeze: closed opps never write back
                continue;
            }
            if (hasSyncedFieldChange(opp, oldOpps.get(opp.Id), false)) {
                changedByOppId.put(opp.Id, opp);
            }
        }
        if (changedByOppId.isEmpty()) { return; }

        // Only Branches whose PRIMARY lookup points at one of these opps — any other
        // Opportunity for the same Branch is ignored by design.
        List<Advisor_Group__c> toUpdate = new List<Advisor_Group__c>();
        for (Advisor_Group__c ag : queryAdvisorGroups(changedByOppId.keySet())) {
            if (pendingEchoIds.contains(ag.Id)                    // mid-write
                || BLOCKED_STATUSES.contains(ag.Status__c)) {     // terminal AG: mirror frozen
                continue;
            }
            Opportunity source = changedByOppId.get(ag.Primary_Branch_Opportunity__c);
            SObject delta = buildDelta(source, ag, new Advisor_Group__c(Id = ag.Id), false);
            if (delta != null) {
                toUpdate.add((Advisor_Group__c) delta);
            }
        }
        writeTargets(toUpdate);
    }

    // ---------- helpers ----------

    /** sourceIsAg picks which side of each pair to read on the changed record. */
    private static Boolean hasSyncedFieldChange(
        SObject newRec, SObject oldRec, Boolean sourceIsAg
    ) {
        if (oldRec == null) { return false; }
        for (FieldPair p : syncPairs) {
            String f = sourceIsAg ? p.agField : p.oppField;
            if (newRec.get(f) != oldRec.get(f)) { return true; }
        }
        return false;
    }

    /**
     * Builds a sparse update (Id + only the differing synced fields) so non-writeable
     * queried fields (e.g. IsClosed) and unchanged data are never sent in the DML.
     * sourceIsAg = true reads AG-side field names on source and writes Opp-side on delta;
     * false is the reverse. Returns null when nothing differs.
     */
    private static SObject buildDelta(
        SObject source, SObject current, SObject delta, Boolean sourceIsAg
    ) {
        Boolean changed = false;
        for (FieldPair p : syncPairs) {
            String sourceField = sourceIsAg ? p.agField : p.oppField;
            String targetField = sourceIsAg ? p.oppField : p.agField;
            Object sourceValue = source.get(sourceField);
            if (current.get(targetField) != sourceValue) {
                delta.put(targetField, sourceValue);
                changed = true;
            }
        }
        return changed ? delta : null;
    }

    private static List<String> pairFields(Boolean agSide) {
        // Set dedupes so a duplicate CMDT entry can't break the dynamic SOQL.
        Set<String> fields = new Set<String>();
        for (FieldPair p : syncPairs) {
            fields.add(agSide ? p.agField : p.oppField);
        }
        return new List<String>(fields);
    }

    private static List<Opportunity> queryOpportunities(Set<Id> oppIds) {
        return Database.query(
            'SELECT Id, IsClosed, ' + String.join(pairFields(false), ', ')
            + ' FROM Opportunity WHERE Id IN :oppIds'
        );
    }

    private static List<Advisor_Group__c> queryAdvisorGroups(Set<Id> oppIds) {
        return Database.query(
            'SELECT Id, Primary_Branch_Opportunity__c, Status__c, '
            + String.join(pairFields(true), ', ')
            + ' FROM Advisor_Group__c WHERE Primary_Branch_Opportunity__c IN :oppIds'
        );
    }

    /**
     * Partial-success write: one bad record (e.g. a picklist value the target record type
     * doesn't allow) must not block the rest of the batch.
     */
    private static void writeTargets(List<SObject> targets) {
        if (targets.isEmpty()) { return; }
        for (SObject rec : targets) {
            pendingEchoIds.add(rec.Id); // mark BEFORE DML so the echo trigger firing skips them
        }
        Integer i = 0;
        for (Database.SaveResult sr : Database.update(targets, false)) {
            if (!sr.isSuccess()) {
                // No trigger fired for a failed save, so no echo will consume the mark.
                pendingEchoIds.remove(targets[i].Id);
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        'BranchOpportunitySyncService: failed to sync ' + targets[i].Id
                        + ' - ' + err.getStatusCode() + ': ' + err.getMessage());
                }
            }
            i++;
        }
    }
}