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

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isSite = isSiteRef(ref);
        // Deep-link state can arrive after connectedCallback in the core app,
        // where it rides the page reference rather than the query string.
        if (!this.initialUrlName && !this.initialCategory) {
            this.applyParams(readParams(ref));
        }
    }

    handleResourcesLink() {
        goToResource(this, this.linkCtx, { view: 'home' });
    }

    connectedCallback() {
        this.applyParams(readParams(this._pageRef));
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        this._popstateHandler = () => this.handlePopState();
        window.addEventListener('popstate', this._popstateHandler);
    }

    /** ?name= is canonical; ?article= is the accepted legacy alias, and
        ?topic= opens browse mode with no article named.

        Merges rather than overwrites: the CurrentPageReference wire is
        provisioned BEFORE connectedCallback, so an internal deep link is
        already applied by the time the query-string read runs. First value
        wins. */
    applyParams(params) {
        this.initialUrlName =
            this.initialUrlName || params.name || params.article || undefined;
        this.initialCategory = this.initialCategory || params.topic || undefined;
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

    currentUrlName() {
        return readParams(this._pageRef).name || null;
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
                return; // deep-link mount or popstate-driven open — URL is right
            }
            const url = new URL(window.location.href);
            url.searchParams.delete('article'); // never carry the legacy form forward
            url.searchParams.set('name', urlName);
            window.history.pushState({}, '', url.toString());
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
        if (name) {
            browser.openArticleByUrlName(name);
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