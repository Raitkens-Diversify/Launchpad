import { LightningElement, api } from 'lwc';
import { parseScribeUrl, toEmbedUrl, toShareUrl, titleFromSlug } from 'c/scribeUrlUtil';

/** Give a slow Scribe this long before the fallback card takes over. */
const LOAD_TIMEOUT_MS = 20000;
/** Start loading this far before the frame scrolls into view. */
const LAZY_MARGIN_PX = 400;
const LAZY_ROOT_MARGIN = `${LAZY_MARGIN_PX}px 0px`;

const ICON = {
    // step-list glyph: three rows with a tick in the first
    scribe: 'M4 6h2M4 12h2M4 18h2M10 6h10M10 12h10M10 18h10',
    expand: 'M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7',
    collapse: 'M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7',
    external: 'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3'
};

/**
 * scribeEmbed — one Scribe (scribehow.com) walkthrough rendered inline as an
 * interactive frame, with the reader UX the bare iframe lacked:
 *
 *   - accepts ANY Scribe link shape (shared / viewer / embed) and derives the
 *     chrome-less embed URL through c/scribeUrlUtil; any other URL renders
 *     nothing (only scribehow.com is ever framed — the host decides what to
 *     show instead)
 *   - lazy: the frame's src is not set until the card is within ~400px of the
 *     viewport — IntersectionObserver where the sandbox exposes it, otherwise
 *     a throttled scroll/resize check (Lightning's component sandbox hides
 *     IntersectionObserver, verified 2026-09-05); `eager` skips both
 *   - skeleton while loading; a fallback card (title + "Open in Scribe" +
 *     "Try again") when the frame errors, is refused by CSP, or has not
 *     loaded after 20 s — the frame stays mounted so a late load still wins
 *   - Expand: native Fullscreen API on the whole card (bar + frame, so the
 *     exit button stays reachable), falling back to a fixed-position overlay
 *     with Escape where the API is unavailable (iOS Safari) or refused
 *   - "Open in Scribe ↗" is always visible: Scribe's own login wall for a
 *     restricted guide cannot be detected from outside the frame
 *
 * Surface-agnostic on purpose: no community imports, no navigation, no
 * window.location writes — it mounts identically on the LWR site, inside the
 * ARC chrome and on the core Lightning tab.
 *
 * @api url    any Scribe link
 * @api title  optional heading override (default: derived from the slug)
 * @api eager  skip lazy-loading (above-the-fold hosts such as resourceDetail)
 * @api mode   'slides' | 'scrollable' | 'video' — overrides the authored `as=`
 * Events (bubbles, composed): scribeready { url }, scribefail { url }
 */
export default class ScribeEmbed extends LightningElement {
    @api title;
    @api mode;

    state = 'idle'; // idle | loading | ready | failed
    /** Which lazy-load path armed this card — surfaced as data-lazy for QA. */
    lazyMode = 'idle'; // idle | eager | observer | scroll
    frameKey = 0;
    expanded = false; // CSS pseudo-fullscreen
    fullscreen = false; // native Fullscreen API

    _url;
    _eager = false;
    _parsed = null;
    _armedUrl = null;
    _observer = null;
    _scrollHandler = null;
    _scrollTick = false;
    _timer = null;
    _fullscreenHandler = null;
    _keydownHandler = null;
    _savedBodyOverflow = null;
    _returnFocus = null;

    @api
    get url() {
        return this._url;
    }
    set url(value) {
        this._url = value;
        this._parsed = parseScribeUrl(value);
        this.resetLoad();
    }

    @api
    get eager() {
        return this._eager;
    }
    set eager(value) {
        this._eager = value === true || value === '' || value === 'true';
    }

    // ---- derived -----------------------------------------------------------------

    get isScribe() {
        return this._parsed !== null;
    }

    get displayTitle() {
        return this.title || titleFromSlug(this._parsed ? this._parsed.slug : '') || 'Interactive guide';
    }

    get frameTitle() {
        return `${this.displayTitle} — interactive guide`;
    }

    get embedSrc() {
        return this._parsed ? toEmbedUrl(this._parsed, { mode: this.mode }) : null;
    }

    get shareUrl() {
        return toShareUrl(this._parsed);
    }

    /** The iframe exists only once loading starts; bumping the key remounts it. */
    get frameItems() {
        return this.state === 'idle' ? [] : [{ key: `frame-${this.frameKey}` }];
    }

