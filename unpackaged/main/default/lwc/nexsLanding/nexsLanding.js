import { LightningElement, api, wire, track } from 'lwc';
import getWelcomeState from '@salesforce/apex/NexSWelcomeController.getWelcomeState';
// Same brand logo the new wizard top bar (envelopeTopBarV2) uses.
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';

/**
 * nexsLanding
 *
 * Entry point for the help center. Everyone lands on the home page; on first
 * login (welcome flag not yet set) the home page shows a welcome banner,
 * which writes the flag when the user dismisses it via "Got it".
 *
 * From home, topic / article / search actions swap to the article-browser view
 * with the chosen state handed over via @api; the browser's "Help Center"
 * breadcrumb (and this component's header crumb) swap back to home.
 *
 * Dual-context note: all views share this single page, so we swap views
 * *inline* rather than navigating. Inline rendering behaves identically in the
 * Experience Cloud LWR site and the core Lightning App, and it avoids any
 * surface-specific navigation dependency (an earlier version imported
 * @salesforce/community/basePath, which only resolves inside a community and
 * threw in the core app). If separate site pages are ever introduced, swap the
 * view handlers for a NavigationMixin redirect guarded by surface.
 */
export default class NexsLanding extends LightningElement {
    /** @api hideBranding — hides the Diversify logo + "Help Center" crumb in
     *  the header (search bar and the "?" help menu still show) for
     *  embeddings, like ARC, that already have their own site chrome. Same
     *  coercion as resourceCenter's hideBranding: a checkbox in the Builder
     *  property panel or a content.json attribute can hand this over as the
     *  string "false" rather than a real boolean. */
    _hideBranding = false;
    @api
    get hideBranding() {
        return this._hideBranding;
    }
    set hideBranding(value) {
        this._hideBranding = value !== false && value !== 'false';
    }

    get showBranding() {
        return !this._hideBranding;
    }

    logoUrl = diversifyLogo;
    @track view = 'loading'; // 'loading' | 'home' | 'browse'
    @track showWelcomeBanner = false;
    @track helpOpen = false;
    _helpOutsideClick = null;

    // Hand-off state for the browser view, set by the home view's events.
    browseCategory;
    browseArticleId;
    browseSearchTerm;
    browseArticleUrlName;

    connectedCallback() {
        // ?article=<UrlName> deep links (Related Articles on the Resource
        // Center, Get Help article terminals) — the LWR site has no /article/
        // route, so the home page doubles as the deep-link entry. Plain
        // location parsing works on both surfaces (no community-only import).
        try {
            const urlName = new URLSearchParams(window.location.search).get('article');
            if (urlName) {
                this.browseArticleUrlName = urlName;
            }
        } catch (e) {
            // URL parsing is best-effort — fall through to the home page.
        }
    }

    @wire(getWelcomeState)
    wiredWelcome({ data, error }) {
        if (data !== undefined && data !== null) {
            this.showWelcomeBanner = data === false;
            this.view = this.browseArticleUrlName ? 'browse' : 'home';
        } else if (error) {
            // Don't strand the user on an error — just show the home page.
            this.view = this.browseArticleUrlName ? 'browse' : 'home';
            // eslint-disable-next-line no-console
            console.error('nexsLanding getWelcomeState error', error);
        }
    }

    get copyrightLine() {
        return `© ${new Date().getFullYear()} Diversify Financial. Internal use only.`;
    }

    get isLoading() {
        return this.view === 'loading';
    }
    get isHome() {
        return this.view === 'home';
    }
    get isBrowse() {
        return this.view === 'browse';
    }

    // "Got it" on the home page's welcome banner.
    handleWelcomeDismiss() {
        this.showWelcomeBanner = false;
    }

    // ---- Header help menu (guided tour entry point) ----------------------------

    handleHelpToggle() {
        if (this.helpOpen) {
            this._closeHelp();
            return;
        }
        this.helpOpen = true;
        // Close on any click outside the menu. Registered on the next tick so
        // the opening click doesn't immediately re-close it; composedPath sees
        // through the shadow boundary.
        this._helpOutsideClick = (event) => {
            const help = this.template.querySelector('.nexs-chrome__help');
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            if (!help || !path.includes(help)) {
                this._closeHelp();
            }
        };
        setTimeout(() => {
            if (this._helpOutsideClick) {
                window.addEventListener('click', this._helpOutsideClick, true);
            }
        }, 0);
    }

    _closeHelp() {
        this.helpOpen = false;
        if (this._helpOutsideClick) {
            window.removeEventListener('click', this._helpOutsideClick, true);
            this._helpOutsideClick = null;
        }
    }

    disconnectedCallback() {
        this._closeHelp();
    }

    // "Start the tour": the tour targets live on the home view, so make sure
    // we're there first — the launcher's target polling absorbs the re-render.
    handleTourStart() {
        this._closeHelp();
        this.handleGoHome();
        const launcher = this.template.querySelector('c-tour-launcher');
        if (launcher) {
            launcher.start();
        }
    }

    // ---- Header search (browse view) ------------------------------------------
    // The browser is already mounted, so drive it via its @api methods rather
    // than the mount-time initial-* props.

    get browserEl() {
        return this.template.querySelector('c-nexs-article-browser');
    }

    handleHeaderSuggestionSelect(event) {
        const browser = this.browserEl;
        if (browser) {
            browser.openArticleById(event.detail.articleId);
        }
    }

    handleHeaderSearch(event) {
        const browser = this.browserEl;
        if (browser) {
            browser.searchFor((event.detail && event.detail.value) || '');
        }
    }

    // ---- Home → browse hand-offs ---------------------------------------------

    handleTopicSelect(event) {
        this.resetBrowseState();
        this.browseCategory = event.detail.name;
        this.view = 'browse';
    }

    handleArticleSelect(event) {
        this.resetBrowseState();
        this.browseArticleId = event.detail.articleId;
        this.view = 'browse';
    }

    handleSearchSubmit(event) {
        this.resetBrowseState();
        this.browseSearchTerm = event.detail.value;
        this.view = 'browse';
    }

    // Browser's "Help Center" breadcrumb, or the header crumb.
    handleGoHome() {
        if (this.view === 'browse') {
            this.resetBrowseState();
            this.view = 'home';
        }
    }

    resetBrowseState() {
        this.browseCategory = undefined;
        this.browseArticleId = undefined;
        this.browseSearchTerm = undefined;
        this.browseArticleUrlName = undefined;
    }
}