import { LightningElement, api } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import startSession from '@salesforce/apex/UatSessionController.startSession';
import deleteSession from '@salesforce/apex/UatSessionController.deleteSession';
import getMyCycles from '@salesforce/apex/UatRunController.getMyCycles';
import { messageFrom, toast } from 'c/messageUtil';
import { SESSION_STATUS_VARIANT } from 'c/uatConstants';
import { relativeTime, joinMeta } from 'c/uatCardUtil';

const PAGE_SIZE = 25;

// Combobox value for a cycle-less session — same literal uatQueue keys its
// standalone execution group with. Maps to cycleId: null in the payload.
const NO_CYCLE = 'standalone';

/**
 * uatSessionList — the Exploratory Sessions tab content inside uatQueue.
 * Presentational over the host's pre-scoped session list (uatQueue owns the
 * getExploratorySessions fetch so its tab counts exist before this mounts),
 * plus this component's two writes: the Start-Session modal and
 * delete-session (row kebab, owner's Active sessions only — admins delete
 * from the workspace, which knows viewerIsAdmin; the list DTO deliberately
 * doesn't). A delete emits `sessionschange` so the host refetches sessions
 * and tab counts together.
 *
 * One featured card for MY most recent Active session; status chips
 * (All/Active/Completed/Has findings/Mine); a dense row list below. Opening
 * anything emits `sessionopen` { sessionId } for uatQueue to re-dispatch;
 * the cycle findings-log link reuses the existing `exploratory` event.
 */
export default class UatSessionList extends LightningElement {
    @api sessions = [];      // SessionDTO[], already scoped to the cycle selection
    @api cycleId;            // null = all cycles
    @api cycleName;

    filterStatus = 'all';
    page = 1;

    startForm = null;        // {title, areaText, cycleId}
    starting = false;
    cycleOptions = [];

    deleteTarget = null;     // {sessionId, title}
    deleting = false;

    // ---- Decoration -------------------------------------------------------------

    get decorated() {
        return (this.sessions || []).map((s) => {
            const mine = s.testerId === USER_ID || s.isMine;
            return {
                ...s,
                key: s.sessionId,
                statusVariant: SESSION_STATUS_VARIANT[s.status] || 'default',
                cycleLabel: s.cycleName || 'Standalone',
                mine,
                canDelete: mine && s.status === 'Active',
                findingsLabel: `${s.findingsCount || 0} finding${s.findingsCount === 1 ? '' : 's'}`,
                filesLabel: s.filesCount ? `${s.filesCount} file${s.filesCount === 1 ? '' : 's'}` : null,
                updatedLabel: s.lastUpdated ? relativeTime(s.lastUpdated) : '—',
                openAria: `Open session ${s.title}`,
                menuAlt: `More actions for ${s.title}`
            };
        });
    }

    /** MY most recently started Active session — the one card that gets the
     *  polished treatment (server order is newest first already). */
    get featuredSession() {
        const s = this.decorated.find((x) => x.mine && x.status === 'Active');
        if (!s) {
            return null;
        }
        return {
            ...s,
            // The one optional line the tester gave at creation. Was the
            // charter; charters are no longer asked for.
            charterExcerpt: s.areaText,
            metaLine: joinMeta([
                s.startedAt ? `Started ${relativeTime(s.startedAt)}` : null,
                s.findingsLabel,
                s.filesLabel
            ])
        };
    }

    get chips() {
        const all = this.decorated;
        return [
            { value: 'all', label: 'All', count: all.length },
            { value: 'active', label: 'Active', count: all.filter((s) => s.status === 'Active').length },
            { value: 'completed', label: 'Completed', count: all.filter((s) => s.status === 'Completed').length },
            { value: 'findings', label: 'Has findings', count: all.filter((s) => s.findingsCount > 0).length },
            { value: 'mine', label: 'Mine', count: all.filter((s) => s.mine).length }
        ];
    }

    get filteredRows() {
        const all = this.decorated;
        if (this.filterStatus === 'active') {
            return all.filter((s) => s.status === 'Active');
        }
        if (this.filterStatus === 'completed') {
            return all.filter((s) => s.status === 'Completed');
        }
        if (this.filterStatus === 'findings') {
            return all.filter((s) => s.findingsCount > 0);
        }
        if (this.filterStatus === 'mine') {
            return all.filter((s) => s.mine);
        }
        return all;
    }

    /** The featured card leaves the list (the user's sketch), but only under
     *  the default chip — a filtered list shows everything it matches. */
    get listRows() {
        const featured = this.featuredSession;
        const rows = this.filteredRows;
        if (!featured || this.filterStatus !== 'all') {
            return rows;
        }
        return rows.filter((s) => s.key !== featured.key);
    }

