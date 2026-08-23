import { LightningElement, api, wire } from 'lwc';
import getCategories from '@salesforce/apex/NexSKnowledgeController.getCategories';
import getArticlesByCategory from '@salesforce/apex/NexSKnowledgeController.getArticlesByCategory';
import getArticle from '@salesforce/apex/NexSKnowledgeController.getArticle';
// Shared Help_Topics icon paths (rendered with stroke=currentColor).
import { topicIconPath } from 'c/nexsTopicIcons';
// This component owns the guided tour's data-tour-id targets; registering the
// template lets the tour engine find them in every sandbox mode (walking in
// from outside is severed by platform shadow roots on core pages).
import { registerTourScope } from 'c/tourDom';

const MAX_POPULAR = 6;

/**
 * nexsHome
 *
 * Hulu-style help center home: navy hero with headline + search, "Popular help
 * articles" (Featured__c-first, via the existing controller ordering), and an
 * icon-led topic grid built from the live Help_Topics taxonomy.
 *
 * Surface-agnostic like its siblings: it does no navigation, only emits events
 * and lets the host (nexsLanding) swap views, so it behaves identically in the
 * Experience Cloud LWR site and the core Lightning App.
 *
 * Events:
 *   topicselect   { name, label }  — a topic card was chosen
 *   articleselect { articleId }    — a popular article or search suggestion was chosen
 *   searchsubmit  { value }        — user asked for full results for a term
 *     (distinct name on purpose: c-nexs-search-bar's own composed `search`
 *      event bubbles through this component, including empty clear events)
 *   welcomedismiss                 — "Got it" on the first-login welcome banner
 */
export default class NexsHome extends LightningElement {
    /** Show the first-login "Welcome to NexS" video banner (host-owned state). */
    @api showWelcome = false;

    categories = [];
    articles = [];
    _prefetched = new Set(); // article ids whose bodies we've warmed on hover
    _unregisterTourScope = null;

    connectedCallback() {
        this._unregisterTourScope = registerTourScope(this.template);
    }

    disconnectedCallback() {
        if (this._unregisterTourScope) {
            this._unregisterTourScope();
            this._unregisterTourScope = null;
        }
    }

    @wire(getCategories)
    wiredCategories({ data, error }) {
        if (data) {
            this.categories = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('nexsHome category load error', error);
        }
    }

    @wire(getArticlesByCategory, { category: null })
    wiredArticles({ data, error }) {
        if (data) {
            this.articles = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('nexsHome popular articles load error', error);
        }
    }

    get topicItems() {
        return this.categories.map((c) => ({
            ...c,
            iconPath: topicIconPath(c.name)
        }));
    }

    // Controller already orders Featured__c DESC; keep the featured rows (or
    // fall back to the top of the list while nothing is flagged yet).
    get popularArticles() {
        const rows = this.articles || [];
        const featured = rows.filter((a) => a.featured);
        return (featured.length ? featured : rows).slice(0, MAX_POPULAR);
    }

    // Column-major split for the Hulu-style two-column row blocks.
    get popularColumns() {
        const rows = this.popularArticles;
        const splitAt = Math.ceil(rows.length / 2);
        return [
            { key: 'col-1', rows: rows.slice(0, splitAt) },
            { key: 'col-2', rows: rows.slice(splitAt) }
        ].filter((col) => col.rows.length);
    }

    get hasPopular() {
        return this.popularArticles.length > 0;
    }

    get hasTopics() {
        return this.categories.length > 0;
    }

    handleTopicClick(event) {
        const { name, label } = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('topicselect', { detail: { name, label } }));
    }

    // "See all topics" beside the Popular Topics heading: same hand-off as a
    // topic card but with no topic named, so the browser lands on its default
    // (first) topic with the full All-topics nav.
    handleSeeAllTopics(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('topicselect', { detail: { name: null, label: null } }));
    }

    handleArticleClick(event) {
        event.preventDefault(); // rows are anchors; don't jump the page
        const { id, urlname } = event.currentTarget.dataset;
        this.dispatchEvent(
            new CustomEvent('articleselect', {
                detail: { articleId: id, urlName: urlname }
            })
        );
    }

    // Warm the (cacheable) article body cache on hover/focus so opening a
    // popular article from the home page feels instant.
    handlePrefetch(event) {
        const id = event.currentTarget.dataset.id;
        if (!id || this._prefetched.has(id)) {
            return;
        }
        this._prefetched.add(id);
        getArticle({ articleId: id }).catch(() => this._prefetched.delete(id));
    }

    // A suggestion was picked in the hero search bar.
    handleSuggestionSelect(event) {
        this.dispatchEvent(
            new CustomEvent('articleselect', {
                detail: { articleId: event.detail.articleId, urlName: event.detail.urlName }
            })
        );
    }

    // "Got it" on the welcome banner — the host owns the visibility state.
    handleWelcomeDismiss() {
        this.dispatchEvent(new CustomEvent('welcomedismiss'));
    }

    // "View all results" (or Enter) in the hero search bar.
    handleSearch(event) {
        const value = (event.detail && event.detail.value) || '';
        if (!value.trim()) {
            return; // clearing the box on home is a no-op
        }
        this.dispatchEvent(new CustomEvent('searchsubmit', { detail: { value } }));
    }
}