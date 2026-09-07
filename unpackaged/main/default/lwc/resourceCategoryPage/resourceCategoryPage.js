import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import { toContentItem, rcRootCrumbs, CRUMB_HELP_HOME, CRUMB_RC_HOME } from 'c/rcConstants';
import { indexTree, findNode } from 'c/treeUtil';

const PREVIEW_MAX = 3;
const GENERAL_SECTION = 'general';
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
 * Pages (any depth), the same shape at every level:
 *  - Section cards (c-ds-section-cards), one per direct subcategory from
 *    CategoryDetail.subcategories (description, "N sections · M resources",
 *    a preview of its first resources), keyed by slug.
 *  - Then the category's own resources as cards (c-ds-item-list, cards
 *    variant) — or, when it has none of its own, the resources inherited
 *    from its children grouped under linked child headings, capped with a
 *    "View all" link. A leaf goes straight to its own resources. Every
 *    category is its own page — deep links land here directly.
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
    }

    // ---- View model ----------------------------------------------------------

    /** One per direct child holding that child's whole subtree (server-built),
        plus the trailing 'general' section of the category's own resources. */
    get sections() {
        return (this.detail && this.detail.sections) || [];
    }

    sectionFor(slug) {
        const section = this.sections.find((s) => s.key === slug);
        return (section && section.resources) || [];
    }

    /** Section cards: EVERY active direct subcategory (CategoryDetail.subcategories
        is unpruned, unlike the sidebar tree, so an empty one still cards and
        reads "0 resources"), keyed by slug — the routing key. */
    get sectionCardItems() {
        return ((this.detail && this.detail.subcategories) || []).map((t) => ({
            key: t.slug,
            label: t.name,
            description: t.description,
            sectionCount: t.subcategoryCount || 0,
            descendantItemCount: t.resourceCount || 0,
            preview: this.sectionFor(t.slug).slice(0, PREVIEW_MAX).map((r) => ({ id: r.id, title: r.name }))
        }));
    }

    get showSectionCards() {
        return this.sectionCardItems.length > 0;
    }

    /** Resources shown on the category itself (home + "Also show in"). */
    get ownItems() {
        return ((this.detail && this.detail.resources) || []).map(toContentItem);
    }

    get ownHeading() {
        return this.detail ? `Resources in ${this.detail.name}` : '';
    }

    /** Inherited resources grouped by the child they hang from — only when
        the category has nothing of its own, so a branch never dead-ends. */
    get inheritedGroups() {
        if (this.ownItems.length) {
            return [];
        }
        return this.sections
            .filter((s) => s.key !== GENERAL_SECTION && (s.resources || []).length > 0)
            .map((s) => ({ key: s.key, label: s.title, items: s.resources.map(toContentItem) }));
    }

    get showList() {
        return this.ownItems.length > 0 || this.inheritedGroups.length > 0;
    }

    /** True empty: nothing on the category and nothing anywhere under it. */
    get isEmpty() {
        return Boolean(this.detail) && !this.showList;
    }

    /** Tree keys are category Ids; the routed key is the slug. */
    get activeKey() {
        return this.detail ? this.detail.id : null;
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

    /** Sidebar rows are keyed by category Id; resolve to the routed slug. */
    handleNavSelect(event) {
        const node = findNode(this._navTree, event.detail.key);
        if (node) {
            this.fireCategorySelect(node.slug);
        }
    }

    /** Section cards and inherited-group headings are keyed by slug already. */
    handleSlugSelect(event) {
        if (event.detail.key) {
            this.fireCategorySelect(event.detail.key);
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