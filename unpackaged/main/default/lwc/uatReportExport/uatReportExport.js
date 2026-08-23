/**
 * uatReportExport — the column contract for the Cycle Report, and the workbook
 * builder that walks a CycleReportDTO into spreadsheet sheets.
 *
 * Pure module, no template and no SheetJS: it returns [{ name, rows }] where
 * rows are plain arrays. c/xlsxUtil turns those into bytes. Keeping the walk
 * dependency-free is what lets Jest assert sheet names, row counts and cell
 * values without loading a 280 KB vendor bundle.
 *
 * COLUMNS is shared with adminUatReport's per-tab CSV export, so a column added
 * for the workbook shows up in the CSV and vice versa — one contract, not two
 * that drift.
 *
 * Conventions, held from the CSV export this replaces: AutoNumber then the
 * 18-char Salesforce Id as the first two columns of every data sheet,
 * snake_case headers, ISO 8601 datetimes, dates by string slice, TRUE/FALSE
 * booleans, empty string for null, and evidence URLs deduped by
 * ContentDocumentId and absolutised so a link survives being emailed.
 */
import { cellValue, isoDate, isoDateTime, csvBoolean } from 'c/csvUtil';
import { humanizeCaseCode } from 'c/uatTitleUtil';

/** Excel tab names. Order is the order they appear in the workbook. */
export const SHEETS = {
    summary: 'Summary',
    testResults: 'Test Results',
    runs: 'Runs',
    findings: 'Findings',
    sessionNotes: 'Sessions & Notes',
    events: 'Assignment Log'
};

/** Shepherd paths are site-relative. A workbook outlives the tab it came from,
 *  so the exported link has to carry its origin. */
export function absoluteUrl(path) {
    if (!path) {
        return '';
    }
    if (path.startsWith('http')) {
        return path;
    }
    return (typeof window === 'undefined' ? '' : window.location.origin) + path;
}

export function evidenceUrls(files) {
    const urls = (files || []).map((f) => absoluteUrl(f.downloadUrl)).filter(Boolean);
    return [...new Set(urls)].join(';');
}

/** The expression every UI surface uses, so an export never disagrees with the
 *  screen it was taken from. */
export function titleOf(row) {
    return (row && (row.caseTitle || humanizeCaseCode(row.caseCode) || row.caseCode)) || '';
}

function text(value) {
    return value === null || value === undefined ? '' : value;
}

function num(value) {
    return value || 0;
}

// ---- Column specs --------------------------------------------------------

const EVIDENCE_COLUMNS = [
    { label: 'evidence_count', value: (r) => num(r.evidenceCount) },
    { label: 'evidence_urls', value: (r) => evidenceUrls(r.files) }
];

/** Case context, repeated on every Test Results row. Denormalised on purpose:
 *  a spreadsheet row has to stand on its own once it is sorted or filtered. */
const CASE_CONTEXT_COLUMNS = [
    { label: 'case_number', value: (r) => text(r.caseNumber) },
    { label: 'case_id', value: (r) => text(r.caseId) },
    { label: 'case_code', value: (r) => text(r.caseCode) },
    { label: 'case_title', value: (r) => titleOf(r) },
    { label: 'case_verdict', value: (r) => text(r.caseVerdict) },
    { label: 'module_path', value: (r) => text(r.modulePath) },
    { label: 'priority', value: (r) => text(r.priority) },
    { label: 'case_in_scope', value: (r) => csvBoolean(r.caseInScope) },
    { label: 'case_scope_sources', value: (r) => text(r.caseScopeSources) }
];

