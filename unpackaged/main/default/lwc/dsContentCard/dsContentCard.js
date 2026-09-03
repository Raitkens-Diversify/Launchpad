import { LightningElement, api } from 'lwc';
import { typeMeta } from 'c/resourceTypeIcons';

/**
 * dsContentCard — shared presentational tile for a piece of routable content:
 * a Resource Center resource or a Help Center article. Generalizes the old
 * resourceCard recipe (surface + border + 10px radius + navy-border/lift
 * hover) behind a kind-agnostic contract. Apex-free; hosts own routing.
 * Consumed by resourceCategoryPage, unifiedLanding and the unified
 * search results.
 *
 * @api item: {
 *   kind: 'article' | 'resource',
 *   id: string,
 *   title: string,
 *   subtitle: string?,      // description/summary; card omits the <p> when absent
 *   routeKey: string,       // resource slug or article urlName — opaque to the card
 *   resourceType: string?,  // resources only; drives icon/badge/action via typeMeta
 *   action: string?,        // primary-action label override (rcConstants.resourceAction
 *                           // sets it for lifecycle verbs like a webinar's "Sign up" /
 *                           // "Watch"); absent → typeMeta's verb
 *   href: string?           // true external link: the primary action renders as an
 *                           // <a target="_blank" rel="noopener noreferrer"> instead
 *                           // of a button (hosts pass it only when the content
 *                           // really leaves the site)
 * }
 *
 * Emits `contentselect { kind, routeKey, id }` (bubbles + composed so the
 * orchestrator can catch it across shadow DOM) from the card head
 * (click / Enter / Space), the title, and the primary-action button. The href
 * anchor never fires it — the browser owns that navigation. Cards never
 * download directly (the detail view owns Download, so download counts stay
 * real).
 *
 * Visuals key off c/resourceTypeIcons.typeMeta(): kind === 'article' uses the
 * 'Article' entry; kind === 'resource' uses typeMeta(resourceType) exactly as
 * resourceCard did (unknown types fall back to Resource/Open).
 */
export default class DsContentCard extends LightningElement {
    @api item;

    get meta() {
        const item = this.item || {};
        return typeMeta(item.kind === 'article' ? 'Article' : item.resourceType);
    }
    get iconPath() {
        return this.meta.iconPath;
    }
    get badge() {
        return this.meta.badge;
    }
    get primaryLabel() {
        return (this.item && this.item.action) || this.meta.action;
    }
    get hasHref() {
        return Boolean(this.item && this.item.href);
    }
    get isButtonAction() {
        return !this.hasHref;
    }

    handleSelect() {
        const { kind, routeKey, id } = this.item || {};
        this.dispatchEvent(new CustomEvent('contentselect', {
            detail: { kind, routeKey, id }, bubbles: true, composed: true
        }));
    }

    handleKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect();
        }
    }
}