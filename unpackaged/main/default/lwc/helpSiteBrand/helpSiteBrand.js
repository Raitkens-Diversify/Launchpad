import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import { linkContext, isInternal, homeHref, goToHome } from 'c/contextNav';

/**
 * helpSiteBrand — the /help site's brand mark, placed in the theme layout
 * header (Customizable Header → logo region) so every route shares ONE
 * header. Diversify logo + divider + "Help Center" label, linking to the
 * site home. Replaces the per-page brand strip c-ds-chrome used to draw
 * (those pages now run with hideBranding).
 *
 * Why an LWC and not the platform Site Logo: the site has no CMS image and
 * the logo already ships as the DiversifyLogoV2 static resource every page
 * uses — one asset, no CMS upload.
 *
 * Navigation goes through c/contextNav like every other cross-page hop:
 * a plain click routes client-side (standard__webPage); the anchor's real
 * href keeps middle/modifier clicks and the no-JS case working. Before the
 * context resolves (or for a guest on the login page, where Apex is not
 * reachable) the anchor falls back to the site root.
 *
 * Lives in a Builder region — a SIBLING of the page roots — so it inherits
 * no tokens and self-declares the block on :host (docs/ui-standards.md §1).
 */
export default class HelpSiteBrand extends NavigationMixin(LightningElement) {
    logoUrl = diversifyLogo;
    label = 'Help Center';
    linkCtx = null;
    homeUrl = './';

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
            if (!isInternal(ctx)) {
                this.homeUrl = homeHref(ctx);
            }
        });
    }

    handleClick(event) {
        const isPlainClick =
            event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
        if (!isPlainClick || !this.linkCtx) {
            return; // the anchor navigates
        }
        event.preventDefault();
        goToHome(this, this.linkCtx);
    }
}