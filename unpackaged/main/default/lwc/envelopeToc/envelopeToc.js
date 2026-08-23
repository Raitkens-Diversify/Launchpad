import { LightningElement, api } from 'lwc';

// Progressive save-status → indicator display. Keyed by the shell's saveStatus enum; any other value
// (including 'idle' / unset) hides the indicator, so the TOC is unchanged when no status is passed.
const SAVE_INDICATORS = {
    pending: { iconName: 'utility:info', label: 'Save Pending', statusClass: 'toc__status toc__status_pending' },
    saving: { iconName: 'utility:sync', label: 'Saving...', statusClass: 'toc__status toc__status_saving' },
    saved: { iconName: 'utility:success', label: 'Saved', statusClass: 'toc__status toc__status_saved' }
};

/**
 * envelopeToc — a reusable Table-of-Contents tree for the envelope wizard's paged forms.
 *
 * Renders a nested list of navigable sections: parent nodes (collapsible via a chevron) each
 * containing indented children — nested to any depth — plus flat leaf-only lists. The active leaf is
 * highlighted with a left marker and a semibold label, and each row can show a progress dot for its
 * completion status.
 * Selection is controlled by the parent: clicking a leaf emits `select { key }`, and the parent feeds
 * the chosen key back through `active-key`. Expand/collapse is local state, so re-passing `items`
 * (e.g. as a form draft changes) does not reset which groups are open.
 */
export default class EnvelopeToc extends LightningElement {
    // Heading shown above the tree.
    @api title = 'Table of Contents';

    // Nested nodes: [{ key, label, status?, children?: [node] }], nested to any depth (child nodes
    // may carry children of their own). A node with children renders as a collapsible parent at its
    // depth; a node without renders as a leaf. Keys must be unique across the whole tree. `status`
    // is 'incomplete' | 'complete' | 'none' and drives the progress indicator: 'incomplete' shows
    // an amber dot, 'complete' shows a green check, 'none' shows nothing.
    @api items = [];

    // The active leaf's key (drives the active marker + bold label). Owned by the parent.
    @api activeKey;

    // Optional progressive save-status shown as an indicator on the title row: 'pending' | 'saving' |
    // 'saved' render the chip; anything else (incl. 'idle' / unset) hides it. Owned by the parent.
    @api saveStatus;

    // Keys of parent nodes the user has collapsed; absent means expanded (the default).
    _collapsed = {};

    get saveIndicator() {
        return SAVE_INDICATORS[this.saveStatus] || null;
    }

    // Flatten the tree into render rows, honouring the local collapsed state and the active key.
    // Precomputed here because the template can't branch on tree depth.
    get rows() {
        const rows = [];
        this._flatten(this.items || [], 0, rows);
        this._assertUniqueKeys(rows);
        return rows;
    }

    /**
     * Keys must be unique across the whole flattened tree, because the tree renders from a single
     * for:each: a duplicate key does not throw, it quietly breaks LWC's keyed reconciliation of the
     * entire rail. Both collisions this component has suffered — a group keyed the same as its only
     * child, and a trailing group keyed off a running length that matched a parent's index — presented
     * as a wedged page with a clean console, so the check earns its keep many times over. One Set over
     * a few dozen rows; always on, since this codebase's LWC has no dev/prod build split.
     */
    _assertUniqueKeys(rows) {
        const seen = new Set();
        const duplicates = new Set();
        rows.forEach((row) => {
            if (seen.has(row.key)) {
                duplicates.add(row.key);
                return;
            }
            seen.add(row.key);
        });
        if (duplicates.size) {
            console.error(
                `envelopeToc: duplicate key(s) in the tree, reconciliation will misbehave: ${[
                    ...duplicates
                ].join(', ')}`
            );
        }
    }

    // Toggle a group's collapsed state, or select a leaf (bubbled to the parent). A click on the
    // already-active leaf is ignored so the parent isn't re-notified needlessly.
    handleRowClick(event) {
        const { key, role } = event.currentTarget.dataset;
        if (role === 'toggle') {
            this._collapsed = { ...this._collapsed, [key]: !this._collapsed[key] };
            return;
        }
        if (key === this.activeKey) {
            return;
        }
        this.dispatchEvent(new CustomEvent('select', { detail: { key } }));
    }

    // Walk the nodes depth-first into `rows`, descending into expanded parents. Each row carries a
    // depth class so nested levels indent progressively.
    _flatten(nodes, depth, rows) {
        nodes.forEach((node) => {
            const children = node.children || [];
            if (children.length > 0) {
                const isCollapsed = this._collapsed[node.key] === true;
                rows.push(this._parentRow(node, isCollapsed, depth));
                if (!isCollapsed) {
                    this._flatten(children, depth + 1, rows);
                }
            } else {
                rows.push(this._leafRow(node, this.activeKey, depth));
            }
        });
    }

    _parentRow(node, isCollapsed, depth) {
        return {
            key: node.key,
            label: node.label,
            role: 'toggle',
            isParent: true,
            chevronIcon: isCollapsed ? 'utility:chevronright' : 'utility:chevrondown',
            ariaExpanded: String(!isCollapsed),
            ariaCurrent: null,
            showDot: (node.status || 'none') === 'incomplete',
            showCheck: (node.status || 'none') === 'complete',
            rowClass: `toc__row toc__row_parent toc__row_depth-${depth}`
        };
    }

    _leafRow(node, activeKey, depth) {
        const isActive = node.key === activeKey;
        let rowClass = `toc__row toc__row_leaf toc__row_depth-${depth}`;
        if (isActive) {
            rowClass += ' toc__row_active';
        }
        return {
            key: node.key,
            label: node.label,
            role: 'select',
            isParent: false,
            chevronIcon: null,
            ariaExpanded: null,
            ariaCurrent: isActive ? 'page' : null,
            showDot: (node.status || 'none') === 'incomplete',
            showCheck: (node.status || 'none') === 'complete',
            rowClass
        };
    }
}