import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * householdOutlineItem — a single line in the Household Outline rail (a household
 * member or an account/DPI/service agreement). Presentational: it renders the
 * leading type icon, the entity name, a meta line and an optional amount from the
 * `item` it is given. Selection/open behavior is handled by a later slice.
 *
 * Expected shape:
 *   { id, name, meta, amount, iconVariant: 'member' | 'account', isNew, addedInEnvelope, removable }
 */
export default class HouseholdOutlineItem extends LightningElement {
    @api item;

    // Entity-type label for the more-actions "Remove" item (e.g. "Remove account"), supplied
    // by the host group. Falls back to a generic "Remove" if not provided.
    @api removeLabel;

    get removeMenuLabel() {
        return this.removeLabel || 'Remove';
    }

    // Members use the person icon; accounts/DPIs/service agreements use the document icon.
    get iconName() {
        return this.item?.iconVariant === 'member' ? 'utility:user' : 'utility:page';
    }

    get iconClass() {
        const variant = this.item?.iconVariant === 'member' ? 'member' : 'account';
        return `outline-item__icon outline-item__icon_${variant}`;
    }

    get hasMeta() {
        return !!this.item?.meta;
    }

    get hasAmount() {
        return !!this.item?.amount;
    }

    // "New" until the underlying record is submitted. `isNew` mirrors !Submitted__c — set from the
    // server for loaded rows and true for session-added rows — so the badge clears once the record
    // is submitted, matching the row's Remove/edit gating.
    get showNewBadge() {
        return !!this.item?.isNew;
    }

    // The Remove menu shows only for removable rows. Existing household entities (mock-seeded
    // or, later, loaded) carry no `removable` flag and can't be removed — only the actions
    // added to them can.
    get canRemove() {
        return !!this.item?.removable;
    }

    // The "+" Add-action button shows only for entities whose type offers at least one action to
    // add (`canAddActions`, supplied by the host). Draft (unsubmitted, `isNew`) entities already
    // carry their interview action and cannot gain more, mirroring how `canRemove` gates the
    // Remove menu via `removable`; item types with no actions (e.g. DPIs, services) hide the "+"
    // entirely.
    get canAdd() {
        return !this.item?.isNew && !!this.item?.canAddActions;
    }

    // The status indicator mirrors the content-area workspace: an entity surfaces its action
    // cards there only while it is an unsubmitted (isNew) draft — a submitted record is a locked
    // reference that shows no card, so it carries no status dot/check here either.
    get hasActiveActions() {
        return !!this.item?.isNew && (this.item?.actions?.length || 0) > 0;
    }

    // Progress indicator for an active entity: the amber in-progress dot while inputs are missing,
    // the green check once every action is complete (`isComplete`, computed by the host from the
    // shared completion selector).
    get showStatusDot() {
        return this.hasActiveActions && !this.item?.isComplete;
    }

    get showStatusCheck() {
        return this.hasActiveActions && !!this.item?.isComplete;
    }

    // The status region (New badge and/or progress indicator) renders when any indicator applies.
    get showStatusRegion() {
        return this.showNewBadge || this.showStatusDot || this.showStatusCheck;
    }

    get showAddClient() {
        return this.item?.iconVariant === 'member' && !(this.item?.actions?.length);
    }

    get showMenu() {
        return this.canRemove || this.showAddClient;
    }

    // More-actions menu select; mirrors envelopeActionCard's cardmenu.
    handleMenuSelect(event) {
        this.dispatchEvent(
            new CustomEvent('itemmenu', {
                detail: {
                    action: event.detail.value,
                    id: this.item?.id,
                    name: this.item?.name,
                    removeLabel: this.removeLabel
                }
            })
        );
    }

    // The row's "+" — behavior is owned by the host; this only signals intent.
    handleAdd() {
        this.dispatchEvent(
            new CustomEvent('itemadd', {
                detail: { id: this.item?.id, name: this.item?.name }
            })
        );
    }
}