import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeActionDetailsHeader — header for the action-details (interview) page: a
 * "Back to Envelope" link, the action title, a status badge, and an overflow menu.
 * Presentational; emits `back` (the link) and `headeraction` (the overflow menu).
 */
export default class EnvelopeActionDetailsHeader extends LightningElement {
    @api title = '';
    @api statusLabel = '';

    // Which treatment the status badge takes: 'warning' (in progress), 'complete' or 'updated'.
    @api statusVariant = 'warning';

    @api removeLabel = 'Remove action';

    get hasStatus() {
        return !!this.statusLabel;
    }

    // Only completion carries a check; the "Updated" badge is text alone.
    get statusComplete() {
        return this.statusVariant === 'complete';
    }

    get badgeClass() {
        return `action-header__badge action-header__badge_${this.statusVariant}`;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleMenuSelect(event) {
        this.dispatchEvent(
            new CustomEvent('headeraction', { detail: { action: event.detail.value } })
        );
    }
}