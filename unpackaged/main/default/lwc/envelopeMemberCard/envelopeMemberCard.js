import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeMemberCard — a compact card for a selected member (e.g. an Account Owner in Review
 * Missing Items): the member name with an optional "New" badge and a missing-inputs hint, plus an
 * overflow menu whose Remove action bubbles `ownerremove`. Driven entirely by its `member` prop.
 */
export default class EnvelopeMemberCard extends LightningElement {
    @api member;

    get hasBadge() {
        return Boolean(this.member?.isNew);
    }

    get hasMissing() {
        return Boolean(this.member?.missingLabel);
    }

    handleMenuSelect() {
        this.dispatchEvent(
            new CustomEvent('ownerremove', { detail: { id: this.member?.id } })
        );
    }
}