import { LightningElement, api, track } from 'lwc';
import {
    animateRect,
    computeCardPosition,
    getFocusables,
    prefersReducedMotion,
    rafThrottle
} from 'c/tourDom';

const SPOTLIGHT_PAD = 8; // px of breathing room around the target rect
const SPOTLIGHT_RADIUS = 12; // px cutout corner radius (mirrors --tour-spotlight-radius)
const SLIDE_DURATION = 350; // ms spotlight glide (mirrors --tour-duration)
const CONTENT_SWAP_MS = 160; // ms card-content cross-fade out

/**
 * Presentational half of the tour: the blurred scrim, the feathered animated
 * spotlight, and the coach-mark card. Fully controlled — it receives the
 * target element and step content via @api and only ever reads
 * getBoundingClientRect() from the target, so it runs identically at runtime
 * (under c-tour-launcher) and inside the Tour Builder preview.
 *
 * Events (plain, parent-only): next, back, skip {dismissed}, finish.
 */
export default class TourOverlay extends LightningElement {
    @api stepCount = 0;
    @api stepTitle = '';
    @api stepBody = '';
    @api placement = 'auto';
    @api advanceOn = 'button';
    @api showDismissForever = false;

    // Displayed copies of the step props: content swaps in sync with the
    // cross-fade instead of the instant LWC re-render.
    @track dTitle = '';
    @track dBody = '';
    @track dStepIndex = 0;
    @track dAdvanceOn = 'button';
    _leaving = false;
    _caretSide = 'top';

    _targetElement = null;
    _stepIndex = 0;
    _active = false;

    _wired = false;
    _hasShown = false;
    _syncQueued = false;
    _retryFrames = 0;
    _swapTimer = null;
    _cancelAnim = null;
    _currentRect = null;
    _previouslyFocused = null;
    _viewportHandler = null;

    // ---- controlled props ------------------------------------------------------

    @api
    get targetElement() {
        return this._targetElement;
    }
    set targetElement(value) {
        this._targetElement = value;
        this._scheduleSync();
    }

    @api
    get stepIndex() {
        return this._stepIndex;
    }
    set stepIndex(value) {
        this._stepIndex = value || 0;
        this._scheduleSync();
    }

    @api
    get active() {
        return this._active;
    }
    set active(value) {
        const next = Boolean(value);
        if (next === this._active) {
            return;
        }
        this._active = next;
        if (next) {
            this._previouslyFocused =
                document.activeElement && document.activeElement !== document.body
                    ? document.activeElement
                    : null;
        } else {
            const target = this._previouslyFocused;
            this._previouslyFocused = null;
            if (target && target.isConnected && typeof target.focus === 'function') {
                target.focus();
            }
        }
    }

    // ---- lifecycle ---------------------------------------------------------------