export const COLUMNS = {
    /**
     * Step-result grain with its case and run carried alongside. This is the
     * report's spine: one row per answered or unanswered step, ordered case ->
     * run -> step. A case with no run, and a run with no step results, each
     * still emit one row with the step columns blank — a coverage gap that
     * vanishes from the export is a coverage gap nobody fixes.
     */
    testResults: [
        ...CASE_CONTEXT_COLUMNS,
        { label: 'execution_number', value: (r) => text(r.executionName) },
        { label: 'execution_id', value: (r) => text(r.executionId) },
        { label: 'tester_name', value: (r) => text(r.testerName) },
        { label: 'tester_id', value: (r) => text(r.testerId) },
        { label: 'execution_status', value: (r) => text(r.testingStatus) },
        { label: 'execution_result', value: (r) => text(r.testingResult) },
        { label: 'released', value: (r) => csvBoolean(r.released) },
        { label: 'last_tested_date', value: (r) => isoDate(r.lastTestedDate) },
        { label: 'step_result_number', value: (r) => text(r.stepResultName) },
        { label: 'step_result_id', value: (r) => text(r.stepResultId) },
        { label: 'step_number', value: (r) => text(r.stepNumber) },
        { label: 'step_deleted', value: (r) => csvBoolean(r.stepDeleted) },
        { label: 'test_condition', value: (r) => text(r.stepCondition) },
        { label: 'step_description', value: (r) => text(r.stepDescription) },
        { label: 'expected_result', value: (r) => text(r.expectedResult) },
        { label: 'explore_prompt', value: (r) => text(r.explorePrompt) },
        { label: 'is_explore', value: (r) => csvBoolean(r.isExplore) },
        { label: 'result', value: (r) => text(r.result) },
        { label: 'actual_result', value: (r) => text(r.actualResult) },
        { label: 'explore_notes', value: (r) => text(r.exploreNotes) },
        { label: 'step_workflow_status', value: (r) => text(r.stepWorkflowStatus) },
        { label: 'step_external_ref', value: (r) => text(r.stepExternalRef) },
        ...EVIDENCE_COLUMNS,
        { label: 'text_truncated', value: (r) => csvBoolean(r.textTruncated) }
    ],

    /** Execution grain. Its own sheet because UX rating, recommendation and the
     *  seat timestamps are per-run: repeating them on nine step rows would
     *  triple-count them in any pivot. */
    runs: [
        { label: 'execution_number', fieldName: 'name' },
        { label: 'execution_id', fieldName: 'executionId' },
        { label: 'cycle_name', value: (r) => text(r.cycleName) },
        { label: 'cycle_id', value: (r) => text(r.cycleId) },
        { label: 'case_number', value: (r) => text(r.caseNumber) },
        { label: 'case_id', value: (r) => text(r.caseId) },
        { label: 'case_code', value: (r) => text(r.caseCode) },
        { label: 'case_title', value: (r) => titleOf(r) },
        { label: 'case_version', value: (r) => text(r.caseVersion) },
        { label: 'case_sequence', value: (r) => text(r.caseSequence) },
        { label: 'module_path', value: (r) => text(r.modulePath) },
        { label: 'system_name', value: (r) => text(r.systemName) },
        { label: 'module_group_name', value: (r) => text(r.moduleGroupName) },
        { label: 'module_name', value: (r) => text(r.moduleName) },
        { label: 'priority', value: (r) => text(r.priority) },
        { label: 'estimated_effort', value: (r) => text(r.estimatedEffort) },
        { label: 'testing_surface', value: (r) => text(r.testingSurface) },
        { label: 'tester_name', value: (r) => text(r.testerName) },
        { label: 'tester_id', value: (r) => text(r.testerId) },
        { label: 'team_name', value: (r) => text(r.teamName) },
        { label: 'status', value: (r) => text(r.testingStatus) },
        { label: 'result', value: (r) => text(r.testingResult) },
        { label: 'released', value: (r) => csvBoolean(r.released) },
        { label: 'claimed_at', value: (r) => isoDateTime(r.claimedDate) },
        { label: 'last_tested_date', value: (r) => isoDate(r.lastTestedDate) },
        { label: 'created_at', value: (r) => isoDateTime(r.createdDate) },
        { label: 'last_modified_at', value: (r) => isoDateTime(r.lastModifiedDate) },
        { label: 'steps_total', value: (r) => num(r.stepsTotal) },
        { label: 'steps_answered', value: (r) => num(r.stepsAnswered) },
        { label: 'steps_passed', value: (r) => num(r.stepsPassed) },
        { label: 'steps_failed', value: (r) => num(r.stepsFailed) },
        { label: 'steps_blocked', value: (r) => num(r.stepsBlocked) },
        { label: 'steps_orphaned', value: (r) => num(r.stepsOrphaned) },
        { label: 'ux_rating', value: (r) => text(r.uxRating) },
        { label: 'ux_recommendation', value: (r) => text(r.uxRecommendation) },
        { label: 'identity_key', value: (r) => text(r.identityKey) },
        ...EVIDENCE_COLUMNS,
        { label: 'text_truncated', value: (r) => csvBoolean(r.textTruncated) }
    ],

    findings: [
        { label: 'finding_number', fieldName: 'name' },
        { label: 'finding_id', fieldName: 'findingId' },
        { label: 'title', value: (r) => text(r.title) },
        { label: 'type', value: (r) => text(r.findingType) },
        { label: 'severity', value: (r) => text(r.severity) },
        // Null status exports as New: the picklist default, and what the
        // report shows for the same row.
        { label: 'workflow_status', value: (r) => text(r.workflowStatus || 'New') },
        { label: 'external_ref', value: (r) => text(r.externalRef) },
        { label: 'source', value: (r) => text(r.source) },
        { label: 'what_testing', value: (r) => text(r.whatTesting) },
        { label: 'what_happened', value: (r) => text(r.whatHappened) },
        { label: 'what_expected', value: (r) => text(r.whatExpected) },
        { label: 'no_evidence_reason', value: (r) => text(r.noEvidenceReason) },
        { label: 'flagged_no_evidence', value: (r) => csvBoolean(r.flaggedNoEvidence) },
        { label: 'tester_name', value: (r) => text(r.testerName) },
        { label: 'tester_id', value: (r) => text(r.testerId) },
        { label: 'date_logged', value: (r) => isoDate(r.dateLogged) },
        { label: 'created_at', value: (r) => isoDateTime(r.createdDate) },
        { label: 'last_modified_at', value: (r) => isoDateTime(r.lastModifiedDate) },
        { label: 'cycle_name', value: (r) => text(r.cycleName) },
        { label: 'cycle_id', value: (r) => text(r.cycleId) },
        { label: 'session_number', value: (r) => text(r.sessionName) },
        { label: 'session_id', value: (r) => text(r.sessionId) },
        { label: 'session_title', value: (r) => text(r.sessionTitle) },
        { label: 'source_note_number', value: (r) => text(r.sourceNoteName) },
        { label: 'source_note_id', value: (r) => text(r.sourceNoteId) },
        { label: 'execution_number', value: (r) => text(r.executionName) },
        { label: 'execution_id', value: (r) => text(r.executionId) },
        { label: 'case_id', value: (r) => text(r.caseId) },
        { label: 'case_code', value: (r) => text(r.caseCode) },
        { label: 'case_title', value: (r) => (r.caseCode ? titleOf(r) : '') },
        { label: 'step_result_number', value: (r) => text(r.stepResultName) },
        { label: 'step_result_id', value: (r) => text(r.stepResultId) },
        ...EVIDENCE_COLUMNS,
        { label: 'text_truncated', value: (r) => csvBoolean(r.textTruncated) }
    ],

    sessionNotes: [
        { label: 'note_number', fieldName: 'name' },
        { label: 'note_id', fieldName: 'noteId' },
        { label: 'session_number', value: (r) => text(r.sessionName) },
        { label: 'session_id', value: (r) => text(r.sessionId) },
        { label: 'session_title', value: (r) => text(r.sessionTitle) },
        { label: 'session_status', value: (r) => text(r.sessionStatus) },
        { label: 'session_area', value: (r) => text(r.sessionArea) },
        { label: 'session_started_at', value: (r) => isoDateTime(r.sessionStartedAt) },
        { label: 'session_finished_at', value: (r) => isoDateTime(r.sessionFinishedAt) },
        { label: 'session_duration_minutes', value: (r) => text(r.sessionDurationMinutes) },
        { label: 'session_tester_name', value: (r) => text(r.sessionTesterName) },
        { label: 'cycle_name', value: (r) => text(r.cycleName) },
        { label: 'cycle_id', value: (r) => text(r.cycleId) },
        { label: 'logged_at', value: (r) => isoDateTime(r.loggedAt) },
        { label: 'tag', value: (r) => text(r.tag) },
        { label: 'author_name', value: (r) => text(r.authorName) },
        { label: 'author_id', value: (r) => text(r.authorId) },
        { label: 'entry_text', value: (r) => text(r.text) },
        { label: 'logged_from_execution_number', value: (r) => text(r.executionName) },
        { label: 'logged_from_execution_id', value: (r) => text(r.executionId) },
        { label: 'logged_from_case_code', value: (r) => text(r.caseCode) },
        { label: 'promoted_finding_number', value: (r) => text(r.promotedFindingName) },
        { label: 'promoted_finding_id', value: (r) => text(r.promotedFindingId) },
        ...EVIDENCE_COLUMNS,
        { label: 'text_truncated', value: (r) => csvBoolean(r.textTruncated) }
    ],

    events: [
        { label: 'event_number', fieldName: 'name' },
        { label: 'event_id', fieldName: 'eventId' },
        { label: 'action', value: (r) => text(r.action) },
        { label: 'occurred_at', value: (r) => isoDateTime(r.occurredAt) },
        { label: 'tester_name', value: (r) => text(r.testerName) },
        { label: 'tester_id', value: (r) => text(r.testerId) },
        { label: 'actor_name', value: (r) => text(r.actorName) },
        { label: 'actor_id', value: (r) => text(r.actorId) },
        { label: 'reason', value: (r) => text(r.reason) },
        { label: 'execution_number', value: (r) => text(r.executionName) },
        { label: 'execution_id', value: (r) => text(r.executionId) },
        { label: 'case_code', value: (r) => text(r.caseCode) },
        { label: 'case_id', value: (r) => text(r.caseId) },
        { label: 'cycle_name', value: (r) => text(r.cycleName) },
        { label: 'cycle_id', value: (r) => text(r.cycleId) },
        { label: 'text_truncated', value: (r) => csvBoolean(r.textTruncated) }
    ]
};

