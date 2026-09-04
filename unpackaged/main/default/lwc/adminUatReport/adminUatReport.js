import { LightningElement } from 'lwc';
import getCycles from '@salesforce/apex/UatCycleAdminController.getCycles';
import getCycleReport from '@salesforce/apex/UatReportController.getCycleReport';
import getStandaloneReport from '@salesforce/apex/UatReportController.getStandaloneReport';
/* Moderation reuses the tester surface's endpoints unchanged — owner-or-admin on
 * the server, and UAT_Console admins pass. No new write path exists for the
 * report, and saveFinding stamps Tester/Date/Source on CREATE only, so an admin
 * edit cannot take authorship of someone else's finding. */
import saveFinding from '@salesforce/apex/UatRunController.saveFinding';
import deleteFinding from '@salesforce/apex/UatRunController.deleteFinding';
/* The report's own writes: the pair of admin triage dispositions (findings
 * and step failures). Gated by UAT_Console server-side like the reads. */
import setFindingWorkflowStatus from '@salesforce/apex/UatReportController.setFindingWorkflowStatus';
import setStepWorkflowStatus from '@salesforce/apex/UatReportController.setStepWorkflowStatus';
import { logError, messageFrom, reportError, toast } from 'c/messageUtil';
import {
    STEP_RESULTS,
    FINDING_TYPES,
    FINDING_TYPE_DEFECT,
    DEFECT_SEVERITIES,
    EVIDENCE_REQUIRED_SEVERITIES,
    SESSION_STATUSES,
    SEVERITY_VARIANT,
    RESULT_VARIANT,
    FINDING_TYPE_VARIANT,
    FINDING_SOURCE_VARIANT,
    SESSION_STATUS_VARIANT,
    CYCLE_STATUS_VARIANT,
    WORKFLOW_STATUSES,
    WORKFLOW_STATUS_NEW,
    WORKFLOW_STATUSES_IN_TRACKER,
    WORKFLOW_STATUS_VARIANT,
    findingViewModel,
    toFilterOptions,
    toOptions
} from 'c/uatConstants';
import { formatDateLong, formatDateTimeLong, matchesSearch } from 'c/uatCardUtil';
import { formatDurationMinutes } from 'c/rcConstants';
import { shortCaseRef } from 'c/uatTitleUtil';
import { slugify } from 'c/slugUtil';
import { buildCsvContent, csvFilename, downloadBlob, downloadCsv, isoDate } from 'c/csvUtil';
import { loadXlsx, sheetsToXlsxBlob, xlsxFilename } from 'c/xlsxUtil';
import {
    COLUMNS,
    buildNoteRows,
    buildTestResultRows,
    buildWorkbookSheets,
    titleOf
} from 'c/uatReportExport';

const STANDALONE = 'standalone';
const PAGE_SIZE = 10;
const DASH = '—';
/** Past this, a "session" is almost certainly a browser tab left open, not
 *  testing. The duration still shows — muted, with the doubt in the tooltip —
 *  because hiding it would misreport the data. Display-only. */
const LONG_SESSION_MINUTES = 480;
const LONG_SESSION_TITLE =
    'Session may have been left open — this is wall-clock time between start and finish.';
/** The Findings tab's status filter buckets: the two Added-to-* values
 *  collapse into one "In tracker" chip. */
const STATUS_FILTER_TRACKER = 'tracker';
/** Log prefix. Every catch in this bundle logs the real error object and names
 *  the operation in its toast — a generic toast with nothing in the console is
 *  what made the broken export undiagnosable from the outside. */
const BUNDLE = 'adminUatReport';

/** One descriptor per tab. Drives the tab strip, the CSV file stem, the column
 *  spec and the export labels, so a new grain is one row, not five.
 *
 *  The assignment log is deliberately absent: it is an audit trail, not a
 *  reading surface, and it renders as a collapsed section at the foot of the
 *  page instead. It is still in every export. */
const GRAINS = [
    {
        key: 'testResults',
        label: 'Test Results',
        file: 'test_results',
        columns: 'testResults',
        itemLabel: 'test cases'
    },
    { key: 'findings', label: 'Findings', file: 'findings', columns: 'findings', itemLabel: 'findings' },
    {
        key: 'sessions',
        label: 'Sessions & Notes',
        file: 'session_notes',
        columns: 'sessionNotes',
        itemLabel: 'sessions'
    }
];
const EVENT_GRAIN = { file: 'assignment_log', columns: 'events' };

// Filter dropdowns pass '' as the catch-all so filteredRows can treat falsy as
// "no filter" — the adminUatCases contract.
const STEP_RESULT_OPTIONS = toFilterOptions('All step results', STEP_RESULTS, '');
const FINDING_SEVERITY_OPTIONS = toFilterOptions('All severities', DEFECT_SEVERITIES, '');
const SESSION_STATUS_OPTIONS = toFilterOptions('All statuses', SESSION_STATUSES, '');
const FINDING_SOURCE_OPTIONS = [
    { label: 'All sources', value: '' },
    { label: 'Session', value: 'Session' },
    { label: 'Test case', value: 'Test case' }
];

/** Viewer edit form. Mirrors the tester form's rules so an admin hears about a
 *  gap without a round trip; UatRunController.saveFinding is still the
 *  authority, and it force-clears severity on a non-defect either way. */
const TITLE_MIN = 10;
const FORM_TYPE_OPTIONS = toOptions(FINDING_TYPES);
const FORM_SEVERITY_OPTIONS = [{ label: 'No severity', value: '' }].concat(
    toOptions(DEFECT_SEVERITIES)
);
const DELETE_WARNING =
    'The finding and its evidence are deleted for the whole team and cannot be recovered.';

const CASE_SORT_OPTIONS = [
    { label: 'Case sequence', value: 'default' },
    { label: 'Worst verdict first', value: 'verdict' },
    { label: 'Tester (A–Z)', value: 'tester' }
];
const FINDING_SORT_OPTIONS = [
    { label: 'Severity, then newest', value: 'default' },
    { label: 'Newest first', value: 'reported' },
    { label: 'Type', value: 'type' }
];
const SESSION_SORT_OPTIONS = [
    { label: 'Newest session first', value: 'default' },
    { label: 'Tester (A–Z)', value: 'tester' },
    { label: 'Most entries', value: 'notes' }
];
const EVENT_SORT_OPTIONS = [
    { label: 'Newest first', value: 'default' },
    { label: 'Oldest first', value: 'oldest' }
];

/** Worst first — the order the verdict rule itself resolves in, so the sort and
 *  the rule never tell different stories. */
const CASE_VERDICTS = ['Failed', 'Blocked', 'In progress', 'Postponed', 'Passed', 'Not started'];
const CASE_VERDICT_ORDER = {
    Failed: 0,
    Blocked: 1,
    'In progress': 2,
    Postponed: 3,
    Passed: 4,
    'Not started': 5
};
const CASE_VERDICT_VARIANT = {
    Passed: RESULT_VARIANT.Passed,
    Failed: RESULT_VARIANT.Failed,
    Blocked: RESULT_VARIANT.Blocked,
    Postponed: 'default',
    'In progress': 'default',
    'Not started': 'default'
};

const SEVERITY_ORDER = { Critical: 0, High: 1, Medium: 2, Low: 3 };
/** uatConstants owns RESULT_VARIANT for run verdicts (Passed/Failed/Blocked);
 *  step results use the shorter Pass/Fail/Blocked/N/A vocabulary. */
const STEP_RESULT_VARIANT = { Pass: 'success', Fail: 'error', Blocked: 'warning', 'N/A': 'default' };

function rank(map, value) {
    return map[value] === undefined ? 99 : map[value];
}

// ---- Comparators (never mutate the source; sort() is stable, so the server's
// order survives as the tiebreak) ------------------------------------------

function byCaseSequence(a, b) {
    const sa = a.caseSequence === null || a.caseSequence === undefined ? Infinity : a.caseSequence;
    const sb = b.caseSequence === null || b.caseSequence === undefined ? Infinity : b.caseSequence;
    if (sa !== sb) {
        return sa - sb;
    }
    return (a.caseCode || '').localeCompare(b.caseCode || '');
}
function byVerdictThenSequence(a, b) {
    const r = rank(CASE_VERDICT_ORDER, a.verdict) - rank(CASE_VERDICT_ORDER, b.verdict);
    return r !== 0 ? r : byCaseSequence(a, b);
}
/** Unnamed testers sort last. Explicitly, not via a high sentinel character —
 *  U+FFFF is a Unicode noncharacter and the Metadata API rejects the file. */
