import { LightningElement, api } from 'lwc';
import getQueue from '@salesforce/apex/UatRunController.getQueue';
import getExploratorySessions from '@salesforce/apex/UatSessionController.getExploratorySessions';
import getCasePreview from '@salesforce/apex/UatRunController.getCasePreview';
import releaseClaim from '@salesforce/apex/UatRunController.releaseClaim';
import { humanizeCaseCode } from 'c/uatTitleUtil';
import { messageFrom, toast } from 'c/messageUtil';
import { BUCKET_BADGE, BUCKET_ORDER, bucketOf } from 'c/uatConstants';
import {
    relativeDays,
    relativeTime,
    formatDateLong,
    joinMeta,
    areaOf,
    areaOptionsFrom,
    matchesSearch
} from 'c/uatCardUtil';

/* Client-side paging over the full getQueue payload. The endpoint caps at
 * 1000 rows (no server paging) — fine at this org's scale; the pager caption
 * counts loaded rows only. */
const PAGE_SIZE = 8;

const TABS = [
    { value: 'assigned', label: 'Assigned Test Cases' },
    { value: 'exploratory', label: 'Ad-hoc Sessions' }
];

const SORT_OPTIONS = [
    { label: 'Cycle order', value: 'default' },
    { label: 'Recently updated', value: 'updated' },
    { label: 'Target date', value: 'target' }
];

/**
 * uatQueue — "My Queue": the tester's OWN claimed work, split into two
 * workflows by a level-1 tab strip (c-ds-tabs). Assigned Test Cases is a
 * featured Continue-Testing card over a dense column-header list, grouped by
 * lifecycle under the default sort (In Progress → Blocked → Not Started →
 * Completed, section headers only when more than one bucket shows);
 * Ad-hoc Sessions holds the off-script session workflow
 * (c-uat-session-list; its `sessionschange` triggers a full reload so the
 * tab counts move with the list).
 *
 * Counting rule: the tab counts, status chips, and area options all derive
 * from scopedRows — the rows inside the header cycle switcher's selection —
 * so every number on the page moves together with the pager caption (the
 * dashboard's scoped summary follows the same rule server-side). The pill on
 * a row is its LIFECYCLE bucket (shared bucketOf); verdicts surface as
 * secondary indicators ("1 failed step"), never as the pill.
 *
 * Server actionLabel drives the row button; Release lives in the kebab
 * (reason required, Complete runs excluded); open/exploratory/navigate event
 * contracts are unchanged. Embedded by uatTesterApp only.
 *
 * View Details (2026-08-14) opens the same read-only c-uat-case-preview the
 * pool uses — description, pre-conditions, grouped steps — instead of jumping
 * into the runner: once a case left the pool this view was unreachable, so a
 * claimed tester had no way to re-read the briefing without burning a run
 * load. getCasePreview skips ensureStepResults, so looking never writes.
 */
export default class UatQueue extends LightningElement {
    queue;
    sessions = [];
    loading = true;
    errorMessage;

    activeTab = 'assigned';

    releaseTarget = null; // { executionId, caseCode }
    releaseBusy = false;

    previewOpen = false;
    previewLoading = false;
    previewError;
    previewData;
    previewRow = null; // the kebab dataset of the row being previewed

    filterBucket = 'all';
    searchTerm = '';
    filtersOpen = false;
    filterCycle = 'all';
    filterArea = 'all';
    sortBy = 'default';
    page = 1;

    _cycleId = null;

    /** The header switcher's selection drives the cycle scope; the old
     *  per-view Cycle combobox is gone. Null/undefined = All cycles. */
    @api
    get cycleId() {
        return this._cycleId;
    }
    set cycleId(value) {
        this._cycleId = value || null;
        this.filterCycle = this._cycleId || 'all';
        this.page = 1;
    }

    connectedCallback() {
        this.load();
    }

    @api
    async load() {
        this.loading = true;
        try {
            // The queue owns both fetches: the tab counts must exist before
            // either tab body mounts, and the cycle scope applies in one place.
            const [queue, sessions] = await Promise.all([
                getQueue(), getExploratorySessions()
            ]);
            this.queue = queue;
            this.sessions = sessions || [];
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
            this.page = 1;
        }
    }

    // ---- Tabs -------------------------------------------------------------------

    get tabs() {
        return [
            { ...TABS[0], count: this.scopedRows.length },
            { ...TABS[1], count: this.scopedSessions.length }
        ];
    }

    get isAssignedTab() {
        return this.activeTab === 'assigned';
    }