// ---- Row shapers ---------------------------------------------------------

function rowsOf(grain) {
    return (grain && grain.rows) || [];
}

function indexById(rows, key) {
    const map = {};
    (rows || []).forEach((row) => {
        map[row[key]] = row;
    });
    return map;
}

/**
 * One Test Results row: the case, the run beneath it, and the step beneath
 * that — any of the last two possibly absent.
 *
 * Evidence follows the row's own grain: a step row reports the step's files, a
 * run row with no steps reports the run's. Run-level evidence is never lost —
 * the Runs sheet carries every run's files in full.
 */
function testResultRow(caseRow, run, step) {
    const source = step || run || {};
    return {
        caseNumber: caseRow.caseNumber,
        caseId: caseRow.caseId,
        caseCode: caseRow.caseCode,
        caseTitle: caseRow.caseTitle,
        caseVerdict: caseRow.verdict,
        modulePath: caseRow.modulePath,
        priority: caseRow.priority,
        caseInScope: caseRow.inScope,
        caseScopeSources: caseRow.scopeSources,
        executionName: run ? run.name : '',
        executionId: run ? run.executionId : '',
        testerName: run ? run.testerName : '',
        testerId: run ? run.testerId : '',
        testingStatus: run ? run.testingStatus : '',
        testingResult: run ? run.testingResult : '',
        released: run ? run.released : '',
        lastTestedDate: run ? run.lastTestedDate : '',
        stepResultName: step ? step.name : '',
        stepResultId: step ? step.resultId : '',
        stepNumber: step ? step.stepNumber : '',
        stepDeleted: step ? step.stepDeleted : '',
        stepCondition: step ? step.stepCondition : '',
        stepDescription: step ? step.stepDescription : '',
        expectedResult: step ? step.expectedResult : '',
        explorePrompt: step ? step.explorePrompt : '',
        isExplore: step ? step.isExplore : '',
        result: step ? step.result : '',
        actualResult: step ? step.actualResult : '',
        exploreNotes: step ? step.exploreNotes : '',
        // '' — not 'New' — on the case/run filler rows: a triage status for a
        // step that does not exist would be a false claim in the export.
        stepWorkflowStatus: step ? step.workflowStatus || 'New' : '',
        stepExternalRef: step ? step.externalRef || '' : '',
        evidenceCount: source.evidenceCount,
        files: source.files,
        textTruncated: source.textTruncated
    };
}

