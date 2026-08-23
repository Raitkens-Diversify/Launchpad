import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeActionCard — one action row inside an Action Item group: leading icon, action
 * title, status badge, a missing-inputs hint, and the overflow / open controls. Driven
 * entirely by its `action` prop; emits `cardmenu` / `openitem` for the host to handle.
 */
export default class EnvelopeActionCard extends LightningElement {
    @api action;

    // Member/ISA use the same icons as the sidebar outline row, so a card matches its
    // entity: the person icon for members, the document icon for accounts/ISAs.
    get iconName() {
        return this.action?.iconVariant === 'isa' ? 'utility:page' : 'utility:user';
    }

    get iconClass() {
        const variant = this.action?.iconVariant === 'isa' ? 'isa' : 'member';
        return `action-card__icon action-card__icon_${variant}`;
    }

    get badgeClass() {
        const variant = this.action?.isComplete ? 'complete' : 'warning';
        return `action-card__badge action-card__badge_${variant}`;
    }

    // Overflow-menu remove label. Defaults to the generic "Remove action"; the host supplies the
    // entity-remove label (e.g. "Remove household member") for a new record's card, where removing
    // the action removes the whole record.
    get removeMenuLabel() {
        return this.action?.removeMenuLabel || 'Remove action';
    }

    handleMenuSelect(event) {
        this.dispatchEvent(
            new CustomEvent('cardmenu', {
                detail: {
                    action: event.detail.value,
                    id: this.action?.id,
                    title: this.action?.title
                }
            })
        );
    }

    handleOpen() {
        this.dispatchEvent(
            new CustomEvent('openitem', { detail: { id: this.action?.id } })
        );
    }
}