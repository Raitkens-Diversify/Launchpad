/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Reusable diversify-styled data table: client-side sorting, anchor record links,
 * optional row-action menu, and optional built-in pagination. Self-contained CSS
 * (no diversifyStyles static resource).
 */
import { LightningElement, api, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getRecords, getFieldValue } from "lightning/uiRecordApi";
import USER_NAME from "@salesforce/schema/User.Name";
import {
  buildExperienceRecordPath,
  buildRecordNavigationReference,
  resolveRecordUrl,
  shouldAllowNativeRecordNavigation,
  usesQueryParamRecordRoute,
} from "c/recordNavigationCommunityUtils";
import {
  SORT_ASC,
  resolveSortDirection,
  sortRecords,
} from "c/dataTableSortUtils";

const DEFAULT_PAGE_SIZE = 10;
const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50];
const DEFAULT_SCROLL_COLUMN_MIN_WIDTH = "8rem";

const USER_ID_COLUMN_TYPES = new Set(["userid", "user_id", "user"]);
const SALESFORCE_ID_PATTERN = /^[a-zA-Z0-9]{15,18}$/;

const parseNumericCellValue = (value) => {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  const normalized = String(value).replace(/[^0-9.-]/g, "");

  if (!normalized || normalized === "-" || normalized === ".") {
    return null;
  }

  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
};

export default class StyledDataTable extends NavigationMixin(LightningElement) {
  @api keyField = "id";
  @api rowActions = [];
  @api placeholder = "";
  @api title = "";
  @api ariaLabel = "Data table";
  @api defaultLinkObjectApiName = "";
  @api linkObjectApiNameField = "objectApiName";

  _enablePagination = true;
  @api
  get enablePagination() {
    return this._enablePagination;
  }
  set enablePagination(value) {
    this._enablePagination = value !== false && value !== "false";
  }

  _enableRowClick = false;
  @api
  get enableRowClick() {
    return this._enableRowClick;
  }
  set enableRowClick(value) {
    this._enableRowClick = value !== false && value !== "false";
  }

  @api rowDetailType = "";
  @api rowDetailGroupsField = "taskGroups";
  @api detailRowActions = [];

  _expandedRowIds = [];
  @api
  get expandedRowIds() {
    return this._expandedRowIds;
  }
  set expandedRowIds(value) {
    if (Array.isArray(value)) {
      this._expandedRowIds = [...value];
      return;
    }

    if (typeof value === "string" && value.trim()) {
      this._expandedRowIds = value.split(",").map((entry) => entry.trim());
      return;
    }

    this._expandedRowIds = [];
  }

  /** @deprecated Use expandedRowIds */
  @api
  get expandedRowId() {
    return this._expandedRowIds[0] || null;
  }
  set expandedRowId(value) {
    this._expandedRowIds = value ? [value] : [];
  }

  @api emptyMessage = "No results found";
  // Comma-separated object API names whose experience links use /{route}?id={recordId}
  // instead of /{route}/{recordId}. Example: "Envelope__c".
  @api linkQueryParamObjectApiNames = "";

  _isLoading = false;
  @api
  get isLoading() {
    return this._isLoading;
  }
  set isLoading(value) {
    this._isLoading = value === true || value === "true";
  }

  _enableSideScrolling = true;
  @api
  get enableSideScrolling() {
    return this._enableSideScrolling;
  }
  set enableSideScrolling(value) {
    this._enableSideScrolling = value !== false && value !== "false";
  }

  // Rows shown per page when pagination is enabled. Override via page-size on the parent.
  _pageSize = DEFAULT_PAGE_SIZE;
  @api
  get pageSize() {
    return this._pageSize;
  }
  set pageSize(value) {
    const parsed = Number(value);
    this._pageSize =
      Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : DEFAULT_PAGE_SIZE;
    this.page = 1;
  }

  _pageSizeOptions = DEFAULT_PAGE_SIZE_OPTIONS;
  @api
  get pageSizeOptions() {
    return this._pageSizeOptions;
  }
  set pageSizeOptions(value) {
    this._pageSizeOptions =
      Array.isArray(value) && value.length ? [...value] : DEFAULT_PAGE_SIZE_OPTIONS;
  }

