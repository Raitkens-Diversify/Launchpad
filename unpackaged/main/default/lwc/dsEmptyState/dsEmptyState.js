import { LightningElement, api } from 'lwc';

/**
 * dsEmptyState — formalizes the one-sentence-plus-action empty-state
 * convention already used ad hoc across Help Center, Resource Center, and
 * the UAT portal (e.g. "Nothing in your queue yet — claim a test from the
 * Open Pool and it lands here."). Invites action instead of just saying
 * "no records."
 *
 * @api icon: optional lightning-icon name
 * @api heading, message: the one-sentence explanation
 * @api actionLabel: shown only when showAction is true
 * Emits `action` when the button is clicked; the host decides what it does.
 */
export default class DsEmptyState extends LightningElement {
    @api icon = '';
    @api heading = '';
    @api message = '';
    @api actionLabel = '';

    _showAction = false;
    @api
    get showAction() {
        return this._showAction;
    }
    set showAction(value) {
        this._showAction = value === '' ? true : Boolean(value);
    }

    get hasIcon() {
        return Boolean(this.icon);
    }

    get showActionButton() {
        return this._showAction && Boolean(this.actionLabel);
    }

    handleAction() {
        this.dispatchEvent(new CustomEvent('action'));
    }
}