/**
 * UatCaseAdminController
 *
 * Apex behind the Admin Console's UAT Test Cases section (adminUatCases):
 * the case list, the New Case modal (cascading taxonomy + live Case ID
 * preview via getNextSequence), and the case detail page's Steps and
 * Reference Material tabs.
 *
 * Execution-related reads (the "Viewing run" selector, latest-run columns,
 * the Evidence tab) land with the execution engine phase — the DTOs carry
 * those fields from day one so the UI contract doesn't churn.
 *
 * Behavioral notes from the spec (02/03 docs):
 *  - Test_Condition__c is a group label; renames flow through saveSteps
 *    (the UI rewrites the group in one save — the old renameCondition
 *    endpoint was dead and removed 2026-08-04).
 *  - Step deletion is cross-execution data loss (03 §9). The trigger-based
 *    cascade ships with the engine phase; the UI confirmation wording warns
 *    from day one.
 *  - Module is editable after create (2026-08-12) via saveCase or the bulk
 *    moveCasesToModule; both go through applyModuleMove, which re-sequences
 *    into the destination so two cases can never render one Case ID.
 *
 * Conventions: with sharing, describe asserts + stripInaccessible,
 * AuraHandledException, JSON-string write payloads (org quirk).
 */
public with sharing class UatCaseAdminController {

    /** Cap on one bulk module move. Well inside the DML row limit; the point
     *  is a plain-language refusal instead of a governor limit. */
    private static final Integer MOVE_BATCH_LIMIT = 200;

    // ---- DTOs ----------------------------------------------------------------

    public class CaseRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseCode;      // Case_ID__c
        @AuraEnabled public String title;         // Title__c — human-readable, may be blank
        @AuraEnabled public String moduleName;
        @AuraEnabled public Id systemId;
        @AuraEnabled public String systemName;
        @AuraEnabled public String creationStatus;
        // Execution-derived columns; null until the engine phase fills them.
        @AuraEnabled public String latestRunLabel;
        @AuraEnabled public Integer executionCount;
        @AuraEnabled public String assignedLabel;
        @AuraEnabled public String testingStatus;
        @AuraEnabled public String testingResult;
    }

    public class StepDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal stepNumber;
        @AuraEnabled public String title;       // optional per-step name
        @AuraEnabled public String condition;
        @AuraEnabled public String description;
        @AuraEnabled public String expected;
        @AuraEnabled public Boolean isExplore;
        @AuraEnabled public String explorePrompt;
    }

    public class RefMaterialDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String type;
        @AuraEnabled public String label;
        @AuraEnabled public String url;
        @AuraEnabled public UatFileService.FileDTO file; // File rows: newest attached file
    }

    /** A book this case is in RIGHT NOW (one Test_Book_Item__c row), for the
     *  detail page's membership chips. bookItemId is the handle
     *  UatBookAdminController.removeCaseFromBook takes. */
    public class BookMembershipDTO {
        @AuraEnabled public Id bookItemId;
        @AuraEnabled public Id bookId;
        @AuraEnabled public String bookName;
    }

    public class CaseDetailDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseCode;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public Id moduleId;
        @AuraEnabled public String moduleName;
        @AuraEnabled public Id groupId;
        @AuraEnabled public String groupName;
        @AuraEnabled public Id systemId;
        @AuraEnabled public String systemName;
        @AuraEnabled public String systemCode;   // leading Case_ID__c segment
        @AuraEnabled public String version;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String creationStatus;
        @AuraEnabled public String testingSurface;
        @AuraEnabled public String priority;
        @AuraEnabled public String estimatedEffort;
        @AuraEnabled public Integer maxTestersOverride; // null = inherit cycle default
        @AuraEnabled public String authorName;
        @AuraEnabled public Id targetBookId;        // pending "add on Complete"
        @AuraEnabled public String targetBookName;
        /** The books this case is in NOW — deliberately separate from
         *  targetBookId, which is a pending pointer that clears itself the
         *  moment it fires and so can never answer "where is this case?". */
        @AuraEnabled public List<BookMembershipDTO> books = new List<BookMembershipDTO>();
        @AuraEnabled public String preConditions;
        @AuraEnabled public List<StepDTO> steps = new List<StepDTO>();
        @AuraEnabled public List<RefMaterialDTO> refMaterials = new List<RefMaterialDTO>();
    }

    public class CaseInput {
        public Id id;                // null = create
        public String title;
        public String description;
        public Id moduleId;
        public String version;
        public Decimal sequence;     // editable suggested sequence from the modal
        public String testingSurface;
        public String creationStatus;
        public String priority;
        public String estimatedEffort;
        public Integer maxTestersOverride;
        public Id targetBookId;
        public String preConditions;
    }

    public class StepsInput {
        public Id caseId;
        public List<StepInput> steps = new List<StepInput>();
    }

    public class StepInput {
        public Id id;                // null = create
        public String title;
        public String condition;
        public String description;
        public String expected;
        public Boolean isExplore;
        public String explorePrompt;
    }

    public class RefLinkInput {
        public Id id;                // null = create
        public Id caseId;
        public String label;
        public String url;
    }

    // ---- Reads ---------------------------------------------------------------

    /** All cases (bounded); search/System/status filtering happens client-side
     *  per console convention (adminArticleList). The Latest Run / Assigned /
     *  Status / Result columns reflect each case's most recently touched
     *  execution, with a count chip when more exist. */
    @AuraEnabled
    public static List<CaseRowDTO> getCaseList() {
        assertCasesReadable();
        List<CaseRowDTO> rows = new List<CaseRowDTO>();
        Map<Id, CaseRowDTO> byCase = new Map<Id, CaseRowDTO>();
        for (Test_Case__c c : [
            SELECT Id, Case_ID__c, Title__c, Creation_Status__c,
                Module__r.Name,
                Module__r.Module_Group__r.System__c,
                Module__r.Module_Group__r.System__r.Name
            FROM Test_Case__c
            ORDER BY Case_ID__c
            LIMIT 500
        ]) {
            CaseRowDTO row = new CaseRowDTO();
            row.id = c.Id;
            row.caseCode = c.Case_ID__c;
            row.title = c.Title__c;
            row.moduleName = c.Module__r.Name;
            row.systemId = c.Module__r.Module_Group__r.System__c;
            row.systemName = c.Module__r.Module_Group__r.System__r.Name;
            row.creationStatus = c.Creation_Status__c;
            row.executionCount = 0;
            rows.add(row);
            byCase.put(c.Id, row);
        }
        // Most recently modified execution per case drives the display.
        for (Test_Execution__c e : [
            SELECT Test_Case__c, Test_Cycle__r.Name,
                Assigned_Team__r.Name, Assigned_Tester__r.Name,
                Testing_Status__c, Testing_Result__c
            FROM Test_Execution__c
            WHERE Test_Case__c IN :byCase.keySet()
            ORDER BY LastModifiedDate DESC
            LIMIT 2000
        ]) {
            CaseRowDTO row = byCase.get(e.Test_Case__c);
            row.executionCount++;
            if (row.latestRunLabel == null) {
                String cycleLabel = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : 'Standalone';
                String testerLabel = e.Assigned_Tester__r != null
                    ? e.Assigned_Tester__r.Name
                    : (e.Assigned_Team__r != null
                        ? 'Unclaimed (' + e.Assigned_Team__r.Name + ')'
                        : 'Unclaimed');
                row.latestRunLabel = cycleLabel + ' — ' + testerLabel;
                row.assignedLabel = testerLabel;
                row.testingStatus = e.Testing_Status__c;
                row.testingResult = e.Testing_Result__c;
            }
        }
        return rows;
    }

    /** Live Case ID preview in the New Case modal: next sequence per module. */
    @AuraEnabled
    public static Integer getNextSequence(Id moduleId) {
        assertCasesReadable();
        if (moduleId == null) {
            return 1001;
        }
        List<Test_Case__c> maxCase = [
            SELECT Sequence__c FROM Test_Case__c
            WHERE Module__c = :moduleId AND Sequence__c != null
            ORDER BY Sequence__c DESC
            LIMIT 1
        ];
        return maxCase.isEmpty() ? 1001 : (Integer) maxCase[0].Sequence__c + 1;
    }

    @AuraEnabled
    public static CaseDetailDTO getCaseDetail(Id caseId) {
        assertCasesReadable();
        Test_Case__c c;
        try {
            c = [
                SELECT Id, Case_ID__c, Title__c, Description__c, Pre_Conditions__c,
                    Version__c, Sequence__c, Creation_Status__c,
                    Testing_Surface__c, Priority__c, Estimated_Effort__c,
                    Max_Testers_Override__c, Author__r.Name,
                    Target_Book__c, Target_Book__r.Name,
                    Module__c, Module__r.Name,
                    Module__r.Module_Group__c, Module__r.Module_Group__r.Name,
                    Module__r.Module_Group__r.System__c,
                    Module__r.Module_Group__r.System__r.Name,
                    Module__r.Module_Group__r.System__r.System_Code__c
                FROM Test_Case__c
                WHERE Id = :caseId
            ];
        } catch (QueryException e) {
            throw auraError('That test case no longer exists.');
        }
        CaseDetailDTO dto = new CaseDetailDTO();
        dto.id = c.Id;
        dto.caseCode = c.Case_ID__c;
        dto.title = c.Title__c;
        dto.description = c.Description__c;
        dto.preConditions = c.Pre_Conditions__c;
        dto.moduleId = c.Module__c;
        dto.moduleName = c.Module__r.Name;
        dto.groupId = c.Module__r.Module_Group__c;
        dto.groupName = c.Module__r.Module_Group__r.Name;
        dto.systemId = c.Module__r.Module_Group__r.System__c;
        dto.systemName = c.Module__r.Module_Group__r.System__r.Name;
        dto.systemCode = c.Module__r.Module_Group__r.System__r.System_Code__c;
        dto.version = c.Version__c;
        dto.sequence = c.Sequence__c;
        dto.creationStatus = c.Creation_Status__c;
        dto.testingSurface = c.Testing_Surface__c;
        dto.priority = c.Priority__c;
        dto.estimatedEffort = c.Estimated_Effort__c;
        dto.maxTestersOverride = c.Max_Testers_Override__c == null
            ? null : Integer.valueOf(c.Max_Testers_Override__c);
        dto.authorName = c.Author__r != null ? c.Author__r.Name : null;
        dto.targetBookId = c.Target_Book__c;
        dto.targetBookName = c.Target_Book__r != null ? c.Target_Book__r.Name : null;

        for (Test_Book_Item__c item : [
            SELECT Id, Test_Book__c, Test_Book__r.Name
            FROM Test_Book_Item__c
            WHERE Test_Case__c = :caseId
            ORDER BY Test_Book__r.Name
        ]) {
            BookMembershipDTO bm = new BookMembershipDTO();
            bm.bookItemId = item.Id;
            bm.bookId = item.Test_Book__c;
            bm.bookName = item.Test_Book__r.Name;
            dto.books.add(bm);
        }

        for (Test_Step__c s : [
            SELECT Id, Step_Number__c, Step_Title__c, Test_Condition__c, Step_Description__c,
                Expected_Result__c, Is_Explore__c, Explore_Prompt__c
            FROM Test_Step__c
            WHERE Test_Case__c = :caseId
            ORDER BY Step_Number__c
        ]) {
            dto.steps.add(toStepDTO(s));
        }

        List<Reference_Material__c> refs = [
            SELECT Id, Type__c, Label__c, URL__c
            FROM Reference_Material__c
            WHERE Test_Case__c = :caseId
            ORDER BY CreatedDate
        ];
        Set<Id> refIds = new Map<Id, Reference_Material__c>(refs).keySet();
        Map<Id, List<UatFileService.FileDTO>> filesByRef = UatFileService.getFilesFor(refIds);
        for (Reference_Material__c r : refs) {
            RefMaterialDTO rd = new RefMaterialDTO();
            rd.id = r.Id;
            rd.type = r.Type__c;
            rd.label = r.Label__c;
            rd.url = r.URL__c;
            List<UatFileService.FileDTO> files = filesByRef.get(r.Id);
            rd.file = (files != null && !files.isEmpty()) ? files[0] : null; // newest wins
            dto.refMaterials.add(rd);
        }
        return dto;
    }

    // ---- Case + step writes -----------------------------------------------------

    @AuraEnabled
    public static Id saveCase(String inputJson) {
        assertCaseAdmin();
        CaseInput input = (CaseInput) parse(inputJson, CaseInput.class);
        if (input.id == null && input.moduleId == null) {
            throw auraError('Pick a module — the Case ID is built from it.');
        }
        if (String.isBlank(input.version)) {
            throw auraError('Version is required — it becomes part of the Case ID.');
        }
        if (input.maxTestersOverride != null
            && (input.maxTestersOverride < 1 || input.maxTestersOverride > 999)) {
            throw auraError('Max Testers must be between 1 and 999 (leave it blank to inherit the cycle default).');
        }
        Test_Case__c record = new Test_Case__c(
            Id = input.id,
            Title__c = String.isBlank(input.title) ? null : input.title.trim(),
            Description__c = String.isBlank(input.description) ? null : input.description.trim(),
            Pre_Conditions__c = String.isBlank(input.preConditions) ? null : input.preConditions.trim(),
            Version__c = input.version.trim(),
            Sequence__c = input.sequence,
            Testing_Surface__c = input.testingSurface,
            Creation_Status__c = String.isBlank(input.creationStatus) ? 'Draft' : input.creationStatus,
            Estimated_Effort__c = String.isBlank(input.estimatedEffort) ? null : input.estimatedEffort,
            Max_Testers_Override__c = input.maxTestersOverride,
            Target_Book__c = input.targetBookId
        );
        // Blank priority defaults on create but never clobbers an existing
        // value on update (the detail editor always round-trips it).
        if (String.isNotBlank(input.priority)) {
            record.Priority__c = input.priority;
        } else if (input.id == null) {
            record.Priority__c = 'Medium';
        }
        if (input.id == null) {
            record.Module__c = input.moduleId;
            record.Author__c = UserInfo.getUserId();
        } else if (input.moduleId != null) {
            // Module was create-only until 2026-08-12: a case filed under the
            // wrong module had no way out of it but deletion. The detail editor
            // round-trips moduleId on every save, so only a real CHANGE moves.
            Test_Case__c existing = [SELECT Module__c FROM Test_Case__c WHERE Id = :input.id];
            if (existing.Module__c != input.moduleId) {
                applyModuleMove(record, input.moduleId, null);
            }
        }
        upsertStripped(record);
        // Deferred book add fires before seat reconciliation so the book-item
        // trigger materializes slots against the true scope first.
        processTargetBook(record.Id);
        if (input.id != null) {
            // The override may have changed: settle slots in every open cycle
            // this case runs in (design §2.2).
            UatExecutionService.reconcileSeatsForCase(record.Id);
        }
        return record.Id;
    }

    /**
     * Re-files a case under a different module, in place on `record`.
     *
     * Case_ID__c is a formula over the taxonomy, so the code follows the move
     * on its own — but Sequence__c is numbered PER MODULE, so carrying the old
     * number across can land on a case already sitting on it in the
     * destination, and a formula field cannot be made unique. Every move
     * therefore takes a fresh sequence: the Case ID changes, which is the
     * honest outcome of moving, and Name (TC-00042) stays the stable key.
     *
     * `sequence` lets a caller moving several cases at once hand out
     * consecutive numbers — getNextSequence() reads committed rows, so it
     * returns the SAME number for every case inside one transaction.
     */
    private static void applyModuleMove(Test_Case__c record, Id newModuleId, Integer sequence) {
        assertModuleWritable();
        record.Module__c = newModuleId;
        record.Sequence__c = sequence != null ? sequence : getNextSequence(newModuleId);
    }

    /**
     * Bulk re-file for the list's checkbox selection — re-filing a module's
     * worth of cases one detail page at a time was the original complaint.
     * Returns how many actually moved (cases already in the destination are
     * skipped rather than needlessly re-sequenced).
     */
    @AuraEnabled
    public static Integer moveCasesToModule(List<Id> caseIds, Id moduleId) {
        assertCaseAdmin();
        if (moduleId == null) {
            throw auraError('Pick a destination module.');
        }
        if (caseIds == null || caseIds.isEmpty()) {
            throw auraError('Select at least one test case to move.');
        }
        if (caseIds.size() > MOVE_BATCH_LIMIT) {
            throw auraError('Move up to ' + MOVE_BATCH_LIMIT + ' cases at a time — '
                + caseIds.size() + ' are selected.');
        }
        if ([SELECT COUNT() FROM Module__c WHERE Id = :moduleId] == 0) {
            throw auraError('That module no longer exists — reload and try again.');
        }
        Integer sequence = getNextSequence(moduleId);
        List<Test_Case__c> moving = new List<Test_Case__c>();
        for (Test_Case__c c : [SELECT Id, Module__c FROM Test_Case__c WHERE Id IN :caseIds]) {
            if (c.Module__c == moduleId) {
                continue;
            }
            applyModuleMove(c, moduleId, sequence);
            sequence++;
            moving.add(c);
        }
        if (moving.isEmpty()) {
            return 0;
        }
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, moving);
            update decision.getRecords();
        } catch (DmlException e) {
            throw auraError('The cases could not be moved: ' + e.getDmlMessage(0));
        }
        return moving.size();
    }

    /** Deferred book membership: a case carrying Target_Book__c is appended
     *  to that book the moment it is Complete, and the pointer is cleared.
     *  Idempotent — an already-present case just clears the pointer. */
    private static void processTargetBook(Id caseId) {
        Test_Case__c c = [
            SELECT Target_Book__c, Creation_Status__c FROM Test_Case__c WHERE Id = :caseId
        ];
        if (c.Target_Book__c == null
            || c.Creation_Status__c != UatConstants.CREATION_COMPLETE) {
            return;
        }
        UatBookAdminController.addCaseIfAbsent(c.Target_Book__c, caseId);
        update new Test_Case__c(Id = caseId, Target_Book__c = null);
    }

    /**
     * Batch upsert of a case's steps. Step order = array order; Step_Number__c
     * is renumbered 1..n so drag-free inserts (Add Step / Add Condition /
     * Add Exploratory Note) stay stable.
     */
    @AuraEnabled
    public static List<StepDTO> saveSteps(String inputJson) {
        assertCaseAdmin();
        StepsInput input = (StepsInput) parse(inputJson, StepsInput.class);
        if (input.caseId == null) {
            throw auraError('Missing case — refresh and try again.');
        }
        List<Test_Step__c> toInsert = new List<Test_Step__c>();
        List<Test_Step__c> toUpdate = new List<Test_Step__c>();
        Integer stepNo = 1;
        for (StepInput s : input.steps) {
            Boolean explore = s.isExplore == true;
            Test_Step__c row = new Test_Step__c(
                Id = s.id,
                Step_Number__c = stepNo++,
                Step_Title__c = String.isBlank(s.title) ? null : s.title.trim(),
                Test_Condition__c = s.condition,
                Step_Description__c = explore ? null : s.description,
                Expected_Result__c = explore ? null : s.expected,
                Is_Explore__c = explore,
                Explore_Prompt__c = explore ? s.explorePrompt : null
            );
            if (s.id == null) {
                // Master-detail is set on insert only — it can't change on update.
                row.Test_Case__c = input.caseId;
                toInsert.add(row);
            } else {
                toUpdate.add(row);
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        List<StepDTO> result = new List<StepDTO>();
        for (Test_Step__c s : [
            SELECT Id, Step_Number__c, Step_Title__c, Test_Condition__c, Step_Description__c,
                Expected_Result__c, Is_Explore__c, Explore_Prompt__c
            FROM Test_Step__c
            WHERE Test_Case__c = :input.caseId
            ORDER BY Step_Number__c
        ]) {
            result.add(toStepDTO(s));
        }
        return result;
    }

    /**
     * Deletes one step. The cross-execution Test_Step_Result__c cascade is the
     * step trigger's job (engine phase) so every delete path is covered — the
     * UI confirmation wording warns about the cross-cycle loss.
     */
    @AuraEnabled
    public static void deleteStep(Id stepId) {
        assertCaseAdmin();
        if (!Schema.sObjectType.Test_Step__c.isDeletable()) {
            throw auraError('You do not have access to remove steps.');
        }
        delete new Test_Step__c(Id = stepId);
    }

    // ---- Reference material -------------------------------------------------------

    @AuraEnabled
    public static Id saveReferenceLink(String inputJson) {
        assertCaseAdmin();
        RefLinkInput input = (RefLinkInput) parse(inputJson, RefLinkInput.class);
        if (String.isBlank(input.label) || String.isBlank(input.url)) {
            throw auraError('Links need both a label and a URL.');
        }
        Reference_Material__c record = new Reference_Material__c(
            Id = input.id,
            Type__c = 'Link',
            Label__c = input.label.trim(),
            URL__c = input.url.trim()
        );
        if (input.id == null) {
            if (input.caseId == null) {
                throw auraError('Missing case — refresh and try again.');
            }
            record.Test_Case__c = input.caseId;
        }
        upsertStripped(record);
        return record.Id;
    }

    /** Shell row a file upload attaches to; label set from the filename after
     *  upload via registerReferenceUpload. */
    @AuraEnabled
    public static Id createReferenceFile(Id caseId) {
        assertCaseAdmin();
        if (caseId == null) {
            throw auraError('Missing case — refresh and try again.');
        }
        Reference_Material__c record = new Reference_Material__c(
            Test_Case__c = caseId,
            Type__c = 'File'
        );
        insert record;
        return record.Id;
    }

    /** After lightning-file-upload finishes on a File-type row: normalize
     *  visibility and label the row from the file title. */
    @AuraEnabled
    public static void registerReferenceUpload(Id refId, List<String> contentDocumentIds) {
        assertCaseAdmin();
        List<Id> docIds = new List<Id>();
        for (String s : contentDocumentIds) {
            docIds.add((Id) s);
        }
        UatFileService.normalizeVisibility(refId, docIds);
        List<UatFileService.FileDTO> files = UatFileService.getFilesFor(refId);
        if (!files.isEmpty()) {
            update new Reference_Material__c(Id = refId, Label__c = files[0].title);
        }
    }

    /** Removes the row and any file attached to it (File rows own their file). */
    @AuraEnabled
    public static void deleteReferenceMaterial(Id refId) {
        assertCaseAdmin();
        if (!Schema.sObjectType.Reference_Material__c.isDeletable()) {
            throw auraError('You do not have access to remove reference material.');
        }
        for (UatFileService.FileDTO f : UatFileService.getFilesFor(refId)) {
            UatFileService.deleteFile(f.contentDocumentId, refId);
        }
        delete new Reference_Material__c(Id = refId);
    }

    // ---- Executions (the "Viewing run" selector + Evidence & Feedback tab) --------

    public class ExecutionOptionDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;   // null = Standalone
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;  // null = Unclaimed
        @AuraEnabled public String label;       // "[Cycle|Standalone] — [Tester|Unclaimed]"
    }

    public class StepResultViewDTO {
        @AuraEnabled public Id stepId;
        @AuraEnabled public String actualResult;
        @AuraEnabled public String result;
        @AuraEnabled public String exploreNotes;
        @AuraEnabled public List<UatFileService.FileDTO> files = new List<UatFileService.FileDTO>();
    }

    public class ExecutionViewDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public Id teamId;
        @AuraEnabled public String teamName;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
        @AuraEnabled public String status;
        @AuraEnabled public String result;
        @AuraEnabled public Date lastTestedDate;
        @AuraEnabled public Decimal uxRating;
        @AuraEnabled public String uxRecommendation;
        @AuraEnabled public List<StepResultViewDTO> stepResults = new List<StepResultViewDTO>();
        @AuraEnabled public List<UatFileService.FileDTO> caseEvidence = new List<UatFileService.FileDTO>();
    }

    /** Every execution of this case, for the detail page's run selector.
     *  Ordered by LastModifiedDate DESC to match how getCaseList picks the
     *  list's "Latest Run" — ordering by CreatedDate here let the two screens
     *  disagree about which run is the latest one. */
    @AuraEnabled
    public static List<ExecutionOptionDTO> getExecutionsForCase(Id caseId) {
        assertCasesReadable();
        List<ExecutionOptionDTO> options = new List<ExecutionOptionDTO>();
        for (Test_Execution__c e : [
            SELECT Id, Test_Cycle__c, Test_Cycle__r.Name,
                Assigned_Tester__c, Assigned_Tester__r.Name
            FROM Test_Execution__c
            WHERE Test_Case__c = :caseId
            ORDER BY LastModifiedDate DESC
        ]) {
            ExecutionOptionDTO o = new ExecutionOptionDTO();
            o.id = e.Id;
            o.cycleId = e.Test_Cycle__c;
            o.cycleName = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : null;
            o.testerId = e.Assigned_Tester__c;
            o.testerName = e.Assigned_Tester__r != null ? e.Assigned_Tester__r.Name : null;
            o.label = (o.cycleName != null ? o.cycleName : 'Standalone')
                + ' — ' + (o.testerName != null ? o.testerName : 'Unclaimed');
            options.add(o);
        }
        return options;
    }

    /** Read-only view of one run: the tester's step findings, UX feedback,
     *  and evidence. Admins author, they don't grade. */
    @AuraEnabled
    public static ExecutionViewDTO getExecutionView(Id executionId) {
        assertCasesReadable();
        Test_Execution__c e;
        try {
            e = [
                SELECT Id, Test_Cycle__c, Test_Cycle__r.Name,
                    Assigned_Team__c, Assigned_Team__r.Name,
                    Assigned_Tester__c, Assigned_Tester__r.Name,
                    Testing_Status__c, Testing_Result__c, Last_Tested_Date__c,
                    UX_Rating__c, UX_Recommendation__c
                FROM Test_Execution__c WHERE Id = :executionId
            ];
        } catch (QueryException ex) {
            throw auraError('That run no longer exists.');
        }
        ExecutionViewDTO dto = new ExecutionViewDTO();
        dto.id = e.Id;
        dto.cycleId = e.Test_Cycle__c;
        dto.cycleName = e.Test_Cycle__r != null ? e.Test_Cycle__r.Name : null;
        dto.teamId = e.Assigned_Team__c;
        dto.teamName = e.Assigned_Team__r != null ? e.Assigned_Team__r.Name : null;
        dto.testerId = e.Assigned_Tester__c;
        dto.testerName = e.Assigned_Tester__r != null ? e.Assigned_Tester__r.Name : null;
        dto.status = e.Testing_Status__c;
        dto.result = e.Testing_Result__c;
        dto.lastTestedDate = e.Last_Tested_Date__c;
        dto.uxRating = e.UX_Rating__c;
        dto.uxRecommendation = e.UX_Recommendation__c;

        List<Test_Step_Result__c> results = [
            SELECT Id, Test_Step__c, Actual_Result__c, Result__c, Explore_Notes__c
            FROM Test_Step_Result__c
            WHERE Test_Execution__c = :executionId AND Test_Step__c != null
        ];
        Set<Id> resultIds = new Map<Id, Test_Step_Result__c>(results).keySet();
        Map<Id, List<UatFileService.FileDTO>> filesByResult = UatFileService.getFilesFor(resultIds);
        for (Test_Step_Result__c r : results) {
            StepResultViewDTO v = new StepResultViewDTO();
            v.stepId = r.Test_Step__c;
            v.actualResult = r.Actual_Result__c;
            v.result = r.Result__c;
            v.exploreNotes = r.Explore_Notes__c;
            if (filesByResult.containsKey(r.Id)) {
                v.files = filesByResult.get(r.Id);
            }
            dto.stepResults.add(v);
        }
        dto.caseEvidence = UatFileService.getFilesFor(executionId);
        return dto;
    }

    /**
     * 03 §2: switching the Tester (or Team) on the detail page is NOT "rename
     * this execution" — find-or-create the execution matching the new
     * identity and return it; the page switches to displaying that one.
     */
    @AuraEnabled
    public static ExecutionOptionDTO resolveExecutionForIdentity(Id caseId, Id cycleId, Id testerId) {
        assertCaseAdmin();
        try {
            Test_Execution__c resolved =
                UatExecutionService.resolveForIdentity(caseId, cycleId, testerId);
            for (ExecutionOptionDTO o : getExecutionsForCase(caseId)) {
                if (o.id == resolved.Id) {
                    return o;
                }
            }
            throw auraError('Could not load the run — refresh and try again.');
        } catch (UatExecutionService.UatExecutionException ex) {
            throw auraError(ex.getMessage());
        }
    }

    /** Lookup-only companion to resolveExecutionForIdentity: the execution
     *  matching the triple, or null when none exists. The UI confirms with
     *  the admin before creating one — switching a dropdown to browse should
     *  never silently put work in a tester's queue. */
    @AuraEnabled
    public static ExecutionOptionDTO findExecutionForIdentity(Id caseId, Id cycleId, Id testerId) {
        assertCasesReadable();
        String key = UatExecutionService.identityKey(caseId, cycleId, testerId);
        List<Test_Execution__c> found = [
            SELECT Id FROM Test_Execution__c WHERE Identity_Key__c = :key LIMIT 1
        ];
        if (found.isEmpty()) {
            return null;
        }
        for (ExecutionOptionDTO o : getExecutionsForCase(caseId)) {
            if (o.id == found[0].Id) {
                return o;
            }
        }
        return null;
    }

    /** Members of a team, for the detail page's Tester dropdown. */
    @AuraEnabled
    public static List<ExecutionOptionDTO> getTeamMembers(Id teamId) {
        assertCasesReadable();
        List<ExecutionOptionDTO> options = new List<ExecutionOptionDTO>();
        if (teamId == null) {
            return options;
        }
        for (Team_Member__c member : [
            SELECT User__c, User__r.Name FROM Team_Member__c
            WHERE Team__c = :teamId AND User__c != null
            ORDER BY User__r.Name
        ]) {
            ExecutionOptionDTO o = new ExecutionOptionDTO();
            o.testerId = member.User__c;
            o.testerName = member.User__r.Name;
            o.label = member.User__r.Name;
            options.add(o);
        }
        return options;
    }

    /** Case-level evidence removal for the selected run (admins can prune). */
    @AuraEnabled
    public static void deleteEvidence(Id contentDocumentId, Id recordId) {
        assertCaseAdmin();
        try {
            UatFileService.deleteFile(contentDocumentId, recordId);
        } catch (UatFileService.UatFileException e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Retire / delete (2026-08-05: admins can delete everything) ---------------

    public class CaseDeleteImpactDTO {
        @AuraEnabled public String caseCode;
        @AuraEnabled public Boolean blocked;         // any Restrict reference exists
        @AuraEnabled public List<String> bookNames = new List<String>();
        @AuraEnabled public List<String> cycleNames = new List<String>();
        @AuraEnabled public Integer executionCount;  // any run, incl. standalone
        @AuraEnabled public Integer stepCount;       // dies with the case
        @AuraEnabled public Integer refCount;        // dies; files stay with uploaders
    }

    /** What blocks (books / cycles / runs — the Restrict lookups) or dies
     *  (steps, reference rows) with this case — drives the delete confirm
     *  and its Retire-instead fallback. */
    @AuraEnabled
    public static CaseDeleteImpactDTO getCaseDeleteImpact(Id caseId) {
        assertCasesReadable();
        Test_Case__c c;
        try {
            c = [SELECT Case_ID__c FROM Test_Case__c WHERE Id = :caseId];
        } catch (QueryException e) {
            throw auraError('That test case no longer exists.');
        }
        CaseDeleteImpactDTO dto = new CaseDeleteImpactDTO();
        dto.caseCode = c.Case_ID__c;
        Set<String> books = new Set<String>();
        for (Test_Book_Item__c item : [
            SELECT Test_Book__r.Name FROM Test_Book_Item__c WHERE Test_Case__c = :caseId
        ]) {
            books.add(item.Test_Book__r.Name);
        }
        dto.bookNames.addAll(books);
        Set<String> cycles = new Set<String>();
        for (Test_Cycle_Case__c junction : [
            SELECT Test_Cycle__r.Name FROM Test_Cycle_Case__c WHERE Test_Case__c = :caseId
        ]) {
            cycles.add(junction.Test_Cycle__r.Name);
        }
        for (Test_Execution__c e : [
            SELECT Test_Cycle__r.Name FROM Test_Execution__c
            WHERE Test_Case__c = :caseId AND Test_Cycle__c != null
        ]) {
            cycles.add(e.Test_Cycle__r.Name);
        }
        dto.cycleNames.addAll(cycles);
        dto.executionCount = [SELECT COUNT() FROM Test_Execution__c WHERE Test_Case__c = :caseId];
        dto.stepCount = [SELECT COUNT() FROM Test_Step__c WHERE Test_Case__c = :caseId];
        dto.refCount = [SELECT COUNT() FROM Reference_Material__c WHERE Test_Case__c = :caseId];
        dto.blocked = !dto.bookNames.isEmpty() || !dto.cycleNames.isEmpty() || dto.executionCount > 0;
        return dto;
    }

    /**
     * Hard delete — only for a case nothing references. Books, cycle
     * junctions, and executions all Restrict the delete; the preflight turns
     * the raw DELETE_FAILED into a plain-language reason and the UI offers
     * Retire instead. When clear: steps cascade (their before-delete trigger
     * finds no results, since no executions exist) and reference rows cascade
     * (uploaded files stay in their uploaders' Files — stated in the confirm).
     */
    @AuraEnabled
    public static void deleteCase(Id caseId) {
        assertCaseAdmin();
        if (!Schema.sObjectType.Test_Case__c.isDeletable()) {
            throw auraError('You do not have access to delete test cases.');
        }
        CaseDeleteImpactDTO impact = getCaseDeleteImpact(caseId);
        if (impact.blocked) {
            List<String> parts = new List<String>();
            if (!impact.bookNames.isEmpty()) {
                parts.add(impact.bookNames.size() + ' book' + (impact.bookNames.size() == 1 ? '' : 's'));
            }
            if (!impact.cycleNames.isEmpty()) {
                parts.add(impact.cycleNames.size() + ' cycle' + (impact.cycleNames.size() == 1 ? '' : 's'));
            }
            if (impact.executionCount > 0) {
                parts.add(impact.executionCount + ' recorded run' + (impact.executionCount == 1 ? '' : 's'));
            }
            throw auraError('Can\'t delete ' + impact.caseCode + ' — it\'s in ' + String.join(parts, ', ')
                + '. Remove it from those places, or retire it to hide it while keeping history.');
        }
        try {
            delete new Test_Case__c(Id = caseId);
        } catch (DmlException e) {
            throw auraError('The case could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    /** One-click Retire/Restore (mirrors UatCycleAdminController.setCycleStatus
     *  — saveCase isn't reusable for this, it round-trips the whole form).
     *  Retired only leaves the add-pickers; existing books, cycles, and run
     *  history are untouched. */
    @AuraEnabled
    public static void setCaseCreationStatus(Id caseId, String status) {
        assertCaseAdmin();
        if (status != 'Draft' && status != 'In Progress'
            && status != UatConstants.CREATION_COMPLETE && status != UatConstants.CREATION_RETIRED) {
            throw auraError('Unknown creation status.');
        }
        try {
            update new Test_Case__c(Id = caseId, Creation_Status__c = status);
        } catch (DmlException e) {
            throw auraError('The case could not be updated: ' + e.getDmlMessage(0));
        }
        if (status == UatConstants.CREATION_COMPLETE) {
            processTargetBook(caseId);
        }
    }

    // ---- Internals -------------------------------------------------------------

    private static StepDTO toStepDTO(Test_Step__c s) {
        StepDTO dto = new StepDTO();
        dto.id = s.Id;
        dto.stepNumber = s.Step_Number__c;
        dto.title = s.Step_Title__c;
        dto.condition = s.Test_Condition__c;
        dto.description = s.Step_Description__c;
        dto.expected = s.Expected_Result__c;
        dto.isExplore = s.Is_Explore__c;
        dto.explorePrompt = s.Explore_Prompt__c;
        return dto;
    }

    private static Object parse(String inputJson, Type target) {
        try {
            Object input = String.isBlank(inputJson) ? null : JSON.deserialize(inputJson, target);
            if (input == null) {
                throw auraError('Could not read the form — refresh and try again.');
            }
            return input;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
    }

    private static void upsertStripped(SObject record) {
        SObjectAccessDecision decision = Security.stripInaccessible(
            record.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
            new List<SObject>{ record }
        );
        SObject stripped = decision.getRecords()[0];
        if (record.Id == null) {
            insert stripped;
            record.Id = stripped.Id;
        } else {
            update stripped;
        }
    }

    /** Module__c and Sequence__c move together, and stripInaccessible would
     *  drop either one SILENTLY — a save that reports success while the case
     *  stays exactly where it was. Fail loudly instead. (Module__c is required
     *  on the object, so it carries no field permissions and is writable
     *  wherever the object is; Sequence__c is granted on UAT_Admin.) */
    private static void assertModuleWritable() {
        if (!Schema.sObjectType.Test_Case__c.fields.Module__c.isUpdateable()
            || !Schema.sObjectType.Test_Case__c.fields.Sequence__c.isUpdateable()) {
            throw auraError('You don\'t have edit access to Module on test cases — '
                + 'ask an admin for the UAT Admin permission set.');
        }
    }

    private static void assertCaseAdmin() {
        if (!Schema.sObjectType.Test_Case__c.isCreateable()
            || !Schema.sObjectType.Test_Case__c.isUpdateable()) {
            throw auraError('You do not have access to manage test cases.');
        }
    }

    private static void assertCasesReadable() {
        if (!Schema.sObjectType.Test_Case__c.isAccessible()
            || !Schema.sObjectType.Test_Step__c.isAccessible()) {
            throw auraError('You do not have access to test cases.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}