/**
 * Case -> run -> step, in report order. The flat step-result grain the old
 * Step Results tab exported was ordered by run, which put two seats on the same
 * case in different parts of the file.
 */
export function buildTestResultRows(report, scope) {
    const execById = indexById(rowsOf(report.executions), 'executionId');
    const rows = [];
    scopedCases(report, scope).forEach((caseRow) => {
        const runs = (caseRow.executionIds || []).map((id) => execById[id]).filter(Boolean);
        if (!runs.length) {
            rows.push(testResultRow(caseRow, null, null));
            return;
        }
        runs.forEach((run) => {
            const steps = run.steps || [];
            if (!steps.length) {
                rows.push(testResultRow(caseRow, run, null));
                return;
            }
            steps.forEach((step) => rows.push(testResultRow(caseRow, run, step)));
        });
    });
    return rows;
}

/** Session headers flattened onto their entries — a note row that cannot say
 *  which session it came from is unreadable once sorted. */
export function buildNoteRows(report) {
    const rows = [];
    rowsOf(report.sessions).forEach((session) => {
        (session.notes || []).forEach((note) => {
            rows.push({
                ...note,
                sessionStatus: session.status,
                sessionArea: session.areaText,
                sessionStartedAt: session.startedAt,
                sessionFinishedAt: session.finishedAt,
                sessionDurationMinutes: session.durationMinutes,
                sessionTesterName: session.testerName,
                cycleName: session.cycleName,
                cycleId: session.cycleId
            });
        });
    });
    return rows;
}

