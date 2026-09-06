import { LightningElement, api } from 'lwc';
import { indexTree, findNode, flattenTree, expandedForActive, ancestorsOf } from 'c/treeUtil';

/**
 * dsTree — the shared N-level "All topics" sidebar for the Help Center and
 * Resource Center (the tree-shaped successor of dsTopicNav, which stays for
 * the arc* clones). One flat `<ul role="tree">` of rows rendered from
 * c/treeUtil: the path to the active node is expanded, siblings show at
 * every level, everything else stays collapsed; chevrons let a reader peek
 * into other branches without navigating. Past `rebaseDepth` the list is
 * rebased at the active node's grandparent behind a single "back" row so
 * deep levels never become a wall of indents — the breadcrumb carries the
 * rest of the chain.
 *
 * Controlled/presentational: the host owns the data and the selection.
 *
 * @api roots       CategoryTreeService.TreeDTO.roots (any depth). A host may
 *                  add `iconPath` (SVG path `d`, 24x24) on top-level nodes.
 * @api activeKey   id of the current node (HC: category API name; RC: slug
 *                  is NOT the key — pass the id the host routes by; both
 *                  apps pass whatever they put in `key` today).
 * @api showCounts  render descendantItemCount badges.
 * @api rebaseDepth depth (1-based) at which the view rebases; default 4.
 *
 * Emits `navselect { key }` from any row, including the "back" row.
 * Keyboard: roving tabindex; ArrowUp/Down move, ArrowRight expands or enters,
 * ArrowLeft collapses or climbs, Home/End, Enter/Space select (native button).
 */
export default class DsTree extends LightningElement {
    // Named `heading`, not `title` — @api title would double as the global
    // HTML title attribute and tooltip the whole nav.
    @api heading = 'All topics';
    @api rebaseDepth = 4;

    _roots = [];
    _activeKey;
    _tree = indexTree([]);
    _expanded = new Set();
    _peeked = new Map(); // key -> true (opened) | false (closed) by the reader
    _focusKey = null;
    _refocus = false;

    @api
    get roots() {
        return this._roots;
    }
    set roots(value) {
        this._roots = value || [];
        this._tree = indexTree(this._roots);
        this._peeked = new Map();
        this.resetExpansion();
    }

    @api
    get activeKey() {
        return this._activeKey;
    }
    set activeKey(value) {
        this._activeKey = value;
        this._peeked = new Map();
        this.resetExpansion();
    }

    _showCounts = false;
    @api
    get showCounts() {
        return this._showCounts;
    }
    set showCounts(value) {
        this._showCounts = value === '' ? true : Boolean(value);
    }

    resetExpansion() {
        this._expanded = expandedForActive(this._tree, this._activeKey);
    }

    // ---- View model ----------------------------------------------------------

    get activeNode() {
        return findNode(this._tree, this._activeKey);
    }

    /** The node the list is rebased at (null = whole tree). */
    get base() {
        const active = this.activeNode;
        const rebaseAt = Number(this.rebaseDepth) || 4;
        if (!active || active.depth < rebaseAt) {
            return null;
        }
        const chain = ancestorsOf(this._tree, active.id);
        return chain[chain.length - 2] || null;
    }

    get upRow() {
        const base = this.base;
        if (!base) {
            return null;
        }
        const parent = findNode(this._tree, base.parentId);
        return parent ? { key: parent.id, label: parent.label } : null;
    }

    get hasUpRow() {
        return Boolean(this.upRow);
    }

