import { LightningElement } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeAddCta — the "Add member" / "Add ISA" action row shown at the top of the
 * envelope content area. Presentational for now; clicks dispatch an `addaction`
 * event for the host to wire up in a later slice.
 */
export default class EnvelopeAddCta extends LightningElement {
    handleClick(event) {
        const action = event.currentTarget.dataset.action;
        this.dispatchEvent(new CustomEvent('addaction', { detail: { action } }));
    }
}