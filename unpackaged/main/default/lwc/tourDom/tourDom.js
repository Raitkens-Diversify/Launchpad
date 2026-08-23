/**
 * Shared DOM utilities for the guided tour framework (no template — a JS-only
 * service module, same pattern as c/nexsTopicIcons).
 *
 * Everything here is framework-free and pure so the launcher, overlay and
 * builder can share one implementation of the hard parts: shadow-piercing
 * target resolution, spring rect animation, and tooltip placement math.
 */

// Elements that can hold keyboard focus inside the tour card. Mirrors the
// selector used by dsModalV2 (lightning-* host tags delegate focus internally).
export const FOCUSABLE_SELECTOR = [
    'a[href]',
    'button:not([disabled])',
    'input:not([disabled])',
    'select:not([disabled])',
    'textarea:not([disabled])',
    'lightning-button',
    'lightning-button-icon',
    'lightning-input',
    'lightning-combobox',
    'lightning-textarea',
    '[tabindex]:not([tabindex="-1"])'
].join(',');

/**
 * Explicit search scopes registered by components that OWN tour targets.
 *
 * Why this exists: walking the shadow tree from the outside is at the mercy
 * of the platform sandbox — on core Lightning pages an intervening base
 * component's shadowRoot reads null under LWS and severs the walk entirely.
 * A component querying its OWN template is permitted in every sandbox mode,
 * so hosts hand deepQuery a guaranteed-searchable scope instead:
 *
 *   import { registerTourScope } from 'c/tourDom';
 *   connectedCallback()    { this._unregisterTourScope = registerTourScope(this.template); }
 *   disconnectedCallback() { this._unregisterTourScope?.(); }
 */
const tourScopes = new Set();

export function registerTourScope(scope) {
    if (!scope) {
        return () => {};
    }
    tourScopes.add(scope);
    return () => tourScopes.delete(scope);
}

/** @returns true when at least one live scope is registered (diagnostics). */
export function hasTourScopes() {
    for (const scope of tourScopes) {
        if (!scope.host || scope.host.isConnected) {
            return true;
        }
    }
    return false;
}

function queryScopes(selector) {
    for (const scope of tourScopes) {
        if (scope.host && !scope.host.isConnected) {
            continue; // stale registration (host unmounted without cleanup)
        }
        try {
            const match = scope.querySelector(selector);
            if (match) {
                return match;
            }
        } catch (e) {
            return null; // invalid selector
        }
    }
    return null;
}

/**
 * Shadow-piercing querySelector.
 *
 * Search order:
 *  1. Registered tour scopes (see registerTourScope) — exact and permitted in
 *     every sandbox mode; this is the reliable path on core Lightning pages.
 *  2. Fast path on `root`: under synthetic shadow a plain querySelector often
 *     pierces, and under native shadow it still catches light-DOM targets.
 *  3. Breadth-first walk from `root` descending into open shadow roots —
 *     same-namespace `c-*` roots are readable; hosts whose shadowRoot reads
 *     null under LWS (platform/base components) end that branch, which is why
 *     `root` should be as close to the targets as possible.
 * Slotted nodes stay light-DOM children of their host, so the per-scope
 * querySelector covers them without special handling.
 */
export function deepQuery(selector, root = document) {
    const scoped = queryScopes(selector);
    if (scoped) {
        return scoped;
    }

    let direct = null;
    try {
        direct = root.querySelector(selector);
    } catch (e) {
        return null; // invalid selector
    }
    if (direct) {
        return direct;
    }

    const start = root === document ? document.body : root;
    if (!start) {
        return null;
    }
    const queue = [start];
    while (queue.length) {
        const node = queue.shift();
        const scope = node.shadowRoot || node;
        if (scope !== root && typeof scope.querySelector === 'function') {
            const match = scope.querySelector(selector);
            if (match) {
                return match;
            }
        }
        if (typeof scope.querySelectorAll === 'function') {
            for (const el of scope.querySelectorAll('*')) {
                if (el.shadowRoot) {
                    queue.push(el);
                }
            }
        }
    }
    return null;
}

