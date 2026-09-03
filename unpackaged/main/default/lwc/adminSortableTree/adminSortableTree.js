import { LightningElement, api } from 'lwc';

/**
 * adminSortableTree — the shared two-level admin tree with grip-based
 * drag-and-drop + keyboard reordering, extracted from the Help-topics pane of
 * adminCategoryManager so the Resource-categories pane behaves identically.
 *
 * Controlled component: it never reorders its own data. The host owns the
 * items and persistence (SOAP Metadata for help topics, DML for resource
 * categories) — on `reorder` it applies the new order optimistically and
 * reloads on save failure, which flows back down through `items`.
 *
 * items: [{ key, label, sublabel?, badge?, statusLabel?, statusClass?,
 *           children?: [same shape, no deeper nesting] }]
 * badge / statusLabel+statusClass / sublabel are optional config-driven row
 * decorations (per-row slots aren't expressible inside nested for:each);
 * rows without them render exactly like the original Help-topics rows.
 *
 * Events: reorder {parentKey|null, orderedKeys, movedKey, movedLabel,
 *         position, total}, edit {key, label}, addchild {parentKey}.
 *
 * Reorder constraints ride on the markup: top-level rows reorder among
 * themselves and carry their children with them (children nest inside the
 * parent <li>); children reorder only within their own parent — sameList()
 * on data-parent rejects everything else, so the browser shows a no-drop
 * cursor and never fires drop.
 */
export default class AdminSortableTree extends LightningElement {
    @api items = [];
    @api busy = false;
    @api editLabel = 'Edit';
    @api addChildLabel = 'Add subtopic';

    // Static boolean attributes arrive as '' — normalize presence to true so
    // hosts can write `editable` / `allow-add-child` without a binding.
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

    // Optional row actions added for the UAT dual picker (flat lists that
    // reorder + remove, no edit). Both default off — existing hosts
    // (Help topics, Resource categories) are unaffected.
    _removable = false;
    @api
    get removable() {
        return this._removable;
    }
    set removable(value) {
        this._removable = value === '' ? true : Boolean(value);
    }

    _hideEdit = false;
    @api
    get hideEdit() {
        return this._hideEdit;
    }
    set hideEdit(value) {
        this._hideEdit = value === '' ? true : Boolean(value);
    }

    @api removeLabel = 'Remove';

    // Drag-and-drop reorder state. Index/key-based, kept in JS — dataTransfer
    // payloads are unreliable under Lightning Web Security.
    drag = null;                 // {key, parentKey|null, index} while dragging
    dropTarget = null;           // {key, position: 'before'|'after'} under the pointer
    reorderAnnouncement = '';    // aria-live text for reorders
    _dragArmed = false;          // grip mousedown gate: drags must start on the grip
    _refocusKey = null;          // grip to refocus after a keyboard move re-renders

    get viewItems() {
        const decorate = (nodes, isChild) => (nodes || []).map((n, i) => ({
            ...n,
            index: i,
            dragEnabled: this.editable && !this.busy,
            gripLabel: `Reorder ${n.label}, position ${i + 1} of ${nodes.length}. Use arrow keys to move.`,
            rowClass: this.rowClass(n.key),
            labelClass: isChild ? 'acm__topic-label' : 'acm__topic acm__topic-label',
            showAddChild: this.allowAddChild && !isChild,
            showEdit: !this.hideEdit,
            showRemove: this.removable,
            children: isChild ? [] : decorate(n.children || [], true)
        }));
        return decorate(this.items, false);
    }

    rowClass(key) {
        let cls = 'acm__topic-row';
        if (this.drag && this.drag.key === key) {
            cls += ' acm__topic-row--dragging';
        }
        if (this.dropTarget && this.dropTarget.key === key) {
            cls += ` acm__topic-row--drop-${this.dropTarget.position}`;
        }
        return cls;
    }

    // ---- Row actions --------------------------------------------------------------

