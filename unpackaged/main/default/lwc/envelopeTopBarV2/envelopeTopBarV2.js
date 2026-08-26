import { LightningElement, api } from 'lwc';
// Logo lives in a Salesforce static resource (exported from Figma). Swap the
// resource name here if a new export is added under a different name.
import logo from '@salesforce/resourceUrl/DiversifyLogoV2';

export default class EnvelopeTopBarV2 extends LightningElement {
    /** Breadcrumb trail: array of { label, key, current? }. List page passes a single current crumb. */
    @api breadcrumb = [];
    /** Show the "Review and Submit" action (workspace variant). Hidden on the list page. */
    @api showReview = false;
    /**
     * Bar variant: 'default' (logo + breadcrumb) or 'focused' (leading title + envelope name +
     * status + Close), used by full-screen review views (Review Missing Items, Review & Submit).
     */
    @api mode = 'default';
    @api leadingTitle = '';
    @api envelopeName = '';
    @api statusText = '';
    @api showClose = false;
    /** Greys the Review button until the envelope is submittable. */
    @api reviewDisabled = false;

    /** Hides the Diversify logo for hosts that already have their own header/branding. */
    _hideBranding = false;
    @api
    get hideBranding() {
        return this._hideBranding;
    }
    set hideBranding(value) {
        this._hideBranding = value !== false && value !== 'false';
    }

    logoUrl = logo;

    get isDefault() {
        return this.mode !== 'focused';
    }

    get showBranding() {
        return !this._hideBranding;
    }

    get isFocused() {
        return this.mode === 'focused';
    }

    get hasStatus() {
        return Boolean(this.statusText);
    }

    get hasBreadcrumb() {
        return this.breadcrumbItems.length > 0;
    }

    get breadcrumbItems() {
        const items = Array.isArray(this.breadcrumb) ? this.breadcrumb : [];
        return items.map((item, index) => ({
            key: item.key || item.label || `crumb-${index}`,
            label: item.label
        }));
    }

    handleDsCrumbClick(event) {
        const key = event.target.name;
        this.dispatchEvent(new CustomEvent('navigate', { detail: { key } }));
    }

    handleReview() {
        this.dispatchEvent(new CustomEvent('review'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}