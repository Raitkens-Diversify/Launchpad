import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
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
 * Pages:
 *  - Main topic (slug has no parent): collapsible subtopic sections (first
 *    open), direct-filed resources trailing in "General resources"; topics
 *    with at most one section render the plain card grid.
 *  - Subtopic (slug has a parent): flat card grid of its own resources with
 *    a Resource Center › Parent › Subtopic crumb. Subtopic slugs are their
 *    own pages — deep links land here directly.
 *
 * Emits (composed) `categoryselect { slug }`, `rchome`. Resource card events
 * bubble to the orchestrator.
 */
export default class ResourceCategoryPage extends LightningElement {
    @api slug;

    detail;
    error;
    loading = true;
    openKeys = new Set();
    navTopics = [];

    @wire(getCategoryNav)
    wiredNav({ data }) {
        if (data) {
            this.navTopics = data;
        }
    }

    @wire(getCategoryBySlug, { slug: '$slug' })
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
        const crumbs = [{ label: 'Resource Center', key: 'home' }];
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
        if (key === 'home') {
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

    handleHome() {
        this.dispatchEvent(new CustomEvent('rchome', { bubbles: true, composed: true }));
    }

    reduce(error) {
        return (error && error.body && error.body.message) || 'Something went wrong.';
    }
}