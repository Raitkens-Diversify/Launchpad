import { LightningElement } from 'lwc';
import getDashboardSummary from '@salesforce/apex/UatCoverageController.getDashboardSummary';
import { messageFrom } from 'c/messageUtil';

/**
 * adminUatDashboard — "Cycle Dashboard": the console's UAT Testing landing
 * section. A hero for the most at-risk (or first) open cycle, stat tiles
 * (at risk / unclaimed / failed / participation), and the at-risk cycle
 * list. Reduces UatCoverageController's existing rollups to a glanceable
 * summary — the dense per-cycle table (adminUatCoverage, still reachable as
 * "Pool Health") stays the drill-down, not the front door. Embedded by
 * adminConsole only.
 */
export default class AdminUatDashboard extends LightningElement {
    summary;
    loading = true;
    errorMessage;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.summary = await getDashboardSummary();
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- Hero -------------------------------------------------------------------

    get hero() {
        return this.summary ? this.summary.heroCycle : null;
    }

    get hasHero() {
        return Boolean(this.hero);
    }

    /* Four mutually-exclusive buckets (unclaimed / not started / in progress /
     * complete). Failed runs are surfaced as their own stat tile below, not a
     * bar segment — Testing_Result__c can be 'Failed' on a run that's still
     * In Progress, so it isn't exclusive with these buckets. */
    get heroSegments() {
        const h = this.hero;
        if (!h) {
            return [];
        }
        return [
            { value: h.completeClaims, variant: 'success', label: 'Complete' },
            { value: h.inProgressClaims, variant: 'accent', label: 'In progress' },
            { value: h.notStartedClaims, variant: 'track', label: 'Not started' },
            { value: h.unclaimedSeats, variant: 'track', label: 'Unclaimed' }
        ];
    }

    get heroSummary() {
        const h = this.hero;
        if (!h) {
            return '';
        }
        return `${h.caseCount} case${h.caseCount === 1 ? '' : 's'} · `
            + `${h.unclaimedSeats} unclaimed · ${h.completeClaims} complete · ${h.failedRuns} failed`;
    }

    get heroProgressAriaLabel() {
        return `Cycle progress: ${this.heroSummary}`;
    }

    get heroDeadlineLabel() {
        const h = this.hero;
        if (!h || h.daysToTarget == null) {
            return null;
        }
        if (h.daysToTarget < 0) {
            return `${-h.daysToTarget}d overdue`;
        }
        if (h.daysToTarget === 0) {
            return 'Due today';
        }
        return `${h.daysToTarget} day${h.daysToTarget === 1 ? '' : 's'} left`;
    }

    get hasHeroDeadline() {
        return Boolean(this.heroDeadlineLabel);
    }

    // ---- Stat tiles ---------------------------------------------------------------

    get atRiskCount() {
        return this.summary ? this.summary.atRiskCycles : 0;
    }

    get unclaimedCount() {
        return this.summary ? this.summary.unclaimedSeats : 0;
    }

    get failedCount() {
        return this.summary ? this.summary.failedRuns : 0;
    }

    get participationValue() {
        return this.summary ? this.summary.testersParticipating : 0;
    }

    get participationSublabel() {
        if (!this.summary) {
            return '';
        }
        return this.summary.testersTotal != null
            ? `of ${this.summary.testersTotal} eligible testers`
            : 'testers with a claim';
    }

    // ---- At-risk list ---------------------------------------------------------------

    get atRisk() {
        return (this.summary ? this.summary.atRisk : []).map((row) => ({
            ...row,
            key: row.cycleId,
            deadlineLabel: row.daysToTarget == null ? '—'
                : row.daysToTarget < 0 ? `${-row.daysToTarget}d overdue`
                : row.daysToTarget === 0 ? 'due today'
                : `due in ${row.daysToTarget}d`
        }));
    }

    get hasAtRisk() {
        return this.atRisk.length > 0;
    }

    get isEmpty() {
        return !this.loading && !this.errorMessage && !this.hasHero;
    }

    // ---- Handlers ---------------------------------------------------------------

    handleOpenCycle(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('uatnavigate', {
            bubbles: true,
            composed: true,
            detail: { section: 'uatCycles', recordId: ds.id }
        }));
    }

}