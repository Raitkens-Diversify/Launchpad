import { LightningElement, api, track } from 'lwc';
import LightningToast from 'lightning/toast';
import deleteWizEnvelope from '@salesforce/apex/EnvelopeLandingApex.deleteWizEnvelope';

/**
 * envelopeDeleteModalV2 — delete-envelope behavior wrapper. It composes the shared
 * presentational shell (envelopeConfirmRemovalModal) and adds the only things specific to
 * deleting an envelope: the `deleteWizEnvelope` Apex call, the success/error toast, the
 * busy spinner, and the `deleted` event. Keeping that here means the persistence lives in
 * one place for both callers (envelopeListV2 row delete + envelopeShellV2 header delete).
 *
 * Callers embed ONLY this component for envelope deletion — they do not also place the
 * shell; the shell is rendered internally. For a confirmation where the host owns the
 * action (no shared Apex), use envelopeConfirmRemovalModal directly instead.
 */
export default class EnvelopeDeleteModalV2 extends LightningElement {
    @api envelopeId;
    @api envelopeName = '';

    // True while the delete is running — drives the spinner over the Delete button and
    // disables the footer so the dialog stays put until the action resolves.
    @track isDeleting = false;

    _isOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so a host can drive the dialog from JS via a DOM ref
    // (e.g. lwc:ref) instead of binding the is-open flag.
    @api
    open() {
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
    }

    // Forward the shared dialog's close (Cancel / X / backdrop / Esc) to the host.
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Persist the delete here so this dialog is self-contained. Keep the dialog open while
    // deleting; on success let the host refresh and close via the `deleted` event, on error
    // surface a toast and stay open to retry.
    async handleDelete() {
        const name = this.envelopeName;
        this.isDeleting = true;
        try {
            await deleteWizEnvelope({ wizardEnvelopeId: this.envelopeId });
            this.showToast('Envelope deleted', 'The envelope has been permanently deleted.', 'success');
            this.dispatchEvent(
                new CustomEvent('deleted', {
                    detail: { id: this.envelopeId, name }
                })
            );
        } catch (error) {
            console.error('Failed to delete envelope', error);
            const message = error?.body?.message || error?.message || 'Unable to delete envelope.';
            this.showToast('Delete failed', message, 'error');
        } finally {
            this.isDeleting = false;
        }
    }

    showToast(title, message, variant) {
        LightningToast.show({ label: title, message, variant }, this);
    }
}