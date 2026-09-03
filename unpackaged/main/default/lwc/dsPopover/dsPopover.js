import { LightningElement, api } from 'lwc';

/**
 * dsPopover — a small non-modal dialog anchored to an element: a detail card
 * that opens next to whatever was clicked (a calendar chip, a row) rather than
 * in the centre of the screen. At phone widths the same panel becomes a
 * bottom sheet — that swap is pure CSS (see the 640px block), so the host
 * never has to know which one it got.
 *
 * Pure presentation, Apex-free; the host owns what is inside and when it is
 * open (reactive `is-open`, the dsModalV2 shape — never an open() method).
 *
 * @api isOpen: render/dismiss
 * @api anchorRect: { top, left, width, height } in viewport coordinates — a
 *   plain object (dsCalendar's eventselect hands one over), never a DOMRect
 * @api label: accessible name of the dialog (default 'Details')
 * @api heading: optional visible heading. NOT `title`: that is a global HTML
 *   attribute, so an @api title never receives the binding (the dsDateBlock
 *   `datetime` lesson).
 * Default slot: the body. `close()` closes imperatively.
 * Emits `close` (plain — the host listens on the element) on Escape, the
 * close button, or a click outside the panel.
 *
 * Positioning: below the anchor, flipped above when there is no room below
 * but there is above, and clamped into the viewport with an 8px margin. The
 * coordinates ride on custom properties (--ds-pop-top / --ds-pop-left) rather
 * than inline top/left so the mobile media query can override them without
 * !important. The panel is measured after its first paint, so it renders
 * invisible for one frame and then snaps into place.
 *
 * Focus moves into the panel on open and back to the opener on close. There
 * is deliberately no focus trap: this is a non-modal dialog (APG), so Tab
 * leaves it and the host page stays reachable.
 */
const GAP = 8;
const MARGIN = 8;

function clamp(value, min, max) {
    return Math.min(Math.max(value, min), Math.max(min, max));
}

export default class DsPopover extends LightningElement {
    @api isOpen = false;
    @api anchorRect;
    @api label = 'Details';
    @api heading;

    _coords = null;
    _wasOpen = false;
    _previouslyFocused = null;
    _keydownHandler = null;
    _outsideClickHandler = null;
    _resizeHandler = null;
    _outsideTimer = null;

    connectedCallback() {
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' && this.isOpen) {
                this._fireClose();
            }
        };
        this._resizeHandler = () => {
            if (this.isOpen) {
                this._position();
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
        window.addEventListener('resize', this._resizeHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._keydownHandler);
        window.removeEventListener('resize', this._resizeHandler);
        this._keydownHandler = null;
        this._resizeHandler = null;
        this._unwatchOutside();
    }

    renderedCallback() {
        if (this.isOpen && !this._wasOpen) {
            this._wasOpen = true;
            this._onOpened();
        } else if (!this.isOpen && this._wasOpen) {
            this._wasOpen = false;
            this._onClosed();
        }
    }

    get panelStyle() {
        return this._coords
            ? `--ds-pop-top:${this._coords.top}px;--ds-pop-left:${this._coords.left}px`
            : '';
    }

    get panelClass() {
        return this._coords ? 'ds-pop__panel ds-pop__panel--placed' : 'ds-pop__panel';
    }

    get hasHeading() {
        return Boolean(this.heading);
    }

    @api
    close() {
        this._fireClose();
    }

    handleClose() {
        this._fireClose();
    }

    stopProp(event) {
        event.stopPropagation();
    }

    // ---- open / close transitions --------------------------------------------

    _onOpened() {
        this._previouslyFocused =
            document.activeElement && document.activeElement !== document.body
                ? document.activeElement
                : null;
        this._position();
        const panel = this.template.querySelector('.ds-pop__panel');
        if (panel) {
            panel.focus();
        }
        // Registered on the next tick so the click that opened us does not
        // immediately close us; capture phase + composedPath see through the
        // shadow boundary and into slotted content (arcLanding's help menu).
        this._outsideClickHandler = (event) => {
            const current = this.template.querySelector('.ds-pop__panel');
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            if (!current || !path.includes(current)) {
                this._fireClose();
            }
        };
        this._outsideTimer = setTimeout(() => {
            this._outsideTimer = null;
            if (this._outsideClickHandler) {
                window.addEventListener('click', this._outsideClickHandler, true);
            }
        }, 0);
    }

    _onClosed() {
        this._unwatchOutside();
        this._coords = null;
        const target = this._previouslyFocused;
        this._previouslyFocused = null;
        if (target && target.isConnected && typeof target.focus === 'function') {
            target.focus();
        }
    }

    _unwatchOutside() {
        if (this._outsideTimer) {
            clearTimeout(this._outsideTimer);
            this._outsideTimer = null;
        }
        if (this._outsideClickHandler) {
            window.removeEventListener('click', this._outsideClickHandler, true);
            this._outsideClickHandler = null;
        }
    }

    // ---- placement -----------------------------------------------------------

    _position() {
        const panel = this.template.querySelector('.ds-pop__panel');
        if (!panel) {
            return;
        }
        const size = panel.getBoundingClientRect();
        const a = this.anchorRect || { top: 0, left: 0, width: 0, height: 0 };
        const viewportW = window.innerWidth || 0;
        const viewportH = window.innerHeight || 0;

        const below = a.top + a.height + GAP;
        const above = a.top - GAP - size.height;
        const fitsBelow = below + size.height <= viewportH - MARGIN;
        const fitsAbove = above >= MARGIN;
        const top = fitsBelow || !fitsAbove ? below : above;

        this._coords = {
            top: Math.round(clamp(top, MARGIN, viewportH - size.height - MARGIN)),
            left: Math.round(clamp(a.left, MARGIN, viewportW - size.width - MARGIN))
        };
    }

    _fireClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}