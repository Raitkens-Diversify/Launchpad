import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import { toContentItem, rcRootCrumbs, CRUMB_HELP_HOME, CRUMB_RC_HOME } from 'c/rcConstants';
import getCategoryBySlug from '@salesforce/apex/ResourceCenterService.getCategoryBySlug';
import getCategoryNav from '@salesforce/apex/ResourceCenterService.getCategoryNav';

/**
 * resourceCategoryPage — the Resource Center's browse surface, mirroring the
 * Help Center's topic browser (nexsArticleBrowser): a persistent left
 * "All topics" sidebar (shared c-ds-topic-nav) beside the topic content.
 *
 * The sidebar differs from the Help Center in one deliberate way: it is an
 * accordion — the main topic that owns the current page expands to show its
 * (non-empty) subtopics; every other branch stays collapsed. Expansion is
 * derived from the routed slug, so clicking another topic collapses the
 * previous branch for free.
 *
 * Landing: with no routed slug the page falls back to the FIRST topic in
 * the sidebar, exactly as the Help Center's browser falls back to
 * categories[0] (nexsArticleBrowser.applyInitialState). That is what makes
 * the Resources tab land on the same browse shape as Help Articles instead
 * of a bespoke landing page.
 *
 * Pages:
 *  - Main topic (slug has no parent): collapsible subtopic sections (first
 *    open), direct-filed resources trailing in "General resources"; topics
 *    with at most one section render the plain card grid.
 *  - Subtopic (slug has a parent): flat card grid of its own resources with
 *    a Help & Resources › Resource Center › Parent › Subtopic crumb. Subtopic slugs are their
 *    own pages — deep links land here directly.
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
    navTopics = [];

    @wire(getCategoryNav)
    wiredNav({ data }) {
        if (data) {
            this.navTopics = data;
            this.resolveEffectiveSlug();
        }
    }

    /** A routed slug always wins; otherwise land on the first topic. The
        nav wire is unparameterised, so it resolves even with no slug —
        without this the detail wire would never fire and the page would
        spin forever. */
    resolveEffectiveSlug() {
        const first = this.navTopics.length ? this.navTopics[0].slug : undefined;
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
        const sections = data.sections || [];
        // Help Center convention: first section open, rest collapsed.
        this.openKeys = new Set(sections.length ? [sections[0].key] : []);
    }

    // ---- View model ----------------------------------------------------------

    get sections() {
        return (this.detail && this.detail.sections) || [];
    }

    get isSubtopicPage() {
        return Boolean(this.detail && this.detail.parentSlug);
    }

    /** Section chrome only earns its place on a main topic with 2+ groups;
        subtopic pages and single-section topics render the plain grid. */
    get useSections() {
        return !this.isSubtopicPage && this.sections.length > 1;
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

    /** The main topic that owns the current page (self, or the parent). */
    get activeTopSlug() {
        if (!this.detail) {
            return null;
        }
        return this.detail.parentSlug || this.detail.slug;
    }

    get navItems() {
        const currentSlug = this.detail ? this.detail.slug : null;
        return (this.navTopics || []).map((t) => ({
            key: t.slug,
            label: t.name,
            iconPath: iconPath(t.iconName),
            active: t.slug === currentSlug,
            expanded: t.slug === this.activeTopSlug,
            children: (t.children || []).map((ch) => ({
                key: ch.slug,
                label: ch.name,
                active: ch.slug === currentSlug
            }))
        }));
    }

    get crumbItems() {
        const crumbs = rcRootCrumbs();
        if (this.detail && this.detail.parentSlug) {
            crumbs.push({ label: this.detail.parentName, key: this.detail.parentSlug });
        }
        if (this.detail) {
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
        this.fireCategorySelect(event.detail.key);
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