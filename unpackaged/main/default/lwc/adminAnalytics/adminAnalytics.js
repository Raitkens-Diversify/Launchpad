import { LightningElement } from 'lwc';
import getEngagementSummary from '@salesforce/apex/ArticleAdminController.getEngagementSummary';
import listSearches from '@salesforce/apex/ArticleAdminController.listSearches';
import listViews from '@salesforce/apex/ArticleAdminController.listViews';
import getArticleEngagement from '@salesforce/apex/ArticleAdminController.getArticleEngagement';

const PAGE_SIZE = 50;

/**
 * adminAnalytics — the console's engagement destination. A summary of cards
 * (most viewed, feedback, top searches, zero-result searches) with drill-down
 * views so every captured data point is at most one click away:
 *   - searches: the complete raw search log (term filter, zero-only toggle)
 *   - views: the complete view log (who read what, when, how often)
 *   - article: everything about one article (viewers, feedback, click-throughs)
 * Article titles are clickable wherever they appear.
 */
export default class AdminAnalytics extends LightningElement {
    view = 'summary'; // summary | searches | views | article
    surface = '';

    summary;
    loading = true;
    errorMessage;

    // Searches drill-down
    searchRows = [];
    searchTerm = '';
    zeroOnly = false;
    searchesLoading = false;
    searchesExhausted = false;

    // Views drill-down
    viewRows = [];
    viewsLoading = false;
    viewsExhausted = false;

    // Article drill-down
    articleDetail;
    articleLoading = false;
    articleReturnView = 'summary';

    _searchDebounce;

    connectedCallback() {
        this.loadSummary();
    }

    disconnectedCallback() {
        clearTimeout(this._searchDebounce);
    }

    // ---- Data loads -------------------------------------------------------

    async loadSummary() {
        this.loading = true;
        try {
            this.summary = await getEngagementSummary({
                surface: this.surface || null
            });
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = this.messageOf(e);
        } finally {
            this.loading = false;
        }
    }

    async loadSearches(reset) {
        if (reset) {
            this.searchRows = [];
            this.searchesExhausted = false;
        }
        this.searchesLoading = true;
        try {
            const last = this.searchRows[this.searchRows.length - 1];
            const rows = await listSearches({
                surface: this.surface || null,
                termFilter: this.searchTerm || null,
                zeroOnly: this.zeroOnly,
                beforeCursor: reset || !last ? null : last.createdDate
            });
            this.searchRows = [...this.searchRows, ...rows];
            this.searchesExhausted = rows.length < PAGE_SIZE;
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = this.messageOf(e);
        } finally {
            this.searchesLoading = false;
        }
    }

    async loadViews(reset) {
        if (reset) {
            this.viewRows = [];
            this.viewsExhausted = false;
        }
        this.viewsLoading = true;
        try {
            const last = this.viewRows[this.viewRows.length - 1];
            const rows = await listViews({
                surface: this.surface || null,
                beforeCursor: reset || !last ? null : last.lastViewed
            });
            this.viewRows = [...this.viewRows, ...rows];
            this.viewsExhausted = rows.length < PAGE_SIZE;
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = this.messageOf(e);
        } finally {
            this.viewsLoading = false;
        }
    }

    async loadArticle(articleId) {
        this.articleLoading = true;
        try {
            this.articleDetail = await getArticleEngagement({ articleId });
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = this.messageOf(e);
        } finally {
            this.articleLoading = false;
        }
    }

    messageOf(e) {
        return (e && e.body && e.body.message) || 'Could not load analytics.';
    }

    // ---- View state ---------------------------------------------------------

    get isSummary() {
        return this.view === 'summary';
    }

    get isSearchesView() {
        return this.view === 'searches';
    }

    get isViewsView() {
        return this.view === 'views';
    }

    get isArticleView() {
        return this.view === 'article';
    }

    get ready() {
        return !this.loading && !!this.summary;
    }

    get surfaceOptions() {
        const options = [{ label: 'All surfaces', value: '' }];
        ((this.summary && this.summary.surfaces) || []).forEach((s) =>
            options.push({ label: s, value: s })
        );
        return options;
    }

    // ---- Summary getters ------------------------------------------------------

    get topViewedRows() {
        if (!this.ready) {
            return [];
        }
        return this.summary.topViewed.map((item) => ({
            ...item,
            clickable: !!item.key
        }));
    }

    get feedbackRows() {
        if (!this.ready) {
            return [];
        }
        return this.summary.recentComments.map((item, i) => ({
            ...item,
            rowKey: `${item.createdDate}-${i}`,
            who: item.authorName || 'Unknown user',
            clickable: !!item.articleId
        }));
    }

    get hasViews() {
        return this.ready && this.summary.topViewed.length > 0;
    }

    get hasComments() {
        return this.ready && this.summary.recentComments.length > 0;
    }

