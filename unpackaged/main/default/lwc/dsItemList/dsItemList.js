import { LightningElement, api } from 'lwc';
import { pluralize } from 'c/treeUtil';

const DEFAULT_GROUP_CAP = 5;

/**
 * dsItemList — the content list under a topic page's subtopic filter rows,
 * shared by the Help Center (article link rows) and the Resource Center
 * (resource cards). Two modes, one component:
 *
 *  - own:      `items` under `heading` ("Articles in {label}") — the node's
 *              directly attached content.
 *  - grouped:  `groups` — content inherited from the node's direct children,
 *              each under the child's name as a LINKED heading with its
 *              count, capped at `groupCap` rows with a "View all N" link to
 *              the child. A topic page must never dead-end while content
 *              exists below it; hosts pass groups when `items` is empty.
 *
 * @api variant 'rows' (default; `{id, title, routeKey, featured?, pathLabel?,
 *              pathKey?}` as link rows — pathLabel renders a c-item-path-tag
 *              after the title) or 'cards' (`c-ds-content-card` items from
 *              rcConstants.toContentItem, same optional path fields — the
 *              card's own composed `contentselect` / the tag's `pathselect`
 *              reach the host untouched).
 * @api noun    'article' | 'resource' — count wording.
 *
 * Events: rows emit `itemselect {id, routeKey}` on click and `itemhover
 * {id}` on mouseenter/focus (hosts prefetch); group headings and "View all"
 * emit `navselect {key}` like c-ds-tree, so a host reuses its tree handler.
 */
export default class DsItemList extends LightningElement {
    @api heading;
    @api noun = 'article';
    @api variant = 'rows';
    @api groupCap = DEFAULT_GROUP_CAP;

    _items = [];
    _groups = [];

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = value || [];
    }

    @api
    get groups() {
        return this._groups;
    }
    set groups(value) {
        this._groups = value || [];
    }

    get isRows() {
        return this.variant !== 'cards';
    }

    get hasOwn() {
        return this._items.length > 0;
    }

    get ownRows() {
        return this._items.map((item) => this.rowView(item));
    }

    get hasGroups() {
        return this._groups.some((g) => (g.items || []).length > 0);
    }

    get groupView() {
        const cap = Number(this.groupCap) || DEFAULT_GROUP_CAP;
        return this._groups
            .filter((g) => (g.items || []).length > 0)
            .map((g) => {
                const all = g.items || [];
                const count = g.count != null ? g.count : all.length;
                return {
                    key: g.key,
                    label: g.label,
                    countLabel: pluralize(count, this.noun),
                    rows: all.slice(0, cap).map((item) => this.rowView(item)),
                    showMore: all.length > cap || count > cap,
                    moreLabel: `View all ${pluralize(count, this.noun)}`
                };
            });
    }

    rowView(item) {
        return {
            ...item,
            key: item.id || item.routeKey,
            routeKey: item.routeKey,
            featured: Boolean(item.featured)
        };
    }

    // ---- Events ----------------------------------------------------------------

    handleItemClick(event) {
        event.preventDefault(); // rows are anchors; don't jump the page
        const { id, routekey } = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('itemselect', { detail: { id, routeKey: routekey } }));
    }

    handleItemHover(event) {
        this.dispatchEvent(new CustomEvent('itemhover', { detail: { id: event.currentTarget.dataset.id } }));
    }

    handleNav(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('navselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }
}