    get pageSize() {
        return PAGE_SIZE;
    }

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

    get hasRows() {
        return this.pagedRows.length > 0;
    }

    get isEmpty() {
        return (this.sessions || []).length === 0;
    }

    get showLogLink() {
        return Boolean(this.cycleId);
    }

    // ---- Handlers -----------------------------------------------------------------

    handleChipSelect(event) {
        this.filterStatus = event.detail.value;
        this.page = 1;
    }

    handlePageChange(event) {
        this.page = event.detail.page;
    }

    handleOpen(event) {
        this.dispatchEvent(new CustomEvent('sessionopen', {
            detail: { sessionId: event.currentTarget.dataset.id }
        }));
    }

    handleLogOpen() {
        this.dispatchEvent(new CustomEvent('exploratory', {
            detail: { cycleId: this.cycleId, cycleName: this.cycleName }
        }));
    }

    handleMenuSelect(event) {
        const sessionId = event.currentTarget.dataset.id;
        const action = event.detail.value;
        if (action === 'open') {
            this.dispatchEvent(new CustomEvent('sessionopen', { detail: { sessionId } }));
        } else if (action === 'delete') {
            const row = this.decorated.find((s) => s.sessionId === sessionId);
            this.deleteTarget = {
                sessionId,
                title: row ? row.title : '',
                standalone: row ? !row.cycleId : false
            };
        }
    }

    // ---- Delete session -----------------------------------------------------------

    get deleteOpen() {
        return this.deleteTarget !== null;
    }

    /** A standalone session's findings only exist in its workspace — they die
     *  with it; a cycled session's findings survive into the cycle log. */
    get deleteMessage() {
        return this.deleteTarget && this.deleteTarget.standalone
            ? 'The session, its notes, and its findings are deleted — a standalone session has no cycle log to keep them.'
            : 'The session and its notes are deleted. Findings already logged are preserved in the cycle findings log.';
    }

    handleDeleteCancel() {
        this.deleteTarget = null;
    }

    async handleDeleteConfirm() {
        this.deleting = true;
        const standalone = this.deleteTarget.standalone;
        try {
            await deleteSession({ sessionId: this.deleteTarget.sessionId });
            this.deleteTarget = null;
            toast(this, 'success', standalone
                ? 'Session deleted, findings included.'
                : 'Session deleted — its findings stay in the cycle log.');
            // The host owns the data; it refetches sessions + tab counts.
            this.dispatchEvent(new CustomEvent('sessionschange'));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.deleting = false;
        }
    }

    // ---- Start-session modal ---------------------------------------------------------

    async handleStartOpen() {
        this.startForm = {
            title: '', areaText: '', cycleId: this.cycleId || ''
        };
        if (!this.cycleOptions.length) {
            try {
                const cycles = await getMyCycles();
                const realCycles = (cycles || []).map((c) => ({
                    label: c.cycleName, value: c.cycleId
                }));
                this.cycleOptions = [
                    ...realCycles,
                    { label: 'No cycle — standalone', value: NO_CYCLE }
                ];
                // Only one cycle in my audience — it picks itself (standalone
                // never auto-picks; going cycle-less stays an explicit choice).
                if (!this.startForm.cycleId && realCycles.length === 1) {
                    this.startForm = { ...this.startForm, cycleId: realCycles[0].value };
                }
            } catch (e) {
                toast(this, 'error', messageFrom(e));
            }
        }
    }

    get startOpen() {
        return this.startForm !== null;
    }

    handleStartField(event) {
        this.startForm = {
            ...this.startForm,
            [event.currentTarget.dataset.field]: event.target.value
        };
    }

    handleStartCycle(event) {
        this.startForm = { ...this.startForm, cycleId: event.detail.value };
    }

    handleStartCancel() {
        this.startForm = null;
    }

    async handleStartConfirm() {
        const f = this.startForm;
        if (!f.title.trim()) {
            toast(this, 'error', 'Give the session a title.');
            return;
        }
        if (!f.cycleId) {
            toast(this, 'error', 'Pick a test cycle — or "No cycle" for a standalone session.');
            return;
        }
        this.starting = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const sessionId = await startSession({ inputJson: JSON.stringify({
                title: f.title,
                areaText: f.areaText,
                cycleId: f.cycleId === NO_CYCLE ? null : f.cycleId
            }) });
            this.startForm = null;
            toast(this, 'success', 'Session started.');
            this.dispatchEvent(new CustomEvent('sessionopen', { detail: { sessionId } }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.starting = false;
        }
    }
}