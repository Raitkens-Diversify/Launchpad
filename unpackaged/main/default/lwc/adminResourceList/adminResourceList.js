import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { resourceDetailUrl, copyText } from 'c/rcLinkUtil';
import listResources from '@salesforce/apex/ResourceAdminController.listResources';
import getCategoryTree from '@salesforce/apex/ResourceAdminController.getCategoryTree';
import getResourceLinkBase from '@salesforce/apex/ResourceCenterService.getResourceLinkBase';
import { indexTree, descendantsOf, optionsFor } from 'c/treeUtil';
import {
    RESOURCE_TYPES,
    toOptions,
    WEBINAR_STATUS_UPCOMING,
    WEBINAR_STATUS_PAST,
    WEBINAR_STATUS_RECORDED
} from 'c/rcConstants';

/**
 * adminResourceList — Admin Console resource overview with filters and quick
 * actions. Emits `edit` { resourceId } and `create`. Each row offers "Copy
 * link" — the shareable Resource Center URL, pasteable into article bodies.
 *
 * Webinars carry a lifecycle chip (server-derived `webinarStatus`, never
 * re-derived here) and a "Webinar status" filter — "Needs recording" is the
 * coordination view: past webinars still missing a recording, oldest first.
 */
const TYPE_OPTIONS = [{ label: 'All types', value: '' }].concat(toOptions(RESOURCE_TYPES));
/** webinarStatus → chip. Past reads as the admin's to-do, not a neutral fact. */
const LIFECYCLE = {
    [WEBINAR_STATUS_UPCOMING]: { label: 'Upcoming', variant: 'info' },
    [WEBINAR_STATUS_PAST]: { label: 'Needs recording', variant: 'warning' },
    [WEBINAR_STATUS_RECORDED]: { label: 'Recorded', variant: 'success' }
};
const LIFECYCLE_OPTIONS = [{ label: 'All webinar statuses', value: '' }].concat(
    Object.keys(LIFECYCLE).map((status) => ({ label: LIFECYCLE[status].label, value: status }))
);

export default class AdminResourceList extends LightningElement {
    rows = [];
    loading = true;
    errorMessage;

    searchTerm = '';
    typeFilter = '';
    categoryFilter = '';
    lifecycleFilter = '';
    activeOnly = false;
    categoryOptions = [{ label: 'All categories', value: '' }];
    _categoryTree = indexTree([]);
    linkBase = null;

    connectedCallback() {
        this.load();
        this.loadCategories();
        getResourceLinkBase()
            .then((base) => {
                this.linkBase = base || null;
            })
            .catch(() => {
                this.linkBase = null;
            });
    }

    async load() {
        this.loading = true;
        try {
            const data = await listResources();
            this.rows = (data || []).map((r) => {
                const lifecycle = LIFECYCLE[r.webinarStatus];
                const secondary = r.secondaryCategoryNames || [];
                return {
                    ...r,
                    secondaryCategoryNames: secondary,
                    secondaryCount: secondary.length,
                    moreLabel: `+${secondary.length} more`,
                    // Hover reveals every placement: home first, then "Also show in".
                    categoryTitle: [r.categoryName, ...secondary].filter(Boolean).join(', '),
                    statusLabel: r.active ? 'Active' : 'Inactive',
                    statusClass: r.active
                        ? 'arl-badge arl-badge--on'
                        : 'arl-badge arl-badge--off',
                    lifecycleLabel: lifecycle ? lifecycle.label : undefined,
                    lifecycleVariant: lifecycle ? lifecycle.variant : undefined
                };
            });
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage =
                (e && e.body && e.body.message) || 'Could not load resources.';
        } finally {
            this.loading = false;
        }
    }

    /**
     * The whole category tree drives the filter: every category at any depth,
     * indented by level, and picking one includes everything below it. (Row
     * names alone could not express "and its subtopics".)
     */
    async loadCategories() {
        try {
            const dto = await getCategoryTree();
            this._categoryTree = indexTree((dto && dto.roots) || []);
            this.categoryOptions = [
                { label: 'All categories', value: '' },
                ...optionsFor(this._categoryTree, null, dto && dto.maxDepth ? dto.maxDepth : 5)
                    .map((o) => ({ label: o.label, value: o.value }))
            ];
        } catch (e) {
            // Filter degrades to "All categories" — the list still works.
        }
    }

    get typeOptions() {
        return TYPE_OPTIONS;
    }
    get lifecycleOptions() {
        return LIFECYCLE_OPTIONS;
    }

    get filteredRows() {
        const term = this.searchTerm.trim().toLowerCase();
        const rows = this.rows.filter((row) => {
            if (this.typeFilter && row.resourceType !== this.typeFilter) {
                return false;
            }
            // A lifecycle filter implies webinars only (other types have none).
            if (this.lifecycleFilter && row.webinarStatus !== this.lifecycleFilter) {
                return false;
            }
            // A category filter matches the home OR any "Also show in"
            // placement, in the picked category or anywhere below it.
            if (this.categoryFilter && !this.inCategoryScope(row)) {
                return false;
            }
            if (this.activeOnly && !row.active) {
                return false;
            }
            if (
                term &&
                !(row.name || '').toLowerCase().includes(term) &&
                !(row.slug || '').toLowerCase().includes(term)
            ) {
                return false;
            }
            return true;
        }).map((row) => ({
            ...row,
            copyUrl: resourceDetailUrl(this.linkBase, row.slug)
        }));
        if (this.lifecycleFilter) {
            // Upcoming: soonest first. Past/Recorded: most recent first.
            const dir = this.lifecycleFilter === WEBINAR_STATUS_UPCOMING ? 1 : -1;
            rows.sort((a, b) => dir * (Date.parse(a.eventDatetime || 0) - Date.parse(b.eventDatetime || 0)));
        }
        return rows;
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    /** Ids of the filtered category and everything under it (empty = no filter). */
    get categoryScopeIds() {
        if (!this.categoryFilter) {
            return null;
        }
        const ids = new Set([this.categoryFilter]);
        descendantsOf(this._categoryTree, this.categoryFilter).forEach((n) => ids.add(n.id));
        return ids;
    }

    inCategoryScope(row) {
        const scope = this.categoryScopeIds;
        if (!scope) {
            return true;
        }
        return scope.has(row.categoryId)
            || (row.secondaryCategoryIds || []).some((id) => scope.has(id));
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }
    handleTypeChange(event) {
        this.typeFilter = event.detail.value;
    }
    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
    }
    handleLifecycleChange(event) {
        this.lifecycleFilter = event.detail.value;
    }
    handleActiveChange(event) {
        this.activeOnly = event.target.checked;
    }
    handleRefresh() {
        this.load();
    }

    handleCreate() {
        this.dispatchEvent(new CustomEvent('create'));
    }

    handleEdit(event) {
        this.dispatchEvent(
            new CustomEvent('edit', {
                detail: { resourceId: event.currentTarget.dataset.id }
            })
        );
    }

    async handleCopyLink(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) {
            return;
        }
        try {
            await copyText(url);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Link copied',
                    message: 'Shareable Resource Center link — paste it anywhere, including article bodies.',
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not copy',
                    message: url,
                    variant: 'warning'
                })
            );
        }
    }
}