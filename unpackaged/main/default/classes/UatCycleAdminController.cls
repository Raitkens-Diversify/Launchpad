/**
 * UatCycleAdminController
 *
 * Apex behind the Admin Console's UAT Test Cycles section (adminUatCycles):
 * the cycle list (multi-book labels, direct-case chip, X/Y progress where Y
 * counts EXECUTIONS, findings count), and the cycle editor (fields, books
 * picker, direct-cases picker, and the All Cases & Executions table with
 * per-case source tags, execution chips, and "+ Add tester").
 *
 * Slot lifecycle is the triggers' + UatExecutionService's job — this class
 * only writes cycles and junctions and reads the results. Team-change
 * propagation to unclaimed executions rides the cycle trigger (03 §6), not
 * this controller.
 *
 * Conventions: with sharing, describe asserts + stripInaccessible,
 * AuraHandledException, JSON-string write payloads (org quirk).
 */
public with sharing class UatCycleAdminController {

    // ---- DTOs ----------------------------------------------------------------

    public class CycleRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String bookNames;      // comma list, per spec
        @AuraEnabled public Boolean hasDirectCases;
        @AuraEnabled public String teamName;
        @AuraEnabled public Date targetDate;
        @AuraEnabled public String status;         // 'Active' | 'Closed' (null-status rows read as Active)
        @AuraEnabled public Integer completeCount;
        @AuraEnabled public Integer totalExecutions;
        @AuraEnabled public Integer findingsCount;
    }

    public class OptionDTO {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class JunctionDTO {
        @AuraEnabled public Id junctionId;
        @AuraEnabled public Id targetId;
        @AuraEnabled public String label;
        @AuraEnabled public String sublabel;
        @AuraEnabled public String title;   // case junctions only; null = fall back to label
        @AuraEnabled public Id systemId;
    }

    public class ExecutionChipDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;    // null = Unclaimed
        @AuraEnabled public String status;
        @AuraEnabled public String result;
        @AuraEnabled public Boolean released;     // history — no seat, no actions
        @AuraEnabled public Datetime claimedDate;
    }

    public class ScopeRowDTO {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String title;   // null = fall back to the code
        @AuraEnabled public String moduleName;
        @AuraEnabled public String sourceLabel;   // "Book A, Book B" / "Added directly"
        @AuraEnabled public List<ExecutionChipDTO> executions = new List<ExecutionChipDTO>();
    }

    public class CycleDetailDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date targetDate;
        @AuraEnabled public String status;         // 'Active' | 'Claims Paused' | 'Closed'
        @AuraEnabled public Integer maxTesters;         // seats per case (default 1)
        @AuraEnabled public Integer claimLimitPerTester; // null = unlimited
        @AuraEnabled public Integer staleClaimDays;      // null = never auto-release
        /** Per-cycle focus-prompt override for exploratory-session notes;
         *  blank = inherit the org defaults (UAT_Focus_Prompt__mdt). Parsed
         *  in UatSessionController.resolvePrompts, not here. */
        @AuraEnabled public String focusPrompts;
        @AuraEnabled public Id teamId;
        @AuraEnabled public List<OptionDTO> teamOptions = new List<OptionDTO>();
        @AuraEnabled public List<OptionDTO> teamMembers = new List<OptionDTO>();
        @AuraEnabled public List<JunctionDTO> attachedBooks = new List<JunctionDTO>();
        @AuraEnabled public List<JunctionDTO> availableBooks = new List<JunctionDTO>();
        @AuraEnabled public List<JunctionDTO> directCases = new List<JunctionDTO>();
        @AuraEnabled public List<JunctionDTO> availableCases = new List<JunctionDTO>();
        @AuraEnabled public List<ScopeRowDTO> scopeRows = new List<ScopeRowDTO>();
    }

    public class CycleInput {
        public Id id;             // null = create
        public String name;
        public Date targetDate;
        public Id teamId;
        public Integer maxTesters;
        public Integer claimLimitPerTester;
        public Integer staleClaimDays;
        public String focusPrompts;
    }

    public class SeatActionInput {
        public Id executionId;
        public Id newTesterId;    // reassign only
        public String reason;
    }

    // ---- Reads ---------------------------------------------------------------

    @AuraEnabled
    public static List<CycleRowDTO> getCycles() {
        assertCyclesReadable();
        List<Test_Cycle__c> cycles = [
            SELECT Id, Name, Target_Date__c, Status__c, Assigned_Team__r.Name,
                Max_Testers__c
            FROM Test_Cycle__c
            ORDER BY Target_Date__c NULLS LAST, Name
            LIMIT 500
        ];
        Set<Id> cycleIds = new Map<Id, Test_Cycle__c>(cycles).keySet();

        Map<Id, List<String>> bookNamesByCycle = new Map<Id, List<String>>();
        for (Test_Cycle_Book__c junction : [
            SELECT Test_Cycle__c, Test_Book__r.Name FROM Test_Cycle_Book__c
            WHERE Test_Cycle__c IN :cycleIds ORDER BY Test_Book__r.Name
        ]) {
            if (!bookNamesByCycle.containsKey(junction.Test_Cycle__c)) {
                bookNamesByCycle.put(junction.Test_Cycle__c, new List<String>());
            }
            bookNamesByCycle.get(junction.Test_Cycle__c).add(junction.Test_Book__r.Name);
        }
        Set<Id> withDirect = new Set<Id>();
        for (Test_Cycle_Case__c direct : [
            SELECT Test_Cycle__c FROM Test_Cycle_Case__c WHERE Test_Cycle__c IN :cycleIds
        ]) {
            withDirect.add(direct.Test_Cycle__c);
        }
        Map<Id, Integer> totalByCycle = new Map<Id, Integer>();
        Map<Id, Integer> completeByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, Testing_Status__c status, COUNT(Id) total
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
            GROUP BY Test_Cycle__c, Testing_Status__c
        ]) {
            Id cycleId = (Id) ar.get('cycleId');
            Integer total = (Integer) ar.get('total');
            totalByCycle.put(cycleId, (totalByCycle.containsKey(cycleId) ? totalByCycle.get(cycleId) : 0) + total);
            if ((String) ar.get('status') == 'Complete') {
                completeByCycle.put(cycleId, total);
            }
        }
        Map<Id, Integer> findingsByCycle = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Cycle__c cycleId, COUNT(Id) total
            FROM Exploratory_Finding__c
            WHERE Test_Cycle__c IN :cycleIds
            GROUP BY Test_Cycle__c
        ]) {
            findingsByCycle.put((Id) ar.get('cycleId'), (Integer) ar.get('total'));
        }

        List<CycleRowDTO> rows = new List<CycleRowDTO>();
        for (Test_Cycle__c cycle : cycles) {
            CycleRowDTO row = new CycleRowDTO();
            row.id = cycle.Id;
            row.name = cycle.Name;
            row.bookNames = bookNamesByCycle.containsKey(cycle.Id)
                ? String.join(bookNamesByCycle.get(cycle.Id), ', ') : '';
            row.hasDirectCases = withDirect.contains(cycle.Id);
            row.teamName = cycle.Assigned_Team__r != null ? cycle.Assigned_Team__r.Name : null;
            row.targetDate = cycle.Target_Date__c;
            row.status = String.isBlank(cycle.Status__c) ? UatConstants.CYCLE_ACTIVE : cycle.Status__c;
            row.totalExecutions = totalByCycle.containsKey(cycle.Id) ? totalByCycle.get(cycle.Id) : 0;
            row.completeCount = completeByCycle.containsKey(cycle.Id) ? completeByCycle.get(cycle.Id) : 0;
            row.findingsCount = findingsByCycle.containsKey(cycle.Id) ? findingsByCycle.get(cycle.Id) : 0;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static CycleDetailDTO getCycleDetail(Id cycleId) {
        assertCyclesReadable();
        Test_Cycle__c cycle;
        try {
            cycle = [
                SELECT Id, Name, Target_Date__c, Status__c, Assigned_Team__c,
                    Max_Testers__c, Claim_Limit_Per_Tester__c, Stale_Claim_Days__c,
                    Focus_Prompts__c
                FROM Test_Cycle__c WHERE Id = :cycleId
            ];
        } catch (QueryException e) {
            throw auraError('That test cycle no longer exists.');
        }
        CycleDetailDTO dto = new CycleDetailDTO();
        dto.id = cycle.Id;
        dto.name = cycle.Name;
        dto.targetDate = cycle.Target_Date__c;
        dto.status = String.isBlank(cycle.Status__c) ? UatConstants.CYCLE_ACTIVE : cycle.Status__c;
        dto.maxTesters = cycle.Max_Testers__c == null ? 1 : Integer.valueOf(cycle.Max_Testers__c);
        dto.claimLimitPerTester = cycle.Claim_Limit_Per_Tester__c == null
            ? null : Integer.valueOf(cycle.Claim_Limit_Per_Tester__c);
        dto.staleClaimDays = cycle.Stale_Claim_Days__c == null
            ? null : Integer.valueOf(cycle.Stale_Claim_Days__c);
        dto.focusPrompts = cycle.Focus_Prompts__c;
        dto.teamId = cycle.Assigned_Team__c;

        for (Team__c team : [SELECT Id, Name FROM Team__c ORDER BY Name]) {
            OptionDTO o = new OptionDTO();
            o.value = team.Id;
            o.label = team.Name;
            dto.teamOptions.add(o);
        }
        if (cycle.Assigned_Team__c != null) {
            for (Team_Member__c member : [
                SELECT User__c, User__r.Name FROM Team_Member__c
                WHERE Team__c = :cycle.Assigned_Team__c AND User__c != null
                ORDER BY User__r.Name
            ]) {
                OptionDTO o = new OptionDTO();
                o.value = member.User__c;
                o.label = member.User__r.Name;
                dto.teamMembers.add(o);
            }
        }

        Set<Id> attachedBookIds = new Set<Id>();
        for (Test_Cycle_Book__c junction : [
            SELECT Id, Test_Book__c, Test_Book__r.Name FROM Test_Cycle_Book__c
            WHERE Test_Cycle__c = :cycleId ORDER BY Test_Book__r.Name
        ]) {
            JunctionDTO j = new JunctionDTO();
            j.junctionId = junction.Id;
            j.targetId = junction.Test_Book__c;
            j.label = junction.Test_Book__r.Name;
            dto.attachedBooks.add(j);
            attachedBookIds.add(junction.Test_Book__c);
        }
        for (Test_Book__c book : [
            SELECT Id, Name, Case_Count__c FROM Test_Book__c
            WHERE Id NOT IN :attachedBookIds ORDER BY Name LIMIT 500
        ]) {
            JunctionDTO j = new JunctionDTO();
            j.targetId = book.Id;
            j.label = book.Name;
            j.sublabel = (book.Case_Count__c == null ? 0 : (Integer) book.Case_Count__c) + ' case(s)';
            dto.availableBooks.add(j);
        }

        Set<Id> directCaseIds = new Set<Id>();
        for (Test_Cycle_Case__c direct : [
            SELECT Id, Test_Case__c, Test_Case__r.Case_ID__c, Test_Case__r.Title__c,
                Test_Case__r.Module__r.Name
            FROM Test_Cycle_Case__c
            WHERE Test_Cycle__c = :cycleId ORDER BY Test_Case__r.Case_ID__c
        ]) {
            JunctionDTO j = new JunctionDTO();
            j.junctionId = direct.Id;
            j.targetId = direct.Test_Case__c;
            j.label = direct.Test_Case__r.Case_ID__c;
            j.title = direct.Test_Case__r.Title__c;
            j.sublabel = direct.Test_Case__r.Module__r.Name;
            dto.directCases.add(j);
            directCaseIds.add(direct.Test_Case__c);
        }
        // Only finished definitions can enter scope — a Draft case in scope
        // would instantly become runnable work in tester queues.
        for (Test_Case__c candidate : [
            SELECT Id, Case_ID__c, Title__c, Module__r.Name, Module__r.Module_Group__r.System__c
            FROM Test_Case__c
            WHERE Id NOT IN :directCaseIds
            AND Creation_Status__c = :UatConstants.CREATION_COMPLETE
            ORDER BY Case_ID__c LIMIT 500
        ]) {
            JunctionDTO j = new JunctionDTO();
            j.targetId = candidate.Id;
            j.label = candidate.Case_ID__c;
            j.title = candidate.Title__c;
            j.sublabel = candidate.Module__r.Name;
            j.systemId = candidate.Module__r.Module_Group__r.System__c;
            dto.availableCases.add(j);
        }

        dto.scopeRows = buildScopeRows(cycleId);
        return dto;
    }

    // ---- Writes ---------------------------------------------------------------

    @AuraEnabled
    public static Id saveCycle(String inputJson) {
        assertCycleAdmin();
        CycleInput input;
        try {
            input = String.isBlank(inputJson)
                ? null
                : (CycleInput) JSON.deserialize(inputJson, CycleInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (input == null || String.isBlank(input.name)) {
            throw auraError('Give the cycle a name.');
        }
        // Upper bound = the fields' precision (3,0). Validated here so an
        // out-of-range value gets a readable message, not a raw DML error.
        if (input.maxTesters != null && (input.maxTesters < 1 || input.maxTesters > 999)) {
            throw auraError('Max Testers must be between 1 and 999.');
        }
        if (input.claimLimitPerTester != null
            && (input.claimLimitPerTester < 1 || input.claimLimitPerTester > 999)) {
            throw auraError('The claim limit must be between 1 and 999 (leave it blank for no limit).');
        }
        if (input.staleClaimDays != null
            && (input.staleClaimDays < 1 || input.staleClaimDays > 999)) {
            throw auraError('Stale Claim Days must be between 1 and 999 (leave it blank to never auto-release).');
        }
        Test_Cycle__c record = new Test_Cycle__c(
            Id = input.id,
            Name = input.name.trim(),
            Target_Date__c = input.targetDate,
            Assigned_Team__c = input.teamId,
            Max_Testers__c = input.maxTesters == null ? 1 : input.maxTesters,
            Claim_Limit_Per_Tester__c = input.claimLimitPerTester,
            Stale_Claim_Days__c = input.staleClaimDays,
            // Blank normalizes to null so "inherit the org defaults" is one
            // state, not two (null vs. a field full of whitespace).
            Focus_Prompts__c = String.isBlank(input.focusPrompts)
                ? null : input.focusPrompts.trim()
        );
        SObjectAccessDecision decision = Security.stripInaccessible(
            record.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
            new List<Test_Cycle__c>{ record }
        );
        Test_Cycle__c stripped = (Test_Cycle__c) decision.getRecords()[0];
        if (record.Id == null) {
            insert stripped;
            record.Id = stripped.Id;
        } else {
            update stripped; // team-change propagation = the cycle trigger's job
            // Capacity may have changed: open the missing slots / retire the
            // surplus ones (design §2.2 — save-path reconcile, not a trigger).
            UatExecutionService.reconcileSeats(new Set<Id>{ record.Id });
        }
        return record.Id;
    }

    @AuraEnabled
    public static void attachBook(Id cycleId, Id bookId) {
        assertCycleAdmin();
        Integer existing = [
            SELECT COUNT() FROM Test_Cycle_Book__c
            WHERE Test_Cycle__c = :cycleId AND Test_Book__c = :bookId
        ];
        if (existing > 0) {
            throw auraError('That book is already attached to this cycle.');
        }
        insert new Test_Cycle_Book__c(Test_Cycle__c = cycleId, Test_Book__c = bookId);
    }

    @AuraEnabled
    public static void detachBook(Id junctionId) {
        assertCycleAdmin();
        delete new Test_Cycle_Book__c(Id = junctionId);
    }

    @AuraEnabled
    public static void addDirectCase(Id cycleId, Id caseId) {
        assertCycleAdmin();
        assertCaseComplete(caseId);
        Integer existing = [
            SELECT COUNT() FROM Test_Cycle_Case__c
            WHERE Test_Cycle__c = :cycleId AND Test_Case__c = :caseId
        ];
        if (existing > 0) {
            throw auraError('That case is already added directly to this cycle.');
        }
        insert new Test_Cycle_Case__c(Test_Cycle__c = cycleId, Test_Case__c = caseId);
    }

    /** Server-side backstop for the candidate-list filter: only finished
     *  definitions enter scope (they become runnable work immediately). */
    private static void assertCaseComplete(Id caseId) {
        List<Test_Case__c> found = [
            SELECT Creation_Status__c FROM Test_Case__c WHERE Id = :caseId
        ];
        if (found.isEmpty() || found[0].Creation_Status__c != UatConstants.CREATION_COMPLETE) {
            throw auraError('Only cases marked Complete can be added — testers would see this one immediately.');
        }
    }

    /** Active / Claims Paused / Closed. Pausing stops new claims while
     *  in-flight work continues; closing hides the cycle from tester queues.
     *  Nothing is deleted, and reopening restores it exactly as it was. */
    @AuraEnabled
    public static void setCycleStatus(Id cycleId, String status) {
        assertCycleAdmin();
        if (status != UatConstants.CYCLE_ACTIVE && status != UatConstants.CYCLE_CLAIMS_PAUSED && status != UatConstants.CYCLE_CLOSED) {
            throw auraError('Unknown cycle status.');
        }
        update new Test_Cycle__c(Id = cycleId, Status__c = status);
    }

    /** Admin force-unassign (design §3.2): same release state machine as a
     *  tester's own release, different audit action. Reason required. */
    @AuraEnabled
    public static void forceUnassign(String inputJson) {
        assertCycleAdmin();
        SeatActionInput input = parseSeatAction(inputJson);
        try {
            UatExecutionService.releaseSeat(
                input.executionId, UserInfo.getUserId(), input.reason, UatConstants.EVENT_FORCE_UNASSIGNED);
        } catch (UatExecutionService.UatExecutionException e) {
            throw auraError(e.getMessage());
        }
    }

    /** Admin reassignment (design §3.2): frees the old tester's seat and hands
     *  the new tester their own independent execution — never relabels. */
    @AuraEnabled
    public static ExecutionChipDTO reassignTester(String inputJson) {
        assertCycleAdmin();
        SeatActionInput input = parseSeatAction(inputJson);
        if (input.newTesterId == null) {
            throw auraError('Pick a tester to reassign to.');
        }
        try {
            Test_Execution__c fresh = UatExecutionService.reassignSeat(
                input.executionId, input.newTesterId, UserInfo.getUserId(), input.reason);
            Test_Execution__c loaded = [
                SELECT Id, Assigned_Tester__c, Assigned_Tester__r.Name,
                    Testing_Status__c, Testing_Result__c, Released__c, Claimed_Date__c
                FROM Test_Execution__c WHERE Id = :fresh.Id
            ];
            return toChip(loaded);
        } catch (UatExecutionService.UatExecutionException e) {
            throw auraError(e.getMessage());
        }
    }

    private static SeatActionInput parseSeatAction(String inputJson) {
        SeatActionInput input;
        try {
            input = String.isBlank(inputJson)
                ? null
                : (SeatActionInput) JSON.deserialize(inputJson, SeatActionInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (input == null || input.executionId == null) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (String.isBlank(input.reason)) {
            throw auraError('Give a short reason — it goes in the assignment log.');
        }
        return input;
    }

    /** "Same scope, next sprint": copies the cycle (same team, BLANK target
     *  date — a new run gets its own date) and its book/direct-case junctions.
     *  The junction triggers materialize fresh unclaimed slots. */
    @AuraEnabled
    public static Id cloneCycle(Id cycleId) {
        assertCycleAdmin();
        Test_Cycle__c source;
        try {
            source = [
                SELECT Name, Assigned_Team__c FROM Test_Cycle__c WHERE Id = :cycleId
            ];
        } catch (QueryException e) {
            throw auraError('That test cycle no longer exists.');
        }
        Test_Cycle__c copy = new Test_Cycle__c(
            Name = (source.Name + ' (copy)').left(120),
            Assigned_Team__c = source.Assigned_Team__c
        );
        insert copy;
        List<Test_Cycle_Book__c> bookJunctions = new List<Test_Cycle_Book__c>();
        for (Test_Cycle_Book__c junction : [
            SELECT Test_Book__c FROM Test_Cycle_Book__c WHERE Test_Cycle__c = :cycleId
        ]) {
            bookJunctions.add(new Test_Cycle_Book__c(
                Test_Cycle__c = copy.Id, Test_Book__c = junction.Test_Book__c
            ));
        }
        if (!bookJunctions.isEmpty()) {
            insert bookJunctions;
        }
        List<Test_Cycle_Case__c> caseJunctions = new List<Test_Cycle_Case__c>();
        for (Test_Cycle_Case__c junction : [
            SELECT Test_Case__c FROM Test_Cycle_Case__c WHERE Test_Cycle__c = :cycleId
        ]) {
            caseJunctions.add(new Test_Cycle_Case__c(
                Test_Cycle__c = copy.Id, Test_Case__c = junction.Test_Case__c
            ));
        }
        if (!caseJunctions.isEmpty()) {
            insert caseJunctions;
        }
        return copy.Id;
    }

    @AuraEnabled
    public static void removeDirectCase(Id junctionId) {
        assertCycleAdmin();
        delete new Test_Cycle_Case__c(Id = junctionId);
    }

    // ---- Delete (2026-08-05: admins can delete everything; Closed stays the
    //      archive state and the recommended path — deleteCycle is the
    //      destructive alternative) -------------------------------------------------

    public class CycleDeleteImpactDTO {
        @AuraEnabled public String cycleName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer executions;   // total runs purged
        @AuraEnabled public Integer claimedRuns;  // Assigned_Tester__c != null — the scary number
        @AuraEnabled public Integer stepResults;
        @AuraEnabled public Integer sessions;
        @AuraEnabled public Integer findings;
        @AuraEnabled public Integer bookLinks;
        @AuraEnabled public Integer directCases;
    }

    /** Honest numbers for the delete confirm, counted at click time — the
     *  list rows' counts are load-time stale. */
    @AuraEnabled
    public static CycleDeleteImpactDTO getCycleDeleteImpact(Id cycleId) {
        assertCyclesReadable();
        Test_Cycle__c cycle;
        try {
            cycle = [SELECT Name, Status__c FROM Test_Cycle__c WHERE Id = :cycleId];
        } catch (QueryException e) {
            throw auraError('That test cycle no longer exists.');
        }
        CycleDeleteImpactDTO dto = new CycleDeleteImpactDTO();
        dto.cycleName = cycle.Name;
        dto.status = cycle.Status__c == null ? UatConstants.CYCLE_ACTIVE : cycle.Status__c;
        dto.executions = [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycleId];
        dto.claimedRuns = [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c != null AND Released__c = false
        ];
        dto.stepResults = [
            SELECT COUNT() FROM Test_Step_Result__c
            WHERE Test_Execution__r.Test_Cycle__c = :cycleId
        ];
        dto.sessions = [SELECT COUNT() FROM Exploratory_Session__c WHERE Test_Cycle__c = :cycleId];
        dto.findings = [SELECT COUNT() FROM Exploratory_Finding__c WHERE Test_Cycle__c = :cycleId];
        dto.bookLinks = [SELECT COUNT() FROM Test_Cycle_Book__c WHERE Test_Cycle__c = :cycleId];
        dto.directCases = [SELECT COUNT() FROM Test_Cycle_Case__c WHERE Test_Cycle__c = :cycleId];
        return dto;
    }

    /**
     * Purge-then-delete: executions, sessions, and findings all restrict the
     * cycle delete (deleting would otherwise relabel them "Standalone" —
     * standalone is a deliberate state, not a deletion artifact), so all
     * three are purged explicitly first — this is the one flow that destroys
     * them, and the UI's confirm carries the counts. The cycle delete then
     * cascades junctions (their triggers find no executions left — no-op).
     * Audit rows survive with nulled lookups; evidence documents stay in
     * their uploaders' Files (deleting other users' docs throws).
     */
    @AuraEnabled
    public static void deleteCycle(Id cycleId) {
        assertCycleAdmin();
        if (!Schema.sObjectType.Test_Cycle__c.isDeletable()
            || !Schema.sObjectType.Test_Execution__c.isDeletable()) {
            throw auraError('You do not have access to delete test cycles.');
        }
        Integer executions;
        try {
            executions = [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycleId];
        } catch (QueryException e) {
            throw auraError('That test cycle no longer exists.');
        }
        // Direct deletes count toward the 10k DML-row transaction ceiling
        // (cascaded children don't) — refuse rather than blow up mid-purge.
        if (executions > 9000) {
            throw auraError('This cycle has too many runs to purge in one go — detach its books to shrink scope, then retry.');
        }
        UatExecutionService.purgeCycleExecutions(cycleId);
        // Findings before sessions: dropping a session first would SetNull
        // its findings' session link and orphan them mid-purge.
        delete [SELECT Id FROM Exploratory_Finding__c WHERE Test_Cycle__c = :cycleId];
        delete [SELECT Id FROM Exploratory_Session__c WHERE Test_Cycle__c = :cycleId];
        try {
            delete new Test_Cycle__c(Id = cycleId);
        } catch (DmlException e) {
            throw auraError('The cycle could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    /** 03 §5: creates an ADDITIONAL, fully independent execution. */
    @AuraEnabled
    public static ExecutionChipDTO addTesterExecution(Id cycleId, Id caseId, Id userId) {
        assertCycleAdmin();
        try {
            Test_Execution__c fresh =
                UatExecutionService.createIndependentExecution(cycleId, caseId, userId);
            Test_Execution__c loaded = [
                SELECT Id, Assigned_Tester__c, Assigned_Tester__r.Name,
                    Testing_Status__c, Testing_Result__c, Released__c, Claimed_Date__c
                FROM Test_Execution__c WHERE Id = :fresh.Id
            ];
            return toChip(loaded);
        } catch (UatExecutionService.UatExecutionException e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Internals -------------------------------------------------------------

    private static List<ScopeRowDTO> buildScopeRows(Id cycleId) {
        Map<Id, UatScopeService.ScopeEntry> scope =
            UatScopeService.effectiveScope(new Set<Id>{ cycleId }).get(cycleId);

        Map<Id, Test_Case__c> cases = new Map<Id, Test_Case__c>([
            SELECT Id, Case_ID__c, Title__c, Module__r.Name
            FROM Test_Case__c WHERE Id IN :scope.keySet()
        ]);
        Map<Id, List<ExecutionChipDTO>> chipsByCase = new Map<Id, List<ExecutionChipDTO>>();
        for (Test_Execution__c e : [
            SELECT Id, Test_Case__c, Assigned_Tester__c, Assigned_Tester__r.Name,
                Testing_Status__c, Testing_Result__c, Released__c, Claimed_Date__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId
            ORDER BY CreatedDate
        ]) {
            if (!chipsByCase.containsKey(e.Test_Case__c)) {
                chipsByCase.put(e.Test_Case__c, new List<ExecutionChipDTO>());
            }
            chipsByCase.get(e.Test_Case__c).add(toChip(e));
        }

        List<ScopeRowDTO> rows = new List<ScopeRowDTO>();
        for (Id caseId : scope.keySet()) {
            Test_Case__c c = cases.get(caseId);
            if (c == null) {
                continue;
            }
            ScopeRowDTO row = new ScopeRowDTO();
            row.caseId = caseId;
            row.caseCode = c.Case_ID__c;
            row.title = c.Title__c;
            row.moduleName = c.Module__r.Name;
            row.sourceLabel = String.join(scope.get(caseId).sources, ', ');
            if (chipsByCase.containsKey(caseId)) {
                row.executions = chipsByCase.get(caseId);
            }
            rows.add(row);
        }
        // Stable display: by case code.
        rows.sort(new ScopeRowComparator());
        return rows;
    }

    private class ScopeRowComparator implements Comparator<ScopeRowDTO> {
        public Integer compare(ScopeRowDTO a, ScopeRowDTO b) {
            String left = a.caseCode == null ? '' : a.caseCode;
            String right = b.caseCode == null ? '' : b.caseCode;
            return left.compareTo(right);
        }
    }

    private static ExecutionChipDTO toChip(Test_Execution__c e) {
        ExecutionChipDTO chip = new ExecutionChipDTO();
        chip.id = e.Id;
        chip.testerId = e.Assigned_Tester__c;
        chip.testerName = e.Assigned_Tester__r != null ? e.Assigned_Tester__r.Name : null;
        chip.status = e.Testing_Status__c;
        chip.result = e.Testing_Result__c;
        chip.released = e.Released__c;
        chip.claimedDate = e.Claimed_Date__c;
        return chip;
    }

    private static void assertCycleAdmin() {
        if (!Schema.sObjectType.Test_Cycle__c.isCreateable()
            || !Schema.sObjectType.Test_Cycle__c.isUpdateable()) {
            throw auraError('You do not have access to manage test cycles.');
        }
    }

    private static void assertCyclesReadable() {
        if (!Schema.sObjectType.Test_Cycle__c.isAccessible()
            || !Schema.sObjectType.Test_Execution__c.isAccessible()) {
            throw auraError('You do not have access to test cycles.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}