    get isExploratoryTab() {
        return this.activeTab === 'exploratory';
    }

    handleTabChange(event) {
        this.activeTab = event.detail.value;
        this.page = 1;
    }

    // ---- Rows (flattened) -----------------------------------------------------

    /** Assigned cards only — exploratory work lives on its own tab now. */
    get assignedRows() {
        if (!this.queue) {
            return [];
        }
        const rows = [];
        const groups = [...(this.queue.cycleGroups || [])];
        if (this.queue.standalone) {
            groups.push(this.queue.standalone);
        }
        groups.forEach((grp) => {
            grp.cards.forEach((card, i) => {
                rows.push(this.decorateCard(card, grp, i));
            });
        });
        return rows;
    }

    /** The rows inside the header switcher's cycle scope — the shared base
     *  for tab counts, chips, area options, and featured selection, so every
     *  count on the page agrees with the visible list. */
    get scopedRows() {
        if (this.filterCycle === 'all') {
            return this.assignedRows;
        }
        return this.assignedRows.filter((r) => (r.cycleId || 'standalone') === this.filterCycle);
    }

    decorateCard(c, grp, i) {
        const displayTitle = c.caseTitle || humanizeCaseCode(c.caseCode);
        const bucket = bucketOf(c);
        const badge = BUCKET_BADGE[bucket] || BUCKET_BADGE.notStarted;
        const answered = c.stepsAnswered || 0;
        const hasSteps = (c.stepsTotal || 0) > 0;
        const percent = hasSteps
            ? Math.min(Math.max(Math.round((answered / c.stepsTotal) * 100), 0), 100)
            : null;
        let stepLabel = null;
        if (hasSteps) {
            stepLabel = bucket === 'inProgress'
                ? `Step ${Math.min(answered + 1, c.stepsTotal)} of ${c.stepsTotal}`
                : `${Math.min(answered, c.stepsTotal)} of ${c.stepsTotal} steps`;
        }
        const updatedShort = c.lastUpdated
            ? relativeTime(c.lastUpdated)
            : (c.lastTestedDate ? relativeDays(c.lastTestedDate) : null);
        // The pill carries the lifecycle; verdicts are secondary indicators —
        // a mid-run execution with a failed step is In Progress, not Failed.
        const statusNotes = [];
        if (bucket === 'completed') {
            if (c.result) {
                const tone = c.result === 'Passed' ? 'success'
                    : (c.result === 'Failed' ? 'error' : 'muted');
                statusNotes.push({
                    key: 'verdict',
                    label: c.result,
                    cssClass: `uq__status-note uq__status-note--${tone}`
                });
            }
        } else {
            const failed = c.stepsFailed || 0;
            const blocked = c.stepsBlocked || 0;
            if (failed > 0) {
                statusNotes.push({
                    key: 'failed',
                    label: `${failed} failed step${failed === 1 ? '' : 's'}`,
                    cssClass: 'uq__status-note uq__status-note--error'
                });
            }
            if (blocked > 0) {
                statusNotes.push({
                    key: 'blocked',
                    label: `${blocked} blocked step${blocked === 1 ? '' : 's'}`,
                    cssClass: 'uq__status-note uq__status-note--warning'
                });
            }
            // Last note, and the one that says why the row is still open. A
            // submitted run with an unanswered step used to read only as
            // "In Progress · 1 failed step", so the tester concluded the
            // FAILURE was holding it open and filed the status as a bug
            // (2026-08-13). Severity first, then the reason.
            //
            // Only once they've answered something — on an untouched run every
            // step is unanswered, which is what "Not Started" already says —
            // and never on a Complete run, where the server has already
            // established that every scripted step has an answer.
            const unanswered = answered > 0 && c.status !== 'Complete'
                ? Math.max((c.stepsTotal || 0) - answered, 0)
                : 0;
            if (unanswered > 0) {
                statusNotes.push({
                    key: 'unanswered',
                    label: unanswered === 1
                        ? '1 step needs a result'
                        : `${unanswered} steps need a result`,
                    cssClass: 'uq__status-note uq__status-note--muted'
                });
            }
        }
        return {
            ...c,
            key: c.executionId,
            // Overrides the server card's own cycleId/cycleName with the
            // group's — identical values today; the group stays the source
            // of truth for row rendering.
            cycleId: grp.cycleId || null,
            cycleName: grp.cycleName,
            targetDate: grp.targetDate,
            targetLabel: grp.targetDate ? `Target: ${formatDateLong(grp.targetDate)}` : null,
            displayTitle,
            statusLabel: badge.label,
            statusVariant: badge.variant,
            statusNotes,
            hasStatusNotes: statusNotes.length > 0,
            canRelease: c.status !== 'Complete',
            caseIndex: i + 1,
            caseTotal: grp.cards.length,
            bucket,
            rowClass: 'uq__tr' + (bucket === 'inProgress' ? ' uq__tr--active' : ''),
            caseMeta: joinMeta([c.caseNumber, c.moduleName]),
            stepLabel,
            stepFraction: hasSteps ? `${Math.min(answered, c.stepsTotal)} of ${c.stepsTotal}` : null,
            updatedShort,
            updatedLabel: updatedShort ? `Updated ${updatedShort}` : null,
            // Bar only with real step data, and not on finished work — a
            // missing metric renders as absence, never as a fabricated zero.
            showProgress: hasSteps && bucket !== 'completed',
            showStepText: hasSteps && bucket === 'completed',
            percentLabel: percent === null ? null : `${percent}% complete`,
            segments: hasSteps
                ? [
                    { value: answered, variant: 'accent', label: 'Answered' },
                    { value: Math.max(c.stepsTotal - answered, 0), variant: 'track', label: 'Remaining' }
                ]
                : [],
            progressAria: `${displayTitle}: ${percent === null ? 0 : percent}% complete`,
            actionAria: `${c.actionLabel} ${displayTitle}`,
            menuAlt: `More actions for ${displayTitle}`
        };
    }