    get hasSearches() {
        return this.ready && this.summary.topSearches.length > 0;
    }

    get hasGaps() {
        return this.ready && this.summary.zeroResultSearches.length > 0;
    }

    get voteSummary() {
        if (!this.ready) {
            return '';
        }
        return `${this.summary.upVotes} up · ${this.summary.downVotes} down`;
    }

    // ---- Drill-down getters -----------------------------------------------------

    get searchTableRows() {
        return this.searchRows.map((row) => ({
            ...row,
            who: row.userName || 'Unknown user',
            clickedLabel: row.clickedTitle || '—',
            clickable: !!row.clickedArticleId,
            rowClass: row.resultCount === 0 ? 'aan__tr aan__tr--gap' : 'aan__tr'
        }));
    }

    get viewTableRows() {
        return this.viewRows.map((row, i) => ({
            ...row,
            rowKey: `${row.articleId}-${row.userName}-${i}`,
            who: row.userName || 'Unknown user',
            clickable: !!row.articleId
        }));
    }

    get hasSearchRows() {
        return this.searchRows.length > 0;
    }

    get hasViewRows() {
        return this.viewRows.length > 0;
    }

    get showSearchesEmpty() {
        return !this.searchesLoading && !this.hasSearchRows;
    }

    get showViewsEmpty() {
        return !this.viewsLoading && !this.hasViewRows;
    }

    get canLoadMoreSearches() {
        return !this.searchesLoading && !this.searchesExhausted && this.hasSearchRows;
    }

    get canLoadMoreViews() {
        return !this.viewsLoading && !this.viewsExhausted && this.hasViewRows;
    }

    get articleReady() {
        return !this.articleLoading && !!this.articleDetail;
    }

    get articleVoteSummary() {
        if (!this.articleReady) {
            return '';
        }
        return `${this.articleDetail.upVotes} up · ${this.articleDetail.downVotes} down`;
    }

    get articleViewers() {
        if (!this.articleReady) {
            return [];
        }
        return this.articleDetail.viewers.map((row, i) => ({
            ...row,
            rowKey: `${row.userName}-${i}`,
            who: row.userName || 'Unknown user'
        }));
    }

    get articleFeedback() {
        if (!this.articleReady) {
            return [];
        }
        return this.articleDetail.feedback.map((item, i) => ({
            ...item,
            rowKey: `${item.createdDate}-${i}`,
            who: item.authorName || 'Unknown user',
            commentLabel: item.comment || '—'
        }));
    }

    get articleSearches() {
        if (!this.articleReady) {
            return [];
        }
        return this.articleDetail.searches.map((row) => ({
            ...row,
            who: row.userName || 'Unknown user'
        }));
    }

    get hasArticleViewers() {
        return this.articleViewers.length > 0;
    }

    get hasArticleFeedback() {
        return this.articleFeedback.length > 0;
    }

    get hasArticleSearches() {
        return this.articleSearches.length > 0;
    }

    // ---- Handlers -----------------------------------------------------------------

    handleSurfaceChange(event) {
        this.surface = event.detail.value;
        this.loadSummary();
        if (this.isSearchesView) {
            this.loadSearches(true);
        } else if (this.isViewsView) {
            this.loadViews(true);
        }
    }

    handleRefresh() {
        this.loadSummary();
        if (this.isSearchesView) {
            this.loadSearches(true);
        } else if (this.isViewsView) {
            this.loadViews(true);
        } else if (this.isArticleView && this.articleDetail) {
            this.loadArticle(this.articleDetail.articleId);
        }
    }

    handleOpenSearches() {
        this.view = 'searches';
        this.zeroOnly = false;
        this.searchTerm = '';
        this.loadSearches(true);
    }

    handleOpenGaps() {
        this.view = 'searches';
        this.zeroOnly = true;
        this.searchTerm = '';
        this.loadSearches(true);
    }

    handleOpenViews() {
        this.view = 'views';
        this.loadViews(true);
    }

    handleBackToSummary() {
        this.view = 'summary';
        this.loadSummary();
    }

    handleArticleClick(event) {
        const articleId = event.currentTarget.dataset.id;
        if (!articleId) {
            return;
        }
        this.articleReturnView = this.view;
        this.view = 'article';
        this.articleDetail = undefined;
        this.loadArticle(articleId);
    }

    handleArticleBack() {
        this.view = this.articleReturnView;
        if (this.view === 'summary') {
            this.loadSummary();
        }
    }

    handleSearchTermChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchDebounce);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchDebounce = setTimeout(() => this.loadSearches(true), 300);
    }

    handleZeroOnlyChange(event) {
        this.zeroOnly = event.target.checked;
        this.loadSearches(true);
    }

    handleLoadMoreSearches() {
        this.loadSearches(false);
    }

    handleLoadMoreViews() {
        this.loadViews(false);
    }
}