import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import { toContentItem, rcRootCrumbs, CRUMB_HELP_HOME, CRUMB_RC_HOME } from 'c/rcConstants';
import { typeMeta } from 'c/resourceTypeIcons';
import {
    indexTree, findNode, ancestorsOf, rootOf, pruneEmpty, filterRows, inSubtree, pathTag, pluralize
} from 'c/treeUtil';
import getCategoryBySlug from '@salesforce/apex/ResourceCenterService.getCategoryBySlug';
import getCategoryTree from '@salesforce/apex/ResourceCenterService.getCategoryTree';

/** The Type facet's "everything" value. Chip values are typeMeta badges
    ('PDF', 'Form', 'Link' …) so the facet reads like the cards' chips. */
const TYPE_ALL = 'all';

/**
 * resourceCategoryPage — the Resource Center's browse surface, mirroring the
 * Help Center's topic browser (nexsArticleBrowser): a persistent left
 * "All topics" sidebar (shared c-ds-tree) beside the topic content.
 *
 * The sidebar is an N-level accordion: the path to the current category is
 * expanded with siblings visible at every level, everything else collapsed
 * (c/treeUtil rules; past depth 4 the tree rebases at the grandparent behind
 * a "Back to" row and the breadcrumb carries the rest). Expansion derives
 * from the routed category, so clicking another branch collapses the
 * previous one for free. At phone widths the sidebar becomes a drawer behind
 * a "Browse topics" button (Escape closes, focus round-trips).
 *
 * Landing: with no routed slug the page falls back to the FIRST topic in
 * the sidebar, exactly as the Help Center's browser falls back to
 * categories[0] (nexsArticleBrowser.applyInitialState). That is what makes
 * the Resources tab land on the same browse shape as Help Articles instead
 * of a bespoke landing page.
 *
 * The page (2026-09-07: filtering, not drilling). A topic page is the
 * TOP-LEVEL topic of the routed node: its title, then cascading subtopic
 * pill rows (c-subtopic-filter-rows — the topic's children, then the
 * selected child's children, and so on), a count line with a compact Type
 * facet, and every resource in the selected node's subtree as cards, flat,
 * each with a path tag saying where it lives relative to the selection.
 * The ROUTE is the one source of truth: a pill, a path tag, a sidebar row
 * and a breadcrumb all emit `categoryselect { slug }` and the host routes;
 * this component re-derives the rows, the list and the sidebar highlight
 * from the slug it is handed back. Back/Forward therefore restore the pill
 * state for free.
 *
 * Data: the detail wire is keyed on the top-level topic's slug, not the
 * routed one — one fetch per main topic (CategoryDetail.allResources, the
 * whole subtree flat, each card naming its page categories), narrowed
 * client-side with c/treeUtil. Moving between subtopics of one topic never
 * refetches. The tree wire asks for the FULL tree (includeEmpty) so an empty
 * subtopic still shows as a disabled pill; the sidebar gets the pruned copy
 * it always had.
 *
 * Emits (composed) `categoryselect { slug }`, `rchome`, and
 * `resourceselect { slug }` — translated from c-ds-content-card's
 * `contentselect { kind, routeKey, id }` so the orchestrator's contract is
 * unchanged.
 */
export default class ResourceCategoryPage extends LightningElement {
    /** Routed slug. Undefined on the Resource Center landing, where the
        page falls back to the first sidebar topic. */
    @api
    get slug() {
        return this._slug;
    }
    set slug(value) {
        this._slug = value;
        this.navOpen = false;
        this.resolveRoute();
    }

    _slug;
    /** What the detail wire keys off: the routed node's TOP-LEVEL topic (or
        the routed slug itself while the tree is still loading / for a slug
        the tree doesn't know, so the server's own error still surfaces). */
    fetchSlug;

    detail;
    error;
    loading = true;
    /** Sidebar roots: the pruned tree (empty subtopics hidden), icons added. */
    navRoots = [];
    /** The full tree (includeEmpty): pills, path tags, counts, crumbs. */
    _tree = indexTree([]);
    _bySlug = new Map();
    typeFilter = TYPE_ALL;
    navOpen = false;
    _focusTree = false;

    @wire(getCategoryTree, { includeEmpty: true })
    wiredTree({ data }) {
        if (data) {
            const roots = (data.roots || []).map((r) => ({ ...r, iconPath: iconPath(r.iconName) }));
            this._tree = indexTree(roots);
            this._bySlug = new Map(this._tree.ordered.map((n) => [n.slug, n]));
            this.navRoots = pruneEmpty(roots);
            this.resolveRoute();
        }
    }

