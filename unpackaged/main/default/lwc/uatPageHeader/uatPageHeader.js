import { LightningElement, api } from 'lwc';

/**
 * uatPageHeader — the tester pages' shared page header: an icon tile, the
 * h1 + one-line subtitle, an optional count chip, and a right-aligned brand
 * action (the cross-link between My Queue and Open Pool). Absorbs the shell's
 * old .uta-page-head so each page owns its own header content.
 *
 * @api iconName: lightning-icon name for the tile (omit → no tile)
 * @api heading:  the page h1
 * @api subtitle: one-line explanation under the heading
 * @api count:    optional record count rendered as a chip beside the h1
 * @api actionLabel: right-aligned brand button label (omit → no button)
 * Emits `action` on button click; the host decides where it navigates.
 */
export default class UatPageHeader extends LightningElement {
    @api iconName = '';
    @api heading = '';
    @api subtitle = '';
    @api actionLabel = '';
    @api count;

    get hasIcon() {
        return Boolean(this.iconName);
    }

    get hasSubtitle() {
        return Boolean(this.subtitle);
    }

    get hasCount() {
        return this.count !== undefined && this.count !== null && this.count !== '';
    }

    get hasAction() {
        return Boolean(this.actionLabel);
    }

    handleAction() {
        this.dispatchEvent(new CustomEvent('action'));
    }
}