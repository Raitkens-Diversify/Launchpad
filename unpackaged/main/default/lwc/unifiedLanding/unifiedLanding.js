import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import unifiedTypeahead from '@salesforce/apex/UnifiedSearchService.typeahead';
import getSupportSettings from '@salesforce/apex/NexSKnowledgeController.getSupportSettings';
import getHelpTopicTree from '@salesforce/apex/NexSKnowledgeController.getCategoryTree';
import getFallbackArticles from '@salesforce/apex/NexSKnowledgeController.getFallbackArticles';
import getResourceTree from '@salesforce/apex/ResourceCenterService.getCategoryTree';
import getFeaturedResources from '@salesforce/apex/ResourceCenterService.getFeaturedResources';
import getEvents from '@salesforce/apex/ResourceCenterService.getEvents';
import { topicIconPath } from 'c/nexsTopicIcons';
import { iconPath } from 'c/rcIcons';
import { indexTree, findNode } from 'c/treeUtil';
import { toContentItem } from 'c/rcConstants';
import {
    linkContext,
    readParams,
    goToArticle,
    goToResource,
    goToEvents
} from 'c/contextNav';
import { createSuggestionFetcher } from 'c/dsSearchBar';
import { createSearchLogger, logSearchEntry, APP_LANDING } from 'c/searchLogUtil';
import { registerTourScope } from 'c/tourDom';

/** A directory row: the main topic alone. Dropping the branch removes the
    c-ds-tree chevron (no peeking subtopics on the home page), and the home
    page shows NO counts (user decision 2026-09-06) — the count line and the
    branch belong on the topic's own page. */
function topLevel(node) {
    return { ...node, children: [], hasChildren: false };
}

/**
 * unifiedLanding — the shared front door for the Help Center + Resource Center
 * (replaces nexsLanding on the /help/ home route per the 2026-08 unification
 * plan, decision D3; also exposed as a core-app tab). Routes people to the
 * right article or resource:
 *   - hero search over BOTH apps (UnifiedSearchService: merged typeahead;
 *     submitted searches render the shared grouped results view inline)
 *   - side-by-side topic directories (help topics / resource categories —
 *     deliberately NOT merged; see the audit's taxonomy findings), tiles
 *     deep-linking into each app
 *   - featured strip mixing Featured articles and Featured resources
 *   - the shared support band
 *   - the events surface: a dismissible next-event banner under the hero
 *     (c-event-banner, fed upcoming[0] from getEvents) and an "Upcoming
 *     Events" chrome action with a count badge routing to /help/events
 *
 * Deep-link shim: the legacy /help/?article=<UrlName> form (every pre-route
 * link in the wild) redirects to the real /help/article route.
 *
 * Dual-surface rules as nexsLanding: inline view swaps, no community-only
 * imports. Cross-app navigation goes through c/contextNav, which routes to
 * the site by URL on Experience Cloud and to a Lightning tab by
 * PageReference in the core app — so core-app users never leave Lightning.
 */
export default class UnifiedLanding extends NavigationMixin(LightningElement) {
    /** @api hideBranding — passed through to c-ds-chrome (ARC embeddings
     *  carry their own site chrome); the chrome coerces string values. */
    @api hideBranding = false;

    logoUrl = diversifyLogo;
    @track view = 'home'; // 'home' | 'results'
    @track term = '';
    @track suggestions = [];

    unifiedSearchEnabled = true;
    events = { upcoming: [], past: [] };
    helpTopics = [];
    resourceCategories = [];
    featuredArticles = [];
    featuredResources = [];

    _lastSearchTerm;
    _fetchSuggestions = createSuggestionFetcher((term) => unifiedTypeahead({ term }));
    _searchLogger = createSearchLogger(APP_LANDING);
    _unregisterTourScope = null;
    _redirecting = false;

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    connectedCallback() {
        // Legacy ?article= deep links predate the /article route — forward them
        // instead of painting the landing. The param is read synchronously so
        // the landing never flashes; the hop itself waits on the surface, since
        // internally it is a tab navigation rather than a URL.
        const legacy = readParams(null).article;
        if (legacy) {
            this._redirecting = true;
            linkContext().then((ctx) => {
                this.linkCtx = ctx;
                goToArticle(this, ctx, { urlName: legacy });
            });
            return;
        }
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        this._unregisterTourScope = registerTourScope(this.template);
    }

    disconnectedCallback() {
        if (this._unregisterTourScope) {
            this._unregisterTourScope();
            this._unregisterTourScope = null;
        }
        this._searchLogger.dispose();
    }

    // ---- Wires ---------------------------------------------------------------

    @wire(getSupportSettings)
    wiredSettings({ data }) {
        if (data) {
            // Absent field / older server shape reads as enabled.
            this.unifiedSearchEnabled = data.unifiedSearchEnabled !== false;
        }
    }

    /** Both directories list main topics only (see topLevel()); the branch
        lives on the topic's own page, where the section cards and the sidebar show it. */
    @wire(getHelpTopicTree)
    wiredTopics({ data }) {
        if (data) {
            this.helpTopics = data.roots || [];
        }
    }

    _resourceTree = indexTree([]);

    @wire(getResourceTree)
    wiredResourceCategories({ data }) {
        if (data) {
            this.resourceCategories = data.roots || [];
            this._resourceTree = indexTree(this.resourceCategories);
        }
    }

    @wire(getFallbackArticles, { category: null })
    wiredFeaturedArticles({ data }) {
        if (data) {
            this.featuredArticles = data;
        }
    }

