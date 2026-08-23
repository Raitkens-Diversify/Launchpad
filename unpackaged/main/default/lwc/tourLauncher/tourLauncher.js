import { LightningElement, api } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import getTour from '@salesforce/apex/TutorialTourController.getTour';
import getUserState from '@salesforce/apex/TutorialTourController.getUserState';
import saveState from '@salesforce/apex/TutorialTourController.saveState';
import { waitForTarget, prefersReducedMotion } from 'c/tourDom';

const FADE_OUT_MS = 220; // matches --tour-duration-fast + a little slack
const RECT_STABLE_CAP_MS = 1200; // long enough for a smooth full-page scroll-to-top
const WATCH_INTERVAL_MS = 400; // target-liveness poll while a step is showing
const REFIND_TIMEOUT_MS = 1000; // grace to re-find a target replaced by a re-render
const CLICK_ADVANCE_PAD = 8; // mirrors SPOTLIGHT_PAD in c/tourOverlay

/**
 * Tour engine. Drop once on any page (Experience Builder region or host
 * component markup) with a tour-key; the published tour, per-user state and
 * the premium overlay child do the rest. Surface-agnostic: LWR guest,
 * LWR authenticated, and core Lightning pages.
 *
 * Design rule: a broken tour must NEVER break the host page — every load or
 * persistence failure degrades to "no tour" with a console.warn.
 */
export default class TourLauncher extends LightningElement {
    /** API key of the published tour to run (Tutorial_Tour__mdt.Tour_Key__c). */
    @api tourKey;
    /**
     * 'auto' (default): start when the tour allows it and the user hasn't
     * completed/dismissed it. 'never': only via the start() API. 'always':
     * ignore saved state — for testing a tour.
     */
    @api autoStartOverride = 'auto';

    overlayRendered = false;
    overlayActive = false;
    currentTarget = null;
    stepIndex = 0;

    _tour = null;
    _state = null;
    _running = false;
    _direction = 1;
    _shownCount = 0;
    _missCount = 0;
    _generation = 0;
    _targetCache = new Map();
    _searchRoots = null;
    _fadeTimer = null;
    _keydownHandler = null;
    _clickHandler = null;
    _watchTimer = null;

    // ---- lifecycle -----------------------------------------------------------