  _columns = [];
  @api
  get columns() {
    return this._columns;
  }
  set columns(value) {
    this._columns = Array.isArray(value) ? [...value] : [];
    if (!this._useExternalSort) {
      this.applyCurrentSort();
    }
  }

  _sourceData = [];
  @api
  get data() {
    return this._sourceData;
  }
  set data(value) {
    const nextData = Array.isArray(value) ? [...value] : [];
    const dataCollectionChanged = this.hasDataCollectionChanged(
      this._sourceData,
      nextData
    );

    this._sourceData = nextData;

    if (dataCollectionChanged) {
      this.page = 1;
    }

    if (!this._useExternalSort) {
      this.applyCurrentSort();
    }
    this.resolveRecordUrls(this._sourceData);
  }

  _useExternalSort = false;
  @api
  get useExternalSort() {
    return this._useExternalSort;
  }
  set useExternalSort(value) {
    this._useExternalSort = value === true || value === "true";
  }

  _externalSortedBy = "";
  @api
  get externalSortedBy() {
    return this._externalSortedBy;
  }
  set externalSortedBy(value) {
    this._externalSortedBy = value || "";
  }

  _externalSortedDirection = SORT_ASC;
  @api
  get externalSortedDirection() {
    return this._externalSortedDirection;
  }
  set externalSortedDirection(value) {
    this._externalSortedDirection = value || SORT_ASC;
  }

