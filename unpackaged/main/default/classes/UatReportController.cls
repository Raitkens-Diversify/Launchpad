/**
 * UatReportController
 *
 * Apex behind the Admin Console's Cycle Report section (adminUatReport): one
 * read-only assembly of everything a cycle produced — runs and their step
 * results, exploratory sessions and their note timelines, findings, the
 * assignment audit trail, evidence, and the rollups an admin signs off against.
 *
 * Read-only except the pair of deliberate triage writes —
 * setFindingWorkflowStatus and setStepWorkflowStatus, the admin disposition
 * (which tracker a failure went to). Everything else stays DML-free, and
 * deliberately no reuse of the capped list methods the
 * console's live sections use: those cap at 50-500 rows to render a screen and
 * say nothing when they cut. This class runs its own queries and tells the
 * caller, per grain, when it hit a limit. Summary rollups describe what is IN
 * this report, not what is in the org; when a grain truncates, its `truncated`
 * flag is the disclosure.
 *
 * Closed cycles are reportable. Every other UAT read filters Status__c !=
 * 'Closed'; a closed cycle is the primary thing you report on.
 *
 * Two things `with sharing` does NOT do here, both worth knowing before
 * trusting a number:
 *  - It hides no records. Every root this reads is OWD Read or Public
 *    Read/Write and every child is ControlledByParent beneath one, and the org
 *    has no sharing rules (docs/uat-architecture.md). Record scoping comes from
 *    the query predicates and assertReport(), not from sharing.
 *  - It does not govern files. ContentDocumentLink visibility is its own
 *    mechanism, so a file uploaded by a path that skipped
 *    UatFileService.normalizeVisibility stays owner-only and is invisible here.
 *    evidenceCount can therefore under-report, and a finding can be
 *    data-quality-flagged despite having a screenshot.
 *
 * Scale: safe to roughly 1,500 rows in one report and hard-stopped by the
 * budgets below. Past that the answer is not a bigger limit — it is a paged
 * endpoint or an async batch writing a CSV ContentVersion. Neither is built.
 *
 * Conventions: with sharing, describe asserts, AuraHandledException.
 */
