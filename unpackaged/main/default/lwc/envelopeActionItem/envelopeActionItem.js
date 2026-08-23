import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeActionItem — an Action Item group for a single household member / ISA: a header
 * (name, type, "New" badge) above one or more action cards. Presentational; re-dispatches
 * its cards' `cardmenu` / `openitem` events so the host can listen once per group.
 */
export default class EnvelopeActionItem extends LightningElement {
    @api entity;

    // "New" until the underlying record is submitted — same rule as the outline row: `isNew`
    // mirrors !Submitted__c, so the badge clears once the record is submitted.
    //
    // Account Action Items are excluded: the badge marks a household record that is new to the
    // envelope, and an action item is not one — it is work raised against an account that already
    // exists, so its header names that (submitted) account and must not claim it is new. Their
    // `isNew` still has to stay true, because the workspace list renders only entities carrying it.
    get showNewBadge() {
        return !!this.entity?.isNew && this.entity?.groupId !== 'cases';
    }

    handleCardMenu(event) {
        this.dispatchEvent(new CustomEvent('cardmenu', { detail: event.detail }));
    }

    handleOpenItem(event) {
        this.dispatchEvent(new CustomEvent('openitem', { detail: event.detail }));
    }
}