  _defaultSortField = "";
  @api
  get defaultSortField() {
    return this._defaultSortField;
  }
  set defaultSortField(value) {
    this._defaultSortField = value || "";
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

  sortedBy = "";
  sortedDirection = SORT_ASC;
  @track sortedData = [];
  recordUrlById = {};
  page = 1;
  @track _detailGroupExpansion = {};
  @track userDisplayNameById = {};

  connectedCallback() {
    this.initializeSortState();
  }

  get userRecordWireInputs() {
    const userIds = this.collectUserIdsForWire();

    if (!userIds.length) {
      return undefined;
    }

    return [{ recordIds: userIds, fields: [USER_NAME] }];
  }

  @wire(getRecords, { records: "$userRecordWireInputs" })
  wiredUserRecords({ data }) {
    if (!data?.results?.length) {
      return;
    }

    const nextMap = { ...this.userDisplayNameById };

    data.results.forEach((entry) => {
      const record = entry?.result?.data;

      if (!record?.id) {
        return;
      }

      const displayName = getFieldValue(record, USER_NAME);

      if (displayName) {
        nextMap[record.id] = displayName;
      }
    });

    this.userDisplayNameById = nextMap;

    if (this.sortedBy) {
      this.applyCurrentSort();
    }
  }

  @api
  refreshSort() {
    this.applyCurrentSort();
  }

  resolveSortValue(record, sortField, column) {
    if (!record || !sortField) {
      return null;
    }

    if (column && this.isUserIdColumn(column)) {
      const userId = this.resolveUserIdValue(record, column);
      const inferredField = this.inferUserDisplayFieldName(column.fieldName);
      const inferredName = inferredField ? record?.[inferredField] : "";

      if (inferredName) {
        return inferredName;
      }

      if (userId && this.userDisplayNameById[userId]) {
        return this.userDisplayNameById[userId];
      }
    }

    if (!sortField.includes(".")) {
      return record[sortField];
    }

    return sortField
      .split(".")
      .reduce((current, key) => current?.[key], record);
  }

  initializeSortState() {
    this.sortedBy = this._defaultSortField || "";
    this.sortedDirection = this._defaultSortDirection || SORT_ASC;
    this.applyCurrentSort();
  }

  get hasRows() {
    return this.paginatedData.length > 0;
  }

  get hasTitle() {
    return Boolean(this.title?.trim());
  }

  get showLoading() {
    return this._isLoading;
  }

  get usesHorizontalScrollLayout() {
    return this._enableSideScrolling && this.hasRows;
  }

  get scrollContainerClass() {
    return this.usesHorizontalScrollLayout
      ? "div-table-scroll div-table-scroll--horizontal"
      : "div-table-scroll";
  }

  get tableClass() {
    return this.usesHorizontalScrollLayout
      ? "div-table div-table--horizontal-scroll"
      : "div-table";
  }

  get emptyColspan() {
    return this._columns.length + (this.hasRowActions ? 1 : 0);
  }

  get showEmptyRow() {
    return !this.hasRows && this._columns.length > 0;
  }

  applyCurrentSort() {
    this.sortedData = this.sortedBy
      ? sortRecords(
          this._sourceData,
          this.sortedBy,
          this.sortedDirection,
          this._columns,
          (record, sortField, column) =>
            this.resolveSortValue(record, sortField, column)
        )
      : [...this._sourceData];
  }

  hasDataCollectionChanged(previousData, nextData) {
    const previousRows = Array.isArray(previousData) ? previousData : [];
    const nextRows = Array.isArray(nextData) ? nextData : [];

    if (previousRows.length !== nextRows.length) {
      return true;
    }

    if (!previousRows.length) {
      return false;
    }

    const keyField = this.keyField;

    for (let index = 0; index < nextRows.length; index += 1) {
      const previousKey = `${previousRows[index]?.[keyField] ?? ""}`;
      const nextKey = `${nextRows[index]?.[keyField] ?? ""}`;

      if (previousKey !== nextKey) {
        return true;
      }
    }

    return false;
  }

  get hasRowActions() {
    return Array.isArray(this.rowActions) && this.rowActions.length > 0;
  }

  get hasDetailRowActions() {
    return Array.isArray(this.detailRowActions) && this.detailRowActions.length > 0;
  }

  get totalRows() {
    return this._useExternalSort ? this._sourceData.length : this.sortedData.length;
  }

  get pageCount() {
    return Math.max(1, Math.ceil(this.totalRows / this._pageSize));
  }

  get clampedPage() {
    return Math.min(this.page, this.pageCount);
  }

  get paginatedData() {
    const sourceRows = this._useExternalSort ? this._sourceData : this.sortedData;

    if (!this._enablePagination) {
      return sourceRows;
    }

    const start = (this.clampedPage - 1) * this._pageSize;
    return sourceRows.slice(start, start + this._pageSize);
  }

  get showPager() {
    return this._enablePagination && this.totalRows > 0;
  }

  get pageSizeSelectValue() {
    return String(this._pageSize);
  }

  get resolvedPageSizeOptions() {
    const options = this._pageSizeOptions?.length
      ? [...this._pageSizeOptions]
      : [...DEFAULT_PAGE_SIZE_OPTIONS];
    const current = Number(this._pageSize);

    if (current > 0 && !options.includes(current)) {
      options.push(current);
      options.sort((left, right) => left - right);
    }

    return options;
  }

  get pageSizeOptionViews() {
    const current = this._pageSize;

    return this.resolvedPageSizeOptions.map((option) => {
      const value = Number(option);
      return {
        key: String(value),
        value: String(value),
        label: String(value),
        isSelected: value === current,
      };
    });
  }

  get prevDisabled() {
    return this.clampedPage <= 1;
  }

  get nextDisabled() {
    return this.clampedPage >= this.pageCount;
  }

  get pageItems() {
    const count = this.pageCount;
    const current = this.clampedPage;
    let pages;

    if (count <= 7) {
      pages = [];
      for (let index = 1; index <= count; index += 1) {
        pages.push(index);
      }
    } else {
      let start = Math.max(2, current - 2);
      let end = Math.min(count - 1, current + 2);

      if (current <= 3) {
        start = 2;
        end = 5;
      }

      if (current >= count - 2) {
        start = count - 4;
        end = count - 1;
      }

      pages = [1];

      if (start > 2) {
        pages.push("gap-lead");
      }

      for (let index = start; index <= end; index += 1) {
        pages.push(index);
      }

      if (end < count - 1) {
        pages.push("gap-trail");
      }

      pages.push(count);
    }

    return pages.map((entry) => {
      if (typeof entry === "string") {
        return { key: entry, isGap: true };
      }

      const isCurrent = entry === current;
      return {
        key: `page-${entry}`,
        isGap: false,
        page: entry,
        label: String(entry),
        ariaCurrent: isCurrent ? "page" : null,
        cssClass: isCurrent
          ? "div-table-pager__btn div-table-pager__btn--current"
          : "div-table-pager__btn",
      };
    });
  }

  get activeSortedBy() {
    return this._useExternalSort ? this._externalSortedBy : this.sortedBy;
  }

  get activeSortedDirection() {
    return this._useExternalSort
      ? this._externalSortedDirection
      : this.sortedDirection;
  }

  get primaryColumnIndex() {
    const flagged = this._columns.findIndex(
      (column) => column.primary === true || column.isLink === true
    );
    return flagged === -1 ? 0 : flagged;
  }

  get headerColumns() {
    return this._columns.map((column) => {
      const isActive = this.activeSortedBy === column.fieldName;
      const isSortable = column.sortable !== false;
      const isAscending = this.activeSortedDirection === SORT_ASC;

      return {
        key: column.fieldName,
        label: column.label,
        sortable: isSortable,
        headerClass: column.type === "number" ? "div-table__cell--numeric" : "",
        style: this.resolveColumnStyle(column),
        ariaSort: isActive ? (isAscending ? "ascending" : "descending") : "none",
        sortIcon: isActive && !isAscending ? "utility:arrowdown" : "utility:arrowup",
        sortIconClass: isActive
          ? "div-table__sort-icon div-table__sort-icon--active"
          : "div-table__sort-icon",
      };
    });
  }

  get expandedRowIdSet() {
    return new Set((this._expandedRowIds || []).map((rowId) => `${rowId}`));
  }

  get isWorkTaskDetail() {
    return this.rowDetailType === "workTasks";
  }

  isRowExpanded(rowKey) {
    return this.expandedRowIdSet.has(`${rowKey}`);
  }

  getRowDetailGroups(record) {
    if (!record) {
      return [];
    }

    const groups = record[this.rowDetailGroupsField];
    return Array.isArray(groups) ? groups : [];
  }

  hasExpandableRowDetail(record) {
    return this.getRowDetailGroups(record).some(
      (group) => Array.isArray(group.tasks) && group.tasks.length > 0
    );
  }

  get rows() {
    const primaryIndex = this.primaryColumnIndex;

    return this.paginatedData.map((record) => {
      const rowKey = record[this.keyField];
      const isExpanded = this.isRowExpanded(rowKey);
      const canExpandRow =
        this._enableRowClick && this.hasExpandableRowDetail(record);
      const rowClass = isExpanded ? "div-table__row--expanded" : "";

      return {
        key: rowKey,
        rowClass,
        cells: this._columns.map((column, index) => {
          const isExpandColumn = column.type === "expand";
          const showExpandChevron =
            !isExpandColumn &&
            canExpandRow &&
            column.showExpandChevron === true;
          const isLinkColumn =
            !isExpandColumn &&
            (column.isLink === true ||
              column.primary === true ||
              index === primaryIndex);
          const objectApiName = isLinkColumn
            ? this.resolveObjectApiName(column, record)
            : "";
          const linkPathOptions = this.buildLinkPathOptions(objectApiName);
          const recordUrl =
            this.recordUrlById[rowKey] ||
            buildExperienceRecordPath(rowKey, objectApiName, linkPathOptions);
          const rawValue = record[column.fieldName];
          const isPill = column.type === "pill";
          const pillClassField =
            column.pillClassField || `${column.fieldName}PillClass`;
          const displayValue = isPill
            ? rawValue ?? this.placeholder
            : this.resolveCellDisplayValue(record, column, rawValue);

          return {
            key: column.fieldName,
            label: column.label,
            value: displayValue,
            cellClass: this.buildCellClass(column, isLinkColumn, isExpandColumn),
            style: this.resolveColumnStyle(column),
            isLink: Boolean(isLinkColumn && rowKey),
            isPill,
            isExpand: isExpandColumn,
            showExpandChevron,
            isExpanded,
            expandIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
            expandAriaLabel: isExpanded ? "Collapse row" : "Expand row",
            pillClass: record[pillClassField] || "div-work-pill",
            recordId: rowKey,
            objectApiName,
            recordUrl,
            linkAriaLabel: displayValue ? `Open ${displayValue}` : "Open record",
          };
        }),
      };
    });
  }

  get tableBodyItems() {
    const items = [];

    for (const row of this.rows) {
      items.push({
        key: row.key,
        isDataRow: true,
        row,
      });

      if (!this.isRowExpanded(row.key)) {
        continue;
      }

      if (this.isWorkTaskDetail) {
        items.push(...this.buildWorkTaskDetailItems(row.key));
        continue;
      }

      items.push({
        key: `${row.key}-detail`,
        isDetailWrapper: true,
        detailTaskGroups: this.getRowDetailGroups(this.findRow(row.key)),
      });
    }

    return items;
  }

  buildWorkTaskDetailItems(rowKey) {
    const taskGroups = this.getRowDetailGroups(this.findRow(rowKey));
    const detailColumnCount = 5 + (this.hasDetailRowActions ? 1 : 0);

    const groupViews = taskGroups.map((group) => {
      const isExpanded = this.isDetailGroupExpanded(rowKey, group.key);

      return {
        key: group.key,
        rowKey,
        groupKey: group.key,
        label: group.label,
        isExpanded,
        expandIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
        detailColumnCount,
        tasks: isExpanded
          ? (group.tasks || []).map((task) => this.enrichWorkTask(task))
          : [],
      };
    });

    return [
      {
        key: `${rowKey}-work-detail`,
        isWorkDetailSection: true,
        rowKey,
        sectionColspan: this.emptyColspan,
        detailColumnCount,
        groupViews,
        hasGroups: groupViews.length > 0,
        hasDetailRowActions: this.hasDetailRowActions,
      },
    ];
  }

  enrichWorkTask(task) {
    return {
      ...task,
      dueDate: task.dueDate || this.placeholder,
      completedDate: task.completedDate || this.placeholder,
      recordUrl: buildExperienceRecordPath(task.id, "Task"),
      linkAriaLabel: task.name ? `Open ${task.name}` : "Open task",
      statusPillClass: task.statusPillClass || "div-work-pill div-work-pill--not-started",
    };
  }

  isDetailGroupExpanded(rowKey, groupKey) {
    const expandedGroups = this._detailGroupExpansion[rowKey];

    if (!expandedGroups) {
      return true;
    }

    return expandedGroups.includes(groupKey);
  }

  getDefaultExpandedGroupKeys(rowKey) {
    return this.getRowDetailGroups(this.findRow(rowKey)).map((group) => group.key);
  }

  handleDetailGroupToggle(event) {
    event.stopPropagation();

    const rowKey = event.currentTarget.dataset.rowKey;
    const groupKey = event.currentTarget.dataset.groupKey;

    if (!rowKey || !groupKey) {
      return;
    }

    const currentGroups =
      this._detailGroupExpansion[rowKey] || this.getDefaultExpandedGroupKeys(rowKey);

    if (currentGroups.includes(groupKey)) {
      this._detailGroupExpansion = {
        ...this._detailGroupExpansion,
        [rowKey]: currentGroups.filter((key) => key !== groupKey),
      };
      return;
    }

    this._detailGroupExpansion = {
      ...this._detailGroupExpansion,
      [rowKey]: [...currentGroups, groupKey],
    };
  }

  handleDetailGroupKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleDetailGroupToggle(event);
  }

