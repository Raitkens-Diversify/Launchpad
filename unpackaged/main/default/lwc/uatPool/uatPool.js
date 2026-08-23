import { LightningElement, api } from 'lwc';
import getPool from '@salesforce/apex/UatRunController.getPool';
import claimCase from '@salesforce/apex/UatRunController.claimCase';
import claimAllAvailable from '@salesforce/apex/UatRunController.claimAllAvailable';
import getCasePreview from '@salesforce/apex/UatRunController.getCasePreview';
import { humanizeCaseCode } from 'c/uatTitleUtil';
import { messageFrom, toast } from 'c/messageUtil';
import {
    PRIORITY_ORDER,
    PRIORITY_VARIANT,
    EFFORT_ORDER,
    CASE_EFFORTS,
    toFilterOptions
} from 'c/uatConstants';
import { formatDateLong, joinMeta, areaOf, areaOptionsFrom, matchesSearch } from 'c/uatCardUtil';

/* Client-side paging over the full getPool payload (LIMIT 1000 server-side,
 * no server paging) — 12 ≈ three grid rows. */
const PAGE_SIZE = 12;

/* A lost race lingers on the card long enough to read, then the list
 * refreshes to reality. */
const JUST_FILLED_REFRESH_MS = 4000;

const SORT_OPTIONS = [
    { label: 'Priority first', value: 'priority' },
    { label: 'Smallest effort first', value: 'effort' },
    { label: 'Waiting longest first', value: 'waiting' }
];

/**
 * uatPool — "Open Pool": every claimable seat in the tester's audience, as
 * browsing-oriented card grids under slim per-cycle section headers. The
 * sections stay because bulk claim (claimAllAvailable) and the per-tester
 * claim limit are per-CYCLE server contracts — a fully flat grid would
 * orphan both. Priority chips (the picking axis), a quick-tests toggle,
 * search, a cycle/area/effort/sort filter panel, and client-side paging
 * (the page's cards regroup into their sections) sit on top.
 *
 * Claiming: one seat per Claim Test; "Claim all available" sweeps a cycle
 * behind a confirm and reports a tally — partial success is expected
 * behavior. A lost race renders a non-alarming inline note on the very card
 * (no toast) and refreshes shortly after, so the card visibly flips to
 * gone/full without a page reload. Other claim failures keep the server's
 * message as a toast plus an immediate refresh. Embedded by uatTesterApp
 * only.
 *
 * Preview (2026-08-14): the card title and a Details button open the whole
 * case — steps, expected results, pre-conditions, reference material — in a
 * c-ds-modal-v2 over c-uat-case-preview, WITHOUT claiming. The card's 240-char
 * blurb used to be all a tester had, so they claimed to browse and released.
 * getCasePreview is the one runner-shaped read that skips ensureStepResults, so
 * looking never writes step-result rows against a seat nobody holds. The
 * modal's Claim closes it FIRST and then delegates to handleClaim, so the
 * lost-race note lands on the card the tester is looking at.
 */
export default class UatPool extends LightningElement {
    pool;
    loading = true;
    errorMessage;
    busy = false;

    claimingId = null;   // executionId mid-claim (button shows "Claiming…")
    justFilledId = null; // executionId that just lost a race (inline note)

    filterPriority = 'all'; // the chip row
    quickOnly = false;
    searchTerm = '';
    filtersOpen = false;
    filterCycle = 'all';
    filterArea = 'all';
    filterEffort = 'all';
    sortBy = 'priority';
    page = 1;

    bulkTarget = null; // { cycleId, cycleName, count }
    bulkBusy = false;

    previewOpen = false;
    previewLoading = false;
    previewError;
    previewData;
    previewCard = null; // the claim dataset of the card being previewed

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

    disconnectedCallback() {
        if (this._justFilledTimer) {
            window.clearTimeout(this._justFilledTimer);
        }
    }

    @api
    async load() {
        this.loading = true;
        try {
            this.pool = await getPool();
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
            this.page = 1;
        }
    }