    handleEditClick(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('edit', {
            detail: { key: ds.key, label: ds.label }
        }));
    }

    handleAddChildClick(event) {
        this.dispatchEvent(new CustomEvent('addchild', {
            detail: { parentKey: event.currentTarget.dataset.key }
        }));
    }

    handleRemoveClick(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('remove', {
            detail: { key: ds.key, label: ds.label }
        }));
    }

    // ---- Reordering (drag-and-drop + keyboard on the grip) -------------------------
    // Drags start only from the grip (mousedown arms them), so the edit/add
    // buttons and text selection inside a row are unaffected.

    handleGripMouseDown() {
        this._dragArmed = true;
    }

    handleRowMouseUp() {
        this._dragArmed = false;
    }

    handleGripKeydown(event) {
        if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') {
            return;
        }
        event.preventDefault();
        this._refocusKey = event.currentTarget.dataset.key;
        this.moveItem(event.currentTarget.dataset, event.key === 'ArrowUp' ? -1 : 1);
    }

    renderedCallback() {
        // Restore focus to the moved row's grip after a keyboard reorder; wait
        // for the not-busy render (grips are disabled while the host saves).
        if (!this._refocusKey || this.busy) {
            return;
        }
        const grip = this.template.querySelector(`.acm__grip[data-key="${this._refocusKey}"]`);
        this._refocusKey = null;
        if (grip) {
            grip.focus();
        }
    }

    handleDragStart(event) {
        if (!this._dragArmed || !this.editable || this.busy) {
            event.preventDefault(); // drag didn't start on a grip — cancel it
            return;
        }
        event.stopPropagation();
        const ds = event.currentTarget.dataset;
        this.drag = { key: ds.key, parentKey: ds.parent || null, index: Number(ds.index) };
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            try {
                event.dataTransfer.setData('text/plain', ds.key);
            } catch (e) {
                // LWS may block dataTransfer payloads; drag state lives in JS.
            }
        }
    }

    handleDragOver(event) {
        if (!this.sameList(event.currentTarget.dataset)) {
            return; // no preventDefault -> browser shows no-drop, drop never fires
        }
        event.preventDefault();
        if (event.dataTransfer) {
            event.dataTransfer.dropEffect = 'move';
        }
        const rect = event.currentTarget.getBoundingClientRect();
        const position = event.clientY < rect.top + rect.height / 2 ? 'before' : 'after';
        const key = event.currentTarget.dataset.key;
        if (!this.dropTarget || this.dropTarget.key !== key
            || this.dropTarget.position !== position) {
            this.dropTarget = { key, position };
        }
    }

    handleDragLeave(event) {
        if (this.dropTarget && this.dropTarget.key === event.currentTarget.dataset.key) {
            this.dropTarget = null;
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const ds = event.currentTarget.dataset;
        const drag = this.drag;
        const dropTarget = this.dropTarget;
        this.drag = null;
        this.dropTarget = null;
        this._dragArmed = false;
        if (!drag || (ds.parent || null) !== drag.parentKey) {
            return;
        }
        const keys = this.siblingKeys(drag.parentKey);
        const from = keys.indexOf(drag.key);
        if (from < 0) {
            return;
        }
        const after = dropTarget && dropTarget.key === ds.key && dropTarget.position === 'after';
        let to = Number(ds.index) + (after ? 1 : 0);
        if (from < to) {
            to -= 1;
        }
        if (from === to) {
            return; // dropped back where it was — nothing to save
        }
        keys.splice(to, 0, keys.splice(from, 1)[0]);
        this.emitReorder(drag.parentKey, keys, drag.key);
    }

    handleDragEnd() {
        this.drag = null;
        this.dropTarget = null;
        this._dragArmed = false;
    }

    sameList(dataset) {
        return Boolean(this.drag) && (dataset.parent || null) === this.drag.parentKey;
    }

    siblingKeys(parentKey) {
        const siblings = parentKey
            ? (this.items.find((t) => t.key === parentKey) || {}).children || []
            : this.items;
        return siblings.map((s) => s.key);
    }

    /** Keyboard reorder: move one position within the sibling list. */
    moveItem(dataset, direction) {
        if (this.busy) {
            return;
        }
        const parentKey = dataset.parent || null;
        const keys = this.siblingKeys(parentKey);
        const from = keys.indexOf(dataset.key);
        const to = from + direction;
        if (from < 0 || to < 0 || to >= keys.length) {
            return;
        }
        keys.splice(from, 1);
        keys.splice(to, 0, dataset.key);
        this.emitReorder(parentKey, keys, dataset.key);
    }

    /**
     * Announce at emit time: the host applies this order optimistically, and
     * the server-side stale-set validation means a success IS this order.
     */
    emitReorder(parentKey, orderedKeys, movedKey) {
        const siblings = parentKey
            ? (this.items.find((t) => t.key === parentKey) || {}).children || []
            : this.items;
        const moved = siblings.find((s) => s.key === movedKey);
        const movedLabel = moved ? moved.label : movedKey;
        const position = orderedKeys.indexOf(movedKey) + 1;
        this.reorderAnnouncement =
            `${movedLabel} moved to position ${position} of ${orderedKeys.length}.`;
        this.dispatchEvent(new CustomEvent('reorder', {
            detail: {
                parentKey,
                orderedKeys,
                movedKey,
                movedLabel,
                position,
                total: orderedKeys.length
            }
        }));
    }
}