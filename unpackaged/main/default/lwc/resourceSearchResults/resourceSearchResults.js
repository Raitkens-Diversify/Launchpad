import { LightningElement, api, wire } from 'lwc';
import search from '@salesforce/apex/UnifiedSearchService.search';
import { createSearchLogger, APP_RESOURCE_CENTER } from 'c/searchLogUtil';
import { linkContext, goToArticle } from 'c/contextNav';
import { toContentItem } from 'c/rcConstants';

/**
 * resourceSearchResults — the shared cross-app results view: grouped Articles /
 * Resources sections (ranked within each by UnifiedSearchService), rendered as
 * c-ds-content-card tiles. Resources open in-site (emits `resourceselect
 * { slug }`) unless their action leaves the site (External Link, an upcoming
 * webinar's "Sign up") — rcConstants.toContentItem decides, same as every other
 * card grid. Articles carry an href deep link into the Help Center. Either side
 * can be degraded (no access / backend fault) — the other still renders, with a
 * quiet notice instead of a hard error.
 */
export default class ResourceSearchResults extends LightningElement {
    @api term;
    /** Optional override; defaults to the site root resolved server-side. */
    @api helpCenterBaseUrl;

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
    }

    articleHits = [];
    resourceHits = [];
    meta = {};
    loading = true;
    // Fire-and-forget analytics: one row per submitted term (the wire can
    // re-emit the same term; searchLogUtil dedupes consecutive repeats).
    // search is cacheable Apex, so it can't log server-side.
    _searchLogger = createSearchLogger(APP_RESOURCE_CENTER);

    disconnectedCallback() {
        this._searchLogger.dispose();
    }

    @wire(search, { term: '$term' })
    wiredResults({ data }) {
        if (!data) {
            return;
        }
        this.articleHits = data.articles || [];
        this.resourceHits = data.resources || [];
        this.meta = data.meta || {};
        this.loading = false;
        this._searchLogger.logFull({
            term: this.term,
            resultCount: this.articleHits.length + this.resourceHits.length,
            topResultArticleId: this.articleHits.length ? this.articleHits[0].id : null,
            searchType: this.meta.fuzzy ? 'Fuzzy' : 'Full'
        });
    }

    get resourceItems() {
        return this.resourceHits.map(toContentItem);
    }

    /** Articles carry NO href on purpose — dsContentCard reserves that for
        links that truly leave the site. See handleContentSelect. */
    get articleItems() {
        return this.articleHits.map((a) => ({
            kind: 'article',
            id: a.id,
            title: a.title,
            subtitle: a.summary,
            routeKey: a.urlName
        }));
    }

    get hasResources() {
        return this.resourceHits.length > 0;
    }
    get hasArticles() {
        return this.articleHits.length > 0;
    }
    get isEmpty() {
        return !this.loading && !this.hasResources && !this.hasArticles;
    }
    get articlesDegraded() {
        return this.meta.articlesDegraded === true;
    }
    get resourcesDegraded() {
        return this.meta.resourcesDegraded === true;
    }
    get showFuzzy() {
        return this.meta.fuzzy === true && Boolean(this.meta.corrected);
    }

    handleContentSelect(event) {
        event.stopPropagation();
        if (event.detail.kind === 'article') {
            // No mixin here, so contextNav takes its event rung and the
            // host routes. Previously this branch returned early and the
            // click was simply dropped.
            goToArticle(this, this.linkCtx, { urlName: event.detail.routeKey });
            return;
        }
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug: event.detail.routeKey }, bubbles: true, composed: true
        }));
    }
}