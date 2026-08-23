import { LightningElement, api } from 'lwc';
import getDashboard from '@salesforce/apex/UatRunController.getDashboard';
import claimCase from '@salesforce/apex/UatRunController.claimCase';
import findOrCreateAdHocSession from '@salesforce/apex/UatSessionController.findOrCreateAdHocSession';
import { humanizeCaseCode } from 'c/uatTitleUtil';
import { messageFrom, toast } from 'c/messageUtil';
import {
    PRIORITY_VARIANT,
    RESULT_VARIANT,
    CYCLE_STATUS_VARIANT,
    CASE_PRIORITIES,
    toFilterOptions
} from 'c/uatConstants';
import {
    relativeDays,
    relativeTime,
    formatDateLong,
    joinMeta,
    metaItems,
    areaOf,
    areaOptionsFrom,
    matchesSearch
} from 'c/uatCardUtil';

const AVAILABLE_DISPLAY_CAP = 6;

/** Metric row item — zero values keep a neutral gray icon so an empty
 *  category looks intentional rather than alarming. */
function statItem(key, label, value, icon, tone) {
    const toneClass = value ? ` ud__stat-icon--${tone}` : ' ud__stat-icon--muted';
    return { key, label, value, icon, iconClass: 'ud__stat-icon' + toneClass };
}

/**
 * uatDashboard — the tester's landing view, an operational dashboard:
 * a compact white cycle-summary card (cycle name, status chip, cycle-wide
 * progress ring + stat row + segmented bar — all sans, see the CSS header),
 * then a two-column grid: Active Test and the filterable Available Tests on
 * the left, My Queue summary / Cycle Activity / Recently Completed in the
 * sidebar. One Apex call (getDashboard) feeds everything; filtering is
 * client-side over the uncapped pool list. Embedded by uatTesterApp only.
 *
 * Cards headline with the case's human-readable title (Test_Case__c.Title__c,
 * falling back to the Case_ID__c slug for untitled cases); the short
 * TC-number + version live in the meta line.
 */
export default class UatDashboard extends LightningElement {
    dashboard;
    loading = true;
    errorMessage;
    busy = false;

    searchTerm = '';
    filterArea = 'all';
    filterPriority = 'all';
    quickOnly = false;

    startingAdHoc = false;
    _cycleId = null;
    _connected = false;

    /** The header switcher's selection; null = All cycles (auto hero). */
    @api
    get cycleId() {
        return this._cycleId;
    }
    set cycleId(value) {
        const next = value || null;
        if (next === this._cycleId) {
            return;
        }
        this._cycleId = next;
        if (this._connected) {
            this.load(); // the setter also fires pre-connect on mount
        }
    }

