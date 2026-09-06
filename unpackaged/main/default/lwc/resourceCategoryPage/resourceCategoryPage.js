import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import { toContentItem, rcRootCrumbs, CRUMB_HELP_HOME, CRUMB_RC_HOME } from 'c/rcConstants';
import { indexTree, findNode } from 'c/treeUtil';
import getCategoryBySlug from '@salesforce/apex/ResourceCenterService.getCategoryBySlug';
import getCategoryTree from '@salesforce/apex/ResourceCenterService.getCategoryTree';

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
 * Pages (any depth):
 *  - A category WITH subcategories: collapsible sections, one per direct
 *    child holding that child's whole subtree (first open), then its own
 *    resources trailing in "General resources"; a single section renders
 *    the plain card grid.
 *  - A leaf category: flat card grid of its own resources. Every category is
 *    its own page — deep links land here directly.
 *
 * Emits (composed) `categoryselect { slug }`, `rchome`, and
 * `resourceselect { slug }` — translated from c-ds-content-card's
 * `contentselect { kind, routeKey, id }` so the orchestrator's contract is
 * unchanged.
 */
export default class ResourceCategoryPage extends LightningElement {
    /** Routed slug. Undefined on the Resource Center landing, where
        effectiveSlug falls back to the first sidebar topic. */
    @api
    get slug() {
        return this._slug;
    }
    set slug(value) {
        this._slug = value;
        this.resolveEffectiveSlug();
    }

    _slug;
    /** What the detail wire actually keys off — routed slug or the default. */
    effectiveSlug;

    detail;
    error;
    loading = true;
    openKeys = new Set();
    navRoots = [];
    _navTree = indexTree([]);
    navOpen = false;
    _focusTree = false;

    @wire(getCategoryTree)
    wiredTree({ data }) {
        if (data) {
            this.navRoots = (data.roots || []).map((r) => ({ ...r, iconPath: iconPath(r.iconName) }));
            this._navTree = indexTree(this.navRoots);
            this.resolveEffectiveSlug();
        }
    }

    /** A routed slug always wins; otherwise land on the first topic. The
        tree wire is unparameterised, so it resolves even with no slug —
        without this the detail wire would never fire and the page would
        spin forever. */
    resolveEffectiveSlug() {
        const first = this.navRoots.length ? this.navRoots[0].slug : undefined;
        this.effectiveSlug = this._slug || first;
    }

    @wire(getCategoryBySlug, { slug: '$effectiveSlug' })
    wiredCategory({ data, error }) {
        if (data) {
            this.applyDetail(data);
        } else if (error) {
            this.detail = undefined;
            this.error = this.reduce(error);
            this.loading = false;
        }
    }

    applyDetail(data) {
        this.detail = data;
        this.error = undefined;
        this.loading = false;
        this.navOpen = false;
        const sections = data.sections || [];
        // Help Center convention: first section open, rest collapsed.
        this.openKeys = new Set(sections.length ? [sections[0].key] : []);
    }

    // ---- View model ----------------------------------------------------------

    get sections() {
        return (this.detail && this.detail.sections) || [];
    }

    /** Section chrome only earns its place on a branch with 2+ groups; leaf
        pages and single-section branches render the plain grid. */
    get useSections() {
        return Boolean(this.detail && this.detail.hasChildren) && this.sections.length > 1;
    }

    get gridResources() {
        if (this.sections.length === 1) {
            return this.sections[0].resources;
        }
        return (this.detail && this.detail.resources) || [];
    }

    get hasGridResources() {
        return this.gridResources.length > 0;
    }

    get gridItems() {
        return this.gridResources.map(toContentItem);
    }

    get isEmpty() {
        return Boolean(this.detail) && !this.useSections && !this.hasGridResources;
    }

    /** Tree keys are category Ids; the routed key is the slug. */
    get activeKey() {
        return this.detail ? this.detail.id : null;
    }

    /** This category's direct children for c-ds-subnav, keyed like the
        sidebar so one handleNavSelect serves both. The reader tree prunes
        empty branches server-side, so only subcategories with content list. */
    get subtopicItems() {
        const node = findNode(this._navTree, this.activeKey);
        return ((node && node.children) || []).map((c) => ({
            key: c.id,
            label: c.label,
            count: c.descendantItemCount
        }));
    }

    get showSubtopics() {
        return this.subtopicItems.length > 0;
    }

    get crumbItems() {
        const crumbs = rcRootCrumbs();
        if (this.detail) {
            (this.detail.ancestors || []).forEach((a) => {
                crumbs.push({ label: a.name, key: a.slug });
            });
            crumbs.push({ label: this.detail.name });
        }
        return crumbs;
    }

    get sectionView() {
        return this.sections.map((s) => {
            const open = this.openKeys.has(s.key);
            const count = s.resources.length;
            return {
                ...s,
                items: s.resources.map(toContentItem),
                ariaExpanded: open ? 'true' : 'false',
                iconName: open ? 'utility:chevrondown' : 'utility:chevronright',
                bodyClass: open
                    ? 'rc-section__body'
                    : 'rc-section__body rc-section__body--collapsed',
                countLabel: count === 1 ? '1 resource' : `${count} resources`
            };
        });
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

    handleSectionToggle(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.openKeys);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.openKeys = next;
    }

    handleNavSelect(event) {
        const node = findNode(this._navTree, event.detail.key);
        if (node) {
            this.fireCategorySelect(node.slug);
        }
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