import { LightningElement, api } from 'lwc';

/**
 * dsTopicNav — the shared "All topics" sidebar for the Help Center and
 * Resource Center (extracted from nexsArticleBrowser's inline .nexs__nav*
 * markup so both centers consume one component).
 *
 * Controlled/presentational: the host owns selection and expansion.
 *
 * @api items: [{
 *   key: string,        // opaque routing key (HC: category API name; RC: slug)
 *   label: string,
 *   iconPath: string,   // SVG path `d` (24x24 viewBox, stroke=currentColor)
 *   active: boolean,    // navy fill + white underlined label
 *   expanded: boolean,  // accordion: children render only when true
 *   children: [{ key, label, active }]   // omit/empty for leaf topics
 * }]
 *
 * Emits `navselect { key }` for both topic and subtopic rows.
 *
 * Rows are real <button>s (native Enter/Space + focus — an upgrade over the
 * original clickable <li>s). Styling: no :host token redeclaration — custom
 * properties inherit from the host page's :host block, with the same literal
 * fallbacks in each var(). The 340px column / right border stay on the host's
 * <aside>; this component is just the title + list.
 */
export default class DsTopicNav extends LightningElement {
    // Named `heading`, not `title` — @api title would double as the global
    // HTML title attribute and tooltip the whole nav.
    @api heading = 'All topics';
    @api items = [];

    get itemView() {
        return (this.items || []).map((it) => {
            const children = it.children || [];
            const hasChildren = children.length > 0;
            const expanded = Boolean(it.expanded) && hasChildren;
            return {
                ...it,
                cssClass: it.active ? 'tnav__item tnav__item--active' : 'tnav__item',
                ariaCurrent: it.active ? 'true' : undefined,
                ariaExpanded: hasChildren ? String(expanded) : undefined,
                showChildren: expanded,
                children: children.map((ch) => ({
                    ...ch,
                    cssClass: ch.active ? 'tnav__child tnav__child--active' : 'tnav__child',
                    ariaCurrent: ch.active ? 'true' : undefined
                }))
            };
        });
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('navselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }
}