    @wire(getFeaturedResources)
    wiredFeaturedResources({ data }) {
        if (data) {
            this.featuredResources = data;
        }
    }

    @wire(getEvents)
    wiredEvents({ data }) {
        if (data) {
            this.events = data;
        }
    }

    // ---- Derived view --------------------------------------------------------

    get isHome() {
        return this.view === 'home';
    }
    get isResults() {
        return this.view === 'results';
    }
    get showHeaderSearch() {
        return this.unifiedSearchEnabled && this.isResults;
    }
    get showHeroSearch() {
        return this.unifiedSearchEnabled && this.isHome;
    }
    /** The next upcoming event feeds the banner; null hides it (the banner
        also self-hides when the user dismissed this exact event). */
    get nextEvent() {
        return (this.events.upcoming || [])[0] || null;
    }
    get upcomingCount() {
        return (this.events.upcoming || []).length;
    }
    get hasUpcomingCount() {
        return this.upcomingCount > 0;
    }

    /** Help topic roots for c-ds-tree (keys are Data Category API names). */
    get helpTopicRoots() {
        return (this.helpTopics || []).map((t) => topLevel({ ...t, iconPath: topicIconPath(t.id) }));
    }

    /** Resource category roots for c-ds-tree (keys are record Ids; routed by slug). */
    get resourceCategoryRoots() {
        return (this.resourceCategories || []).map((c) => topLevel({ ...c, iconPath: iconPath(c.iconName) }));
    }

    get hasHelpTopics() {
        return this.helpTopicRoots.length > 0;
    }
    get hasResourceCategories() {
        return this.resourceCategoryRoots.length > 0;
    }

    /** Featured strip: Featured/popular articles then Featured resources.
        Articles carry NO href on purpose — dsContentCard reserves that for
        links that truly leave the site and renders them target="_blank".
        An article is in-app, so its action fires contentselect and routes
        through contextNav exactly like the title does. */
    get featuredItems() {
        const articles = (this.featuredArticles || []).map((a) => ({
            kind: 'article',
            id: a.id,
            title: a.title,
            subtitle: a.summary,
            routeKey: a.urlName
        }));
        const resources = (this.featuredResources || []).map(toContentItem);
        return articles.concat(resources);
    }
    get hasFeatured() {
        return this.featuredItems.length > 0;
    }

    // ---- Search --------------------------------------------------------------

    async handleSearchQuery(event) {
        const term = event.detail.value;
        this._lastSearchTerm = term;
        try {
            const results = await this._fetchSuggestions(term);
            if (results === null) {
                return; // stale response — a newer request already rendered
            }
            this.suggestions = (results || []).map((s) => ({
                id: s.id,
                title: s.title,
                subtitle: s.subtitle,
                kind: s.kind,
                routeKey: s.routeKey
            }));
            this._searchLogger.settleTypeahead({ term, count: this.suggestions.length });
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('unifiedLanding typeahead error', error);
        }
    }

    handleSuggestionSelect(event) {
        const { suggestion, rank } = event.detail;
        if (suggestion.kind === 'article') {
            this._searchLogger.logTypeaheadConversion({
                term: this._lastSearchTerm,
                suggestions: this.suggestions,
                clickedArticleId: suggestion.id,
                rank
            });
            goToArticle(this, this.linkCtx, { urlName: suggestion.routeKey });
        } else {
            // Resources aren't Knowledge articles — plain conversion row, no
            // top-result stamp / click chain (matches the RC hosts).
            logSearchEntry({
                term: this._lastSearchTerm,
                resultCount: this.suggestions.length,
                topResultArticleId: null,
                searchType: 'Typeahead',
                app: APP_LANDING
            });
            goToResource(this, this.linkCtx, { slug: suggestion.routeKey });
        }
    }

    handleSearchSubmit(event) {
        const value = (event.detail && event.detail.value) || '';
        if (!value.trim()) {
            if (this.isResults) {
                this.view = 'home'; // clearing the box leaves the results view
                this.term = '';
            }
            return;
        }
        // The results view logs the full search itself.
        this._searchLogger.cancelZeroLog();
        this.term = value;
        this.view = 'results';
    }

    /** Featured strip cards — title, head and action all arrive here. */
    handleFeaturedSelect(event) {
        event.stopPropagation();
        if (event.detail.kind === 'resource') {
            goToResource(this, this.linkCtx, { slug: event.detail.routeKey });
        } else if (event.detail.kind === 'article') {
            goToArticle(this, this.linkCtx, { urlName: event.detail.routeKey });
        }
    }

    handleEventsLink() {
        goToEvents(this, this.linkCtx);
    }

    /** resourceselect from the shared results view. */
    handleResourceSelect(event) {
        goToResource(this, this.linkCtx, { slug: event.detail.slug });
    }

    /** articleselect from the shared results view — it has no mixin, so
        contextNav hands the target up to us. */
    handleArticleSelect(event) {
        goToArticle(this, this.linkCtx, { urlName: event.detail.urlName });
    }

    // ---- Topic directory -----------------------------------------------------

    /** Any depth: the tree hands back the topic's API name, which ?topic= takes as-is. */
    handleHelpTopicNav(event) {
        if (event.detail.key) {
            goToArticle(this, this.linkCtx, { topic: event.detail.key });
        }
    }

    /** Resource categories route by slug; the tree key is the record Id. */
    handleResourceNav(event) {
        const node = findNode(this._resourceTree, event.detail.key);
        if (node) {
            goToResource(this, this.linkCtx, { slug: node.slug, view: 'category' });
        }
    }

    handleBrandHome() {
        this.view = 'home';
        this.term = '';
    }
}