    // ---- Cards ------------------------------------------------------------------

    get allCards() {
        const cards = [];
        (this.pool || []).forEach((grp) => {
            grp.cards.forEach((c) => cards.push(this.decorateCard(c, grp)));
        });
        return cards;
    }

    decorateCard(card, grp) {
        const displayTitle = card.caseTitle || humanizeCaseCode(card.caseCode);
        const opened = new Date(card.openedDate);
        const days = Math.max(0, Math.floor((Date.now() - opened.getTime()) / 86400000));
        const justFilled = this.justFilledId === card.executionId;
        const claiming = this.claimingId === card.executionId;
        return {
            ...card,
            key: card.executionId,
            // Overrides the server card's own cycleName with the group's —
            // identical values today; the group stays the source of truth.
            cycleName: grp.cycleName,
            displayTitle,
            hasPriority: Boolean(card.priority),
            priorityVariant: PRIORITY_VARIANT[card.priority] || 'default',
            seatsLabel: card.seatsMax > 1
                ? `${card.seatsTaken} of ${card.seatsMax} claimed`
                : null,
            waitingLabel: days === 0 ? 'opened today' : `waiting ${days}d`,
            idLabel: joinMeta([card.caseNumber, card.version]),
            justFilled,
            claimLabel: claiming ? 'Claiming…' : 'Claim Test',
            claimDisabled: this.busy || justFilled,
            claimAria: `Claim ${displayTitle}`,
            previewAria: `Preview ${displayTitle}`
        };
    }

    /** The cards inside the header switcher's cycle scope — the shared base
     *  for the chips, the header count, the area options, and the visible
     *  grid, so every count on the page moves with the selection (same rule
     *  as the queue). */
    get scopedCards() {
        if (this.filterCycle === 'all') {
            return this.allCards;
        }
        return this.allCards.filter((c) => c.cycleId === this.filterCycle);
    }

    get filteredCards() {
        let cards = this.scopedCards;
        if (this.filterPriority !== 'all') {
            cards = cards.filter((c) => c.priority === this.filterPriority);
        }
        if (this.filterArea !== 'all') {
            cards = cards.filter((c) => areaOf(c) === this.filterArea);
        }
        if (this.filterEffort !== 'all') {
            cards = cards.filter((c) => c.effort === this.filterEffort);
        }
        if (this.quickOnly) {
            cards = cards.filter((c) => c.effort === 'Small');
        }
        if (this.searchTerm.trim()) {
            cards = cards.filter((c) => matchesSearch(this.searchTerm, [
                c.displayTitle, c.description, c.caseCode, c.caseNumber,
                c.moduleName, c.systemName, c.cycleName
            ]));
        }
        const sorters = {
            priority: (a, b) => rank(PRIORITY_ORDER, a.priority) - rank(PRIORITY_ORDER, b.priority),
            effort: (a, b) => rank(EFFORT_ORDER, a.effort) - rank(EFFORT_ORDER, b.effort),
            waiting: (a, b) => new Date(a.openedDate) - new Date(b.openedDate)
        };
        return [...cards].sort(sorters[this.sortBy] || sorters.priority);
    }

    // ---- Paging + regrouping ------------------------------------------------------

    get pageSize() {
        return PAGE_SIZE;
    }

    get clampedPage() {
        const pageCount = Math.max(1, Math.ceil(this.filteredCards.length / PAGE_SIZE));
        return Math.min(this.page, pageCount);
    }

    get totalFiltered() {
        return this.filteredCards.length;
    }