    connectedCallback() {
        this._viewportHandler = rafThrottle(() => this._reposition());
        window.addEventListener('resize', this._viewportHandler);
        window.addEventListener('scroll', this._viewportHandler, { capture: true, passive: true });
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._viewportHandler);
        window.removeEventListener('scroll', this._viewportHandler, { capture: true });
        this._viewportHandler = null;
        if (this._cancelAnim) {
            this._cancelAnim();
            this._cancelAnim = null;
        }
        if (this._swapTimer) {
            clearTimeout(this._swapTimer);
            this._swapTimer = null;
        }
    }

    renderedCallback() {
        if (!this._wired) {
            this._wired = true;
            this._wireSvgIds();
            this._syncViewport();
            this._scheduleSync();
        }
    }

    // ---- template state ------------------------------------------------------------

    get overlayClass() {
        return this._active ? 'tour-overlay tour-overlay--active' : 'tour-overlay';
    }

    get cardInnerClass() {
        return this._leaving
            ? 'tour-overlay__card-inner tour-overlay__card-inner--leaving'
            : 'tour-overlay__card-inner';
    }

    get caretClass() {
        return `tour-overlay__caret tour-overlay__caret--${this._caretSide}`;
    }

    get progressLabel() {
        return `${this.dStepIndex + 1} of ${this.stepCount}`;
    }

    get dots() {
        const items = [];
        for (let i = 0; i < this.stepCount; i++) {
            items.push({
                key: `dot-${i}`,
                className:
                    i === this.dStepIndex
                        ? 'tour-overlay__dot tour-overlay__dot--active'
                        : 'tour-overlay__dot'
            });
        }
        return items;
    }

    get showBack() {
        return this.dStepIndex > 0;
    }

    get nextLabel() {
        return this.dStepIndex >= this.stepCount - 1 ? 'Finish' : 'Next';
    }

    get showClickHint() {
        return this.dAdvanceOn === 'click';
    }

    // ---- actions ----------------------------------------------------------------------

    handleNextClick() {
        if (this.dStepIndex >= this.stepCount - 1) {
            this.dispatchEvent(new CustomEvent('finish'));
        } else {
            this.dispatchEvent(new CustomEvent('next'));
        }
    }

    handleBackClick() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleSkipClick() {
        this.dispatchEvent(new CustomEvent('skip', { detail: { dismissed: false } }));
    }

    handleDismissForever() {
        this.dispatchEvent(new CustomEvent('skip', { detail: { dismissed: true } }));
    }

    // Soft focus wrap: Tab off the last card control loops to the first and
    // vice versa (same sentinel technique as dsModalV2, minus slot walking).
    handleSentinelStart() {
        const focusables = this._cardFocusables();
        const last = focusables[focusables.length - 1];
        if (last) {
            last.focus();
        }
    }

    handleSentinelEnd() {
        const [first] = this._cardFocusables();
        if (first) {
            first.focus();
        }
    }

    _cardFocusables() {
        const card = this.refs.card;
        return getFocusables(card).filter(
            (el) => !el.classList || !el.classList.contains('tour-overlay__sentinel')
        );
    }

    // ---- step sync (content swap + geometry) ---------------------------------------------

    _scheduleSync() {
        if (this._syncQueued || !this._wired) {
            return;
        }
        this._syncQueued = true;
        Promise.resolve().then(() => {
            this._syncQueued = false;
            this._syncStep();
        });
    }

    _syncStep() {
        if (!this._targetElement || !this._targetElement.isConnected) {
            // The target can be momentarily disconnected mid-rerender; re-arm a
            // bounded retry so the overlay never strands unpositioned.
            if (this._retryFrames < 30) {
                this._retryFrames++;
                requestAnimationFrame(() => this._scheduleSync());
            }
            return;
        }
        this._retryFrames = 0;
        if (!this._hasShown) {
            this._hasShown = true;
            this._applyContent();
            requestAnimationFrame(() => {
                this._positionAll(true);
                this._focusNext();
            });
            return;
        }
        // Cross-fade: content out → swap → geometry glides → content in.
        this._leaving = true;
        if (this._swapTimer) {
            clearTimeout(this._swapTimer);
        }
        const swapDelay = prefersReducedMotion() ? 0 : CONTENT_SWAP_MS;
        this._swapTimer = setTimeout(() => {
            this._swapTimer = null;
            this._applyContent();
            requestAnimationFrame(() => {
                this._positionAll(false);
                this._leaving = false;
                this._focusNext();
            });
        }, swapDelay);
    }

    _applyContent() {
        this.dTitle = this.stepTitle || '';
        this.dBody = this.stepBody || '';
        this.dStepIndex = this._stepIndex;
        this.dAdvanceOn = this.advanceOn || 'button';
    }

    _positionAll(jump) {
        const rect = this._measureTarget();
        if (!rect) {
            return;
        }

        // Spotlight: rAF-interpolated so mask, glow and blur hole stay locked.
        if (this._cancelAnim) {
            this._cancelAnim();
        }
        const duration = jump || prefersReducedMotion() ? 0 : SLIDE_DURATION;
        this._cancelAnim = animateRect(
            this._currentRect,
            rect,
            duration,
            (r) => this._applySpotlight(r),
            () => {
                this._cancelAnim = null;
            }
        );

        this._positionCard(rect, jump);
    }

    _reposition() {
        // Scroll/resize track the target 1:1 — no spring, it would feel laggy.
        if (!this._hasShown || !this._targetElement || !this._targetElement.isConnected) {
            return;
        }
        this._syncViewport();
        const rect = this._measureTarget();
        if (!rect) {
            return;
        }
        if (this._cancelAnim) {
            this._cancelAnim();
            this._cancelAnim = null;
        }
        this._applySpotlight(rect);
        this._positionCard(rect, true);
    }

    _measureTarget() {
        const r = this._targetElement.getBoundingClientRect();
        if (!r.width && !r.height) {
            return null;
        }
        return {
            x: r.x - SPOTLIGHT_PAD,
            y: r.y - SPOTLIGHT_PAD,
            width: r.width + SPOTLIGHT_PAD * 2,
            height: r.height + SPOTLIGHT_PAD * 2
        };
    }

    /**
     * Where the overlay's fixed layers actually landed. Normally (0,0), but a
     * transformed/filtered ancestor (e.g. core Lightning page chrome) becomes
     * the containing block for position:fixed and shifts every layer — while
     * targets are measured in true viewport coordinates. Subtracting this
     * origin from all applied geometry re-aligns the two coordinate spaces.
     */
    _origin() {
        const shell = this.refs.shell;
        if (!shell) {
            return { x: 0, y: 0 };
        }
        const b = shell.getBoundingClientRect();
        return { x: b.x, y: b.y };
    }

    _toLocal(rect, o) {
        return rect
            ? { x: rect.x - o.x, y: rect.y - o.y, width: rect.width, height: rect.height }
            : null;
    }

    _applySpotlight(rect) {
        this._currentRect = rect;
        const { cutout, glow, blur, shield } = this.refs;
        if (!cutout) {
            return;
        }
        const o = this._origin();
        const r = this._toLocal(rect, o);
        cutout.setAttribute('x', r.x);
        cutout.setAttribute('y', r.y);
        cutout.setAttribute('width', Math.max(r.width, 0));
        cutout.setAttribute('height', Math.max(r.height, 0));
        glow.setAttribute('x', r.x);
        glow.setAttribute('y', r.y);
        glow.setAttribute('width', Math.max(r.width, 0));
        glow.setAttribute('height', Math.max(r.height, 0));
        blur.style.clipPath = this._holePath(r, o);
        shield.setAttribute('d', this._shieldPath(r, o));
    }

    /** Inner rounded-rect subpath — the spotlight hole, shared by the blur
     *  clip-path and the click shield so their geometry can never drift. */
    _innerHolePath(rect) {
        const r = Math.min(SPOTLIGHT_RADIUS, rect.width / 2, rect.height / 2);
        const x = rect.x;
        const y = rect.y;
        const w = rect.width;
        const h = rect.height;
        return (
            `M${x + r} ${y}` +
            `H${x + w - r}` +
            `A${r} ${r} 0 0 1 ${x + w} ${y + r}` +
            `V${y + h - r}` +
            `A${r} ${r} 0 0 1 ${x + w - r} ${y + h}` +
            `H${x + r}` +
            `A${r} ${r} 0 0 1 ${x} ${y + h - r}` +
            `V${y + r}` +
            `A${r} ${r} 0 0 1 ${x + r} ${y}` +
            `Z`
        );
    }

    /** The viewport rect expressed in overlay-local coordinates. */
    _viewportFrame(o) {
        const x0 = -o.x;
        const y0 = -o.y;
        const x1 = window.innerWidth - o.x;
        const y1 = window.innerHeight - o.y;
        return `M${x0} ${y0}H${x1}V${y1}H${x0}Z`;
    }

    /**
     * Frame-with-a-hole for the blur layer: outer viewport rect plus an inner
     * rounded-rect subpath, combined with evenodd so the spotlight stays crisp
     * while everything around it blurs. Both in overlay-local coordinates.
     */
    _holePath(localRect, o) {
        return `path(evenodd, "${this._viewportFrame(o)} ${this._innerHolePath(localRect)}")`;
    }

    /**
     * Click-shield geometry. Button steps block the whole viewport; click
     * steps punch the spotlight hole so only the highlighted element is
     * clickable (evenodd applies to SVG hit-testing too).
     */
    _shieldPath(localRect, o) {
        const frame = this._viewportFrame(o);
        if (this.dAdvanceOn === 'click' && localRect) {
            return `${frame} ${this._innerHolePath(localRect)}`;
        }
        return frame;
    }

    _positionCard(rect, jump) {
        const card = this.refs.card;
        if (!card) {
            return;
        }
        const size = { width: card.offsetWidth, height: card.offsetHeight };
        const pos = computeCardPosition(rect, size, this.placement || 'auto', {
            width: window.innerWidth,
            height: window.innerHeight
        });

        if (jump) {
            // Suppress the spring transition for instant tracking (first paint,
            // scroll/resize), restore it next frame.
            card.style.transition = 'none';
            requestAnimationFrame(() => {
                card.style.transition = '';
            });
        }
        // pos is viewport-space; shift into overlay-local space (see _origin).
        const o = this._origin();
        card.style.transform = `translate3d(${Math.round(pos.left - o.x)}px, ${Math.round(pos.top - o.y)}px, 0)`;

        this._caretSide = pos.caret.side;
        const caret = this.refs.caret;
        if (pos.caret.side === 'top' || pos.caret.side === 'bottom') {
            caret.style.left = `${Math.round(pos.caret.offset) - 6}px`;
            caret.style.top = '';
        } else {
            caret.style.top = `${Math.round(pos.caret.offset) - 6}px`;
            caret.style.left = '';
        }
    }

    _focusNext() {
        const btn = this.refs.nextBtn;
        if (btn && this._active !== false) {
            try {
                btn.focus({ preventScroll: true });
            } catch (e) {
                btn.focus();
            }
        }
    }

    // ---- SVG plumbing -----------------------------------------------------------------

    /**
     * LWC mangles template ids at compile time, which breaks url(#...)
     * references between the filter/mask and their consumers — so unique ids
     * are generated and wired at runtime instead.
     */
    _wireSvgIds() {
        const uid = `tour${Math.random().toString(36).slice(2, 10)}`;
        const { feather, mask, cutout, scrimRect, title, body, card } = this.refs;

        feather.setAttribute('id', `${uid}-feather`);
        mask.setAttribute('id', `${uid}-mask`);
        cutout.setAttribute('filter', `url(#${uid}-feather)`);
        scrimRect.setAttribute('mask', `url(#${uid}-mask)`);

        title.setAttribute('id', `${uid}-title`);
        body.setAttribute('id', `${uid}-body`);
        card.setAttribute('aria-labelledby', `${uid}-title`);
        card.setAttribute('aria-describedby', `${uid}-body`);
    }

    /** Sizes the SVG canvas and the (oversized) mask base to the viewport,
     *  expressed in overlay-local coordinates (see _origin). */
    _syncViewport() {
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        const { svg, mask, maskBase, scrimRect, shield } = this.refs;
        if (!svg) {
            return;
        }
        const o = this._origin();
        shield.setAttribute('d', this._shieldPath(this._toLocal(this._currentRect, o), o));
        svg.setAttribute('width', vw);
        svg.setAttribute('height', vh);
        // The mask base extends past the viewport so the feather blur never
        // lightens the screen edges.
        mask.setAttribute('x', -o.x - 40);
        mask.setAttribute('y', -o.y - 40);
        mask.setAttribute('width', vw + 80);
        mask.setAttribute('height', vh + 80);
        maskBase.setAttribute('x', -o.x - 40);
        maskBase.setAttribute('y', -o.y - 40);
        maskBase.setAttribute('width', vw + 80);
        maskBase.setAttribute('height', vh + 80);
        scrimRect.setAttribute('x', -o.x);
        scrimRect.setAttribute('y', -o.y);
        scrimRect.setAttribute('width', vw);
        scrimRect.setAttribute('height', vh);
    }
}