function nameCompare(na, nb) {
    if (!na && !nb) {
        return 0;
    }
    if (!na) {
        return 1;
    }
    if (!nb) {
        return -1;
    }
    return na.localeCompare(nb);
}
function byNameAsc(a, b) {
    return nameCompare(a.testerName, b.testerName);
}
function byCaseTesterAsc(a, b) {
    const c = nameCompare((a.testerNames || [])[0], (b.testerNames || [])[0]);
    return c !== 0 ? c : byCaseSequence(a, b);
}
function bySeverityThenDateDesc(a, b) {
    const r = rank(SEVERITY_ORDER, a.severity) - rank(SEVERITY_ORDER, b.severity);
    if (r !== 0) {
        return r;
    }
    return String(b.dateLogged || '').localeCompare(String(a.dateLogged || ''));
}
function byReportedDesc(a, b) {
    return String(b.dateLogged || '').localeCompare(String(a.dateLogged || ''));
}
function byFindingType(a, b) {
    return (a.findingType || '').localeCompare(b.findingType || '');
}
function bySessionStartedDesc(a, b) {
    return String(b.startedAt || '').localeCompare(String(a.startedAt || ''));
}
/** Null means 'New': pre-backfill rows and the picklist default agree. */
function statusOf(row) {
    return row.workflowStatus || WORKFLOW_STATUS_NEW;
}
function byNoteCountDesc(a, b) {
    return (b.noteCount || 0) - (a.noteCount || 0);
}
function byOccurredDesc(a, b) {
    return String(b.occurredAt || '').localeCompare(String(a.occurredAt || ''));
}
function byOccurredAsc(a, b) {
    return String(a.occurredAt || '').localeCompare(String(b.occurredAt || ''));
}

export default class AdminUatReport extends LightningElement {
    // ---- Load state
    report;
    cycles = [];
    loading = true;
    reportLoading = false;
    errorMessage;

    // ---- Scope
    scope;

    // ---- Tabs / row disclosure
    activeTab = 'testResults';
    expandedEvidenceKey = null;
    expandedSessionId = null;
    /** Sets, reassigned on every mutation — LWC does not observe Set.add(). */
    expandedCaseIds = new Set();
    expandedExecIds = new Set();
    assignmentOpen = false;

    // ---- Per-tab filter state
    caseSearch = '';
    caseVerdict = 'all';
    caseTester = '';
    caseStepResult = '';
    caseSort = 'default';
    casePage = 1;

    findingSearch = '';
    findingType = 'all';
    findingStatus = 'all';
    findingSeverity = '';
    findingSource = '';
    findingSort = 'default';
    findingPage = 1;

    sessionSearch = '';
    sessionStatus = '';
    sessionTester = '';
    sessionSort = 'default';
    sessionPage = 1;

    eventSearch = '';
    eventAction = '';
    eventSort = 'default';
    eventPage = 1;

    // ---- Finding viewer
    /** { findingIds: Id[], findingId: Id|null, caseCode: String|null } — a list
     *  when findingId is null, one finding when it is set. */
    viewer = null;
    viewerForm = null;
    viewerConfirm = false;
    viewerBusy = false;

    // ---- Workflow-status picker
    /** { kind: 'finding'|'step', recordId, name, current, ref, picked } —
     *  picked is null until an Added-to-* status is chosen, which reveals the
     *  ticket-ref input. One dialog serves both triage grains; only the
     *  opener and the save endpoint branch on kind. */
    statusPrompt = null;
    statusBusy = false;

    // ---- Export
    exporting = false;

