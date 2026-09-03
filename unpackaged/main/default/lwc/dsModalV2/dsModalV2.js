import { LightningElement, api } from 'lwc';

const SIZE_CLASS = {
    small: 'ds-modal-v2__container ds-modal-v2__container--small',
    medium: 'ds-modal-v2__container ds-modal-v2__container--medium',
    large: 'ds-modal-v2__container ds-modal-v2__container--large'
};

// Elements that can hold keyboard focus inside the dialog. Includes the Lightning host tags used
// in these modals — calling focus() on the host delegates to its internal control.
const FOCUSABLE_SELECTOR = [
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

export default class DsModalV2 extends LightningElement {
    @api isOpen = false;
    @api title = '';
    @api subtitle = '';
    @api size = 'small';
    @api hideFooter = false;
    @api allowOverflow = false;
    @api disableBackdropClose = false;

    _keydownHandler = null;
    _wasOpen = false;
    _previouslyFocused = null;

    connectedCallback() {
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' && this.isOpen && !this.disableBackdropClose) {
                this._fireClose();
            }
        };
        window.addEventListener('keydown', this._keydownHandler);
    }

    disconnectedCallback() {
        if (this._keydownHandler) {
            window.removeEventListener('keydown', this._keydownHandler);
            this._keydownHandler = null;
        }
    }

    // The shell is driven by the reactive isOpen prop (not an open() method), so move focus on the
    // open/close transition. The _wasOpen guard keeps it from re-running on incidental re-renders
    // (e.g. a footer button toggling disabled during a busy state).
    renderedCallback() {
        if (this.isOpen && !this._wasOpen) {
            this._wasOpen = true;
            this._onOpened();
        } else if (!this.isOpen && this._wasOpen) {
            this._wasOpen = false;
            this._onClosed();
        }
    }

    get containerClass() {
        const base = SIZE_CLASS[this.size] || SIZE_CLASS.small;
        return this.allowOverflow ? `${base} ds-modal-v2__container--allow-overflow` : base;
    }

    get bodyClass() {
        return this.allowOverflow
            ? 'ds-modal-v2__body ds-modal-v2__body--allow-overflow'
            : 'ds-modal-v2__body';
    }

    get hasSubtitle() {
        return Boolean(this.subtitle);
    }

    @api
    close() {
        this._fireClose();
    }

    handleClose() {
        this._fireClose();
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget && !this.disableBackdropClose) {
            this._fireClose();
        }
    }

    stopProp(event) {
        event.stopPropagation();
    }

    // Focus reached the leading sentinel via Shift+Tab off the first control — wrap to the last.
    handleSentinelStart() {
        const focusables = this._getOrderedFocusables();
        const last = focusables[focusables.length - 1];
        if (last) {
            last.focus();
        }
    }

    // Focus reached the trailing sentinel via Tab off the last control — wrap to the first.
    handleSentinelEnd() {
        const [first] = this._getOrderedFocusables();
        if (first) {
            first.focus();
        }
    }

    _onOpened() {
        this._previouslyFocused =
            document.activeElement && document.activeElement !== document.body
                ? document.activeElement
                : null;
        const container = this.template.querySelector('.ds-modal-v2__container');
        if (container) {
            container.focus();
        }
    }

    _onClosed() {
        const target = this._previouslyFocused;
        this._previouslyFocused = null;
        if (target && target.isConnected && typeof target.focus === 'function') {
            target.focus();
        }
    }

    // Focusable controls in tab order: header slot, close button, body slot, footer slot. The
    // close button is always appended as a fallback (it is never disabled), so the trap holds even
    // when the action buttons are disabled during a busy state.
    _getOrderedFocusables() {
        const result = [];
        const headerSlot = this.template.querySelector('slot[name="header"]');
        if (headerSlot) {
            result.push(...this._focusablesInSlot(headerSlot));
        }
        const closeButton = this.template.querySelector('.ds-modal-v2__close');
        if (closeButton) {
            result.push(closeButton);
        }
        const bodySlot = this.template.querySelector('slot:not([name])');
        if (bodySlot) {
            result.push(...this._focusablesInSlot(bodySlot));
        }
        const footerSlot = this.template.querySelector('slot[name="footer"]');
        if (footerSlot) {
            result.push(...this._focusablesInSlot(footerSlot));
        }
        return result;
    }

    // Focusable elements projected into a slot. assignedElements reaches the slotted nodes (which
    // live in the consumer's template); querySelectorAll then finds focusables nested inside any
    // wrapper. Disabled controls are skipped so focus never lands on one.
    _focusablesInSlot(slot) {
        const found = [];
        const assigned = slot.assignedElements ? slot.assignedElements({ flatten: true }) : [];
        assigned.forEach((node) => {
            if (node.matches && node.matches(FOCUSABLE_SELECTOR)) {
                found.push(node);
            }
            if (node.querySelectorAll) {
                found.push(...node.querySelectorAll(FOCUSABLE_SELECTOR));
            }
        });
        return found.filter((el) => !el.disabled);
    }

    _fireClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }
}