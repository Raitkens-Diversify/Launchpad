import { LightningElement, api, track } from 'lwc';
import {
    memberRecordTypesFor,
    pendingPartyIds,
    relatedPartyPeers,
    partyAlternativesLabel,
    partyTypeChoices,
    exclusivePartyIds
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

// Shown when a pick would name the same entity in two slots that must differ.
const DUPLICATE_OWNER_MESSAGE =
    'That entity is already named in another owner slot. Each owner must be a different entity.';

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

    // Shown when a pick would put the same entity in two slots that must name different ones. The
    // picker normally excludes those entities outright, so this only surfaces for a value that was
    // already held when the section loaded.
    @track duplicateMessage = null;

    // Cache of the create dialog's type options, keyed by the slot that opened it. Two reasons, both
    // load-bearing: the options are an @api value on the dialog, and handing it a fresh array
    // identity for the same option set reads to LWC as a change and re-renders it needlessly; and
    // reopening the same slot should not rebuild what it already computed.
    _typeOptionsMemo = { key: undefined, value: null };

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

    // Member Type options for the create dialog. A slot accepting one entity type is named by its
    // subsection, so the dropdown offers the subsections a new member could belong to and the dialog
    // opens locked on one. A slot accepting several — a service agreement's owner, which may be an
    // Individual, a Business or a Trust — cannot be named that way: the type decides which record
    // gets created, so the dropdown offers the entity types themselves and the dialog opens unlocked.
    //
    // Set on the dialog just before it opens rather than bound in the template. The set depends on
    // which subsection opened the dialog, and that is not reactive state — a template binding would
    // still be showing the previous slot's options at the moment open() ran. Assigning here makes the
    // order explicit instead of racing a re-render.
    _typeOptionsFor(key) {
        if (this._typeOptionsMemo.key === key && this._typeOptionsMemo.value) {
            return this._typeOptionsMemo.value;
        }
        const requirement = this._requirementFor(key);
        const value = this._isMultiTypeSlot(requirement)
            ? partyTypeChoices(requirement.types)
            : (this.requirements || []).map((entry) => ({
                  label: entry.title,
                  value: entry.key
              }));
        this._typeOptionsMemo = { key, value };
        return value;
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
            // A single-type subsection already determines the member type, so the dialog opens on it
            // locked. A multi-type slot opens unlocked so the user picks the entity type; either way
            // it is capped to the slots this subsection has left.
            const requirement = this._requirementFor(key);
            const preset = this._isMultiTypeSlot(requirement) ? null : key;
            const dialog = this.refs.createMemberModal;
            dialog.memberTypeOptions = this._typeOptionsFor(key);
            dialog.open(preset, this._remainingSlotsFor(key));
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
    // related party, the parties it already holds, so the list shows only what can still be added,
    // and — for a slot that must name a different entity than its siblings — whatever those siblings
    // hold. exclusivePartyIds is empty for every slot carrying no exclusivity.
    _excludedIdsFor(key) {
        return [
            ...(this.entityId ? [this.entityId] : []),
            ...this._partiesFor(key).map((party) => party.id),
            ...exclusivePartyIds(this.requirements, key, this.value)
        ];
    }

    // Add the picked member to the subsection that opened the dialog. The picker is single-select, so
    // ignore a member already in this subsection rather than listing them twice.
    //
    // A pick already held by a slot this one must differ from is refused with a message rather than
    // ignored: the picker excludes those entities, so reaching here means the value was already held
    // when the section loaded, and doing nothing silently would read as a broken button.
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
        if (exclusivePartyIds(this.requirements, key, this.value).includes(id)) {
            this.duplicateMessage = DUPLICATE_OWNER_MESSAGE;
            return;
        }
        this.duplicateMessage = null;
        this._commit(key, [...parties, { id, name }]);
    }

    // Created members carry the type chosen in the dialog. For a single-type slot that is a
    // requirement key, so each member routes to its own subsection and one dialog can fill several at
    // once. For a multi-type slot it is a member type instead, which matches no requirement, so the
    // existing fallback files it under the subsection that opened the dialog — and the chosen type is
    // carried on the party as `partyType`, because it is the only record of which kind of entity to
    // create and the slot's own `types` no longer answers that on its own.
    //
    // Each gets a temporary id until its record is created on save, sequenced past the ids the
    // section already holds.
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
            const isRequirementKey = (this.requirements || []).some(
                (requirement) => requirement.key === member.type
            );
            next[key] = [
                ...(next[key] || []),
                {
                    id: ids[index],
                    name: member.name,
                    isNew: true,
                    missingLabel: member.missingLabel,
                    // Only a multi-type slot's chosen entity type is worth carrying: a requirement
                    // key says nothing the slot's own types do not already say.
                    ...(isRequirementKey ? {} : { partyType: member.type })
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

    // Dismiss the duplicate-owner message. Held until dismissed or superseded so it survives the
    // dialog closing over it.
    handleDuplicateDismiss() {
        this.duplicateMessage = null;
    }

    _partiesFor(key) {
        return (this.value || {})[key] || [];
    }

    _requirementFor(key) {
        return (this.requirements || []).find((entry) => entry.key === key);
    }

    // True for a slot accepting more than one entity type, which therefore cannot infer from its own
    // configuration which kind of record "Create new" should make.
    _isMultiTypeSlot(requirement) {
        return (requirement?.types || []).length > 1;
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