    // ---- Exploratory tab ----------------------------------------------------------

    /** Sessions inside the header switcher's cycle scope — c-uat-session-list
     *  is presentational over this. */
    get scopedSessions() {
        if (this.filterCycle === 'all') {
            return this.sessions;
        }
        return this.sessions.filter((s) => s.cycleId === this.filterCycle);
    }

    /** The scoped cycle's name (for the findings-log link's event payload). */
    get scopedCycleName() {
        if (this.filterCycle === 'all' || !this.queue) {
            return null;
        }
        const grp = (this.queue.cycleGroups || [])
            .find((g) => g.cycleId === this.filterCycle);
        return grp ? grp.cycleName : null;
    }

    // ---- Chips / filters / search / sort ---------------------------------------

    get chips() {
        const rows = this.scopedRows;
        const count = (bucket) => rows.filter((r) => r.bucket === bucket).length;
        const chips = [
            { value: 'all', label: 'All', count: rows.length },
            { value: 'inProgress', label: 'In Progress', count: count('inProgress') },
            { value: 'notStarted', label: 'Not Started', count: count('notStarted') },
            { value: 'completed', label: 'Completed', count: count('completed') }
        ];
        // Blocked appears only when something is blocked — blocked work is
        // never mis-filed under Completed (bucketOf: the verdict outranks
        // the status).
        const blocked = count('blocked');
        if (blocked > 0) {
            chips.push({ value: 'blocked', label: 'Blocked', count: blocked });
        }
        return chips;
    }

    get areaOptions() {
        return areaOptionsFrom(this.scopedRows);
    }

    get sortOptions() {
        return SORT_OPTIONS;
    }

    get activeFilterCount() {
        // The cycle scope is global (header switcher), not a local filter.
        return this.filterArea === 'all' ? 0 : 1;
    }

    get filtersLabel() {
        return this.activeFilterCount ? `Filters · ${this.activeFilterCount}` : 'Filters';
    }

    get filtersExpanded() {
        return this.filtersOpen ? 'true' : 'false';
    }

    get hasActiveFilters() {
        return this.activeFilterCount > 0 || this.filterBucket !== 'all'
            || Boolean(this.searchTerm.trim()) || this.sortBy !== 'default';
    }

    get filteredRows() {
        let rows = this.scopedRows;
        if (this.filterBucket !== 'all') {
            rows = rows.filter((r) => r.bucket === this.filterBucket);
        }
        if (this.filterArea !== 'all') {
            rows = rows.filter((r) => areaOf(r) === this.filterArea);
        }
        const term = this.searchTerm;
        if (term.trim()) {
            rows = rows.filter((r) => matchesSearch(term, [
                r.displayTitle, r.description, r.caseCode, r.caseNumber,
                r.moduleName, r.systemName, r.cycleName
            ]));
        }
        if (this.sortBy === 'updated') {
            rows = [...rows].sort(byUpdatedDesc);
        } else if (this.sortBy === 'target') {
            rows = [...rows].sort(byTargetAsc);
        } else {
            // Default "Cycle order" groups by lifecycle first (In Progress →
            // Blocked → Not Started → Completed); sort() is stable, so the
            // server's cycle order survives as the tiebreak within buckets.
            rows = [...rows].sort(
                (a, b) => (BUCKET_ORDER[a.bucket] ?? 99) - (BUCKET_ORDER[b.bucket] ?? 99)
            );
        }
        return rows;
    }

