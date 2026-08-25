import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';

/**
 * resourceCenter — root orchestrator + branded chrome, matching the NexS Help
 * Center. The single component both the internal Lightning App tab and the LWR
 * site render.
 *
 * Chrome: full-bleed sticky white header (Diversify logo + divider + "Resource
 * Center" crumb, optional Help Center link) and footer, replicated from
 * nexsLanding. Search lives in the hero (like NexS), not the header.
 *
 * Surface-aware navigation (the agreed hybrid): views swap inline on every
 * surface (this is what the core app uses); on the LWR site the current
 * view/slug/term are best-effort synced to the URL query string. Surface is
 * derived from CurrentPageReference (NOT @salesforce/community/basePath, which
 * throws in the core app — see nexsLanding.js).
 *
 * @api helpCenterBaseUrl — absolute base URL of the Help Center, for cross-links.
 * @api hideBranding — hides the Diversify logo + "Resource Center" crumb in the
 *   header (but keeps the header's search bar / Help Center link, when those
 *   apply) for embeddings that already have their own site chrome/branding.
 */
export default class ResourceCenter extends NavigationMixin(LightningElement) {
    @api helpCenterBaseUrl;

    _hideBranding = false;
    @api
    get hideBranding() {
        return this._hideBranding;
    }
    set hideBranding(value) {
        this._hideBranding = value !== false && value !== 'false';
    }

    logoUrl = diversifyLogo;

    view = 'home'; // home | category | detail | search | guide
    slug;
    term;

    _pageRef;
    _isCommunity = false;
    _restored = false;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isCommunity = !!(ref && ref.type && ref.type.indexOf('comm__') === 0);
        if (this._isCommunity && ref && ref.state && !this._restored) {
            if (ref.state.rcview) {
                this.view = ref.state.rcview;
            }
            if (ref.state.rcslug) {
                this.slug = ref.state.rcslug;
            }
            if (ref.state.rcterm) {
                this.term = ref.state.rcterm;
            }
            this._restored = true;
        }
    }

    /** Header search shows on every inner view; home keeps its hero search
        (mirrors nexsLanding, whose header search is browse-only). */
    get showHeaderSearch() { return this.view !== 'home'; }

    get showBranding() { return !this._hideBranding; }

    /** Collapses the header entirely rather than leaving an empty padded bar
        when branding is hidden and neither the header search nor the Help
        Center link apply (e.g. the Home view with no helpCenterBaseUrl). */
    get showHeaderChrome() {
        return this.showBranding || this.showHeaderSearch || Boolean(this.helpCenterBaseUrl);
    }

    get isHome() { return this.view === 'home'; }
    get isCategory() { return this.view === 'category'; }
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
    handleSearch(event) { this.setState('search', undefined, event.detail.term); }
    handleDownload(event) {
        if (event.detail && event.detail.id) {
            trackDownload({ resourceId: event.detail.id }).catch(() => {});
        }
    }

    // Header search: resourceSearchBar's raw (non-composed) events, listened
    // on the element itself — same pattern as resourceCenterHome's hero search
    // before it renames them to the composed resourceselect/rcsearch.
    handleHeaderSelect(event) {
        this.setState('detail', event.detail.slug);
    }
    handleHeaderSearch(event) {
        const term = (event.detail.value || '').trim();
        if (term) {
            this.setState('search', undefined, term);
        }
    }

    handleHelpCenter() {
        if (this.helpCenterBaseUrl) {
            window.open(this.helpCenterBaseUrl, '_blank', 'noopener');
        }
    }

    // ---- State + URL sync ----------------------------------------------------

    setState(view, slug, term) {
        this.view = view;
        this.slug = slug;
        this.term = term;
        this.syncUrl();
    }

    syncUrl() {
        if (!this._isCommunity || !this._pageRef) {
            return;
        }
        try {
            const state = { rcview: this.view };
            state.rcslug = this.slug || null;
            state.rcterm = this.term || null;
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