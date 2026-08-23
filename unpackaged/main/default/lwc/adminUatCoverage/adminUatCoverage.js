import { LightningElement } from 'lwc';
import getCoverage from '@salesforce/apex/UatCoverageController.getCoverage';
import getCycleDrilldown from '@salesforce/apex/UatCoverageController.getCycleDrilldown';
import { messageFrom, toast } from 'c/messageUtil';
import { humanizeCaseCode } from 'c/uatTitleUtil';

/**
 * adminUatCoverage — Pool Health: per-cycle coverage health (unclaimed seats,
 * claim/progress counts, oldest sitting seat, days to target, at-risk flag)
 * with a per-cycle drill-down of unclaimed cases and the recent
 * assignment-event feed. Read-only; "Open cycle" hops to the Cycles editor
 * via the console's uatnavigate event. Embedded by adminConsole only.
 */
export default class AdminUatCoverage extends LightningElement {
    cycles;
    loading = true;
    errorMessage;

    openCycleId = null;
    openCycleName = null;
    drilldown = null;
    drillLoading = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.cycles = await getCoverage();
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        return (this.cycles || []).map((c) => ({
            ...c,
            rowClass: 'aucv__row' + (c.atRisk ? ' aucv__row--risk' : ''),
            targetLabel: c.daysToTarget == null ? '—'
                : c.daysToTarget < 0 ? `${-c.daysToTarget}d overdue`
                : c.daysToTarget === 0 ? 'today'
                : `in ${c.daysToTarget}d`,
            oldestLabel: c.oldestUnclaimedDays == null ? '—'
                : c.oldestUnclaimedDays === 0 ? 'today'
                : `${c.oldestUnclaimedDays}d`,
            teamLabel: c.teamName || 'Whole pool',
            isOpen: c.cycleId === this.openCycleId
        }));
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get drillEvents() {
        if (!this.drilldown) {
            return [];
        }
        return this.drilldown.events.map((e, index) => ({
            ...e,
            key: index,
            line: this.eventLine(e)
        }));
    }

    eventLine(e) {
        const who = e.testerName || 'Unknown';
        const by = e.actorName && e.actorName !== e.testerName ? ` by ${e.actorName}` : '';
        const what = e.caseCode ? ` — ${e.caseCode}` : '';
        return `${e.action}: ${who}${by}${what}`;
    }

    get drillUnclaimed() {
        return this.drilldown
            ? this.drilldown.unclaimed.map((seat) => ({
                ...seat,
                titleDisplay: seat.caseTitle || humanizeCaseCode(seat.caseCode)
            }))
            : [];
    }

    get drillHasUnclaimed() {
        return this.drillUnclaimed.length > 0;
    }

    get drillHasEvents() {
        return this.drillEvents.length > 0;
    }

    async handleRowToggle(event) {
        const ds = event.currentTarget.dataset;
        if (this.openCycleId === ds.id) {
            this.openCycleId = null;
            this.drilldown = null;
            return;
        }
        this.openCycleId = ds.id;
        this.openCycleName = ds.name;
        this.drilldown = null;
        this.drillLoading = true;
        try {
            this.drilldown = await getCycleDrilldown({ cycleId: ds.id });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.drillLoading = false;
        }
    }

    handleOpenCycle(event) {
        event.stopPropagation();
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('uatnavigate', {
            bubbles: true,
            composed: true,
            detail: { section: 'uatCycles', recordId: ds.id }
        }));
    }

}