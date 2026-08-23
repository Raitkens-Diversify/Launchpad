import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listArticles from '@salesforce/apex/ArticleAdminController.listArticles';
import getAuthoringMeta from '@salesforce/apex/ArticleAdminController.getAuthoringMeta';
import unpublishArticle from '@salesforce/apex/ArticleAdminController.unpublishArticle';
import discardDraft from '@salesforce/apex/ArticleAdminController.discardDraft';

/**
 * adminArticleList — Admin Console article overview: one row per article with
 * status, topics, and quick actions. Emits `edit` { kaId } and `create`.
 */
const STATUS_OPTIONS = [
    { label: 'All statuses', value: '' },
    { label: 'Draft', value: 'Draft' },
    { label: 'Online', value: 'Online' },
    { label: 'Online + draft', value: 'Online + draft' }
];

export default class AdminArticleList extends LightningElement {
    rows = [];
    loading = true;
    errorMessage;

    searchTerm = '';
    statusFilter = '';
    categoryFilter = '';
    featuredOnly = false;
    categoryOptions = [{ label: 'All topics', value: '' }];

    confirm; // { kaId, title, action: 'unpublish' | 'discard' }

    connectedCallback() {
        this.load();
        this.loadMeta();
    }

    async load() {
        this.loading = true;
        try {
            const data = await listArticles();
            this.rows = (data || []).map((r) => this.decorate(r));
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage =
                (e && e.body && e.body.message) || 'Could not load articles.';
        } finally {
            this.loading = false;
        }
    }

    async loadMeta() {
        try {
            const meta = await getAuthoringMeta();
            const options = [{ label: 'All topics', value: '' }];
            (meta.categoryTree || []).forEach((topic) => {
                options.push({ label: topic.label, value: topic.label });
                (topic.children || []).forEach((sub) => {
                    options.push({ label: '— ' + sub.label, value: sub.label });
                });
            });
            this.categoryOptions = options;
        } catch (e) {
            // filter dropdown degrades to "All topics" — the list still works
        }
    }

    decorate(row) {
        const statusClass =
            row.status === 'Online'
                ? 'aal-badge aal-badge--online'
                : row.status === 'Draft'
                  ? 'aal-badge aal-badge--draft'
                  : 'aal-badge aal-badge--pending';
        return {
            ...row,
            statusClass,
            categoriesLabel: (row.categoryLabels || []).join(', '),
            // Unpublish (editOnlineArticle) fails while a draft is pending, so it
            // is only offered on plain-Online rows; discard the draft first.
            isOnline: row.status === 'Online',
            hasDraft: row.status !== 'Online'
        };
    }

    // ---- Filters ------------------------------------------------------------------

    get statusOptions() {
        return STATUS_OPTIONS;
    }

    get filteredRows() {
        const term = this.searchTerm.trim().toLowerCase();
        return this.rows.filter((row) => {
            if (this.statusFilter && row.status !== this.statusFilter) {
                return false;
            }
            if (this.featuredOnly && !row.featured) {
                return false;
            }
            if (
                this.categoryFilter &&
                !(row.categoryLabels || []).includes(this.categoryFilter)
            ) {
                return false;
            }
            if (
                term &&
                !(row.title || '').toLowerCase().includes(term) &&
                !(row.urlName || '').toLowerCase().includes(term)
            ) {
                return false;
            }
            return true;
        });
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }
    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
    }
    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
    }
    handleFeaturedChange(event) {
        this.featuredOnly = event.target.checked;
    }

    // ---- Actions -------------------------------------------------------------------

    handleCreate() {
        this.dispatchEvent(new CustomEvent('create'));
    }

    handleEdit(event) {
        this.dispatchEvent(
            new CustomEvent('edit', {
                detail: { kaId: event.currentTarget.dataset.kaid }
            })
        );
    }

    handleRefresh() {
        this.load();
    }

    handleUnpublishClick(event) {
        this.confirm = {
            kaId: event.currentTarget.dataset.kaid,
            title: event.currentTarget.dataset.title,
            action: 'unpublish',
            message:
                'Readers will stop seeing this article on the Help Center. Its content is kept as a draft you can republish later.',
            confirmLabel: 'Unpublish'
        };
    }

    handleDiscardClick(event) {
        this.confirm = {
            kaId: event.currentTarget.dataset.kaid,
            title: event.currentTarget.dataset.title,
            action: 'discard',
            message:
                'The pending draft is deleted. If a published version exists, it stays online unchanged.',
            confirmLabel: 'Discard draft'
        };
    }

    handleConfirmCancel() {
        this.confirm = undefined;
    }

    async handleConfirmProceed() {
        const { kaId, action } = this.confirm;
        this.confirm = undefined;
        this.loading = true;
        try {
            if (action === 'unpublish') {
                await unpublishArticle({ kaId });
                this.toast('success', 'Article unpublished — its content is now a draft.');
            } else {
                await discardDraft({ kaId });
                this.toast('success', 'Draft discarded.');
            }
        } catch (e) {
            this.toast('error', (e && e.body && e.body.message) || 'The action failed.');
        }
        this.load();
    }

    toast(variant, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: variant === 'error' ? 'Error' : 'Success',
                message,
                variant
            })
        );
    }
}