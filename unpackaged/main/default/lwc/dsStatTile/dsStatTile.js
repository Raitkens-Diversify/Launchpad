import { LightningElement, api } from 'lwc';

const VARIANTS = ['default', 'success', 'warning', 'error'];

/**
 * dsStatTile — label + big number + optional sub-label, for dashboard stat
 * rows (unclaimed seats, at-risk cycles, etc). Used by uatDashboard and
 * adminUatDashboard.
 */
export default class DsStatTile extends LightningElement {
    @api label = '';
    @api value = '';
    @api sublabel = '';
    @api variant = 'default'; // default|success|warning|error

    get valueClass() {
        const v = VARIANTS.includes(this.variant) ? this.variant : 'default';
        return `ds-stat__value ds-stat__value--${v}`;
    }

    get hasSublabel() {
        return Boolean(this.sublabel);
    }
}