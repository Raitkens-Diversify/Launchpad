/**
 * Design-system custom data table (SLDS2 / v2 wizard).
 *
 * A semantic <table> we fully control the styling of — unlike lightning-datatable,
 * whose shadow-DOM internals can't be themed to the Figma. Keeps the behaviour
 * that matters: client-side column sorting (via c/dataTableSortUtils) and a
 * per-row action (⋮) menu. The `rowaction` event mirrors lightning-datatable's
 * `{ action: { name }, row }` detail so existing parent handlers work unchanged.
 */
import { LightningElement, api } from 'lwc';
import {
    SORT_ASC,
    createSortState,
    resolveSortDirection,
    sortRecords
} from 'c/dataTableSortUtils';

export default class DsDataTableV2 extends LightningElement {
    @api keyField = 'id';
    @api rowActions = [];
    // Rendered in place of empty (null/undefined/'') cell values. Defaults to ''
    // so existing consumers are unaffected; envelopeListV2 passes '-'.
    @api placeholder = '';

    _columns = [];
    @api
    get columns() {
        return this._columns;
    }
    set columns(value) {
        this._columns = Array.isArray(value) ? [...value] : [];
        this.applyCurrentSort();
    }

    _sourceData = [];
    @api
    get data() {
        return this._sourceData;
    }
    set data(value) {
        this._sourceData = Array.isArray(value) ? [...value] : [];
        this.applyCurrentSort();
    }

    _defaultSortField = '';
    @api
    get defaultSortField() {
        return this._defaultSortField;
    }
    set defaultSortField(value) {
        this._defaultSortField = value || '';
        this.initializeSortState();
    }

    _defaultSortDirection = SORT_ASC;
    @api
    get defaultSortDirection() {
        return this._defaultSortDirection;
    }
    set defaultSortDirection(value) {
        this._defaultSortDirection = value || SORT_ASC;
        this.initializeSortState();
    }

    sortedBy = '';
    sortedDirection = SORT_ASC;
    sortedData = [];

    connectedCallback() {
        this.initializeSortState();
    }

    initializeSortState() {
        const sortState = createSortState({
            fieldName: this._defaultSortField,
            direction: this._defaultSortDirection,
            records: this._sourceData,
            columns: this._columns
        });

        this.sortedBy = sortState.sortedBy;
        this.sortedDirection = sortState.sortedDirection;
        this.sortedData = sortState.sortedData;
    }

    applyCurrentSort() {
        this.sortedData = this.sortedBy
            ? sortRecords(this._sourceData, this.sortedBy, this.sortedDirection, this._columns)
            : [...this._sourceData];
    }

    get hasRowActions() {
        return Array.isArray(this.rowActions) && this.rowActions.length > 0;
    }

    get headerColumns() {
        return this._columns.map((column) => {
            const isActive = this.sortedBy === column.fieldName;
            const isSortable = column.sortable !== false;
            const isAscending = this.sortedDirection === SORT_ASC;

            return {
                key: column.fieldName,
                label: column.label,
                sortable: isSortable,
                ariaSort: isActive ? (isAscending ? 'ascending' : 'descending') : 'none',
                sortIcon: isActive && !isAscending ? 'utility:arrowdown' : 'utility:arrowup',
                sortIconClass: isActive
                    ? 'ds-data-table-v2__sort-icon ds-data-table-v2__sort-icon--active'
                    : 'ds-data-table-v2__sort-icon'
            };
        });
    }

    // Index of the primary navigation column: the first column flagged
    // `primary`, falling back to the first column so every table gets a
    // focusable link in each row even when no flag is supplied.
    get primaryColumnIndex() {
        const flagged = this._columns.findIndex((column) => column.primary === true);
        return flagged === -1 ? 0 : flagged;
    }

    get rows() {
        const primaryIndex = this.primaryColumnIndex;
        return this.sortedData.map((record) => {
            const rowKey = record[this.keyField];
            return {
                key: rowKey,
                cells: this._columns.map((column, index) => ({
                    key: column.fieldName,
                    value: this.formatCellValue(record[column.fieldName], column.type),
                    cellClass: 'ds-data-table-v2__cell',
                    // The primary cell renders a focusable link (keyboard/screen-reader
                    // path to open the record); other cells render plain text.
                    isPrimary: index === primaryIndex,
                    rowId: rowKey
                }))
            };
        });
    }

    formatCellValue(value, columnType) {
        if (value === null || value === undefined || value === '') {
            return this.placeholder;
        }

        if (columnType === 'currency') {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD'
            }).format(value);
        }

        if (columnType === 'date') {
            return new Intl.DateTimeFormat('en-US').format(new Date(value));
        }

        return value;
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.field;
        if (!fieldName) {
            return;
        }

        this.sortedDirection = resolveSortDirection(fieldName, this.sortedBy, this.sortedDirection);
        this.sortedBy = fieldName;
        this.applyCurrentSort();
    }

    handleSortKeyDown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        event.preventDefault();
        this.handleSort(event);
    }

    findRow(rowId) {
        return this._sourceData.find((record) => `${record[this.keyField]}` === `${rowId}`);
    }

    handleRowClick(event) {
        const row = this.findRow(event.currentTarget.dataset.id);
        this.dispatchEvent(new CustomEvent('rowclick', { detail: { row } }));
    }

    // Primary-cell link: the accessible (keyboard/screen-reader) path to open a
    // record. Reuses the `rowclick` contract; stopPropagation keeps the row's
    // own click from firing a second time.
    handlePrimaryClick(event) {
        event.stopPropagation();
        const row = this.findRow(event.currentTarget.dataset.id);
        this.dispatchEvent(new CustomEvent('rowclick', { detail: { row } }));
    }

    // Keep clicks inside the actions cell from bubbling to the row's click.
    handleActionCellClick(event) {
        event.stopPropagation();
    }

    // Map the button-menu's select event to the lightning-datatable-style
    // `rowaction` detail so existing parent handlers work unchanged.
    handleMenuSelect(event) {
        event.stopPropagation();
        const rowId = event.currentTarget.dataset.id;
        const name = event.detail.value;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action: { name }, row: this.findRow(rowId) }
            })
        );
    }
}