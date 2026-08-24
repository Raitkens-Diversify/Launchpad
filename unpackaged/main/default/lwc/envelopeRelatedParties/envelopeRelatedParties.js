import { LightningElement, api } from 'lwc';
import {
    memberRecordTypesFor,
    pendingPartyIds,
    relatedPartyPeers,
    partyAlternativesLabel
} from 'c/envelopeFormSchema';

/**
 * Author: Mile Cacanovic
 *
 * envelopeRelatedParties — the body of the Related Parties section: one subsection per party type
 * the entity must have (e.g. a business needs an Authorized Person, a Beneficial Owner and a Control
 * Person), each listing the parties added so far or an empty state.
 *
 * Which subsections apply is resolved by the host from the entity's record type, so this component
 * renders whatever `requirements` it's given. It owns the party data and both dialogs, while the
 * subsections stay presentational. Every change re-emits the section's whole value as
 * `partieschange`, which the form section persists like any other field value.
 */

// Shown in a subsection until its first party is added.
const EMPTY_MESSAGE = 'No related party added yet.';

export default class EnvelopeRelatedParties extends LightningElement {
    // The party types this entity needs: [{ key, title, type, types, min, max, group }], in render
    // order. `max` is absent for the member requirements, which are unbounded; `group` is present
    // only on roles that share one minimum with a sibling.
    @api requirements = [];

    // The parties added so far, keyed by requirement: { [key]: [{ id, name, isNew?, missingLabel? }] }.
    @api value = {};

    // The record these parties belong to, so it can't be offered as a party of itself.
    @api entityId;

    // The household this record belongs to, so "Select Existing" only offers parties already
    // linked to that household rather than searching the user's whole book.
    @api householdId;

    // The current envelope, so "Select Existing" can still offer a member just added to this
    // envelope alongside the household's already-formalized roster.
    @api envelopeId;

    // The requirement keys whose waiver is currently affirmed, comma-separated. A primitive so the
    // host can rebuild its section descriptor every render without this reading as a new value.
    @api waived = '';

    get _waivedKeys() {
        return String(this.waived || '')
            .split(',')
            .filter(Boolean);
    }

    // The subsection whose buttons opened the current dialog, so the result lands in the right list.
    _pendingKey = null;

    // One subsection per requirement. Requirements sharing a `group` are satisfied together, which
    // neither title says on its own, so the first of each set carries a note naming the alternatives
    // — stated once rather than repeated on every subsection it covers.
    get groups() {
        const noted = new Set();
        return (this.requirements || []).map((requirement) => {
            const isFirstOfGroup =
                requirement.group && !noted.has(requirement.group);
            if (isFirstOfGroup) {
                noted.add(requirement.group);
            }
            return {
                ...requirement,
                parties: this._partiesFor(requirement.key),
                emptyMessage: EMPTY_MESSAGE,
                note: isFirstOfGroup ? this._groupNoteFor(requirement.key) : null,
                // Present only on a role that can be affirmed away instead of filled, so the
                // template renders the checkbox for that subsection alone.
                waiverLabel: requirement.waiver?.label || null,
                waived: this._waivedKeys.includes(requirement.key),
                // The affirmation and the parties are mutually exclusive, enforced from both
                // sides: the add buttons are disabled while the affirmation stands (see the group
                // component's `waived`), and the affirmation cannot be ticked while the role holds
                // anyone. Remove the last party to make it available again.
                waiverDisabled: this._partiesFor(requirement.key).length > 0
            };
        });
    }

    // Member Type options for the create dialog: the party types this entity needs, so the dropdown
    // offers exactly the subsections a new member could belong to.
    get memberTypeOptions() {
        return (this.requirements || []).map((requirement) => ({
            label: requirement.title,
            value: requirement.key
        }));
    }

    handlePartyAction(event) {
        const { key, action } = event.detail;
        this._pendingKey = key;
        if (action === 'selectExisting') {
            this.refs.selectMemberModal.open(
                this._allowedRecordTypesFor(key),
                this._excludedIdsFor(key),
                this.householdId,
                this.envelopeId
            );
        } else if (action === 'createNew') {
            // The subsection already determines the member type, so the dialog opens on it locked
            // and capped to the slots it has left.
            this.refs.createMemberModal.open(key, this._remainingSlotsFor(key));
        }
    }

