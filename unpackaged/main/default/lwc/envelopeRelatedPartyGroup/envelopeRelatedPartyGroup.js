import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeRelatedPartyGroup — one related-party subsection of the Related Parties section: a title
 * with Select Existing / Create New buttons, and below them either the parties added so far or an
 * empty-state message.
 *
 * Presentational only. The parties are supplied by the host (envelopeRelatedParties), which owns the
 * data and both dialogs; this component just reports what the user clicked, echoing back its
 * `partyKey` so the host knows which subsection acted.
 */

// The two ways a party can be added, rendered in this order. `key` reaches the host on `partyaction`.
const ACTIONS = [
    { key: 'selectExisting', label: 'Select Existing' },
    { key: 'createNew', label: 'Create New' }
];

export default class EnvelopeRelatedPartyGroup extends LightningElement {
    // This subsection's requirement key (e.g. 'authorizedPerson'), echoed back on every event.
    @api partyKey;

    // The party type's display name (e.g. 'Authorized Person').
    @api title;

    // Optional line under the title, used to spell out a requirement the title alone can't carry —
    // e.g. that this subsection and a sibling share one minimum. Omitted when there is nothing to say.
    @api note;

    // The parties added so far: [{ id, name, isNew?, missingLabel? }] — the envelopeMemberCard shape.
    @api parties = [];

    // Shown in place of the list while no party has been added.
    @api emptyMessage;

    // The most parties this subsection accepts, or null when unbounded. A subsection at its limit
    // still lists what it holds; only the add buttons are disabled.
    @api maxParties;

    get actions() {
        const disabled = this.isAtLimit;
        return ACTIONS.map((action) => ({ ...action, disabled }));
    }

    get isAtLimit() {
        return (
            typeof this.maxParties === 'number' &&
            (this.parties || []).length >= this.maxParties
        );
    }

    get hasParties() {
        return (this.parties || []).length > 0;
    }

    handleAction(event) {
        this.dispatchEvent(
            new CustomEvent('partyaction', {
                detail: {
                    key: this.partyKey,
                    action: event.currentTarget.dataset.action
                }
            })
        );
    }

    // The member card's `ownerremove` doesn't bubble; re-dispatch it as a removal for this
    // subsection so the host can drop the party from the right list.
    handleRemove(event) {
        this.dispatchEvent(
            new CustomEvent('partyremove', {
                detail: { key: this.partyKey, id: event.detail?.id }
            })
        );
    }
}