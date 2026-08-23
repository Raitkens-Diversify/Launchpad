/**
 * UatRunController
 *
 * Apex behind the tester app (uatTesterApp): the cycle-grouped queue, the
 * step-by-step runner, evidence via real Salesforce Files, UX feedback, the
 * shared exploratory-findings log, and the header cycle switcher's cycle
 * list (getMyCycles) + per-cycle dashboard scoping (getDashboard's cycleId).
 *
 * Visibility rule (02 Part 2, extended by the open-pool design doc): the
 * QUEUE is strictly the tester's own claimed work; claimable seats live in
 * the POOL, whose audience is the cycle's assigned team — or every UAT_Tester
 * holder when the cycle has no team. Enforced as QUERY PREDICATES here (by
 * design — see the build plan's sharing rationale), plus a per-record check
 * before the runner opens and inside every claim transaction.
 *
 * Exploratory findings are a team-VISIBLE log scoped to the cycle's audience
 * (open-pool design §8): anyone in the audience reads every entry, but edit
 * and delete are author-or-admin (UAT_Console) — the 2026-08 session build
 * superseded the original any-member rule. Findings may link to an
 * Exploratory_Session__c (session workflow lives in UatSessionController);
 * the audience gates themselves live in UatAudienceService, shared by both
 * controllers.
 *
 * Conventions: with sharing, describe asserts, AuraHandledException,
 * JSON-string write payloads (org quirk).
 */