    // ---- Featured "Continue Testing" card ---------------------------------------

    /** The single most relevant run: first in-progress in server group order
     *  (cycles with in-flight work first, then nearest target), else first
     *  not-started. Hidden while any row-HIDING control is active — chip,
     *  search, or area filter — so the page never shows a card the list
     *  wouldn't; sort alone only reorders, so it keeps the card. */
    get featuredRow() {
        if (this.filterBucket !== 'all' || this.searchTerm.trim() || this.filterArea !== 'all') {
            return null;
        }
        const rows = this.scopedRows;
        return rows.find((r) => r.bucket === 'inProgress')
            || rows.find((r) => r.bucket === 'notStarted')
            || null;
    }

    /** The dense list: filtered rows minus the featured card (when shown). */
    get listRows() {
        const featured = this.featuredRow;
        if (!featured) {
            return this.filteredRows;
        }
        return this.filteredRows.filter((r) => r.key !== featured.key);
    }

    // ---- Paging -----------------------------------------------------------------

    get pageSize() {
        return PAGE_SIZE;
    }

    /** Data changes (release, filters) can strand `page` past the end —
     *  render the last real page instead. */
    get clampedPage() {
        const pageCount = Math.max(1, Math.ceil(this.listRows.length / PAGE_SIZE));
        return Math.min(this.page, pageCount);
    }

    get pagedRows() {
        const start = (this.clampedPage - 1) * PAGE_SIZE;
        return this.listRows.slice(start, start + PAGE_SIZE);
    }

    get totalFiltered() {
        return this.listRows.length;
    }

    /** Section headers only where sections mean something: the default sort
     *  (bucket-ordered) with the All chip — a chip-filtered list is
     *  single-bucket by definition, a date-sorted list interleaves buckets,
     *  and a single-bucket list needs no announcement. */
    get showGroupHeaders() {
        if (this.sortBy !== 'default' || this.filterBucket !== 'all') {
            return false;
        }
        return new Set(this.listRows.map((r) => r.bucket)).size > 1;
    }

    /** The page slice regrouped for rendering — pager math is untouched.
     *  Header counts span the whole filtered list (so a group that crosses a
     *  page boundary repeats with the same number); they can read one lower
     *  than the chip when the featured card absorbs a row — honest: the
     *  header describes the list, the chip describes the scope. */
    get pagedGroups() {
        const rows = this.pagedRows;
        if (!this.showGroupHeaders) {
            return rows.length ? [{ key: 'all', label: null, countLabel: null, rows }] : [];
        }
        const totals = {};
        this.listRows.forEach((r) => {
            totals[r.bucket] = (totals[r.bucket] || 0) + 1;
        });
        const groups = [];
        rows.forEach((r) => {
            const last = groups[groups.length - 1];
            if (last && last.key === r.bucket) {
                last.rows.push(r);
            } else {
                const badge = BUCKET_BADGE[r.bucket] || BUCKET_BADGE.notStarted;
                groups.push({
                    key: r.bucket,
                    label: badge.label,
                    countLabel: String(totals[r.bucket] || 0),
                    rows: [r]
                });
            }
        });
        return groups;
    }

    // ---- View state ---------------------------------------------------------------

    get isEmpty() {
        return this.assignedRows.length === 0;
    }

    get isFilteredEmpty() {
        return !this.isEmpty && this.filteredRows.length === 0;
    }

    get hasRows() {
        return this.pagedRows.length > 0;
    }

    get releaseOpen() {
        return Boolean(this.releaseTarget);
    }

    get releaseHeader() {
        return this.releaseTarget ? `Release: ${this.releaseTarget.caseCode}` : '';
    }

    // ---- Handlers -------------------------------------------------------------------

    handleChipSelect(event) {
        this.filterBucket = event.detail.value;
        this.page = 1;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.page = 1;
    }

    handleToggleFilters() {
        this.filtersOpen = !this.filtersOpen;
    }

    handleFilterArea(event) {
        this.filterArea = event.detail.value;
        this.page = 1;
    }