/**
 * Resolves to the target element once it exists AND has a non-zero rect
 * (a display:none target keeps waiting), or null after the timeout.
 *
 * `roots` lets the caller search several origins in order — typically the
 * launcher's own containing shadow root first, then the document.
 *
 * Polling instead of MutationObserver on purpose: observers can't see into
 * native shadow roots without attaching one per root, while ~20 polls of a
 * cheap traversal is negligible and absorbs @wire data latency.
 */
export function waitForTarget(selector, { timeout = 4000, interval = 200, root, roots } = {}) {
    const origins = (roots && roots.length ? roots : [root || document]).filter(Boolean);
    return new Promise((resolve) => {
        let settled = false;
        let intervalId = null;

        const settle = (value) => {
            if (settled) {
                return;
            }
            settled = true;
            if (intervalId) {
                clearInterval(intervalId);
            }
            if (value === null && !hasTourScopes()) {
                // eslint-disable-next-line no-console
                console.warn(
                    'tour: no tour scopes are registered — if the target lives inside a '
                    + "component's shadow DOM, have that component call registerTourScope"
                    + '(this.template) from c/tourDom.'
                );
            }
            resolve(value);
        };

        const tryFind = () => {
            for (const origin of origins) {
                const el = deepQuery(selector, origin);
                if (el) {
                    const rect = el.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0) {
                        settle(el);
                        return true;
                    }
                }
            }
            return false;
        };

        if (tryFind()) {
            return;
        }
        // One rAF retry catches "renders next frame", then slow polling.
        requestAnimationFrame(() => {
            if (settled || tryFind()) {
                return;
            }
            const deadline = Date.now() + timeout;
            intervalId = setInterval(() => {
                if (tryFind()) {
                    return;
                }
                if (Date.now() > deadline) {
                    settle(null);
                }
            }, interval);
        });
    });
}

// Spring-ish overshoot curve (easeOutBack) — the signature motion of the
// spotlight glide. Matches the CSS token --tour-ease-spring.
function easeOutBack(t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}

/**
 * rAF-interpolated rect animation. One JS interpolator (instead of CSS
 * transitions) because three consumers — the SVG mask rect, the glow rect and
 * the blur layer's clip-path string — must stay pixel-locked per frame.
 *
 * Returns a cancel function. A null `from` or non-positive duration jumps
 * straight to `to` (the reduced-motion path).
 */
export function animateRect(from, to, duration, onFrame, onDone) {
    if (!from || !duration || duration <= 0) {
        onFrame({ ...to });
        if (onDone) {
            onDone();
        }
        return () => {};
    }

    let rafId = null;
    let startTs = null;
    let cancelled = false;

    const step = (ts) => {
        if (cancelled) {
            return;
        }
        if (startTs === null) {
            startTs = ts;
        }
        const t = Math.min((ts - startTs) / duration, 1);
        const e = easeOutBack(t);
        onFrame({
            x: from.x + (to.x - from.x) * e,
            y: from.y + (to.y - from.y) * e,
            width: from.width + (to.width - from.width) * e,
            height: from.height + (to.height - from.height) * e
        });
        if (t < 1) {
            rafId = requestAnimationFrame(step);
        } else if (onDone) {
            onDone();
        }
    };

    rafId = requestAnimationFrame(step);
    return () => {
        cancelled = true;
        if (rafId) {
            cancelAnimationFrame(rafId);
        }
    };
}

/** Coalesces calls into at most one per animation frame (scroll/resize). */
export function rafThrottle(fn) {
    let scheduled = false;
    return (...args) => {
        if (scheduled) {
            return;
        }
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            fn(...args);
        });
    };
}

const PLACEMENT_ORDER = ['bottom', 'top', 'right', 'left'];
const OPPOSITE = { top: 'bottom', bottom: 'top', left: 'right', right: 'left' };
const GAP = 14; // px between target edge and card (caret spans it)
const MARGIN = 16; // px minimum distance from the viewport edge
const CARET_INSET = 20; // px the caret keeps clear of the card's corners

