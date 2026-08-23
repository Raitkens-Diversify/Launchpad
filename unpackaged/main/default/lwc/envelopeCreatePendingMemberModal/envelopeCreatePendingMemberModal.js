import { LightningElement, api, track } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeCreatePendingMemberModal — a dialog for creating one or more pending members
 * (an account owner, a trustee/grantor, or an entity's related party) with a nickname and member
 * type. Each created member is added to the household outline as pending, with an action item to
 * complete their full details later.
 *
 * The variations differ only in the header title and the info-alert wording, selected via
 * the `variant` property. Built on the shared modal shell (dsModalV2) and opened imperatively
 * via a DOM ref (open()/close()), matching the other V2 dialogs. On save it dispatches
 * `membercreated` with the completed rows and closes, leaving the assignment to the host.
 */

// Per-variation copy — the only thing that differs between the account-owner and
// trustee/grantor dialogs.
const VARIANTS = {
    accountOwner: {
        title: 'Create new account owner',
        infoText:
            'This member will be added as a pending member to the household outline, and an action item will be created in the envelope to complete their information.'
    },
    trusteeGrantor: {
        title: 'Create new trustee and/or grantor',
        infoText:
            'This member(s) will be added as a pending member(s) to the household outline, and an action item will be created in the envelope to complete their information.'
    },
    relatedParty: {
        title: 'Create new related party',
        infoText:
            'This member(s) will be added as a pending member(s) to the household outline, and an action item will be created in the envelope to complete their information.'
    }
};

// Shown on each created member's card until their full details are completed via the action item.
const PENDING_MISSING_LABEL = 'Complete member information';

export default class EnvelopeCreatePendingMemberModal extends LightningElement {
    @api variant = 'accountOwner';

    // Member Type options ([{label,value}]), owned by the host so the same dialog serves any
    // member context; a later slice sources these from picklist metadata.
    @api memberTypeOptions = [];

    // One entry per member row: { id, nickname, type }. Reset to a single empty row on open.
    @track members = [];

    _isOpen = false;
    _nextRowId = 0;

    // The member type every row is fixed to for this opening, or '' when the user picks it. Set by
    // open() when the host knows the type already (a related-party subsection's own Create New).
    _presetType = '';

    // How many members this opening may create, or null when the host set no ceiling. Set by open()
    // when the host's subsection has a slot limit, so the dialog can't push it past its max.
    _maxMembers = null;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
        // Start each open with a clean single row.
        if (value) {
            this._reset();
        }
    }

    // Imperative open/close so the host can drive the dialog via a DOM ref, matching the other
    // V2 dialogs. Opening starts fresh with a single empty row. `presetType` is a value from
    // memberTypeOptions: pass it when the dialog is opened from a place that already determines the
    // member type, and every row opens on that type with the picker locked. `maxMembers` caps how
    // many rows can be added this opening: pass the subsection's remaining slot count so the dialog
    // can't create more members than it can take.
    @api
    open(presetType, maxMembers) {
        this._presetType = presetType || '';
        this._maxMembers = typeof maxMembers === 'number' ? maxMembers : null;
        this._reset();
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
        this._presetType = '';
        this._maxMembers = null;
    }

    // The Member Type picker is read-only once the host fixed the type — the dialog was opened from
    // that member type's own section, so changing it there would file the member elsewhere.
    get isTypeLocked() {
        return !!this._presetType;
    }

    get dialogTitle() {
        return this._config.title;
    }

    get infoText() {
        return this._config.infoText;
    }

    // Enable Save only when every row is complete and there is at least one — a half-filled row
    // can't be saved, and an empty "Add another member" row blocks submit until it is filled.
    get isSaveDisabled() {
        return !this.members.length || this.members.some((row) => !this._isRowComplete(row));
    }

    get canRemoveMembers() {
        return this.members.length > 1;
    }

    // Stop adding rows once the dialog holds as many members as the host's subsection can still
    // take; removing a row re-enables the button. Null means the host set no ceiling.
    get isAddMemberDisabled() {
        return this._maxMembers !== null && this.members.length >= this._maxMembers;
    }

    handleNicknameChange(event) {
        const value = event.detail?.value ?? event.target.value;
        this._updateRow(Number(event.target.dataset.index), { nickname: value });
    }

    handleTypeChange(event) {
        const value = event.detail?.value ?? event.target.value;
        this._updateRow(Number(event.target.dataset.index), { type: value });
    }

    handleAddMember() {
        this.members = [...this.members, this._blankRow()];
    }

    handleRemoveMember(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (Number.isNaN(index)) {
            return;
        }
        this.members = this.members.filter((_, i) => i !== index);
    }

    // Emit the completed rows to the host (which owns the assignment) and close. Partial/blank
    // rows are dropped; Save is disabled while any exist, so this is a safety net.
    handleSave() {
        const members = this.members
            .filter((row) => this._isRowComplete(row))
            .map((row) => ({
                name: row.nickname.trim(),
                type: row.type,
                isNew: true,
                missingLabel: PENDING_MISSING_LABEL
            }));
        if (!members.length) {
            return;
        }
        this.dispatchEvent(new CustomEvent('membercreated', { detail: { members } }));
        this.close();
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // The inner ds-modal-v2 close event is composed; stop it so the host gets a single `close`.
    handleClose(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }

    get _config() {
        return VARIANTS[this.variant] || VARIANTS.accountOwner;
    }

    _reset() {
        this.members = [this._blankRow()];
    }

    _blankRow() {
        this._nextRowId += 1;
        return { id: `row-${this._nextRowId}`, nickname: '', type: this._presetType };
    }

    _updateRow(index, patch) {
        if (Number.isNaN(index)) {
            return;
        }
        this.members = this.members.map((row, i) => (i === index ? { ...row, ...patch } : row));
    }

    _isRowComplete(row) {
        return !!(row.nickname?.trim() && row.type);
    }
}