public with sharing class UatRunController {

    // ---- DTOs ----------------------------------------------------------------

    public class QueueCardDTO {
        @AuraEnabled public Id executionId;
        @AuraEnabled public Id caseId;
        @AuraEnabled public Id cycleId;          // null on standalone runs
        @AuraEnabled public String cycleName;    // null on standalone runs
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseNumber;   // Test_Case__c autonumber, e.g. TC-00042
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String version;
        @AuraEnabled public String description;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String systemName;
        @AuraEnabled public String status;
        @AuraEnabled public String result;
        @AuraEnabled public Boolean unclaimed;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public Date lastTestedDate;
        @AuraEnabled public Datetime lastUpdated;  // LastModifiedDate — recency cue; bumps on ANY edit, not just tester activity
        @AuraEnabled public Integer stepsAnswered;
        @AuraEnabled public Integer stepsTotal;
        @AuraEnabled public Integer stepsFailed;    // answered scripted steps with Result__c = 'Fail'
        @AuraEnabled public Integer stepsBlocked;   // answered scripted steps with Result__c = 'Blocked'
    }

    public class QueueGroupDTO {
        @AuraEnabled public Id cycleId;          // null for the Standalone group
        @AuraEnabled public String cycleName;
        @AuraEnabled public String cycleStatus;
        @AuraEnabled public Date targetDate;
        @AuraEnabled public List<QueueCardDTO> cards = new List<QueueCardDTO>();
    }

    public class QueueDTO {
        @AuraEnabled public List<QueueGroupDTO> cycleGroups = new List<QueueGroupDTO>();
        @AuraEnabled public QueueGroupDTO standalone;
        @AuraEnabled public QueueSummaryDTO summary; // bucket counts over every card (cycles + standalone)
    }

    public class RunnerStepDTO {
        @AuraEnabled public Id stepId;
        @AuraEnabled public Decimal stepNumber;
        @AuraEnabled public String stepTitle;   // optional per-step name
        @AuraEnabled public String condition;
        @AuraEnabled public String description;
        @AuraEnabled public String expected;
        @AuraEnabled public Boolean isExplore;
        @AuraEnabled public String explorePrompt;
        @AuraEnabled public Id resultId;
        @AuraEnabled public String actualResult;
        @AuraEnabled public String result;
        @AuraEnabled public String exploreNotes;
        @AuraEnabled public String defectSeverity;
        @AuraEnabled public String defectSummary;
        @AuraEnabled public Integer evidenceCount;
    }

    public class RunnerRefDTO {
        @AuraEnabled public String type;
        @AuraEnabled public String label;
        @AuraEnabled public String url;
        @AuraEnabled public UatFileService.FileDTO file;
    }

    public class RunnerDTO {
        @AuraEnabled public Id executionId;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String description;  // full text — the pool card's blurb() is truncated
        @AuraEnabled public String preConditions;
        @AuraEnabled public String version;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String pathLabel;   // "System › Group · case-id · Cycle"
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Datetime claimedDate;
        @AuraEnabled public String status;
        @AuraEnabled public String result;
        @AuraEnabled public Decimal uxRating;
        @AuraEnabled public String uxRecommendation;
        @AuraEnabled public List<RunnerStepDTO> steps = new List<RunnerStepDTO>();
        @AuraEnabled public List<RunnerRefDTO> referenceMaterials = new List<RunnerRefDTO>();
    }

    public class ExecutionSummaryDTO {
        @AuraEnabled public Id executionId;
        @AuraEnabled public String status;
        @AuraEnabled public String result;
    }

    public class FindingDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;         // 'EF-00003' — the promote badge
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String source;       // Session | Test case
        @AuraEnabled public String whatTesting;
        @AuraEnabled public String whatExpected;
        @AuraEnabled public String whatHappened;
        @AuraEnabled public String severity;
        /** Admin triage disposition + tracker ref — read-only on every tester
         *  surface; written only by UatReportController.setFindingWorkflowStatus. */
        @AuraEnabled public String workflowStatus;
        @AuraEnabled public String externalRef;
        @AuraEnabled public String noEvidenceReason;
        @AuraEnabled public Id sessionId;        // null = logged straight in the cycle log
        @AuraEnabled public String sessionName;  // 'ES-00012'
        @AuraEnabled public String sessionTitle;
        @AuraEnabled public Id sourceNoteId;     // the entry it was promoted from
        @AuraEnabled public Datetime sourceLoggedAt; // that entry's timestamp
        @AuraEnabled public Id executionId;      // Test case-sourced only
        @AuraEnabled public String caseTitle;    // ditto — what an admin triages by
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
        @AuraEnabled public Date dateLogged;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
    }

    public class StepResultInput {
        public Id resultId;
        public String actualResult;
        public String result;
        public String exploreNotes;
        public String defectSeverity;
        public String defectSummary;
    }

    public class FeedbackInput {
        public Id executionId;
        public Decimal uxRating;
        public String uxRecommendation;
    }

    public class FindingInput {
        public Id id;              // null = create
        public Id cycleId;
        public Id sessionId;       // create-only: link into MY Active session (cycle derives from it)
        public Id sourceNoteId;    // create-only: promoted from this session entry
        public String title;
        public String type;        // Defect | Works as expected | Suggestion | Question
        public String whatTesting;
        public String whatExpected;
        public String whatHappened;
        public String severity;    // Defect only — force-cleared otherwise
        public String noEvidenceReason;
        /** Docs uploaded into the open form but not yet claimed onto the
         *  record. Passed so the High/Critical evidence gate can be satisfied
         *  at INSERT — the claim happens after saveFinding returns, so
         *  counting ContentDocumentLinks alone would reject every new
         *  finding that has evidence attached in the same breath. */
        public List<String> stagedDocumentIds;
    }

    public class ReleaseInput {
        public Id executionId;
        public String reason;
    }

    public class PoolCardDTO {
        @AuraEnabled public Id executionId;     // the open slot
        @AuraEnabled public Id caseId;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseNumber;  // Test_Case__c autonumber, e.g. TC-00042
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String version;
        @AuraEnabled public String description;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String systemName;
        @AuraEnabled public String priority;
        @AuraEnabled public String effort;
        @AuraEnabled public Integer seatsTaken;
        @AuraEnabled public Integer seatsMax;
        @AuraEnabled public Datetime openedDate; // when this seat opened (slot CreatedDate)
    }

    public class PoolGroupDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Integer claimLimit;   // null = unlimited
        @AuraEnabled public Integer myOpenClaims;
        @AuraEnabled public List<PoolCardDTO> cards = new List<PoolCardDTO>();
    }

    public class BulkClaimResultDTO {
        @AuraEnabled public Integer claimed = 0;
        @AuraEnabled public Integer takenByOthers = 0;
        @AuraEnabled public Boolean capReached = false;
    }

    public class DashboardHeroDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String cycleStatus;  // null Status__c normalizes to 'Active'
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Integer daysToTarget;
        // My claims in the hero cycle only.
        @AuraEnabled public Integer notStarted = 0;
        @AuraEnabled public Integer inProgress = 0;
        @AuraEnabled public Integer blocked = 0;
        @AuraEnabled public Integer completePassed = 0;
        @AuraEnabled public Integer completeFailed = 0;
        @AuraEnabled public Integer total = 0;
        // Cycle-wide: every live seat in the hero cycle, all testers.
        @AuraEnabled public Integer cycleCompleted = 0;
        @AuraEnabled public Integer cycleInProgress = 0;
        @AuraEnabled public Integer cycleBlocked = 0;
        @AuraEnabled public Integer cycleAvailable = 0;
        @AuraEnabled public Integer cycleClaimedNotStarted = 0;
        @AuraEnabled public Integer cycleTotal = 0;
    }

    public class QueueSummaryDTO {
        @AuraEnabled public Integer notStarted = 0;   // assigned, not begun
        @AuraEnabled public Integer inProgress = 0;
        @AuraEnabled public Integer blocked = 0;
        @AuraEnabled public Integer completed = 0;
        @AuraEnabled public Integer total = 0;
    }

    public class ActivityItemDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String action;      // Claimed | Released | Auto Released | Reassigned
        @AuraEnabled public String testerName;
        @AuraEnabled public Boolean isMe;
        @AuraEnabled public Datetime timestamp;
    }

    public class DashboardDTO {
        @AuraEnabled public DashboardHeroDTO hero;
        @AuraEnabled public List<QueueCardDTO> continueTesting = new List<QueueCardDTO>();
        @AuraEnabled public List<PoolCardDTO> availableToClaim = new List<PoolCardDTO>();
        @AuraEnabled public List<QueueCardDTO> recentlyCompleted = new List<QueueCardDTO>();
        @AuraEnabled public QueueSummaryDTO queueSummary;
        @AuraEnabled public List<ActivityItemDTO> recentActivity = new List<ActivityItemDTO>();
    }

    // ---- Queue ---------------------------------------------------------------

    @AuraEnabled
    public static QueueDTO getQueue() {
        assertTester();
        Id me = UserInfo.getUserId();
        Set<Id> myTeams = myTeamIds(me);

        // The queue is strictly MY claimed work (open-pool design: claimable
        // seats moved to getPool). Released runs are history and stay out.
        // Closed cycles leave the queue entirely (SOQL != includes null-status
        // rows, so pre-Status cycles count as active). Claimed runs stay
        // reachable by direct open — only queue visibility is affected.
        List<Test_Execution__c> executions = [
            SELECT Id, Test_Case__c, Test_Case__r.Case_ID__c, Test_Case__r.Name,
                Test_Case__r.Title__c, Test_Case__r.Version__c, Test_Case__r.Description__c,
                Test_Case__r.Module__r.Name,
                Test_Case__r.Module__r.Module_Group__r.System__r.Name,
                Test_Cycle__c, Test_Cycle__r.Name, Test_Cycle__r.Target_Date__c,
                Test_Cycle__r.Status__c,
                Assigned_Tester__c, Testing_Status__c, Testing_Result__c,
                Last_Tested_Date__c, LastModifiedDate
            FROM Test_Execution__c
            WHERE Assigned_Tester__c = :me
            AND Released__c = false
            AND (Test_Cycle__c = null OR Test_Cycle__r.Status__c != 'Closed')
            ORDER BY Test_Case__r.Case_ID__c
            LIMIT 1000
        ];

        Map<Id, QueueGroupDTO> groupsByCycle = new Map<Id, QueueGroupDTO>();
        QueueGroupDTO standalone = new QueueGroupDTO();
        standalone.cycleName = 'Standalone';
        for (Test_Execution__c e : executions) {
            QueueCardDTO card = new QueueCardDTO();
            card.executionId = e.Id;
            card.caseId = e.Test_Case__c;
            card.cycleId = e.Test_Cycle__c;
            card.cycleName = e.Test_Cycle__c == null ? null : e.Test_Cycle__r.Name;
            card.caseCode = e.Test_Case__r.Case_ID__c;
            card.caseNumber = e.Test_Case__r.Name;
            card.caseTitle = e.Test_Case__r.Title__c;
            card.version = e.Test_Case__r.Version__c;
            card.description = blurb(e.Test_Case__r.Description__c);
            card.moduleName = e.Test_Case__r.Module__r.Name;
            card.systemName = e.Test_Case__r.Module__r.Module_Group__r.System__r.Name;
            card.status = e.Testing_Status__c;
            card.result = e.Testing_Result__c;
            card.lastTestedDate = e.Last_Tested_Date__c;
            card.lastUpdated = e.LastModifiedDate;
            card.unclaimed = false; // claimables live in the pool now
            card.actionLabel = e.Testing_Status__c == 'Complete' ? 'Review'
                : e.Testing_Status__c == 'In Progress' ? 'Continue'
                : 'Start';

            if (e.Test_Cycle__c == null) {
                standalone.cards.add(card);
            } else {
                QueueGroupDTO grp = groupsByCycle.get(e.Test_Cycle__c);
                if (grp == null) {
                    grp = new QueueGroupDTO();
                    grp.cycleId = e.Test_Cycle__c;
                    grp.cycleName = e.Test_Cycle__r.Name;
                    grp.cycleStatus = e.Test_Cycle__r.Status__c;
                    grp.targetDate = e.Test_Cycle__r.Target_Date__c;
                    groupsByCycle.put(e.Test_Cycle__c, grp);
                }
                grp.cards.add(card);
            }
        }
        // Cycles in the tester's audience always show — the always-present
        // Exploratory Testing card exists even with no cases. Audience =
        // my teams' cycles plus team-less cycles (open to every tester),
        // matching getPool and getMyCycles.
        for (Test_Cycle__c cycle : [
            SELECT Id, Name, Status__c, Target_Date__c FROM Test_Cycle__c
            WHERE (Assigned_Team__c IN :myTeams OR Assigned_Team__c = null)
            AND Status__c != :UatConstants.CYCLE_CLOSED
            AND Id NOT IN :groupsByCycle.keySet()
        ]) {
            QueueGroupDTO grp = new QueueGroupDTO();
            grp.cycleId = cycle.Id;
            grp.cycleName = cycle.Name;
            grp.cycleStatus = cycle.Status__c;
            grp.targetDate = cycle.Target_Date__c;
            groupsByCycle.put(cycle.Id, grp);
        }
        // Most relevant/active first: cycles where I have in-progress work,
        // then nearest target date (nulls last). Standalone group always last.
        List<QueueGroupDTO> ordered = groupsByCycle.values();
        ordered.sort(new QueueGroupComparator());

        // Step X-of-Y on every card (two aggregate queries regardless of row
        // count) and the bucket tallies the queue chips and the dashboard
        // both read — one source of truth for both surfaces.
        List<QueueCardDTO> allCards = new List<QueueCardDTO>();
        for (QueueGroupDTO grp : ordered) {
            allCards.addAll(grp.cards);
        }
        allCards.addAll(standalone.cards);
        if (!allCards.isEmpty()) {
            attachStepProgress(allCards);
        }
        QueueSummaryDTO summary = new QueueSummaryDTO();
        for (QueueCardDTO card : allCards) {
            tally(summary, bucketOf(card));
        }

        QueueDTO dto = new QueueDTO();
        dto.cycleGroups = ordered;
        dto.standalone = standalone.cards.isEmpty() ? null : standalone;
        dto.summary = summary;
        return dto;
    }

    private class QueueGroupComparator implements Comparator<QueueGroupDTO> {
        public Integer compare(QueueGroupDTO a, QueueGroupDTO b) {
            Integer activeA = hasInProgress(a) ? 0 : 1;
            Integer activeB = hasInProgress(b) ? 0 : 1;
            if (activeA != activeB) {
                return activeA - activeB;
            }
            if (a.targetDate == null && b.targetDate == null) {
                return 0;
            }
            if (a.targetDate == null) {
                return 1;
            }
            if (b.targetDate == null) {
                return -1;
            }
            return a.targetDate < b.targetDate ? -1 : (a.targetDate > b.targetDate ? 1 : 0);
        }

        private Boolean hasInProgress(QueueGroupDTO grp) {
            for (QueueCardDTO card : grp.cards) {
                if (card.status == 'In Progress' && !card.unclaimed) {
                    return true;
                }
            }
            return false;
        }
    }

    // ---- Open pool (open-pool design §4, §6.4) ---------------------------------

    /** Claimable seats, grouped by cycle. Audience: the cycle's team, or every
     *  tester when the cycle has no team. Paused/closed cycles don't offer
     *  seats. Filtering/sorting happens client-side (pools are small). */
    @AuraEnabled
    public static List<PoolGroupDTO> getPool() {
        assertTester();
        Id me = UserInfo.getUserId();
        Set<Id> myTeams = myTeamIds(me);

        List<Test_Execution__c> slots = [
            SELECT Id, CreatedDate, Test_Case__c, Test_Case__r.Case_ID__c, Test_Case__r.Name,
                Test_Case__r.Title__c, Test_Case__r.Version__c, Test_Case__r.Description__c,
                Test_Case__r.Priority__c, Test_Case__r.Estimated_Effort__c,
                Test_Case__r.Max_Testers_Override__c,
                Test_Case__r.Module__r.Name,
                Test_Case__r.Module__r.Module_Group__r.System__r.Name,
                Test_Cycle__c, Test_Cycle__r.Name, Test_Cycle__r.Target_Date__c,
                Test_Cycle__r.Max_Testers__c, Test_Cycle__r.Claim_Limit_Per_Tester__c
            FROM Test_Execution__c
            WHERE Assigned_Tester__c = null
            AND Test_Cycle__c != null
            AND (Assigned_Team__c IN :myTeams OR Assigned_Team__c = null)
            AND (Test_Cycle__r.Status__c = 'Active' OR Test_Cycle__r.Status__c = null)
            ORDER BY Test_Case__r.Case_ID__c
            LIMIT 1000
        ];

        // Seats taken per (cycle, case), and my open claims per cycle.
        Set<Id> caseIds = new Set<Id>();
        Set<Id> cycleIds = new Set<Id>();
        for (Test_Execution__c slot : slots) {
            caseIds.add(slot.Test_Case__c);
            cycleIds.add(slot.Test_Cycle__c);
        }
        Map<String, Integer> takenByPair = new Map<String, Integer>();
        Map<Id, Integer> myOpenByCycle = new Map<Id, Integer>();
        Set<String> myActivePairs = new Set<String>();
        for (Test_Execution__c e : [
            SELECT Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Testing_Status__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds AND Assigned_Tester__c != null
            AND Released__c = false
        ]) {
            String pair = String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c);
            if (caseIds.contains(e.Test_Case__c)) {
                Integer count = takenByPair.containsKey(pair) ? takenByPair.get(pair) : 0;
                takenByPair.put(pair, count + 1);
            }
            if (e.Assigned_Tester__c == me) {
                // Any unreleased seat of mine — Complete included — makes the
                // (cycle, case) unclaimable for ME: claimSeat would just hand
                // back this run. Released seats are deliberately absent here
                // so re-claiming can resume an earlier run.
                myActivePairs.add(pair);
                if (e.Testing_Status__c != 'Complete') {
                    Integer count = myOpenByCycle.containsKey(e.Test_Cycle__c)
                        ? myOpenByCycle.get(e.Test_Cycle__c) : 0;
                    myOpenByCycle.put(e.Test_Cycle__c, count + 1);
                }
            }
        }

        Map<Id, PoolGroupDTO> groups = new Map<Id, PoolGroupDTO>();
        for (Test_Execution__c slot : slots) {
            String pair = String.valueOf(slot.Test_Cycle__c) + ':' + String.valueOf(slot.Test_Case__c);
            // Per-caller filter: the slot row itself is untouched, so every
            // other tester still sees it. Skip BEFORE creating the group so a
            // cycle whose every card is mine emits no empty group.
            if (myActivePairs.contains(pair)) {
                continue;
            }
            PoolGroupDTO grp = groups.get(slot.Test_Cycle__c);
            if (grp == null) {
                grp = new PoolGroupDTO();
                grp.cycleId = slot.Test_Cycle__c;
                grp.cycleName = slot.Test_Cycle__r.Name;
                grp.targetDate = slot.Test_Cycle__r.Target_Date__c;
                grp.claimLimit = slot.Test_Cycle__r.Claim_Limit_Per_Tester__c == null
                    ? null : Integer.valueOf(slot.Test_Cycle__r.Claim_Limit_Per_Tester__c);
                grp.myOpenClaims = myOpenByCycle.containsKey(slot.Test_Cycle__c)
                    ? myOpenByCycle.get(slot.Test_Cycle__c) : 0;
                groups.put(slot.Test_Cycle__c, grp);
            }
            PoolCardDTO card = new PoolCardDTO();
            card.executionId = slot.Id;
            card.caseId = slot.Test_Case__c;
            card.cycleId = slot.Test_Cycle__c;
            card.cycleName = slot.Test_Cycle__r.Name;
            card.caseCode = slot.Test_Case__r.Case_ID__c;
            card.caseNumber = slot.Test_Case__r.Name;
            card.caseTitle = slot.Test_Case__r.Title__c;
            card.version = slot.Test_Case__r.Version__c;
            card.description = blurb(slot.Test_Case__r.Description__c);
            card.moduleName = slot.Test_Case__r.Module__r.Name;
            card.systemName = slot.Test_Case__r.Module__r.Module_Group__r.System__r.Name;
            card.priority = slot.Test_Case__r.Priority__c;
            card.effort = slot.Test_Case__r.Estimated_Effort__c;
            card.openedDate = slot.CreatedDate;
            card.seatsTaken = takenByPair.containsKey(pair) ? takenByPair.get(pair) : 0;
            Decimal caseOverride = slot.Test_Case__r.Max_Testers_Override__c;
            Decimal cycleDefault = slot.Test_Cycle__r.Max_Testers__c;
            Decimal maxSeats = caseOverride != null ? caseOverride
                : (cycleDefault != null ? cycleDefault : 1);
            card.seatsMax = maxSeats < 1 ? 1 : Integer.valueOf(maxSeats);
            grp.cards.add(card);
        }
        return groups.values();
    }

    /** Claim one seat. Success returns my execution id; a lost race or a full
     *  pool surfaces as prose the LWC toasts verbatim, then refreshes. */
    @AuraEnabled
    public static Id claimCase(Id cycleId, Id caseId) {
        assertTester();
        assertCycleAudience(cycleId);
        try {
            return UatExecutionService.claimSeat(cycleId, caseId, UserInfo.getUserId()).Id;
        } catch (UatExecutionService.UatExecutionException e) {
            throw auraError(e.getMessage());
        }
    }

    /** "Claim all available" for one cycle (§6.4): oldest seats first, stops
     *  at the per-tester cap, reports a tally — partial success is expected
     *  behavior, not an error. Bounded at 50 seats per invocation. */
    @AuraEnabled
    public static BulkClaimResultDTO claimAllAvailable(Id cycleId) {
        assertTester();
        assertCycleAudience(cycleId);
        Id me = UserInfo.getUserId();
        Set<Id> myTeams = myTeamIds(me);
        List<Test_Execution__c> slots = [
            SELECT Test_Case__c FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c = null
            AND (Assigned_Team__c IN :myTeams OR Assigned_Team__c = null)
            ORDER BY CreatedDate
            LIMIT 50
        ];
        // Cases where I already hold an unreleased seat: claimSeat would just
        // return that run (alreadyMine), silently inflating tally.claimed and
        // burning the 50-slot budget on no-ops.
        Set<Id> myCaseIds = new Set<Id>();
        for (Test_Execution__c mine : [
            SELECT Test_Case__c FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c = :me
            AND Released__c = false
        ]) {
            myCaseIds.add(mine.Test_Case__c);
        }
        BulkClaimResultDTO tally = new BulkClaimResultDTO();
        for (Test_Execution__c slot : slots) {
            if (myCaseIds.contains(slot.Test_Case__c)) {
                continue;
            }
            try {
                UatExecutionService.claimSeat(cycleId, slot.Test_Case__c, me);
                tally.claimed++;
            } catch (UatExecutionService.ClaimCapException e) {
                tally.capReached = true;
                break; // every further claim fails the same way
            } catch (UatExecutionService.PoolFullException e) {
                tally.takenByOthers++;
            } catch (UatExecutionService.UatExecutionException e) {
                throw auraError(e.getMessage());
            }
        }
        return tally;
    }

    // ---- Cycle context (header switcher) ----------------------------------------

    public class CycleOptionDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String cycleStatus;   // null Status__c normalizes to 'Active'
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Integer daysToTarget; // null when no target date
        @AuraEnabled public Integer myClaimCount = 0; // my unreleased claims in the cycle
    }

    /** The cycles this tester can point the app at: the pool audience (my
     *  teams' cycles plus team-less cycles, not Closed — SOQL != keeps the
     *  null-status pre-Status cycles, which count as active) UNION any cycle
     *  where I still hold an unreleased claim, so a team switch never strands
     *  my work (mirrors assertCycleAudience's live-claim clause).
     *  MIRROR: keep these predicates in lockstep with getQueue's group
     *  building (executions query + team backfill) — getDashboard(cycleId)
     *  validates the requested id against those groups, so drift silently
     *  resets user selections. */
    @AuraEnabled
    public static List<CycleOptionDTO> getMyCycles() {
        assertTester();
        Id me = UserInfo.getUserId();
        Set<Id> myTeams = myTeamIds(me);

        Map<Id, CycleOptionDTO> options = new Map<Id, CycleOptionDTO>();
        for (Test_Cycle__c c : [
            SELECT Id, Name, Status__c, Target_Date__c FROM Test_Cycle__c
            WHERE (Assigned_Team__c IN :myTeams OR Assigned_Team__c = null)
            AND Status__c != :UatConstants.CYCLE_CLOSED
        ]) {
            options.put(c.Id, toCycleOption(c));
        }
        Map<Id, Integer> claimsByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT(Id) total
            FROM Test_Execution__c
            WHERE Assigned_Tester__c = :me AND Released__c = false
            AND Test_Cycle__c != null
            AND Test_Cycle__r.Status__c != :UatConstants.CYCLE_CLOSED
            GROUP BY Test_Cycle__c
        ]) {
            claimsByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('total'));
        }
        Set<Id> claimOnly = new Set<Id>(claimsByCycle.keySet());
        claimOnly.removeAll(options.keySet());
        if (!claimOnly.isEmpty()) {
            for (Test_Cycle__c c : [
                SELECT Id, Name, Status__c, Target_Date__c
                FROM Test_Cycle__c WHERE Id IN :claimOnly
            ]) {
                options.put(c.Id, toCycleOption(c));
            }
        }
        for (Id cid : claimsByCycle.keySet()) {
            options.get(cid).myClaimCount = claimsByCycle.get(cid);
        }
        List<CycleOptionDTO> result = options.values();
        result.sort(new CycleOptionComparator());
        return result;
    }

    private static CycleOptionDTO toCycleOption(Test_Cycle__c c) {
        CycleOptionDTO dto = new CycleOptionDTO();
        dto.cycleId = c.Id;
        dto.cycleName = c.Name;
        dto.cycleStatus = c.Status__c == null ? UatConstants.CYCLE_ACTIVE : c.Status__c;
        dto.targetDate = c.Target_Date__c;
        dto.daysToTarget = c.Target_Date__c == null
            ? null : Date.today().daysBetween(c.Target_Date__c);
        return dto;
    }

    /** Soonest target first (nulls last), then name — the switcher menu order. */
    private class CycleOptionComparator implements Comparator<CycleOptionDTO> {
        public Integer compare(CycleOptionDTO a, CycleOptionDTO b) {
            if (a.targetDate != b.targetDate) {
                if (a.targetDate == null) { return 1; }
                if (b.targetDate == null) { return -1; }
                return a.targetDate < b.targetDate ? -1 : 1;
            }
            if (a.cycleName == b.cycleName) { return 0; }
            return a.cycleName < b.cycleName ? -1 : 1;
        }
    }

    // ---- Dashboard --------------------------------------------------------------

    private static final Integer DASHBOARD_ROW_LIMIT = 5;
    private static final Integer ACTIVITY_ROW_LIMIT = 6;

    /** One landing view: the hero cycle's cycle-wide health, my active work,
     *  the full claimable pool, my queue summary, and the cycle's recent seat
     *  activity. Row visibility still comes from getQueue()/getPool() so the
     *  audience rules stay in one place; the extra reads below are additive
     *  aggregates over records the tester's audience can already see.
     *
     *  cycleId (the header switcher's selection) is optional: null keeps the
     *  auto-picked hero and cross-cycle rows; an id matching one of my queue
     *  groups makes that cycle the hero and scopes the rows, pool, and queue
     *  summary to it. Unknown or inaccessible ids fall back to the auto-pick
     *  — group membership IS the audience check, and the landing view must
     *  never throw over a stale stored preference. */
    @AuraEnabled
    public static DashboardDTO getDashboard(Id cycleId) {
        assertTester();
        QueueDTO queue = getQueue();
        Date today = Date.today();
        DashboardDTO dto = new DashboardDTO();
        dto.queueSummary = queue.summary; // tallied once, in getQueue

        // Standalone (cycle-less) executions are intentionally left out of the
        // hero and the card rows — there's no cycle to report against. They
        // still count toward queue.summary (tallied over every card upstream).
        QueueGroupDTO heroGroup = null;
        if (cycleId != null) {
            for (QueueGroupDTO grp : queue.cycleGroups) {
                if (grp.cycleId == cycleId) {
                    heroGroup = grp;
                    break;
                }
            }
        }
        Boolean scoped = heroGroup != null;
        if (heroGroup == null && !queue.cycleGroups.isEmpty()) {
            heroGroup = queue.cycleGroups[0]; // getQueue orders most-relevant first
        }

        List<QueueCardDTO> inProgress = new List<QueueCardDTO>();
        List<QueueCardDTO> completed = new List<QueueCardDTO>();
        for (QueueGroupDTO grp : queue.cycleGroups) {
            if (scoped && grp.cycleId != heroGroup.cycleId) {
                continue;
            }
            for (QueueCardDTO card : grp.cards) {
                if (card.status == 'In Progress') {
                    inProgress.add(card);
                }
                if (card.status == 'Complete') {
                    completed.add(card);
                }
            }
        }
        // Collect-then-sort (like recentlyCompleted) so a busy hero cycle
        // can't starve later cycles out of the row.
        inProgress.sort(new CardRecencyComparator());
        for (Integer i = 0; i < Math.min(DASHBOARD_ROW_LIMIT, inProgress.size()); i++) {
            dto.continueTesting.add(inProgress[i]);
        }
        completed.sort(new RecentCardComparator());
        for (Integer i = 0; i < Math.min(DASHBOARD_ROW_LIMIT, completed.size()); i++) {
            dto.recentlyCompleted.add(completed[i]);
        }
        // Step progress already attached by getQueue — continueTesting holds
        // references to the same card objects.

        if (scoped) {
            // Sidebar counts follow the selection so they agree with the
            // queue view, which threads the same cycle id into its filter.
            QueueSummaryDTO scopedSummary = new QueueSummaryDTO();
            for (QueueCardDTO card : heroGroup.cards) {
                tally(scopedSummary, bucketOf(card));
            }
            dto.queueSummary = scopedSummary;
        }

        if (heroGroup != null) {
            DashboardHeroDTO hero = new DashboardHeroDTO();
            hero.cycleId = heroGroup.cycleId;
            hero.cycleName = heroGroup.cycleName;
            hero.cycleStatus = heroGroup.cycleStatus == null ? UatConstants.CYCLE_ACTIVE : heroGroup.cycleStatus;
            hero.targetDate = heroGroup.targetDate;
            hero.daysToTarget = heroGroup.targetDate == null
                ? null : today.daysBetween(heroGroup.targetDate);
            for (QueueCardDTO card : heroGroup.cards) {
                hero.total++;
                String bucket = bucketOf(card);
                if (bucket == 'notStarted') {
                    hero.notStarted++;
                } else if (bucket == 'completePassed') {
                    hero.completePassed++;
                } else if (bucket == 'completeFailed') {
                    hero.completeFailed++;
                } else if (bucket == 'blocked') {
                    hero.blocked++;
                } else {
                    hero.inProgress++;
                }
            }
            // Whole-cycle progress for the ring and stat row. A loop-count
            // (not GROUP BY) because available-vs-claimed-not-started needs
            // Assigned_Tester__c and status together.
            for (Test_Execution__c e : [
                SELECT Testing_Status__c, Testing_Result__c, Assigned_Tester__c
                FROM Test_Execution__c
                WHERE Test_Cycle__c = :hero.cycleId AND Released__c = false
                LIMIT 2000
            ]) {
                hero.cycleTotal++;
                if (e.Assigned_Tester__c == null) {
                    hero.cycleAvailable++;
                } else if (e.Testing_Result__c == 'Blocked') {
                    // Verdict outranks status, matching bucketOf: a run that
                    // ended Blocked is stuck, not done.
                    hero.cycleBlocked++;
                } else if (e.Testing_Status__c == 'Complete') {
                    hero.cycleCompleted++;
                } else if (e.Testing_Status__c == 'In Progress') {
                    hero.cycleInProgress++;
                } else {
                    hero.cycleClaimedNotStarted++;
                }
            }
            dto.hero = hero;
        }

        List<PoolCardDTO> poolCards = new List<PoolCardDTO>();
        for (PoolGroupDTO grp : getPool()) {
            if (scoped && grp.cycleId != heroGroup.cycleId) {
                continue;
            }
            poolCards.addAll(grp.cards);
        }
        poolCards.sort(new PoolPriorityComparator());
        // Uncapped on purpose: the dashboard searches/filters this list
        // client-side and shows the true available count. Bounded upstream
        // by getPool's LIMIT, and descriptions are abbreviated at 240.
        dto.availableToClaim.addAll(poolCards);

        // Seat-lifecycle feed for the hero cycle. Guarded so a missing
        // object grant degrades to an empty feed instead of failing the
        // whole dashboard. Force Unassigned stays admin-console-only.
        if (dto.hero != null
            && Schema.sObjectType.Test_Assignment_Event__c.isAccessible()) {
            for (Test_Assignment_Event__c ev : [
                SELECT Id, Action__c, Tester__c, Tester__r.Name, CreatedDate
                FROM Test_Assignment_Event__c
                WHERE Test_Cycle__c = :dto.hero.cycleId
                AND Action__c IN :UatConstants.ACTIVITY_FEED_EVENTS
                ORDER BY CreatedDate DESC
                LIMIT :ACTIVITY_ROW_LIMIT
            ]) {
                ActivityItemDTO item = new ActivityItemDTO();
                item.id = ev.Id;
                item.action = ev.Action__c;
                item.testerName = ev.Tester__r == null ? null : ev.Tester__r.Name;
                item.isMe = ev.Tester__c == UserInfo.getUserId();
                item.timestamp = ev.CreatedDate;
                dto.recentActivity.add(item);
            }
        }

        return dto;
    }

    /** One status bucket per queue card, shared by the hero's my-claims
     *  counters and the queue summary. Complete runs keep their verdict:
     *  a Complete run whose result is Blocked counts as blocked, not passed
     *  (Blocked never occurs on Not Started rows — recomputeRollups only
     *  sets a verdict once at least one step is answered).
     *  Mirrored client-side by bucketOf in c/uatConstants (queue filter
     *  chips) — keep the two in step. */
    private static String bucketOf(QueueCardDTO card) {
        if (card.status == 'Complete') {
            if (card.result == 'Failed') {
                return 'completeFailed';
            }
            if (card.result == 'Blocked') {
                return 'blocked';
            }
            return 'completePassed';
        }
        if (card.result == 'Blocked') {
            return 'blocked';
        }
        if (card.status == 'Not Started') {
            return 'notStarted';
        }
        return 'inProgress';
    }

    private static void tally(QueueSummaryDTO summary, String bucket) {
        summary.total++;
        if (bucket == 'notStarted') {
            summary.notStarted++;
        } else if (bucket == 'blocked') {
            summary.blocked++;
        } else if (bucket == 'inProgress') {
            summary.inProgress++;
        } else {
            summary.completed++;
        }
    }

    /** Step X-of-Y for queue cards (getQueue attaches it to every card; the
     *  dashboard reuses those objects). Same definitions as
     *  UatExecutionService.recomputeRollups: denominator = the case's
     *  scripted (non-explore) steps; numerator = answered results, ignoring
     *  explore rows and orphaned results whose step was deleted. Cost is two
     *  aggregate queries regardless of card count. */
    private static void attachStepProgress(List<QueueCardDTO> cards) {
        Set<Id> caseIds = new Set<Id>();
        Set<Id> execIds = new Set<Id>();
        for (QueueCardDTO card : cards) {
            caseIds.add(card.caseId);
            execIds.add(card.executionId);
        }
        Map<Id, Integer> totalByCase = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Case__c caseId, COUNT(Id) total
            FROM Test_Step__c
            WHERE Test_Case__c IN :caseIds AND Is_Explore__c = false
            GROUP BY Test_Case__c
        ]) {
            totalByCase.put((Id) ar.get('caseId'), (Integer) ar.get('total'));
        }
        // Broken down by step verdict so the queue can say "1 failed step"
        // without a third query: answered = the sum across verdicts.
        Map<Id, Integer> answeredByExec = new Map<Id, Integer>();
        Map<Id, Integer> failedByExec = new Map<Id, Integer>();
        Map<Id, Integer> blockedByExec = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Execution__c execId, Result__c verdict, COUNT(Id) answered
            FROM Test_Step_Result__c
            WHERE Test_Execution__c IN :execIds
            AND Result__c != null
            AND Test_Step__c != null
            AND Test_Step__r.Is_Explore__c = false
            GROUP BY Test_Execution__c, Result__c
        ]) {
            Id execId = (Id) ar.get('execId');
            Integer answered = (Integer) ar.get('answered');
            String verdict = (String) ar.get('verdict');
            Integer runningTotal = answeredByExec.containsKey(execId)
                ? answeredByExec.get(execId) : 0;
            answeredByExec.put(execId, runningTotal + answered);
            if (verdict == 'Fail') {
                failedByExec.put(execId, answered);
            } else if (verdict == 'Blocked') {
                blockedByExec.put(execId, answered);
            }
        }
        for (QueueCardDTO card : cards) {
            card.stepsTotal = totalByCase.containsKey(card.caseId)
                ? totalByCase.get(card.caseId) : 0;
            card.stepsAnswered = answeredByExec.containsKey(card.executionId)
                ? answeredByExec.get(card.executionId) : 0;
            card.stepsFailed = failedByExec.containsKey(card.executionId)
                ? failedByExec.get(card.executionId) : 0;
            card.stepsBlocked = blockedByExec.containsKey(card.executionId)
                ? blockedByExec.get(card.executionId) : 0;
        }
    }

    /** Most recently touched first: LastModifiedDate desc, then
     *  Last_Tested_Date__c desc, nulls last. The date tiebreak keeps the
     *  Continue Testing order deterministic when a bulk edit stamps several
     *  rows in the same second (Apex sort is not stable). */
    private class CardRecencyComparator implements Comparator<QueueCardDTO> {
        public Integer compare(QueueCardDTO a, QueueCardDTO b) {
            if (a.lastUpdated != b.lastUpdated) {
                if (a.lastUpdated == null) { return 1; }
                if (b.lastUpdated == null) { return -1; }
                return b.lastUpdated < a.lastUpdated ? -1 : 1;
            }
            if (a.lastTestedDate == b.lastTestedDate) { return 0; }
            if (a.lastTestedDate == null) { return 1; }
            if (b.lastTestedDate == null) { return -1; }
            return b.lastTestedDate < a.lastTestedDate ? -1 : 1;
        }
    }

    private class RecentCardComparator implements Comparator<QueueCardDTO> {
        public Integer compare(QueueCardDTO a, QueueCardDTO b) {
            if (a.lastTestedDate == null && b.lastTestedDate == null) {
                return 0;
            }
            if (a.lastTestedDate == null) {
                return 1;
            }
            if (b.lastTestedDate == null) {
                return -1;
            }
            return b.lastTestedDate < a.lastTestedDate ? -1
                : (b.lastTestedDate > a.lastTestedDate ? 1 : 0);
        }
    }

    private class PoolPriorityComparator implements Comparator<PoolCardDTO> {
        private final Map<String, Integer> order = new Map<String, Integer>{
            'Critical' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
        };
        public Integer compare(PoolCardDTO a, PoolCardDTO b) {
            return rank(a.priority) - rank(b.priority);
        }
        private Integer rank(String priority) {
            return order.containsKey(priority) ? order.get(priority) : 99;
        }
    }

    /** Tester releases their own claim; a reason is required (design §3.2 —
     *  every release is audited with actor, timestamp, and reason). */
    @AuraEnabled
    public static void releaseClaim(String inputJson) {
        assertTester();
        ReleaseInput input;
        try {
            input = (ReleaseInput) JSON.deserialize(inputJson, ReleaseInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the release — refresh and try again.');
        }
        if (input == null || input.executionId == null) {
            throw auraError('Could not read the release — refresh and try again.');
        }
        if (String.isBlank(input.reason)) {
            throw auraError('Give a short reason for releasing — it goes in the assignment log.');
        }
        Id me = UserInfo.getUserId();
        List<Test_Execution__c> mine = [
            SELECT Id FROM Test_Execution__c
            WHERE Id = :input.executionId AND Assigned_Tester__c = :me AND Released__c = false
        ];
        if (mine.isEmpty()) {
            throw auraError('That run isn\'t yours to release — refresh your queue.');
        }
        try {
            UatExecutionService.releaseSeat(input.executionId, me, input.reason, UatConstants.EVENT_RELEASED);
        } catch (UatExecutionService.UatExecutionException e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Runner ---------------------------------------------------------------

    @AuraEnabled
    public static RunnerDTO claimAndStart(Id executionId) {
        assertTester();
        Test_Execution__c e;
        try {
            e = [
                SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c
                FROM Test_Execution__c WHERE Id = :executionId
            ];
        } catch (QueryException qe) {
            throw auraError('That test no longer exists — refresh your queue.');
        }
        try {
            if (e.Test_Cycle__c != null && e.Assigned_Tester__c == null) {
                // Pool seat: capacity-aware claim. The returned record may be
                // a different row than the slot clicked (race → retry, or a
                // resumed released run) — always open THAT one.
                assertCycleAudience(e.Test_Cycle__c);
                Test_Execution__c claimed = UatExecutionService.claimSeat(
                    e.Test_Cycle__c, e.Test_Case__c, UserInfo.getUserId());
                return startExecution(claimed.Id);
            }
            UatExecutionService.claim(executionId, UserInfo.getUserId());
        } catch (UatExecutionService.UatExecutionException ex) {
            throw auraError(ex.getMessage());
        }
        return startExecution(executionId);
    }

    @AuraEnabled
    public static RunnerDTO startExecution(Id executionId) {
        assertTester();
        Test_Execution__c e = loadVisibleExecution(executionId);

        List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(executionId);
        Map<Id, Test_Step_Result__c> resultByStep = new Map<Id, Test_Step_Result__c>();
        Set<Id> resultIds = new Set<Id>();
        for (Test_Step_Result__c r : results) {
            if (r.Test_Step__c != null) {
                resultByStep.put(r.Test_Step__c, r);
                resultIds.add(r.Id);
            }
        }
        // Per-step evidence counts drive the step navigator's markers and the
        // submit review's "Fail/Blocked with no detail" nudge.
        Map<Id, List<UatFileService.FileDTO>> filesByResult = UatFileService.getFilesFor(resultIds);

        return buildRunnerDto(e, resultByStep, filesByResult);
    }

    /**
     * Read-only twin of startExecution: the case as the tester would run it,
     * for a seat they have NOT claimed (Open Pool preview).
     *
     * The distinction that matters is the omission — no
     * UatExecutionService.ensureStepResults call, so previewing never writes
     * Test_Step_Result__c rows against a seat nobody holds. loadVisibleExecution
     * already permits an open seat inside the caller's audience and rejects
     * everything else, so the audience gate is the same one the runner uses.
     * Steps come back verdict-free (no resultId, no result, no evidence count).
     */
    @AuraEnabled
    public static RunnerDTO getCasePreview(Id executionId) {
        assertTester();
        Test_Execution__c e = loadVisibleExecution(executionId);
        return buildRunnerDto(
            e,
            new Map<Id, Test_Step_Result__c>(),
            new Map<Id, List<UatFileService.FileDTO>>()
        );
    }

    /**
     * The execution + its case's steps and reference material as one DTO. Split
     * out of startExecution so getCasePreview can reuse it with empty maps —
     * the shape the LWCs render is then identical by construction, and a step
     * with no result row simply carries nulls.
     */
    private static RunnerDTO buildRunnerDto(
        Test_Execution__c e,
        Map<Id, Test_Step_Result__c> resultByStep,
        Map<Id, List<UatFileService.FileDTO>> filesByResult
    ) {
        RunnerDTO dto = new RunnerDTO();
        dto.executionId = e.Id;
        dto.caseId = e.Test_Case__c;
        dto.caseCode = e.Test_Case__r.Case_ID__c;
        dto.caseTitle = e.Test_Case__r.Title__c;
        dto.description = e.Test_Case__r.Description__c;
        dto.preConditions = e.Test_Case__r.Pre_Conditions__c;
        dto.version = e.Test_Case__r.Version__c;
        dto.moduleName = e.Test_Case__r.Module__r.Name;
        dto.pathLabel = e.Test_Case__r.Module__r.Module_Group__r.System__r.Name
            + ' › ' + e.Test_Case__r.Module__r.Module_Group__r.Name
            + ' · ' + e.Test_Case__r.Case_ID__c
            + (e.Test_Cycle__c != null ? ' · ' + e.Test_Cycle__r.Name : ' · Standalone');
        dto.cycleId = e.Test_Cycle__c;
        dto.cycleName = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : null;
        dto.targetDate = e.Test_Cycle__r != null ? e.Test_Cycle__r.Target_Date__c : null;
        dto.claimedDate = e.Claimed_Date__c;
        dto.status = e.Testing_Status__c;
        dto.result = e.Testing_Result__c;
        dto.uxRating = e.UX_Rating__c;
        dto.uxRecommendation = e.UX_Recommendation__c;

        for (Test_Step__c s : [
            SELECT Id, Step_Number__c, Step_Title__c, Test_Condition__c, Step_Description__c,
                Expected_Result__c, Is_Explore__c, Explore_Prompt__c
            FROM Test_Step__c
            WHERE Test_Case__c = :e.Test_Case__c
            ORDER BY Step_Number__c
        ]) {
            RunnerStepDTO step = new RunnerStepDTO();
            step.stepId = s.Id;
            step.stepNumber = s.Step_Number__c;
            step.stepTitle = s.Step_Title__c;
            step.condition = s.Test_Condition__c;
            step.description = s.Step_Description__c;
            step.expected = s.Expected_Result__c;
            step.isExplore = s.Is_Explore__c;
            step.explorePrompt = s.Explore_Prompt__c;
            Test_Step_Result__c r = resultByStep.get(s.Id);
            step.evidenceCount = 0;
            if (r != null) {
                step.resultId = r.Id;
                step.actualResult = r.Actual_Result__c;
                step.result = r.Result__c;
                step.exploreNotes = r.Explore_Notes__c;
                step.defectSeverity = r.Defect_Severity__c;
                step.defectSummary = r.Defect_Summary__c;
                List<UatFileService.FileDTO> stepFiles = filesByResult.get(r.Id);
                step.evidenceCount = stepFiles != null ? stepFiles.size() : 0;
            }
            dto.steps.add(step);
        }

        List<Reference_Material__c> refs = [
            SELECT Id, Type__c, Label__c, URL__c FROM Reference_Material__c
            WHERE Test_Case__c = :e.Test_Case__c ORDER BY CreatedDate
        ];
        Map<Id, List<UatFileService.FileDTO>> filesByRef =
            UatFileService.getFilesFor(new Map<Id, Reference_Material__c>(refs).keySet());
        for (Reference_Material__c ref : refs) {
            RunnerRefDTO r = new RunnerRefDTO();
            r.type = ref.Type__c;
            r.label = ref.Label__c;
            r.url = ref.URL__c;
            List<UatFileService.FileDTO> files = filesByRef.get(ref.Id);
            r.file = files != null && !files.isEmpty() ? files[0] : null;
            dto.referenceMaterials.add(r);
        }
        return dto;
    }

    /**
     * The other half of the 2026-08-06 unification: a defect reported against a
     * scripted step becomes a real Finding (Source__c = 'Test case'), so
     * scripted and ad-hoc defects triage in one list instead of one living as
     * two inert fields on the step result.
     *
     * Upsert, not insert: the runner re-saves a step on every keystroke pause,
     * and each save must not mint another finding. Clearing the severity in the
     * runner deletes the finding — the tester decided it was not a defect.
     *
     * Deliberately NOT routed through saveFinding: that path enforces the
     * title/evidence rules a tester answers in the finding form, and blocking a
     * step save behind them would strand someone mid-run. The runner's defect
     * toggle captures what it can; the gaps surface in triage.
     */
    private static void upsertStepDefectFinding(
        Test_Step_Result__c row, Test_Execution__c execution, StepResultInput input
    ) {
        List<Exploratory_Finding__c> existing = [
            SELECT Id FROM Exploratory_Finding__c WHERE Test_Step_Result__c = :row.Id
        ];
        if (String.isBlank(input.defectSeverity)) {
            if (!existing.isEmpty()) {
                delete existing;
            }
            return;
        }
        String summary = String.isBlank(input.defectSummary)
            ? input.actualResult : input.defectSummary;
        String title = firstLineOf(summary);
        if (String.isBlank(title)) {
            // No summary yet — name it after the step so the row is still
            // identifiable in a triage list.
            title = 'Defect on step: ' + firstLineOf(row.Test_Step__r.Step_Description__c);
        }
        Exploratory_Finding__c finding = new Exploratory_Finding__c(
            Id = existing.isEmpty() ? null : existing[0].Id,
            Title__c = title.length() > 255 ? title.substring(0, 255) : title,
            Type__c = FINDING_TYPE_DEFECT,
            Source__c = FINDING_SOURCE_CASE,
            Severity__c = input.defectSeverity,
            What_Testing__c = row.Test_Step__r.Step_Description__c,
            What_Expected__c = row.Test_Step__r.Expected_Result__c,
            What_Happened__c = summary,
            Test_Step_Result__c = row.Id,
            Test_Execution__c = execution.Id,
            Test_Cycle__c = execution.Test_Cycle__c,
            Tester__c = UserInfo.getUserId(),
            Date__c = Date.today()
        );
        upsert finding;
    }

    private static String firstLineOf(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (String line : value.split('\n')) {
            if (String.isNotBlank(line)) {
                return line.trim();
            }
        }
        return null;
    }

    @AuraEnabled
    public static ExecutionSummaryDTO saveStepResult(String inputJson) {
        assertTester();
        StepResultInput input;
        try {
            input = (StepResultInput) JSON.deserialize(inputJson, StepResultInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the step — refresh and try again.');
        }
        if (input == null || input.resultId == null) {
            throw auraError('Could not read the step — refresh and try again.');
        }
        Test_Step_Result__c row = [
            SELECT Id, Test_Execution__c, Test_Step__c, Test_Step__r.Step_Description__c,
                Test_Step__r.Expected_Result__c
            FROM Test_Step_Result__c WHERE Id = :input.resultId
        ];
        Test_Execution__c execution = loadVisibleExecution(row.Test_Execution__c); // visibility gate
        upsertStepDefectFinding(row, execution, input);
        update new Test_Step_Result__c(
            Id = input.resultId,
            Actual_Result__c = input.actualResult,
            Result__c = String.isBlank(input.result) ? null : input.result,
            Explore_Notes__c = input.exploreNotes,
            // DEPRECATED writes, kept so a code revert restores the old
            // behaviour without a data migration. The Finding created above is
            // the record that is actually read.
            Defect_Severity__c = String.isBlank(input.defectSeverity) ? null : input.defectSeverity,
            Defect_Summary__c = input.defectSummary
        );
        return summarize(row.Test_Execution__c);
    }

    @AuraEnabled
    public static void saveFeedback(String inputJson) {
        assertTester();
        FeedbackInput input;
        try {
            input = (FeedbackInput) JSON.deserialize(inputJson, FeedbackInput.class);
        } catch (Exception e) {
            throw auraError('Could not save your feedback — refresh and try again.');
        }
        loadVisibleExecution(input.executionId);
        update new Test_Execution__c(
            Id = input.executionId,
            UX_Rating__c = input.uxRating,
            UX_Recommendation__c = input.uxRecommendation
        );
    }

    /** Save & exit floors the status at In Progress (spec). */
    @AuraEnabled
    public static void saveAndExit(Id executionId) {
        assertTester();
        Test_Execution__c e = loadVisibleExecution(executionId);
        if (e.Testing_Status__c == 'Not Started') {
            update new Test_Execution__c(Id = executionId, Testing_Status__c = 'In Progress');
        }
    }

    @AuraEnabled
    public static ExecutionSummaryDTO submitExecution(Id executionId) {
        assertTester();
        loadVisibleExecution(executionId);
        UatExecutionService.recomputeRollups(new Set<Id>{ executionId });
        update new Test_Execution__c(Id = executionId, Last_Tested_Date__c = Date.today());
        return summarize(executionId);
    }

    // ---- Files -----------------------------------------------------------------

    @AuraEnabled
    public static List<UatFileService.FileDTO> getFiles(Id recordId) {
        assertTester();
        return UatFileService.getFilesFor(recordId);
    }

    @AuraEnabled
    public static void registerUploads(Id recordId, List<String> contentDocumentIds) {
        assertTester();
        List<Id> docIds = new List<Id>();
        for (String s : contentDocumentIds) {
            docIds.add((Id) s);
        }
        UatFileService.normalizeVisibility(recordId, docIds);
    }

    @AuraEnabled
    public static void deleteFile(Id contentDocumentId, Id recordId) {
        assertTester();
        try {
            UatFileService.deleteFile(contentDocumentId, recordId);
        } catch (UatFileService.UatFileException e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Claim evidence staged on a finding's session onto the finding itself
     * (the before-first-save upload flow). The staging parent is derived
     * server-side from the finding's session link — the client never names
     * it, so files can only ever move session → its own finding.
     *
     * Gate is assertSessionAudience, NOT assertCycleAudience: a standalone
     * session has no cycle, and assertCycleAudience(null) throws 'Missing
     * cycle'. That made every claim fail on a standalone session — the client
     * swallows the error into a toast, so the finding saved with its evidence
     * stranded on the session and the finish gate then blocked a tester who
     * could see the screenshots right there in the session log (reported
     * 2026-08-14). saveFinding and deleteFinding already guarded this; these
     * two staging endpoints were the ones that missed it.
     */
    @AuraEnabled
    public static void claimStagedFiles(Id findingId, List<String> contentDocumentIds) {
        assertTester();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw auraError('Nothing to attach — refresh and try again.');
        }
        Exploratory_Finding__c f = loadFinding(findingId);
        UatAudienceService.assertSessionAudience(f.Test_Cycle__c, f.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(f.Tester__c, 'finding');
        if (f.Exploratory_Session__c == null) {
            throw auraError('This finding has no session to stage evidence from.');
        }
        try {
            UatFileService.relinkFiles(f.Exploratory_Session__c, f.Id, toIdList(contentDocumentIds));
        } catch (UatFileService.UatFileException e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Discard evidence staged on a session (the finding form was cancelled).
     * The load-bearing invariant is on the documents: only their uploader can
     * discard them (enforced in the service). The audience check is
     * assertSessionAudience for the same reason as claimStagedFiles — a
     * standalone session has no cycle, and asserting the cycle threw 'Missing
     * cycle', which is how cancelled finding forms left orphaned uploads
     * behind on standalone sessions. Cycled sessions are gated exactly as
     * before; standalone ones now resolve to owner-or-admin.
     */
    @AuraEnabled
    public static void discardStagedFiles(Id sessionId, List<String> contentDocumentIds) {
        assertTester();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Exploratory_Session__c s = loadSession(sessionId);
        UatAudienceService.assertSessionAudience(s.Test_Cycle__c, s.Tester__c);
        try {
            UatFileService.deleteFiles(s.Id, toIdList(contentDocumentIds));
        } catch (UatFileService.UatFileException e) {
            throw auraError(e.getMessage());
        }
    }

    private static List<Id> toIdList(List<String> values) {
        List<Id> ids = new List<Id>();
        for (String s : values) {
            ids.add((Id) s);
        }
        return ids;
    }

    // ---- Exploratory findings (team-visible log, audience-scoped — design §8;
    //      edit/delete = author-or-admin since the 2026-08 session build) ---------

    @AuraEnabled
    public static List<FindingDTO> getFindings(Id cycleId) {
        assertTester();
        assertCycleAudience(cycleId);
        List<Exploratory_Finding__c> findings = [
            SELECT Id, Name, Title__c, Type__c, Source__c,
                What_Testing__c, What_Expected__c, What_Happened__c,
                Severity__c, Workflow_Status__c, External_Ref__c,
                No_Evidence_Reason__c,
                Source_Note__c, Source_Note__r.Logged_At__c,
                Test_Execution__c, Test_Execution__r.Test_Case__r.Title__c,
                Tester__c, Tester__r.Name, Date__c,
                Exploratory_Session__c, Exploratory_Session__r.Name,
                Exploratory_Session__r.Title__c
            FROM Exploratory_Finding__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY CreatedDate DESC
        ];
        Map<Id, List<UatFileService.FileDTO>> filesByFinding =
            UatFileService.getFilesFor(new Map<Id, Exploratory_Finding__c>(findings).keySet());
        return toFindingDTOs(findings, filesByFinding);
    }

    // ---- Finding rules (2026-08-06 rework) ---------------------------------------
    //
    // These live in Apex, not in validation rules, for two reasons: they are
    // conditional (severity matters only for a Defect), and the evidence gate
    // has to see documents that are still STAGED at save time — the claim onto
    // the finding happens after this method returns, so a formula would reject
    // every new finding that has a screenshot attached in the same breath.

    public static final String FINDING_TYPE_DEFECT = 'Defect';
    public static final String FINDING_SOURCE_SESSION = 'Session';
    public static final String FINDING_SOURCE_CASE = 'Test case';
    private static final Set<String> FINDING_TYPES = new Set<String>{
        FINDING_TYPE_DEFECT, 'Works as expected', 'Suggestion', 'Question'
    };
    /** Severities serious enough that "no evidence" has to be a stated choice. */
    private static final Set<String> EVIDENCE_REQUIRED = new Set<String>{ 'High', 'Critical' };
    private static final Integer TITLE_MIN = 10;

    /**
     * Everything a finding must have before it is allowed to exist. A finding
     * nobody can read is worse than no finding: the org still carries one
     * titled "T" at Critical severity, which is what these rules prevent.
     */
    private static void assertFindingIsUsable(FindingInput input) {
        if (String.isBlank(input.title) || input.title.trim().length() < TITLE_MIN) {
            throw auraError('Give the finding a title of at least '
                + TITLE_MIN + ' characters — it is what someone triaging sees first.');
        }
        if (String.isBlank(input.whatHappened)) {
            throw auraError('Describe what happened — that field is required.');
        }
        if (String.isBlank(input.type) || !FINDING_TYPES.contains(input.type)) {
            throw auraError('Pick what kind of finding this is.');
        }
        if (input.type != FINDING_TYPE_DEFECT) {
            return; // severity and evidence are defect concerns only
        }
        if (String.isBlank(input.severity)) {
            throw auraError('A defect needs a severity.');
        }
        if (!EVIDENCE_REQUIRED.contains(input.severity)) {
            return;
        }
        if (String.isNotBlank(input.noEvidenceReason)) {
            return; // "no evidence" made deliberate and readable
        }
        if (input.stagedDocumentIds != null && !input.stagedDocumentIds.isEmpty()) {
            return; // attached in this same save, not yet claimed
        }
        if (input.id != null && hasEvidence(input.id)) {
            return;
        }
        // Promote-to-finding: the entry's evidence is copied onto the finding
        // AFTER the insert, so counting the finding's own links here would
        // reject a promotion whose screenshot is sitting on the note already.
        if (input.sourceNoteId != null && hasEvidence(input.sourceNoteId)) {
            return;
        }
        throw auraError('A ' + input.severity.toLowerCase()
            + ' defect needs a screenshot or file — or say why there isn\'t one.');
    }

    private static Boolean hasEvidence(Id recordId) {
        return [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ] > 0;
    }

    /** Row → DTO mapping shared with UatSessionController (its workspace
     *  serves the same shape filtered to one session). Rows must be selected
     *  with getFindings' field list. */
    public static List<FindingDTO> toFindingDTOs(
        List<Exploratory_Finding__c> findings,
        Map<Id, List<UatFileService.FileDTO>> filesByFinding
    ) {
        List<FindingDTO> result = new List<FindingDTO>();
        for (Exploratory_Finding__c f : findings) {
            FindingDTO dto = new FindingDTO();
            dto.id = f.Id;
            dto.name = f.Name;
            dto.title = f.Title__c;
            dto.type = f.Type__c;
            dto.source = f.Source__c;
            dto.whatTesting = f.What_Testing__c;
            dto.whatExpected = f.What_Expected__c;
            dto.whatHappened = f.What_Happened__c;
            // Severity is meaningful only on a Defect; saveFinding force-clears
            // it for every other type, so this needs no defensive filtering.
            dto.severity = f.Severity__c;
            dto.workflowStatus = f.Workflow_Status__c;
            dto.externalRef = f.External_Ref__c;
            dto.noEvidenceReason = f.No_Evidence_Reason__c;
            dto.sessionId = f.Exploratory_Session__c;
            dto.sessionName = f.Exploratory_Session__r != null
                ? f.Exploratory_Session__r.Name : null;
            dto.sessionTitle = f.Exploratory_Session__r != null
                ? f.Exploratory_Session__r.Title__c : null;
            dto.sourceNoteId = f.Source_Note__c;
            dto.sourceLoggedAt = f.Source_Note__r != null
                ? f.Source_Note__r.Logged_At__c : null;
            dto.executionId = f.Test_Execution__c;
            dto.caseTitle = f.Test_Execution__r != null
                && f.Test_Execution__r.Test_Case__r != null
                ? f.Test_Execution__r.Test_Case__r.Title__c : null;
            dto.testerId = f.Tester__c;
            dto.testerName = f.Tester__r != null ? f.Tester__r.Name : null;
            dto.dateLogged = f.Date__c;
            if (filesByFinding.containsKey(f.Id)) {
                dto.files = filesByFinding.get(f.Id);
            }
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static Id saveFinding(String inputJson) {
        assertTester();
        FindingInput input;
        try {
            input = (FindingInput) JSON.deserialize(inputJson, FindingInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the finding — refresh and try again.');
        }
        if (input == null) {
            throw auraError('Could not read the finding — refresh and try again.');
        }
        assertFindingIsUsable(input);
        // Severity describes a defect; it is meaningless on the other three
        // types, so it is CLEARED rather than trusted from the client — that
        // pairing ("Pass, Critical") is exactly what this rework removes.
        Boolean isDefect = input.type == FINDING_TYPE_DEFECT;
        Exploratory_Finding__c record = new Exploratory_Finding__c(
            Id = input.id,
            Title__c = input.title.trim(),
            Type__c = input.type,
            What_Testing__c = input.whatTesting,
            What_Expected__c = input.whatExpected,
            What_Happened__c = input.whatHappened,
            Severity__c = isDefect && String.isNotBlank(input.severity) ? input.severity : null,
            No_Evidence_Reason__c = isDefect ? input.noEvidenceReason : null
        );
        if (input.id == null) {
            if (input.sessionId != null) {
                // Session findings: only into MY still-Active session; the
                // cycle derives from the session (a client cycleId is
                // ignored — one source of truth). Null cycle = standalone
                // session, no audience to assert beyond the owner check above.
                Exploratory_Session__c session = loadSession(input.sessionId);
                if (session.Tester__c != UserInfo.getUserId()) {
                    throw auraError('You can only add findings to your own session.');
                }
                if (session.Status__c != UatConstants.SESSION_ACTIVE) {
                    throw auraError('This session is finished — findings are read-only.');
                }
                if (session.Test_Cycle__c != null) {
                    assertCycleAudience(session.Test_Cycle__c);
                }
                record.Test_Cycle__c = session.Test_Cycle__c;
                record.Exploratory_Session__c = session.Id;
                // Promote-to-finding: the entry must belong to the session
                // being written into, or the origin trail would be a lie.
                if (input.sourceNoteId != null) {
                    List<Session_Note__c> notes = [
                        SELECT Id FROM Session_Note__c
                        WHERE Id = :input.sourceNoteId
                        AND Exploratory_Session__c = :session.Id
                    ];
                    if (notes.isEmpty()) {
                        throw auraError('That note is not part of this session — refresh and try again.');
                    }
                    record.Source_Note__c = input.sourceNoteId;
                }
            } else {
                if (input.cycleId == null) {
                    throw auraError('Missing cycle — refresh and try again.');
                }
                assertCycleAudience(input.cycleId);
                record.Test_Cycle__c = input.cycleId;
            }
            record.Tester__c = UserInfo.getUserId();
            record.Date__c = Date.today();
            // Stamped server-side, never chosen by a tester: this is the only
            // thing distinguishing the two flows now that they share the
            // object, so it has to be derived from how the record was created.
            record.Source__c = FINDING_SOURCE_SESSION;
            insert record;
            if (record.Source_Note__c != null) {
                // Promoted: the entry's screenshots become the finding's
                // evidence, and the entry keeps them too — the timeline is the
                // tester's record of what they saw, and stripping it would
                // rewrite history.
                UatFileService.copyLinks(record.Source_Note__c, record.Id);
            }
        } else {
            // Author-or-admin; the session link is immutable on update (the
            // input's sessionId is ignored — no reparenting). Null cycle =
            // standalone-session finding; owner-or-admin is the whole gate.
            Exploratory_Finding__c existing = loadFinding(input.id);
            if (existing.Test_Cycle__c != null) {
                assertCycleAudience(existing.Test_Cycle__c);
            }
            UatAudienceService.assertOwnerOrAdmin(existing.Tester__c, 'finding');
            update record;
        }
        return record.Id;
    }

    @AuraEnabled
    public static void deleteFinding(Id findingId) {
        assertTester();
        Exploratory_Finding__c existing = loadFinding(findingId);
        if (existing.Test_Cycle__c != null) {
            assertCycleAudience(existing.Test_Cycle__c);
        }
        // Author-or-admin (supersedes the 2026-07-23 any-member rule).
        // Deleting the record drops its ContentDocumentLinks; the underlying
        // documents stay in their uploaders' Files (deleting another owner's
        // document throws) — which peers can no longer trigger.
        UatAudienceService.assertOwnerOrAdmin(existing.Tester__c, 'finding');
        delete new Exploratory_Finding__c(Id = findingId);
    }

    // ---- Internals -------------------------------------------------------------

    private static Test_Execution__c loadVisibleExecution(Id executionId) {
        Test_Execution__c e;
        try {
            e = [
                SELECT Id, Test_Case__c, Test_Case__r.Case_ID__c,
                    Test_Case__r.Title__c, Test_Case__r.Pre_Conditions__c,
                    Test_Case__r.Description__c, Test_Case__r.Version__c,
                    Test_Case__r.Module__r.Name,
                    Test_Case__r.Module__r.Module_Group__r.Name,
                    Test_Case__r.Module__r.Module_Group__r.System__r.Name,
                    Test_Cycle__c, Test_Cycle__r.Name, Test_Cycle__r.Target_Date__c,
                    Assigned_Team__c, Assigned_Tester__c, Released__c, Claimed_Date__c,
                    Testing_Status__c, Testing_Result__c,
                    UX_Rating__c, UX_Recommendation__c
                FROM Test_Execution__c WHERE Id = :executionId
            ];
        } catch (QueryException ex) {
            throw auraError('That test no longer exists — refresh your queue.');
        }
        Id me = UserInfo.getUserId();
        if (e.Assigned_Tester__c == me) {
            if (e.Released__c) {
                throw auraError('You released this run — claim it again from the pool to resume.');
            }
            return e;
        }
        if (e.Assigned_Tester__c == null
            && (e.Assigned_Team__c == null || isOnTeam(e.Assigned_Team__c, me))) {
            // Open seat within my audience (team, or the whole pool when the
            // cycle has no team).
            return e;
        }
        throw auraError('This test isn\'t assigned to you — refresh your queue.');
    }

    // ---- Audience (open-pool design §1 — bodies live in UatAudienceService) ------

    private static Set<Id> myTeamIds(Id userId) {
        return UatAudienceService.myTeamIds(userId);
    }

    private static Boolean isOnTeam(Id teamId, Id userId) {
        return UatAudienceService.isOnTeam(teamId, userId);
    }

    private static void assertCycleAudience(Id cycleId) {
        UatAudienceService.assertCycleAudience(cycleId);
    }

    private static Exploratory_Finding__c loadFinding(Id findingId) {
        try {
            return [
                SELECT Id, Test_Cycle__c, Tester__c, Exploratory_Session__c
                FROM Exploratory_Finding__c WHERE Id = :findingId
            ];
        } catch (QueryException ex) {
            throw auraError('That finding no longer exists — refresh and try again.');
        }
    }

    private static Exploratory_Session__c loadSession(Id sessionId) {
        try {
            return [
                SELECT Id, Test_Cycle__c, Tester__c, Status__c
                FROM Exploratory_Session__c WHERE Id = :sessionId
            ];
        } catch (QueryException ex) {
            throw auraError('That session no longer exists — refresh and try again.');
        }
    }

    private static ExecutionSummaryDTO summarize(Id executionId) {
        Test_Execution__c e = [
            SELECT Testing_Status__c, Testing_Result__c
            FROM Test_Execution__c WHERE Id = :executionId
        ];
        ExecutionSummaryDTO dto = new ExecutionSummaryDTO();
        dto.executionId = executionId;
        dto.status = e.Testing_Status__c;
        dto.result = e.Testing_Result__c;
        return dto;
    }

    private static void assertTester() {
        UatAudienceService.assertTester();
    }

    /** Card blurb: the case description trimmed to card length. The full
     *  text stays admin-side; cards never need more than a couple of lines. */
    private static String blurb(String text) {
        return String.isBlank(text) ? null : text.abbreviate(240);
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}