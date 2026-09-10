import { LightningElement, api } from 'lwc';

/**
 * envelopeUnsavedChangesModal — confirmation dialog shown when a caller tries to leave an
 * interview (or Review Missing Items / Review & Submit) while a save is pending or in flight.
 * Presentational and stateless about persistence, like envelopeConfirmRemovalModal: it offers
 * three outcomes and lets the host decide what each one does.
 *
 *  - "Save & Exit" dispatches `confirm` with `{ choice: 'saveAndExit' }`. The host is expected to
 *    set `busy` while the save is in flight (disables the footer, shows a spinner) and, on
 *    failure, set `errorMessage` so the dialog stays open with the reason shown inline.
 *  - "Exit without saving" dispatches `confirm` with `{ choice: 'exitWithoutSaving' }`.
 *  - Cancel, the backdrop or Escape dispatch `close` (handled by dsModalV2 itself for the latter
 *    two, forwarded here the same way envelopeConfirmRemovalModal does).
 */
export default class EnvelopeUnsavedChangesModal extends LightningElement {
    @api title = 'Unsaved changes';
    @api messageBefore =
        "You have unsaved changes. If you leave now, they'll be lost unless you save first.";
    // 'medium' (not the confirm-modal default 'small') so the three footer buttons fit on one
    // line — small's 396px wrapped "Exit without saving"/"Save & Exit" onto a second line.
    @api size = 'medium';

    // When true, shows a spinner over "Save & Exit" and disables the whole footer so the dialog
    // stays put while the host persists the save.
    @api busy = false;

    // Set by the host when a Save & Exit attempt fails; shown inline so the user can retry or
    // choose to exit without saving instead. Cleared by the host on the next attempt/close.
    @api errorMessage = '';

    _isOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so a host can drive the dialog from JS via a DOM ref (e.g. lwc:ref)
    // instead of binding the is-open flag.
    @api
    open() {
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    handleClose(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleExitWithoutSaving() {
        this.dispatchEvent(
            new CustomEvent('confirm', { detail: { choice: 'exitWithoutSaving' } })
        );
    }

    handleSaveAndExit() {
        this.dispatchEvent(new CustomEvent('confirm', { detail: { choice: 'saveAndExit' } }));
    }
}