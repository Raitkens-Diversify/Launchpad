/**
 * UatCoverageController
 *
 * Apex behind the Admin Console's Pool Health section (adminUatCoverage):
 * per-cycle coverage rollups (unclaimed seats, claim/progress counts, oldest
 * sitting seat, days to target, at-risk flag) plus a per-cycle drill-down of
 * unclaimed cases and the recent assignment-event feed.
 *
 * Read-only — no DML anywhere. Everything is computed here in aggregates
 * (Test_Cycle__c carries no rollup fields, by design).
 *
 * Conventions: with sharing, describe asserts, AuraHandledException.
 */
public with sharing class UatCoverageController {

    /** Target date within this many days (or past) flags a cycle at risk
     *  while open work remains. */
    private static final Integer AT_RISK_WINDOW_DAYS = 7;

    // ---- DTOs ----------------------------------------------------------------

    public class CycleHealthDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String status;         // 'Active' | 'Claims Paused'
        @AuraEnabled public String teamName;       // null = open to the whole pool
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Integer daysToTarget;  // negative = past due; null = no date
        @AuraEnabled public Integer caseCount;     // distinct cases in scope
        @AuraEnabled public Integer unclaimedSeats;
        @AuraEnabled public Integer oldestUnclaimedDays; // null when nothing is unclaimed
        @AuraEnabled public Integer notStartedClaims;
        @AuraEnabled public Integer inProgressClaims;
        @AuraEnabled public Integer completeClaims;
        @AuraEnabled public Integer failedRuns;
        @AuraEnabled public Integer releasedRuns;
        @AuraEnabled public Boolean atRisk;
    }

    public class UnclaimedRowDTO {
        @AuraEnabled public Id executionId;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseTitle;   // null = fall back to the code
        @AuraEnabled public String moduleName;
        @AuraEnabled public String priority;
        @AuraEnabled public String effort;
        @AuraEnabled public Datetime openedDate;
        @AuraEnabled public Integer sittingDays;
    }

    public class EventRowDTO {
        @AuraEnabled public String action;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String testerName;
        @AuraEnabled public String actorName;
        @AuraEnabled public String reason;
        @AuraEnabled public Datetime timestamp;
    }

    public class DrilldownDTO {
        @AuraEnabled public List<UnclaimedRowDTO> unclaimed = new List<UnclaimedRowDTO>();
        @AuraEnabled public List<EventRowDTO> events = new List<EventRowDTO>();
    }

    public class DashboardSummaryDTO {
        @AuraEnabled public Integer atRiskCycles = 0;
        @AuraEnabled public Integer unclaimedSeats = 0;
        @AuraEnabled public Integer failedRuns = 0;
        @AuraEnabled public Integer testersParticipating = 0;
        /** null = the open cycles have no assigned team, so there's no fixed
         *  eligible-tester roster to divide by (see getDashboardSummary). */
        @AuraEnabled public Integer testersTotal;
        @AuraEnabled public CycleHealthDTO heroCycle;
        @AuraEnabled public List<CycleHealthDTO> atRisk = new List<CycleHealthDTO>();
    }

    // ---- Reads ---------------------------------------------------------------

    @AuraEnabled
    public static List<CycleHealthDTO> getCoverage() {
        assertCoverage();
        List<Test_Cycle__c> cycles = [
            SELECT Id, Name, Status__c, Target_Date__c, Assigned_Team__r.Name
            FROM Test_Cycle__c
            WHERE Status__c != :UatConstants.CYCLE_CLOSED
            ORDER BY Target_Date__c NULLS LAST, Name
            LIMIT 200
        ];
        Set<Id> cycleIds = new Map<Id, Test_Cycle__c>(cycles).keySet();

        Map<Id, Integer> casesByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT_DISTINCT(Test_Case__c) cases
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
            GROUP BY Test_Cycle__c
        ]) {
            casesByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('cases'));
        }
        Map<Id, Integer> unclaimedByCycle = new Map<Id, Integer>();
        Map<Id, Datetime> oldestSlotByCycle = new Map<Id, Datetime>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT(Id) slots, MIN(CreatedDate) oldest
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds AND Assigned_Tester__c = null
            GROUP BY Test_Cycle__c
        ]) {
            unclaimedByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('slots'));
            oldestSlotByCycle.put((Id) ar.get('cycleId'), (Datetime) ar.get('oldest'));
        }
        Map<Id, Map<String, Integer>> claimsByStatus = new Map<Id, Map<String, Integer>>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, Testing_Status__c status, COUNT(Id) total
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
            AND Assigned_Tester__c != null AND Released__c = false
            GROUP BY Test_Cycle__c, Testing_Status__c
        ]) {
            Id cycleId = (Id) ar.get('cycleId');
            if (!claimsByStatus.containsKey(cycleId)) {
                claimsByStatus.put(cycleId, new Map<String, Integer>());
            }
            claimsByStatus.get(cycleId).put((String) ar.get('status'), (Integer) ar.get('total'));
        }
        Map<Id, Integer> failedByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT(Id) total
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
            AND Assigned_Tester__c != null AND Released__c = false
            AND Testing_Result__c = 'Failed'
            GROUP BY Test_Cycle__c
        ]) {
            failedByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('total'));
        }
        Map<Id, Integer> releasedByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT(Id) total
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds AND Released__c = true
            GROUP BY Test_Cycle__c
        ]) {
            releasedByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('total'));
        }

        Date today = Date.today();
        List<CycleHealthDTO> rows = new List<CycleHealthDTO>();
        for (Test_Cycle__c cycle : cycles) {
            CycleHealthDTO row = new CycleHealthDTO();
            row.cycleId = cycle.Id;
            row.cycleName = cycle.Name;
            row.status = String.isBlank(cycle.Status__c) ? UatConstants.CYCLE_ACTIVE : cycle.Status__c;
            row.teamName = cycle.Assigned_Team__r != null ? cycle.Assigned_Team__r.Name : null;
            row.targetDate = cycle.Target_Date__c;
            row.daysToTarget = cycle.Target_Date__c == null
                ? null : today.daysBetween(cycle.Target_Date__c);
            row.caseCount = valueOr(casesByCycle.get(cycle.Id));
            row.unclaimedSeats = valueOr(unclaimedByCycle.get(cycle.Id));
            Datetime oldest = oldestSlotByCycle.get(cycle.Id);
            row.oldestUnclaimedDays = oldest == null ? null : oldest.date().daysBetween(today);
            Map<String, Integer> statuses = claimsByStatus.containsKey(cycle.Id)
                ? claimsByStatus.get(cycle.Id) : new Map<String, Integer>();
            row.notStartedClaims = valueOr(statuses.get('Not Started'));
            row.inProgressClaims = valueOr(statuses.get('In Progress'));
            row.completeClaims = valueOr(statuses.get('Complete'));
            row.failedRuns = valueOr(failedByCycle.get(cycle.Id));
            row.releasedRuns = valueOr(releasedByCycle.get(cycle.Id));
            Boolean openWork = row.unclaimedSeats > 0
                || row.notStartedClaims > 0 || row.inProgressClaims > 0;
            row.atRisk = row.daysToTarget != null
                && row.daysToTarget <= AT_RISK_WINDOW_DAYS
                && openWork;
            rows.add(row);
        }
        return rows;
    }

    /** Cycle Dashboard summary: same rollups as getCoverage(), reduced to a
     *  hero cycle, aggregate stat tiles, and the at-risk list — no new SOQL
     *  beyond the small tester-participation count below. */
    @AuraEnabled
    public static DashboardSummaryDTO getDashboardSummary() {
        List<CycleHealthDTO> rows = getCoverage();
        DashboardSummaryDTO dto = new DashboardSummaryDTO();
        CycleHealthDTO hero;
        for (CycleHealthDTO row : rows) {
            dto.unclaimedSeats += row.unclaimedSeats;
            dto.failedRuns += row.failedRuns;
            if (row.atRisk) {
                dto.atRiskCycles++;
                dto.atRisk.add(row);
                if (hero == null) {
                    hero = row;
                }
            }
        }
        dto.heroCycle = hero != null ? hero : (rows.isEmpty() ? null : rows[0]);

        // Participation is scoped to cycles with an assigned team — a
        // teamless cycle is open to every UAT_Tester holder, and there's no
        // cheap query for "everyone" without scanning PermissionSetAssignment,
        // so those cycles are left out of both sides of the ratio rather than
        // faked into a denominator.
        Map<Id, CycleHealthDTO> cycleIds = new Map<Id, CycleHealthDTO>();
        for (CycleHealthDTO row : rows) {
            cycleIds.put(row.cycleId, row);
        }
        Set<Id> teamIds = new Set<Id>();
        for (Test_Cycle__c c : [
            SELECT Assigned_Team__c FROM Test_Cycle__c
            WHERE Id IN :cycleIds.keySet() AND Assigned_Team__c != null
        ]) {
            teamIds.add(c.Assigned_Team__c);
        }
        Set<Id> memberIds = new Set<Id>();
        for (Team_Member__c tm : [
            SELECT User__c FROM Team_Member__c WHERE Team__c IN :teamIds
        ]) {
            memberIds.add(tm.User__c);
        }
        if (!memberIds.isEmpty()) {
            dto.testersTotal = memberIds.size();
        }
        Set<Id> participating = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Assigned_Tester__c tester
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds.keySet()
            AND Assigned_Tester__c != null AND Released__c = false
            GROUP BY Assigned_Tester__c
        ]) {
            participating.add((Id) ar.get('tester'));
        }
        dto.testersParticipating = participating.size();

        return dto;
    }

    @AuraEnabled
    public static DrilldownDTO getCycleDrilldown(Id cycleId) {
        assertCoverage();
        DrilldownDTO dto = new DrilldownDTO();
        Date today = Date.today();
        for (Test_Execution__c slot : [
            SELECT Id, CreatedDate, Test_Case__r.Case_ID__c, Test_Case__r.Title__c,
                Test_Case__r.Module__r.Name,
                Test_Case__r.Priority__c, Test_Case__r.Estimated_Effort__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c = null
            ORDER BY CreatedDate
            LIMIT 200
        ]) {
            UnclaimedRowDTO row = new UnclaimedRowDTO();
            row.executionId = slot.Id;
            row.caseCode = slot.Test_Case__r.Case_ID__c;
            row.caseTitle = slot.Test_Case__r.Title__c;
            row.moduleName = slot.Test_Case__r.Module__r.Name;
            row.priority = slot.Test_Case__r.Priority__c;
            row.effort = slot.Test_Case__r.Estimated_Effort__c;
            row.openedDate = slot.CreatedDate;
            row.sittingDays = slot.CreatedDate.date().daysBetween(today);
            dto.unclaimed.add(row);
        }
        for (Test_Assignment_Event__c event : [
            SELECT Action__c, Reason__c, CreatedDate,
                Tester__r.Name, Actor__r.Name, Test_Case__r.Case_ID__c
            FROM Test_Assignment_Event__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            EventRowDTO row = new EventRowDTO();
            row.action = event.Action__c;
            row.caseCode = event.Test_Case__r != null ? event.Test_Case__r.Case_ID__c : null;
            row.testerName = event.Tester__r != null ? event.Tester__r.Name : null;
            row.actorName = event.Actor__r != null ? event.Actor__r.Name : null;
            row.reason = event.Reason__c;
            row.timestamp = event.CreatedDate;
            dto.events.add(row);
        }
        return dto;
    }

    // ---- Internals -------------------------------------------------------------

    private static Integer valueOr(Integer value) {
        return value == null ? 0 : value;
    }

    /** Same capability as the Cycles section (the feed exposes the audit
     *  trail, so bare read on cycles isn't enough) — mirrors
     *  AdminAccessService.getAccess().uatCoverage. */
    private static void assertCoverage() {
        if (!Schema.sObjectType.Test_Cycle__c.isCreateable()
            || !Schema.sObjectType.Test_Cycle__c.isUpdateable()
            || !Schema.sObjectType.Test_Assignment_Event__c.isAccessible()) {
            throw auraError('You do not have access to pool health.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}