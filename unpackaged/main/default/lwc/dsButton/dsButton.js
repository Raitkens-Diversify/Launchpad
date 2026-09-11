import { LightningElement, api } from 'lwc';

/**
 * dsButton — the ONE button recipe for the Help Center / Resource Center /
 * Events surfaces (docs/ui-standards.md §3, docs/help-center-visual-audit.md).
 *
 * Renders a native <button type="button"> — or an <a> when `href` is given
 * (external links, downloads, mailto:) — in the family's three looks:
 *   brand  navy fill / white text (the primary action)
 *   quiet  white fill / navy text / hairline border (Close, secondary)
 *   link   text-only medium blue, underline on hover ("View details")
 * Sizes sm / md / lg step the padding and type; `full-width` stretches it.
 *
 * WHY a component and not a class: on the LWR sites the platform's
 * dxp-slds-extensions sheet styles every anchor with
 *   a:link:not(.slds-button, .slds-dropdown__item > a) { color; background-color; text-decoration }
 * at specificity (0,2,2) — and under synthetic shadow DOM that global rule
 * cascades into our markup and beats any plain class rule (0,1,0 + the LWC
 * scope token). Every anchor rule in dsButton.css is therefore written as
 * `a.ds-btn…:link/:visited/:hover/:focus/:active` (element + class + pseudo
 * + scope = 0,3,1), which wins on both surfaces. Keep that shape when you
 * touch the stylesheet. Buttons are not affected; the site only styles `a`.
 *
 * Sizing is in px on purpose: rem renders 12.5% smaller on ARC (14px root)
 * than in Lightning (16px root); px is identical everywhere.
 *
 * Clicks are the native ones (they compose through the shadow boundary), so
 * `onclick` and `data-*` on <c-ds-button> work exactly as on a raw button.
 */
const VARIANTS = ['brand', 'quiet', 'link'];
const SIZES = ['sm', 'md', 'lg'];
const HOST_FULL = 'ds-btn-host--full';

export default class DsButton extends LightningElement {
    /** Text of the control; the default slot is the alternative. */
    @api label;
    /** brand (default) | quiet | link */
    @api variant = 'brand';
    /** sm | md (default) | lg */
    @api size = 'md';
    /** Renders an <a> instead of a <button>. */
    @api href;
    /** Anchor target; `_blank` adds rel="noopener noreferrer". */
    @api target;
    /** Anchor only: save the target instead of navigating. Rendered ONLY when
     *  true — a `download="false"` attribute still triggers a save. */
    @api download = false;
    @api disabled = false;
    /** Stretch to the container's width (stacked cards, detail rails). */
    @api fullWidth = false;

    connectedCallback() {
        this.syncHostClass();
    }

    renderedCallback() {
        this.syncHostClass();
    }

    syncHostClass() {
        this.classList.toggle(HOST_FULL, Boolean(this.fullWidth));
    }

    get isLink() {
        return Boolean(this.href);
    }

    get safeVariant() {
        return VARIANTS.includes(this.variant) ? this.variant : 'brand';
    }

    get safeSize() {
        return SIZES.includes(this.size) ? this.size : 'md';
    }

    get cssClass() {
        const classes = ['ds-btn', `ds-btn--${this.safeVariant}`, `ds-btn--${this.safeSize}`];
        if (this.fullWidth) {
            classes.push('ds-btn--full');
        }
        if (this.disabled) {
            classes.push('ds-btn--disabled');
        }
        return classes.join(' ');
    }

    get relAttr() {
        return this.target === '_blank' ? 'noopener noreferrer' : undefined;
    }

    get ariaDisabledAttr() {
        return this.disabled ? 'true' : undefined;
    }

    get tabIndexAttr() {
        return this.disabled ? '-1' : undefined;
    }

    /** A disabled anchor must neither navigate nor let the host's handler run. */
    handleClick(event) {
        if (this.disabled) {
            event.preventDefault();
            event.stopPropagation();
        }
    }
}