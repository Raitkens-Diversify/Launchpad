import { LightningElement, api } from 'lwc';
import LightningToast from 'lightning/toast';
import getAllMembers from '@salesforce/apex/EnvelopeHouseholdMemberController.getAllMembers';
import getHouseholdRoster from '@salesforce/apex/EnvelopeHouseholdMemberController.getHouseholdRoster';

/**
 * Author: Mile Cacanovic
 *
 * envelopeSelectMemberModal — the "Select existing member" dialog opened from the Account Owner
 * empty state in Review Missing Items. It lets the user search every member across all their
 * households and pick one to assign as the account owner.
 *
 * Composes the shared modal shell (dsModalV2) and the searchable combobox lookup. The members are
 * fetched on open; on confirm it dispatches `memberselected` with the chosen member and closes,
 * leaving the assignment to the host (envelopeShellV2). Opened imperatively via a DOM ref
 * (`open()`/`close()`), matching the other V2 dialogs.
 */
export default class EnvelopeSelectMemberModal extends LightningElement {
    memberOptions = [];
    isLoading = false;
    selectedId = '';
    selectedName = '';

    _isOpen = false;

    // RecordType DeveloperNames the picker is limited to for this opening (e.g. ['PersonAccount']).
    // Empty lists every member, which is what callers with no type restriction get.
    _allowedRecordTypes = [];

    // Member ids left out of the list for this opening: the record being filled in and anyone already
    // assigned to the slot, so the picker never offers a choice the caller would reject.
    _excludedIds = [];

    // When set, narrows the roster to this one household (getHouseholdRoster) instead of the
    // team-wide search (getAllMembers) — callers like an ISA's Related Parties section, where only
    // parties already linked to that specific household may be offered. Omit for the Account Owner
    // picker's original behavior.
    _householdId = null;

    // The current envelope, forwarded to getHouseholdRoster so a member just added to this
    // envelope is still offered even before it's a formalized part of the household roster.
    _envelopeId = null;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so the shell can drive the dialog via a DOM ref. Opening starts fresh
    // (clears any prior selection) and loads the members. `allowedRecordTypes` narrows the list to
    // members whose Account RecordType DeveloperName is in the list; omit it to offer every member.
    // `excludedIds` drops individual members from the list; omit it to exclude none. `householdId`
    // narrows the roster to that one household; omit it to search across the user's whole book
    // (the Account Owner picker's original behavior).
    @api
    open(allowedRecordTypes, excludedIds, householdId, envelopeId) {
        this.selectedId = '';
        this.selectedName = '';
        this._allowedRecordTypes = allowedRecordTypes || [];
        this._excludedIds = excludedIds || [];
        this._householdId = householdId || null;
        this._envelopeId = envelopeId || null;
        this._isOpen = true;
        this._loadMembers();
    }

    @api
    close() {
        this._isOpen = false;
    }

    get isContinueDisabled() {
        return !this.selectedId;
    }

    handleSelect(event) {
        const value = event.detail?.value || '';
        this.selectedId = value;
        this.selectedName =
            this.memberOptions.find((option) => option.value === value)?.label || '';
    }

    // Confirm the pick: bubble the selected member up to the host (which owns the assignment) and
    // close. The host already holds the pending Account Owner context, so only the member is sent.
    handleContinue() {
        this.dispatchEvent(
            new CustomEvent('memberselected', {
                detail: { id: this.selectedId, name: this.selectedName }
            })
        );
        this.close();
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // The inner ds-modal-v2 close event is composed; stop it so the host gets a single `close`
    // from this component.
    handleClose(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Load the roster into the combobox options. When opened with a householdId, the roster is
    // that one household's members (getHouseholdRoster) — e.g. an ISA's Primary Owner may only be
    // someone already linked to that household. Otherwise every member across the user's
    // households is offered (getAllMembers), so the account owner can be picked regardless of
    // which household (or a brand-new one) the envelope was created against. Either call returns a
    // flat, de-duplicated roster. When the caller restricted the record types, members whose
    // RecordType DeveloperName is outside the list are dropped, as are any the caller excluded by id.
    async _loadMembers() {
        this.memberOptions = [];
        this.isLoading = true;
        try {
            const result = this._householdId
                ? await getHouseholdRoster({
                      householdId: this._householdId,
                      envelopeId: this._envelopeId
                  })
                : await getAllMembers();
            const allowed = this._allowedRecordTypes;
            const excluded = new Set(this._excludedIds);
            this.memberOptions = (result || [])
                .filter((member) => member && member.id)
                .filter((member) => !excluded.has(member.id))
                .filter(
                    (member) =>
                        !allowed.length || allowed.includes(member.recordType)
                )
                .map((member) => ({ label: member.name, value: member.id }));
        } catch (error) {
            LightningToast.show({
                label: 'Members',
                message: error?.body?.message || 'Could not load members.',
                variant: 'error'
            }, this);
        } finally {
            this.isLoading = false;
        }
    }
}