    connectedCallback() {
        this._keydownHandler = (event) => this._handleKeydown(event);
        window.addEventListener('keydown', this._keydownHandler);
        this._init();
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._keydownHandler);
        this._keydownHandler = null;
        this._detachClickAdvance();
        this._clearTargetWatch();
        this._generation++;
        if (this._fadeTimer) {
            clearTimeout(this._fadeTimer);
            this._fadeTimer = null;
        }
    }

    async _init() {
        if (!this.tourKey) {
            return;
        }
        try {
            this._tour = await getTour({ tourKey: this.tourKey });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn(`tour: could not load "${this.tourKey}"`, e);
            return;
        }
        if (!this._tour || !this._tour.steps || this._tour.steps.length === 0) {
            return;
        }

        this._state = await this._readState();

        if (this.autoStartOverride === 'never') {
            return;
        }
        if (this.autoStartOverride !== 'always') {
            if (this._isSuppressed() || !this._tour.autoStart) {
                return;
            }
        }
        this.start();
    }

    // ---- public API ----------------------------------------------------------

    /** Starts (or restarts) the tour at step 1. */
    @api
    start() {
        if (!this._tour || !this._tour.steps.length || this._running) {
            return;
        }
        this._running = true;
        this._shownCount = 0;
        this._missCount = 0;
        this._direction = 1;
        this._showStep(0);
    }

    @api
    next() {
        if (!this._running) {
            return;
        }
        if (this.stepIndex >= this._tour.steps.length - 1) {
            this.finish();
            return;
        }
        this._direction = 1;
        this._showStep(this.stepIndex + 1);
    }

    @api
    back() {
        if (!this._running || this.stepIndex === 0) {
            return;
        }
        this._direction = -1;
        this._showStep(this.stepIndex - 1);
    }

    /**
     * Ends the tour without completing it. Both the Skip link and "Don't show
     * this again" persist dismissed=true (suppressed until a version bump);
     * the flag is kept as a parameter for future analytics distinction.
     */
    @api
    skip(dismissed = false) {
        if (!this._running) {
            return;
        }
        this._stop();
        this._persist({ completed: false, dismissed: true, versionSeen: this._tour.version, wasDismissLink: dismissed });
    }

    /** Ends the tour as completed. */
    @api
    finish() {
        if (!this._running) {
            return;
        }
        const sawAnyStep = this._shownCount > 0;
        this._stop();
        // Zero-steps-shown guard: if no target ever resolved (e.g. the user is
        // on a view without any of the tour's targets), stay eligible for the
        // next visit instead of recording a completion the user never saw.
        if (sawAnyStep) {
            this._persist({ completed: true, dismissed: false, versionSeen: this._tour.version });
        }
    }

    // ---- overlay events --------------------------------------------------------

    handleNext() {
        this.next();
    }

    handleBack() {
        this.back();
    }

    handleSkip(event) {
        this.skip(Boolean(event.detail && event.detail.dismissed));
    }

    handleFinish() {
        this.finish();
    }

    // ---- step machinery --------------------------------------------------------

    get stepCount() {
        return this._tour ? this._tour.steps.length : 0;
    }

    get currentStep() {
        return this._tour ? this._tour.steps[this.stepIndex] : null;
    }

    get currentTitle() {
        return this.currentStep ? this.currentStep.title : '';
    }

    get currentBody() {
        return this.currentStep ? this.currentStep.body : '';
    }

    get currentPlacement() {
        return this.currentStep ? this.currentStep.placement : 'auto';
    }

    get currentAdvanceOn() {
        return this.currentStep ? this.currentStep.advanceOn : 'button';
    }

    async _showStep(index) {
        const gen = ++this._generation;
        this._detachClickAdvance();
        this._clearTargetWatch();

        if (index >= this._tour.steps.length) {
            this.finish();
            return;
        }
        if (index < 0) {
            return; // walked off the front going backward — stay put
        }

        const step = this._tour.steps[index];
        let el = this._targetCache.get(index);
        if (!el || !el.isConnected) {
            el = await waitForTarget(step.targetSelector, { roots: this._resolveSearchRoots() });
            if (gen !== this._generation) {
                return; // superseded by a newer navigation
            }
        }

        if (!el) {
            // eslint-disable-next-line no-console
            console.warn(`tour: target not found for step ${index + 1}: ${step.targetSelector} — skipping`);
            this._missCount++;
            if (this._missCount >= this._tour.steps.length) {
                // Every step failed to resolve: end deterministically (and
                // silently for the user) rather than walking off an end.
                // Nothing persists, so the tour stays eligible next visit.
                // eslint-disable-next-line no-console
                console.warn('tour: ended — no targets reachable on this page');
                this._stop();
                return;
            }
            this._showStep(index + this._direction);
            return;
        }
        this._missCount = 0;
        this._targetCache.set(index, el);

        await this._settleIntoView(el, gen);
        if (gen !== this._generation) {
            return;
        }

        this.stepIndex = index;
        this.currentTarget = el;
        this._shownCount++;
        this._mountOverlay();

        if (step.advanceOn === 'click') {
            this._attachClickAdvance(el);
        }
        this._startTargetWatch(el, step, index, gen);
    }

    // ---- target watchdog ---------------------------------------------------------

    /**
     * Watches the spotlighted element while its step is showing. If it
     * disconnects or collapses to a zero rect (view swap, re-render), one
     * short re-find absorbs element replacement; failing that, the tour ends
     * quietly via _stop() — nothing persists, so the user stays eligible on
     * the next visit instead of being stranded under a stale spotlight.
     */
    _startTargetWatch(el, step, index, gen) {
        this._clearTargetWatch();
        this._watchTimer = setInterval(() => {
            if (gen !== this._generation) {
                this._clearTargetWatch();
                return;
            }
            if (el.isConnected) {
                const r = el.getBoundingClientRect();
                if (r.width > 0 && r.height > 0) {
                    return;
                }
            }
            this._clearTargetWatch();
            waitForTarget(step.targetSelector, {
                roots: this._resolveSearchRoots(),
                timeout: REFIND_TIMEOUT_MS
            }).then((found) => {
                if (gen !== this._generation) {
                    return;
                }
                if (found) {
                    this._targetCache.set(index, found);
                    this.currentTarget = found;
                    if (step.advanceOn === 'click') {
                        this._detachClickAdvance();
                        this._attachClickAdvance(found);
                    }
                    this._startTargetWatch(found, step, index, gen);
                    return;
                }
                // eslint-disable-next-line no-console
                console.warn(`tour: target for step ${index + 1} disappeared — ending quietly`);
                this._stop();
            });
        }, WATCH_INTERVAL_MS);
    }

    _clearTargetWatch() {
        if (this._watchTimer) {
            clearInterval(this._watchTimer);
            this._watchTimer = null;
        }
    }

    /**
     * Search origins for target resolution, nearest first. The launcher's own
     * containing shadow root (its host component's template) is the primary
     * origin: from there the walk only crosses same-namespace `c-*` shadow
     * roots, which are readable on every surface. A document walk is kept as
     * a fallback for light-DOM/legacy targets, but on core Lightning pages it
     * gets severed by platform shadow roots that read null under LWS — which
     * is exactly why it must not be the only path.
     */
    _resolveSearchRoots() {
        if (!this._searchRoots) {
            const roots = [];
            try {
                const host = this.template.host;
                const rootNode = host && host.getRootNode ? host.getRootNode() : null;
                if (rootNode && rootNode !== document) {
                    roots.push(rootNode);
                }
            } catch (e) {
                // sandbox refused getRootNode — fall through to document
            }
            roots.push(document);
            this._searchRoots = roots;
        }
        return this._searchRoots;
    }

    /**
     * Centers the target, then waits until its rect is stable for two frames
     * (capped) so the spotlight never animates toward a still-moving rect.
     * `scrollend` isn't reliable cross-browser, hence the rect polling.
     */
    _settleIntoView(el, gen) {
        const reduced = prefersReducedMotion();
        if (!this._scrollPinnedHome(el, reduced)) {
            el.scrollIntoView({ block: 'center', behavior: reduced ? 'auto' : 'smooth' });
        }
        return new Promise((resolve) => {
            const started = Date.now();
            let last = null;
            const check = () => {
                if (gen !== this._generation) {
                    resolve();
                    return;
                }
                const r = el.getBoundingClientRect();
                const key = `${Math.round(r.x)}|${Math.round(r.y)}|${Math.round(r.width)}|${Math.round(r.height)}`;
                if (key === last || Date.now() - started > RECT_STABLE_CAP_MS) {
                    resolve();
                    return;
                }
                last = key;
                requestAnimationFrame(check);
            };
            requestAnimationFrame(check);
        });
    }

    /**
     * scrollIntoView is a no-op for targets pinned by position:sticky/fixed —
     * a stuck header is always "in view", so the page would stay wherever the
     * previous step left it. Pinned chrome lives at the top of its scroller,
     * so instead scroll every scrolled ancestor (and the window) back to the
     * top, bringing the user all the way up before the spotlight lands.
     * @returns true when the target was pinned and handled here.
     */
    _scrollPinnedHome(el, reduced) {
        const behavior = reduced ? 'auto' : 'smooth';
        let pinned = null;
        for (let node = el; node && node !== document.documentElement; ) {
            const pos = window.getComputedStyle(node).position;
            if (pos === 'sticky' || pos === 'fixed') {
                pinned = node;
                break;
            }
            // parentElement is null at a shadow root — hop to the host.
            node = node.parentElement
                || (node.getRootNode && node.getRootNode().host)
                || null;
        }
        if (!pinned) {
            return false;
        }
        for (let node = pinned; node; ) {
            if (node.scrollTop > 0 && typeof node.scrollTo === 'function') {
                node.scrollTo({ top: 0, behavior });
            }
            node = node.parentElement
                || (node.getRootNode && node.getRootNode().host)
                || null;
        }
        window.scrollTo({ top: 0, behavior });
        return true;
    }

    _mountOverlay() {
        if (this._fadeTimer) {
            clearTimeout(this._fadeTimer);
            this._fadeTimer = null;
        }
        this.overlayRendered = true;
        if (!this.overlayActive) {
            // Let the overlay render once before fading in.
            requestAnimationFrame(() => {
                this.overlayActive = true;
            });
        }
    }

    _stop() {
        this._running = false;
        this._generation++;
        this._detachClickAdvance();
        this._clearTargetWatch();
        this._targetCache.clear();
        this.overlayActive = false; // fade out…
        this._fadeTimer = setTimeout(() => {
            this.overlayRendered = false; // …then unmount
            this.currentTarget = null;
            this._fadeTimer = null;
        }, FADE_OUT_MS);
    }

    // ---- advance-on-click ------------------------------------------------------

    _attachClickAdvance(target) {
        // Capture-phase listener on window: the shield leaves the spotlight
        // hole open, so the page click happens naturally and the engine just
        // observes it. composedPath pierces open shadow roots.
        this._clickHandler = (event) => {
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            const overlay = this.template.querySelector('c-tour-overlay');
            if (overlay && path.includes(overlay)) {
                return; // card buttons and shield hits — never treat as target clicks
            }
            let hit = path.includes(target);
            if (!hit && target.isConnected) {
                // The shield hole is the padded spotlight rect, so a click can
                // land in the glowing area yet miss the target node — count it.
                const r = target.getBoundingClientRect();
                hit = event.clientX >= r.left - CLICK_ADVANCE_PAD
                    && event.clientX <= r.right + CLICK_ADVANCE_PAD
                    && event.clientY >= r.top - CLICK_ADVANCE_PAD
                    && event.clientY <= r.bottom + CLICK_ADVANCE_PAD;
            }
            if (hit) {
                this.next();
            }
        };
        window.addEventListener('click', this._clickHandler, true);
    }

    _detachClickAdvance() {
        if (this._clickHandler) {
            window.removeEventListener('click', this._clickHandler, true);
            this._clickHandler = null;
        }
    }

    // ---- keyboard ---------------------------------------------------------------

    _handleKeydown(event) {
        if (!this._running) {
            return;
        }
        if (event.key === 'Escape') {
            this.skip(false);
            return;
        }
        // Enter/arrows only act when the keystroke happened inside the tour
        // card — never hijack keys typed into the page.
        const overlay = this.template.querySelector('c-tour-overlay');
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        if (!overlay || !path.includes(overlay)) {
            return;
        }
        if (event.key === 'Enter' || event.key === 'ArrowRight') {
            event.preventDefault();
            this.next();
        } else if (event.key === 'ArrowLeft') {
            event.preventDefault();
            this.back();
        }
    }

    // ---- suppression + persistence ----------------------------------------------

    _isSuppressed() {
        const s = this._state;
        if (!s) {
            return false;
        }
        const seen = s.versionSeen == null ? -1 : s.versionSeen;
        return (s.completed || s.dismissed) && seen >= this._tour.version;
    }

    get _storageKey() {
        return `tour_${this.tourKey}_v${this._tour.version}`;
    }

    async _readState() {
        if (isGuest) {
            try {
                const raw = window.localStorage.getItem(this._storageKey);
                return raw ? JSON.parse(raw) : null;
            } catch (e) {
                return null; // storage unavailable → tour shows each visit
            }
        }
        try {
            return await getUserState({ tourKey: this.tourKey });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('tour: could not read state', e);
            return null;
        }
    }

    _persist(state) {
        const merged = { ...(this._state || {}), ...state };
        delete merged.wasDismissLink;
        this._state = merged;
        if (isGuest) {
            try {
                window.localStorage.setItem(this._storageKey, JSON.stringify({
                    completed: merged.completed === true,
                    dismissed: merged.dismissed === true,
                    versionSeen: merged.versionSeen
                }));
            } catch (e) {
                // Storage unavailable (private mode) — the tour re-shows next visit.
            }
            return;
        }
        saveState({
            tourKey: this.tourKey,
            completed: merged.completed === true,
            dismissed: merged.dismissed === true,
            versionSeen: merged.versionSeen
        }).catch((e) => {
            // eslint-disable-next-line no-console
            console.warn('tour: could not save state', e);
        });
    }
}