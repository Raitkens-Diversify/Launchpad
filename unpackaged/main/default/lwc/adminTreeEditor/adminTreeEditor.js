import { LightningElement, api } from 'lwc';
import {
    indexTree, findNode, flattenTree, siblingsOf,
    dropTarget, canDrop, moveResult, MSG
} from 'c/treeUtil';

/**
 * adminTreeEditor — the shared N-level tree editor for the Admin Console's
 * Resource categories and Help topics panes (the tree-shaped successor of
 * adminSortableTree, which stays for flat-list hosts). One flat list of rows
 * from c/treeUtil: expand/collapse (top level open by default, "Expand all /
 * Collapse all"), add a child at any node within the depth limit, inline
 * rename (F2 / double-click), edit and delete actions, and grip-based
 * drag-and-drop that can reorder among siblings OR move a node — with its
 * whole subtree — under any valid parent. Drop zones come from the pointer:
 * the top quarter of a row drops before it, the bottom quarter after it,
 * the middle into it. Invalid targets (the node itself, its own subtree, or
 * a parent that would push the subtree past `maxDepth`) get no preventDefault,
 * so the browser shows the no-drop cursor and drop never fires; the reason
 * is announced. Keyboard: ArrowUp/Down reorder, Alt+ArrowLeft outdents,
 * Alt+ArrowRight indents into the previous sibling, all through the same
 * rules (c/treeUtil.canDrop = CategoryTreeService.validateMove).
 *
 * Controlled: the host owns the data and persistence. Events:
 *   move     { key, newParentKey|null, orderedSiblingKeys, movedLabel, position, total }
 *   rename   { key, label }
 *   edit     { key, label }        addchild { parentKey }        remove { key, label }
 *
 * ~1000 nodes: only expanded branches exist in the DOM (collapsed by default
 * below the top level), so the row count stays in the tens.
 */
export default class AdminTreeEditor extends LightningElement {
    @api busy = false;
    @api editLabel = 'Edit';
    @api addChildLabel = 'Add subtopic';
    @api removeLabel = 'Delete';

    _roots = [];
    _tree = indexTree([]);
    _expanded = null;      // Set of keys; null = default (top level open)
    _maxDepth = 5;

    @api
    get roots() {
        return this._roots;
    }
    set roots(value) {
        this._roots = value || [];
        this._tree = indexTree(this._roots);
        if (this._expanded) {
            // Keep the reader's expansion, dropping keys that no longer exist.
            this._expanded = new Set([...this._expanded].filter((k) => this._tree.byId.has(k)));
        }
    }

    @api
    get maxDepth() {
        return this._maxDepth;
    }
    set maxDepth(value) {
        const n = Number(value);
        this._maxDepth = n > 0 ? n : 5;
    }

    // Static boolean attributes arrive as '' — normalize presence to true.
    _editable = false;
    @api
    get editable() {
        return this._editable;
    }
    set editable(value) {
        this._editable = value === '' ? true : Boolean(value);
    }

    _allowAddChild = false;
    @api
    get allowAddChild() {
        return this._allowAddChild;
    }
    set allowAddChild(value) {
        this._allowAddChild = value === '' ? true : Boolean(value);
    }

    _allowRename = false;
    @api
    get allowRename() {
        return this._allowRename;
    }
    set allowRename(value) {
        this._allowRename = value === '' ? true : Boolean(value);
    }

    _allowRemove = false;
    @api
    get allowRemove() {
        return this._allowRemove;
    }
    set allowRemove(value) {
        this._allowRemove = value === '' ? true : Boolean(value);
    }

    // Drag state lives in JS — dataTransfer payloads are unreliable under LWS.
    drag = null;            // { key }
    dropHint = null;        // { key, position } for the insertion line / into outline
    invalidKey = null;      // row under a pointer that may not take the drop
    announcement = '';      // aria-live text
    renamingKey = null;
    renameValue = '';
    _dragArmed = false;
    _refocusKey = null;
    _focusRename = false;

