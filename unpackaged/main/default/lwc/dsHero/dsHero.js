import { LightningElement, api } from 'lwc';

/**
 * dsHero — THE hero band: full-width navy gradient, light-blue eyebrow,
 * white serif display headline, and a slot for the wide element beneath it
 * (Help Center: search bar; Resource Center: search bar + Get Help link;
 * UAT dashboard: cycle progress bar + summary).
 *
 * Extracted from nexsHome's inline .home-hero markup (which
 * unifiedLanding and uatDashboard had each re-implemented) so all three
 * surfaces render the identical component. Colors are self-declared on
 * :host — see the comment in dsHero.css — which is what guarantees the same
 * navy in both LWR sites and the core Lightning app.
 */
export default class DsHero extends LightningElement {
    @api eyebrow = '';
    @api headline = '';
}