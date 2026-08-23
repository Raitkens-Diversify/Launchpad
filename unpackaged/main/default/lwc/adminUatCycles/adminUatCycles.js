import { LightningElement, api } from 'lwc';
import getCycles from '@salesforce/apex/UatCycleAdminController.getCycles';
import getCycleDetail from '@salesforce/apex/UatCycleAdminController.getCycleDetail';
import saveCycle from '@salesforce/apex/UatCycleAdminController.saveCycle';
import attachBook from '@salesforce/apex/UatCycleAdminController.attachBook';
import detachBook from '@salesforce/apex/UatCycleAdminController.detachBook';
import addDirectCase from '@salesforce/apex/UatCycleAdminController.addDirectCase';
import removeDirectCase from '@salesforce/apex/UatCycleAdminController.removeDirectCase';
import addTesterExecution from '@salesforce/apex/UatCycleAdminController.addTesterExecution';
import setCycleStatus from '@salesforce/apex/UatCycleAdminController.setCycleStatus';
import cloneCycle from '@salesforce/apex/UatCycleAdminController.cloneCycle';
import getCycleDeleteImpact from '@salesforce/apex/UatCycleAdminController.getCycleDeleteImpact';
import deleteCycle from '@salesforce/apex/UatCycleAdminController.deleteCycle';
import forceUnassign from '@salesforce/apex/UatCycleAdminController.forceUnassign';
import reassignTester from '@salesforce/apex/UatCycleAdminController.reassignTester';
import { messageFrom, toast } from 'c/messageUtil';
import { humanizeCaseCode } from 'c/uatTitleUtil';

/**
 * adminUatCycles — the UAT Test Cycles section of the Admin Console (the
 * default UAT landing section). List: name, attached book names (comma list
 * + a chip when direct cases exist too), team, target date, progress
 * "X / Y complete" where Y counts EXECUTIONS, and the exploratory findings
 * count. Editor: fields + Save (team changes touch only unclaimed slots —
 * the trigger's job), the books picker, the direct-cases picker, and the
 * All Cases & Executions table: every case in effective scope tagged with
 * where it came from, every execution as a chip (click -> case detail with
 * the cycle breadcrumb), and "+ Add tester" creating an ADDITIONAL, fully
 * independent execution.
 */
export default class AdminUatCycles extends LightningElement {
    view = 'list'; // list | editor
    cycleId = null;

    rows = [];
    detail;
    loading = true;
    saving = false;
    errorMessage;

    name = '';
    targetDate = null;
    teamId = '';
    maxTesters = '1';     // seats per case (cycle default)
    claimLimit = '';      // per-tester open-claim cap ('' = unlimited)
    staleDays = '7';      // days before auto-release ('' = never)
    focusPrompts = '';    // per-cycle notes chips ('' = inherit org defaults)
    confirm = null;
    addTesterByCase = {}; // caseId -> picked userId (per-row dropdown state)
    reassign = null;      // { executionId, testerName, caseId, newTesterId, reason }
    showClosed = false;   // list filter: closed cycles hidden by default

    /** Container-driven deep link (uatnavigate from Books / Run this book). */
    @api
    get openCycleId() {
        return this.cycleId;
    }
    set openCycleId(value) {
        if (value) {
            this.cycleId = value;
            this.view = 'editor';
            this.loadDetail();
        }
    }

    connectedCallback() {
        if (this.view === 'list') {
            this.loadList();
        }
    }