    /** The page's cards, regrouped into their cycle sections (a section
     *  renders only when it has cards on the current page). */
    get pagedGroups() {
        const start = (this.clampedPage - 1) * PAGE_SIZE;
        const pageCards = this.filteredCards.slice(start, start + PAGE_SIZE);
        const byCycle = new Map();
        pageCards.forEach((c) => {
            if (!byCycle.has(c.cycleId)) {
                byCycle.set(c.cycleId, []);
            }
            byCycle.get(c.cycleId).push(c);
        });
        return [...byCycle.entries()].map(([cycleId, cards]) => {
            const grp = (this.pool || []).find((g) => g.cycleId === cycleId) || {};
            const atClaimLimit = grp.claimLimit != null && grp.myOpenClaims >= grp.claimLimit;
            return {
                cycleId,
                cycleName: grp.cycleName,
                targetLabel: grp.targetDate ? `Target: ${formatDateLong(grp.targetDate)}` : null,
                claimHint: grp.claimLimit == null
                    ? null
                    : `You hold ${grp.myOpenClaims} of ${grp.claimLimit} allowed claims`,
                hintClass: 'uap__group-hint' + (atClaimLimit ? ' uap__group-hint--limit' : ''),
                atClaimLimit,
                bulkDisabled: this.busy || atClaimLimit,
                // The sweep takes the cycle's whole availability, not just
                // this page's or this filter's slice — count honestly.
                bulkCount: (grp.cards || []).length,
                bulkLabel: `Claim all available (${(grp.cards || []).length})`,
                cards
            };
        });
    }

    // ---- Chips / filter options -----------------------------------------------------

    get chips() {
        const cards = this.scopedCards;
        const chips = [{ value: 'all', label: 'All', count: cards.length }];
        Object.keys(PRIORITY_ORDER)
            .sort((a, b) => PRIORITY_ORDER[a] - PRIORITY_ORDER[b])
            .forEach((priority) => {
                const count = cards.filter((c) => c.priority === priority).length;
                if (count > 0) {
                    chips.push({ value: priority, label: priority, count });
                }
            });
        return chips;
    }

    get availableCount() {
        return this.scopedCards.length;
    }

    get areaOptions() {
        return areaOptionsFrom(this.scopedCards);
    }

    get effortOptions() {
        return toFilterOptions('Any effort', CASE_EFFORTS);
    }

    get sortOptions() {
        return SORT_OPTIONS;
    }

    get activeFilterCount() {
        // The cycle scope is global (header switcher), not a local filter.
        return (this.filterArea === 'all' ? 0 : 1)
            + (this.filterEffort === 'all' ? 0 : 1);
    }

    get filtersLabel() {
        return this.activeFilterCount ? `Filters · ${this.activeFilterCount}` : 'Filters';
    }

    get filtersExpanded() {
        return this.filtersOpen ? 'true' : 'false';
    }

    get hasActiveFilters() {
        return this.activeFilterCount > 0 || this.filterPriority !== 'all'
            || this.quickOnly || Boolean(this.searchTerm.trim());
    }

    // ---- View state -------------------------------------------------------------------

    get poolIsEmpty() {
        return !this.pool || this.pool.length === 0;
    }

    get isFilteredEmpty() {
        return !this.poolIsEmpty && this.filteredCards.length === 0;
    }

    get hasGroups() {
        return this.pagedGroups.length > 0;
    }

    get bulkOpen() {
        return Boolean(this.bulkTarget);
    }

    get bulkHeader() {
        return this.bulkTarget ? `Claim all in ${this.bulkTarget.cycleName}` : '';
    }

    get bulkMessage() {
        if (!this.bulkTarget) {
            return '';
        }
        const n = this.bulkTarget.count;
        return `Claim all ${n} available test${n === 1 ? '' : 's'} in ${this.bulkTarget.cycleName}? `
            + `If someone grabs one first you'll get the rest — partial success is normal.`;
    }

    // ---- Filter handlers ---------------------------------------------------------------

    handleChipSelect(event) {
        this.filterPriority = event.detail.value;
        this.page = 1;
    }