  handleDetailInteraction(event) {
    event.stopPropagation();
  }

  handleDetailTaskLinkClick(event) {
    event.stopPropagation();

    const openInNewContext = shouldAllowNativeRecordNavigation(event);
    if (openInNewContext) {
      return;
    }

    event.preventDefault();

    const recordId = event.currentTarget.dataset.recordId;
    if (!recordId) {
      return;
    }

    const pageReference = buildRecordNavigationReference(recordId, "Task");
    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  isUserIdColumn(column) {
    const columnType = String(column?.type || "").toLowerCase();

    if (USER_ID_COLUMN_TYPES.has(columnType)) {
      return true;
    }

    return columnType === "reference" && column?.referenceTo === "User";
  }

  collectUserIdsForWire() {
    const userColumns = (this._columns || []).filter((column) =>
      this.isUserIdColumn(column)
    );

    if (!userColumns.length || !this._sourceData.length) {
      return [];
    }

    const userIds = new Set();

    this._sourceData.forEach((record) => {
      userColumns.forEach((column) => {
        const userId = this.resolveUserIdValue(record, column);

        if (userId && SALESFORCE_ID_PATTERN.test(userId)) {
          userIds.add(userId);
        }
      });
    });

    return [...userIds];
  }

  resolveUserIdValue(record, column) {
    const rawValue = record?.[column.fieldName];

    if (rawValue === null || rawValue === undefined || rawValue === "") {
      return "";
    }

    return String(rawValue).trim();
  }

  inferUserDisplayFieldName(fieldName) {
    if (!fieldName) {
      return "";
    }

    if (fieldName.endsWith("Id")) {
      return `${fieldName.slice(0, -2)}Name`;
    }

    return `${fieldName}Name`;
  }

  resolveCellDisplayValue(record, column, rawValue) {
    if (column?.displayField && record?.[column.displayField]) {
      return record[column.displayField];
    }

    if (this.isUserIdColumn(column)) {
      const userId = this.resolveUserIdValue(record, column);
      const inferredField = this.inferUserDisplayFieldName(column.fieldName);
      const inferredName = inferredField ? record?.[inferredField] : "";

      if (inferredName) {
        return inferredName;
      }

      if (userId && this.userDisplayNameById[userId]) {
        return this.userDisplayNameById[userId];
      }

      if (userId && SALESFORCE_ID_PATTERN.test(userId)) {
        return this.userDisplayNameById[userId] || this.placeholder;
      }
    }

    return this.formatCellValue(rawValue, column?.type);
  }

  formatCellValue(value, columnType) {
    if (value === null || value === undefined || value === "") {
      return this.placeholder;
    }

    if (columnType === "currency" || columnType === "number") {
      const numericValue = parseNumericCellValue(value);

      if (numericValue === null) {
        return this.placeholder;
      }

      if (columnType === "number") {
        return new Intl.NumberFormat("en-US").format(numericValue);
      }

      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
      }).format(numericValue);
    }