    // ---- Lifecycle -------------------------------------------------------

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            // Sequential by data dependency: the default scope is not knowable
            // until the cycle list resolves, so Promise.all does not apply.
            this.cycles = (await getCycles()) || [];
            this.scope = this.defaultScope();
            this.report = await this.fetchReport(this.scope);
            this.errorMessage = undefined;
        } catch (e) {
            // The banner stays user-facing (messageFrom), but the console gets
            // the error itself: a client-side failure here is indistinguishable
            // from a server one on screen.
            logError(BUNDLE, 'Report load', e);
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    fetchReport(scope) {
        return scope === STANDALONE ? getStandaloneReport() : getCycleReport({ cycleId: scope });
    }

    defaultScope() {
        const open = this.cycles.find((c) => c.status !== 'Closed');
        if (open) {
            return open.cycleId || open.id;
        }
        if (this.cycles.length) {
            return this.cycles[0].cycleId || this.cycles[0].id;
        }
        return STANDALONE;
    }

    async reloadReport() {
        this.reportLoading = true;
        try {
            this.report = await this.fetchReport(this.scope);
            this.resetFilters();
        } catch (e) {
            // Post-load failures toast; only the initial load takes the banner.
            reportError(this, BUNDLE, 'Report load', e);
        } finally {
            this.reportLoading = false;
        }
    }

    resetFilters() {
        this.activeTab = 'testResults';
        this.expandedEvidenceKey = null;
        this.expandedSessionId = null;
        this.expandedCaseIds = new Set();
        this.expandedExecIds = new Set();
        this.assignmentOpen = false;
        this.caseSearch = '';
        this.caseVerdict = 'all';
        this.caseTester = '';
        this.caseStepResult = '';
        this.caseSort = 'default';
        this.casePage = 1;
        this.findingSearch = '';
        this.findingType = 'all';
        this.findingStatus = 'all';
        this.findingSeverity = '';
        this.findingSource = '';
        this.findingSort = 'default';
        this.findingPage = 1;
        this.sessionSearch = '';
        this.sessionStatus = '';
        this.sessionTester = '';
        this.sessionSort = 'default';
        this.sessionPage = 1;
        this.eventSearch = '';
        this.eventAction = '';
        this.eventSort = 'default';
        this.eventPage = 1;
    }

    // ---- Shell / scope ---------------------------------------------------

    get scopeOptions() {
        const options = this.cycles.map((c) => {
            const id = c.cycleId || c.id;
            const suffix = c.status && c.status !== 'Active' ? ` (${c.status})` : '';
            return { label: (c.cycleName || c.name || 'Untitled cycle') + suffix, value: id };
        });
        options.push({ label: 'Standalone work (no cycle)', value: STANDALONE });
        return options;
    }

    get isStandalone() {
        return this.scope === STANDALONE;
    }

    get selectedCycleName() {
        if (this.isStandalone) {
            return 'Standalone work';
        }
        return this.report && this.report.cycle ? this.report.cycle.cycleName : '';
    }

    get cycleSlug() {
        return slugify(this.selectedCycleName || 'uat-report') || 'uat-report';
    }

    get scopeLabel() {
        return this.isStandalone ? 'Standalone work' : 'Test cycle';
    }

    get summary() {
        return this.report ? this.report.summary : null;
    }

    get hasReport() {
        return Boolean(this.report) && !this.isEmpty;
    }

    get isEmpty() {
        if (!this.report) {
            return false;
        }
        const s = this.report.summary;
        return !s.caseCount && !s.executionCount && !s.sessionCount && !s.findingCount && !s.eventCount;
    }

    get summaryTitle() {
        return this.selectedCycleName || 'Cycle report';
    }

    get statusBadge() {
        const status = this.report && this.report.cycle ? this.report.cycle.status : null;
        return { label: status || DASH, variant: CYCLE_STATUS_VARIANT[status] || 'default' };
    }

    get hasCycleHeader() {
        return Boolean(this.report && this.report.cycle);
    }

    get targetLabel() {
        const cycle = this.report ? this.report.cycle : null;
        if (!cycle || !cycle.targetDate) {
            return 'No target date';
        }
        return `Target ${formatDateLong(cycle.targetDate)}`;
    }

    // ---- Summary ---------------------------------------------------------

    /** The headline number: how much of the cycle is answered. Zero stays
     *  visible here — "0 of 78 cases complete" IS the signal. */
    get caseProgressLabel() {
        const s = this.summary;
        if (!s) {
            return '';
        }
        const total = s.caseCount || 0;
        return `${s.casesComplete || 0} of ${total} ${total === 1 ? 'case' : 'cases'} complete`;
    }

    get hasCases() {
        return Boolean(this.summary && this.summary.caseCount);
    }

    /** Verdicts with no cases are not rendered: a column of zeros reads as data
     *  and is only noise. */
    get caseSpread() {
        const s = this.summary;
        if (!s) {
            return [];
        }
        const counts = {
            Passed: s.casesPassed,
            Failed: s.casesFailed,
            Blocked: s.casesBlocked,
            Postponed: s.casesPostponed,
            'In progress': s.casesInProgress,
            'Not started': s.casesNotStarted
        };
        return CASE_VERDICTS.filter((v) => counts[v] > 0).map((v) => ({
            key: v,
            label: v,
            count: counts[v],
            variant: CASE_VERDICT_VARIANT[v]
        }));
    }

    /** Defect-type findings only, by severity. Workflow_Status__c (2026-08) now
     *  carries the open/closed-ish state; the untriaged queue surfaces in
     *  dataQualityFlags, and this spread deliberately stays severity-only. */
    get defectSpread() {
        const cells = this.summary ? this.summary.findingsByTypeAndSeverity || [] : [];
        const counts = {};
        cells.forEach((cell) => {
            if (cell.findingType === 'Defect' && cell.severity) {
                counts[cell.severity] = (counts[cell.severity] || 0) + cell.count;
            }
        });
        return DEFECT_SEVERITIES.slice()
            .reverse()
            .filter((sev) => counts[sev] > 0)
            .map((sev) => ({
                key: sev,
                label: sev,
                count: counts[sev],
                variant: SEVERITY_VARIANT[sev]
            }));
    }

    get hasDefectSpread() {
        return this.defectSpread.length > 0;
    }

    get testerActivity() {
        const rows = this.summary ? this.summary.testers || [] : [];
        return [...rows].sort(byNameAsc).map((t) => ({
            key: t.testerId,
            testerName: t.testerName || 'Unknown user',
            assigned: t.runsAssigned || 0,
            complete: t.runsComplete || 0,
            released: t.runsReleased || 0,
            steps: t.stepsAnswered || 0,
            findings: t.findingsLogged || 0,
            notes: t.notesLogged || 0
        }));
    }

    get hasTesterActivity() {
        return this.testerActivity.length > 0;
    }

    /** A column of zeros for every tester says nothing; one nonzero release is
     *  worth the whole column. */
    get showReleasedColumn() {
        return this.testerActivity.some((t) => t.released > 0);
    }

    get sessionLine() {
        const s = this.summary;
        if (!s || !s.sessionCount) {
            return null;
        }
        const sessions = `${s.sessionCount} exploratory ${s.sessionCount === 1 ? 'session' : 'sessions'}`;
        const notes = `${s.noteCount || 0} log ${s.noteCount === 1 ? 'entry' : 'entries'}`;
        return `${sessions} · ${notes}`;
    }

    get hasSessionLine() {
        return Boolean(this.sessionLine);
    }

    get dataQualityFlags() {
        const rows = [];
        const flags = this.summary ? this.summary.dataQualityFlags || [] : [];
        if (flags.length) {
            const one = flags.length === 1;
            rows.push({
                key: 'EVIDENCE_MISSING',
                message: `${flags.length} High/Critical ${one ? 'defect is' : 'defects are'} missing evidence with no reason given`,
                detail: flags.map((f) => f.findingName).join(', ')
            });
        }
        // "The failed ones need to be fixed" — this is that queue: defects
        // nobody has dispatched to a tracker (or dismissed) yet.
        const untriaged = this.summary ? this.summary.untriagedDefects || 0 : 0;
        if (untriaged > 0) {
            rows.push({
                key: 'UNTRIAGED_DEFECTS',
                message: `${untriaged} defect ${untriaged === 1 ? 'finding is' : 'findings are'} not yet triaged`,
                detail: this.sourceFindings
                    .filter((f) => f.findingType === FINDING_TYPE_DEFECT && statusOf(f) === WORKFLOW_STATUS_NEW)
                    .map((f) => f.name)
                    .join(', ')
            });
        }
        // The step-failure half of the same queue: failed/blocked steps on
        // live runs that nobody has dispatched or dismissed.
        const untriagedSteps = this.summary ? this.summary.untriagedFailedSteps || 0 : 0;
        if (untriagedSteps > 0) {
            rows.push({
                key: 'UNTRIAGED_STEPS',
                message: `${untriagedSteps} failed/blocked ${untriagedSteps === 1 ? 'step is' : 'steps are'} not yet triaged`,
                // Live runs only, matching the counter — a released run's
                // steps are a superseded attempt.
                detail: this.sourceExecutions
                    .filter((run) => !run.released)
                    .flatMap((run) => run.steps || [])
                    .filter(
                        (s) =>
                            (s.result === 'Fail' || s.result === 'Blocked') &&
                            statusOf(s) === WORKFLOW_STATUS_NEW
                    )
                    .map((s) => s.name)
                    .join(', ')
            });
        }
        return rows;
    }

    get hasDataQualityFlags() {
        return this.dataQualityFlags.length > 0;
    }

    get truncationNotes() {
        if (!this.report) {
            return [];
        }
        const notes = [];
        const push = (label, grain, flag, reason) => {
            if (grain && grain[flag]) {
                notes.push({ key: label, label, reason: grain[reason] });
            }
        };
        push('Test cases', this.report.cases, 'truncated', 'truncationReason');
        push('Runs', this.report.executions, 'truncated', 'truncationReason');
        push('Step results', this.report.executions, 'stepsTruncated', 'stepsTruncationReason');
        push('Sessions', this.report.sessions, 'truncated', 'truncationReason');
        push('Log entries', this.report.sessions, 'notesTruncated', 'notesTruncationReason');
        push('Findings', this.report.findings, 'truncated', 'truncationReason');
        push('Assignment log', this.report.events, 'truncated', 'truncationReason');
        return notes;
    }

    get hasTruncation() {
        return this.truncationNotes.length > 0;
    }

    get truncationSentence() {
        return `This report is incomplete: ${this.truncationNotes
            .map((n) => n.label)
            .join(', ')} hit a row limit. Narrow the scope before treating it as a record.`;
    }

    // ---- Source rows -----------------------------------------------------

    get sourceCases() {
        return this.report ? this.report.cases.rows : [];
    }

    get sourceExecutions() {
        return this.report ? this.report.executions.rows : [];
    }

    get sourceFindings() {
        return this.report ? this.report.findings.rows : [];
    }

    get sourceSessions() {
        return this.report ? this.report.sessions.rows : [];
    }

    get sourceEvents() {
        return this.report ? this.report.events.rows : [];
    }

    get execById() {
        const map = {};
        this.sourceExecutions.forEach((row) => {
            map[row.executionId] = row;
        });
        return map;
    }

    // ---- Tabs ------------------------------------------------------------

    get tabs() {
        return GRAINS.map((g) => ({ value: g.key, label: g.label, count: this.countFor(g.key) }));
    }

    countFor(key) {
        if (key === 'testResults') {
            return this.filteredCaseRows.length;
        }
        if (key === 'findings') {
            return this.filteredFindings.length;
        }
        return this.filteredSessions.length;
    }

    get activeGrain() {
        return GRAINS.find((g) => g.key === this.activeTab) || GRAINS[0];
    }

    get isTestResultsTab() {
        return this.activeTab === 'testResults';
    }
    get isFindingsTab() {
        return this.activeTab === 'findings';
    }
    get isSessionsTab() {
        return this.activeTab === 'sessions';
    }

    // ---- Filter option lists ---------------------------------------------

    get caseStepResultOptions() {
        return STEP_RESULT_OPTIONS;
    }
    get findingSeverityOptions() {
        return FINDING_SEVERITY_OPTIONS;
    }
    get findingSourceOptions() {
        return FINDING_SOURCE_OPTIONS;
    }
    get sessionStatusOptions() {
        return SESSION_STATUS_OPTIONS;
    }
    get caseSortOptions() {
        return CASE_SORT_OPTIONS;
    }
    get findingSortOptions() {
        return FINDING_SORT_OPTIONS;
    }
    get sessionSortOptions() {
        return SESSION_SORT_OPTIONS;
    }
    get eventSortOptions() {
        return EVENT_SORT_OPTIONS;
    }

    namesFrom(rows, field) {
        const names = [...new Set(rows.map((r) => r[field]).filter(Boolean))].sort();
        return [{ label: 'All testers', value: '' }].concat(
            names.map((n) => ({ label: n, value: n }))
        );
    }

    get caseTesterOptions() {
        return this.namesFrom(this.sourceExecutions, 'testerName');
    }
    get sessionTesterOptions() {
        return this.namesFrom(this.sourceSessions, 'testerName');
    }
    get eventActionOptions() {
        const actions = [...new Set(this.sourceEvents.map((e) => e.action).filter(Boolean))].sort();
        return [{ label: 'All actions', value: '' }].concat(
            actions.map((a) => ({ label: a, value: a }))
        );
    }

    /** Chip counts describe the scope the chips select within, so they exclude
     *  the chip's own axis. Zero-count chips are omitted. */
    get caseVerdictChips() {
        const rows = this.caseBase.map((m) => m.row);
        const chips = [{ value: 'all', label: 'All', count: rows.length }];
        CASE_VERDICTS.forEach((verdict) => {
            const n = rows.filter((r) => r.verdict === verdict).length;
            if (n > 0) {
                chips.push({ value: verdict, label: verdict, count: n });
            }
        });
        return chips;
    }

    /** Each chip row's counts include the OTHER row's active filter (what a
     *  click would actually show) and exclude its own axis. */
    get findingTypeChips() {
        const rows = this.findingsBase.filter((r) => this.matchesStatusFilter(r));
        const chips = [{ value: 'all', label: 'All', count: rows.length }];
        FINDING_TYPES.forEach((type) => {
            const n = rows.filter((r) => r.findingType === type).length;
            if (n > 0) {
                chips.push({ value: type, label: type, count: n });
            }
        });
        return chips;
    }

    matchesStatusFilter(row) {
        if (this.findingStatus === 'all') {
            return true;
        }
        if (this.findingStatus === STATUS_FILTER_TRACKER) {
            return WORKFLOW_STATUSES_IN_TRACKER.includes(statusOf(row));
        }
        return statusOf(row) === this.findingStatus;
    }

    get findingStatusChips() {
        const rows = this.findingsBase.filter(
            (r) => this.findingType === 'all' || r.findingType === this.findingType
        );
        const chips = [{ value: 'all', label: 'All statuses', count: rows.length }];
        const buckets = [
            { value: WORKFLOW_STATUS_NEW, label: 'New', matches: (s) => s === WORKFLOW_STATUS_NEW },
            {
                value: STATUS_FILTER_TRACKER,
                label: 'In tracker',
                matches: (s) => WORKFLOW_STATUSES_IN_TRACKER.includes(s)
            },
            { value: 'Not verified', label: 'Not verified', matches: (s) => s === 'Not verified' },
            { value: 'Resolved', label: 'Resolved', matches: (s) => s === 'Resolved' }
        ];
        buckets.forEach((bucket) => {
            const n = rows.filter((r) => bucket.matches(statusOf(r))).length;
            if (n > 0) {
                chips.push({ value: bucket.value, label: bucket.label, count: n });
            }
        });
        return chips;
    }

    // ---- Test Results tree -----------------------------------------------

    /**
     * Match the search term at all three depths and remember WHERE it hit.
     *
     * A term that only matches a step's "what happened" text still has to
     * surface its case, and the case has to open far enough to show the row
     * that matched — otherwise the result is a collapsed case that looks
     * irrelevant. So the match is computed once per render and drives both the
     * filter and the auto-expansion.
     */
    get caseBase() {
        const term = this.caseSearch;
        const searching = Boolean(term && term.trim());
        const runsById = this.execById;
        const stepFilter = this.caseStepResult;
        const models = [];

        this.sourceCases.forEach((row) => {
            const runs = (row.executionIds || []).map((id) => runsById[id]).filter(Boolean);
            const caseHit = matchesSearch(term, [
                row.caseCode,
                row.caseTitle,
                row.caseNumber,
                row.modulePath,
                row.verdict,
                (row.testerNames || []).join(' ')
            ]);
            let childHit = false;
            let stepMatchCount = 0;

            const runModels = runs.map((run) => {
                const steps = run.steps || [];
                const stepModels = steps.map((step) => {
                    const hit =
                        searching &&
                        matchesSearch(term, [
                            step.name,
                            step.stepDescription,
                            step.expectedResult,
                            step.actualResult,
                            step.exploreNotes,
                            step.result
                        ]);
                    return { step, hit };
                });
                const runHit =
                    searching &&
                    matchesSearch(term, [
                        run.name,
                        run.testerName,
                        run.testingStatus,
                        run.testingResult,
                        run.uxRecommendation
                    ]);
                const anyStepHit = stepModels.some((s) => s.hit);
                if (runHit || anyStepHit) {
                    childHit = true;
                }
                stepMatchCount += stepModels.filter((s) => s.hit).length;
                return { run, stepModels, runHit, anyStepHit };
            });

            if (searching && !caseHit && !childHit) {
                return;
            }
            if (stepFilter) {
                const keeps = runModels.some((rm) =>
                    rm.stepModels.some((sm) => sm.step.result === stepFilter)
                );
                if (!keeps) {
                    return;
                }
            }
            if (this.caseTester && !(row.testerNames || []).includes(this.caseTester)) {
                return;
            }
            models.push({ row, runModels, childHit, stepMatchCount });
        });
        return models;
    }

    /** The raw CaseRowDTOs behind the visible tree, in display order. The CSV
     *  export walks these, so what downloads is exactly what is on screen. */
    get filteredCaseRows() {
        const rows = this.caseBase
            .filter((m) => this.caseVerdict === 'all' || m.row.verdict === this.caseVerdict)
            .map((m) => m.row);
        if (this.caseSort === 'verdict') {
            return [...rows].sort(byVerdictThenSequence);
        }
        if (this.caseSort === 'tester') {
            return [...rows].sort(byCaseTesterAsc);
        }
        return [...rows].sort(byCaseSequence);
    }

    get caseRows() {
        const searching = Boolean(this.caseSearch && this.caseSearch.trim());
        const byId = {};
        this.caseBase.forEach((m) => {
            byId[m.row.caseId] = m;
        });
        return this.paged(this.filteredCaseRows, this.casePage).map((row) => {
            const model = byId[row.caseId] || { runModels: [], childHit: false };
            // While a search is running, expansion is derived: a case whose
            // match is below the surface opens far enough to show it. Manual
            // expansion resumes the moment the box is cleared.
            const isOpen = searching
                ? model.childHit || this.expandedCaseIds.has(row.caseId)
                : this.expandedCaseIds.has(row.caseId);
            const testers = row.testerNames || [];
            return {
                key: row.caseId,
                caseId: row.caseId,
                caseCode: row.caseCode || DASH,
                caseNumber: row.caseNumber,
                titleDisplay: titleOf(row) || '(untitled case)',
                modulePathDisplay: row.modulePath || DASH,
                verdictDisplay: row.verdict || DASH,
                verdictVariant: CASE_VERDICT_VARIANT[row.verdict] || 'default',
                // "Jane Doe +2" in the cell, everyone in the tooltip — a third
                // tester must never be the thing that overflows the column.
                testerShort:
                    testers.length === 0
                        ? 'Unclaimed'
                        : testers.length === 1
                          ? testers[0]
                          : `${testers[0]} +${testers.length - 1}`,
                testerFull: testers.length ? testers.join(', ') : 'Unclaimed',
                stepsDisplay: this.stepProgress(row),
                untriagedDisplay: row.stepsUntriaged ? `${row.stepsUntriaged} open` : DASH,
                untriagedClass: row.stepsUntriaged ? 'aur__num aur__untriaged-open' : 'aur__num',
                findingCountLabel: String(row.findingCount || 0),
                hasFindings: (row.findingCount || 0) > 0,
                findingsLabel: `Open the ${row.findingCount || 0} ${
                    row.findingCount === 1 ? 'finding' : 'findings'
                } on ${row.caseCode || 'this case'}`,
                evidenceCountLabel: String(row.evidenceCount || 0),
                hasEvidence: (row.evidenceCount || 0) > 0,
                noRunCreated: row.noRunCreated === true,
                outOfScope: row.inScope === false,
                exportLabel: `Export ${row.caseCode || 'case'} as a workbook`,
                isOpen,
                expanded: String(isOpen),
                chevronIcon: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
                hasRuns: model.runModels.length > 0,
                runRows: isOpen ? model.runModels.map((rm) => this.runView(rm, searching)) : []
            };
        });
    }

    /** "3/9 · 3 failed" — the shape a lead scans for. Blocked is called out too;
     *  a blocked case is not a passing one. */
    stepProgress(row) {
        const total = row.stepsTotal || 0;
        if (!total) {
            return row.noRunCreated ? 'No run' : DASH;
        }
        const parts = [`${row.stepsAnswered || 0}/${total}`];
        if (row.stepsFailed) {
            parts.push(`${row.stepsFailed} failed`);
        }
        if (row.stepsBlocked) {
            parts.push(`${row.stepsBlocked} blocked`);
        }
        return parts.join(' · ');
    }

    runView(model, searching) {
        const run = model.run;
        const isOpen = searching
            ? model.anyStepHit || this.expandedExecIds.has(run.executionId)
            : this.expandedExecIds.has(run.executionId);
        const meta = [run.testingStatus || 'Not Started'];
        if (run.testingResult) {
            meta.push(run.testingResult);
        }
        meta.push(run.testerName || 'Unclaimed');
        if (run.uxRating) {
            meta.push(`UX ${run.uxRating}/5`);
        }
        if (run.lastTestedDate) {
            meta.push(`tested ${formatDateLong(run.lastTestedDate)}`);
        }
        return {
            key: run.executionId,
            executionId: run.executionId,
            name: run.name,
            metaDisplay: meta.join(' · '),
            resultDisplay: run.testingResult || DASH,
            resultVariant: RESULT_VARIANT[run.testingResult] || 'default',
            hasResult: Boolean(run.testingResult),
            released: run.released === true,
            hasRecommendation: Boolean(run.uxRecommendation),
            recommendationDisplay: run.uxRecommendation,
            isOpen,
            expanded: String(isOpen),
            chevronIcon: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
            hasSteps: (run.steps || []).length > 0,
            stepRows: isOpen ? model.stepModels.map((sm) => this.stepView(sm.step)) : [],
            ...this.evidenceView(run, run.executionId)
        };
    }

    /**
     * A step renders as stacked blocks, never as cells: a head line ("3." +
     * verdict badge + clip) with nothing elastic on it, then the authored
     * description as its own full-width paragraph, then the tester's
     * narrative. The old Step Results table put the badge and free text in
     * adjacent cells of an auto-layout table — max-width on a <td> is advisory
     * there, the text column inflated, and the unshrinkable inline-flex badge
     * overflowed into it. Authored cases that pack all ten steps into one
     * description now read as a paragraph instead of filler beside a badge.
     */
    stepView(step) {
        const narrative = step.actualResult || step.exploreNotes || '';
        const status = statusOf(step);
        return {
            key: step.resultId,
            resultId: step.resultId,
            name: step.name,
            stepLabel: step.stepDeleted
                ? '(step deleted)'
                : `${step.stepNumber === null || step.stepNumber === undefined ? '?' : step.stepNumber}.`,
            stepDeleted: step.stepDeleted === true,
            descriptionDisplay: step.stepDeleted ? '' : step.stepDescription || '',
            hasDescription: !step.stepDeleted && Boolean(step.stepDescription),
            resultDisplay: step.result || 'Unanswered',
            resultVariant: STEP_RESULT_VARIANT[step.result] || 'default',
            // Only a failure can need triage; passing/unanswered steps carry
            // the field but no chip — display noise, not data.
            showStatusChip:
                !step.stepDeleted && (step.result === 'Fail' || step.result === 'Blocked'),
            statusDisplay: status,
            statusVariant: WORKFLOW_STATUS_VARIANT[status] || 'default',
            statusTitle: [
                `Workflow status: ${status}`,
                step.externalRef ? `Ref: ${step.externalRef}` : null,
                'Click to change'
            ]
                .filter(Boolean)
                .join(' · '),
            hasNarrative: Boolean(narrative),
            narrativeDisplay: narrative,
            ...this.evidenceView(step, step.resultId)
        };
    }

    // ---- Findings / sessions / events -------------------------------------

    get findingsBase() {
        return this.sourceFindings.filter((r) => {
            if (this.findingSeverity && r.severity !== this.findingSeverity) {
                return false;
            }
            if (this.findingSource && r.source !== this.findingSource) {
                return false;
            }
            return matchesSearch(this.findingSearch, [
                r.name,
                r.title,
                r.whatHappened,
                r.whatTesting,
                r.testerName,
                r.caseCode
            ]);
        });
    }

    get filteredFindings() {
        const rows = this.findingsBase.filter(
            (r) =>
                (this.findingType === 'all' || r.findingType === this.findingType) &&
                this.matchesStatusFilter(r)
        );
        const sorted =
            this.findingSort === 'reported'
                ? [...rows].sort(byReportedDesc)
                : this.findingSort === 'type'
                  ? [...rows].sort(byFindingType)
                  : [...rows].sort(bySeverityThenDateDesc);
        return sorted.map((r) => {
            const status = statusOf(r);
            return {
                ...r,
                key: r.findingId,
                titleDisplay: r.title || '(untitled)',
                typeVariant: FINDING_TYPE_VARIANT[r.findingType] || 'default',
                severityDisplay: r.severity || DASH,
                severityVariant: SEVERITY_VARIANT[r.severity] || 'default',
                hasSeverity: Boolean(r.severity),
                sourceVariant: FINDING_SOURCE_VARIANT[r.source] || 'default',
                statusDisplay: status,
                statusVariant: WORKFLOW_STATUS_VARIANT[status] || 'default',
                statusTitle: [
                    `Workflow status: ${status}`,
                    r.externalRef ? `Ref: ${r.externalRef}` : null,
                    'Click to change'
                ]
                    .filter(Boolean)
                    .join(' · '),
                reportedDisplay: r.dateLogged ? formatDateLong(r.dateLogged) : DASH,
                testerDisplay: r.testerName || DASH,
                // A case-anchored finding links back into the tree; a session
                // one names its session. Both land in the merged Source cell:
                // the badge says which trail, the ref names the stop on it.
                hasCaseLink: Boolean(r.caseId && r.caseCode),
                sourceRef:
                    r.source === 'Test case'
                        ? shortCaseRef(r.caseCode) || DASH
                        : r.sessionTitle || r.sessionName || DASH,
                sourceRefFull:
                    r.source === 'Test case'
                        ? [r.caseCode, r.caseTitle].filter(Boolean).join(' · ')
                        : [r.sessionName, r.sessionTitle].filter(Boolean).join(' · ')
            };
        });
    }

    get filteredSessions() {
        const rows = this.sourceSessions.filter((r) => {
            if (this.sessionStatus && r.status !== this.sessionStatus) {
                return false;
            }
            if (this.sessionTester && r.testerName !== this.sessionTester) {
                return false;
            }
            const noteText = (r.notes || []).map((n) => n.text).join(' ');
            return matchesSearch(this.sessionSearch, [
                r.name,
                r.title,
                r.areaText,
                r.testerName,
                noteText
            ]);
        });
        const sorted =
            this.sessionSort === 'tester'
                ? [...rows].sort(byNameAsc)
                : this.sessionSort === 'notes'
                  ? [...rows].sort(byNoteCountDesc)
                  : [...rows].sort(bySessionStartedDesc);
        return sorted.map((r) => {
            const isOpen = r.sessionId === this.expandedSessionId;
            return {
                ...r,
                key: r.sessionId,
                titleDisplay: r.title || '(untitled session)',
                statusDisplay: r.status || DASH,
                statusVariant: SESSION_STATUS_VARIANT[r.status] || 'default',
                testerDisplay: r.testerName || DASH,
                // startedAt is a Datetime — parseLocalDate handles both shapes
                // now, but the cell stays date-only; the tooltip carries time.
                startedDisplay: (r.startedAt && formatDateLong(r.startedAt)) || DASH,
                startedTitle: (r.startedAt && formatDateTimeLong(r.startedAt)) || null,
                durationDisplay: formatDurationMinutes(r.durationMinutes) || DASH,
                durationClass:
                    (r.durationMinutes || 0) > LONG_SESSION_MINUTES ? 'aur__duration-long' : null,
                durationTitle:
                    (r.durationMinutes || 0) > LONG_SESSION_MINUTES ? LONG_SESSION_TITLE : null,
                noteCountLabel: `${r.noteCount || 0}`,
                isOpen,
                expanded: String(isOpen),
                chevronIcon: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
                hasNotes: (r.notes || []).length > 0,
                noteRows: (r.notes || []).map((n) => ({
                    ...n,
                    key: n.noteId,
                    // A timeline needs times: entries in one session share a date.
                    loggedDisplay: (n.loggedAt && formatDateTimeLong(n.loggedAt)) || DASH,
                    authorDisplay: n.authorName || DASH,
                    hasTag: Boolean(n.tag),
                    hasPromotedFinding: Boolean(n.promotedFindingId),
                    hasRunLink: Boolean(n.executionId),
                    ...this.evidenceView(n, n.noteId)
                }))
            };
        });
    }

    get filteredEvents() {
        const rows = this.sourceEvents.filter((r) => {
            if (this.eventAction && r.action !== this.eventAction) {
                return false;
            }
            return matchesSearch(this.eventSearch, [
                r.name,
                r.action,
                r.testerName,
                r.actorName,
                r.caseCode,
                r.reason
            ]);
        });
        const sorted =
            this.eventSort === 'oldest' ? [...rows].sort(byOccurredAsc) : [...rows].sort(byOccurredDesc);
        return sorted.map((r) => ({
            ...r,
            key: r.eventId,
            occurredDisplay: (r.occurredAt && formatDateLong(r.occurredAt)) || DASH,
            occurredTitle: (r.occurredAt && formatDateTimeLong(r.occurredAt)) || null,
            testerDisplay: r.testerName || DASH,
            actorDisplay: r.actorName && r.actorName !== r.testerName ? r.actorName : DASH,
            caseDisplay: r.caseCode || DASH,
            reasonDisplay: r.reason || DASH
        }));
    }

    evidenceView(row, key) {
        const files = row.files || [];
        const open = key === this.expandedEvidenceKey;
        return {
            hasEvidence: (row.evidenceCount || 0) > 0,
            evidenceLabel: String(row.evidenceCount || 0),
            evidenceAria: `${row.evidenceCount || 0} evidence file(s) for ${row.name}`,
            evidenceExpanded: String(open),
            isEvidenceOpen: open,
            evidenceFilesView: files.map((f) => ({ ...f, key: f.contentDocumentId }))
        };
    }

    // ---- Assignment history (collapsed section) ---------------------------

    get assignmentLabel() {
        return `Assignment history (${this.sourceEvents.length})`;
    }

    get hasAssignmentHistory() {
        return this.sourceEvents.length > 0;
    }

    get assignmentExpanded() {
        return String(this.assignmentOpen);
    }

    get assignmentChevron() {
        return this.assignmentOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get assignmentExportNote() {
        const n = this.filteredEvents.length;
        return `Exports the ${n} assignment ${n === 1 ? 'row' : 'rows'} currently shown.`;
    }

    // ---- Paging ----------------------------------------------------------

    get pageSize() {
        return PAGE_SIZE;
    }

    paged(rows, page) {
        const clamped = this.clamp(rows, page);
        const start = (clamped - 1) * PAGE_SIZE;
        return rows.slice(start, start + PAGE_SIZE);
    }

    clamp(rows, page) {
        return Math.min(Math.max(1, page), Math.max(1, Math.ceil(rows.length / PAGE_SIZE)));
    }

    get clampedCasePage() {
        return this.clamp(this.filteredCaseRows, this.casePage);
    }
    get totalCases() {
        return this.filteredCaseRows.length;
    }
    get caseHasRows() {
        return this.totalCases > 0;
    }

    get pagedFindings() {
        return this.paged(this.filteredFindings, this.findingPage);
    }
    get clampedFindingPage() {
        return this.clamp(this.filteredFindings, this.findingPage);
    }
    get totalFindings() {
        return this.filteredFindings.length;
    }
    get findingHasRows() {
        return this.totalFindings > 0;
    }

    get pagedSessions() {
        return this.paged(this.filteredSessions, this.sessionPage);
    }
    get clampedSessionPage() {
        return this.clamp(this.filteredSessions, this.sessionPage);
    }
    get totalSessions() {
        return this.filteredSessions.length;
    }
    get sessionHasRows() {
        return this.totalSessions > 0;
    }

    get pagedEvents() {
        return this.paged(this.filteredEvents, this.eventPage);
    }
    get clampedEventPage() {
        return this.clamp(this.filteredEvents, this.eventPage);
    }
    get totalEvents() {
        return this.filteredEvents.length;
    }
    get eventHasRows() {
        return this.totalEvents > 0;
    }

    // ---- Handlers --------------------------------------------------------

    handleScopeChange(event) {
        this.scope = event.detail.value;
        this.reloadReport();
    }
    handleTabChange(event) {
        this.activeTab = event.detail.value;
    }

    handleCaseSearch(event) {
        this.caseSearch = event.target.value;
        this.casePage = 1;
    }
    handleCaseVerdictChip(event) {
        this.caseVerdict = event.detail.value;
        this.casePage = 1;
    }
    handleCaseTester(event) {
        this.caseTester = event.detail.value;
        this.casePage = 1;
    }
    handleCaseStepResult(event) {
        this.caseStepResult = event.detail.value;
        this.casePage = 1;
    }
    handleCaseSort(event) {
        this.caseSort = event.detail.value;
    }
    handleCasePage(event) {
        this.casePage = event.detail.page;
    }

    handleFindingSearch(event) {
        this.findingSearch = event.target.value;
        this.findingPage = 1;
    }
    handleFindingTypeChip(event) {
        this.findingType = event.detail.value;
        this.findingPage = 1;
    }
    handleFindingStatusChip(event) {
        this.findingStatus = event.detail.value;
        this.findingPage = 1;
    }
    handleFindingSeverity(event) {
        this.findingSeverity = event.detail.value;
        this.findingPage = 1;
    }
    handleFindingSource(event) {
        this.findingSource = event.detail.value;
        this.findingPage = 1;
    }
    handleFindingSort(event) {
        this.findingSort = event.detail.value;
    }
    handleFindingPage(event) {
        this.findingPage = event.detail.page;
    }

    handleSessionSearch(event) {
        this.sessionSearch = event.target.value;
        this.sessionPage = 1;
    }
    handleSessionStatus(event) {
        this.sessionStatus = event.detail.value;
        this.sessionPage = 1;
    }
    handleSessionTester(event) {
        this.sessionTester = event.detail.value;
        this.sessionPage = 1;
    }
    handleSessionSort(event) {
        this.sessionSort = event.detail.value;
    }
    handleSessionPage(event) {
        this.sessionPage = event.detail.page;
    }

    handleEventSearch(event) {
        this.eventSearch = event.target.value;
        this.eventPage = 1;
    }
    handleEventAction(event) {
        this.eventAction = event.detail.value;
        this.eventPage = 1;
    }
    handleEventSort(event) {
        this.eventSort = event.detail.value;
    }
    handleEventPage(event) {
        this.eventPage = event.detail.page;
    }

    /** Sets are replaced, not mutated: LWC's reactivity does not see Set.add. */
    toggleIn(set, id) {
        const next = new Set(set);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        return next;
    }

    handleCaseToggle(event) {
        this.expandedCaseIds = this.toggleIn(this.expandedCaseIds, event.currentTarget.dataset.id);
    }

    handleRunToggle(event) {
        this.expandedExecIds = this.toggleIn(this.expandedExecIds, event.currentTarget.dataset.id);
    }

    handleEvidenceToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.expandedEvidenceKey = this.expandedEvidenceKey === key ? null : key;
    }

    handleSessionToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedSessionId = this.expandedSessionId === id ? null : id;
    }

    handleAssignmentToggle() {
        this.assignmentOpen = !this.assignmentOpen;
    }

    /**
     * Narrow the Findings tab to one finding by its number.
     *
     * This was the promoted-finding badge's whole behaviour until the badge
     * started opening the finding itself (2026-08-12). It stays as the fallback
     * for when the findings grain truncated and the badge's row is not in the
     * payload — a filtered tab that shows nothing is at least an honest answer.
     */
    filterToFinding(number) {
        this.activeTab = 'findings';
        this.findingType = 'all';
        this.findingSeverity = '';
        this.findingSource = '';
        this.findingSort = 'default';
        this.findingSearch = number || '';
        this.findingPage = 1;
    }

    /** A finding's case, back in the tree, opened. */
    jumpToCase(caseId, caseCode) {
        this.activeTab = 'testResults';
        this.caseVerdict = 'all';
        this.caseTester = '';
        this.caseStepResult = '';
        this.caseSort = 'default';
        this.caseSearch = caseCode || '';
        this.casePage = 1;
        this.expandedCaseIds = new Set([caseId]);
    }

    handleJumpToCase(event) {
        const ds = event.currentTarget.dataset;
        this.jumpToCase(ds.id, ds.code);
    }

    handleOpenCycle() {
        if (!this.report || !this.report.cycle) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('uatnavigate', {
                bubbles: true,
                composed: true,
                detail: { section: 'uatCycles', recordId: this.report.cycle.cycleId }
            })
        );
    }

    handleOpenCase(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(
            new CustomEvent('uatnavigate', {
                bubbles: true,
                composed: true,
                detail: {
                    section: 'uatCases',
                    recordId: ds.id,
                    context: {
                        executionId: ds.execution,
                        cycleId: this.isStandalone ? null : this.scope,
                        cycleName: this.selectedCycleName
                    }
                }
            })
        );
    }

    // ---- Finding viewer --------------------------------------------------

    /**
     * Everything below reads the report payload already on the client:
     * FindingRowDTO carries the narratives, the evidence and the full session /
     * note / run / case / step context, so opening a finding costs no round
     * trip. The two write actions are the only server calls, and both are
     * endpoints the tester surface already uses.
     */

    get viewerOpen() {
        return this.viewer !== null;
    }

    get findingById() {
        const map = {};
        this.sourceFindings.forEach((row) => {
            map[row.findingId] = row;
        });
        return map;
    }

    /** Flat index over the nested step results — the step-status picker's
     *  lookup, mirroring findingById. */
    get stepById() {
        const map = {};
        this.sourceExecutions.forEach((run) => {
            (run.steps || []).forEach((step) => {
                map[step.resultId] = step;
            });
        });
        return map;
    }

    /** Detail mode when a finding is selected; list mode otherwise. */
    get viewerListMode() {
        return this.viewerOpen && !this.viewer.findingId;
    }

    get viewerFinding() {
        const row = this.viewerOpen ? this.findingById[this.viewer.findingId] : null;
        return row ? findingViewModel(row) : null;
    }

    get viewerHasFinding() {
        return this.viewerFinding !== null;
    }

    /** Back to the list only when there is a list to go back to. */
    get viewerCanGoBack() {
        return Boolean(this.viewerOpen && this.viewer.findingId && this.viewer.findingIds.length > 1);
    }

    get viewerRows() {
        if (!this.viewerOpen) {
            return [];
        }
        const map = this.findingById;
        return this.viewer.findingIds
            .map((id) => map[id])
            .filter(Boolean)
            .map((r) => ({
                key: r.findingId,
                findingId: r.findingId,
                name: r.name,
                titleDisplay: r.title || '(untitled)',
                type: r.findingType,
                typeVariant: FINDING_TYPE_VARIANT[r.findingType] || 'default',
                hasSeverity: Boolean(r.severity),
                severity: r.severity,
                severityVariant: SEVERITY_VARIANT[r.severity] || 'default',
                metaDisplay: [r.testerName, r.dateLogged ? formatDateLong(r.dateLogged) : null]
                    .filter(Boolean)
                    .join(' · ')
            }));
    }

    get viewerTitle() {
        if (!this.viewerOpen) {
            return '';
        }
        if (this.viewerListMode) {
            const n = this.viewerRows.length;
            return `${n} ${n === 1 ? 'finding' : 'findings'} on ${this.viewer.caseCode || 'this case'}`;
        }
        const f = this.viewerFinding;
        return f ? f.name : 'Finding';
    }

    /** The trail behind a finding, in the order an admin asks for it. Only rows
     *  that exist are rendered — a Session finding has no run, and a Test case
     *  one has no session. */
    get viewerContextRows() {
        const f = this.viewerFinding;
        if (!f) {
            return [];
        }
        const rows = [];
        const add = (label, value) => {
            if (value) {
                rows.push({ key: label, label, value });
            }
        };
        const pair = (a, b) => [a, b].filter(Boolean).join(' · ');
        add('Source', f.source);
        add('Cycle', f.cycleName);
        add('Session', pair(f.sessionName, f.sessionTitle));
        // The note's own number, and the time it was logged if the origin line
        // carried one. Never the bare time — "Promoted from 14:32" says nothing.
        add('Promoted from', f.sourceNoteName
            ? pair(f.sourceNoteName, f.originLine ? f.originLine.split('· ')[1] : null)
            : null);
        add('Test case', pair(f.caseCode, f.caseTitle));
        add('Run', f.executionName);
        add('Step result', f.stepResultName);
        return rows;
    }

    /** Both case navigations need a case; a Session finding has none. */
    get viewerHasCase() {
        const f = this.viewerFinding;
        return Boolean(f && f.caseId);
    }

    get viewerIsEditing() {
        return this.viewerForm !== null;
    }

    get viewerFormIsDefect() {
        return this.viewerForm && this.viewerForm.type === FINDING_TYPE_DEFECT;
    }

    get viewerFormNeedsEvidence() {
        return (
            this.viewerFormIsDefect &&
            EVIDENCE_REQUIRED_SEVERITIES.includes(this.viewerForm.severity)
        );
    }

    get viewerTypeOptions() {
        return FORM_TYPE_OPTIONS;
    }

    get viewerSeverityOptions() {
        return FORM_SEVERITY_OPTIONS;
    }

    get viewerDeleteWarning() {
        return DELETE_WARNING;
    }

    /** Opens `id` when the payload actually contains it. Returns false when it
     *  does not, so a caller can fall back — a truncated findings grain is a
     *  real state, and the badge in Sessions & Notes can outlive its row. */
    openFinding(id, scope) {
        if (!id || !this.findingById[id]) {
            return false;
        }
        this.viewer = {
            findingIds: (scope && scope.findingIds) || [id],
            findingId: id,
            caseCode: (scope && scope.caseCode) || null
        };
        this.viewerForm = null;
        this.viewerConfirm = false;
        return true;
    }

    handleOpenFinding(event) {
        this.openFinding(event.currentTarget.dataset.id);
    }

    /** Whole-row convenience click. One closest() guard instead of
     *  stopPropagation on every inner control: shadow retargeting makes
     *  event.target the inner button/link host for clicks anywhere inside it,
     *  so anything interactive falls through to its own handler. The <tr>
     *  carries no tabindex — the Title button stays the keyboard path. */
    handleFindingRowClick(event) {
        if (event.target.closest('button, a')) {
            return;
        }
        this.openFinding(event.currentTarget.dataset.id);
    }

    /** The case tree's findings count. One finding opens straight to it; several
     *  open the list, because picking from a list beats guessing. */
    handleOpenCaseFindings(event) {
        const ds = event.currentTarget.dataset;
        const row = this.sourceCases.find((c) => c.caseId === ds.id);
        const ids = ((row && row.findingIds) || []).filter((id) => this.findingById[id]);
        if (!ids.length) {
            return;
        }
        this.viewer = {
            findingIds: ids,
            findingId: ids.length === 1 ? ids[0] : null,
            caseCode: (row && row.caseCode) || null
        };
        this.viewerForm = null;
        this.viewerConfirm = false;
    }

    /** The promoted-finding badge in Sessions & Notes. Opens the finding rather
     *  than filtering the tab to it; falls back to the old filter jump when the
     *  findings grain was truncated out from under the badge. */
    handleOpenPromotedFinding(event) {
        const ds = event.currentTarget.dataset;
        if (!this.openFinding(ds.id)) {
            this.filterToFinding(ds.finding);
        }
    }

    handleViewerSelect(event) {
        this.viewer = { ...this.viewer, findingId: event.currentTarget.dataset.id };
        this.viewerForm = null;
        this.viewerConfirm = false;
    }

    handleViewerBack() {
        this.viewer = { ...this.viewer, findingId: null };
        this.viewerForm = null;
        this.viewerConfirm = false;
    }

    handleViewerClose() {
        this.viewer = null;
        this.viewerForm = null;
        this.viewerConfirm = false;
    }

    /** In-report navigation: the case's row in the Test Results tree, opened. */
    handleViewerShowInReport() {
        const f = this.viewerFinding;
        if (!f) {
            return;
        }
        this.jumpToCase(f.caseId, f.caseCode);
        this.handleViewerClose();
    }

    /** Out-of-report navigation: the case's own admin page. */
    handleViewerOpenCase() {
        const f = this.viewerFinding;
        if (!f) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('uatnavigate', {
                bubbles: true,
                composed: true,
                detail: {
                    section: 'uatCases',
                    recordId: f.caseId,
                    context: {
                        executionId: f.executionId,
                        cycleId: this.isStandalone ? null : this.scope,
                        cycleName: this.selectedCycleName
                    }
                }
            })
        );
        this.handleViewerClose();
    }

    // ---- Viewer moderation (existing endpoints only) ----------------------

    handleViewerEdit() {
        const f = this.viewerFinding;
        if (!f) {
            return;
        }
        this.viewerForm = {
            id: f.id,
            title: f.title || '',
            type: f.type || FINDING_TYPE_DEFECT,
            whatTesting: f.whatTesting || '',
            whatExpected: f.whatExpected || '',
            whatHappened: f.whatHappened || '',
            severity: f.severity || '',
            noEvidenceReason: f.noEvidenceReason || ''
        };
        this.viewerConfirm = false;
    }

    handleViewerFormField(event) {
        this.viewerForm = {
            ...this.viewerForm,
            [event.currentTarget.dataset.field]: event.target.value
        };
    }

    handleViewerFormType(event) {
        this.viewerForm = { ...this.viewerForm, type: event.detail.value };
    }

    handleViewerFormSeverity(event) {
        this.viewerForm = { ...this.viewerForm, severity: event.detail.value };
    }

    handleViewerFormCancel() {
        this.viewerForm = null;
    }

    async handleViewerFormSave() {
        const form = this.viewerForm;
        if (!form.title || form.title.trim().length < TITLE_MIN) {
            toast(this, 'error', `Give the finding a title of at least ${TITLE_MIN} characters `
                + '— it is what someone triaging sees first.');
            return;
        }
        if (!form.whatHappened || !form.whatHappened.trim()) {
            toast(this, 'error', 'Describe what happened — that field is required.');
            return;
        }
        if (form.type === FINDING_TYPE_DEFECT && !form.severity) {
            toast(this, 'error', 'A defect needs a severity.');
            return;
        }
        this.viewerBusy = true;
        try {
            // JSON string: custom-Apex-type @AuraEnabled params arrive null from
            // LWC in this org. No cycleId or sessionId — on update the server
            // ignores both and the session link is immutable.
            await saveFinding({
                inputJson: JSON.stringify({
                    id: form.id,
                    title: form.title,
                    type: form.type,
                    whatTesting: form.whatTesting,
                    whatExpected: form.whatExpected,
                    whatHappened: form.whatHappened,
                    severity: form.severity,
                    noEvidenceReason: form.noEvidenceReason
                })
            });
            this.viewerForm = null;
            toast(this, 'success', 'Finding updated.');
            await this.refreshReport();
        } catch (e) {
            reportError(this, BUNDLE, 'Save finding', e);
        } finally {
            this.viewerBusy = false;
        }
    }

    /** Inline rather than c-admin-confirm-modal: that component sits at
     *  z-index 110 and c-ds-modal-v2 at 9000, so a stacked confirm would render
     *  BEHIND this dialog with no way out of it. */
    handleViewerDeleteClick() {
        this.viewerConfirm = true;
    }

    handleViewerDeleteCancel() {
        this.viewerConfirm = false;
    }

    async handleViewerDeleteConfirm() {
        const f = this.viewerFinding;
        if (!f) {
            return;
        }
        this.viewerBusy = true;
        try {
            await deleteFinding({ findingId: f.id });
            this.handleViewerClose();
            toast(this, 'success', 'Finding deleted.');
            await this.refreshReport();
        } catch (e) {
            reportError(this, BUNDLE, 'Delete finding', e);
        } finally {
            this.viewerBusy = false;
        }
    }

    // ---- Workflow status (the report's own write) --------------------------

    get statusPromptOpen() {
        return this.statusPrompt !== null;
    }

    get statusPromptTitle() {
        return this.statusPrompt ? `Workflow status · ${this.statusPrompt.name}` : '';
    }

    get statusPromptOptions() {
        const p = this.statusPrompt;
        if (!p) {
            return [];
        }
        const selected = p.picked || p.current;
        return WORKFLOW_STATUSES.map((s) => ({
            value: s,
            label: s,
            variant: WORKFLOW_STATUS_VARIANT[s] || 'default',
            isCurrent: s === p.current,
            pressed: String(s === selected)
        }));
    }

    /** Only an Added-to-* choice asks for the ticket ref; the other statuses
     *  save on click, menu-style. */
    get statusPromptNeedsRef() {
        return Boolean(this.statusPrompt && this.statusPrompt.picked);
    }

    get statusPromptRef() {
        return this.statusPrompt ? this.statusPrompt.ref : '';
    }

    openStatusPrompt(kind, recordId) {
        const row = kind === 'step' ? this.stepById[recordId] : this.findingById[recordId];
        if (!row) {
            return;
        }
        this.statusPrompt = {
            kind,
            recordId,
            name: row.name,
            current: statusOf(row),
            ref: row.externalRef || '',
            picked: null
        };
    }

    handleStatusChipClick(event) {
        this.openStatusPrompt('finding', event.currentTarget.dataset.id);
    }

    handleStepStatusChipClick(event) {
        this.openStatusPrompt('step', event.currentTarget.dataset.id);
    }

    /** The shared viewer's admin control — same dialog, same save path. */
    handleViewerStatusEdit(event) {
        this.openStatusPrompt('finding', event.detail.findingId);
    }

    handleStatusPromptPick(event) {
        const status = event.currentTarget.dataset.status;
        if (WORKFLOW_STATUSES_IN_TRACKER.includes(status)) {
            this.statusPrompt = { ...this.statusPrompt, picked: status };
            return;
        }
        this.saveWorkflowStatus(status, undefined);
    }

    handleStatusPromptRef(event) {
        this.statusPrompt = { ...this.statusPrompt, ref: event.target.value };
    }

    handleStatusPromptSave() {
        // '' deliberately clears a stored ref; the server treats absent as
        // "leave it alone" and empty as "clear it".
        this.saveWorkflowStatus(this.statusPrompt.picked, this.statusPrompt.ref || '');
    }

    handleStatusPromptSkip() {
        this.saveWorkflowStatus(this.statusPrompt.picked, undefined);
    }

    handleStatusPromptCancel() {
        if (!this.statusBusy) {
            this.statusPrompt = null;
        }
    }

    async saveWorkflowStatus(status, externalRef) {
        const p = this.statusPrompt;
        this.statusBusy = true;
        try {
            // JSON string transport; JSON.stringify drops an undefined
            // externalRef, which is exactly the server's "leave it" case.
            if (p.kind === 'step') {
                await setStepWorkflowStatus({
                    inputJson: JSON.stringify({ resultId: p.recordId, status, externalRef })
                });
            } else {
                await setFindingWorkflowStatus({
                    inputJson: JSON.stringify({ findingId: p.recordId, status, externalRef })
                });
            }
            this.statusPrompt = null;
            toast(this, 'success', `Marked ${status}.`);
            await this.refreshReport();
        } catch (e) {
            reportError(this, BUNDLE, 'Set workflow status', e);
        } finally {
            this.statusBusy = false;
        }
    }

    /**
     * Re-fetch without resetFilters().
     *
     * reloadReport() is for a SCOPE change, where resetting the tab, chips and
     * page is right. After moderating one finding it would throw the admin back
     * to page 1 of Test Results, which reads as the app losing their place.
     */
    async refreshReport() {
        this.reportLoading = true;
        try {
            this.report = await this.fetchReport(this.scope);
        } catch (e) {
            reportError(this, BUNDLE, 'Report refresh', e);
        } finally {
            this.reportLoading = false;
        }
    }

    // ---- Export ----------------------------------------------------------

    get exportTabLabel() {
        return `Export ${this.activeGrain.label}`;
    }

    get exportTabNote() {
        const count = this.countFor(this.activeTab);
        if (this.isTestResultsTab) {
            return `Exports the ${count} ${
                count === 1 ? 'test case' : 'test cases'
            } currently shown, one row per step result — filters and search applied.`;
        }
        return `Exports the ${count} ${this.activeGrain.itemLabel} currently shown — filters and search applied.`;
    }

    get workbookLabel() {
        return this.isStandalone ? 'Export standalone work (Excel)' : 'Export full cycle (Excel)';
    }

    todayIso() {
        return isoDate(new Date());
    }

    /** The visible rows of a tab, at the grain its CSV is written in. */
    filteredRowsFor(key) {
        if (key === 'testResults') {
            // Step-result grain, walked case -> run -> step so the file reads in
            // the same order the tree does.
            return buildTestResultRows({ ...this.report, cases: { rows: this.filteredCaseRows } }, null);
        }
        if (key === 'findings') {
            return this.filteredFindings;
        }
        // The sessions tab exports entries, not session headers.
        const visible = new Set(this.filteredSessions.map((s) => s.sessionId));
        return buildNoteRows(this.report).filter((n) => visible.has(n.sessionId));
    }

    exportCsv(grain, rows) {
        try {
            downloadCsv(
                csvFilename(this.cycleSlug, grain.file, this.todayIso()),
                buildCsvContent(rows, COLUMNS[grain.columns])
            );
        } catch (e) {
            reportError(this, BUNDLE, 'Export', e);
        }
    }

    handleExportTab() {
        this.exportCsv(this.activeGrain, this.filteredRowsFor(this.activeTab));
    }

    handleExportEvents() {
        this.exportCsv(EVENT_GRAIN, this.filteredEvents);
    }

    /**
     * One click, one file. The six staggered CSV downloads this replaces relied
     * on the browser not silently dropping any of them, which is undetectable
     * when it happens — a workbook either arrives or it does not.
     */
    async buildWorkbook(scope, filename) {
        this.exporting = true;
        try {
            await loadXlsx(this);
            downloadBlob(filename, sheetsToXlsxBlob(buildWorkbookSheets(this.report, scope)));
        } catch (e) {
            reportError(this, BUNDLE, 'Export', e);
        } finally {
            this.exporting = false;
        }
    }

    handleExportWorkbook() {
        return this.buildWorkbook(
            null,
            xlsxFilename(this.cycleSlug, 'uat_report', this.todayIso())
        );
    }

    handleExportCase(event) {
        const ds = event.currentTarget.dataset;
        return this.buildWorkbook(
            { caseId: ds.id },
            xlsxFilename(this.cycleSlug, slugify(ds.code || 'case'), this.todayIso())
        );
    }
}