    async loadList() {
        this.loading = true;
        try {
            this.rows = await getCycles();
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async loadDetail() {
        this.loading = true;
        try {
            this.detail = await getCycleDetail({ cycleId: this.cycleId });
            this.name = this.detail.name;
            this.targetDate = this.detail.targetDate;
            this.teamId = this.detail.teamId || '';
            this.maxTesters = String(this.detail.maxTesters || 1);
            this.claimLimit = this.detail.claimLimitPerTester == null
                ? '' : String(this.detail.claimLimitPerTester);
            this.staleDays = this.detail.staleClaimDays == null
                ? '' : String(this.detail.staleClaimDays);
            this.focusPrompts = this.detail.focusPrompts || '';
            this.addTesterByCase = {};
            this.reassign = null;
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- View machine -------------------------------------------------------------

    get isList() {
        return this.view === 'list';
    }

    get isEditor() {
        return this.view === 'editor';
    }

    get busy() {
        return this.loading || this.saving;
    }

    get listRows() {
        return this.rows
            .filter((r) => this.showClosed || r.status !== 'Closed')
            .map((r) => ({
                ...r,
                booksDisplay: r.bookNames || '—',
                teamDisplay: r.teamName || 'Unassigned',
                progress: `${r.completeCount} / ${r.totalExecutions} complete`,
                findingsLabel: `Exploratory findings (${r.findingsCount})`,
                statusClass: r.status === 'Closed'
                    ? 'aucy__status aucy__status--closed' : 'aucy__status'
            }));
    }

    get hasRows() {
        return this.listRows.length > 0;
    }

    get closedCount() {
        return this.rows.filter((r) => r.status === 'Closed').length;
    }

    get showClosedLabel() {
        return `Show closed (${this.closedCount})`;
    }

    get hasClosedRows() {
        return this.closedCount > 0;
    }

    handleShowClosedToggle(event) {
        this.showClosed = event.target.checked;
    }

    handleNewCycle() {
        this.cycleId = null;
        this.detail = {
            teamOptions: [], teamMembers: [], attachedBooks: [],
            availableBooks: [], directCases: [], availableCases: [], scopeRows: []
        };
        this.name = '';
        this.targetDate = null;
        this.teamId = '';
        this.maxTesters = '1';
        this.claimLimit = '';
        this.staleDays = '7';
        this.view = 'editor';
        this.loading = false;
    }

    handleEdit(event) {
        this.cycleId = event.currentTarget.dataset.id;
        this.view = 'editor';
        this.loadDetail();
    }

    /** "Same scope, next sprint" — copies team + books + direct cases; fresh
     *  unclaimed slots materialize via the junction triggers. */
    async handleClone(event) {
        const sourceId = event.currentTarget.dataset.id;
        this.saving = true;
        try {
            const newId = await cloneCycle({ cycleId: sourceId });
            toast(this, 'success', 'Cycle cloned with the same scope and team — set a target date.');
            this.cycleId = newId;
            this.view = 'editor';
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleBack() {
        this.view = 'list';
        this.cycleId = null;
        this.detail = undefined;
        this.loadList();
    }

    // ---- Editor: fields --------------------------------------------------------------

    get editorTitle() {
        return this.cycleId ? 'Edit cycle' : 'New cycle';
    }

    get isExistingCycle() {
        return this.cycleId !== null;
    }

    get isClosed() {
        return Boolean(this.detail && this.detail.status === 'Closed');
    }

    get isPaused() {
        return Boolean(this.detail && this.detail.status === 'Claims Paused');
    }

    get isOpenExistingCycle() {
        return this.isExistingCycle && !this.isClosed;
    }

    get isActiveExistingCycle() {
        return this.isOpenExistingCycle && !this.isPaused;
    }

    /** Pause/resume claims — reversible and non-destructive, so no confirm. */
    async handlePauseClaims() {
        await this.changeStatus('Claims Paused',
            'Claims paused — in-flight work continues; the pool stops offering seats.');
    }

    async handleResumeClaims() {
        await this.changeStatus('Active', 'Claims resumed — open seats are back in the pool.');
    }

    async changeStatus(status, message) {
        this.saving = true;
        try {
            await setCycleStatus({ cycleId: this.cycleId, status });
            toast(this, 'success', message);
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleCloseCycle() {
        this.confirm = {
            action: 'closeCycle',
            header: 'Close cycle: ' + this.name,
            message: 'Testers stop seeing this cycle\'s work in their queues. Nothing is '
                + 'deleted — results, evidence, and findings stay put, and you can reopen '
                + 'the cycle at any time.',
            confirmLabel: 'Close cycle'
        };
    }

    /** Destructive alternative to Close: honest numbers fetched at click
     *  time, escalated wording when claimed work would die. */
    async handleDeleteCycle() {
        this.saving = true;
        try {
            const impact = await getCycleDeleteImpact({ cycleId: this.cycleId });
            const parts = [];
            if (impact.claimedRuns > 0) {
                parts.push(`Testers have claimed work in this cycle — they will lose it. `);
            }
            parts.push(`Permanently deletes this cycle and its entire run history: `
                + `${impact.executions} run${impact.executions === 1 ? '' : 's'}`
                + (impact.claimedRuns > 0 ? ` (${impact.claimedRuns} claimed)` : '')
                + `, ${impact.stepResults} step result${impact.stepResults === 1 ? '' : 's'}`
                + `, ${impact.sessions} exploratory session${impact.sessions === 1 ? '' : 's'}`
                + `, and ${impact.findings} finding${impact.findings === 1 ? '' : 's'}. `);
            parts.push('Book and case definitions are kept. The assignment audit log keeps '
                + 'its rows. Evidence files stay in their uploaders\' Files. This cannot be '
                + 'undone — if you just want it out of the way, Close it instead.');
            this.confirm = {
                action: 'deleteCycle',
                header: 'Delete cycle: ' + this.name,
                message: parts.join(''),
                confirmLabel: 'Delete cycle'
            };
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleReopenCycle() {
        this.saving = true;
        try {
            await setCycleStatus({ cycleId: this.cycleId, status: 'Active' });
            toast(this, 'success', 'Cycle reopened — its work is back in tester queues.');
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    get teamOptions() {
        const base = this.detail ? this.detail.teamOptions.map((t) => ({ label: t.label, value: t.value })) : [];
        return [{ label: 'Unassigned', value: '' }].concat(base);
    }

    handleNameChange(event) {
        this.name = event.target.value;
    }

    handleDateChange(event) {
        this.targetDate = event.target.value;
    }

    handleTeamChange(event) {
        this.teamId = event.detail.value;
    }

    handleMaxTestersChange(event) {
        this.maxTesters = event.target.value;
    }

    handleClaimLimitChange(event) {
        this.claimLimit = event.target.value;
    }

    /** Shown greyed in the field so an admin can see the expected shape
     *  without having to open the help bubble. */
    get promptsPlaceholder() {
        return ['Observation', 'Steps | Steps to reproduce:', 'Question'].join('\n');
    }

    handleFocusPromptsChange(event) {
        this.focusPrompts = event.target.value;
    }

    handleStaleDaysChange(event) {
        this.staleDays = event.target.value;
    }

    async handleSave() {
        if (!this.name || !this.name.trim()) {
            toast(this, 'error', 'Cycle name is required.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const savedId = await saveCycle({
                inputJson: JSON.stringify({
                    id: this.cycleId,
                    name: this.name,
                    targetDate: this.targetDate || null,
                    teamId: this.teamId || null,
                    maxTesters: this.maxTesters ? parseInt(this.maxTesters, 10) : null,
                    claimLimitPerTester: this.claimLimit ? parseInt(this.claimLimit, 10) : null,
                    staleClaimDays: this.staleDays ? parseInt(this.staleDays, 10) : null,
                    focusPrompts: this.focusPrompts
                })
            });
            const isNew = !this.cycleId;
            this.cycleId = savedId;
            toast(this, 'success', 'Cycle saved. Team changes affect unclaimed runs only.');
            if (isNew) {
                await this.loadDetail();
            } else {
                await this.loadDetail(); // team member options / chips may shift
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Pickers ------------------------------------------------------------------------

    get booksSelected() {
        return this.detail
            ? this.detail.attachedBooks.map((b) => ({ id: b.junctionId, label: b.label }))
            : [];
    }

    get booksAvailable() {
        return this.detail
            ? this.detail.availableBooks.map((b) => ({ id: b.targetId, label: b.label, sublabel: b.sublabel }))
            : [];
    }

    // Title leads; the Case ID (server `label`) demotes to the sublabel,
    // which the picker's search still covers (it matches label + sublabel).
    get casesSelected() {
        return this.detail
            ? this.detail.directCases.map((c) => ({
                id: c.junctionId,
                label: c.title || humanizeCaseCode(c.label),
                sublabel: `${c.label} · ${c.sublabel}`
            }))
            : [];
    }

    get casesAvailable() {
        return this.detail
            ? this.detail.availableCases.map((c) => ({
                id: c.targetId,
                label: c.title || humanizeCaseCode(c.label),
                sublabel: `${c.label} · ${c.sublabel}`,
                systemId: c.systemId
            }))
            : [];
    }

    async handleBookAdd(event) {
        this.saving = true;
        try {
            await attachBook({ cycleId: this.cycleId, bookId: event.detail.id });
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleBookRemove(event) {
        this.confirm = {
            action: 'detachBook',
            id: event.detail.id,
            header: 'Remove book: ' + event.detail.label,
            message: 'This cycle stops showing the book\'s cases going forward. Execution '
                + 'history that already exists is NOT deleted; empty unclaimed slots are cleaned up.',
            confirmLabel: 'Remove book'
        };
    }

    async handleCaseAdd(event) {
        this.saving = true;
        try {
            await addDirectCase({ cycleId: this.cycleId, caseId: event.detail.id });
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleCaseRemove(event) {
        this.confirm = {
            action: 'removeDirectCase',
            id: event.detail.id,
            header: 'Remove case: ' + event.detail.label,
            message: 'This cycle stops showing the case going forward (unless a book still '
                + 'brings it in). Execution history that already exists is NOT deleted.',
            confirmLabel: 'Remove case'
        };
    }

    // ---- All Cases & Executions -------------------------------------------------------------

    get scopeRows() {
        if (!this.detail) {
            return [];
        }
        return this.detail.scopeRows.map((row) => {
            const assignedIds = new Set(row.executions.map((e) => e.testerId).filter(Boolean));
            const options = this.detail.teamMembers
                .filter((m) => !assignedIds.has(m.value))
                .map((m) => ({ label: m.label, value: m.value }));
            return {
                ...row,
                titleDisplay: row.title || humanizeCaseCode(row.caseCode),
                chips: row.executions.map((e) => ({
                    ...e,
                    label: (e.testerName || 'Unclaimed')
                        + (e.released ? ' · Released' : (e.status ? ' · ' + e.status : '')),
                    chipClass: 'aucy__chip' + (e.released ? ' aucy__chip--released'
                        : e.result === 'Failed' ? ' aucy__chip--failed'
                        : e.result === 'Passed' ? ' aucy__chip--passed'
                        : e.result === 'Blocked' ? ' aucy__chip--blocked' : ''),
                    // Only a live claim has a seat to take away.
                    canUnassign: Boolean(e.testerId) && !e.released
                })),
                addTesterOptions: options,
                addTesterValue: this.addTesterByCase[row.caseId] || '',
                // Button appears only once a tester is picked — a permanently
                // greyed control reads as broken.
                hasAddTesterPick: Boolean(this.addTesterByCase[row.caseId]),
                isReassignRow: Boolean(this.reassign && this.reassign.caseId === row.caseId)
            };
        });
    }

    // ---- Force unassign / reassign (open-pool design §3.2) -----------------------

    handleUnassignClick(event) {
        event.stopPropagation();
        const ds = event.currentTarget.dataset;
        this.confirm = {
            action: 'forceUnassign',
            executionId: ds.execid,
            header: 'Unassign: ' + ds.tester,
            message: 'The seat goes back to the pool. Anything the tester already recorded '
                + 'is kept and resumes if they claim this case again.',
            confirmLabel: 'Unassign',
            promptLabel: 'Why are you unassigning them?',
            promptRequired: true
        };
    }

    handleReassignClick(event) {
        event.stopPropagation();
        const ds = event.currentTarget.dataset;
        this.reassign = {
            executionId: ds.execid,
            testerName: ds.tester,
            caseId: ds.caseid,
            newTesterId: '',
            reason: ''
        };
    }

    get reassignTitle() {
        return this.reassign ? `Reassign ${this.reassign.testerName}'s run to:` : '';
    }

    get reassignDisabled() {
        return this.busy || !this.reassign
            || !this.reassign.newTesterId || !this.reassign.reason.trim();
    }

    handleReassignPick(event) {
        this.reassign = { ...this.reassign, newTesterId: event.detail.value };
    }

    handleReassignReason(event) {
        this.reassign = { ...this.reassign, reason: event.target.value };
    }

    handleReassignCancel() {
        this.reassign = null;
    }

    async handleReassignConfirm() {
        this.saving = true;
        try {
            await reassignTester({
                inputJson: JSON.stringify({
                    executionId: this.reassign.executionId,
                    newTesterId: this.reassign.newTesterId,
                    reason: this.reassign.reason
                })
            });
            this.reassign = null;
            toast(this, 'success', 'Reassigned — the new tester gets their own independent run.');
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    get hasScopeRows() {
        return this.detail && this.detail.scopeRows.length > 0;
    }

    get hasTeamMembers() {
        return this.detail && this.detail.teamMembers.length > 0;
    }

    handleChipClick(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('uatnavigate', {
            detail: {
                section: 'uatCases',
                view: 'detail',
                recordId: ds.caseid,
                context: {
                    executionId: ds.execid,
                    cycleId: this.cycleId,
                    cycleName: this.name
                }
            }
        }));
    }

    handleAddTesterPick(event) {
        const caseId = event.currentTarget.dataset.caseid;
        this.addTesterByCase = { ...this.addTesterByCase, [caseId]: event.detail.value };
    }

    async handleAddTester(event) {
        const caseId = event.currentTarget.dataset.caseid;
        const userId = this.addTesterByCase[caseId];
        if (!userId) {
            return;
        }
        this.saving = true;
        try {
            await addTesterExecution({ cycleId: this.cycleId, caseId, userId });
            toast(this, 'success', 'Independent run added for that tester.');
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Confirm modal ---------------------------------------------------------------------

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed(event) {
        const c = this.confirm;
        this.saving = true;
        try {
            let message = 'Removed.';
            if (c.action === 'detachBook') {
                await detachBook({ junctionId: c.id });
            } else if (c.action === 'removeDirectCase') {
                await removeDirectCase({ junctionId: c.id });
            } else if (c.action === 'closeCycle') {
                await setCycleStatus({ cycleId: this.cycleId, status: 'Closed' });
                message = 'Cycle closed — testers no longer see it in their queues.';
            } else if (c.action === 'forceUnassign') {
                await forceUnassign({
                    inputJson: JSON.stringify({
                        executionId: c.executionId,
                        reason: event.detail && event.detail.comment
                    })
                });
                message = 'Unassigned — the seat is back in the pool.';
            } else if (c.action === 'deleteCycle') {
                await deleteCycle({ cycleId: this.cycleId });
                this.confirm = null;
                toast(this, 'success', 'Cycle deleted — its run history was purged.');
                this.handleBack(); // the record is gone; the editor has nothing to reload
                return;
            }
            this.confirm = null;
            toast(this, 'success', message);
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Internals ------------------------------------------------------------------------------

}