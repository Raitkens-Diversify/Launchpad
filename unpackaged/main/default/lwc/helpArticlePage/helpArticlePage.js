import { LightningElement, api, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import typeahead from '@salesforce/apex/NexSKnowledgeController.typeahead';
import { wire } from 'lwc';
import { createSuggestionFetcher } from 'c/dsSearchBar';
import { createSearchLogger, APP_HELP_CENTER } from 'c/searchLogUtil';
import {
    linkContext,
    readParams,
    isSiteRef,
    goToHome,
    goToResource
} from 'c/contextNav';

/**
 * helpArticlePage — the /help/article route host: the first REAL article route
 * the site has had (deep links used to collapse onto the home route as
 * ?article=). Thin wrapper: shared chrome + header search + the article
 * browser, with the browser's navigation mirrored into the URL so articles
 * are finally bookmarkable and browser Back works.
 *
 * URL contract: /help/article?name=<Knowledge UrlName>. The legacy
 * /help/?article=<UrlName> form still resolves (home-route shim redirects
 * here). ?article= is also accepted on THIS route for symmetry. In the core
 * app the same state arrives c__-prefixed on the Help_Center_Article tab;
 * c/contextNav.readParams reads whichever form the surface uses.
 *
 * URL sync is SITE-ONLY. Lightning owns its own history stack, so calling
 * pushState on a core-app tab corrupts Back — internally the browser's
 * navigation stays in-component and the URL is left alone (the same choice
 * resourceCenter.syncUrl makes). On the site it is the plain history API:
 *   - viewer loads an article (search click, rail suggestion, deep link) →
 *     browser fires `articleopen {urlName}` → pushState ?name= (replace when
 *     the URL already names it — the deep-link mount case).
 *   - viewer closes back to the list → `articleclose` → pushState without
 *     ?name (Back returns to the article).
 *   - popstate → drive the browser via its @api (openArticleByUrlName /
 *     searchFor('')), guarded so the resulting articleopen doesn't re-push.
 */
export default class HelpArticlePage extends NavigationMixin(LightningElement) {
    /** @api hideBranding — passed through to c-ds-chrome (ARC embeddings
     *  carry their own site chrome); the chrome coerces string values. */
    @api hideBranding = false;

    logoUrl = diversifyLogo;
    initialUrlName;
    initialCategory;

    @track headerSuggestions = [];
    _lastHeaderTerm;
    _fetchHeaderSuggestions = createSuggestionFetcher((term) => typeahead({ term, category: null }));
    _headerSearchLogger = createSearchLogger(APP_HELP_CENTER);
    _popstateHandler = null;

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;
    /** True on the LWR site — gates the history-API URL sync. */
    _isSite = false;
    _pageRef;

    /** `name|topic` of the route this host has already adopted. Undefined
        until the first emit. See applyRoute(). */
    _routeSig;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isSite = isSiteRef(ref);
        // Deep-link state can arrive after connectedCallback in the core app,
        // where it rides the page reference rather than the query string —
        // and it can arrive AGAIN, naming a different article, without this
        // host being re-mounted: c/contextNav reaches the core-app tab with
        // standard__navItemPage state, and the LWR router can reuse the route
        // host. Every emit is considered; only a changed route acts.
        this.applyRoute(readParams(ref));
    }

    handleResourcesLink() {
        goToResource(this, this.linkCtx, { view: 'home' });
    }

    /** `resourceselect` bubbling out of the article rail (articleResources has
        no mixin, so contextNav hands the target up to this host to route). */
    handleResourceSelect(event) {
        const slug = event.detail && event.detail.slug;
        if (slug) {
            goToResource(this, this.linkCtx, { slug });
        }
    }

    connectedCallback() {
        this.applyRoute(readParams(this._pageRef));
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        this._popstateHandler = () => this.handlePopState();
        window.addEventListener('popstate', this._popstateHandler);
    }

    /** The identity of a route: ?name= is canonical, ?article= is the accepted
        legacy alias, ?topic= opens browse mode with no article named. */
    routeSigOf(params) {
        return (params.name || params.article || '') + '|' + (params.topic || '');
    }

    /**
     * Adopt a route, from the page reference or the URL.
     *
     * Before the first render there is no browser to drive, so the target
     * rides the mount-time initial-* props. Afterwards those props are inert —
     * nexsArticleBrowser applies them once, when its taxonomy wire first
     * resolves — so a later route change has to go through the browser's @api
     * (the same way nexsLanding and handlePopState drive it).
     *
     * Keyed on the LAST APPLIED route rather than on what is on screen: the
     * core app never syncs the URL, so its tab page reference stays on the
     * article it was deep-linked with while the reader browses on, and a
     * repeat emit of that stale reference must not yank them back.
     */
    applyRoute(params) {
        const sig = this.routeSigOf(params);
        if (sig === this._routeSig) {
            return;
        }
        this._routeSig = sig;
        const browser = this.browserEl;
        if (!browser) {
            this.initialUrlName = params.name || params.article || undefined;
            this.initialCategory = params.topic || undefined;
            return;
        }
        if (params.name || params.article) {
            browser.openArticleByUrlName(params.name || params.article);
        } else if (params.topic) {
            browser.openCategory(params.topic);
        } else {
            browser.searchFor(''); // back to the browse list
        }
    }

    /** Record the route this host just mirrored into the URL itself, so a
        later page-reference emit that only echoes it is a no-op. Site-only:
        in the core app nothing writes the URL. */
    markRouteApplied() {
        this._routeSig = this.routeSigOf(readParams(null));
    }

    disconnectedCallback() {
        if (this._popstateHandler) {
            window.removeEventListener('popstate', this._popstateHandler);
            this._popstateHandler = null;
        }
        this._headerSearchLogger.dispose();
    }

    get browserEl() {
        return this.template.querySelector('c-nexs-article-browser');
    }

    // ---- URL sync ------------------------------------------------------------

    /** Read from the live URL, not the cached page ref — this host writes
        ?name= itself and the CurrentPageReference wire never re-emits after a
        history.pushState, while readParams gives page-reference state
        precedence over the query string. Reading the cached ref here left
        every URL decision anchored to the article the page was mounted with. */
    currentUrlName() {
        return readParams(null).name || null;
    }

    /** Same contract as currentUrlName, for the browse route. */
    currentTopic() {
        return readParams(null).topic || null;
    }

    /** Browse navigation → ?topic=, so Back/Forward walk the topic tree too
        (mirror of handleArticleOpen). The first topic after a bare mount is
        canonicalised with replaceState — no extra history entry for landing
        on the default topic; later changes push. */
    handleTopicChange(event) {
        const topic = event.detail && event.detail.name;
        if (!topic || !this._isSite) {
            return; // core app: Lightning owns the history stack
        }
        try {
            if (this.currentTopic() === topic) {
                this.markRouteApplied();
                return; // deep-link mount or popstate-driven open — URL is right
            }
            const url = new URL(window.location.href);
            const bare = !url.searchParams.has('topic') && !url.searchParams.has('name')
                && !url.searchParams.has('article');
            url.searchParams.set('topic', topic);
            if (bare) {
                window.history.replaceState({}, '', url.toString());
            } else {
                window.history.pushState({}, '', url.toString());
            }
            this.markRouteApplied();
        } catch (e) {
            // URL sync is best-effort — never break browsing.
        }
    }

    handleArticleOpen(event) {
        const urlName = event.detail.urlName;
        if (!urlName) {
            return;
        }
        if (!this._isSite) {
            return; // core app: Lightning owns the history stack
        }
        try {
            if (this.currentUrlName() === urlName) {
                this.markRouteApplied();
                return; // deep-link mount or popstate-driven open — URL is right
            }
            const url = new URL(window.location.href);
            url.searchParams.delete('article'); // never carry the legacy form forward
            url.searchParams.set('name', urlName);
            window.history.pushState({}, '', url.toString());
            this.markRouteApplied();
        } catch (e) {
            // URL sync is best-effort — never break reading the article.
        }
    }

    handleArticleClose() {
        if (!this._isSite) {
            return; // core app: nothing was pushed, nothing to unwind
        }
        try {
            if (!this.currentUrlName()) {
                return;
            }
            const url = new URL(window.location.href);
            url.searchParams.delete('name');
            url.searchParams.delete('article');
            window.history.pushState({}, '', url.toString());
            this.markRouteApplied();
        } catch (e) {
            // best-effort
        }
    }

    handlePopState() {
        const browser = this.browserEl;
        if (!browser) {
            return;
        }
        const name = this.currentUrlName();
        const topic = this.currentTopic();
        this.markRouteApplied();
        if (name) {
            browser.openArticleByUrlName(name);
        } else if (topic) {
            browser.openCategory(topic); // the topic this history entry was on
        } else {
            browser.searchFor(''); // back to the browse list
        }
    }

    // ---- Brand crumb → site home ---------------------------------------------

    handleBrandHome() {
        goToHome(this, this.linkCtx);
    }

    // ---- Header search glue (same shape as nexsLanding's) --------------------

    async handleHeaderQuery(event) {
        const term = event.detail.value;
        this._lastHeaderTerm = term;
        try {
            const results = await this._fetchHeaderSuggestions(term);
            if (results === null) {
                return; // stale response — a newer request already rendered
            }
            this.headerSuggestions = (results || []).map((r) => ({
                id: r.id,
                title: r.title,
                kind: 'article',
                routeKey: r.urlName
            }));
            this._headerSearchLogger.settleTypeahead({ term, count: this.headerSuggestions.length });
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('helpArticlePage typeahead error', error);
        }
    }

    handleHeaderSuggestionSelect(event) {
        const { suggestion, rank } = event.detail;
        this._headerSearchLogger.logTypeaheadConversion({
            term: this._lastHeaderTerm,
            suggestions: this.headerSuggestions,
            clickedArticleId: suggestion.id,
            rank
        });
        const browser = this.browserEl;
        if (browser) {
            browser.openArticleById(suggestion.id);
        }
    }

    handleHeaderSearch(event) {
        const value = (event.detail && event.detail.value) || '';
        if (value.trim()) {
            this._headerSearchLogger.cancelZeroLog(); // the browser logs the full search
        }
        const browser = this.browserEl;
        if (browser) {
            browser.searchFor(value);
        }
    }
}