    /** Route → the slug to fetch. A routed slug always wins; otherwise land
        on the first topic. The tree wire is unparameterised by the route, so
        it resolves even with no slug — without this the detail wire would
        never fire and the page would spin forever. */
    resolveRoute() {
        const first = this._tree.roots.length ? this._tree.roots[0] : null;
        const selected = this._slug ? this._bySlug.get(this._slug) : first;
        const root = selected ? rootOf(this._tree, selected.id) : null;
        const next = root ? root.slug : (this._slug || (first ? first.slug : undefined));
        if (next !== this.fetchSlug) {
            // A new main topic: drop the old one's cards so the narrowed list
            // never flashes another topic's resources while the wire reloads.
            this.detail = undefined;
            this.error = undefined;
            this.loading = Boolean(next);
            this.fetchSlug = next;
        }
    }

    @wire(getCategoryBySlug, { slug: '$fetchSlug' })
    wiredCategory({ data, error }) {
        if (data) {
            this.detail = data;
            this.error = undefined;
            this.loading = false;
        } else if (error) {
            this.detail = undefined;
            this.error = this.reduce(error);
            this.loading = false;
        }
    }

    // ---- Route-derived state ----------------------------------------------------

    /** The routed node (the first topic on the landing); null until the tree
        lands or for a slug it doesn't carry. */
    get selectedNode() {
        const node = this._slug ? this._bySlug.get(this._slug) : this._tree.roots[0];
        return node || null;
    }

    /** The top-level topic the page is titled after. */
    get rootNode() {
        const selected = this.selectedNode;
        return selected ? rootOf(this._tree, selected.id) : null;
    }

    /** A pill (or deep link) has narrowed the page below its topic. */
    get isNarrowed() {
        const selected = this.selectedNode;
        const root = this.rootNode;
        return Boolean(selected && root && selected.id !== root.id);
    }

    get pageTitle() {
        const root = this.rootNode;
        return root ? root.label : (this.detail ? this.detail.name : '');
    }

    get pageDescription() {
        const root = this.rootNode;
        return root ? root.description : (this.detail ? this.detail.description : '');
    }

    /** c-subtopic-filter-rows input: the selected path's rows, from the tree. */
    get filterRowsData() {
        const selected = this.selectedNode;
        return selected ? filterRows(this._tree, selected.id) : [];
    }

    get showFilterRows() {
        return this.filterRowsData.length > 0;
    }

    /** Tree keys are category Ids; the routed key is the slug. */
    get activeKey() {
        const selected = this.selectedNode;
        return selected ? selected.id : null;
    }

    get crumbItems() {
        const crumbs = rcRootCrumbs();
        const selected = this.selectedNode;
        if (selected) {
            ancestorsOf(this._tree, selected.id).forEach((a) => {
                crumbs.push({ label: a.label, key: a.slug });
            });
            crumbs.push({ label: selected.label });
        } else if (this.detail) {
            (this.detail.ancestors || []).forEach((a) => {
                crumbs.push({ label: a.name, key: a.slug });
            });
            crumbs.push({ label: this.detail.name });
        }
        return crumbs;
    }

    // ---- Items ------------------------------------------------------------------------

    /** Every card on the main topic's page, as content items that remember
        which page categories they belong to (home first). */
    get allItems() {
        const cards = (this.detail && this.detail.allResources) || [];
        return cards.map((r) => ({ ...toContentItem(r), nodeKeys: r.pageCategoryIds || [] }));
    }

    /** …narrowed to the selected node's subtree (the subtopic filter). */
    get subtreeItems() {
        const selected = this.selectedNode;
        if (!selected) {
            return this.allItems;
        }
        return this.allItems.filter((item) => inSubtree(this._tree, item.nodeKeys, selected.id));
    }

    /** …then by type, with the path tag relative to the selection attached. */
    get items() {
        const selected = this.selectedNode;
        return this.subtreeItems
            .filter((item) => this.typeFilter === TYPE_ALL || this.typeOf(item) === this.typeFilter)
            .map((item) => {
                const { nodeKeys, ...card } = item;
                const tag = selected ? pathTag(this._tree, nodeKeys, selected.id) : null;
                return tag ? { ...card, pathLabel: tag.label, pathKey: tag.key } : card;
            });
    }

    get hasItems() {
        return this.items.length > 0;
    }

    typeOf(item) {
        return typeMeta(item.resourceType).badge;
    }