    handleSort(event) {
        this.sortBy = event.detail.value;
        this.page = 1;
    }

    handleClearFilters() {
        // Deliberately leaves filterCycle alone — the cycle scope belongs
        // to the header switcher, and Clear must not fight it.
        this.filterBucket = 'all';
        this.searchTerm = '';
        this.filterArea = 'all';
        this.sortBy = 'default';
        this.page = 1;
    }

    handlePageChange(event) {
        this.page = event.detail.page;
    }

    handleCardAction(event) {
        const ds = event.currentTarget.dataset;
        this.openExecution(ds);
    }

    openExecution(ds) {
        this.dispatchEvent(new CustomEvent('open', {
            detail: {
                executionId: ds.id,
                claim: false,
                caseIndex: ds.index ? Number(ds.index) : null,
                caseTotal: ds.total ? Number(ds.total) : null
            }
        }));
    }

    handleMenuSelect(event) {
        const ds = event.currentTarget.dataset;
        const action = event.detail.value;
        if (action === 'details') {
            this.handlePreview(ds);
        } else if (action === 'release') {
            this.releaseTarget = { executionId: ds.id, caseCode: ds.code };
        }
    }

    // ---- Case preview (read-only, no run load) --------------------------------------

    async handlePreview(ds) {
        this.previewRow = { id: ds.id, index: ds.index, total: ds.total, title: ds.title };
        this.previewOpen = true;
        this.previewLoading = true;
        this.previewError = undefined;
        this.previewData = undefined;
        try {
            this.previewData = await getCasePreview({ executionId: ds.id });
        } catch (e) {
            // A load failure belongs in the dialog the tester is looking at,
            // not in a toast behind it.
            this.previewError = messageFrom(e);
        } finally {
            this.previewLoading = false;
        }
    }

    handlePreviewClose() {
        this.previewOpen = false;
        this.previewLoading = false;
        this.previewError = undefined;
        this.previewData = undefined;
        this.previewRow = null;
    }

    /** Close first, THEN open the runner — same order the pool uses for Claim. */
    handlePreviewStart() {
        const row = this.previewRow;
        this.handlePreviewClose();
        this.openExecution({ id: row.id, index: row.index, total: row.total });
    }

    get previewTitle() {
        return this.previewRow ? this.previewRow.title : '';
    }

    get previewSubtitle() {
        if (!this.previewData) {
            return '';
        }
        return joinMeta([this.previewData.caseCode, this.previewData.cycleName]);
    }

    get showPreviewBody() {
        return !this.previewLoading && !this.previewError && Boolean(this.previewData);
    }

    handleReleaseCancel() {
        this.releaseTarget = null;
    }

    async handleReleaseConfirm(event) {
        const reason = event.detail && event.detail.comment;
        this.releaseBusy = true;
        try {
            await releaseClaim({ inputJson: JSON.stringify({
                executionId: this.releaseTarget.executionId,
                reason
            }) });
            this.releaseTarget = null;
            toast(this, 'success', 'Released — the seat is back in the pool.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.releaseBusy = false;
        }
    }

    handleGoToPool() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { view: 'pool' } }));
    }

    // c-uat-session-list events relay upward — uatTesterApp owns the routing.
    handleSessionOpen(event) {
        this.dispatchEvent(new CustomEvent('sessionopen', { detail: event.detail }));
    }

    /** A session was deleted in the list — refetch so the session rows and
     *  the tab counts move together (the counting rule). */
    handleSessionsChange() {
        this.load();
    }

    handleExploratoryRelay(event) {
        this.dispatchEvent(new CustomEvent('exploratory', { detail: event.detail }));
    }
}

/** Most recently touched first; rows without any date last. */
function byUpdatedDesc(a, b) {
    const av = a.lastUpdated || a.lastTestedDate || null;
    const bv = b.lastUpdated || b.lastTestedDate || null;
    if (!av && !bv) {
        return 0;
    }
    if (!av) {
        return 1;
    }
    if (!bv) {
        return -1;
    }
    return new Date(bv) - new Date(av);
}

/** Soonest target first; rows without one last. ISO dates compare as text. */
function byTargetAsc(a, b) {
    if (!a.targetDate && !b.targetDate) {
        return 0;
    }
    if (!a.targetDate) {
        return 1;
    }
    if (!b.targetDate) {
        return -1;
    }
    return a.targetDate < b.targetDate ? -1 : (a.targetDate > b.targetDate ? 1 : 0);
}