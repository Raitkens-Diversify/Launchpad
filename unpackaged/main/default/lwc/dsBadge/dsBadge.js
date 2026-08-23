import { LightningElement, api } from 'lwc';

/**
 * Usage:
 * <c-ds-badge label="Needs info" variant="warning"></c-ds-badge>
 */
export default class DsBadge extends LightningElement {
    /**
     * Badge text label.
     * @type {string}
     */
    @api label = '';

    /**
     * Badge variant.
     * @type {'default'|'success'|'warning'|'error'|'info'}
     */
    @api variant = 'default';

    /**
     * Badge size.
     * @type {'sm'|'md'}
     */
    @api size = 'md';

    get badgeClass() {
        const variant = ['default', 'success', 'warning', 'error', 'info'].includes(this.variant) ? this.variant : 'default';
        const size = this.size === 'sm' ? 'sm' : 'md';
        return `ds-badge ds-badge_${variant} ds-badge_${size}`;
    }
}