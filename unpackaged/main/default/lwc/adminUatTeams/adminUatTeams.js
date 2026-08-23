import { LightningElement } from 'lwc';
import getTeams from '@salesforce/apex/UatTeamAdminController.getTeams';
import getTesterPool from '@salesforce/apex/UatTeamAdminController.getTesterPool';
import saveTeam from '@salesforce/apex/UatTeamAdminController.saveTeam';
import searchUsers from '@salesforce/apex/UatTeamAdminController.searchUsers';
import addUserToPool from '@salesforce/apex/UatTeamAdminController.addUserToPool';
import getTeamDeleteImpact from '@salesforce/apex/UatTeamAdminController.getTeamDeleteImpact';
import deleteTeam from '@salesforce/apex/UatTeamAdminController.deleteTeam';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminUatTeams — the UAT Teams section of the Admin Console: team list
 * (name, member chips, Manage, Delete) plus a create/edit modal with a
 * tester-pool checklist and an inline "add a new tester" search. Adding a
 * tester assigns the UAT_Tester permission set to an existing internal user —
 * it cannot create Users (licensing), and the UI copy says so.
 *
 * Team delete (2026-08-05): blocked while any open cycle is assigned to the
 * team (a deleted team's cycles would open to EVERY tester — null team =
 * whole pool); otherwise a destructive confirm that states the
 * closed-cycle-reopen hazard.
 */
const SEARCH_DEBOUNCE_MS = 250;

export default class AdminUatTeams extends LightningElement {
    teams = [];
    pool = [];
    loading = true;
    errorMessage;

    // Modal state: null when closed, else { id, name, checkedUserIds:Set }
    modal = null;
    saving = false;

    // Delete confirm: null when closed, else { action, header, message, ... }
    confirm = null;

    // Inline add-tester search state
    searchTerm = '';
    searchResults = [];
    searching = false;
    _searchTimer;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [teams, pool] = await Promise.all([getTeams(), getTesterPool()]);
            this.teams = teams;
            this.pool = pool;
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- Derived state ----------------------------------------------------------

    get busy() {
        return this.loading || this.saving;
    }

    get teamRows() {
        return this.teams.map((t) => ({
            ...t,
            memberCount: t.members.length,
            chips: t.members.map((m) => ({ key: m.memberId, label: m.userName }))
        }));
    }

    get hasTeams() {
        return this.teamRows.length > 0;
    }

    get modalOpen() {
        return this.modal !== null;
    }

    get modalTitle() {
        return this.modal && this.modal.id ? 'Manage team' : 'New team';
    }

    /** Pool checklist plus any current members who left the pool (still shown). */
    get checklistRows() {
        if (!this.modal) {
            return [];
        }
        const rows = this.pool.map((p) => ({ userId: p.value, label: p.label }));
        const inPool = new Set(rows.map((r) => r.userId));
        const team = this.teams.find((t) => t.id === this.modal.id);
        if (team) {
            for (const m of team.members) {
                if (!inPool.has(m.userId)) {
                    rows.push({ userId: m.userId, label: m.userName + ' (no longer a tester)' });
                }
            }
        }
        return rows.map((r) => ({
            ...r,
            checked: this.modal.checkedUserIds.has(r.userId)
        }));
    }

    get hasChecklist() {
        return this.checklistRows.length > 0;
    }

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    // ---- List actions -------------------------------------------------------------

    handleNewTeam() {
        this.modal = { id: null, name: '', checkedUserIds: new Set() };
        this.resetSearch();
    }

    handleManage(event) {
        const team = this.teams.find((t) => t.id === event.currentTarget.dataset.id);
        this.modal = {
            id: team.id,
            name: team.name,
            checkedUserIds: new Set(team.members.map((m) => m.userId))
        };
        this.resetSearch();
    }

    // ---- Delete team ------------------------------------------------------------

    get confirmOpen() {
        return this.confirm !== null && this.confirm !== undefined;
    }

