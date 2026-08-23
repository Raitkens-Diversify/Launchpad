import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeAddActionModal — the "Add action item" dialog opened from a Household Outline
 * row's "+". It presents the available action types as a grid of selectable cards and
 * lets the user pick one or more before confirming. It composes the shared modal shell
 * (dsModalV2) and owns no persistence: it dispatches `confirm` (with the selected ids) and
 * `close`, leaving the host to act on the selection. The action catalog is supplied by the host
 * (resolved per the target entity's type); this dialog stays presentational and renders whatever
 * list it is given.
 *
 * Opened imperatively via a DOM ref (`open()`/`close()`) rather than an is-open flag,
 * matching the other V2 dialogs in envelopeShellV2.
 */
export default class EnvelopeAddActionModal extends LightningElement {
    // The entity the actions are being added to; drives the dialog subtitle.
    @api entityName = '';

    // Action ids already on the entity. Their rows render checked and disabled so an action
    // can't be added twice.
    @api disabledIds = [];

    _isOpen = false;
    _actions = [];
    _selectedIds = new Set();

    // The action-type catalog to offer, supplied by the host per the target entity's type. Any
    // array is accepted (an empty one renders no cards); the host gates the "+" so the dialog is
    // not opened with an empty catalog.
    @api
    get actions() {
        return this._actions;
    }
    set actions(value) {
        if (Array.isArray(value)) {
            this._actions = value;
        }
    }

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so a host can drive the dialog from JS via a DOM ref. Opening
    // clears any previous selection so the dialog starts fresh.
    @api
    open() {
        this._selectedIds = new Set();
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
    }

    get subtitle() {
        return this.entityName ? `Add actions to ${this.entityName}` : 'Select the actions to add';
    }

    // Render model: each action plus its selected/disabled flags and the matching card class.
    // An already-added action (id in disabledIds) is shown checked and disabled.
    get actionRows() {
        const disabled = new Set(this.disabledIds || []);
        return this._actions.map((action) => {
            const isDisabled = disabled.has(action.id);
            const selected = isDisabled || this._selectedIds.has(action.id);
            const classes = ['add-action__card'];
            if (selected) {
                classes.push('add-action__card_selected');
            }
            if (isDisabled) {
                classes.push('add-action__card_disabled');
            }
            return {
                ...action,
                selected,
                disabled: isDisabled,
                cardClass: classes.join(' ')
            };
        });
    }

    handleToggle(event) {
        this._toggleSelection(event.currentTarget.dataset.id);
    }

    // Whole-card click: toggle the action when the click landed on the card itself, not on the
    // checkbox/label (those retarget to the lightning-input and are handled by its `change` above,
    // so forwarding them here too would double-toggle). Already-added actions stay checked+disabled.
    handleCardClick(event) {
        if (event.target !== event.currentTarget) {
            return;
        }
        const id = event.currentTarget.dataset.id;
        if ((this.disabledIds || []).includes(id)) {
            return;
        }
        this._toggleSelection(id);
    }

    handleConfirm() {
        this.dispatchEvent(
            new CustomEvent('confirm', { detail: { selectedIds: [...this._selectedIds] } })
        );
        this._isOpen = false;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Flip an action's selection and reassign the set so `actionRows` (and the card classes)
    // re-render. A checkbox `change` always represents a flip, so both the checkbox and the
    // whole-card click share this.
    _toggleSelection(id) {
        if (this._selectedIds.has(id)) {
            this._selectedIds.delete(id);
        } else {
            this._selectedIds.add(id);
        }
        this._selectedIds = new Set(this._selectedIds);
    }
}