import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeKeyPointChangeModal — confirmation dialog shown before an already-answered Key Point
 * field (Key_Decision__c) is re-answered. A Key Point decides which questions appear below it, so
 * changing it rebuilds that branch of the interview and clears the answers it contained; this
 * dialog makes that consequence explicit before the change is applied.
 *
 * Presentational: it owns no state beyond open/closed and carries no props, since all of its copy
 * is fixed. It dispatches `confirm` and `close` and leaves the host to apply or discard the pending
 * change (see envelopeFieldControl).
 */
export default class EnvelopeKeyPointChangeModal extends LightningElement {
    _isOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so a host can drive the dialog from JS via a DOM ref (lwc:ref) instead
    // of binding the is-open flag.
    @api
    open() {
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
    }

    // The shell's own `close` (X, backdrop, Esc) is composed, so it is stopped here and re-emitted
    // as this component's event — the host listens to one dismissal path.
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