    get showSkeleton() {
        return this.state === 'idle' || this.state === 'loading';
    }

    get showFallback() {
        return this.state === 'failed';
    }

    get isBusy() {
        return this.showSkeleton ? 'true' : 'false';
    }

    get isEnlarged() {
        return this.fullscreen || this.expanded;
    }

    get expandLabel() {
        return this.isEnlarged ? 'Exit full screen' : 'Expand';
    }

    get expandIconPath() {
        return this.isEnlarged ? ICON.collapse : ICON.expand;
    }

    get scribeIconPath() {
        return ICON.scribe;
    }

    get externalIconPath() {
        return ICON.external;
    }

    get wrapperClass() {
        const classes = ['se'];
        if (this.expanded) {
            classes.push('se--expanded');
        }
        if (this.fullscreen) {
            classes.push('se--fullscreen');
        }
        return classes.join(' ');
    }

    get frameClass() {
        return this.state === 'failed' ? 'se__frame se__frame--hidden' : 'se__frame';
    }

    // ---- lifecycle -------------------------------------------------------------------

    connectedCallback() {
        this._fullscreenHandler = () => this.syncFullscreen();
        document.addEventListener('fullscreenchange', this._fullscreenHandler);
    }

    disconnectedCallback() {
        this.clearTimer();
        this.disconnectObserver();
        if (this._fullscreenHandler) {
            document.removeEventListener('fullscreenchange', this._fullscreenHandler);
            this._fullscreenHandler = null;
        }
        this.leavePseudo(false);
        this._armedUrl = null;
    }

    /**
     * Arm loading once per url: straight away when eager, otherwise when the
     * card approaches the viewport.
     */
    renderedCallback() {
        if (!this._parsed || this._armedUrl === this._url) {
            return;
        }
        this._armedUrl = this._url;
        if (this._eager) {
            this.lazyMode = 'eager';
            this.startLoad();
            return;
        }
        const target = this.template.querySelector('.se');
        if (!target) {
            this._armedUrl = null;
            return;
        }
        if (typeof IntersectionObserver !== 'undefined') {
            try {
                this._observer = new IntersectionObserver(
                    (entries) => {
                        if (entries.some((entry) => entry.isIntersecting)) {
                            this.disconnectObserver();
                            this.startLoad();
                        }
                    },
                    { rootMargin: LAZY_ROOT_MARGIN }
                );
                this._observer.observe(target);
                this.lazyMode = 'observer';
                return;
            } catch (e) {
                // A sandbox that exposes the constructor but refuses the
                // element: fall through to the position check.
                this._observer = null;
            }
        }
        this.lazyMode = 'scroll';
        this.armScrollFallback();
    }

    /**
     * No observer in this sandbox: check the card's position once the current
     * render settles, then on every scroll/resize (capture phase catches
     * nested scrollers), one check per animation frame. The first check is
     * deferred to a microtask because this runs from renderedCallback, BEFORE
     * the host article viewer's own renderedCallback injects its html
     * segments — measured synchronously, every card sits near the top of a
     * still-collapsed page and looks in range.
     */
    armScrollFallback() {
        const check = () => {
            this._scrollTick = false;
            if (!this._scrollHandler) {
                return; // disconnected meanwhile
            }
            const card = this.template.querySelector('.se');
            if (card && this.isNearViewport(card)) {
                this.disconnectObserver();
                this.startLoad();
            }
        };
        this._scrollHandler = () => {
            if (this._scrollTick) {
                return;
            }
            this._scrollTick = true;
            if (typeof requestAnimationFrame === 'function') {
                requestAnimationFrame(check);
            } else {
                setTimeout(check, 0);
            }
        };
        window.addEventListener('scroll', this._scrollHandler, true);
        window.addEventListener('resize', this._scrollHandler);
        this._scrollTick = true;
        Promise.resolve().then(check);
    }

    isNearViewport(el) {
        const rect = el.getBoundingClientRect();
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
        return rect.top < viewportHeight + LAZY_MARGIN_PX && rect.bottom > -LAZY_MARGIN_PX;
    }

    // ---- loading ------------------------------------------------------------------------

    resetLoad() {
        this.clearTimer();
        this.disconnectObserver();
        this.state = 'idle';
        this.lazyMode = 'idle';
        this._armedUrl = null;
    }