    get rows() {
        const expanded = new Set(this._expanded);
        this._peeked.forEach((open, key) => (open ? expanded.add(key) : expanded.delete(key)));
        const base = this.base;
        const rows = flattenTree(this._tree, expanded, base ? [base] : this._tree.roots);
        const focusKey = this._focusKey && rows.some((r) => r.id === this._focusKey)
            ? this._focusKey
            : (rows.some((r) => r.id === this._activeKey) ? this._activeKey : (rows[0] && rows[0].id));
        return rows.map((r) => {
            const depth = base ? r.depth - base.depth + 1 : r.depth;
            const active = r.id === this._activeKey;
            const top = depth === 1;
            return {
                key: r.id,
                label: r.label,
                depth,
                level: String(depth),
                setSize: String(r.setSize),
                posInSet: String(r.index + 1),
                hasChildren: r.hasChildren,
                ariaExpanded: r.hasChildren ? String(r.expanded) : undefined,
                expanded: r.expanded,
                active,
                ariaCurrent: active ? 'true' : undefined,
                tabIndex: r.id === focusKey ? '0' : '-1',
                iconPath: top ? r.iconPath : undefined,
                showIcon: top && Boolean(r.iconPath),
                count: this._showCounts && r.descendantItemCount > 0 ? String(r.descendantItemCount) : null,
                toggleLabel: `${r.expanded ? 'Collapse' : 'Expand'} ${r.label}`,
                rowClass: `ds-tree__row ${top ? 'ds-tree__row--top' : 'ds-tree__row--nested'}`
                    + (active ? ' ds-tree__row--active' : ''),
                toggleClass: `ds-tree__toggle${r.expanded ? ' ds-tree__toggle--open' : ''}`,
                style: top ? '' : `padding-left: ${64 + 16 * (depth - 2)}px`
            };
        });
    }

    // ---- Interaction ---------------------------------------------------------

    handleSelect(event) {
        this.emitSelect(event.currentTarget.dataset.key);
    }

    handleUp() {
        const up = this.upRow;
        if (up) {
            this.emitSelect(up.key);
        }
    }

    handleToggle(event) {
        event.stopPropagation();
        this.togglePeek(event.currentTarget.dataset.key);
    }

    togglePeek(key, force) {
        const node = findNode(this._tree, key);
        if (!node || !node.hasChildren) {
            return;
        }
        const open = this._expanded.has(key) ? this._peeked.get(key) !== false : this._peeked.get(key) === true;
        const next = force === undefined ? !open : force;
        this._peeked = new Map(this._peeked).set(key, next);
    }

    handleKeydown(event) {
        const keys = this.rows.map((r) => r.key);
        const key = event.currentTarget.dataset.key;
        const i = keys.indexOf(key);
        if (i < 0) {
            return;
        }
        let target = null;
        switch (event.key) {
            case 'ArrowDown':
                target = keys[Math.min(i + 1, keys.length - 1)];
                break;
            case 'ArrowUp':
                target = keys[Math.max(i - 1, 0)];
                break;
            case 'Home':
                target = keys[0];
                break;
            case 'End':
                target = keys[keys.length - 1];
                break;
            case 'ArrowRight': {
                const row = this.rows[i];
                if (row.hasChildren && !row.expanded) {
                    this.togglePeek(key, true);
                    target = key;
                } else if (row.hasChildren) {
                    target = keys[i + 1];
                }
                break;
            }
            case 'ArrowLeft': {
                const row = this.rows[i];
                if (row.hasChildren && row.expanded) {
                    this.togglePeek(key, false);
                    target = key;
                } else {
                    const node = findNode(this._tree, key);
                    target = node && node.parentId != null && keys.includes(node.parentId) ? node.parentId : null;
                }
                break;
            }
            default:
                return;
        }
        event.preventDefault();
        if (target) {
            this._focusKey = target;
            this._refocus = true;
        }
    }

    renderedCallback() {
        if (!this._refocus) {
            return;
        }
        this._refocus = false;
        const btn = this.template.querySelector(`.ds-tree__item[data-key="${this._focusKey}"]`);
        if (btn) {
            btn.focus();
        }
    }

    emitSelect(key) {
        this.dispatchEvent(new CustomEvent('navselect', { detail: { key } }));
    }

    /** Move keyboard focus to the current row (hosts call this when a drawer opens). */
    @api
    focusActive() {
        const btn = this.template.querySelector('.ds-tree__item[tabindex="0"]')
            || this.template.querySelector('.ds-tree__item');
        if (btn) {
            btn.focus();
        }
    }
}