public with sharing class UatReportController {

    /** Per-grain ceiling. The transaction row budget below usually binds first. */
    private static final Integer GRAIN_LIMIT = 10000;
    /** LongTextArea ceiling per field. Five 32k fields on one joined step-result
     *  row is ~0.31 MB, which exhausts a 6 MB heap in 19 rows. 8,000 is well
     *  clear of any real UAT narrative; textTruncated discloses a cut. */
    private static final Integer TEXT_LIMIT = 8000;
    /** ContentDocumentLink bind-collection size. Bounds the IN clause and keeps
     *  each query selective — it does NOT help the row limit, which is
     *  cumulative per transaction. The row budget is what protects that. */
    private static final Integer CDL_CHUNK = 500;
    /** Rows held back from the grains for the two evidence phases. */
    private static final Integer ROW_BUDGET_RESERVE = 5000;
    /** 0.6, not 0.9: the framework's JSON serialization of the response
     *  allocates roughly the size of the response after we stop measuring. */
    private static final Decimal HEAP_CEILING = 0.6;

    private static final String STEP_DELETED_LABEL = '(step deleted)';
    private static final String SCOPE_CYCLE = 'Cycle';
    private static final String SCOPE_STANDALONE = 'Standalone';

    private static final String REASON_GRAIN = 'Grain row limit reached — narrow the report scope.';
    private static final String REASON_ROWS = 'Transaction row budget reached — narrow the report scope.';
    private static final String REASON_HEAP = 'Heap budget reached — narrow the report scope.';
    private static final String REASON_PARENT_EXEC = 'Parent executions were truncated.';
    private static final String REASON_PARENT_SESSION = 'Parent sessions were truncated.';
    private static final String REASON_SCOPE_SKIPPED =
        'Row budget reached before the cycle scope was read — cases with no run may be missing.';

    /** Case verdicts. Their own vocabulary, not Testing_Result__c's: a case is
     *  not a seat, and 'Not started' / 'In progress' have no result equivalent. */
    private static final String VERDICT_NOT_STARTED = 'Not started';
    private static final String VERDICT_IN_PROGRESS = 'In progress';
    private static final String VERDICT_PASSED = 'Passed';
    private static final String VERDICT_FAILED = 'Failed';
    private static final String VERDICT_BLOCKED = 'Blocked';
    private static final String VERDICT_POSTPONED = 'Postponed';
    /** Rows the scope resolver needs before it is worth starting. Its three
     *  queries are uncapped (it is the shared console resolver, not ours to
     *  limit), so we decline rather than risk the transaction on it. */
    private static final Integer SCOPE_BUDGET_MIN = 3000;

    private static final String TYPE_DEFECT = 'Defect';
    private static final String SOURCE_SESSION = 'Session';
    private static final String SOURCE_TEST_CASE = 'Test case';
    /** Workflow_Status__c values, raw literals per the picklist convention
     *  above. Order mirrors the field XML; client mirror is
     *  lwc/uatConstants WORKFLOW_STATUSES — change all three together. */
    private static final String STATUS_NEW = 'New';
    private static final Set<String> WORKFLOW_STATUS_VALUES = new Set<String>{
        'New', 'Added to Jira', 'Added to ClickUp', 'Not verified', 'Resolved'
    };
    private static final Set<String> EVIDENCE_REQUIRED_SEVERITIES = new Set<String>{ 'High', 'Critical' };
    private static final String FLAG_EVIDENCE_MISSING = 'EVIDENCE_MISSING';

    /** Test seam: the truncation branch needs 10,001 rows to fire naturally,
     *  which no test can build — the uatConsoleOverride pattern, numeric. */
    @TestVisible private static Integer grainLimitOverride;

    // ---- DTOs ----------------------------------------------------------------

    public class CycleReportDTO {
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public Id generatedById;
        @AuraEnabled public String generatedByName;
        @AuraEnabled public String scope;                  // 'Cycle' | 'Standalone'
        @AuraEnabled public CycleHeaderDTO cycle;          // null = standalone report
        @AuraEnabled public SummaryDTO summary = new SummaryDTO();
        /** The report's organising grain. Empty for a standalone report — that
         *  work has no cycle and therefore no scope. */
        @AuraEnabled public CaseGrainDTO cases = new CaseGrainDTO();
        @AuraEnabled public ExecutionGrainDTO executions = new ExecutionGrainDTO();
        @AuraEnabled public SessionGrainDTO sessions = new SessionGrainDTO();
        @AuraEnabled public FindingGrainDTO findings = new FindingGrainDTO();
        @AuraEnabled public EventGrainDTO events = new EventGrainDTO();
    }

    public class CycleHeaderDTO {
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String status;
        @AuraEnabled public Id teamId;
        @AuraEnabled public String teamName;               // null = open to the whole pool
        @AuraEnabled public Date targetDate;
        @AuraEnabled public Integer daysToTarget;          // negative = past due; null = no date
        @AuraEnabled public Integer maxTesters;
        @AuraEnabled public Integer claimLimitPerTester;   // null = unlimited
        @AuraEnabled public Integer staleClaimDays;        // null = never auto-release
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class CountRowDTO {
        @AuraEnabled public String label;                  // null = unset on the record
        @AuraEnabled public Integer count = 0;
    }

    public class TypeSeverityCountDTO {
        @AuraEnabled public String findingType;
        @AuraEnabled public String severity;               // null = not a Defect
        @AuraEnabled public Integer count = 0;
    }

    public class TesterActivityDTO {
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;             // null = the User lookup was SetNull'd
        @AuraEnabled public Integer runsAssigned = 0;
        @AuraEnabled public Integer runsReleased = 0;
        @AuraEnabled public Integer runsComplete = 0;
        @AuraEnabled public Integer runsFailed = 0;
        @AuraEnabled public Integer stepsAnswered = 0;
        @AuraEnabled public Integer sessionsStarted = 0;
        @AuraEnabled public Integer notesLogged = 0;
        @AuraEnabled public Integer findingsLogged = 0;
        @AuraEnabled public Integer defectsLogged = 0;
        @AuraEnabled public Datetime lastActivity;         // null = no timestamped activity
    }

    public class DataQualityFlagDTO {
        @AuraEnabled public String code;
        @AuraEnabled public Id findingId;
        @AuraEnabled public String findingName;
        @AuraEnabled public String title;
        @AuraEnabled public String findingType;
        @AuraEnabled public String severity;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;            // null = not from a session
        @AuraEnabled public Id executionId;
        @AuraEnabled public String caseCode;               // null = not from a run
        /** A field, not a constant, so the rule set can grow without a DTO change. */
        @AuraEnabled public String reason;
    }

    public class SummaryDTO {
        @AuraEnabled public Integer executionCount = 0;
        @AuraEnabled public Integer stepResultCount = 0;
        @AuraEnabled public Integer sessionCount = 0;
        @AuraEnabled public Integer noteCount = 0;
        @AuraEnabled public Integer findingCount = 0;
        @AuraEnabled public Integer eventCount = 0;

        @AuraEnabled public Integer activeRuns = 0;        // claimed, not released
        @AuraEnabled public Integer releasedRuns = 0;      // history rows
        @AuraEnabled public Integer unclaimedSlots = 0;

        // Raw literals: UatConstants deliberately does not carry these
        // picklists (UatCoverageController is the precedent).
        @AuraEnabled public Integer statusNotStarted = 0;
        @AuraEnabled public Integer statusInProgress = 0;
        @AuraEnabled public Integer statusComplete = 0;
        @AuraEnabled public Integer statusUnset = 0;

        @AuraEnabled public Integer resultPassed = 0;
        @AuraEnabled public Integer resultFailed = 0;
        @AuraEnabled public Integer resultBlocked = 0;
        @AuraEnabled public Integer resultPostponed = 0;
        @AuraEnabled public Integer resultNone = 0;

        @AuraEnabled public Integer stepsPass = 0;
        @AuraEnabled public Integer stepsFail = 0;
        @AuraEnabled public Integer stepsBlocked = 0;
        @AuraEnabled public Integer stepsNotApplicable = 0;
        @AuraEnabled public Integer stepsUnanswered = 0;
        @AuraEnabled public Integer stepsOrphaned = 0;     // step definition SetNull'd

        @AuraEnabled public Integer uxRatingCount = 0;
        @AuraEnabled public Decimal uxRatingAverage;       // null = nobody rated

        @AuraEnabled public List<CountRowDTO> findingsByType = new List<CountRowDTO>();
        @AuraEnabled public List<CountRowDTO> findingsBySeverity = new List<CountRowDTO>();
        @AuraEnabled public List<TypeSeverityCountDTO> findingsByTypeAndSeverity =
            new List<TypeSeverityCountDTO>();
        /** Triage rollup; null statuses count under 'New' (picklist default). */
        @AuraEnabled public List<CountRowDTO> findingsByStatus = new List<CountRowDTO>();
        /** Defect-type findings still at 'New' — the queue the summary header
         *  surfaces as "not yet triaged". */
        @AuraEnabled public Integer untriagedDefects = 0;
        /** Fail/Blocked steps still at 'New' across live (non-released) runs —
         *  the step-failure half of the same queue. */
        @AuraEnabled public Integer untriagedFailedSteps = 0;
        @AuraEnabled public Integer findingsFromSessions = 0;
        @AuraEnabled public Integer findingsFromTestCases = 0;

        /** Distinct ContentDocuments across the whole report. */
        @AuraEnabled public Integer evidenceDocumentCount = 0;
        /** Sum of per-record counts. Promote-to-finding copies the link, so one
         *  document legitimately counts twice here and once above. Neither is
         *  wrong — they answer different questions. */
        @AuraEnabled public Integer evidenceLinkCount = 0;

        /** Case rollups. A case is not a run: 76 runs over 75 cases is normal
         *  (one case held two seats), so these never equal the run counts. */
        @AuraEnabled public Integer caseCount = 0;
        @AuraEnabled public Integer casesPassed = 0;
        @AuraEnabled public Integer casesFailed = 0;
        @AuraEnabled public Integer casesBlocked = 0;
        @AuraEnabled public Integer casesPostponed = 0;
        @AuraEnabled public Integer casesInProgress = 0;
        @AuraEnabled public Integer casesNotStarted = 0;
        /** Passed + Failed + Blocked + Postponed — every case that reached a
         *  verdict, which is the denominator an admin signs off against. */
        @AuraEnabled public Integer casesComplete = 0;
        /** In scope with no execution row at all. Should be zero: slots are
         *  materialized eagerly by trigger. Nonzero means drift, not backlog. */
        @AuraEnabled public Integer casesWithoutRuns = 0;

        @AuraEnabled public List<TesterActivityDTO> testers = new List<TesterActivityDTO>();
        @AuraEnabled public List<DataQualityFlagDTO> dataQualityFlags = new List<DataQualityFlagDTO>();
    }

    public class CaseGrainDTO {
        @AuraEnabled public List<CaseRowDTO> rows = new List<CaseRowDTO>();
        @AuraEnabled public Integer returned = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String truncationReason;       // null = complete
    }

    /**
     * One test case in the cycle, carrying ORDERED REFERENCES to its runs and
     * findings rather than copies of them. The client joins by Id against the
     * flat grains, which keeps one serialization of every execution on the wire
     * and leaves the existing evidence and summary passes untouched.
     */
    public class CaseRowDTO {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;             // TC-####
        @AuraEnabled public String caseCode;               // Case_ID__c formula
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String caseVersion;
        @AuraEnabled public Decimal caseSequence;
        /** Lowest book sort order; null when the case was added to the cycle
         *  directly rather than through a book. */
        @AuraEnabled public Decimal displayOrder;
        /** Book names and/or 'Added directly'. null = the case is not in scope. */
        @AuraEnabled public String scopeSources;
        /** false = worked in this cycle but no longer in its scope. The run
         *  survives its junction being deleted, so it must still be reported. */
        @AuraEnabled public Boolean inScope = false;
        /** true = in scope with no execution row. A coverage gap. */
        @AuraEnabled public Boolean noRunCreated = false;
        @AuraEnabled public String systemName;
        @AuraEnabled public String moduleGroupName;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String modulePath;
        @AuraEnabled public String priority;
        @AuraEnabled public String estimatedEffort;
        @AuraEnabled public String testingSurface;
        @AuraEnabled public String verdict;
        @AuraEnabled public List<Id> executionIds = new List<Id>();
        @AuraEnabled public Integer executionCount = 0;
        @AuraEnabled public Integer releasedCount = 0;
        /** Live seats only, in run order, blanks dropped. */
        @AuraEnabled public List<String> testerNames = new List<String>();
        @AuraEnabled public Integer stepsTotal = 0;
        @AuraEnabled public Integer stepsAnswered = 0;
        @AuraEnabled public Integer stepsPassed = 0;
        @AuraEnabled public Integer stepsFailed = 0;
        @AuraEnabled public Integer stepsBlocked = 0;
        @AuraEnabled public Integer stepsNotApplicable = 0;
        /** Fail/Blocked steps still at 'New' across LIVE runs — the case
         *  row's triage rollup. Released runs are excluded, same as every
         *  other step counter here. */
        @AuraEnabled public Integer stepsUntriaged = 0;
        /** Runs plus their step results. Deduped per record by the evidence
         *  pass, but a document linked to both a run and its step counts twice
         *  here, exactly as evidenceLinkCount does at report level. */
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public List<Id> findingIds = new List<Id>();
        @AuraEnabled public Integer findingCount = 0;
    }

    public class ExecutionGrainDTO {
        @AuraEnabled public List<ExecutionRowDTO> rows = new List<ExecutionRowDTO>();
        @AuraEnabled public Integer returned = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String truncationReason;       // null = complete
        /** Step results are ONE flat query fanned onto rows[].steps, so their
         *  truncation belongs to that query, not to any single execution. */
        @AuraEnabled public Integer stepsReturned = 0;
        @AuraEnabled public Boolean stepsTruncated = false;
        @AuraEnabled public String stepsTruncationReason;
    }

    public class SessionGrainDTO {
        @AuraEnabled public List<SessionRowDTO> rows = new List<SessionRowDTO>();
        @AuraEnabled public Integer returned = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String truncationReason;
        /** Same shape as steps: one flat Session_Note__c query fanned onto rows[].notes. */
        @AuraEnabled public Integer notesReturned = 0;
        @AuraEnabled public Boolean notesTruncated = false;
        @AuraEnabled public String notesTruncationReason;
    }

    public class FindingGrainDTO {
        @AuraEnabled public List<FindingRowDTO> rows = new List<FindingRowDTO>();
        @AuraEnabled public Integer returned = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String truncationReason;
    }

    public class EventGrainDTO {
        @AuraEnabled public List<EventRowDTO> rows = new List<EventRowDTO>();
        @AuraEnabled public Integer returned = 0;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public String truncationReason;
    }

    public class ExecutionRowDTO {
        @AuraEnabled public Id executionId;
        @AuraEnabled public String name;                   // TE-####
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;             // TC-####
        @AuraEnabled public String caseCode;               // Case_ID__c formula
        @AuraEnabled public String caseTitle;
        @AuraEnabled public String caseVersion;
        @AuraEnabled public Decimal caseSequence;
        @AuraEnabled public String systemName;
        @AuraEnabled public String moduleGroupName;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String modulePath;
        @AuraEnabled public String priority;
        @AuraEnabled public String estimatedEffort;
        @AuraEnabled public String testingSurface;
        @AuraEnabled public String creationStatus;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;              // null = standalone run
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;             // null = unclaimed slot
        @AuraEnabled public Id teamId;
        @AuraEnabled public String teamName;
        @AuraEnabled public String testingStatus;
        @AuraEnabled public String testingResult;          // null = no verdict yet
        /** true = superseded history row. Reported, never filtered out. */
        @AuraEnabled public Boolean released = false;
        @AuraEnabled public Datetime claimedDate;
        @AuraEnabled public Date lastTestedDate;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Decimal uxRating;              // null = no feedback
        @AuraEnabled public String uxRecommendation;
        @AuraEnabled public String identityKey;
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public Integer stepsTotal = 0;
        @AuraEnabled public Integer stepsAnswered = 0;
        @AuraEnabled public Integer stepsPassed = 0;
        @AuraEnabled public Integer stepsFailed = 0;
        @AuraEnabled public Integer stepsBlocked = 0;
        @AuraEnabled public Integer stepsNotApplicable = 0;
        @AuraEnabled public Integer stepsOrphaned = 0;
        /** Fail/Blocked steps on this run still at 'New' (triage rollup). */
        @AuraEnabled public Integer stepsUntriaged = 0;
        @AuraEnabled public Boolean textTruncated = false;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
        @AuraEnabled public List<StepResultRowDTO> steps = new List<StepResultRowDTO>();
    }

    /** Deliberately carries no Defect_Severity__c / Defect_Summary__c: those are
     *  deprecated and migrated: the record of a scripted defect is now a Finding
     *  with Source__c = 'Test case'. Do not add them back. */
    public class StepResultRowDTO {
        @AuraEnabled public Id resultId;
        @AuraEnabled public String name;                   // TSR-####
        @AuraEnabled public Id executionId;
        @AuraEnabled public String executionName;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseTitle;
        @AuraEnabled public Id stepId;                     // null = definition SetNull'd
        @AuraEnabled public Boolean stepDeleted = false;
        @AuraEnabled public Decimal stepNumber;
        @AuraEnabled public String stepCondition;
        @AuraEnabled public String stepDescription;
        @AuraEnabled public String expectedResult;
        @AuraEnabled public String explorePrompt;
        @AuraEnabled public Boolean isExplore = false;
        @AuraEnabled public String result;                 // null = unanswered
        @AuraEnabled public String actualResult;
        @AuraEnabled public String exploreNotes;
        /** Triage disposition for a step failure with no Finding; null reads
         *  as 'New' (picklist default) on the client, same as findings. */
        @AuraEnabled public String workflowStatus;
        @AuraEnabled public String externalRef;            // Jira/ClickUp key or URL
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Boolean textTruncated = false;
    }

    /** `files` is the session's OWN gallery, not the union of its notes' files —
     *  running-notes evidence attaches straight to the session record. */
    public class SessionRowDTO {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String name;                   // ES-####
        @AuraEnabled public String title;
        @AuraEnabled public String areaText;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;              // null = standalone/personal
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime finishedAt;
        @AuraEnabled public Integer durationMinutes;       // null while Active
        @AuraEnabled public Decimal timeboxMinutes;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Integer noteCount = 0;
        @AuraEnabled public Integer findingCount = 0;
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
        @AuraEnabled public List<NoteRowDTO> notes = new List<NoteRowDTO>();
    }

    public class NoteRowDTO {
        @AuraEnabled public Id noteId;
        @AuraEnabled public String name;                   // SN-####
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String sessionTitle;
        @AuraEnabled public String text;
        @AuraEnabled public String tag;                    // null = untagged
        @AuraEnabled public Datetime loggedAt;
        @AuraEnabled public Id authorId;
        @AuraEnabled public String authorName;
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
        /** Set only when the note was logged off-script from inside a run. */
        @AuraEnabled public Id executionId;
        @AuraEnabled public String executionName;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseTitle;
        /** The Finding whose Source_Note__c points here; null = never promoted. */
        @AuraEnabled public Id promotedFindingId;
        @AuraEnabled public String promotedFindingName;
        @AuraEnabled public Boolean textTruncated = false;
    }

    /** Deliberately carries no Result__c: deprecated and replaced by Type__c. */
    public class FindingRowDTO {
        @AuraEnabled public Id findingId;
        @AuraEnabled public String name;                   // EF-####
        @AuraEnabled public String title;
        @AuraEnabled public String findingType;
        @AuraEnabled public String source;                 // 'Session' | 'Test case'
        @AuraEnabled public String severity;               // null unless Defect
        /** Triage disposition. Null on pre-backfill rows; the client treats
         *  null as 'New', matching the picklist default. */
        @AuraEnabled public String workflowStatus;
        @AuraEnabled public String externalRef;            // Jira/ClickUp key or URL
        @AuraEnabled public String whatTesting;
        @AuraEnabled public String whatHappened;
        @AuraEnabled public String whatExpected;
        @AuraEnabled public String noEvidenceReason;
        @AuraEnabled public Date dateLogged;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String sessionTitle;
        @AuraEnabled public Id sourceNoteId;
        @AuraEnabled public String sourceNoteName;
        @AuraEnabled public Datetime sourceNoteLoggedAt;
        @AuraEnabled public Id executionId;
        @AuraEnabled public String executionName;
        @AuraEnabled public Id caseId;                     // null for session findings
        @AuraEnabled public String caseCode;
        @AuraEnabled public String caseTitle;
        @AuraEnabled public Id stepResultId;
        @AuraEnabled public String stepResultName;
        @AuraEnabled public Integer evidenceCount = 0;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
        @AuraEnabled public Boolean flaggedNoEvidence = false;
        @AuraEnabled public Boolean textTruncated = false;
    }

    public class EventRowDTO {
        @AuraEnabled public Id eventId;
        @AuraEnabled public String name;                   // TAE-####
        @AuraEnabled public String action;
        /** CreatedDate IS the event timestamp — the object carries no custom one. */
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String reason;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;             // whose seat changed
        @AuraEnabled public Id actorId;
        @AuraEnabled public String actorName;              // who did it
        @AuraEnabled public Id executionId;
        @AuraEnabled public String executionName;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseCode;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public Boolean textTruncated = false;
    }

    /** Step definition text, read once per case and shared by reference across
     *  every result that answers it. Not a DTO — it never crosses the wire. */
    private class StepDef {
        Decimal stepNumber;
        String stepCondition;
        String stepDescription;
        String expectedResult;
        String explorePrompt;
        Boolean isExplore = false;
        Boolean textTruncated = false;
    }

    // ---- Reads ---------------------------------------------------------------

    @AuraEnabled
    public static CycleReportDTO getCycleReport(Id cycleId) {
        assertReport();
        if (cycleId == null) {
            throw auraError('Missing cycle — refresh and try again.');
        }
        return buildReport(cycleId);
    }

    /**
     * Runs, sessions and findings with no cycle — the standalone surface. It
     * exists so a cycle-scoped export never silently omits real work.
     *
     * Shares every query with getCycleReport: a null Id bind renders as
     * `= null`, which IS the standalone predicate (the idiom in
     * UatSessionController.findOrCreateAdHocSession).
     */
    @AuraEnabled
    public static CycleReportDTO getStandaloneReport() {
        assertReport();
        return buildReport(null);
    }

    // ---- Writes ----------------------------------------------------------------

    /** JSON-string transport: custom-Apex-type @AuraEnabled inputs arrive null
     *  org-wide (docs/uat-architecture.md §4.2). externalRef is tri-state:
     *  absent/null = leave the stored ref alone, '' = clear it, value = set it —
     *  so a status-only change never wipes a ticket key the admin typed earlier. */
    public class StatusInput {
        public Id findingId;
        public String status;
        public String externalRef;
    }

    /**
     * The one write in this class: the admin triage disposition. Same
     * UAT_Console gate as the reads — testers see the status read-only through
     * UatRunController and never reach this. Field-level describes fail loudly
     * BEFORE stripInaccessible because a silent strip here is a "saved" toast
     * over an unchanged row (the assertModuleWritable lesson).
     */
    @AuraEnabled
    public static void setFindingWorkflowStatus(String inputJson) {
        assertReport();
        assertTriageWritable();
        StatusInput input = (StatusInput) parse(inputJson, StatusInput.class);
        if (input.findingId == null) {
            throw auraError('Missing finding — refresh the report and try again.');
        }
        if (!WORKFLOW_STATUS_VALUES.contains(input.status)) {
            throw auraError('Pick a workflow status from the list.');
        }
        List<Exploratory_Finding__c> found = [
            SELECT Id FROM Exploratory_Finding__c WHERE Id = :input.findingId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw auraError('That finding no longer exists — refresh the report.');
        }
        Exploratory_Finding__c record = new Exploratory_Finding__c(
            Id = input.findingId,
            Workflow_Status__c = input.status
        );
        if (input.externalRef != null) {
            String ref = input.externalRef.trim();
            record.External_Ref__c = String.isBlank(ref) ? null : ref;
        }
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, new List<SObject>{ record });
            update decision.getRecords();
        } catch (DmlException e) {
            throw auraError('The status could not be saved: ' + e.getDmlMessage(0));
        }
    }

    /** The write gate on top of assertReport(): both triage fields must be
     *  editable, or the save must refuse rather than half-apply. */
    private static void assertTriageWritable() {
        if (!Schema.sObjectType.Exploratory_Finding__c.isUpdateable()
            || !Schema.sObjectType.Exploratory_Finding__c.fields.Workflow_Status__c.isUpdateable()
            || !Schema.sObjectType.Exploratory_Finding__c.fields.External_Ref__c.isUpdateable()) {
            throw auraError('You don\'t have edit access to finding workflow status — '
                + 'ask an admin for the UAT Admin permission set.');
        }
    }

    public class StepStatusInput {
        public Id resultId;
        public String status;
        public String externalRef;
    }

    /**
     * The step-failure sibling of setFindingWorkflowStatus: triage for a
     * failed/blocked step that produced NO Finding (a tester can fail a step
     * without filing one — those failures need a queue too). When a Finding
     * exists for the step, ITS status is the defect's record; this one does
     * not replace it. Same gate, same tri-state externalRef.
     */
    @AuraEnabled
    public static void setStepWorkflowStatus(String inputJson) {
        assertReport();
        assertStepTriageWritable();
        StepStatusInput input = (StepStatusInput) parse(inputJson, StepStatusInput.class);
        if (input.resultId == null) {
            throw auraError('Missing step result — refresh the report and try again.');
        }
        if (!WORKFLOW_STATUS_VALUES.contains(input.status)) {
            throw auraError('Pick a workflow status from the list.');
        }
        List<Test_Step_Result__c> found = [
            SELECT Id FROM Test_Step_Result__c WHERE Id = :input.resultId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw auraError('That step result no longer exists — refresh the report.');
        }
        Test_Step_Result__c record = new Test_Step_Result__c(
            Id = input.resultId,
            Workflow_Status__c = input.status
        );
        if (input.externalRef != null) {
            String ref = input.externalRef.trim();
            record.External_Ref__c = String.isBlank(ref) ? null : ref;
        }
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, new List<SObject>{ record });
            update decision.getRecords();
        } catch (DmlException e) {
            throw auraError('The status could not be saved: ' + e.getDmlMessage(0));
        }
    }

    private static void assertStepTriageWritable() {
        if (!Schema.sObjectType.Test_Step_Result__c.isUpdateable()
            || !Schema.sObjectType.Test_Step_Result__c.fields.Workflow_Status__c.isUpdateable()
            || !Schema.sObjectType.Test_Step_Result__c.fields.External_Ref__c.isUpdateable()) {
            throw auraError('You don\'t have edit access to step workflow status — '
                + 'ask an admin for the UAT Admin permission set.');
        }
    }

    /** The UatCaseAdminController.parse pattern, verbatim: a friendly message
     *  for malformed JSON, and AuraHandledExceptions pass through untouched. */
    private static Object parse(String inputJson, Type target) {
        try {
            Object input = String.isBlank(inputJson) ? null : JSON.deserialize(inputJson, target);
            if (input == null) {
                throw auraError('Could not read the request — refresh and try again.');
            }
            return input;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError('Could not read the request — refresh and try again.');
        }
    }

    // ---- Assembly ------------------------------------------------------------

    private static CycleReportDTO buildReport(Id cycleId) {
        CycleReportDTO dto = new CycleReportDTO();
        dto.generatedAt = System.now();
        dto.generatedById = UserInfo.getUserId();
        dto.generatedByName = UserInfo.getName();
        dto.scope = cycleId == null ? SCOPE_STANDALONE : SCOPE_CYCLE;
        if (cycleId != null) {
            dto.cycle = loadCycleHeader(cycleId);
        }

        Map<Id, ExecutionRowDTO> execById = loadExecutions(dto, cycleId);
        loadStepResults(dto, execById);
        Map<Id, SessionRowDTO> sessionById = loadSessions(dto, cycleId);
        Map<Id, NoteRowDTO> noteById = loadNotes(dto, sessionById);
        loadFindings(dto, cycleId, sessionById);
        loadEvents(dto, cycleId);
        loadEvidence(dto, execById, sessionById, noteById);
        // After evidence, because a case row rolls its runs' evidence up; after
        // findings, because it carries their Ids; before the summary, which
        // counts its verdicts.
        loadCases(dto, cycleId, execById);
        buildSummary(dto, execById, sessionById);
        return dto;
    }

    private static CycleHeaderDTO loadCycleHeader(Id cycleId) {
        Test_Cycle__c cycle;
        try {
            cycle = [
                SELECT Id, Name, Status__c, Target_Date__c, Max_Testers__c,
                    Claim_Limit_Per_Tester__c, Stale_Claim_Days__c,
                    Assigned_Team__c, Assigned_Team__r.Name,
                    CreatedDate, LastModifiedDate
                FROM Test_Cycle__c
                WHERE Id = :cycleId
            ];
        } catch (QueryException e) {
            throw auraError('That cycle no longer exists — refresh and try again.');
        }
        CycleHeaderDTO header = new CycleHeaderDTO();
        header.cycleId = cycle.Id;
        header.cycleName = cycle.Name;
        // The oldest cycle predates the field's default and reads as null.
        header.status = String.isBlank(cycle.Status__c) ? UatConstants.CYCLE_ACTIVE : cycle.Status__c;
        header.teamId = cycle.Assigned_Team__c;
        header.teamName = cycle.Assigned_Team__r != null ? cycle.Assigned_Team__r.Name : null;
        header.targetDate = cycle.Target_Date__c;
        header.daysToTarget = cycle.Target_Date__c == null
            ? null : Date.today().daysBetween(cycle.Target_Date__c);
        header.maxTesters = toInt(cycle.Max_Testers__c);
        header.claimLimitPerTester = toInt(cycle.Claim_Limit_Per_Tester__c);
        header.staleClaimDays = toInt(cycle.Stale_Claim_Days__c);
        header.createdDate = cycle.CreatedDate;
        header.lastModifiedDate = cycle.LastModifiedDate;
        return header;
    }

    /** Released rows are included and flagged — a report of what a cycle
     *  produced must show work that was done and then handed back. */
    private static Map<Id, ExecutionRowDTO> loadExecutions(CycleReportDTO dto, Id cycleId) {
        Map<Id, ExecutionRowDTO> byId = new Map<Id, ExecutionRowDTO>();
        if (heapExhausted()) {
            flagGrain(dto.executions, REASON_HEAP);
            return byId;
        }
        Integer cap = capFor();
        List<Test_Execution__c> rows = [
            SELECT Id, Name, Testing_Status__c, Testing_Result__c, UX_Rating__c,
                UX_Recommendation__c, Claimed_Date__c, Last_Tested_Date__c,
                Released__c, Identity_Key__c, CreatedDate, LastModifiedDate,
                Test_Cycle__c, Test_Cycle__r.Name,
                Assigned_Tester__c, Assigned_Tester__r.Name,
                Assigned_Team__c, Assigned_Team__r.Name,
                Test_Case__c, Test_Case__r.Name, Test_Case__r.Case_ID__c,
                Test_Case__r.Title__c, Test_Case__r.Version__c, Test_Case__r.Sequence__c,
                Test_Case__r.Priority__c, Test_Case__r.Estimated_Effort__c,
                Test_Case__r.Testing_Surface__c, Test_Case__r.Creation_Status__c,
                Test_Case__r.Module__c, Test_Case__r.Module__r.Name,
                Test_Case__r.Module__r.Module_Group__r.Name,
                Test_Case__r.Module__r.Module_Group__r.System__r.Name
            FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY Test_Case__r.Sequence__c NULLS LAST, Test_Case__r.Case_ID__c, Name
            LIMIT :cap
        ];
        if (trimOverflow(rows, cap)) {
            flagGrain(dto.executions, capReason(cap));
        }

        // One path string per module, shared by reference across rows.
        Map<Id, String> pathByModule = new Map<Id, String>();
        for (Test_Execution__c e : rows) {
            ExecutionRowDTO row = new ExecutionRowDTO();
            row.executionId = e.Id;
            row.name = e.Name;
            row.caseId = e.Test_Case__c;
            row.testingStatus = e.Testing_Status__c;
            row.testingResult = e.Testing_Result__c;
            row.released = e.Released__c == true;
            row.claimedDate = e.Claimed_Date__c;
            row.lastTestedDate = e.Last_Tested_Date__c;
            row.createdDate = e.CreatedDate;
            row.lastModifiedDate = e.LastModifiedDate;
            row.uxRating = e.UX_Rating__c;
            row.uxRecommendation = clip(e.UX_Recommendation__c);
            row.textTruncated = isClipped(e.UX_Recommendation__c);
            row.identityKey = e.Identity_Key__c;
            row.cycleId = e.Test_Cycle__c;
            row.cycleName = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : null;
            row.testerId = e.Assigned_Tester__c;
            row.testerName = e.Assigned_Tester__r != null ? e.Assigned_Tester__r.Name : null;
            row.teamId = e.Assigned_Team__c;
            row.teamName = e.Assigned_Team__r != null ? e.Assigned_Team__r.Name : null;
            if (e.Test_Case__r != null) {
                row.caseNumber = e.Test_Case__r.Name;
                row.caseCode = e.Test_Case__r.Case_ID__c;
                row.caseTitle = e.Test_Case__r.Title__c;
                row.caseVersion = e.Test_Case__r.Version__c;
                row.caseSequence = e.Test_Case__r.Sequence__c;
                row.priority = e.Test_Case__r.Priority__c;
                row.estimatedEffort = e.Test_Case__r.Estimated_Effort__c;
                row.testingSurface = e.Test_Case__r.Testing_Surface__c;
                row.creationStatus = e.Test_Case__r.Creation_Status__c;
                if (e.Test_Case__r.Module__r != null) {
                    row.moduleName = e.Test_Case__r.Module__r.Name;
                    if (e.Test_Case__r.Module__r.Module_Group__r != null) {
                        row.moduleGroupName = e.Test_Case__r.Module__r.Module_Group__r.Name;
                        if (e.Test_Case__r.Module__r.Module_Group__r.System__r != null) {
                            row.systemName = e.Test_Case__r.Module__r.Module_Group__r.System__r.Name;
                        }
                    }
                }
                Id moduleId = e.Test_Case__r.Module__c;
                if (moduleId != null) {
                    if (!pathByModule.containsKey(moduleId)) {
                        pathByModule.put(moduleId, joinPath(row.systemName, row.moduleGroupName, row.moduleName));
                    }
                    row.modulePath = pathByModule.get(moduleId);
                }
            }
            dto.executions.rows.add(row);
            byId.put(row.executionId, row);
        }
        dto.executions.returned = dto.executions.rows.size();
        return byId;
    }

    /**
     * Step definitions are read ONCE per case and shared by reference. Selecting
     * Test_Step__r.* on the result query instead would materialize the same
     * step text once per run — 100 runs of an 8-step case carry it 800 times.
     * Clipping happens here, before sharing: clip after and every row gets a
     * fresh substring, which destroys the sharing this exists for.
     */
    private static void loadStepResults(CycleReportDTO dto, Map<Id, ExecutionRowDTO> execById) {
        if (execById.isEmpty()) {
            return;
        }
        // Executions truncating truncates their steps, even if the step query
        // never reaches its own cap. Easiest thing here to get silently wrong.
        if (dto.executions.truncated) {
            dto.executions.stepsTruncated = true;
            dto.executions.stepsTruncationReason = REASON_PARENT_EXEC;
        }
        if (heapExhausted()) {
            dto.executions.stepsTruncated = true;
            dto.executions.stepsTruncationReason =
                firstReason(dto.executions.stepsTruncationReason, REASON_HEAP);
            return;
        }

        Set<Id> caseIds = new Set<Id>();
        for (ExecutionRowDTO row : execById.values()) {
            if (row.caseId != null) {
                caseIds.add(row.caseId);
            }
        }
        Map<Id, StepDef> defByStep = new Map<Id, StepDef>();
        if (!caseIds.isEmpty()) {
            for (Test_Step__c s : [
                SELECT Id, Step_Number__c, Test_Condition__c, Step_Description__c,
                    Expected_Result__c, Explore_Prompt__c, Is_Explore__c
                FROM Test_Step__c
                WHERE Test_Case__c IN :caseIds
                ORDER BY Step_Number__c NULLS LAST
                LIMIT :capFor()
            ]) {
                StepDef def = new StepDef();
                def.stepNumber = s.Step_Number__c;
                def.stepCondition = s.Test_Condition__c;
                def.stepDescription = clip(s.Step_Description__c);
                def.expectedResult = clip(s.Expected_Result__c);
                def.explorePrompt = clip(s.Explore_Prompt__c);
                def.isExplore = s.Is_Explore__c == true;
                def.textTruncated = isClipped(s.Step_Description__c)
                    || isClipped(s.Expected_Result__c) || isClipped(s.Explore_Prompt__c);
                defByStep.put(s.Id, def);
            }
        }

        Set<Id> executionIds = execById.keySet();
        Integer cap = capFor();
        List<Test_Step_Result__c> rows = [
            SELECT Id, Name, Test_Execution__c, Test_Step__c, Result__c,
                Actual_Result__c, Explore_Notes__c,
                Workflow_Status__c, External_Ref__c,
                CreatedDate, LastModifiedDate
            FROM Test_Step_Result__c
            WHERE Test_Execution__c IN :executionIds
            ORDER BY Test_Execution__c, Test_Step__r.Step_Number__c NULLS LAST, Name
            LIMIT :cap
        ];
        if (trimOverflow(rows, cap)) {
            dto.executions.stepsTruncated = true;
            dto.executions.stepsTruncationReason =
                firstReason(dto.executions.stepsTruncationReason, capReason(cap));
        }

        for (Test_Step_Result__c r : rows) {
            ExecutionRowDTO parent = execById.get(r.Test_Execution__c);
            if (parent == null) {
                continue;
            }
            StepResultRowDTO row = new StepResultRowDTO();
            row.resultId = r.Id;
            row.name = r.Name;
            row.executionId = r.Test_Execution__c;
            row.executionName = parent.name;
            row.caseCode = parent.caseCode;
            row.caseTitle = parent.caseTitle;
            row.stepId = r.Test_Step__c;
            row.result = r.Result__c;
            row.actualResult = clip(r.Actual_Result__c);
            row.exploreNotes = clip(r.Explore_Notes__c);
            row.workflowStatus = r.Workflow_Status__c;
            row.externalRef = r.External_Ref__c;
            if ((r.Result__c == 'Fail' || r.Result__c == 'Blocked')
                && (String.isBlank(r.Workflow_Status__c) || r.Workflow_Status__c == STATUS_NEW)) {
                parent.stepsUntriaged++;
            }
            row.createdDate = r.CreatedDate;
            row.lastModifiedDate = r.LastModifiedDate;
            row.textTruncated = isClipped(r.Actual_Result__c) || isClipped(r.Explore_Notes__c);

            StepDef def = r.Test_Step__c == null ? null : defByStep.get(r.Test_Step__c);
            if (r.Test_Step__c == null) {
                // The lookup is SetNull, so the definition can vanish under an
                // answered result. Say so in words — a blank cell in a CSV reads
                // as "nobody wrote a step", which is a different claim.
                row.stepDeleted = true;
                row.stepDescription = STEP_DELETED_LABEL;
                parent.stepsOrphaned++;
            } else if (def != null) {
                row.stepNumber = def.stepNumber;
                row.stepCondition = def.stepCondition;
                row.stepDescription = def.stepDescription;
                row.expectedResult = def.expectedResult;
                row.explorePrompt = def.explorePrompt;
                row.isExplore = def.isExplore;
                row.textTruncated = row.textTruncated || def.textTruncated;
            }

            parent.steps.add(row);
            parent.stepsTotal++;
            if (String.isBlank(r.Result__c)) {
                dto.summary.stepsUnanswered++;
            } else {
                parent.stepsAnswered++;
                if (r.Result__c == 'Pass') {
                    parent.stepsPassed++;
                    dto.summary.stepsPass++;
                } else if (r.Result__c == 'Fail') {
                    parent.stepsFailed++;
                    dto.summary.stepsFail++;
                } else if (r.Result__c == 'Blocked') {
                    parent.stepsBlocked++;
                    dto.summary.stepsBlocked++;
                } else {
                    parent.stepsNotApplicable++;
                    dto.summary.stepsNotApplicable++;
                }
            }
            dto.summary.stepResultCount++;
            if (row.stepDeleted) {
                dto.summary.stepsOrphaned++;
            }
        }
        dto.executions.stepsReturned = dto.summary.stepResultCount;
    }

    private static Map<Id, SessionRowDTO> loadSessions(CycleReportDTO dto, Id cycleId) {
        Map<Id, SessionRowDTO> byId = new Map<Id, SessionRowDTO>();
        if (heapExhausted()) {
            flagGrain(dto.sessions, REASON_HEAP);
            return byId;
        }
        Integer cap = capFor();
        List<Exploratory_Session__c> rows = [
            SELECT Id, Name, Title__c, Area__c, Status__c, Started_At__c, Finished_At__c,
                Timebox_Minutes__c, CreatedDate, LastModifiedDate,
                Test_Cycle__c, Test_Cycle__r.Name, Tester__c, Tester__r.Name
            FROM Exploratory_Session__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY Started_At__c DESC NULLS LAST, Name DESC
            LIMIT :cap
        ];
        if (trimOverflow(rows, cap)) {
            flagGrain(dto.sessions, capReason(cap));
        }
        for (Exploratory_Session__c s : rows) {
            SessionRowDTO row = new SessionRowDTO();
            row.sessionId = s.Id;
            row.name = s.Name;
            row.title = s.Title__c;
            row.areaText = s.Area__c;
            row.status = s.Status__c;
            row.startedAt = s.Started_At__c;
            row.finishedAt = s.Finished_At__c;
            row.timeboxMinutes = s.Timebox_Minutes__c;
            row.createdDate = s.CreatedDate;
            row.lastModifiedDate = s.LastModifiedDate;
            row.cycleId = s.Test_Cycle__c;
            row.cycleName = s.Test_Cycle__r != null ? s.Test_Cycle__r.Name : null;
            row.testerId = s.Tester__c;
            row.testerName = s.Tester__r != null ? s.Tester__r.Name : null;
            if (s.Started_At__c != null && s.Finished_At__c != null) {
                row.durationMinutes = Integer.valueOf(
                    (s.Finished_At__c.getTime() - s.Started_At__c.getTime()) / 60000);
            }
            dto.sessions.rows.add(row);
            byId.put(row.sessionId, row);
        }
        dto.sessions.returned = dto.sessions.rows.size();
        return byId;
    }

    /**
     * Notes are scoped through their session, never through their execution.
     * addSessionNote does not validate that a note's "logged from run" execution
     * shares the session's cycle, so a note in a standalone session can point at
     * a cycled run. The note belongs to its session; executionId is a
     * cross-reference column, not a scope.
     */
    private static Map<Id, NoteRowDTO> loadNotes(CycleReportDTO dto, Map<Id, SessionRowDTO> sessionById) {
        Map<Id, NoteRowDTO> byId = new Map<Id, NoteRowDTO>();
        if (sessionById.isEmpty()) {
            return byId;
        }
        if (dto.sessions.truncated) {
            dto.sessions.notesTruncated = true;
            dto.sessions.notesTruncationReason = REASON_PARENT_SESSION;
        }
        if (heapExhausted()) {
            dto.sessions.notesTruncated = true;
            dto.sessions.notesTruncationReason =
                firstReason(dto.sessions.notesTruncationReason, REASON_HEAP);
            return byId;
        }
        Set<Id> sessionIds = sessionById.keySet();
        Integer cap = capFor();
        List<Session_Note__c> rows = [
            SELECT Id, Name, Exploratory_Session__c, Entry_Text__c, Logged_At__c, Tag__c,
                Author__c, Author__r.Name,
                Test_Execution__c, Test_Execution__r.Name,
                Test_Execution__r.Test_Case__r.Case_ID__c,
                Test_Execution__r.Test_Case__r.Title__c
            FROM Session_Note__c
            WHERE Exploratory_Session__c IN :sessionIds
            ORDER BY Exploratory_Session__c, Logged_At__c NULLS LAST, Name
            LIMIT :cap
        ];
        if (trimOverflow(rows, cap)) {
            dto.sessions.notesTruncated = true;
            dto.sessions.notesTruncationReason =
                firstReason(dto.sessions.notesTruncationReason, capReason(cap));
        }
        for (Session_Note__c n : rows) {
            SessionRowDTO parent = sessionById.get(n.Exploratory_Session__c);
            if (parent == null) {
                continue;
            }
            NoteRowDTO row = new NoteRowDTO();
            row.noteId = n.Id;
            row.name = n.Name;
            row.sessionId = n.Exploratory_Session__c;
            row.sessionName = parent.name;
            row.sessionTitle = parent.title;
            row.text = clip(n.Entry_Text__c);
            row.textTruncated = isClipped(n.Entry_Text__c);
            row.tag = n.Tag__c;
            row.loggedAt = n.Logged_At__c;
            row.authorId = n.Author__c;
            row.authorName = n.Author__r != null ? n.Author__r.Name : null;
            row.executionId = n.Test_Execution__c;
            if (n.Test_Execution__r != null) {
                row.executionName = n.Test_Execution__r.Name;
                if (n.Test_Execution__r.Test_Case__r != null) {
                    row.caseCode = n.Test_Execution__r.Test_Case__r.Case_ID__c;
                    row.caseTitle = n.Test_Execution__r.Test_Case__r.Title__c;
                }
            }
            parent.notes.add(row);
            parent.noteCount++;
            byId.put(row.noteId, row);
        }
        dto.sessions.notesReturned = byId.size();

        // A separate three-field query rather than a scan of the findings grain:
        // the badge must survive that grain truncating.
        if (!byId.isEmpty()) {
            Set<Id> noteIds = byId.keySet();
            for (Exploratory_Finding__c f : [
                SELECT Id, Name, Source_Note__c
                FROM Exploratory_Finding__c
                WHERE Source_Note__c IN :noteIds
            ]) {
                NoteRowDTO note = byId.get(f.Source_Note__c);
                if (note != null) {
                    note.promotedFindingId = f.Id;
                    note.promotedFindingName = f.Name;
                }
            }
        }
        return byId;
    }

    private static void loadFindings(CycleReportDTO dto, Id cycleId, Map<Id, SessionRowDTO> sessionById) {
        if (heapExhausted()) {
            flagGrain(dto.findings, REASON_HEAP);
            return;
        }
        Integer cap = capFor();
        List<Exploratory_Finding__c> rows = [
            SELECT Id, Name, Title__c, Type__c, Source__c, Severity__c,
                Workflow_Status__c, External_Ref__c,
                What_Testing__c, What_Happened__c, What_Expected__c,
                No_Evidence_Reason__c, Date__c, CreatedDate, LastModifiedDate,
                Tester__c, Tester__r.Name,
                Test_Cycle__c, Test_Cycle__r.Name,
                Exploratory_Session__c, Exploratory_Session__r.Name,
                Exploratory_Session__r.Title__c,
                Source_Note__c, Source_Note__r.Name, Source_Note__r.Logged_At__c,
                Test_Step_Result__c, Test_Step_Result__r.Name,
                Test_Execution__c, Test_Execution__r.Name,
                Test_Execution__r.Test_Case__c,
                Test_Execution__r.Test_Case__r.Case_ID__c,
                Test_Execution__r.Test_Case__r.Title__c
            FROM Exploratory_Finding__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY Date__c DESC NULLS LAST, Name DESC
            LIMIT :cap
        ];
        if (trimOverflow(rows, cap)) {
            flagGrain(dto.findings, capReason(cap));
        }
        for (Exploratory_Finding__c f : rows) {
            FindingRowDTO row = new FindingRowDTO();
            row.findingId = f.Id;
            row.name = f.Name;
            row.title = f.Title__c;
            row.findingType = f.Type__c;
            row.source = f.Source__c;
            row.severity = f.Severity__c;
            row.workflowStatus = f.Workflow_Status__c;
            row.externalRef = f.External_Ref__c;
            row.whatTesting = clip(f.What_Testing__c);
            row.whatHappened = clip(f.What_Happened__c);
            row.whatExpected = clip(f.What_Expected__c);
            row.textTruncated = isClipped(f.What_Testing__c) || isClipped(f.What_Happened__c)
                || isClipped(f.What_Expected__c) || isClipped(f.No_Evidence_Reason__c);
            row.noEvidenceReason = clip(f.No_Evidence_Reason__c);
            row.dateLogged = f.Date__c;
            row.createdDate = f.CreatedDate;
            row.lastModifiedDate = f.LastModifiedDate;
            row.testerId = f.Tester__c;
            row.testerName = f.Tester__r != null ? f.Tester__r.Name : null;
            row.cycleId = f.Test_Cycle__c;
            row.cycleName = f.Test_Cycle__r != null ? f.Test_Cycle__r.Name : null;
            row.sessionId = f.Exploratory_Session__c;
            if (f.Exploratory_Session__r != null) {
                row.sessionName = f.Exploratory_Session__r.Name;
                row.sessionTitle = f.Exploratory_Session__r.Title__c;
            }
            row.sourceNoteId = f.Source_Note__c;
            if (f.Source_Note__r != null) {
                row.sourceNoteName = f.Source_Note__r.Name;
                row.sourceNoteLoggedAt = f.Source_Note__r.Logged_At__c;
            }
            row.stepResultId = f.Test_Step_Result__c;
            row.stepResultName = f.Test_Step_Result__r != null ? f.Test_Step_Result__r.Name : null;
            row.executionId = f.Test_Execution__c;
            if (f.Test_Execution__r != null) {
                row.executionName = f.Test_Execution__r.Name;
                row.caseId = f.Test_Execution__r.Test_Case__c;
                if (f.Test_Execution__r.Test_Case__r != null) {
                    row.caseCode = f.Test_Execution__r.Test_Case__r.Case_ID__c;
                    row.caseTitle = f.Test_Execution__r.Test_Case__r.Title__c;
                }
            }
            dto.findings.rows.add(row);
            SessionRowDTO session = row.sessionId == null ? null : sessionById.get(row.sessionId);
            if (session != null) {
                session.findingCount++;
            }
        }
        dto.findings.returned = dto.findings.rows.size();
    }

    /**
     * The one query that genuinely branches. Test_Cycle__c on this object is
     * SetNull, so an event orphaned by a DELETED cycle also carries a null cycle
     * and would otherwise pollute the standalone report. The execution predicate
     * is the real filter; the cycle one is index-friendly and states intent.
     *
     * Accepted consequence: an event whose cycle AND execution were both nulled
     * is unreachable in standalone scope. There is no other anchor.
     */
    private static void loadEvents(CycleReportDTO dto, Id cycleId) {
        if (heapExhausted()) {
            flagGrain(dto.events, REASON_HEAP);
            return;
        }
        Integer cap = capFor();
        List<Test_Assignment_Event__c> rows;
        if (cycleId == null) {
            rows = [
                SELECT Id, Name, Action__c, Reason__c, CreatedDate,
                    Tester__c, Tester__r.Name, Actor__c, Actor__r.Name,
                    Test_Execution__c, Test_Execution__r.Name,
                    Test_Case__c, Test_Case__r.Case_ID__c,
                    Test_Cycle__c, Test_Cycle__r.Name
                FROM Test_Assignment_Event__c
                WHERE Test_Cycle__c = null AND Test_Execution__r.Test_Cycle__c = null
                ORDER BY CreatedDate DESC
                LIMIT :cap
            ];
        } else {
            rows = [
                SELECT Id, Name, Action__c, Reason__c, CreatedDate,
                    Tester__c, Tester__r.Name, Actor__c, Actor__r.Name,
                    Test_Execution__c, Test_Execution__r.Name,
                    Test_Case__c, Test_Case__r.Case_ID__c,
                    Test_Cycle__c, Test_Cycle__r.Name
                FROM Test_Assignment_Event__c
                WHERE Test_Cycle__c = :cycleId
                ORDER BY CreatedDate DESC
                LIMIT :cap
            ];
        }
        if (trimOverflow(rows, cap)) {
            flagGrain(dto.events, capReason(cap));
        }
        for (Test_Assignment_Event__c e : rows) {
            EventRowDTO row = new EventRowDTO();
            row.eventId = e.Id;
            row.name = e.Name;
            row.action = e.Action__c;
            row.occurredAt = e.CreatedDate;
            row.reason = clip(e.Reason__c);
            row.textTruncated = isClipped(e.Reason__c);
            row.testerId = e.Tester__c;
            row.testerName = e.Tester__r != null ? e.Tester__r.Name : null;
            row.actorId = e.Actor__c;
            row.actorName = e.Actor__r != null ? e.Actor__r.Name : null;
            row.executionId = e.Test_Execution__c;
            row.executionName = e.Test_Execution__r != null ? e.Test_Execution__r.Name : null;
            row.caseId = e.Test_Case__c;
            row.caseCode = e.Test_Case__r != null ? e.Test_Case__r.Case_ID__c : null;
            row.cycleId = e.Test_Cycle__c;
            row.cycleName = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : null;
            dto.events.rows.add(row);
        }
        dto.events.returned = dto.events.rows.size();
    }

    /**
     * Two phases, both keeping full file lists: the export carries a
     * download-URL column for every grain, so a count alone is not enough.
     *
     * A runs first — findings, notes and sessions — because the data-quality
     * gate needs "zero evidence" to be authoritative before it decides. B is
     * executions and step results, one to two orders of magnitude larger, and
     * is the first thing to drop when heap runs short: losing evidence links on
     * the big grains beats throwing a LimitException the LWC renders as
     * "Script-thrown exception".
     */
    private static void loadEvidence(CycleReportDTO dto, Map<Id, ExecutionRowDTO> execById,
        Map<Id, SessionRowDTO> sessionById, Map<Id, NoteRowDTO> noteById) {

        Set<Id> allDocs = new Set<Id>();

        Set<Id> phaseA = new Set<Id>();
        phaseA.addAll(sessionById.keySet());
        phaseA.addAll(noteById.keySet());
        for (FindingRowDTO f : dto.findings.rows) {
            phaseA.add(f.findingId);
        }
        if (!phaseA.isEmpty() && !heapExhausted()) {
            Map<Id, List<UatFileService.FileDTO>> files = filesFor(phaseA);
            for (SessionRowDTO s : dto.sessions.rows) {
                s.files = orEmpty(files.get(s.sessionId));
                s.evidenceCount = countDistinct(s.files, allDocs);
                dto.summary.evidenceLinkCount += s.evidenceCount;
            }
            for (NoteRowDTO n : noteById.values()) {
                n.files = orEmpty(files.get(n.noteId));
                n.evidenceCount = countDistinct(n.files, allDocs);
                dto.summary.evidenceLinkCount += n.evidenceCount;
            }
            for (FindingRowDTO f : dto.findings.rows) {
                f.files = orEmpty(files.get(f.findingId));
                f.evidenceCount = countDistinct(f.files, allDocs);
                dto.summary.evidenceLinkCount += f.evidenceCount;
            }
        }

        Set<Id> phaseB = new Set<Id>();
        phaseB.addAll(execById.keySet());
        for (ExecutionRowDTO e : dto.executions.rows) {
            for (StepResultRowDTO s : e.steps) {
                phaseB.add(s.resultId);
            }
        }
        if (!phaseB.isEmpty() && !heapExhausted()) {
            Map<Id, List<UatFileService.FileDTO>> files = filesFor(phaseB);
            for (ExecutionRowDTO e : dto.executions.rows) {
                e.files = orEmpty(files.get(e.executionId));
                e.evidenceCount = countDistinct(e.files, allDocs);
                dto.summary.evidenceLinkCount += e.evidenceCount;
                for (StepResultRowDTO s : e.steps) {
                    s.files = orEmpty(files.get(s.resultId));
                    s.evidenceCount = countDistinct(s.files, allDocs);
                    dto.summary.evidenceLinkCount += s.evidenceCount;
                }
            }
        }

        dto.summary.evidenceDocumentCount = allDocs.size();
    }

    // ---- Cases ---------------------------------------------------------------

    /**
     * The case grain: every test case this cycle touched, in run order.
     *
     * Its membership is the UNION of two sets, and both halves are load-bearing:
     *  - cases in the cycle's effective scope, which is books
     *    (Test_Cycle_Book__c -> Test_Book_Item__c) PLUS direct adds
     *    (Test_Cycle_Case__c), resolved by UatScopeService. Reading the direct
     *    junction alone silently drops every book-sourced case.
     *  - cases with an execution in this cycle. cleanupPristineSlots only
     *    removes UNWORKED slots, so a run survives its junction being deleted;
     *    scoping by the junction alone would erase finished work from the report.
     *
     * Standalone reports get no case grain: Test_Cycle_Case__c.Test_Cycle__c is
     * a required master-detail, so work with no cycle has no scope to compare to.
     */
    private static void loadCases(CycleReportDTO dto, Id cycleId, Map<Id, ExecutionRowDTO> execById) {
        // Half one costs nothing: the executions are already loaded and ordered.
        Map<Id, List<ExecutionRowDTO>> execsByCase = new Map<Id, List<ExecutionRowDTO>>();
        Map<Id, Id> caseByStepResult = new Map<Id, Id>();
        for (ExecutionRowDTO row : dto.executions.rows) {
            if (row.caseId == null) {
                continue;
            }
            if (!execsByCase.containsKey(row.caseId)) {
                execsByCase.put(row.caseId, new List<ExecutionRowDTO>());
            }
            execsByCase.get(row.caseId).add(row);
            for (StepResultRowDTO step : row.steps) {
                caseByStepResult.put(step.resultId, row.caseId);
            }
        }

        // A finding reaches its case through its run, or through the step result
        // its run owns — saveFinding sets whichever the tester was looking at.
        Map<Id, List<FindingRowDTO>> findingsByCase = new Map<Id, List<FindingRowDTO>>();
        for (FindingRowDTO f : dto.findings.rows) {
            Id caseId = f.caseId;
            if (caseId == null && f.stepResultId != null) {
                caseId = caseByStepResult.get(f.stepResultId);
            }
            if (caseId == null && f.executionId != null && execById.containsKey(f.executionId)) {
                caseId = execById.get(f.executionId).caseId;
            }
            if (caseId == null) {
                continue;
            }
            if (!findingsByCase.containsKey(caseId)) {
                findingsByCase.put(caseId, new List<FindingRowDTO>());
            }
            findingsByCase.get(caseId).add(f);
        }

        // Half two needs the scope resolver, whose three queries are uncapped —
        // it is the shared console resolver and not ours to limit. Decline
        // rather than risk the transaction, and say so on the grain.
        Map<Id, UatScopeService.ScopeEntry> scope = new Map<Id, UatScopeService.ScopeEntry>();
        if (cycleId != null) {
            if (heapExhausted()) {
                flagGrain(dto.cases, REASON_HEAP);
            } else if (rowBudgetRemaining() < SCOPE_BUDGET_MIN) {
                flagGrain(dto.cases, REASON_SCOPE_SKIPPED);
            } else {
                Map<Id, Map<Id, UatScopeService.ScopeEntry>> byCycle =
                    UatScopeService.effectiveScope(new Set<Id>{ cycleId });
                if (byCycle.get(cycleId) != null) {
                    scope = byCycle.get(cycleId);
                }
            }
        }
        // Executions truncating truncates the executed half of the union.
        if (dto.executions.truncated) {
            dto.cases.truncated = true;
            dto.cases.truncationReason = firstReason(dto.cases.truncationReason, REASON_PARENT_EXEC);
        }

        // Only scope-only cases need hydrating — an executed case already carries
        // every field the row needs, copied onto its execution rows.
        Set<Id> scopeOnly = new Set<Id>(scope.keySet());
        scopeOnly.removeAll(execsByCase.keySet());
        Map<Id, Test_Case__c> caseById = new Map<Id, Test_Case__c>();
        if (!scopeOnly.isEmpty() && !heapExhausted()) {
            Integer cap = capFor();
            List<Test_Case__c> extra = [
                SELECT Id, Name, Case_ID__c, Title__c, Version__c, Sequence__c,
                    Priority__c, Estimated_Effort__c, Testing_Surface__c,
                    Module__c, Module__r.Name, Module__r.Module_Group__r.Name,
                    Module__r.Module_Group__r.System__r.Name
                FROM Test_Case__c
                WHERE Id IN :scopeOnly
                ORDER BY Sequence__c NULLS LAST, Case_ID__c
                LIMIT :cap
            ];
            if (trimOverflow(extra, cap)) {
                dto.cases.truncated = true;
                dto.cases.truncationReason = firstReason(dto.cases.truncationReason, capReason(cap));
            }
            caseById.putAll(extra);
        }

        Set<Id> caseIds = new Set<Id>(execsByCase.keySet());
        caseIds.addAll(caseById.keySet());

        // Apex cannot sort a DTO list without a Comparable wrapper, so order by
        // a built key instead: sequence first (nulls last), then the case code.
        Map<String, CaseRowDTO> byKey = new Map<String, CaseRowDTO>();
        for (Id caseId : caseIds) {
            List<ExecutionRowDTO> runs = execsByCase.containsKey(caseId)
                ? execsByCase.get(caseId) : new List<ExecutionRowDTO>();
            CaseRowDTO row = buildCaseRow(caseId, runs, caseById.get(caseId), scope.get(caseId));
            for (FindingRowDTO f : orEmptyFindings(findingsByCase.get(caseId))) {
                row.findingIds.add(f.findingId);
            }
            row.findingCount = row.findingIds.size();
            byKey.put(sortKey(row), row);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        for (String key : keys) {
            dto.cases.rows.add(byKey.get(key));
        }
        dto.cases.returned = dto.cases.rows.size();
    }

    private static CaseRowDTO buildCaseRow(Id caseId, List<ExecutionRowDTO> runs,
        Test_Case__c hydrated, UatScopeService.ScopeEntry entry) {

        CaseRowDTO row = new CaseRowDTO();
        row.caseId = caseId;
        row.inScope = entry != null;
        row.noRunCreated = runs.isEmpty();
        if (entry != null) {
            row.displayOrder = entry.displayOrder;
            row.scopeSources = entry.sources == null || entry.sources.isEmpty()
                ? null : String.join(entry.sources, ', ');
        }

        if (!runs.isEmpty()) {
            // Every run of a case carries the same case fields; take the first.
            ExecutionRowDTO first = runs[0];
            row.caseNumber = first.caseNumber;
            row.caseCode = first.caseCode;
            row.caseTitle = first.caseTitle;
            row.caseVersion = first.caseVersion;
            row.caseSequence = first.caseSequence;
            row.systemName = first.systemName;
            row.moduleGroupName = first.moduleGroupName;
            row.moduleName = first.moduleName;
            row.modulePath = first.modulePath;
            row.priority = first.priority;
            row.estimatedEffort = first.estimatedEffort;
            row.testingSurface = first.testingSurface;
        } else if (hydrated != null) {
            row.caseNumber = hydrated.Name;
            row.caseCode = hydrated.Case_ID__c;
            row.caseTitle = hydrated.Title__c;
            row.caseVersion = hydrated.Version__c;
            row.caseSequence = hydrated.Sequence__c;
            row.priority = hydrated.Priority__c;
            row.estimatedEffort = hydrated.Estimated_Effort__c;
            row.testingSurface = hydrated.Testing_Surface__c;
            if (hydrated.Module__r != null) {
                row.moduleName = hydrated.Module__r.Name;
                if (hydrated.Module__r.Module_Group__r != null) {
                    row.moduleGroupName = hydrated.Module__r.Module_Group__r.Name;
                    if (hydrated.Module__r.Module_Group__r.System__r != null) {
                        row.systemName = hydrated.Module__r.Module_Group__r.System__r.Name;
                    }
                }
            }
            row.modulePath = joinPath(row.systemName, row.moduleGroupName, row.moduleName);
        }

        Set<String> testers = new Set<String>();
        for (ExecutionRowDTO run : runs) {
            row.executionIds.add(run.executionId);
            row.evidenceCount += run.evidenceCount;
            for (StepResultRowDTO step : run.steps) {
                row.evidenceCount += step.evidenceCount;
            }
            if (run.released) {
                row.releasedCount++;
                continue;
            }
            // Live seats only: a released run's steps are a superseded attempt,
            // and adding them would report 18 of 9 steps answered.
            if (String.isNotBlank(run.testerName) && !testers.contains(run.testerName)) {
                testers.add(run.testerName);
                row.testerNames.add(run.testerName);
            }
            row.stepsTotal += run.stepsTotal;
            row.stepsAnswered += run.stepsAnswered;
            row.stepsPassed += run.stepsPassed;
            row.stepsFailed += run.stepsFailed;
            row.stepsBlocked += run.stepsBlocked;
            row.stepsNotApplicable += run.stepsNotApplicable;
            row.stepsUntriaged += run.stepsUntriaged;
        }
        row.executionCount = runs.size();
        row.verdict = caseVerdict(runs);
        return row;
    }

    /**
     * The case's own answer, not a seat's.
     *
     * Released executions are history — a run that was handed back says nothing
     * about whether the case passes, so it never votes. Over the live rows the
     * worst outcome wins, because one failure is the answer however many other
     * seats passed. First match, in order:
     *
     *   1. no live runs                -> Not started   (the slot was deleted, or drift)
     *   2. any Failed                  -> Failed
     *   3. any Blocked                 -> Blocked
     *   4. all Complete and all Passed -> Passed
     *   5. any Postponed               -> Postponed
     *   6. any In Progress or Complete -> In progress
     *   7. otherwise                   -> Not started   (every seat still untouched)
     *
     * Postponed is its own verdict rather than folding into In progress: a
     * deliberately deferred case is a decision, and calling it in-flight would
     * put it back on somebody's to-do list.
     */
    private static String caseVerdict(List<ExecutionRowDTO> runs) {
        Boolean anyLive = false;
        Boolean anyFailed = false;
        Boolean anyBlocked = false;
        Boolean anyPostponed = false;
        Boolean anyStarted = false;
        Boolean allComplete = true;
        Boolean allPassed = true;

        for (ExecutionRowDTO run : runs) {
            if (run.released) {
                continue;
            }
            anyLive = true;
            if (run.testingResult == 'Failed') {
                anyFailed = true;
            } else if (run.testingResult == 'Blocked') {
                anyBlocked = true;
            } else if (run.testingResult == 'Postponed') {
                anyPostponed = true;
            }
            if (run.testingResult != 'Passed') {
                allPassed = false;
            }
            if (run.testingStatus != 'Complete') {
                allComplete = false;
            }
            if (run.testingStatus == 'In Progress' || run.testingStatus == 'Complete') {
                anyStarted = true;
            }
        }

        if (!anyLive) {
            return VERDICT_NOT_STARTED;
        }
        if (anyFailed) {
            return VERDICT_FAILED;
        }
        if (anyBlocked) {
            return VERDICT_BLOCKED;
        }
        if (allComplete && allPassed) {
            return VERDICT_PASSED;
        }
        if (anyPostponed) {
            return VERDICT_POSTPONED;
        }
        return anyStarted ? VERDICT_IN_PROGRESS : VERDICT_NOT_STARTED;
    }

    /** Sequence first, nulls last, then case code — the order loadExecutions
     *  already uses, so the tree and the flat grain never disagree. The case Id
     *  is the tiebreak: two cases can share a sequence and a blank code. */
    private static String sortKey(CaseRowDTO row) {
        String seq = row.caseSequence == null
            ? '1|'
            : '0|' + String.valueOf(row.caseSequence.longValue() + 1000000000000L);
        return seq + '|' + (row.caseCode == null ? '' : row.caseCode) + '|' + row.caseId;
    }

    private static List<FindingRowDTO> orEmptyFindings(List<FindingRowDTO> rows) {
        return rows == null ? new List<FindingRowDTO>() : rows;
    }

    // ---- Summary -------------------------------------------------------------

    private static void buildSummary(CycleReportDTO dto, Map<Id, ExecutionRowDTO> execById,
        Map<Id, SessionRowDTO> sessionById) {

        SummaryDTO s = dto.summary;
        s.executionCount = dto.executions.rows.size();
        s.caseCount = dto.cases.rows.size();
        s.sessionCount = dto.sessions.rows.size();
        s.noteCount = dto.sessions.notesReturned;
        s.findingCount = dto.findings.rows.size();
        s.eventCount = dto.events.rows.size();

        for (CaseRowDTO row : dto.cases.rows) {
            if (row.verdict == VERDICT_PASSED) {
                s.casesPassed++;
            } else if (row.verdict == VERDICT_FAILED) {
                s.casesFailed++;
            } else if (row.verdict == VERDICT_BLOCKED) {
                s.casesBlocked++;
            } else if (row.verdict == VERDICT_POSTPONED) {
                s.casesPostponed++;
            } else if (row.verdict == VERDICT_IN_PROGRESS) {
                s.casesInProgress++;
            } else {
                s.casesNotStarted++;
            }
            if (row.noRunCreated) {
                s.casesWithoutRuns++;
            }
        }
        s.casesComplete = s.casesPassed + s.casesFailed + s.casesBlocked + s.casesPostponed;

        Map<Id, TesterActivityDTO> testers = new Map<Id, TesterActivityDTO>();
        Integer uxTotal = 0;

        for (ExecutionRowDTO row : dto.executions.rows) {
            if (row.testerId == null) {
                s.unclaimedSlots++;
            } else if (row.released) {
                s.releasedRuns++;
            } else {
                s.activeRuns++;
            }
            if (row.testingStatus == 'Not Started') {
                s.statusNotStarted++;
            } else if (row.testingStatus == 'In Progress') {
                s.statusInProgress++;
            } else if (row.testingStatus == 'Complete') {
                s.statusComplete++;
            } else {
                s.statusUnset++;
            }
            if (row.testingResult == 'Passed') {
                s.resultPassed++;
            } else if (row.testingResult == 'Failed') {
                s.resultFailed++;
            } else if (row.testingResult == 'Blocked') {
                s.resultBlocked++;
            } else if (row.testingResult == 'Postponed') {
                s.resultPostponed++;
            } else {
                s.resultNone++;
            }
            if (row.uxRating != null) {
                s.uxRatingCount++;
                uxTotal += row.uxRating.intValue();
            }
            if (row.testerId != null) {
                TesterActivityDTO t = tester(testers, row.testerId, row.testerName);
                t.runsAssigned++;
                if (row.released) {
                    t.runsReleased++;
                }
                if (row.testingStatus == 'Complete') {
                    t.runsComplete++;
                }
                if (row.testingResult == 'Failed') {
                    t.runsFailed++;
                }
                t.stepsAnswered += row.stepsAnswered;
                t.lastActivity = later(t.lastActivity, row.claimedDate);
                t.lastActivity = later(t.lastActivity, row.lastModifiedDate);
            }
        }
        if (s.uxRatingCount > 0) {
            s.uxRatingAverage = (Decimal.valueOf(uxTotal) / s.uxRatingCount).setScale(1);
        }

        for (SessionRowDTO row : dto.sessions.rows) {
            if (row.testerId != null) {
                TesterActivityDTO t = tester(testers, row.testerId, row.testerName);
                t.sessionsStarted++;
                t.lastActivity = later(t.lastActivity, row.lastModifiedDate);
            }
            for (NoteRowDTO note : row.notes) {
                if (note.authorId != null) {
                    TesterActivityDTO t = tester(testers, note.authorId, note.authorName);
                    t.notesLogged++;
                    t.lastActivity = later(t.lastActivity, note.loggedAt);
                }
            }
        }

        // Step-failure half of the untriaged queue. Released runs are
        // superseded attempts — skipped here for the same reason buildCaseRow
        // skips their step counters.
        for (ExecutionRowDTO run : dto.executions.rows) {
            if (!run.released) {
                s.untriagedFailedSteps += run.stepsUntriaged;
            }
        }

        Map<String, Integer> byType = new Map<String, Integer>();
        Map<String, Integer> bySeverity = new Map<String, Integer>();
        Map<String, Integer> byStatus = new Map<String, Integer>();
        Map<String, TypeSeverityCountDTO> byBoth = new Map<String, TypeSeverityCountDTO>();
        for (FindingRowDTO row : dto.findings.rows) {
            bump(byType, row.findingType);
            if (row.severity != null) {
                bump(bySeverity, row.severity);
            }
            String status = String.isBlank(row.workflowStatus)
                ? STATUS_NEW : row.workflowStatus;
            bump(byStatus, status);
            if (row.findingType == TYPE_DEFECT && status == STATUS_NEW) {
                s.untriagedDefects++;
            }
            String key = row.findingType + '|' + row.severity;
            if (!byBoth.containsKey(key)) {
                TypeSeverityCountDTO cell = new TypeSeverityCountDTO();
                cell.findingType = row.findingType;
                cell.severity = row.severity;
                byBoth.put(key, cell);
            }
            byBoth.get(key).count++;

            if (row.source == SOURCE_TEST_CASE) {
                s.findingsFromTestCases++;
            } else if (row.source == SOURCE_SESSION) {
                s.findingsFromSessions++;
            }
            if (row.testerId != null) {
                TesterActivityDTO t = tester(testers, row.testerId, row.testerName);
                t.findingsLogged++;
                if (row.findingType == TYPE_DEFECT) {
                    t.defectsLogged++;
                }
                t.lastActivity = later(t.lastActivity, row.lastModifiedDate);
            }

            // A serious defect with nothing to look at and no stated reason. The
            // schema already offers No_Evidence_Reason__c as the escape hatch,
            // so a blank one is a gap, not a judgement call.
            if (row.findingType == TYPE_DEFECT
                && EVIDENCE_REQUIRED_SEVERITIES.contains(row.severity)
                && row.evidenceCount == 0
                && String.isBlank(row.noEvidenceReason)) {
                row.flaggedNoEvidence = true;
                DataQualityFlagDTO flag = new DataQualityFlagDTO();
                flag.code = FLAG_EVIDENCE_MISSING;
                flag.findingId = row.findingId;
                flag.findingName = row.name;
                flag.title = row.title;
                flag.findingType = row.findingType;
                flag.severity = row.severity;
                flag.testerId = row.testerId;
                flag.testerName = row.testerName;
                flag.sessionId = row.sessionId;
                flag.sessionName = row.sessionName;
                flag.executionId = row.executionId;
                flag.caseCode = row.caseCode;
                flag.reason = 'High/Critical defect with no evidence and no stated reason';
                s.dataQualityFlags.add(flag);
            }
        }
        s.findingsByType = countRows(byType);
        s.findingsBySeverity = countRows(bySeverity);
        s.findingsByStatus = countRows(byStatus);
        s.findingsByTypeAndSeverity = byBoth.values();
        s.testers = testers.values();
    }

    // ---- Internals -------------------------------------------------------------

    /** Same capability as Pool Health — deliberately the cycle-MANAGE capability
     *  rather than bare read: a UAT_Tester holds read on cycles and would
     *  otherwise reach every other tester's step notes and every standalone
     *  session in the org. The UAT_Console check is not redundant with the
     *  describes: ModifyAllData makes every one of them return true for a System
     *  Administrator, which is the reason the custom permission exists. */
    private static void assertReport() {
        if (!Schema.sObjectType.Test_Cycle__c.isCreateable()
            || !Schema.sObjectType.Test_Cycle__c.isUpdateable()
            || !Schema.sObjectType.Test_Assignment_Event__c.isAccessible()
            || !Schema.sObjectType.Exploratory_Finding__c.isAccessible()
            || !UatAudienceService.isUatAdmin()) {
            throw auraError('You do not have access to cycle reports.');
        }
    }

    /** Grain ceiling clamped by what the transaction has left, plus one row: the
     *  overflow probe. One snapshot, so it cannot disagree with itself the way a
     *  separate COUNT() can, and it covers both causes with no branching. */
    private static Integer capFor() {
        Integer grainLimit = grainLimitOverride == null ? GRAIN_LIMIT : grainLimitOverride;
        return Math.max(1, Math.min(grainLimit, rowBudgetRemaining())) + 1;
    }

    /** Rows this transaction can still spend on grains, after the reserve the
     *  two evidence phases need. Can go negative; callers clamp. */
    private static Integer rowBudgetRemaining() {
        return Limits.getLimitQueryRows() - Limits.getQueryRows() - ROW_BUDGET_RESERVE;
    }

    private static String capReason(Integer cap) {
        Integer grainLimit = grainLimitOverride == null ? GRAIN_LIMIT : grainLimitOverride;
        return (cap - 1) >= grainLimit ? REASON_GRAIN : REASON_ROWS;
    }

    /** Root cause wins. A child grain can hit its own cap AND be cut short by
     *  its parent in the same pass; the parent cut is the one the reader needs,
     *  because a child bounded by a truncated parent is incomplete whatever its
     *  own query did. Set once, keep the first. */
    private static String firstReason(String existing, String candidate) {
        return String.isBlank(existing) ? candidate : existing;
    }

    /** Drops the probe row and reports whether it was there. */
    private static Boolean trimOverflow(List<SObject> rows, Integer cap) {
        if (rows.size() < cap) {
            return false;
        }
        rows.remove(rows.size() - 1);
        return true;
    }

    private static Boolean heapExhausted() {
        return Limits.getHeapSize() > (Limits.getLimitHeapSize() * HEAP_CEILING);
    }

    private static void flagGrain(Object grain, String reason) {
        if (grain instanceof CaseGrainDTO) {
            CaseGrainDTO cases = (CaseGrainDTO) grain;
            cases.truncated = true;
            // Root cause wins: the scope half can be declined AND the parent
            // executions truncated in the same pass.
            cases.truncationReason = firstReason(cases.truncationReason, reason);
        } else if (grain instanceof ExecutionGrainDTO) {
            ((ExecutionGrainDTO) grain).truncated = true;
            ((ExecutionGrainDTO) grain).truncationReason = reason;
        } else if (grain instanceof SessionGrainDTO) {
            ((SessionGrainDTO) grain).truncated = true;
            ((SessionGrainDTO) grain).truncationReason = reason;
        } else if (grain instanceof FindingGrainDTO) {
            ((FindingGrainDTO) grain).truncated = true;
            ((FindingGrainDTO) grain).truncationReason = reason;
        } else if (grain instanceof EventGrainDTO) {
            ((EventGrainDTO) grain).truncated = true;
            ((EventGrainDTO) grain).truncationReason = reason;
        }
    }

    private static String clip(String value) {
        return value != null && value.length() > TEXT_LIMIT ? value.substring(0, TEXT_LIMIT) : value;
    }

    private static Boolean isClipped(String value) {
        return value != null && value.length() > TEXT_LIMIT;
    }

    private static String joinPath(String systemName, String groupName, String moduleName) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(systemName)) {
            parts.add(systemName);
        }
        if (String.isNotBlank(groupName)) {
            parts.add(groupName);
        }
        if (String.isNotBlank(moduleName)) {
            parts.add(moduleName);
        }
        return parts.isEmpty() ? null : String.join(parts, ' › ');
    }

    private static Integer toInt(Decimal value) {
        return value == null ? null : value.intValue();
    }

    private static Datetime later(Datetime current, Datetime candidate) {
        if (candidate == null) {
            return current;
        }
        return current == null || candidate > current ? candidate : current;
    }

    private static void bump(Map<String, Integer> counts, String key) {
        String safe = key == null ? '' : key;
        counts.put(safe, counts.containsKey(safe) ? counts.get(safe) + 1 : 1);
    }

    private static List<CountRowDTO> countRows(Map<String, Integer> counts) {
        List<CountRowDTO> rows = new List<CountRowDTO>();
        for (String key : counts.keySet()) {
            CountRowDTO row = new CountRowDTO();
            row.label = String.isBlank(key) ? null : key;
            row.count = counts.get(key);
            rows.add(row);
        }
        return rows;
    }

    private static TesterActivityDTO tester(Map<Id, TesterActivityDTO> testers, Id testerId, String name) {
        if (!testers.containsKey(testerId)) {
            TesterActivityDTO t = new TesterActivityDTO();
            t.testerId = testerId;
            t.testerName = name;
            testers.put(testerId, t);
        }
        TesterActivityDTO existing = testers.get(testerId);
        if (existing.testerName == null) {
            existing.testerName = name;
        }
        return existing;
    }

    private static List<UatFileService.FileDTO> orEmpty(List<UatFileService.FileDTO> files) {
        return files == null ? new List<UatFileService.FileDTO>() : files;
    }

    /** ContentDocumentLink is unique on (LinkedEntityId, ContentDocumentId), so
     *  a record's own list is already distinct — the Set is what produces the
     *  report-wide distinct count, and it is what the requirement asks for. */
    private static Integer countDistinct(List<UatFileService.FileDTO> files, Set<Id> allDocs) {
        if (files == null || files.isEmpty()) {
            return 0;
        }
        Set<Id> docs = new Set<Id>();
        for (UatFileService.FileDTO f : files) {
            docs.add(f.contentDocumentId);
        }
        allDocs.addAll(docs);
        return docs.size();
    }

    private static Map<Id, List<UatFileService.FileDTO>> filesFor(Set<Id> recordIds) {
        Map<Id, List<UatFileService.FileDTO>> merged = new Map<Id, List<UatFileService.FileDTO>>();
        List<Id> ids = new List<Id>(recordIds);
        for (Integer i = 0; i < ids.size(); i += CDL_CHUNK) {
            Set<Id> chunk = new Set<Id>();
            for (Integer j = i; j < Math.min(i + CDL_CHUNK, ids.size()); j++) {
                chunk.add(ids[j]);
            }
            merged.putAll(UatFileService.getFilesFor(chunk));
        }
        return merged;
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}