    connectedCallback() {
        this._connected = true;
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.dashboard = await getDashboard({ cycleId: this._cycleId });
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    /** Scoped to one cycle: per-card cycle labels are redundant noise. */
    get isScoped() {
        return Boolean(this._cycleId);
    }

    // ---- Cycle summary ------------------------------------------------------------

    get hero() {
        return this.dashboard ? this.dashboard.hero : null;
    }

    get hasHero() {
        return Boolean(this.hero);
    }

    get cycleStatusLabel() {
        const status = (this.hero && this.hero.cycleStatus) || 'Active';
        return status === 'Active' ? 'Active cycle' : status;
    }

    get cycleStatusVariant() {
        const status = (this.hero && this.hero.cycleStatus) || 'Active';
        return CYCLE_STATUS_VARIANT[status] || 'default';
    }

    get daysRemainingLabel() {
        const h = this.hero;
        if (!h || h.daysToTarget == null) {
            return null;
        }
        if (h.daysToTarget < 0) {
            const overdue = -h.daysToTarget;
            return `${overdue} day${overdue === 1 ? '' : 's'} overdue`;
        }
        if (h.daysToTarget === 0) {
            return 'Due today';
        }
        return `${h.daysToTarget} day${h.daysToTarget === 1 ? '' : 's'} remaining`;
    }

    get cycleEndsLabel() {
        const formatted = this.hero ? formatDateLong(this.hero.targetDate) : null;
        return formatted ? `Cycle ends ${formatted}` : null;
    }

    get cyclePercent() {
        const h = this.hero;
        if (!h || !h.cycleTotal) {
            return 0;
        }
        return Math.round((h.cycleCompleted / h.cycleTotal) * 100);
    }

    get cycleStats() {
        const h = this.hero;
        if (!h) {
            return [];
        }
        return [
            statItem('completed', 'Completed', h.cycleCompleted, 'utility:success', 'success'),
            statItem('inprogress', 'In progress', h.cycleInProgress, 'utility:clock', 'info'),
            statItem('blocked', 'Blocked', h.cycleBlocked, 'utility:error', 'error'),
            statItem('available', 'Available', h.cycleAvailable, 'utility:open_folder', 'accent')
        ];
    }

    /* Completed-vs-remaining only (the mock's thin cyan bar). The status
       breakdown lives in the metric row — putting it in the bar too made a
       lone in-progress seat render as a full-width navy bar. */
    get cycleSegments() {
        const h = this.hero;
        if (!h) {
            return [];
        }
        return [
            { value: h.cycleCompleted, variant: 'accent', label: 'Completed' },
            { value: h.cycleTotal - h.cycleCompleted, variant: 'track', label: 'Remaining' }
        ];
    }

    get testsCaption() {
        const h = this.hero;
        if (!h) {
            return '';
        }
        return `${h.cycleCompleted} of ${h.cycleTotal} test${h.cycleTotal === 1 ? '' : 's'} completed`;
    }

    get cycleProgressAriaLabel() {
        return `Cycle progress: ${this.testsCaption}`;
    }

    // ---- Active test ----------------------------------------------------------------

    get activeTest() {
        const cards = this.dashboard ? this.dashboard.continueTesting : [];
        if (!cards.length) {
            return null;
        }
        const c = cards[0];
        return {
            ...c,
            displayTitle: c.caseTitle || humanizeCaseCode(c.caseCode),
            metaItems: metaItems([
                { icon: 'utility:check', label: c.stepsTotal
                    ? `Step ${Math.min((c.stepsAnswered || 0) + 1, c.stepsTotal)} of ${c.stepsTotal}`
                    : null },
                { icon: 'utility:clock', label: c.lastTestedDate
                    ? `Updated ${relativeDays(c.lastTestedDate)}` : null },
                { icon: 'utility:bookmark', label: c.caseNumber },
                { icon: 'utility:layers', label: c.version },
                { icon: 'utility:event', label: this.isScoped ? null : c.cycleName }
            ])
        };
    }

    get hasActiveTest() {
        return Boolean(this.activeTest);
    }

    get moreInProgressLabel() {
        const count = this.dashboard ? this.dashboard.continueTesting.length : 0;
        return count > 1 ? `+ ${count - 1} more in progress in your queue` : null;
    }

    // ---- Available tests --------------------------------------------------------------

    get availableAll() {
        return (this.dashboard ? this.dashboard.availableToClaim : []).map((c) => ({
            ...c,
            key: c.executionId,
            displayTitle: c.caseTitle || humanizeCaseCode(c.caseCode),
            claimCode: c.caseNumber || c.caseCode,
            priorityVariant: PRIORITY_VARIANT[c.priority] || 'default',
            metaItems: metaItems([
                { icon: 'utility:open_folder', label: c.moduleName },
                { icon: 'utility:clock', label: c.effort },
                { icon: 'utility:bookmark', label: c.caseNumber },
                { icon: 'utility:layers', label: c.version },
                { icon: 'utility:event', label: this.isScoped ? null : c.cycleName }
            ])
        }));
    }

    get availableCount() {
        return this.dashboard ? this.dashboard.availableToClaim.length : 0;
    }

    get hasAvailable() {
        return this.availableCount > 0;
    }

    get areaOptions() {
        return areaOptionsFrom(this.dashboard ? this.dashboard.availableToClaim : []);
    }

    get priorityOptions() {
        return toFilterOptions('All priorities', CASE_PRIORITIES);
    }

    get availableFiltered() {
        return this.availableAll.filter((c) => {
            if (this.filterArea !== 'all' && areaOf(c) !== this.filterArea) {
                return false;
            }
            if (this.filterPriority !== 'all' && c.priority !== this.filterPriority) {
                return false;
            }
            if (this.quickOnly && c.effort !== 'Small') {
                return false;
            }
            return matchesSearch(this.searchTerm, [
                c.displayTitle, c.caseCode, c.caseNumber, c.moduleName
            ]);
        });
    }

    get availableDisplay() {
        return this.availableFiltered.slice(0, AVAILABLE_DISPLAY_CAP);
    }

    get hasFilteredResults() {
        return this.availableFiltered.length > 0;
    }

    get hasMoreAvailable() {
        return this.availableFiltered.length > AVAILABLE_DISPLAY_CAP;
    }

    get viewAllLabel() {
        return `View all ${this.availableFiltered.length} in the Open Pool`;
    }

    // ---- Sidebar ------------------------------------------------------------------------

    get queueStats() {
        const s = this.dashboard ? this.dashboard.queueSummary : null;
        if (!s) {
            return [];
        }
        return [
            statItem('assigned', 'Assigned to me', s.total, 'utility:task', 'accent'),
            statItem('inprogress', 'In progress', s.inProgress, 'utility:clock', 'info'),
            statItem('blocked', 'Blocked', s.blocked, 'utility:error', 'error'),
            statItem('completed', 'Completed', s.completed, 'utility:success', 'success')
        ];
    }

    get activityRows() {
        const raw = this.dashboard ? this.dashboard.recentActivity : [];
        // Consecutive events by the same person with the same action collapse
        // into one row ("claimed 4 tests") — five identical lines is noise,
        // not a feed. Rows arrive newest-first; a group keeps its newest time.
        const grouped = [];
        raw.forEach((item) => {
            const last = grouped[grouped.length - 1];
            if (last && last.action === item.action
                && last.testerName === item.testerName && last.isMe === item.isMe) {
                last.count++;
                return;
            }
            grouped.push({ ...item, count: 1 });
        });
        return grouped.map((item) => {
            const who = item.isMe ? 'You' : (item.testerName || 'A tester');
            const noun = item.count === 1 ? 'a test' : `${item.count} tests`;
            let text;
            if (item.action === 'Claimed') {
                text = `${who} claimed ${noun}`;
            } else if (item.action === 'Released') {
                text = `${who} released ${noun} back to the pool`;
            } else if (item.action === 'Auto Released') {
                const what = item.count === 1 ? 'stale claim was' : `${item.count} stale claims were`;
                text = item.isMe ? `Your ${what} returned to the pool`
                    : `${who}'s ${what} returned to the pool`;
            } else {
                text = item.count === 1
                    ? `A test was reassigned to ${item.isMe ? 'you' : who}`
                    : `${item.count} tests were reassigned to ${item.isMe ? 'you' : who}`;
            }
            return { key: item.id, text, timeLabel: relativeTime(item.timestamp) };
        });
    }

    get hasActivity() {
        return this.activityRows.length > 0;
    }

    get recentlyCompleted() {
        return (this.dashboard ? this.dashboard.recentlyCompleted : []).map((c) => ({
            ...c,
            key: c.executionId,
            displayTitle: c.caseTitle || humanizeCaseCode(c.caseCode),
            resultVariant: RESULT_VARIANT[c.result] || 'default',
            resultLabel: c.result || c.status,
            metaLabel: joinMeta([c.caseNumber, c.version, this.isScoped ? null : c.cycleName]),
            timeLabel: c.lastTestedDate ? relativeDays(c.lastTestedDate) : null
        }));
    }

    get hasRecentlyCompleted() {
        return this.recentlyCompleted.length > 0;
    }

    get isAllCaughtUp() {
        if (this.loading || this.errorMessage) {
            return false;
        }
        const d = this.dashboard;
        return !d || (!d.hero && !d.continueTesting.length && !d.availableToClaim.length);
    }

    // ---- Handlers ---------------------------------------------------------------

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleAreaChange(event) {
        this.filterArea = event.detail.value;
    }

    handlePriorityChange(event) {
        this.filterPriority = event.detail.value;
    }

    handleQuickToggle(event) {
        this.quickOnly = event.target.checked;
    }

    handleOpenCard(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('open', { detail: { executionId: ds.id, claim: false } }));
    }

    async handleClaim(event) {
        const ds = event.currentTarget.dataset;
        this.busy = true;
        try {
            await claimCase({ cycleId: ds.cycleid, caseId: ds.caseid });
            toast(this, 'success', `Claimed ${ds.code} — it's in My Queue.`);
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.busy = false;
        }
        await this.load();
    }

    /**
     * The off-script escape hatch. Find-or-create, so clicking it repeatedly
     * across a sprint lands the tester back in ONE running log rather than
     * leaving a trail of empty sessions behind them. Scoped to whatever cycle
     * the switcher currently has selected — a null cycle is a valid answer and
     * makes a standalone session.
     */
    async handleAdHoc() {
        this.startingAdHoc = true;
        try {
            const sessionId = await findOrCreateAdHocSession({ cycleId: this._cycleId });
            this.dispatchEvent(new CustomEvent('sessionopen', { detail: { sessionId } }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.startingAdHoc = false;
        }
    }

    handleGoToQueue() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { view: 'queue' } }));
    }

    handleGoToPool() {
        this.dispatchEvent(new CustomEvent('navigate', { detail: { view: 'pool' } }));
    }

}