import { LightningElement, api } from 'lwc';

/**
 * dsChrome — the shared page shell for the Help Center / Resource Center /
 * unified landing surfaces: sticky white brand header (logo + divider + brand
 * crumb + optional search + optional actions), body, and brand footer.
 * Extracted from the two per-root chromes (nexsLanding `.nexs-chrome__*` and
 * resourceCenter `.rc-chrome__*`) that had drifted into copies.
 *
 * Presentational: hosts own everything interactive.
 *   @api logoUrl        — brand image (DiversifyLogoV2 static resource URL)
 *   @api brandLabel     — crumb text + footer brand ("Help Center", …)
 *   @api copyrightLine  — footer meta; sensible default
 *   @api hideBranding   — "the site supplies the brand chrome": hides logo +
 *                         divider + brand crumb AND the brand footer, and
 *                         collapses the header strip entirely while both the
 *                         search and actions slots are empty. Set by the
 *                         /help site pages (the theme layout owns the header
 *                         + nav + footer since 2026-09-04) and by embeddings,
 *                         like ARC, that carry their own site chrome. The
 *                         search/actions slots still render when occupied —
 *                         page-specific controls stay, below the site header.
 *   slots: search (right-aligned, flexible width), actions (after search:
 *          help menu, cross-app links), default (page body)
 *   events: brandclick  — the brand crumb was clicked (host routes home)
 *
 * Tokens are inherited from the declaring root's :host block with literal
 * fallbacks (ds* convention — no self-declared token block).
 */
export default class DsChrome extends LightningElement {
    @api logoUrl;
    @api brandLabel = '';
    @api copyrightLine = `© ${new Date().getFullYear()} Diversify Financial. Internal use only.`;

    // A Builder checkbox / content.json attribute can hand this over as the
    // string "true" rather than a boolean, so coerce on the way in.
    _hideBranding = false;
    @api
    get hideBranding() {
        return this._hideBranding;
    }
    set hideBranding(value) {
        this._hideBranding = value === true || value === 'true';
    }
    get showBranding() {
        return !this._hideBranding;
    }
    /** The brand footer belongs to whoever owns the branding. */
    get showFooter() {
        return this.showBranding;
    }
    /** With branding hidden and nothing slotted, the strip would be an empty
        64px bar under the site header — collapse it. The slots stay mounted
        (inside the header) so slotchange keeps firing when a view swaps. */
    get headerClass() {
        const empty = !this.showBranding && !this.hasSearch && !this.hasActions;
        return empty ? 'ds-chrome__header ds-chrome__header--empty' : 'ds-chrome__header';
    }

    // Track slot occupancy so an empty search slot doesn't eat flex space
    // (home views put search in the hero, not the header).
    hasSearch = false;
    hasActions = false;

    handleSearchSlotChange(event) {
        this.hasSearch = event.target.assignedElements().length > 0;
    }
    handleActionsSlotChange(event) {
        this.hasActions = event.target.assignedElements().length > 0;
    }

    get searchClass() {
        return this.hasSearch ? 'ds-chrome__search' : 'ds-chrome__search ds-chrome__search--empty';
    }
    get actionsClass() {
        // With no search, actions sit far right; after a search they follow it.
        const base = this.hasSearch
            ? 'ds-chrome__actions'
            : 'ds-chrome__actions ds-chrome__actions--solo';
        return this.hasActions ? base : `${base} ds-chrome__actions--empty`;
    }

    handleBrandClick() {
        this.dispatchEvent(new CustomEvent('brandclick'));
    }
}