/**
 * Pure tooltip placement math.
 *
 * Tries the requested placement, then its opposite, then the remaining sides
 * ('auto' tries bottom/top/right/left); the first candidate whose primary axis
 * fully fits wins, else the side with the most room. The cross axis is clamped
 * to the viewport and the caret keeps pointing at the target's center.
 *
 * @param {DOMRect-like} targetRect  the (padded) spotlight rect
 * @param {{width,height}} cardSize  measured card size
 * @param {string} placement        'top'|'bottom'|'left'|'right'|'auto'
 * @param {{width,height}} viewport
 * @returns {{top, left, actualPlacement, caret: {side, offset}}}
 */
export function computeCardPosition(targetRect, cardSize, placement, viewport) {
    const cx = targetRect.x + targetRect.width / 2;
    const cy = targetRect.y + targetRect.height / 2;

    const candidates =
        placement && placement !== 'auto'
            ? [
                  placement,
                  OPPOSITE[placement],
                  ...PLACEMENT_ORDER.filter((p) => p !== placement && p !== OPPOSITE[placement])
              ]
            : [...PLACEMENT_ORDER];

    const positionFor = (side) => {
        switch (side) {
            case 'bottom':
                return { top: targetRect.y + targetRect.height + GAP, left: cx - cardSize.width / 2 };
            case 'top':
                return { top: targetRect.y - GAP - cardSize.height, left: cx - cardSize.width / 2 };
            case 'right':
                return { top: cy - cardSize.height / 2, left: targetRect.x + targetRect.width + GAP };
            case 'left':
            default:
                return { top: cy - cardSize.height / 2, left: targetRect.x - GAP - cardSize.width };
        }
    };

    const fits = (side, pos) => {
        switch (side) {
            case 'bottom':
                return pos.top + cardSize.height <= viewport.height - MARGIN;
            case 'top':
                return pos.top >= MARGIN;
            case 'right':
                return pos.left + cardSize.width <= viewport.width - MARGIN;
            case 'left':
            default:
                return pos.left >= MARGIN;
        }
    };

    const spaceFor = (side) => {
        switch (side) {
            case 'bottom':
                return viewport.height - (targetRect.y + targetRect.height);
            case 'top':
                return targetRect.y;
            case 'right':
                return viewport.width - (targetRect.x + targetRect.width);
            case 'left':
            default:
                return targetRect.x;
        }
    };

    let actualPlacement = null;
    for (const side of candidates) {
        if (fits(side, positionFor(side))) {
            actualPlacement = side;
            break;
        }
    }
    if (!actualPlacement) {
        actualPlacement = candidates.reduce((best, side) =>
            spaceFor(side) > spaceFor(best) ? side : best
        );
    }

    const pos = positionFor(actualPlacement);
    const clamp = (value, min, max) => Math.min(Math.max(value, min), Math.max(min, max));
    const left = clamp(pos.left, MARGIN, viewport.width - cardSize.width - MARGIN);
    const top = clamp(pos.top, MARGIN, viewport.height - cardSize.height - MARGIN);

    // The caret sits on the card edge facing the target and slides along it so
    // it keeps pointing at the target center even after clamping.
    const caretSide = OPPOSITE[actualPlacement];
    const horizontal = actualPlacement === 'top' || actualPlacement === 'bottom';
    const offset = horizontal
        ? clamp(cx - left, CARET_INSET, cardSize.width - CARET_INSET)
        : clamp(cy - top, CARET_INSET, cardSize.height - CARET_INSET);

    return { top, left, actualPlacement, caret: { side: caretSide, offset } };
}

/** Focusable, enabled controls inside a container, in DOM order. */
export function getFocusables(rootEl) {
    if (!rootEl) {
        return [];
    }
    return [...rootEl.querySelectorAll(FOCUSABLE_SELECTOR)].filter((el) => !el.disabled);
}

/** True when the OS asks for reduced motion — collapses all tour animation. */
export function prefersReducedMotion() {
    return typeof window.matchMedia === 'function'
        && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}