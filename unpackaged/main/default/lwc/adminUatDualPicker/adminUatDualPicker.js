import { LightningElement, api } from 'lwc';

/**
 * adminUatDualPicker — the one reusable add/remove list manager for the UAT
 * console sections, used everywhere the spec needs a two-pane picker:
 * cases-in-book, books-in-cycle, and direct-cases-in-cycle.
 *
 * Controlled component on the adminSortableTree contract: it never mutates
 * its own data. The host owns both lists and persistence — on `add`/`remove`/
 * `reorder` it applies optimistically (or calls Apex) and passes fresh lists
 * back down. Remove confirmations are the HOST's job (each site has its own
 * consequence wording through the shared adminConfirmModal).
 *
 * Left pane: attached items. When `orderable`, it composes adminSortableTree
 * in flat mode — grip drag-and-drop + keyboard reordering, the console's
 * established reorder control (the build prompt's supersession of the spec's
 * up/down arrows).
 * Right pane: available items with client-side search + System filter.
 *
 * @api selectedItems  [{id, label, sublabel?}] in display/run order
 * @api availableItems [{id, label, sublabel?, systemId?}]
 * @api systemOptions  [{label, value}] — omit to hide the System filter
 * @api orderable      left pane reorders via drag-and-drop when present
 * Events: add {id}, remove {id, label}, reorder {orderedIds}
 */
export default class AdminUatDualPicker extends LightningElement {
    @api selectedItems = [];
    @api availableItems = [];
    @api systemOptions;
    @api busy = false;
    @api selectedLabel = 'Selected';
    @api availableLabel = 'Available';
    @api selectedEmptyText = 'Nothing here yet — add from the right.';
    @api availableEmptyText = 'Nothing matches.';
    @api searchPlaceholder = 'Search…';

    _orderable = false;
    @api
    get orderable() {
        return this._orderable;
    }
    set orderable(value) {
        this._orderable = value === '' ? true : Boolean(value);
    }

    searchTerm = '';
    systemFilter = '';

    // ---- Left pane -----------------------------------------------------------

    get hasSelected() {
        return (this.selectedItems || []).length > 0;
    }

    get treeItems() {
        // Flat list for adminSortableTree: top-level items, no children.
        return (this.selectedItems || []).map((i) => ({
            key: i.id,
            label: i.label,
            sublabel: i.sublabel
        }));
    }

    get plainSelected() {
        return this.selectedItems || [];
    }

    handleTreeReorder(event) {
        this.dispatchEvent(new CustomEvent('reorder', {
            detail: { orderedIds: event.detail.orderedKeys }
        }));
    }

    handleTreeRemove(event) {
        this.dispatchEvent(new CustomEvent('remove', {
            detail: { id: event.detail.key, label: event.detail.label }
        }));
    }

    handleRowRemove(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('remove', {
            detail: { id: ds.id, label: ds.label }
        }));
    }

    // ---- Right pane -----------------------------------------------------------

    get showSystemFilter() {
        return this.systemOptions && this.systemOptions.length > 0;
    }

    get systemFilterOptions() {
        return [{ label: 'All systems', value: '' }].concat(this.systemOptions || []);
    }

    get filteredAvailable() {
        const term = (this.searchTerm || '').toLowerCase();
        return (this.availableItems || []).filter((i) => {
            if (this.systemFilter && i.systemId !== this.systemFilter) {
                return false;
            }
            if (term) {
                const hay = ((i.label || '') + ' ' + (i.sublabel || '')).toLowerCase();
                if (!hay.includes(term)) {
                    return false;
                }
            }
            return true;
        });
    }

    get hasAvailable() {
        return this.filteredAvailable.length > 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleSystemFilterChange(event) {
        this.systemFilter = event.detail.value;
    }

    handleAdd(event) {
        this.dispatchEvent(new CustomEvent('add', {
            detail: { id: event.currentTarget.dataset.id }
        }));
    }
}