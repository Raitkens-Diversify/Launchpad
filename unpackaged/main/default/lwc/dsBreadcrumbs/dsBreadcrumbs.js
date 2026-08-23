import { LightningElement, api } from 'lwc';

/**
 * dsBreadcrumbs — shared breadcrumb trail for the Help Center and Resource
 * Center (extracted from nexsArticleBrowser's inline .nexs__crumbs markup so
 * both centers consume one component).
 *
 * @api items: [{ label, key? }] — items WITH a key render as links and emit
 * `crumbselect { key }` on click; keyless items render as the non-clickable
 * current segment. The last item may still be keyed (the Help Center shows
 * "Help Center › {topic}" with a clickable topic while an article title is
 * loading).
 *
 * Styling: no :host token redeclaration — the --slds-g-* and --ds-* custom
 * properties inherit from the host page's :host block, with the same literal
 * fallbacks baked into each var(). Consumers may style the host element
 * (c-ds-breadcrumbs { align-items: … }) — :host is display:flex for that.
 */
export default class DsBreadcrumbs extends LightningElement {
    @api items = [];

    get itemView() {
        return (this.items || []).map((c, i) => ({
            ...c,
            renderKey: c.key || `crumb-${i}`,
            showSep: i > 0,
            clickable: Boolean(c.key)
        }));
    }

    handleClick(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('crumbselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }
}