    startLoad() {
        this.state = 'loading';
        this.clearTimer();
        this._timer = setTimeout(() => {
            this._timer = null;
            if (this.state === 'loading') {
                this.fail();
            }
        }, LOAD_TIMEOUT_MS);
    }

    handleFrameLoad(event) {
        if (this.state === 'idle') {
            return;
        }
        this.clearTimer();
        // A CSP-refused navigation leaves a readable same-origin about:blank
        // behind; a real cross-origin Scribe document is opaque (null). Locker
        // may throw on the read — treat that as loaded and let the frame speak.
        let blocked = false;
        try {
            blocked = Boolean(event.target && event.target.contentDocument);
        } catch (e) {
            blocked = false;
        }
        if (blocked) {
            this.fail();
            return;
        }
        this.state = 'ready';
        this.dispatchEvent(new CustomEvent('scribeready', {
            detail: { url: this._url }, bubbles: true, composed: true
        }));
    }

    handleFrameError() {
        if (this.state !== 'idle') {
            this.clearTimer();
            this.fail();
        }
    }

    handleRetry() {
        this.frameKey += 1;
        this.startLoad();
    }

    fail() {
        this.state = 'failed';
        this.dispatchEvent(new CustomEvent('scribefail', {
            detail: { url: this._url }, bubbles: true, composed: true
        }));
    }

    clearTimer() {
        if (this._timer) {
            clearTimeout(this._timer);
            this._timer = null;
        }
    }

    /** Stops both lazy-load mechanisms (observer and scroll fallback). */
    disconnectObserver() {
        if (this._observer) {
            this._observer.disconnect();
            this._observer = null;
        }
        if (this._scrollHandler) {
            window.removeEventListener('scroll', this._scrollHandler, true);
            window.removeEventListener('resize', this._scrollHandler);
            this._scrollHandler = null;
        }
        this._scrollTick = false;
    }

    // ---- expand / fullscreen ------------------------------------------------------

    handleToggleExpand() {
        if (this.isEnlarged) {
            this.exitEnlarged();
            return;
        }
        this._returnFocus = this.template.querySelector('.se__btn--expand');
        const card = this.template.querySelector('.se');
        if (card && typeof card.requestFullscreen === 'function' && document.fullscreenEnabled) {
            let request;
            try {
                request = card.requestFullscreen();
            } catch (e) {
                this.enterPseudo();
                return;
            }
            if (request && typeof request.catch === 'function') {
                request.catch(() => this.enterPseudo());
            }
            return;
        }
        this.enterPseudo();
    }

    exitEnlarged() {
        if (this.fullscreen && typeof document.exitFullscreen === 'function') {
            try {
                const exit = document.exitFullscreen();
                if (exit && typeof exit.catch === 'function') {
                    exit.catch(() => {});
                }
            } catch (e) {
                // fall through — the change event will not fire; clear locally
                this.fullscreen = false;
            }
        }
        this.leavePseudo(true);
    }

    /** Native fullscreen state, read after every fullscreenchange. */
    syncFullscreen() {
        const card = this.template.querySelector('.se');
        let local = null;
        try {
            local = this.template.fullscreenElement;
        } catch (e) {
            local = null;
        }
        const active = Boolean(card) && ((local != null && local === card) || document.fullscreenElement === card);
        if (this.fullscreen && !active) {
            this.restoreFocus();
        }
        this.fullscreen = active;
    }

    enterPseudo() {
        if (this.expanded) {
            return;
        }
        this.expanded = true;
        this._savedBodyOverflow = document.body.style.overflow;
        document.body.style.overflow = 'hidden';
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' && this.expanded) {
                this.leavePseudo(true);
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
    }

    leavePseudo(refocus) {
        if (this._keydownHandler) {
            window.removeEventListener('keydown', this._keydownHandler);
            this._keydownHandler = null;
        }
        if (!this.expanded) {
            return;
        }
        this.expanded = false;
        document.body.style.overflow = this._savedBodyOverflow || '';
        this._savedBodyOverflow = null;
        if (refocus) {
            this.restoreFocus();
        }
    }

    restoreFocus() {
        const target = this._returnFocus;
        this._returnFocus = null;
        if (target && target.isConnected && typeof target.focus === 'function') {
            target.focus();
        }
    }
}