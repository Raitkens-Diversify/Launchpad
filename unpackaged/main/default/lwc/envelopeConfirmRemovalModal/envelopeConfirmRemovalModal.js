import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeConfirmRemovalModal — presentational confirmation dialog for destructive
 * "remove/delete" actions (icon + title + message + Cancel/destructive footer). Owns no
 * persistence: it dispatches `confirm` and `close` and lets the host do the work and
 * surface any feedback. The message is supplied as before/highlight/after parts so the
 * emphasized name can sit mid-sentence while this component keeps the markup and styling.
 *
 * This is the shared shell for all removal/delete confirmations. Choose one of two ways
 * to use it — never both:
 *  - Action that hits Apex (e.g. deleting an envelope): use a behavior wrapper that
 *    composes this shell and owns the server call/toast — see envelopeDeleteModalV2.
 *    Callers embed only that wrapper.
 *  - One-off confirmation where the host owns what happens on confirm (no shared Apex):
 *    drop this component in directly and handle its `confirm` event — e.g. the
 *    Remove-action flow in envelopeShellV2, which removes from local state.
 */
export default class EnvelopeConfirmRemovalModal extends LightningElement {
    @api title = '';
    @api confirmLabel = '';
    @api confirmIconName = 'utility:delete';
    @api size = 'small';

    @api messageBefore = '';
    @api messageHighlight = '';
    @api messageAfter = '';

    // When true, shows a spinner over the confirm button and disables the footer so the
    // dialog stays put while the host persists the action.
    @api busy = false;

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

    get hasHighlight() {
        return !!this.messageHighlight;
    }

    handleClose(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleConfirm() {
        this.dispatchEvent(new CustomEvent('confirm'));
    }
}