    // ---- View model ----------------------------------------------------------

    get expandedKeys() {
        if (this._expanded) {
            return this._expanded;
        }
        return new Set(this._tree.roots.map((r) => r.id));
    }

    get rows() {
        const canAct = this._editable && !this.busy;
        return flattenTree(this._tree, this.expandedKeys).map((r) => {
            const total = r.descendantItemCount || 0;
            const own = (r.itemCount || 0) + (r.secondaryItemCount || 0);
            const isDragging = this.drag && this.drag.key === r.id;
            const hint = this.dropHint && this.dropHint.key === r.id ? this.dropHint.position : null;
            let rowClass = 'ate__row';
            if (isDragging) {
                rowClass += ' ate__row--dragging';
            }
            if (hint) {
                rowClass += ` ate__row--drop-${hint}`;
            }
            if (this.invalidKey === r.id) {
                rowClass += ' ate__row--invalid';
            }
            if (r.active === false) {
                rowClass += ' ate__row--inactive';
            }
            return {
                key: r.id,
                label: r.label,
                depth: r.depth,
                level: String(r.depth),
                setSize: String(r.setSize),
                posInSet: String(r.index + 1),
                index: r.index,
                parentKey: r.parentId == null ? '' : r.parentId,
                hasChildren: r.hasChildren,
                expanded: r.expanded,
                ariaExpanded: r.hasChildren ? String(r.expanded) : undefined,
                toggleLabel: `${r.expanded ? 'Collapse' : 'Expand'} ${r.label}`,
                toggleClass: `ate__toggle${r.expanded ? ' ate__toggle--open' : ''}`,
                sublabel: r.slug && r.slug !== r.id ? r.slug : null,
                ownBadge: r.secondaryItemCount ? `${r.itemCount || 0} +${r.secondaryItemCount}` : String(r.itemCount || 0),
                ownTitle: r.secondaryItemCount
                    ? `${r.itemCount || 0} live here, ${r.secondaryItemCount} also shown here`
                    : `${r.itemCount || 0} live here`,
                totalBadge: total > own ? `${total} total` : null,
                totalTitle: `${total} shown here or below`,
                inactive: r.active === false,
                dragEnabled: canAct,
                gripLabel: `Reorder ${r.label}, level ${r.depth}, position ${r.index + 1} of ${r.setSize}. `
                    + 'Arrow keys move among siblings; Alt+Left outdents; Alt+Right indents; F2 renames.',
                showAddChild: canAct && this._allowAddChild && r.depth < this._maxDepth,
                showRemove: canAct && this._allowRemove,
                renaming: this.renamingKey === r.id,
                rowClass,
                style: `padding-left: ${12 + 24 * (r.depth - 1)}px`
            };
        });
    }

    get hasRows() {
        return this._tree.roots.length > 0;
    }

    get showToolbar() {
        return this._tree.ordered.some((n) => n.hasChildren);
    }

    get maxDepthNote() {
        return `Up to ${this._maxDepth} levels deep.`;
    }

