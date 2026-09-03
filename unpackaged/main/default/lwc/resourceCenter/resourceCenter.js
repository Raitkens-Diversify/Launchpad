import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import typeahead from '@salesforce/apex/ResourceCenterService.typeahead';
import { createSuggestionFetcher } from 'c/dsSearchBar';
import { createSearchLogger, logSearchEntry, APP_RESOURCE_CENTER } from 'c/searchLogUtil';
import { linkContext, readParams, isSiteRef, goToHome, goToArticle } from 'c/contextNav';

/**
 * resourceCenter — root orchestrator + branded chrome, matching the NexS Help
 * Center. The single component both the internal Lightning App tab and the LWR
 * site render.
 *
 * Chrome: the shared c-ds-chrome shell (sticky white header: Diversify logo +
 * divider + "Resource Center" crumb; footer), with the header search, the
 * Get Help entry and the Help Center cross-link slotted in. Search lives in
 * the header on every view, matching the Help Center's article browser.
 *
 * Surface-aware navigation (the agreed hybrid): views swap inline on every
 * surface; the current view/slug/term are best-effort synced to the URL on
 * BOTH surfaces — the query string on the LWR site, c__-prefixed page
 * reference state in the core app — so deep links work either side. Surface
 * is derived from CurrentPageReference (NOT @salesforce/community/basePath,
 * which throws in the core app — see nexsLanding.js).
 *
 * @api helpCenterBaseUrl — absolute base URL of the Help Center, for
 * cross-links. Optional Experience Builder override only; when unset (which
 * is every deployment so far) the Help Center button routes through
 * c/contextNav instead, so it renders on both surfaces.
 */
export default class ResourceCenter extends NavigationMixin(LightningElement) {
    /** @api hideBranding — passed through to c-ds-chrome (ARC embeddings
     *  carry their own site chrome); the chrome coerces string values. */
    @api hideBranding = false;

    @api helpCenterBaseUrl;

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
    }

    get effectiveHelpCenterBaseUrl() {
        return this.helpCenterBaseUrl || (this.linkCtx && this.linkCtx.helpBase);
    }

    /** The cross-link renders as soon as a surface is known — internally there
        is no base to resolve, the link routes to the Unified_Support_Home tab.
        Gating on the base alone hid the button in the core app entirely. */
    get showHelpCenterLink() {
        return !!this.helpCenterBaseUrl || !!this.linkCtx;
    }

    logoUrl = diversifyLogo;

    // 'home' is the landing: the same browse view as 'category', with no
    // slug, so resourceCategoryPage falls back to its first topic. Kept as a
    // distinct name so ?rcview=home deep links, the logo crumb and the
    // guide's back-crumb all keep working.
    view = 'home'; // home | category | detail | search | guide
    slug;
    term;

    // Host-owned glue for the header c-ds-search-bar (non-home views).
    headerSuggestions = [];
    _lastHeaderTerm;
    _fetchHeaderSuggestions = createSuggestionFetcher((t) => typeahead({ term: t }));
    _headerSearchLogger = createSearchLogger(APP_RESOURCE_CENTER);

    disconnectedCallback() {
        this._headerSearchLogger.dispose();
    }

    _pageRef;
    _isCommunity = false;
    _restored = false;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isCommunity = isSiteRef(ref);
        // Restore on BOTH surfaces — internally the same state arrives
        // c__-prefixed on the tab's page reference. The _restored latch is
        // load-bearing: the wire re-emits on every syncUrl() Navigate, and
        // without it our own push would be read straight back in.
        if (ref && !this._restored) {
            const params = readParams(ref);
            if (params.rcview) {
                this.view = params.rcview;
            }
            if (params.rcslug) {
                this.slug = params.rcslug;
            }
            if (params.rcterm) {
                this.term = params.rcterm;
            }
            this._restored = true;
        }
    }

    get isHome() { return this.view === 'home'; }
    get isCategory() { return this.view === 'category'; }
    /** Landing and a routed category are the same browse surface — the
        landing just has no slug. */
    get isBrowse() { return this.isHome || this.isCategory; }
    get isDetail() { return this.view === 'detail'; }
    get isSearch() { return this.view === 'search'; }
    get isGuide() { return this.view === 'guide'; }

    // ---- Event handlers from child views ------------------------------------

    handleHome() { this.setState('home'); }
    handleGuideOpen() { this.setState('guide'); }
    handleGuideBack(event) {
        event.preventDefault(); // crumb is an anchor; don't jump the page
        this.setState('home');
    }
    handleCategorySelect(event) { this.setState('category', event.detail.slug); }
    handleResourceSelect(event) { this.setState('detail', event.detail.slug); }
    /** articleselect from the embedded results view — it has no mixin, so
        contextNav hands the target up to us. */
    handleArticleSelect(event) {
        goToArticle(this, this.linkCtx, { urlName: event.detail.urlName });
    }
    handleSearch(event) { this.setState('search', undefined, event.detail.term); }
    handleDownload(event) {
        if (event.detail && event.detail.id) {
            trackDownload({ resourceId: event.detail.id }).catch(() => {});
        }
    }

    // Header search: dsSearchBar's raw (non-composed) events, listened on the
    // element itself, renamed here to the composed resourceselect/rcsearch
    // contract the shell already routes.
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
                title: r.name,
                kind: 'resource',
                routeKey: r.slug
            }));
            this._headerSearchLogger.settleTypeahead({ term, count: this.headerSuggestions.length });
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('resourceCenter header typeahead error', error);
        }
    }
    handleHeaderSelect(event) {
        // Conversion row; no top-result stamp / logClick — resources aren't
        // Knowledge articles (pre-migration resourceSearchBar semantics).
        logSearchEntry({
            term: this._lastHeaderTerm,
            resultCount: this.headerSuggestions.length,
            topResultArticleId: null,
            searchType: 'Typeahead',
            app: APP_RESOURCE_CENTER
        });
        this.setState('detail', event.detail.suggestion.routeKey);
    }
    handleHeaderSearch(event) {
        const term = (event.detail.value || '').trim();
        if (term) {
            // resourceSearchResults logs the full search itself.
            this._headerSearchLogger.cancelZeroLog();
            this.setState('search', undefined, term);
        }
    }

    handleHelpCenter() {
        // A Builder-supplied override stays a plain external link; otherwise
        // contextNav routes to the site or the core-app tab as appropriate.
        if (this.helpCenterBaseUrl) {
            window.open(this.helpCenterBaseUrl, '_blank', 'noopener');
            return;
        }
        goToHome(this, this.linkCtx);
    }

    // ---- State + URL sync ----------------------------------------------------

    setState(view, slug, term) {
        this.view = view;
        this.slug = slug;
        this.term = term;
        this.syncUrl();
    }

    syncUrl() {
        if (!this._pageRef) {
            return;
        }
        try {
            // Explicit null (not undefined) is how a param is DROPPED.
            // Lightning namespaces custom state; LWR does not.
            const prefix = this._isCommunity ? '' : 'c__';
            const state = {};
            state[prefix + 'rcview'] = this.view;
            state[prefix + 'rcslug'] = this.slug || null;
            state[prefix + 'rcterm'] = this.term || null;
            this[NavigationMixin.Navigate]({
                type: this._pageRef.type,
                attributes: this._pageRef.attributes,
                state
            });
        } catch (e) {
            // Best-effort: on the core app (or if navigation is unavailable) the
            // inline view-swap above already updated the UI.
        }
    }
}