    handleQuickToggle(event) {
        this.quickOnly = event.target.checked;
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

    handleFilterEffort(event) {
        this.filterEffort = event.detail.value;
        this.page = 1;
    }

    handleSort(event) {
        this.sortBy = event.detail.value;
        this.page = 1;
    }

    handleClearFilters() {
        // Deliberately leaves filterCycle alone — the cycle scope belongs
        // to the header switcher, and Clear must not fight it.
        this.filterPriority = 'all';
        this.quickOnly = false;
        this.searchTerm = '';
        this.filterArea = 'all';
        this.filterEffort = 'all';
        this.sortBy = 'priority';
        this.page = 1;
    }

    handlePageChange(event) {
        this.page = event.detail.page;
    }

    handleGoToQueue() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { view: 'queue' } }));
    }

    // ---- Preview ------------------------------------------------------------------------

    /** The card title and the Details button both land here — same dataset. */
    async handlePreview(event) {
        const ds = event.currentTarget.dataset;
        this.previewCard = {
            execid: ds.execid,
            cycleid: ds.cycleid,
            caseid: ds.caseid,
            code: ds.code,
            title: ds.title
        };
        this.previewOpen = true;
        this.previewLoading = true;
        this.previewError = undefined;
        this.previewData = undefined;
        try {
            this.previewData = await getCasePreview({ executionId: ds.execid });
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
        this.previewCard = null;
    }

    /** Close first, THEN claim: handleClaim's lost-race branch paints an inline
     *  note on the card, which is unreadable behind an open dialog. */
    async handlePreviewClaim(event) {
        const target = event.currentTarget;
        this.handlePreviewClose();
        await this.handleClaim({ currentTarget: target });
    }

    get previewTitle() {
        return this.previewCard ? this.previewCard.title : '';
    }

    get previewSubtitle() {
        if (!this.previewCard) {
            return '';
        }
        return joinMeta([this.previewCard.code, this.previewData && this.previewData.cycleName]);
    }

    /** The body renders only once the read lands cleanly. */
    get showPreviewBody() {
        return !this.previewLoading && !this.previewError && Boolean(this.previewData);
    }

    get previewClaimDisabled() {
        return this.busy || this.previewLoading || Boolean(this.previewError);
    }

    // ---- Claims -------------------------------------------------------------------------

    async handleClaim(event) {
        const ds = event.currentTarget.dataset;
        this.claimingId = ds.execid;
        this.busy = true;
        try {
            await claimCase({ cycleId: ds.cycleid, caseId: ds.caseid });
            this.busy = false;
            this.claimingId = null;
            toast(this, 'success', `Claimed ${ds.code} — it's in My Queue.`);
            await this.load();
        } catch (e) {
            this.busy = false;
            this.claimingId = null;
            const message = messageFrom(e);
            if (/beat you/i.test(message)) {
                // Lost race (PoolFullException prose): a non-alarming note ON
                // the card instead of a toast, then a short-delay refresh
                // flips the card to its real state — no page reload.
                this.justFilledId = ds.execid;
                this._justFilledTimer = window.setTimeout(() => {
                    this.justFilledId = null;
                    this.load();
                }, JUST_FILLED_REFRESH_MS);
            } else {
                // Cap reached / cycle paused / pool busy: the server's
                // message IS the explanation; refresh shows current truth.
                toast(this, 'error', message);
                await this.load();
            }
        }
    }

    handleBulkClick(event) {
        const ds = event.currentTarget.dataset;
        this.bulkTarget = {
            cycleId: ds.cycleid,
            cycleName: ds.cyclename,
            count: Number(ds.count) || 0
        };
    }

    handleBulkCancel() {
        this.bulkTarget = null;
    }

    async handleBulkConfirm() {
        this.bulkBusy = true;
        this.busy = true;
        try {
            const tally = await claimAllAvailable({ cycleId: this.bulkTarget.cycleId });
            let message = `Claimed ${tally.claimed}.`;
            if (tally.takenByOthers > 0) {
                message += ` ${tally.takenByOthers} were taken by others while you clicked.`;
            }
            if (tally.capReached) {
                message += ' You hit your claim limit for this cycle.';
            }
            toast(this, tally.claimed > 0 ? 'success' : 'error', message);
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.bulkBusy = false;
            this.busy = false;
            this.bulkTarget = null;
        }
        await this.load();
    }
}

function rank(order, value) {
    return value in order ? order[value] : 99;
}