    // The record types the given subsection accepts, for narrowing the existing-member picker.
    // Empty when the requirement names no types, which the picker reads as no restriction.
    _allowedRecordTypesFor(key) {
        const requirement = (this.requirements || []).find(
            (entry) => entry.key === key
        );
        return memberRecordTypesFor(requirement?.types);
    }

    // The members the given subsection must not offer: the record itself, which cannot be its own
    // related party, and the parties it already holds, so the list shows only what can still be added.
    _excludedIdsFor(key) {
        return [
            ...(this.entityId ? [this.entityId] : []),
            ...this._partiesFor(key).map((party) => party.id)
        ];
    }

    // Add the picked member to the subsection that opened the dialog. The picker is single-select, so
    // ignore a member already in this subsection rather than listing them twice.
    handleMemberSelected(event) {
        const { id, name } = event.detail;
        const key = this._pendingKey;
        if (!key || !id) {
            return;
        }
        const parties = this._partiesFor(key);
        if (parties.some((party) => party.id === id)) {
            return;
        }
        this._commit(key, [...parties, { id, name }]);
    }

    // Created members carry the type chosen in the dialog, which is a requirement key — route each to
    // its own subsection so one dialog can fill several at once, falling back to the subsection that
    // opened it when the type doesn't match a requirement. Each gets a temporary id until its person
    // record is created on save, sequenced past the ids the section already holds.
    handleMembersCreated(event) {
        const members = event.detail?.members || [];
        if (!members.length) {
            return;
        }
        const next = { ...(this.value || {}) };
        const ids = pendingPartyIds(
            Object.values(next).flat(),
            members.length
        );
        members.forEach((member, index) => {
            const key = this._requirementKeyFor(member.type);
            if (!key) {
                return;
            }
            next[key] = [
                ...(next[key] || []),
                {
                    id: ids[index],
                    name: member.name,
                    isNew: true,
                    missingLabel: member.missingLabel
                }
            ];
        });
        this._emit(next);
    }

    handlePartyRemove(event) {
        const { key, id } = event.detail;
        this._commit(
            key,
            this._partiesFor(key).filter((party) => party.id !== id)
        );
    }

    handleModalClose() {
        this.refs.selectMemberModal.close();
        this.refs.createMemberModal.close();
        this._pendingKey = null;
    }

    _partiesFor(key) {
        return (this.value || {})[key] || [];
    }

    // The note naming every role a shared minimum accepts, e.g. "Required: a trustee or an
    // authorized person." Null for a group of one, whose own title already says it.
    _groupNoteFor(requirementKey) {
        const peers = relatedPartyPeers(this.requirements, requirementKey);
        if (peers.length < 2) {
            return null;
        }
        return `Required: ${partyAlternativesLabel(
            this.requirements,
            requirementKey
        )}.`;
    }

    // How many more parties the subsection can still take, or null when the requirement is unbounded.
    _remainingSlotsFor(key) {
        const requirement = (this.requirements || []).find(
            (entry) => entry.key === key
        );
        if (!requirement || typeof requirement.max !== 'number') {
            return null;
        }
        return Math.max(requirement.max - this._partiesFor(key).length, 0);
    }

    _requirementKeyFor(type) {
        const match = (this.requirements || []).find(
            (requirement) => requirement.key === type
        );
        return match ? match.key : this._pendingKey;
    }

    _commit(key, parties) {
        this._emit({ ...(this.value || {}), [key]: parties });
    }

    // Emit a new object rather than mutating: `value` is reactive by identity, so an in-place change
    // would not re-render.
    _emit(value) {
        this.dispatchEvent(new CustomEvent('partieschange', { detail: { value } }));
    }

    // The affirmation is a field on the record, not part of the parties value, so it travels as its
    // own event carrying the field name — the host persists it through the same path as any other
    // field answer rather than folding it into this section's composite value.
    handleWaiverChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = (this.requirements || []).find(
            (requirement) => requirement.key === key
        )?.waiver?.field;
        if (!field) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('waiverchange', {
                detail: { field, value: event.currentTarget.checked }
            })
        );
    }
}