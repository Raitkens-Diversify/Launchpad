import { LightningElement, wire } from 'lwc';
import getArcBridge from '@salesforce/apex/ResourceCenterService.getArcBridge';

/**
 * helpReturnLink — "Back to ARC" in the /help site's theme header (Customizable
 * Header → actions region). The ARC site's sidebar "Learning" item lands on
 * /help/?from=arc (same tab, arcNavigation.hrefFor); this component remembers
 * that arrival for the tab (sessionStorage) so the way back survives the
 * client-side hops that follow, and hides itself for everyone else — unless
 * the org says the viewer is an ARC member (ResourceCenterService.getArcBridge).
 *
 * A plain anchor on purpose: ARC is another Experience site, so the hop is a
 * document navigation by design (c/contextNav only routes within a site).
 * The ARC base comes from Apex (Resource_Center_Setting__mdt.Default
 * .Arc_Site_Url_Path_Prefix__c → the site's own SecureUrl); nothing is
 * hardcoded. `from` is not in contextNav.PARAM_NAMES, so page hosts ignore it.
 *
 * Lives in a Builder region — a SIBLING of the page roots — so it inherits no
 * tokens and self-declares the block on :host (docs/ui-standards.md §1).
 */
const FROM_ARC_KEY = 'hc.fromArc';

export default class HelpReturnLink extends LightningElement {
    fromArc = false;
    bridge = null;

    connectedCallback() {
        try {
            const from = new URLSearchParams(window.location.search).get('from');
            if (from === 'arc') {
                sessionStorage.setItem(FROM_ARC_KEY, '1');
            }
            this.fromArc = sessionStorage.getItem(FROM_ARC_KEY) === '1';
        } catch (e) {
            // Storage blocked (private mode, guest sandbox): show only when
            // the org confirms membership.
            this.fromArc = false;
        }
    }

    @wire(getArcBridge)
    wiredBridge({ data, error }) {
        // An error (guest on the login page, Apex unreachable) simply hides
        // the link — never a broken affordance.
        this.bridge = data && !error ? data : null;
    }

    get show() {
        return !!(this.bridge && this.bridge.siteUrl) && (this.fromArc || this.bridge.isMember === true);
    }

    get href() {
        return `${this.bridge.siteUrl.replace(/\/$/, '')}/`;
    }
}