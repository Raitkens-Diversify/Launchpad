import { LightningElement, api } from 'lwc';
import { countLine } from 'c/treeUtil';

const PREVIEW_MAX = 3;

/**
 * dsSectionCards — a node's direct children as a card grid, the shared
 * "what's under this topic" surface of the Help Center and Resource Center
 * topic pages (successor of the c-ds-subnav pill row, which read as filters
 * and hid the fact that a child branches again). Same component at every
 * depth: a depth-3 page shows its depth-4 children exactly like the root
 * shows the top level.
 *
 * @api items  [{ key, label, description?, children?, itemCount?,
 *               descendantItemCount?, preview?: [{ id, title }] }] — pass the
 *              c/treeUtil nodes straight through (the count line is
 *              countLine(node, noun)); `preview` is the host's first few
 *              titles under the child, optional.
 * @api noun   the content word for the count line: 'article' (default) or
 *              'resource'.
 * @api label  accessible name of the grid ("In this topic").
 *
 * The WHOLE card is the link: one `<a>` per child, emitting `navselect
 * { key }` — the same event c-ds-tree fires, so a host points both at one
 * handler. Renders nothing for an empty list (no placeholder: a leaf page
 * goes straight to its articles).
 */
export default class DsSectionCards extends LightningElement {
    @api label = 'In this topic';
    @api noun = 'article';

    _items = [];

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = value || [];
    }

    get hasItems() {
        return this._items.length > 0;
    }

    get cards() {
        return this._items.map((item) => {
            const preview = (item.preview || []).slice(0, PREVIEW_MAX).map((p, i) => ({
                key: p.id || `${item.key}-p${i}`,
                title: p.title
            }));
            return {
                key: item.key,
                label: item.label,
                description: item.description || null,
                counts: countLine(item, this.noun),
                preview,
                hasPreview: preview.length > 0
            };
        });
    }

    handleSelect(event) {
        event.preventDefault(); // href="#" keeps the card a real link for a11y
        this.dispatchEvent(new CustomEvent('navselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }
}