    // ---- Expansion -----------------------------------------------------------

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.expandedKeys);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this._expanded = next;
    }

    handleExpandAll() {
        this._expanded = new Set(this._tree.ordered.filter((n) => n.hasChildren).map((n) => n.id));
    }

    handleCollapseAll() {
        this._expanded = new Set();
    }

    // ---- Row actions -------------------------------------------------------------

    handleEditClick(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('edit', { detail: { key: ds.key, label: ds.label } }));
    }

    handleAddChildClick(event) {
        this.dispatchEvent(new CustomEvent('addchild', {
            detail: { parentKey: event.currentTarget.dataset.key }
        }));
    }

    handleRemoveClick(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('remove', { detail: { key: ds.key, label: ds.label } }));
    }

    // ---- Inline rename -----------------------------------------------------------

    startRename(key) {
        const node = findNode(this._tree, key);
        if (!node || !this._allowRename || !this._editable || this.busy) {
            return;
        }
        this.renamingKey = key;
        this.renameValue = node.label;
        this._focusRename = true;
    }

    handleLabelDoubleClick(event) {
        this.startRename(event.currentTarget.dataset.key);
    }

    handleRenameInput(event) {
        this.renameValue = event.target.value;
    }

    handleRenameKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.commitRename();
        } else if (event.key === 'Escape') {
            event.preventDefault();
            this.cancelRename();
        }
    }

    handleRenameBlur() {
        this.commitRename();
    }

    commitRename() {
        const key = this.renamingKey;
        if (!key) {
            return;
        }
        const label = (this.renameValue || '').trim();
        const node = findNode(this._tree, key);
        this.renamingKey = null;
        this._refocusKey = key;
        if (!node || !label || label === node.label) {
            return;
        }
        this.dispatchEvent(new CustomEvent('rename', { detail: { key, label } }));
    }

    cancelRename() {
        this._refocusKey = this.renamingKey;
        this.renamingKey = null;
    }

    // ---- Drag and drop ---------------------------------------------------------------
    // Drags start only from the grip (mousedown arms them), so the buttons and
    // text selection inside a row are unaffected.

    handleGripMouseDown() {
        this._dragArmed = true;
    }

    handleRowMouseUp() {
        this._dragArmed = false;
    }

    handleDragStart(event) {
        if (!this._dragArmed || !this._editable || this.busy || this.renamingKey) {
            event.preventDefault();
            return;
        }
        event.stopPropagation();
        this.drag = { key: event.currentTarget.dataset.key };
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            try {
                event.dataTransfer.setData('text/plain', this.drag.key);
            } catch (e) {
                // LWS may block dataTransfer payloads; drag state lives in JS.
            }
        }
    }

    /** Where the pointer is over this row, and whether that slot may take the mover. */
    targetFor(event) {
        if (!this.drag) {
            return null;
        }
        const rect = event.currentTarget.getBoundingClientRect();
        const ratio = rect.height > 0 ? (event.clientY - rect.top) / rect.height : 0.5;
        const overKey = event.currentTarget.dataset.key;
        const target = dropTarget(this._tree, this.drag.key, overKey, ratio, true);
        if (!target) {
            return null;
        }
        const check = canDrop(this._tree, this.drag.key, target, this._maxDepth);
        return { target, overKey, ok: check.ok, reason: check.reason };
    }

    handleDragOver(event) {
        const hit = this.targetFor(event);
        if (!hit || !hit.ok) {
            // No preventDefault → no-drop cursor, drop never fires. Flag the row
            // either way: targetFor returns null over the mover's own subtree
            // (dropTarget refuses it outright), and a silent no-drop cursor
            // leaves the admin guessing why.
            const key = event.currentTarget.dataset.key;
            if (this.drag && key !== this.drag.key && this.invalidKey !== key) {
                this.invalidKey = key;
                this.announcement = (hit && hit.reason) || MSG.DESCENDANT;
            }
            if (this.dropHint) {
                this.dropHint = null;
            }
            return;
        }
        event.preventDefault();
        if (event.dataTransfer) {
            event.dataTransfer.dropEffect = 'move';
        }
        if (this.invalidKey) {
            this.invalidKey = null;
        }
        const { position } = hit.target;
        if (!this.dropHint || this.dropHint.key !== hit.overKey || this.dropHint.position !== position) {
            this.dropHint = { key: hit.overKey, position };
        }
    }

    handleDragLeave(event) {
        const key = event.currentTarget.dataset.key;
        if (this.dropHint && this.dropHint.key === key) {
            this.dropHint = null;
        }
        if (this.invalidKey === key) {
            this.invalidKey = null;
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const hit = this.targetFor(event);
        const dragKey = this.drag && this.drag.key;
        this.resetDrag();
        if (!hit || !hit.ok || !dragKey) {
            return;
        }
        this.applyTarget(dragKey, hit.target);
    }

    handleDragEnd() {
        this.resetDrag();
    }

    resetDrag() {
        this.drag = null;
        this.dropHint = null;
        this.invalidKey = null;
        this._dragArmed = false;
    }

    /** Turn a slot into the host's move payload; keep the new parent open. */
    applyTarget(key, target) {
        const result = moveResult(this._tree, key, target);
        if (!result) {
            return false; // dropped back where it was — nothing to save
        }
        if (result.newParentKey != null) {
            const next = new Set(this.expandedKeys);
            next.add(result.newParentKey);
            this._expanded = next;
        }
        const node = findNode(this._tree, key);
        const position = result.orderedSiblingKeys.indexOf(key) + 1;
        const parent = result.newParentKey == null ? null : findNode(this._tree, result.newParentKey);
        this.announcement = parent
            ? `${node.label} moved into ${parent.label}, position ${position} of ${result.orderedSiblingKeys.length}.`
            : `${node.label} moved to position ${position} of ${result.orderedSiblingKeys.length} at the top level.`;
        this._refocusKey = key;
        this.dispatchEvent(new CustomEvent('move', {
            detail: {
                key,
                newParentKey: result.newParentKey,
                orderedSiblingKeys: result.orderedSiblingKeys,
                movedLabel: node.label,
                position,
                total: result.orderedSiblingKeys.length
            }
        }));
        return true;
    }

    // ---- Keyboard on the grip ---------------------------------------------------------

    handleGripKeydown(event) {
        const key = event.currentTarget.dataset.key;
        const node = findNode(this._tree, key);
        if (!node || this.busy || !this._editable) {
            return;
        }
        let target = null;
        if (event.key === 'F2') {
            event.preventDefault();
            this.startRename(key);
            return;
        }
        if (event.altKey && event.key === 'ArrowLeft') {
            // Outdent: after the parent, among the parent's siblings.
            const parent = node.parentId == null ? null : findNode(this._tree, node.parentId);
            if (!parent) {
                return;
            }
            target = { parentKey: parent.parentId == null ? null : parent.parentId, index: parent.sortOrder + 1 };
        } else if (event.altKey && event.key === 'ArrowRight') {
            // Indent: into the previous sibling, as its last child.
            const prev = siblingsOf(this._tree, node.parentId)[node.sortOrder - 1];
            if (!prev) {
                return;
            }
            target = { parentKey: prev.id, index: prev.children.length };
        } else if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
            const dir = event.key === 'ArrowUp' ? -1 : 1;
            const siblings = siblingsOf(this._tree, node.parentId);
            const to = node.sortOrder + dir;
            if (to < 0 || to >= siblings.length) {
                return;
            }
            // Slot index in the list WITHOUT the mover: moving down means the
            // target slot is one further along.
            target = { parentKey: node.parentId == null ? null : node.parentId, index: dir > 0 ? to + 1 : to };
        } else {
            return;
        }
        event.preventDefault();
        const check = canDrop(this._tree, key, target, this._maxDepth);
        if (!check.ok) {
            this.announcement = check.reason || MSG.DESCENDANT;
            return;
        }
        this.applyTarget(key, target);
    }

    renderedCallback() {
        if (this._focusRename) {
            this._focusRename = false;
            const input = this.template.querySelector('.ate__rename');
            if (input) {
                input.focus();
                input.select();
            }
            return;
        }
        // Restore focus to the moved row's grip after a keyboard move re-renders;
        // wait for the not-busy render (grips are disabled while the host saves).
        if (!this._refocusKey || this.busy) {
            return;
        }
        const grip = this.template.querySelector(`.ate__grip[data-key="${this._refocusKey}"]`);
        this._refocusKey = null;
        if (grip) {
            grip.focus();
        }
    }
}