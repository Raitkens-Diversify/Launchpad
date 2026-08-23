import { LightningElement } from 'lwc';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import USER_ID from '@salesforce/user/Id';
import getMyCycles from '@salesforce/apex/UatRunController.getMyCycles';

/* localStorage guarded like bookOfBusinessUtils: typeof checks + try/catch —
 * private mode or storage quirks degrade to "selection doesn't persist",
 * never an error. Key is per-user so shared machines don't leak scope. */
const CYCLE_KEY_PREFIX = 'uat.selectedCycle.';

function storageKey() {
    return CYCLE_KEY_PREFIX + USER_ID;
}

function readStoredCycleId() {
    if (typeof window === 'undefined' || !window.localStorage) {
        return null;
    }
    try {
        return window.localStorage.getItem(storageKey());
    } catch (e) {
        return null;
    }
}

function writeStoredCycleId(cycleId) {
    if (typeof window === 'undefined' || !window.localStorage) {
        return;
    }
    try {
        if (cycleId) {
            window.localStorage.setItem(storageKey(), cycleId);
        } else {
            window.localStorage.removeItem(storageKey());
        }
    } catch (e) {
        // Not persistable — the selection still works for this session.
    }
}

/**
 * uatTesterApp — the Helios UAT tester app: a separate, task-focused surface
 * sharing the UAT objects with the Admin Console but none of its chrome.
 * Same orchestrator + branded-chrome pattern as resourceCenter/adminConsole:
 * one root LWC on a CustomTab, inline view swap (queue | pool | runner |
 * exploratory), no page navigation — behaves identically in the core app
 * and, if ever needed, an Experience Cloud LWR page.
 *
 * Queue vs Pool (open-pool design): My Queue is the tester's claimed work;
 * Open Pool is the claimable seats for their audience. The header nav swaps
 * between them; runner and exploratory always exit back to the queue.
 */
export default class UatTesterApp extends LightningElement {
    logoUrl = diversifyLogo;

    view = 'dashboard'; // dashboard | queue | pool | runner | exploratory | session
    activeExecutionId = null;
    activeSessionId = null;
    claimOnStart = false;
    activeCaseIndex = null;
    activeCaseTotal = null;
    activeCycleId = null;
    activeCycleName = null;

    // Header cycle switcher: the shell owns the selection (null = All
    // cycles) and threads it into dashboard/queue/pool as a prop.
    myCycles = [];
    selectedCycleId = null;
    selectedCycleName = null;

    connectedCallback() {
        this.refreshCycles();
    }

    /* Refetched on every nav-view change — the cheapest trigger for
     * mid-session assignment changes (a new cycle appears; a selection whose
     * cycle closed or moved teams resets to All on the next swap), matching
     * the area's refetch-after-every-action philosophy. */
    async refreshCycles() {
        try {
            this.myCycles = await getMyCycles();
        } catch (e) {
            this.myCycles = []; // switcher hides; views fall back to All cycles
        }
        this.applySelection(this.selectedCycleId || readStoredCycleId());
    }

    applySelection(wantedId) {
        const list = this.myCycles || [];
        // <2 cycles: the switcher is hidden, so never hold a scoped
        // selection the user couldn't see or undo.
        const match = list.length >= 2 ? list.find((c) => c.cycleId === wantedId) : null;
        this.selectedCycleId = match ? match.cycleId : null;
        this.selectedCycleName = match ? match.cycleName : null;
        if (!match && wantedId) {
            writeStoredCycleId(null); // drop stale/inaccessible stored ids
        }
    }

    handleCycleChange(event) {
        this.selectedCycleId = event.detail.cycleId;
        this.selectedCycleName = event.detail.cycleName;
        writeStoredCycleId(this.selectedCycleId);
    }

    get isDashboard() {
        return this.view === 'dashboard';
    }

    get isQueue() {
        return this.view === 'queue';
    }

    get isPool() {
        return this.view === 'pool';
    }

    get isRunner() {
        return this.view === 'runner';
    }

    get isExploratory() {
        return this.view === 'exploratory';
    }

    get isSession() {
        return this.view === 'session';
    }

    get showNav() {
        return this.isDashboard || this.isQueue || this.isPool;
    }

    /* The three nav views (Dashboard/Queue/Pool) and the Runner share the
     * fluid width and the gray card canvas so they read as one application
     * (the queue/pool redesign made them card-based like the Dashboard; the
     * runner joined when it went two-column — its root caps itself at
     * --uta-content-max-wide). Exploratory keeps the centered 1040px reading
     * column on white. */
    get isWideCanvas() {
        return this.showNav || this.isRunner || this.isSession;
    }

    get mainClass() {
        return 'uta-main' + (this.isWideCanvas ? ' uta-main--wide' : '');
    }

    get shellClass() {
        return 'uta-shell' + (this.isWideCanvas ? ' uta-shell--canvas' : '');
    }

    get dashboardNavClass() {
        return 'uta-band__tab' + (this.isDashboard ? ' uta-band__tab--active' : '');
    }

    get queueNavClass() {
        return 'uta-band__tab' + (this.isQueue ? ' uta-band__tab--active' : '');
    }

    get poolNavClass() {
        return 'uta-band__tab' + (this.isPool ? ' uta-band__tab--active' : '');
    }

    handleNavDashboard() {
        this.view = 'dashboard';
        this.refreshCycles();
    }

    handleNavQueue() {
        this.view = 'queue';
        this.refreshCycles();
    }

    handleNavPool() {
        this.view = 'pool';
        this.refreshCycles();
    }

    handleDashboardNavigate(event) {
        this.view = event.detail.view === 'pool' ? 'pool' : 'queue';
    }

    handleOpen(event) {
        this.activeExecutionId = event.detail.executionId;
        this.claimOnStart = Boolean(event.detail.claim);
        this.activeCaseIndex = event.detail.caseIndex || null;
        this.activeCaseTotal = event.detail.caseTotal || null;
        this.view = 'runner';
    }

    handleExploratory(event) {
        this.activeCycleId = event.detail.cycleId;
        this.activeCycleName = event.detail.cycleName;
        this.view = 'exploratory';
    }

    handleSessionOpen(event) {
        this.activeSessionId = event.detail.sessionId;
        this.view = 'session';
    }

    handleBackToQueue() {
        this.view = 'queue';
        this.activeExecutionId = null;
        this.claimOnStart = false;
        this.activeCaseIndex = null;
        this.activeCaseTotal = null;
        this.activeCycleId = null;
        this.activeCycleName = null;
        this.activeSessionId = null;
    }
}