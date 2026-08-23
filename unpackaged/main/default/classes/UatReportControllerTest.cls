/**
 * Tests for UatReportController — the Cycle Report section: the read-only
 * assembly of a cycle's runs, step results, sessions, notes, findings and
 * assignment audit trail, plus the rollups and data-quality flags built off
 * them. Read-only surface; the seat mechanics themselves are covered by
 * UatExecutionServiceTest and the session lifecycle by UatSessionControllerTest.
 */
@IsTest
private class UatReportControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatrpt');
        UatTestDataFactory.createTesterUser('uatrpt1');
        UatTestDataFactory.createTesterUser('uatrpt2');
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    /** Every positive test runs as the admin with the persona seam forced:
     *  checkPermission reads real assignments, which is the fragility the seam
     *  exists for. */
    private static void asAdmin() {
        UatAudienceService.uatConsoleOverride = true;
    }

    private static Test_Cycle__c cycleWithCases(Integer caseCount, Integer stepsPerCase) {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('rpt');
        List<Id> caseIds = new List<Id>();
        for (Integer i = 0; i < caseCount; i++) {
            caseIds.add(UatTestDataFactory.makeCase(tax.mod.Id, stepsPerCase, 1001 + i).Id);
        }
        return UatTestDataFactory.makeCycle('Report Sprint', null, null, caseIds);
    }

    private static Id startSession(Id cycleId, String title) {
        return UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
            'title' => title,
            'areaText' => 'Client Records',
            'timeboxMinutes' => 30,
            'cycleId' => cycleId
        }));
    }

    private static Id addNote(Id sessionId, String text, Id executionId) {
        Map<String, Object> input = new Map<String, Object>{
            'sessionId' => sessionId,
            'text' => text,
            'tag' => 'Observation'
        };
        if (executionId != null) {
            input.put('executionId', executionId);
        }
        UatSessionController.addSessionNote(JSON.serialize(input));
        return [
            SELECT Id FROM Session_Note__c
            WHERE Exploratory_Session__c = :sessionId
            ORDER BY CreatedDate DESC LIMIT 1
        ].Id;
    }

    private static Id addFinding(Map<String, Object> overrides) {
        Map<String, Object> input = new Map<String, Object>{
            'title' => 'Survivor history vanished after merge',
            'type' => 'Defect',
            'whatTesting' => 'Merged two client records',
            'whatHappened' => 'The survivor lost its history',
            'severity' => 'Low',
            'noEvidenceReason' => 'Captured in the session log instead.'
        };
        input.putAll(overrides);
        return UatRunController.saveFinding(JSON.serialize(input));
    }

    private static void answerSteps(Id executionId, List<String> results) {
        UatExecutionService.ensureStepResults(executionId);
        // Re-read in step order: the service's return order is its own business.
        List<Test_Step_Result__c> rows = [
            SELECT Id FROM Test_Step_Result__c
            WHERE Test_Execution__c = :executionId
            ORDER BY Test_Step__r.Step_Number__c NULLS LAST
        ];
        List<Test_Step_Result__c> updates = new List<Test_Step_Result__c>();
        for (Integer i = 0; i < results.size() && i < rows.size(); i++) {
            updates.add(new Test_Step_Result__c(
                Id = rows[i].Id,
                Result__c = results[i],
                Actual_Result__c = 'Observed ' + results[i]
            ));
        }
        // Direct DML rather than UatRunController.saveStepResult: that gate
        // rejects another tester's run. The trigger still fires, so the parent's
        // status and verdict come out real.
        update updates;
    }

    private static UatReportController.ExecutionRowDTO execNamed(
        UatReportController.CycleReportDTO report, Id executionId) {
        for (UatReportController.ExecutionRowDTO row : report.executions.rows) {
            if (row.executionId == executionId) {
                return row;
            }
        }
        return null;
    }

    // ---- Happy path ----------------------------------------------------------

    @IsTest
    static void cycleReportReturnsEveryGrain() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(2, 2);
            User tester = byLastName('UAT uatrpt1');
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, [SELECT Test_Case__c FROM Test_Execution__c
                           WHERE Test_Cycle__c = :cycle.Id LIMIT 1].Test_Case__c, tester.Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass', 'Fail' });

            Id sessionId = startSession(cycle.Id, 'Poking at households');
            addNote(sessionId, 'The drawer overlaps at 125% zoom.', null);
            addNote(sessionId, 'Second observation.', null);
            addFinding(new Map<String, Object>{ 'sessionId' => sessionId });

            Test.startTest();
            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            Test.stopTest();

            Assert.areEqual('Cycle', report.scope, 'A cycle report knows its own scope.');
            Assert.areEqual(cycle.Id, report.cycle.cycleId, 'Header carries the cycle.');
            Assert.areEqual('Report Sprint', report.cycle.cycleName, 'Header carries the name.');
            Assert.isNotNull(report.generatedAt, 'The audit anchor is server-stamped.');
            Assert.isNotNull(report.generatedByName, 'The audit anchor names who ran it.');

            Assert.areEqual(2, report.executions.returned, 'Two cases, one seat each.');
            Assert.isFalse(report.executions.truncated, 'Two rows is not a truncation.');
            UatReportController.ExecutionRowDTO run = execNamed(report, claimed.Id);
            Assert.areEqual(2, run.steps.size(), 'The claimed run carries its step results.');
            Assert.areEqual(2, run.stepsAnswered, 'Both steps were answered.');
            Assert.areEqual(1, run.stepsFailed, 'One of them failed.');
            Assert.isNotNull(run.testerName, 'A claimed run resolves its tester name.');
            Assert.isNotNull(run.modulePath, 'Every run carries a groupable module path.');

            Assert.areEqual(1, report.sessions.returned, 'One session.');
            Assert.areEqual(2, report.sessions.rows[0].notes.size(), 'Both entries hang off it.');
            Assert.areEqual(1, report.findings.returned, 'One finding.');
            Assert.areEqual('Session', report.findings.rows[0].source,
                'A session finding is stamped Session, server-side.');
            Assert.isTrue(report.events.returned > 0, 'Claiming a seat writes an audit row.');
            Assert.areEqual(1, report.summary.resultFailed, 'A failed step fails the run.');
        }
    }

    @IsTest
    static void emptyCycleReportsZerosNotNulls() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Empty Sprint', null, null, null);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual(0, report.executions.rows.size(), 'No runs.');
            Assert.areEqual(0, report.cases.rows.size(), 'No cases.');
            Assert.areEqual(0, report.sessions.rows.size(), 'No sessions.');
            Assert.areEqual(0, report.findings.rows.size(), 'No findings.');
            Assert.areEqual(0, report.events.rows.size(), 'No events.');
            Assert.areEqual(0, report.summary.executionCount, 'Counters start at zero, not null.');
            Assert.areEqual(0, report.summary.caseCount, 'Including the case counters.');
            Assert.areEqual(0, report.summary.casesComplete, 'Zero of zero cases complete.');
            Assert.areEqual(0, report.summary.evidenceDocumentCount, 'No evidence.');
            Assert.isFalse(report.executions.truncated, 'Nothing to truncate.');
            Assert.isTrue(report.summary.dataQualityFlags.isEmpty(), 'Nothing to flag.');
            // Collections initialized inline is what keeps the LWC null-guard-free.
            Assert.isNotNull(report.summary.findingsByType, 'Rollup lists are never null.');
        }
    }

    // ---- Scoping -------------------------------------------------------------

    @IsTest
    static void standaloneReportScopesByNullCycle() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id cycledSession = startSession(cycle.Id, 'Cycled session');
            Id standaloneSession = startSession(null, 'Personal session');
            addFinding(new Map<String, Object>{ 'sessionId' => cycledSession });
            addFinding(new Map<String, Object>{ 'sessionId' => standaloneSession });

            UatReportController.CycleReportDTO standalone = UatReportController.getStandaloneReport();
            UatReportController.CycleReportDTO cycled = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual('Standalone', standalone.scope, 'Scope names itself.');
            Assert.isNull(standalone.cycle, 'A standalone report has no cycle header.');
            Assert.areEqual(1, standalone.sessions.returned, 'Only the personal session.');
            Assert.areEqual('Personal session', standalone.sessions.rows[0].title,
                'And it is the right one.');
            Assert.areEqual(1, standalone.findings.returned, 'Only its finding.');

            Assert.areEqual(1, cycled.sessions.returned, 'The cycle sees only its own session.');
            Assert.areEqual('Cycled session', cycled.sessions.rows[0].title, 'Symmetrically scoped.');
            for (UatReportController.ExecutionRowDTO row : standalone.executions.rows) {
                Assert.isNull(row.cycleId, 'Every standalone run has a null cycle.');
            }
            Assert.areEqual(0, standalone.cases.returned,
                'Standalone work has no cycle, so it has no scope to build a case grain from.');
            Assert.isFalse(standalone.cases.truncated, 'And nothing was cut to get there.');
            Assert.areEqual(1, cycled.cases.returned, 'The cycle still gets its case.');
        }
    }

    @IsTest
    static void notesAreScopedThroughTheirSessionNotTheirExecution() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt').Id);

            // Legal, and the trap: addSessionNote never checks that the note's
            // "logged from run" execution shares the session's cycle.
            Id personal = startSession(null, 'Personal session');
            Id noteId = addNote(personal, 'Noticed while looking at a cycled run.', claimed.Id);

            UatReportController.CycleReportDTO standalone = UatReportController.getStandaloneReport();
            UatReportController.CycleReportDTO cycled = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual(1, standalone.sessions.rows[0].notes.size(),
                'The note belongs to its session, which is standalone.');
            UatReportController.NoteRowDTO note = standalone.sessions.rows[0].notes[0];
            Assert.areEqual(noteId, note.noteId, 'And it is the note we logged.');
            Assert.areEqual(claimed.Id, note.executionId,
                'The run reference survives as a cross-reference column.');
            Assert.isNotNull(note.caseCode, 'Including the case it was logged against.');
            Assert.areEqual(0, cycled.sessions.returned,
                'Scoping notes by their execution would have double-counted this one.');
        }
    }

    // ---- Released history ----------------------------------------------------

    @IsTest
    static void releasedRunsAppearAsFlaggedHistory() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            User tester = byLastName('UAT uatrpt1');
            Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, slot.Test_Case__c, tester.Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass' });
            UatExecutionService.releaseSeat(claimed.Id, tester.Id, 'Moving on',
                UatConstants.EVENT_RELEASED);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            UatReportController.ExecutionRowDTO history = execNamed(report, claimed.Id);
            Assert.isNotNull(history, 'A released run is still reported — the work happened.');
            Assert.isTrue(history.released, 'And it is flagged as history.');
            Assert.areEqual(1, report.summary.releasedRuns, 'The rollup counts it as released.');
            Assert.isTrue(report.summary.unclaimedSlots >= 1, 'Releasing returns a seat to the pool.');

            Set<String> actions = new Set<String>();
            for (UatReportController.EventRowDTO e : report.events.rows) {
                actions.add(e.action);
            }
            Assert.isTrue(actions.contains(UatConstants.EVENT_CLAIMED), 'The claim is in the log.');
            Assert.isTrue(actions.contains(UatConstants.EVENT_RELEASED), 'So is the release.');
        }
    }

    // ---- Deleted step definition ---------------------------------------------

    @IsTest
    static void deletedStepDefinitionRendersAsWordsNotBlank() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass', 'Fail' });

            // Deleting the step cascades its results away (Test_Step_Trigger), so
            // the orphan state is reached by nulling the lookup — what a Data
            // Loader edit or a disabled trigger leaves behind.
            Test_Step_Result__c orphan = [
                SELECT Id FROM Test_Step_Result__c
                WHERE Test_Execution__c = :claimed.Id AND Result__c = 'Fail' LIMIT 1
            ];
            update new Test_Step_Result__c(Id = orphan.Id, Test_Step__c = null);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            UatReportController.ExecutionRowDTO run = execNamed(report, claimed.Id);
            UatReportController.StepResultRowDTO row;
            for (UatReportController.StepResultRowDTO s : run.steps) {
                if (s.resultId == orphan.Id) {
                    row = s;
                }
            }
            Assert.isNotNull(row, 'An orphaned result is still reported.');
            Assert.isTrue(row.stepDeleted, 'And flagged.');
            Assert.isNull(row.stepId, 'Its definition is gone.');
            Assert.areEqual('(step deleted)', row.stepDescription,
                'A blank cell would read as "nobody wrote a step" — a different claim.');
            Assert.isNull(row.stepNumber, 'Its position is unknowable.');
            Assert.areEqual('Fail', row.result, 'The answer the tester gave survives.');
            Assert.areEqual(1, run.stepsOrphaned, 'The run counts its orphans.');
            Assert.areEqual(1, report.summary.stepsOrphaned, 'So does the summary.');
        }
    }

    // ---- Evidence ------------------------------------------------------------

    @IsTest
    static void evidenceDedupesByDocumentAcrossPromotedCopies() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Evidence session');
            Id noteId = addNote(sessionId, 'Screenshot attached.', null);
            Id docId = UatTestDataFactory.attachFile(noteId, 'screenshot');

            // Promote-to-finding copies the link: one document, two records.
            addFinding(new Map<String, Object>{
                'sessionId' => sessionId,
                'sourceNoteId' => noteId
            });

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            UatReportController.NoteRowDTO note = report.sessions.rows[0].notes[0];
            UatReportController.FindingRowDTO finding = report.findings.rows[0];
            Assert.areEqual(1, note.evidenceCount, 'The entry keeps the file it always had.');
            Assert.areEqual(1, finding.evidenceCount, 'The finding has it too — same document.');
            Assert.areEqual(1, report.summary.evidenceDocumentCount,
                'One file in storage is one document report-wide.');
            Assert.areEqual(2, report.summary.evidenceLinkCount,
                'Two records reference it; both counts are right, they answer different questions.');
            Assert.areEqual(noteId, finding.sourceNoteId, 'The promotion is traceable.');
            Assert.areEqual(finding.name, note.promotedFindingName,
                'And the entry carries the badge back.');
            Assert.isNotNull(docId, 'The fixture attached something.');
        }
    }

    @IsTest
    static void executionAndStepEvidenceAreCounted() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass' });
            Test_Step_Result__c result = [
                SELECT Id FROM Test_Step_Result__c WHERE Test_Execution__c = :claimed.Id LIMIT 1
            ];
            UatTestDataFactory.attachFile(claimed.Id, 'case-evidence');
            UatTestDataFactory.attachFile(result.Id, 'step-evidence');

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            UatReportController.ExecutionRowDTO run = execNamed(report, claimed.Id);
            Assert.areEqual(1, run.evidenceCount, 'Case-level evidence counted.');
            Assert.areEqual(1, run.steps[0].evidenceCount, 'Per-step evidence counted.');
            Assert.areEqual(2, report.summary.evidenceDocumentCount, 'Two distinct documents.');
        }
    }

    // ---- Data quality --------------------------------------------------------

    @IsTest
    static void dataQualityFlagsOnlySeriousDefectsWithNothingToLookAt() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Quality session');

            // (a) Critical defect, reason given at save, then the reason drifts
            // away — exactly the state finishSession re-checks for.
            Id flagged = addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'Critical with nothing to show',
                'severity' => 'Critical'
            });
            update new Exploratory_Finding__c(Id = flagged, No_Evidence_Reason__c = null);
            // (b) Critical defect that says why there is no evidence.
            addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'Critical but explained', 'severity' => 'Critical'
            });
            // (c) High defect with a file on it.
            Id withFile = addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'High but evidenced', 'severity' => 'High'
            });
            update new Exploratory_Finding__c(Id = withFile, No_Evidence_Reason__c = null);
            UatTestDataFactory.attachFile(withFile, 'proof');
            // (d) A suggestion — severity does not apply, so neither does the rule.
            addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'Just an idea about spacing',
                'type' => 'Suggestion', 'severity' => null
            });

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual(1, report.summary.dataQualityFlags.size(),
                'Only the Critical defect with no evidence and no reason is a gap.');
            Assert.areEqual(flagged, report.summary.dataQualityFlags[0].findingId,
                'And it names the right finding.');
            Assert.areEqual('EVIDENCE_MISSING', report.summary.dataQualityFlags[0].code,
                'The flag carries a stable code the UI can group on.');
            Assert.areEqual(4, report.findings.returned, 'All four findings are still reported.');
        }
    }

    // ---- Rollups -------------------------------------------------------------

    @IsTest
    static void perTesterActivitySplitsByTester() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(2, 1);
            User t1 = byLastName('UAT uatrpt1');
            User t2 = byLastName('UAT uatrpt2');
            List<Test_Execution__c> slots = [
                SELECT Id, Test_Case__c FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycle.Id ORDER BY Name
            ];
            UatExecutionService.claimSeat(cycle.Id, slots[0].Test_Case__c, t1.Id);
            UatExecutionService.claimSeat(cycle.Id, slots[1].Test_Case__c, t2.Id);

            Id sessionId = startSession(cycle.Id, 'Shared session');
            addNote(sessionId, 'One entry.', null);
            update new Exploratory_Session__c(Id = sessionId, Tester__c = t1.Id);
            update new Session_Note__c(
                Id = [SELECT Id FROM Session_Note__c WHERE Exploratory_Session__c = :sessionId LIMIT 1].Id,
                Author__c = t1.Id);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Map<Id, UatReportController.TesterActivityDTO> byTester =
                new Map<Id, UatReportController.TesterActivityDTO>();
            for (UatReportController.TesterActivityDTO t : report.summary.testers) {
                byTester.put(t.testerId, t);
            }
            Assert.areEqual(2, byTester.size(), 'Two testers claimed work.');
            Assert.areEqual(1, byTester.get(t1.Id).runsAssigned, 'One run each.');
            Assert.areEqual(1, byTester.get(t2.Id).runsAssigned, 'One run each.');
            Assert.areEqual(1, byTester.get(t1.Id).sessionsStarted, 'Only t1 owns the session.');
            Assert.areEqual(1, byTester.get(t1.Id).notesLogged, 'And its entry.');
            Assert.areEqual(0, byTester.get(t2.Id).notesLogged, 't2 logged nothing.');
            Assert.isNotNull(byTester.get(t1.Id).testerName,
                'Names resolve through the lookup, not a separate User query.');
        }
    }

    // ---- Truncation ----------------------------------------------------------

    @IsTest
    static void truncationFlagsFireAndCascadeToChildGrains() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(3, 2);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass', 'Pass' });

            UatReportController.grainLimitOverride = 1;
            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual(1, report.executions.returned, 'The grain limit held.');
            Assert.isTrue(report.executions.truncated, 'And said so.');
            Assert.isTrue(String.isNotBlank(report.executions.truncationReason),
                'A truncation without a reason is just a missing row.');
            Assert.isTrue(report.executions.stepsTruncated,
                'Truncated executions truncate their steps even when the step query never capped.');
            Assert.areEqual('Parent executions were truncated.',
                report.executions.stepsTruncationReason, 'And the cascade says which.');
        }
    }

    @IsTest
    static void longTextIsClippedAndFlagged() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            List<Test_Step_Result__c> rows = UatExecutionService.ensureStepResults(claimed.Id);
            update new Test_Step_Result__c(
                Id = rows[0].Id, Result__c = 'Pass',
                Actual_Result__c = 'x'.repeat(9000));

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            UatReportController.StepResultRowDTO step = execNamed(report, claimed.Id).steps[0];
            Assert.areEqual(8000, step.actualResult.length(),
                'Long text is clipped so one pathological row cannot exhaust the heap.');
            Assert.isTrue(step.textTruncated, 'And the row discloses the cut.');
        }
    }

    // ---- Case grain ----------------------------------------------------------

    private static UatReportController.CaseRowDTO caseFor(
        UatReportController.CycleReportDTO report, Id caseId) {
        for (UatReportController.CaseRowDTO row : report.cases.rows) {
            if (row.caseId == caseId) {
                return row;
            }
        }
        return null;
    }

    /** Claims the cycle's only seat for tester 1, answers its steps, and returns
     *  the case row the report built for it. */
    private static UatReportController.CaseRowDTO singleCaseAfter(
        Test_Cycle__c cycle, List<String> stepResults) {
        Test_Execution__c slot = [
            SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];
        Test_Execution__c claimed = UatExecutionService.claimSeat(
            cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
        answerSteps(claimed.Id, stepResults);
        return caseFor(UatReportController.getCycleReport(cycle.Id), slot.Test_Case__c);
    }

    @IsTest
    static void aFullyPassedCasePassesAndRollsItsStepsUp() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            UatReportController.CaseRowDTO passed =
                singleCaseAfter(cycleWithCases(1, 2), new List<String>{ 'Pass', 'Pass' });

            Assert.areEqual('Passed', passed.verdict, 'All steps pass, so the case passes.');
            Assert.areEqual(2, passed.stepsTotal, 'The case rolls its run steps up.');
            Assert.areEqual(2, passed.stepsPassed, 'Both of them passed.');
            Assert.isFalse(passed.noRunCreated, 'It has a run.');
            Assert.isTrue(passed.inScope, 'And it is in the cycle scope.');
            Assert.areEqual(1, passed.executionIds.size(), 'One seat, one reference.');
            Assert.areEqual(1, passed.testerNames.size(), 'Held by one tester.');
        }
    }

    @IsTest
    static void anUnfinishedCaseIsInProgressNotPassed() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            UatReportController.CaseRowDTO partial =
                singleCaseAfter(cycleWithCases(1, 3), new List<String>{ 'Pass' });

            Assert.areEqual('In progress', partial.verdict,
                'One answered step of three is in flight — "all passed" is not the same as "none failed".');
            Assert.areEqual(1, partial.stepsAnswered, 'And the progress is countable.');
            Assert.areEqual(3, partial.stepsTotal, 'Against the full script.');
        }
    }

    @IsTest
    static void blockedOutranksPassedAndFailedOutranksBoth() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            UatReportController.CaseRowDTO blocked =
                singleCaseAfter(cycleWithCases(1, 2), new List<String>{ 'Pass', 'Blocked' });
            Assert.areEqual('Blocked', blocked.verdict, 'A blocked step blocks the case.');

            Test.startTest();
            UatReportController.CaseRowDTO failed =
                singleCaseAfter(cycleWithCases(1, 3), new List<String>{ 'Pass', 'Blocked', 'Fail' });
            Test.stopTest();
            Assert.areEqual('Failed', failed.verdict,
                'Failed outranks blocked: the worst outcome is the case answer.');
            Assert.areEqual(1, failed.stepsFailed, 'One failure.');
            Assert.areEqual(1, failed.stepsBlocked, 'One block.');
        }
    }

    @IsTest
    static void anUnclaimedCaseReadsAsNotStartedNotAsPassed() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(2, 2);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Assert.areEqual(2, report.cases.returned, 'Both cases are in the report.');
            Assert.areEqual(2, report.summary.caseCount, 'And counted.');
            for (UatReportController.CaseRowDTO row : report.cases.rows) {
                Assert.areEqual('Not started', row.verdict,
                    'An unclaimed slot has answered nothing; a blank verdict would read as passed.');
                Assert.isFalse(row.noRunCreated, 'The slot exists — it is just untouched.');
                Assert.areEqual(0, row.testerNames.size(), 'Nobody holds it.');
            }
            Assert.areEqual(2, report.summary.casesNotStarted, 'The rollup agrees.');
            Assert.areEqual(0, report.summary.casesComplete, 'Nothing reached a verdict.');
            Assert.areEqual(0, report.summary.casesWithoutRuns, 'Slots are materialized eagerly.');
        }
    }

    @IsTest
    static void releasedRunsDoNotDecideTheCaseVerdict() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            User tester = byLastName('UAT uatrpt1');
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, tester.Id);
            answerSteps(claimed.Id, new List<String>{ 'Fail', 'Fail' });
            UatExecutionService.releaseSeat(claimed.Id, tester.Id, 'Handing back',
                UatConstants.EVENT_RELEASED);

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.CaseRowDTO row = caseFor(report, slot.Test_Case__c);

            Assert.areEqual('Not started', row.verdict,
                'A handed-back run is history — it cannot fail the case for whoever picks it up next.');
            Assert.areEqual(1, row.releasedCount, 'The history row is still counted and reported.');
            Assert.areEqual(0, row.stepsAnswered,
                'Superseded step answers do not roll up, or the case reads 4 of 2 answered.');
            Assert.isTrue(row.executionIds.size() >= 2,
                'Both the history row and the fresh slot are referenced.');
        }
    }

    @IsTest
    static void aCaseInScopeWithNoRunIsReportedAsACoverageGap() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(2, 1);
            // Slots are materialized by trigger, so the only way to reach the gap
            // is the way the org reaches it: something deleted the run.
            Test_Execution__c doomed = [
                SELECT Id, Test_Case__c FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycle.Id ORDER BY Name LIMIT 1
            ];
            Id strandedCase = doomed.Test_Case__c;
            delete doomed;

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.CaseRowDTO row = caseFor(report, strandedCase);

            Assert.isNotNull(row, 'A case with no run must still appear — that IS the finding.');
            Assert.isTrue(row.noRunCreated, 'And be marked as having no run.');
            Assert.isTrue(row.inScope, 'It is still in the cycle scope.');
            Assert.areEqual('Not started', row.verdict, 'With nothing done against it.');
            Assert.areEqual(0, row.executionCount, 'And no seats.');
            Assert.isNotNull(row.caseCode, 'Its identity comes from the case, not from a run.');
            Assert.isNotNull(row.modulePath, 'Including its module path.');
            Assert.areEqual(2, report.cases.returned, 'Both cases are reported.');
            Assert.areEqual(1, report.summary.casesWithoutRuns, 'The gap is counted.');
        }
    }

    @IsTest
    static void workDoneOnACaseSurvivesThatCaseLeavingTheScope() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(2, 1);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            answerSteps(claimed.Id, new List<String>{ 'Pass' });
            // Pull the case out of scope. cleanupPristineSlots only removes
            // UNWORKED slots, so the finished run stays behind.
            delete [
                SELECT Id FROM Test_Cycle_Case__c
                WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :slot.Test_Case__c
            ];

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.CaseRowDTO row = caseFor(report, slot.Test_Case__c);

            Assert.isNotNull(row,
                'Scoping the grain by the junction alone would erase finished work from the report.');
            Assert.isFalse(row.inScope, 'It is reported as out of scope.');
            Assert.areEqual('Passed', row.verdict, 'The work it holds still counts.');
            Assert.areEqual(1, row.executionCount, 'Its run is still referenced.');
        }
    }

    @IsTest
    static void caseFindingsResolveThroughTheRunAndThroughTheStepResult() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Test_Execution__c slot = [
                SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
            ];
            Test_Execution__c claimed = UatExecutionService.claimSeat(
                cycle.Id, slot.Test_Case__c, byLastName('UAT uatrpt1').Id);
            answerSteps(claimed.Id, new List<String>{ 'Fail', 'Pass' });
            Test_Step_Result__c failed = [
                SELECT Id FROM Test_Step_Result__c
                WHERE Test_Execution__c = :claimed.Id AND Result__c = 'Fail' LIMIT 1
            ];

            // Direct DML, not saveFinding: the runner mints these through
            // saveStepResult, which rejects another tester's run. What matters
            // here is the two anchor shapes the report has to resolve — one
            // pointing at the run, one pointing only at the step result (what
            // the typed-model migration left behind).
            insert new List<Exploratory_Finding__c>{
                new Exploratory_Finding__c(
                    Title__c = 'Run-scoped defect on the client drawer',
                    Type__c = 'Defect', Source__c = 'Test case', Severity__c = 'Low',
                    Test_Cycle__c = cycle.Id, Test_Execution__c = claimed.Id,
                    Tester__c = UserInfo.getUserId(), Date__c = Date.today()
                ),
                new Exploratory_Finding__c(
                    Title__c = 'Step-scoped defect on the conflict banner',
                    Type__c = 'Defect', Source__c = 'Test case', Severity__c = 'Low',
                    Test_Cycle__c = cycle.Id, Test_Step_Result__c = failed.Id,
                    Tester__c = UserInfo.getUserId(), Date__c = Date.today()
                )
            };
            // A session finding belongs to no case and must not be attributed.
            Id sessionId = startSession(cycle.Id, 'Free poking');
            addFinding(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Session finding with no case at all'
            });

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.CaseRowDTO row = caseFor(report, slot.Test_Case__c);

            Assert.areEqual(3, report.findings.returned, 'All three findings are in the report.');
            Assert.areEqual(2, row.findingCount,
                'Both anchor shapes reach the case; the session finding does not.');
            Assert.areEqual(2, row.findingIds.size(), 'And both are referenced by Id.');

            Map<String, UatReportController.FindingRowDTO> byTitle =
                new Map<String, UatReportController.FindingRowDTO>();
            for (UatReportController.FindingRowDTO f : report.findings.rows) {
                byTitle.put(f.title, f);
            }
            UatReportController.FindingRowDTO viaRun = byTitle.get('Run-scoped defect on the client drawer');
            UatReportController.FindingRowDTO viaStep = byTitle.get('Step-scoped defect on the conflict banner');
            UatReportController.FindingRowDTO viaSession = byTitle.get('Session finding with no case at all');

            Assert.areEqual(slot.Test_Case__c, viaRun.caseId,
                'A run-anchored finding carries its caseId for the tree link.');
            Assert.isTrue(row.findingIds.contains(viaRun.findingId), 'And the case claims it.');
            Assert.isNull(viaStep.caseId,
                'A step-result-only finding has no run to read a case from...');
            Assert.isTrue(row.findingIds.contains(viaStep.findingId),
                '...so the report resolves it through the step result its run owns.');
            Assert.isNull(viaSession.caseId, 'A session finding has no case at all.');
            Assert.isFalse(row.findingIds.contains(viaSession.findingId),
                'And is never attributed to one.');
        }
    }

    @IsTest
    static void caseGrainTruncationCascadesFromExecutions() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(3, 1);

            UatReportController.grainLimitOverride = 1;
            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);

            Assert.isTrue(report.cases.truncated,
                'The executed half of the union is derived from returned executions.');
            Assert.areEqual('Parent executions were truncated.', report.cases.truncationReason,
                'Root cause first: the case grain never hit a cap of its own.');
        }
    }

    // ---- Access --------------------------------------------------------------

    @IsTest
    static void testersCannotReadTheReport() {
        System.runAs(byLastName('UAT uatrpt1')) {
            try {
                UatReportController.getCycleReport(null);
                Assert.fail('The report keys on the cycle-manage capability.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
            try {
                UatReportController.getStandaloneReport();
                Assert.fail('Both endpoints gate the same way.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }

    @IsTest
    static void adminWithoutTheConsolePermissionIsRefused() {
        // The half of the gate describes cannot express: a System Administrator
        // with ModifyAllData passes every describe in the org.
        UatAudienceService.uatConsoleOverride = false;
        System.runAs(byLastName('UAT uatrpt')) {
            try {
                UatReportController.getStandaloneReport();
                Assert.fail('The persona permission is not redundant with the describes.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }

    @IsTest
    static void missingOrUnknownCycleFailsFriendly() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            try {
                UatReportController.getCycleReport(null);
                Assert.fail('A null cycle is a caller bug, not an empty report.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Missing cycle'), e.getMessage());
            }

            Test_Cycle__c gone = UatTestDataFactory.makeCycle('Doomed', null, null, null);
            Id goneId = gone.Id;
            delete gone;
            try {
                UatReportController.getCycleReport(goneId);
                Assert.fail('A deleted cycle should say so.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
            }
        }
    }

    // ---- Workflow status (the class's one write) -------------------------------

    @IsTest
    static void adminSetsStatusWithRefAndTheReportCarriesIt() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Triage session');
            Id findingId = addFinding(new Map<String, Object>{ 'sessionId' => sessionId });

            Test.startTest();
            UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'findingId' => findingId,
                'status' => 'Added to Jira',
                'externalRef' => '  DIV-123  '
            }));
            Test.stopTest();

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.FindingRowDTO row = report.findings.rows[0];
            Assert.areEqual('Added to Jira', row.workflowStatus, 'The read side carries the status.');
            Assert.areEqual('DIV-123', row.externalRef, 'The ref is stored trimmed.');

            Assert.areEqual(0, report.summary.untriagedDefects,
                'A triaged defect leaves the untriaged queue.');
            Boolean found = false;
            for (UatReportController.CountRowDTO count : report.summary.findingsByStatus) {
                if (count.label == 'Added to Jira') {
                    Assert.areEqual(1, count.count);
                    found = true;
                }
            }
            Assert.isTrue(found, 'findingsByStatus rolls the new status up.');
        }
    }

    @IsTest
    static void refIsTriStateAbsentKeepsAndEmptyClears() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Triage session');
            Id findingId = addFinding(new Map<String, Object>{ 'sessionId' => sessionId });

            UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'findingId' => findingId, 'status' => 'Added to ClickUp', 'externalRef' => 'CU-9'
            }));
            // Status-only change: no externalRef key at all.
            UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'findingId' => findingId, 'status' => 'Resolved'
            }));
            Exploratory_Finding__c kept = [
                SELECT Workflow_Status__c, External_Ref__c FROM Exploratory_Finding__c
                WHERE Id = :findingId
            ];
            Assert.areEqual('Resolved', kept.Workflow_Status__c);
            Assert.areEqual('CU-9', kept.External_Ref__c,
                'An absent ref means "leave it alone" — a status click must not wipe the ticket key.');

            // Blank ref means "clear it" — the admin emptied the input on purpose.
            UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'findingId' => findingId, 'status' => 'Resolved', 'externalRef' => '   '
            }));
            Assert.isNull([
                SELECT External_Ref__c FROM Exploratory_Finding__c WHERE Id = :findingId
            ].External_Ref__c);
        }
    }

    @IsTest
    static void statusWriteRefusesBadInput() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Triage session');
            Id findingId = addFinding(new Map<String, Object>{ 'sessionId' => sessionId });

            try {
                UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'findingId' => findingId, 'status' => 'Done'
                }));
                Assert.fail('The value set is restricted; the message should beat the DML error.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('workflow status'), e.getMessage());
            }
            try {
                UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'status' => 'Resolved'
                }));
                Assert.fail('A null finding is a caller bug.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Missing finding'), e.getMessage());
            }

            delete [SELECT Id FROM Exploratory_Finding__c WHERE Id = :findingId];
            try {
                UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'findingId' => findingId, 'status' => 'Resolved'
                }));
                Assert.fail('A deleted finding should say so, not silently no-op.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
            }
        }
    }

    @IsTest
    static void testersCannotSetWorkflowStatus() {
        asAdmin();
        Id findingId;
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Triage session');
            findingId = addFinding(new Map<String, Object>{ 'sessionId' => sessionId });
        }
        // No console override: the tester's real (absent) permission decides.
        UatAudienceService.uatConsoleOverride = null;
        System.runAs(byLastName('UAT uatrpt1')) {
            try {
                UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'findingId' => findingId, 'status' => 'Resolved'
                }));
                Assert.fail('Triage is admin-only; testers read the status through UatRunController.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }

    @IsTest
    static void untriagedCountsOnlyNewDefects() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 1);
            Id sessionId = startSession(cycle.Id, 'Triage session');
            addFinding(new Map<String, Object>{ 'sessionId' => sessionId });
            Id triaged = addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'Second defect, already dispatched'
            });
            addFinding(new Map<String, Object>{
                'sessionId' => sessionId, 'title' => 'A suggestion, not a defect',
                'type' => 'Suggestion', 'severity' => null
            });
            UatReportController.setFindingWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'findingId' => triaged, 'status' => 'Added to Jira'
            }));

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            Assert.areEqual(1, report.summary.untriagedDefects,
                'A New suggestion and a dispatched defect both stay out of the queue.');
        }
    }

    // ---- Step workflow status (the second triage write) --------------------------

    /** One claimed run, one failed step of two. Returns the failed step's Id. */
    private static Id failedStepOn(Test_Cycle__c cycle) {
        User tester = byLastName('UAT uatrpt1');
        Test_Execution__c claimed = UatExecutionService.claimSeat(
            cycle.Id, [SELECT Test_Case__c FROM Test_Execution__c
                       WHERE Test_Cycle__c = :cycle.Id LIMIT 1].Test_Case__c, tester.Id);
        answerSteps(claimed.Id, new List<String>{ 'Fail', 'Pass' });
        return [
            SELECT Id FROM Test_Step_Result__c
            WHERE Test_Execution__c = :claimed.Id AND Result__c = 'Fail'
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void adminSetsStepStatusAndTheRollupsFollow() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Id stepId = failedStepOn(cycle);

            UatReportController.CycleReportDTO before = UatReportController.getCycleReport(cycle.Id);
            Assert.areEqual(1, before.summary.untriagedFailedSteps,
                'A failed step starts in the untriaged queue.');
            Assert.areEqual(1, before.cases.rows[0].stepsUntriaged,
                'The case row carries the rollup the tree column shows.');

            Test.startTest();
            UatReportController.setStepWorkflowStatus(JSON.serialize(new Map<String, Object>{
                'resultId' => stepId,
                'status' => 'Added to ClickUp',
                'externalRef' => '  CU-7  '
            }));
            Test.stopTest();

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            UatReportController.StepResultRowDTO step = null;
            for (UatReportController.StepResultRowDTO s : report.executions.rows[0].steps) {
                if (s.resultId == stepId) {
                    step = s;
                }
            }
            Assert.areEqual('Added to ClickUp', step.workflowStatus, 'The read side carries it.');
            Assert.areEqual('CU-7', step.externalRef, 'The ref is stored trimmed.');
            Assert.areEqual(0, report.summary.untriagedFailedSteps,
                'A triaged failure leaves the queue.');
            Assert.areEqual(0, report.cases.rows[0].stepsUntriaged,
                'The case rollup follows.');
        }
    }

    @IsTest
    static void releasedRunStepsStayOutOfTheUntriagedQueue() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Id stepId = failedStepOn(cycle);
            update new Test_Execution__c(
                Id = [SELECT Test_Execution__c FROM Test_Step_Result__c WHERE Id = :stepId]
                    .Test_Execution__c,
                Released__c = true
            );

            UatReportController.CycleReportDTO report = UatReportController.getCycleReport(cycle.Id);
            Assert.areEqual(0, report.summary.untriagedFailedSteps,
                'A released run is a superseded attempt — its failures are not a queue.');
            Assert.areEqual(0, report.cases.rows[0].stepsUntriaged,
                'The case rollup skips released runs the same way its other step counters do.');
        }
    }

    @IsTest
    static void stepStatusWriteRefusesBadInput() {
        asAdmin();
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            Id stepId = failedStepOn(cycle);

            try {
                UatReportController.setStepWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'resultId' => stepId, 'status' => 'Done'
                }));
                Assert.fail('The value set is restricted; the message should beat the DML error.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('workflow status'), e.getMessage());
            }
            try {
                UatReportController.setStepWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'status' => 'Resolved'
                }));
                Assert.fail('A null step result is a caller bug.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Missing step result'), e.getMessage());
            }

            delete [SELECT Id FROM Test_Step_Result__c WHERE Id = :stepId];
            try {
                UatReportController.setStepWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'resultId' => stepId, 'status' => 'Resolved'
                }));
                Assert.fail('A deleted step result should say so, not silently no-op.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
            }
        }
    }

    @IsTest
    static void testersCannotSetStepWorkflowStatus() {
        asAdmin();
        Id stepId;
        System.runAs(byLastName('UAT uatrpt')) {
            Test_Cycle__c cycle = cycleWithCases(1, 2);
            stepId = failedStepOn(cycle);
        }
        // No console override: the tester's real (absent) permission decides.
        UatAudienceService.uatConsoleOverride = null;
        System.runAs(byLastName('UAT uatrpt1')) {
            try {
                UatReportController.setStepWorkflowStatus(JSON.serialize(new Map<String, Object>{
                    'resultId' => stepId, 'status' => 'Resolved'
                }));
                Assert.fail('Step triage is admin-only, like finding triage.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }
}