    async handleDeleteTeam(event) {
        const teamId = event.currentTarget.dataset.id;
        this.saving = true;
        try {
            const impact = await getTeamDeleteImpact({ teamId });
            if (impact.openCycleNames.length) {
                const plural = impact.openCycleNames.length > 1;
                this.confirm = {
                    action: 'blocked',
                    variant: 'brand',
                    header: `Can't delete: ${impact.teamName}`,
                    message: `Cycle${plural ? 's' : ''} ${impact.openCycleNames.join(', ')} `
                        + `${plural ? 'are' : 'is'} assigned to this team. Reassign or close `
                        + 'those cycles first; deleting this team would open their work to '
                        + 'every tester.',
                    confirmLabel: 'OK'
                };
            } else {
                const closedNote = impact.closedCycleCount > 0
                    ? ` ${impact.closedCycleCount} closed cycle${impact.closedCycleCount === 1 ? ' keeps' : 's keep'} `
                        + 'their history with the team reference cleared — if you reopen one '
                        + 'later, its unclaimed work becomes visible to every tester until '
                        + 'you assign a team.'
                    : '';
                this.confirm = {
                    action: 'deleteTeam',
                    teamId,
                    header: 'Delete team: ' + impact.teamName,
                    message: `Deletes the team and its ${impact.memberCount} member `
                        + `link${impact.memberCount === 1 ? '' : 's'}. Members keep their `
                        + `tester access.${closedNote}`,
                    confirmLabel: 'Delete team'
                };
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        if (this.confirm.action === 'blocked') {
            this.confirm = null;
            return;
        }
        this.saving = true;
        try {
            await deleteTeam({ teamId: this.confirm.teamId });
            this.confirm = null;
            toast(this, 'success', 'Team deleted — its members keep their tester access.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Modal form -----------------------------------------------------------------

    handleNameChange(event) {
        this.modal = { ...this.modal, name: event.target.value };
    }

    handleMemberToggle(event) {
        const userId = event.target.dataset.id;
        const next = new Set(this.modal.checkedUserIds);
        if (event.target.checked) {
            next.add(userId);
        } else {
            next.delete(userId);
        }
        this.modal = { ...this.modal, checkedUserIds: next };
    }

    handleModalCancel() {
        this.modal = null;
    }

    async handleModalSave() {
        const m = this.modal;
        if (!m || !m.name || !m.name.trim()) {
            toast(this, 'error', 'Team name is required.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            await saveTeam({
                inputJson: JSON.stringify({
                    id: m.id,
                    name: m.name,
                    memberUserIds: [...m.checkedUserIds]
                })
            });
            this.modal = null;
            toast(this, 'success', 'Team saved.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Inline add-a-new-tester ------------------------------------------------------

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        window.clearTimeout(this._searchTimer);
        const value = this.searchTerm;
        this._searchTimer = window.setTimeout(() => this.runSearch(value), SEARCH_DEBOUNCE_MS);
    }

    async runSearch(value) {
        if (!value || value.trim().length < 2) {
            this.searchResults = [];
            return;
        }
        this.searching = true;
        try {
            this.searchResults = await searchUsers({ term: value });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.searching = false;
        }
    }

    async handleAddTester(event) {
        const userId = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;
        this.saving = true;
        try {
            await addUserToPool({ userId });
            // New tester joins the pool and starts checked on this team.
            this.pool = [...this.pool, { value: userId, label }].sort((a, b) =>
                a.label.localeCompare(b.label)
            );
            const next = new Set(this.modal.checkedUserIds);
            next.add(userId);
            this.modal = { ...this.modal, checkedUserIds: next };
            this.searchResults = this.searchResults.filter((r) => r.value !== userId);
            toast(this, 'success', label + ' is now a tester.');
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    resetSearch() {
        this.searchTerm = '';
        this.searchResults = [];
    }

    // ---- Internals --------------------------------------------------------------------

}