    if (columnType === "date") {
      const timestamp = new Date(value).getTime();

      if (Number.isNaN(timestamp)) {
        return this.placeholder;
      }

      return new Intl.DateTimeFormat("en-US").format(new Date(value));
    }

    return value;
  }

  resolveObjectApiName(column, record) {
    if (column.linkObjectApiName) {
      return column.linkObjectApiName;
    }

    const fieldValue = record?.[this.linkObjectApiNameField];
    if (fieldValue) {
      return fieldValue;
    }

    return this.defaultLinkObjectApiName || "";
  }

  get queryParamLinkObjectApiNameSet() {
    if (!this.linkQueryParamObjectApiNames) {
      return new Set();
    }

    return new Set(
      this.linkQueryParamObjectApiNames
        .split(",")
        .map((entry) => entry.trim())
        .filter(Boolean)
    );
  }

  usesQueryParamLink(objectApiName) {
    return Boolean(objectApiName && this.queryParamLinkObjectApiNameSet.has(objectApiName));
  }

  buildLinkPathOptions(objectApiName) {
    return {
      useQueryParam:
        this.usesQueryParamLink(objectApiName) ||
        usesQueryParamRecordRoute(objectApiName),
    };
  }

  resolveColumnStyle(column) {
    if (!this.usesHorizontalScrollLayout || !column) {
      return "";
    }

    if (column.type === "expand") {
      return "min-width: 2rem";
    }

    const explicitWidth = column.minWidth ?? column.initialWidth ?? column.fixedWidth;

    if (explicitWidth === null || explicitWidth === undefined || explicitWidth === "") {
      return `min-width: ${DEFAULT_SCROLL_COLUMN_MIN_WIDTH}`;
    }

    if (typeof explicitWidth === "number") {
      return `min-width: ${explicitWidth}px`;
    }

    return `min-width: ${String(explicitWidth)}`;
  }

  buildCellClass(column, isLinkColumn, isExpandColumn) {
    const classes = [];

    if (column.type === "number") {
      classes.push("div-table__cell--numeric");
    }

    if (isExpandColumn) {
      classes.push("styled-data-table__cell--expand");
    }

    if (isLinkColumn) {
      classes.push("div-table__cell--link");
    }

    if (column.type === "pill") {
      classes.push("div-table__cell--pill");
    }

    if (column.cellClass) {
      classes.push(column.cellClass);
    }

    return classes.join(" ");
  }

  async resolveRecordUrls(rows) {
    if (!rows?.length) {
      this.recordUrlById = {};
      return;
    }

    const linkColumns = this._columns.filter(
      (column) => column.isLink === true || column.primary === true
    );

    if (!linkColumns.length && this.primaryColumnIndex === 0) {
      // Default first column may act as link when no explicit flag is set.
    }

    const uniqueRows = [...new Map(rows.map((row) => [row[this.keyField], row])).values()];
    const entries = await Promise.all(
      uniqueRows.map(async (row) => {
        const rowKey = row[this.keyField];
        const linkColumn =
          linkColumns[0] || this._columns[this.primaryColumnIndex] || this._columns[0];
        const objectApiName = linkColumn
          ? this.resolveObjectApiName(linkColumn, row)
          : this.defaultLinkObjectApiName;
        const linkPathOptions = this.buildLinkPathOptions(objectApiName);
        const url = await resolveRecordUrl(this, rowKey, objectApiName, linkPathOptions);
        return [rowKey, url];
      })
    );

    this.recordUrlById = Object.fromEntries(
      entries.filter(([, url]) => Boolean(url))
    );
  }

  handleSort(event) {
    const fieldName =
      event.currentTarget.getAttribute("data-field") ||
      event.currentTarget.dataset.field;

    if (!fieldName) {
      return;
    }

    const nextDirection = resolveSortDirection(
      fieldName,
      this.activeSortedBy,
      this.activeSortedDirection
    );

    if (this._useExternalSort) {
      this.dispatchEvent(
        new CustomEvent("sort", {
          detail: {
            fieldName,
            direction: nextDirection,
          },
          bubbles: true,
          composed: true,
        })
      );
      return;
    }

    this.sortedDirection = nextDirection;
    this.sortedBy = fieldName;
    this.page = 1;
    this.applyCurrentSort();
  }

  handleSortKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    this.handleSort(event);
  }

  handlePageSizeChange(event) {
    const nextPageSize = Number(event.target.value);
    if (!nextPageSize || nextPageSize === this._pageSize) {
      return;
    }

    this._pageSize = nextPageSize;
    this.page = 1;
  }

  handlePrevious() {
    this.emitPageChange(this.clampedPage - 1);
  }

  handleNext() {
    this.emitPageChange(this.clampedPage + 1);
  }

  handlePageClick(event) {
    this.emitPageChange(Number(event.currentTarget.dataset.page));
  }

  emitPageChange(targetPage) {
    const page = Math.min(Math.max(1, targetPage), this.pageCount);
    if (page === this.clampedPage) {
      return;
    }

    this.page = page;
  }

  findRow(rowId) {
    return this._sourceData.find(
      (record) => `${record[this.keyField]}` === `${rowId}`
    );
  }

  emitRowClick(row) {
    this.dispatchEvent(
      new CustomEvent("rowclick", {
        detail: { row },
        bubbles: true,
        composed: true,
      })
    );
  }

  emitRowAction(detail) {
    this.dispatchEvent(
      new CustomEvent("rowaction", {
        detail,
        bubbles: true,
        composed: true,
      })
    );
  }

  handleExpandChevronClick(event) {
    event.stopPropagation();

    if (!this._enableRowClick) {
      return;
    }

    const row = this.findRow(event.currentTarget.dataset.id);
    if (!this.hasExpandableRowDetail(row)) {
      return;
    }

    this.emitRowClick(row);
  }

  handleRecordLinkClick(event) {
    event.stopPropagation();

    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;
    const openInNewContext = shouldAllowNativeRecordNavigation(event);

    if (openInNewContext) {
      return;
    }

    event.preventDefault();

    if (!recordId) {
      return;
    }

    const linkPathOptions = this.buildLinkPathOptions(objectApiName);
    const pageReference = buildRecordNavigationReference(
      recordId,
      objectApiName,
      linkPathOptions
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  handleActionCellClick(event) {
    event.stopPropagation();
  }

  handleMenuSelect(event) {
    event.stopPropagation();
    const rowId = event.currentTarget.dataset.id;
    const name = event.detail.value;
    this.emitRowAction({ action: { name }, row: this.findRow(rowId) });
  }

  handleDetailTaskMenuSelect(event) {
    event.stopPropagation();
    const taskId = event.currentTarget.dataset.id;
    const name = event.detail.value;

    this.emitRowAction({
      action: { name },
      row: {
        id: taskId,
        objectApiName: "Task",
      },
    });
  }
}