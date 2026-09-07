import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import typeahead from '@salesforce/apex/ResourceCenterService.typeahead';
import { createSuggestionFetcher } from 'c/dsSearchBar';
import { createSearchLogger, logSearchEntry, APP_RESOURCE_CENTER } from 'c/searchLogUtil';
import { linkContext, readParams, isSiteRef, goToHome, goToArticle } from 'c/contextNav';
import { rcRootCrumbs, CRUMB_HELP_HOME, CRUMB_RC_HOME } from 'c/rcConstants';

/** "Get Help" (the guided help_guide) is parked for now (2026-09-07): flip to
    restore the chrome action. The guide view, its ?rcview=guide deep link,
    the guideopen event and its crumbs all stay wired. */
const SHOW_GET_HELP = false;

/** The identity of a Resource Center route — what handlePageRef compares an
    inbound page reference against to tell a real change from its own echo. */
function routeSigOf(view, slug, term, scope) {
    return [view || 'home', slug || '', term || '', scope || ''].join('|');
}

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

    get showGetHelp() {
        return SHOW_GET_HELP;
    }

    logoUrl = diversifyLogo;

    // 'home' is the landing: the same browse view as 'category', with no
    // slug, so resourceCategoryPage falls back to its first topic. Kept as a
    // distinct name so ?rcview=home deep links, the logo crumb and the
    // guide's back-crumb all keep working.
    view = 'home'; // home | category | detail | search | guide
    slug;
    term;
    /** Search view only: category slug the resource hits are scoped to (any depth). */
    scope;

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
    /** `rcview|rcslug|rcterm|rcscope` of the route last adopted — including the
        ones this host wrote itself, since syncUrl()'s Navigate makes the wire
        re-emit. Comparing signatures keeps that echo a no-op WITHOUT going
        deaf: a boolean latch here also swallowed genuine route changes, so a
        second search's result click (or Back) left the previous resource on
        screen while the URL moved on. */
    _routeSig;

    /** Restore on BOTH surfaces — internally the same state arrives
        c__-prefixed on the tab's page reference. */
    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isCommunity = isSiteRef(ref);
        if (!ref) {
            return;
        }
        const params = readParams(ref);
        const sig = routeSigOf(params.rcview, params.rcslug, params.rcterm, params.rcscope);
        if (sig === this._routeSig) {
            return; // our own syncUrl push, read straight back in
        }
        this._routeSig = sig;
        // Adopt wholesale, not key by key: a dropped param means the route no
        // longer carries it (Back out of a detail view returns to the landing).
        this.view = params.rcview || 'home';
        this.slug = params.rcslug || undefined;
        this.term = params.rcterm || undefined;
        this.scope = params.rcscope || undefined;
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
    /** Help & Resources › Resource Center › Get Help */
    get guideCrumbs() {
        return [...rcRootCrumbs(), { label: 'Get Help' }];
    }
    handleGuideCrumb(event) {
        const key = event.detail.key;
        if (key === CRUMB_HELP_HOME) {
            this.handleHelpCenter();
        } else if (key === CRUMB_RC_HOME) {
            this.setState('home');
        }
    }
    handleCategorySelect(event) { this.setState('category', event.detail.slug); }
    handleResourceSelect(event) { this.setState('detail', event.detail.slug); }
    /** articleselect from the embedded results view — it has no mixin, so
        contextNav hands the target up to us. */
    handleArticleSelect(event) {
        goToArticle(this, this.linkCtx, { urlName: event.detail.urlName });
    }
    handleSearch(event) { this.setState('search', undefined, event.detail.term, event.detail.scope); }
    /** The results view's category facet asks; the scope lives here (and in the URL). */
    handleSearchScope(event) {
        this.setState('search', undefined, this.term, event.detail.slug || undefined);
    }
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

    /** The chrome's Help Center action AND every child crumb's `helphome`
        (Help & Resources › …) land here. */
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

    setState(view, slug, term, scope) {
        this.view = view;
        this.slug = slug;
        this.term = term;
        this.scope = view === 'search' ? scope : undefined;
        // Stamp the route before pushing it, so the wire re-emission syncUrl()
        // triggers is recognised as our own and changes nothing.
        this._routeSig = routeSigOf(this.view, this.slug, this.term, this.scope);
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
            state[prefix + 'rcscope'] = this.scope || null;
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