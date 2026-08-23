import { LightningElement, api } from 'lwc';

/**
 * uatFindingDetail — one finding, rendered the way its tester sees it.
 *
 * Extracted verbatim from uatSessionWorkspace's finding body (2026-08-12), when
 * the Cycle Report needed to open a finding an admin could previously only read
 * as a table row. "The admin sees what the tester sees" has to hold by
 * construction; two templates kept in step by hand is how that promise breaks
 * the first time a field is added.
 *
 * Presentational only. It renders a view model from
 * c/uatConstants.findingViewModel and emits `edit` / `delete` for the host to
 * act on, so the write paths stay in the components that own them —
 * UatRunController.saveFinding / deleteFinding, owner-or-admin on the server.
 *
 * The disclosure deliberately stays OUTSIDE: the session workspace keeps its
 * own details/summary, the report opens the finding already expanded in a
 * modal. A host with no summary of its own sets show-header to get the badges,
 * headline and meta line that summary would have carried.
 */
export default class UatFindingDetail extends LightningElement {
    @api finding;

    /** Badges + headline + meta — for a host with no summary line of its own. */
    @api showHeader = false;

    /** Edit + Delete. Visibility only; the server is still the authority. */
    @api showActions = false;

    /** Disables the actions while the host has a write in flight. */
    @api busy = false;

    /** Evidence read-only: keeps the thumbnails and download links, drops
     *  upload and remove. */
    @api viewOnlyEvidence = false;

    /** Renders the "Change" affordance next to the workflow status and emits
     *  `statusedit` for the host to act on. The status LINE shows regardless —
     *  testers read the triage state, only admins (the report) change it, and
     *  the write stays in the host (UatReportController.setFindingWorkflowStatus). */
    @api allowStatusEdit = false;

    /** Never reach through `finding` in the template: an unset @api would make
     *  every expression a TypeError during the host's first render. */
    get row() {
        return this.finding || {};
    }

    handleEdit() {
        this.dispatchEvent(new CustomEvent('edit', { detail: { id: this.row.id } }));
    }

    handleDelete() {
        this.dispatchEvent(new CustomEvent('delete', { detail: { id: this.row.id } }));
    }

    handleStatusEdit() {
        this.dispatchEvent(new CustomEvent('statusedit', { detail: { findingId: this.row.id } }));
    }
}