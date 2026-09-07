import { LightningElement, api } from 'lwc';
import { truncateMiddle } from 'c/treeUtil';

/**
 * dsBreadcrumbs — shared breadcrumb trail for the Help Center and Resource
 * Center (extracted from nexsArticleBrowser's inline .nexs__crumbs markup so
 * both centers consume one component).
 *
 * @api items: [{ label, key? }] — items WITH a key render as links and emit
 * `crumbselect { key }` on click; keyless items render as the non-clickable
 * current segment. The last item may still be keyed (the Help Center shows
 * "Help Center › {topic}" with a clickable topic while an article title is
 * loading). Any length: category trees hand over the whole ancestor chain.
 *
 * @api collapseAt: on phone widths (≤ 640px) a trail longer than this
 * collapses to "first › … › parent › current"; the ellipsis is a button that
 * opens a small menu of the hidden ancestors, each a link emitting
 * `crumbselect` (c/treeUtil.truncateMiddle picks what hides). Escape or a
 * click elsewhere closes it. 0 (default) never collapses.
 *
 * Styling: no :host token redeclaration — the --slds-g-* and --ds-* custom
 * properties inherit from the host page's :host block, with the same literal
 * fallbacks baked into each var(). Consumers may style the host element
 * (c-ds-breadcrumbs { align-items: … }) — :host is display:flex for that.
 */
export default class DsBreadcrumbs extends LightningElement {
    @api collapseAt = 0;

    _items = [];
    narrow = false;
    menuOpen = false;
    _mql;
    _onMedia;
    _onDocClick;
    _focusMenu = false;

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = value || [];
        this.closeMenu();
    }

    connectedCallback() {
        if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
            return; // Jest / older sandboxes: never collapse
        }
        this._mql = window.matchMedia('(max-width: 640px)');
        this.narrow = Boolean(this._mql.matches);
        this._onMedia = (event) => {
            this.narrow = Boolean(event.matches);
            this.closeMenu();
        };
        if (typeof this._mql.addEventListener === 'function') {
            this._mql.addEventListener('change', this._onMedia);
        } else if (typeof this._mql.addListener === 'function') {
            this._mql.addListener(this._onMedia);
        }
    }

    disconnectedCallback() {
        this.closeMenu();
        if (!this._mql || !this._onMedia) {
            return;
        }
        if (typeof this._mql.removeEventListener === 'function') {
            this._mql.removeEventListener('change', this._onMedia);
        } else if (typeof this._mql.removeListener === 'function') {
            this._mql.removeListener(this._onMedia);
        }
        this._mql = null;
        this._onMedia = null;
    }

    get itemView() {
        const max = Number(this.collapseAt) || 0;
        const shown = this.narrow && max ? truncateMiddle(this._items, max) : this._items;
        return shown.map((c, i) => {
            if (c.ellipsis) {
                const n = c.hidden.length;
                return {
                    renderKey: 'ellipsis',
                    ellipsis: true,
                    showSep: i > 0,
                    clickable: false,
                    moreLabel: `Show ${n} more ${n === 1 ? 'level' : 'levels'}`,
                    menuExpanded: this.menuOpen ? 'true' : 'false',
                    menuOpen: this.menuOpen,
                    hidden: c.hidden.map((h, j) => ({
                        ...h,
                        renderKey: h.key || `hidden-${j}`,
                        clickable: Boolean(h.key)
                    }))
                };
            }
            return {
                ...c,
                renderKey: c.key || `crumb-${i}`,
                showSep: i > 0,
                clickable: Boolean(c.key)
            };
        });
    }

    handleClick(event) {
        event.preventDefault();
        this.closeMenu();
        this.dispatchEvent(new CustomEvent('crumbselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }

    // ---- Hidden-ancestor menu ------------------------------------------------

    handleMoreToggle(event) {
        event.stopPropagation();
        if (this.menuOpen) {
            this.closeMenu();
        } else {
            this.openMenu();
        }
    }

    openMenu() {
        this.menuOpen = true;
        this._focusMenu = true;
        if (typeof document !== 'undefined' && !this._onDocClick) {
            this._onDocClick = () => this.closeMenu();
            document.addEventListener('click', this._onDocClick);
        }
    }

    closeMenu() {
        this.menuOpen = false;
        if (this._onDocClick && typeof document !== 'undefined') {
            document.removeEventListener('click', this._onDocClick);
            this._onDocClick = null;
        }
    }

    /** Escape closes and returns focus to the ellipsis; arrows walk the items. */
    handleMenuKeydown(event) {
        const links = [...this.template.querySelectorAll('.crumbs__menu-link')];
        const i = links.indexOf(this.template.activeElement);
        if (event.key === 'Escape') {
            event.preventDefault();
            this.closeMenu();
            const more = this.template.querySelector('.crumbs__more');
            if (more) {
                more.focus();
            }
        } else if (event.key === 'ArrowDown' && links.length) {
            event.preventDefault();
            links[(i + 1) % links.length].focus();
        } else if (event.key === 'ArrowUp' && links.length) {
            event.preventDefault();
            links[(i - 1 + links.length) % links.length].focus();
        }
    }

    renderedCallback() {
        if (!this._focusMenu) {
            return;
        }
        this._focusMenu = false;
        const first = this.template.querySelector('.crumbs__menu-link');
        if (first) {
            first.focus();
        }
    }
}