    /** The Type facet: one chip per type present in the selected subtree
        (counts live), All first; hidden when there is only one type. */
    get typeChips() {
        const counts = new Map();
        this.subtreeItems.forEach((item) => {
            const type = this.typeOf(item);
            counts.set(type, (counts.get(type) || 0) + 1);
        });
        if (counts.size < 2) {
            return [];
        }
        const types = [...counts.keys()].sort((a, b) => a.localeCompare(b));
        return [
            { value: TYPE_ALL, label: 'All', count: this.subtreeItems.length },
            ...types.map((type) => ({ value: type, label: type, count: counts.get(type) }))
        ];
    }

    get showTypeChips() {
        return this.typeChips.length > 0;
    }

    /** "25 resources" / "4 resources in Accounts" / "2 Form resources in Accounts". */
    get countLine() {
        const noun = this.typeFilter === TYPE_ALL ? 'resource' : `${this.typeFilter} resource`;
        const text = pluralize(this.items.length, noun);
        return this.isNarrowed ? `${text} in ${this.selectedNode.label}` : text;
    }

    /** True empty: nothing in the selected subtree at all. */
    get isEmpty() {
        return Boolean(this.detail) && this.subtreeItems.length === 0;
    }

    /** The subtree has resources, just none of the chosen type. */
    get isTypeEmpty() {
        return Boolean(this.detail) && this.subtreeItems.length > 0 && this.items.length === 0;
    }

    get typeEmptyText() {
        const where = this.isNarrowed ? ` in ${this.selectedNode.label}` : '';
        return `No ${this.typeFilter} resources${where}.`;
    }

    get navClass() {
        return this.navOpen ? 'rc-cat__nav rc-cat__nav--open' : 'rc-cat__nav';
    }

    get navToggleLabel() {
        return this.navOpen ? 'Hide topics' : 'Browse topics';
    }

    get navToggleExpanded() {
        return this.navOpen ? 'true' : 'false';
    }

    // ---- Handlers --------------------------------------------------------------

    /** Sidebar rows, pills and path tags are all keyed by category Id;
        resolve to the routed slug and ask the host to route. */
    handleNavSelect(event) {
        const node = findNode(this._tree, event.detail.key);
        if (node) {
            this.fireCategorySelect(node.slug);
        }
    }

    /** c-item-path-tag's composed pathselect (from inside a card). */
    handlePathSelect(event) {
        event.stopPropagation();
        this.handleNavSelect(event);
    }

    handleTypeSelect(event) {
        this.typeFilter = event.detail.value || TYPE_ALL;
    }

    handleTypeClear() {
        this.typeFilter = TYPE_ALL;
    }

    /** Phone-width drawer: open moves focus into the tree, close returns it. */
    handleNavToggle() {
        this.navOpen = !this.navOpen;
        this._focusTree = this.navOpen;
    }

    handleNavKeydown(event) {
        if (event.key === 'Escape' && this.navOpen) {
            this.navOpen = false;
            const toggle = this.template.querySelector('.rc-cat__nav-toggle');
            if (toggle) {
                toggle.focus();
            }
        }
    }

    renderedCallback() {
        if (!this._focusTree) {
            return;
        }
        this._focusTree = false;
        const tree = this.template.querySelector('c-ds-tree');
        if (tree && typeof tree.focusActive === 'function') {
            tree.focusActive();
        }
    }

    handleCrumb(event) {
        const key = event.detail.key;
        if (key === CRUMB_HELP_HOME) {
            this.handleHelpHome();
        } else if (key === CRUMB_RC_HOME) {
            this.handleHome();
        } else {
            this.fireCategorySelect(key);
        }
    }

    fireCategorySelect(slug) {
        this.dispatchEvent(new CustomEvent('categoryselect', {
            detail: { slug }, bubbles: true, composed: true
        }));
    }

    /** c-ds-content-card `contentselect` → the orchestrator's `resourceselect
        { slug }` contract (routeKey IS the slug for kind:'resource' items). */
    handleContentSelect(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug: event.detail.routeKey }, bubbles: true, composed: true
        }));
    }

    handleHome() {
        this.dispatchEvent(new CustomEvent('rchome', { bubbles: true, composed: true }));
    }

    /** The unified home is another page; the shell routes it via c/contextNav. */
    handleHelpHome() {
        this.dispatchEvent(new CustomEvent('helphome', { bubbles: true, composed: true }));
    }

    reduce(error) {
        return (error && error.body && error.body.message) || 'Something went wrong.';
    }
}