// ---- Scoping -------------------------------------------------------------

function scopedCases(report, scope) {
    const cases = rowsOf(report.cases);
    if (!scope || !scope.caseId) {
        return cases;
    }
    return cases.filter((row) => row.caseId === scope.caseId);
}

function scopedRuns(report, scope) {
    const runs = rowsOf(report.executions);
    if (!scope || !scope.caseId) {
        return runs;
    }
    return runs.filter((row) => row.caseId === scope.caseId);
}

/** Findings the case owns, resolved server-side into CaseRowDTO.findingIds —
 *  a finding can reach its case through its run OR through a step result, and
 *  the client should not re-derive a rule Apex already applied. */
function scopedFindings(report, scope) {
    const findings = rowsOf(report.findings);
    if (!scope || !scope.caseId) {
        return findings;
    }
    const caseRow = scopedCases(report, scope)[0];
    const owned = new Set((caseRow && caseRow.findingIds) || []);
    return findings.filter((row) => owned.has(row.findingId));
}

function scopedEvents(report, scope) {
    const events = rowsOf(report.events);
    if (!scope || !scope.caseId) {
        return events;
    }
    return events.filter((row) => row.caseId === scope.caseId);
}

// ---- Summary sheet -------------------------------------------------------

function pair(rows, field, value) {
    rows.push([field, value === null || value === undefined ? '' : value]);
}

function severityCounts(report) {
    const counts = {};
    (report.summary.findingsByTypeAndSeverity || []).forEach((cell) => {
        if (cell.findingType === 'Defect' && cell.severity) {
            counts[cell.severity] = (counts[cell.severity] || 0) + cell.count;
        }
    });
    return counts;
}

/**
 * The cover sheet: who ran this, over what, and whether it is whole.
 *
 * Two columns and roughly thirty rows, deliberately — it is the thing you read
 * before trusting the other sheets, so it has to fit on one screen. Anything
 * that needs a third column belongs on a data sheet.
 */
