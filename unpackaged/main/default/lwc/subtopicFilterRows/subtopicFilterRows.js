import { LightningElement, api } from 'lwc';

const DEFAULT_MAX_VISIBLE = 8;

function pillClass(selected, disabled) {
    let cls = 'sfr__pill';
    if (selected) {
        cls += ' sfr__pill--selected';
    }
    if (disabled) {
        cls += ' sfr__pill--disabled';
    }
    return cls;
}

/**
 * subtopicFilterRows — the cascading subtopic pill rows under a topic page's
 * title, shared by the Help Center and Resource Center (successor of the
 * c-ds-section-cards grid, which drilled down instead of narrowing in place).
 *
 * The rows are the topic's children (`All (n)` first), then — once a child is
 * selected — that child's children beneath, and so on to the tree's depth;
 * rows off the selected path are never rendered. The host derives `rows`
 * from the ROUTE with c/treeUtil.filterRows, so the pills, the sidebar and
 * the breadcrumb are three views of one state: selecting a pill only asks
 * the host to route (`navselect { key }`, the event c-ds-tree fires), never
 * stores a selection of its own.
 *
 * @api rows        treeUtil.filterRows output: [{ key, label, depth, allCount,
 *                  selectedKey, pills: [{ key, label, count, selected, disabled }] }]
 * @api maxVisible  pills shown per row before the rest fold behind a
 *                  "More ▾" menu (default 8; the selected pill always stays
 *                  on the row).
 *
 * Emits `navselect { key }` — a pill's node, or the row's own node for its
 * `All` pill (which is what clears every row below it).
 */
export default class SubtopicFilterRows extends LightningElement {
    @api maxVisible = DEFAULT_MAX_VISIBLE;

    _rows = [];
    /** Row key whose overflow menu is open; one at a time. */
    openMenuKey = null;
    _outsideClick = null;

    @api
    get rows() {
        return this._rows;
    }
    set rows(value) {
        this._rows = value || [];
        this.closeMenu();
    }

    get hasRows() {
        return this._rows.length > 0;
    }

    get rowViews() {
        const max = Math.max(2, Number(this.maxVisible) || DEFAULT_MAX_VISIBLE);
        return this._rows.map((row) => {
            const pills = row.pills || [];
            let visible = pills;
            let hidden = [];
            if (pills.length > max) {
                visible = pills.slice(0, max - 1);
                hidden = pills.slice(max - 1);
                const idx = hidden.findIndex((p) => p.selected);
                if (idx >= 0) {
                    // The selected pill never hides behind More: swap it in.
                    const selected = hidden.splice(idx, 1)[0];
                    hidden.unshift(visible.pop());
                    visible.push(selected);
                }
            }
            const decorate = (p) => ({
                key: p.key,
                text: `${p.label} (${p.count})`,
                pressed: p.selected ? 'true' : 'false',
                disabled: Boolean(p.disabled),
                cssClass: pillClass(p.selected, p.disabled),
                menuClass: 'sfr__menu-item' + (p.disabled ? ' sfr__menu-item--disabled' : '')
            });
            const allSelected = !row.selectedKey;
            const menuOpen = this.openMenuKey === row.key;
            return {
                key: row.key,
                groupLabel: `Subtopics of ${row.label}`,
                cssClass: row.depth > 1 ? 'sfr__row sfr__row--nested' : 'sfr__row',
                allText: `All (${row.allCount || 0})`,
                allPressed: allSelected ? 'true' : 'false',
                allClass: pillClass(allSelected, false),
                pills: visible.map(decorate),
                hidden: hidden.map(decorate),
                hasMore: hidden.length > 0,
                moreLabel: `More (${hidden.length})`,
                moreExpanded: menuOpen ? 'true' : 'false',
                menuOpen
            };
        });
    }

    // ---- Selection ---------------------------------------------------------------

    handleSelect(event) {
        const key = event.currentTarget.dataset.key;
        this.closeMenu();
        this.dispatchEvent(new CustomEvent('navselect', { detail: { key } }));
    }

    // ---- Overflow menu -------------------------------------------------------------

    handleMoreToggle(event) {
        const key = event.currentTarget.dataset.row;
        if (this.openMenuKey === key) {
            this.closeMenu();
            return;
        }
        this.openMenuKey = key;
        // Close on any click outside the menu; registered on the next tick so
        // the opening click doesn't immediately re-close it. composedPath sees
        // through the shadow boundary.
        this._outsideClick = (e) => {
            const path = typeof e.composedPath === 'function' ? e.composedPath() : [];
            const inside = path.some((n) => n && n.classList && n.classList.contains('sfr__more'));
            if (!inside) {
                this.closeMenu();
            }
        };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            if (this._outsideClick) {
                document.addEventListener('click', this._outsideClick, true);
            }
        }, 0);
    }

    handleMenuKeydown(event) {
        if (event.key === 'Escape' && this.openMenuKey) {
            event.stopPropagation();
            const rowKey = this.openMenuKey;
            this.closeMenu();
            const button = this.template.querySelector(`.sfr__pill--more[data-row="${rowKey}"]`);
            if (button) {
                button.focus();
            }
        }
    }

    closeMenu() {
        this.openMenuKey = null;
        if (this._outsideClick) {
            document.removeEventListener('click', this._outsideClick, true);
            this._outsideClick = null;
        }
    }

    disconnectedCallback() {
        this.closeMenu();
    }
}