export function buildSummarySheet(report, scope) {
    const s = report.summary || {};
    const cases = scopedCases(report, scope);
    const caseScoped = Boolean(scope && scope.caseId);
    const caseRow = caseScoped ? cases[0] : null;
    const rows = [['field', 'value']];

    pair(rows, 'generated_at', isoDateTime(report.generatedAt));
    pair(rows, 'generated_by', report.generatedByName);
    pair(rows, 'generated_by_user_id', report.generatedById);
    pair(rows, 'export_scope', caseScoped ? 'Single test case' : report.scope);
    if (report.cycle) {
        pair(rows, 'cycle_name', report.cycle.cycleName);
        pair(rows, 'cycle_id', report.cycle.cycleId);
        pair(rows, 'cycle_status', report.cycle.status);
        pair(rows, 'cycle_target_date', isoDate(report.cycle.targetDate));
        pair(rows, 'assigned_team', report.cycle.teamName);
    }

    if (caseRow) {
        rows.push([]);
        pair(rows, 'case_number', caseRow.caseNumber);
        pair(rows, 'case_id', caseRow.caseId);
        pair(rows, 'case_code', caseRow.caseCode);
        pair(rows, 'case_title', titleOf(caseRow));
        pair(rows, 'module_path', caseRow.modulePath);
        pair(rows, 'case_verdict', caseRow.verdict);
        pair(rows, 'case_in_scope', csvBoolean(caseRow.inScope));
        pair(rows, 'testers', (caseRow.testerNames || []).join('; '));
        pair(rows, 'steps_answered', `${num(caseRow.stepsAnswered)} of ${num(caseRow.stepsTotal)}`);
        pair(rows, 'steps_failed', num(caseRow.stepsFailed));
        pair(rows, 'steps_blocked', num(caseRow.stepsBlocked));
    } else {
        rows.push([]);
        pair(rows, 'cases_total', num(s.caseCount));
        pair(rows, 'cases_complete', num(s.casesComplete));
        pair(rows, 'cases_passed', num(s.casesPassed));
        pair(rows, 'cases_failed', num(s.casesFailed));
        pair(rows, 'cases_blocked', num(s.casesBlocked));
        pair(rows, 'cases_postponed', num(s.casesPostponed));
        pair(rows, 'cases_in_progress', num(s.casesInProgress));
        pair(rows, 'cases_not_started', num(s.casesNotStarted));
        pair(rows, 'cases_without_runs', num(s.casesWithoutRuns));
    }

    rows.push([]);
    const severities = severityCounts(report);
    ['Critical', 'High', 'Medium', 'Low'].forEach((severity) => {
        if (severities[severity]) {
            pair(rows, `defects_${severity.toLowerCase()}`, severities[severity]);
        }
    });
    (s.findingsByType || []).forEach((row) => {
        pair(rows, `findings_type_${String(row.label || 'unset').toLowerCase().replace(/\s+/g, '_')}`, row.count);
    });
    (s.findingsByStatus || []).forEach((row) => {
        pair(
            rows,
            `findings_status_${String(row.label || 'unset').toLowerCase().replace(/[\s']+/g, '_')}`,
            row.count
        );
    });
    if (s.untriagedDefects) {
        pair(rows, 'untriaged_defects', s.untriagedDefects);
    }
    if (s.untriagedFailedSteps) {
        pair(rows, 'untriaged_failed_steps', s.untriagedFailedSteps);
    }

    rows.push([]);
    pair(rows, 'rows_test_results', buildTestResultRows(report, scope).length);
    pair(rows, 'rows_runs', scopedRuns(report, scope).length);
    pair(rows, 'rows_findings', scopedFindings(report, scope).length);
    if (!caseScoped) {
        pair(rows, 'rows_session_notes', buildNoteRows(report).length);
    }
    pair(rows, 'rows_assignment_log', scopedEvents(report, scope).length);

    rows.push([]);
    const cut = truncationLabels(report);
    pair(rows, 'report_complete', csvBoolean(cut.length === 0));
    if (cut.length) {
        pair(rows, 'truncated_grains', cut.join('; '));
    }
    const flags = s.dataQualityFlags || [];
    pair(rows, 'data_quality_flags', flags.length);
    if (flags.length) {
        pair(rows, 'flagged_findings', flags.map((f) => f.findingName).join('; '));
    }
    return { name: SHEETS.summary, rows };
}

/** Every grain that cut rows, named. The report says so on screen too; the
 *  workbook has to carry it or an emailed file looks complete. */
export function truncationLabels(report) {
    const cut = [];
    const add = (flag, label) => {
        if (flag) {
            cut.push(label);
        }
    };
    add(report.cases && report.cases.truncated, 'Test cases');
    add(report.executions && report.executions.truncated, 'Runs');
    add(report.executions && report.executions.stepsTruncated, 'Step results');
    add(report.sessions && report.sessions.truncated, 'Sessions');
    add(report.sessions && report.sessions.notesTruncated, 'Log entries');
    add(report.findings && report.findings.truncated, 'Findings');
    add(report.events && report.events.truncated, 'Assignment log');
    return cut;
}

// ---- Workbook ------------------------------------------------------------

/** Header row plus one array per record, resolved through the shared specs. */
export function sheetFrom(name, columns, rows) {
    const body = (rows || []).map((row) => columns.map((column) => cellValue(row, column)));
    return { name, rows: [columns.map((column) => column.label), ...body] };
}

/**
 * The whole export, in one call.
 *
 * @param scope { caseId } — omit for the full cycle. A case-scoped workbook
 *              drops Sessions & Notes (a session belongs to a cycle, not to a
 *              case) and keeps everything else, filtered. One builder with one
 *              argument, so the two exports can never disagree about what a
 *              column means.
 */
export function buildWorkbookSheets(report, scope) {
    if (!report) {
        return [];
    }
    const caseScoped = Boolean(scope && scope.caseId);
    const sheets = [
        buildSummarySheet(report, scope),
        sheetFrom(SHEETS.testResults, COLUMNS.testResults, buildTestResultRows(report, scope)),
        sheetFrom(SHEETS.runs, COLUMNS.runs, scopedRuns(report, scope)),
        sheetFrom(SHEETS.findings, COLUMNS.findings, scopedFindings(report, scope))
    ];
    if (!caseScoped) {
        sheets.push(sheetFrom(SHEETS.sessionNotes, COLUMNS.sessionNotes, buildNoteRows(report)));
    }
    sheets.push(sheetFrom(SHEETS.events, COLUMNS.events, scopedEvents(report, scope)));
    return sheets;
}