/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import {
  SORT_ASC,
  SORT_DESC,
  compareValues,
  resolveSortDirection
} from "c/dataTableSortUtils";
import getNotificationLog from "@salesforce/apex/NotificationCenterController.getNotificationLog";
import {
  attachLogRecordUrls,
  openRecordInNewTab
} from "c/recordNavigationUtils";
import {
  deriveChangeType,
  getChannelBadge,
  getLogStatusStyle,
  buildDivFilterOptionClass,
  ICON,
  isVisibleChannel,
  reduceError,
  STATUS,
  STATUS_FILTER_OPTIONS,
  dispatchNotificationCenterViewReady
} from "c/notificationCenterUtils";

const PAGE_SIZE = 50;
const AUTO_REFRESH_MS = 30000;
const DEFAULT_SORT_FIELD = "sortTimestamp";
const DEFAULT_SORT_DIRECTION = SORT_DESC;

const LOG_TABLE_COLUMNS = Object.freeze([
  {
    label: "",
    fieldName: "expand",
    type: "text",
    sortable: false
  },
  {
    label: "Timestamp",
    fieldName: DEFAULT_SORT_FIELD,
    type: "number",
    sortable: true
  },
  {
    label: "Household",
    fieldName: "householdLabel",
    type: "text",
    sortable: true
  },
  {
    label: "Record Change",
    fieldName: "sourceType",
    type: "text",
    sortable: true
  },
  {
    label: "Mode / Channel",
    fieldName: "frequency",
    type: "text",
    sortable: true
  },
  { label: "Status", fieldName: "status", type: "text", sortable: true }
]);

const formatIsoDate = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export default class NotificationCenterLogAdmin extends NavigationMixin(LightningElement) {
  statusFilter = "ALL";
  startDate = formatIsoDate(new Date());
  endDate = formatIsoDate(new Date());
  logRows = [];
  sortedLogRows = [];
  sortedBy = DEFAULT_SORT_FIELD;
  sortedDirection = DEFAULT_SORT_DIRECTION;
  filteredTotalCount = 0;
  hasMore = false;
  isLoading = true;
  isRefreshing = false;
  isLoadingMore = false;
  errorMessage = "";
  lastSeenId = null;
  autoRefreshTimerId = null;
  expandedLogRowIds = new Set();
  icons = ICON;
  hasDispatchedViewReady = false;

  connectedCallback() {
    this.loadLog(true);
    this.startAutoRefresh();
  }

  disconnectedCallback() {
    this.clearAutoRefresh();
  }

  get statusFilterButtons() {
    return STATUS_FILTER_OPTIONS.map((filter) => ({
      ...filter,
      cssClass: buildDivFilterOptionClass(filter.value === this.statusFilter),
      ariaPressed: String(filter.value === this.statusFilter)
    }));
  }

  get hasRows() {
    return this.sortedLogRows.length > 0;
  }

  get tableHeaderColumns() {
    return LOG_TABLE_COLUMNS.map((column) => {
      if (!column.sortable) {
        return {
          ...column,
          ariaSort: "none",
          isSortable: false
        };
      }

      const isActive = this.sortedBy === column.fieldName;

      return {
        ...column,
        isSortable: true,
        ariaSort: isActive
          ? this.sortedDirection === SORT_ASC
            ? "ascending"
            : "descending"
          : "none",
        sortIcon: isActive
          ? this.sortedDirection === SORT_ASC
            ? "utility:arrowup"
            : "utility:arrowdown"
          : "utility:arrowdown",
        sortIconClass: isActive
          ? "div-table__sort-icon div-table__sort-icon--active"
          : "div-table__sort-icon"
      };
    });
  }

  get tableRows() {
    const rows = [];

    this.sortedLogRows.forEach((row) => {
      const isExpanded = this.expandedLogRowIds.has(row.id);

      rows.push({
        ...row,
        isExpanded,
        detailRowFlag: "false",
        expandIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
        expandAriaLabel: isExpanded
          ? "Collapse notification details"
          : "Expand notification details",
        rowClass: isExpanded
          ? "div-table__row div-table__row--expanded"
          : "div-table__row div-table__row--expandable",
        rowTabIndex: "0",
        ariaExpanded: String(isExpanded),
        isDetailRow: false
      });

      if (isExpanded) {
        rows.push({
          id: `${row.id}-detail`,
          isDetailRow: true,
          detailRowFlag: "true",
          changeContext: row.changeContext,
          hasChangeContext: row.hasChangeContext,
          rowClass: "div-table__detail-row",
          rowTabIndex: "-1",
          ariaExpanded: "false"
        });
      }
    });

    return rows;
  }

  get detailColumnSpan() {
    return LOG_TABLE_COLUMNS.length;
  }

  get footerSummary() {
    const visibleCount = this.sortedLogRows.length;
    const totalCount = this.filteredTotalCount || visibleCount;
    return `Showing ${visibleCount} of ${totalCount} records`;
  }

  get canLoadMore() {
    return (
      this.hasMore &&
      this.sortedBy === DEFAULT_SORT_FIELD &&
      this.sortedDirection === DEFAULT_SORT_DIRECTION
    );
  }

  get isRefreshDisabled() {
    return this.isLoading || this.isRefreshing || this.isLoadingMore;
  }

  get refreshButtonLabel() {
    return this.isRefreshing ? "Refreshing..." : "Refresh";
  }

  get autoRefreshSeconds() {
    return AUTO_REFRESH_MS / 1000;
  }

  get autoRefreshLabel() {
    return `Auto-refreshes every ${this.autoRefreshSeconds}s`;
  }

  get autoRefreshTitle() {
    return `Refresh notification log. Auto-refreshes every ${this.autoRefreshSeconds} seconds.`;
  }

  @api
  refresh() {
    return this.loadLog(true, { silent: true });
  }

  handleRefresh = () => {
    this.loadLog(true, { isManualRefresh: true });
  };

  startAutoRefresh = () => {
    this.clearAutoRefresh();
    this.autoRefreshTimerId = setInterval(() => {
      if (this.isLoading || this.isRefreshing || this.isLoadingMore) {
        return;
      }

      this.loadLog(true, { silent: true });
    }, AUTO_REFRESH_MS);
  };

  clearAutoRefresh = () => {
    if (!this.autoRefreshTimerId) {
      return;
    }

    clearInterval(this.autoRefreshTimerId);
    this.autoRefreshTimerId = null;
  };

  handleStatusFilter = (event) => {
    this.statusFilter = event.currentTarget.dataset.filter;
    this.loadLog(true);
  };

  handleStartDateChange = (event) => {
    this.startDate = event.detail.value;

    if (this.startDate && this.endDate && this.startDate > this.endDate) {
      this.endDate = this.startDate;
    }

    this.loadLog(true);
  };

  handleEndDateChange = (event) => {
    this.endDate = event.detail.value;

    if (this.startDate && this.endDate && this.endDate < this.startDate) {
      this.startDate = this.endDate;
    }

    this.loadLog(true);
  };

  handleLoadMore = () => {
    this.loadLog(false);
  };

  handleRecordNavigate = (event) => {
    event.stopPropagation();
    openRecordInNewTab(this, event.currentTarget.dataset.recordId);
  };

  handleRecordNavigateKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.handleRecordNavigate(event);
  };

  handleRowToggle = (event) => {
    if (event.target.closest(".div-table__expand-button")) {
      return;
    }

    if (event.currentTarget.dataset.detailRow === "true") {
      return;
    }

    this.toggleRowExpand(event.currentTarget.dataset.rowId);
  };

  handleRowToggleKeyDown = (event) => {
    if (event.currentTarget.dataset.detailRow === "true") {
      return;
    }

    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.toggleRowExpand(event.currentTarget.dataset.rowId);
  };

  handleToggleRowExpand = (event) => {
    event.stopPropagation();
    this.toggleRowExpand(event.currentTarget.dataset.rowId);
  };

  toggleRowExpand(rowId) {
    if (!rowId) {
      return;
    }

    const nextExpandedRowIds = new Set(this.expandedLogRowIds);
    if (nextExpandedRowIds.has(rowId)) {
      nextExpandedRowIds.delete(rowId);
    } else {
      nextExpandedRowIds.add(rowId);
    }

    this.expandedLogRowIds = nextExpandedRowIds;
  }

  handleToggleRowExpandKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleToggleRowExpand(event);
  };

  handleColumnSort = (event) => {
    const fieldName = event.currentTarget.dataset.field;

    if (!fieldName) {
      return;
    }

    this.sortedDirection = resolveSortDirection(
      fieldName,
      this.sortedBy,
      this.sortedDirection
    );
    this.sortedBy = fieldName;
    this.applyLogSort();
  };

  handleColumnSortKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleColumnSort(event);
  };

  loadLog = async (reset, options = {}) => {
    const { silent = false, isManualRefresh = false } = options;
    const hasExistingRows = this.logRows.length > 0;
    const keepVisibleRows = silent || (isManualRefresh && hasExistingRows);

    if (reset) {
      this.lastSeenId = null;

      if (keepVisibleRows) {
        this.isRefreshing = true;
      } else {
        this.isLoading = true;
        this.logRows = [];
        this.sortedLogRows = [];
        this.resetDefaultSort();
      }
    } else {
      this.isLoadingMore = true;
    }

    this.errorMessage = "";

    try {
      const result = await getNotificationLog({
        statusFilter: this.statusFilter,
        categoryFilter: "ALL",
        pageSize: PAGE_SIZE,
        lastSeenId: reset ? null : this.lastSeenId,
        startDate: this.startDate || null,
        endDate: this.endDate || null,
        searchTerm: null,
        sourceTypeFilter: "ALL",
        selectedHouseholdIds: [],
        selectedBranchNames: [],
        presentationMode: false
      });

      const itemsWithUrls = await attachLogRecordUrls(this, result?.items || []);
      const incomingItems = itemsWithUrls.map((item) => this.decorateRow(item));
      this.filteredTotalCount = result?.filteredTotalCount || 0;
      this.hasMore = result?.hasMore === true;
      this.logRows = reset ? incomingItems : [...this.logRows, ...incomingItems];
      this.applyLogSort();
      this.updatePaginationCursor();
    } catch (error) {
      this.errorMessage = reduceError(error);
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
      this.dispatchViewReadyOnce();
    }
  };

  dispatchViewReadyOnce() {
    if (this.hasDispatchedViewReady) {
      return;
    }

    this.hasDispatchedViewReady = true;
    dispatchNotificationCenterViewReady(this);
  }

  applyLogSort() {
    if (!this.sortedBy) {
      this.sortedLogRows = [...this.logRows];
      return;
    }

    const columnType =
      LOG_TABLE_COLUMNS.find((column) => column.fieldName === this.sortedBy)?.type ||
      "text";
    const directionMultiplier = this.sortedDirection === SORT_DESC ? -1 : 1;

    this.sortedLogRows = [...this.logRows].sort((first, second) => {
      const primaryCompare =
        compareValues(first[this.sortedBy], second[this.sortedBy], columnType) *
        directionMultiplier;

      if (primaryCompare !== 0) {
        return primaryCompare;
      }

      if (first.id === second.id) {
        return 0;
      }

      return first.id < second.id ? -1 * directionMultiplier : directionMultiplier;
    });
  }

  resetDefaultSort() {
    this.sortedBy = DEFAULT_SORT_FIELD;
    this.sortedDirection = DEFAULT_SORT_DIRECTION;
  }

  updatePaginationCursor() {
    if (!this.canLoadMore || this.logRows.length === 0) {
      return;
    }

    const oldestRow = this.logRows.reduce((oldest, row) => {
      if (!oldest) {
        return row;
      }

      const rowTimestamp = row.sortTimestamp ?? Number.NEGATIVE_INFINITY;
      const oldestTimestamp = oldest.sortTimestamp ?? Number.NEGATIVE_INFINITY;

      if (rowTimestamp !== oldestTimestamp) {
        return rowTimestamp < oldestTimestamp ? row : oldest;
      }

      return row.id < oldest.id ? row : oldest;
    }, null);

    this.lastSeenId = oldestRow?.id ?? null;
  }

  resolveSortTimestamp(value) {
    if (value === null || value === undefined || value === "") {
      return null;
    }

    if (typeof value === "number") {
      return Number.isNaN(value) ? null : value;
    }

    const normalizedValue = String(value)
      .replace(/\+0000$/, "Z")
      .replace(/(\.\d{3})\+00:00$/, "$1Z");

    const timestamp = Date.parse(normalizedValue);
    return Number.isNaN(timestamp) ? null : timestamp;
  }

  decorateRow(item) {
    const statusStyle = getLogStatusStyle(item.status);
    const showChannelPill = isVisibleChannel(item.channel);
    const channelBadge = showChannelPill ? getChannelBadge(item.channel) : null;
    const hasChangeContext = Boolean(item.changeContext?.trim());

    const changeTypeLabel = deriveChangeType(item.title, item.changeContext);
    const sourceLinkLabel = this.buildSourceLinkLabel(item.sourceType, changeTypeLabel);

    return {
      ...item,
      hasChangeContext,
      changeContext: item.changeContext || "",
      sortTimestamp: this.resolveSortTimestamp(item.eventAt),
      timestampLabel: this.formatTimestamp(item.eventAt),
      householdLabel: item.householdName || "Unknown household",
      sourceLinkAriaLabel: sourceLinkLabel
        ? `Open source record: ${sourceLinkLabel}`
        : "Open source record",
      changeTypeLabel,
      showChannelPill,
      channelPillLabel: channelBadge?.label || "",
      channelPillClass: channelBadge?.cssClass || "",
      statusLabel: statusStyle.label,
      statusIcon: statusStyle.icon,
      statusIconClass: statusStyle.iconClass,
      recordLabel: this.buildRecordLabel(item),
      hasLogRecordLink: Boolean(item.id && item.notificationNumber),
      logRecordLinkAriaLabel: item.notificationNumber
        ? `Open notification log record ${item.notificationNumber}`
        : "Open notification log record",
      statusNote: this.buildStatusNote(item)
    };
  }

  buildRecordLabel(item) {
    return item.notificationNumber || "";
  }

  buildSourceLinkLabel(sourceType, changeTypeLabel) {
    if (!sourceType) {
      return changeTypeLabel || "View record";
    }

    if (!changeTypeLabel) {
      return sourceType;
    }

    return `${sourceType} · ${changeTypeLabel}`;
  }

  buildStatusNote(item) {
    if (item.status === STATUS.FAILED) {
      return item.errorMessage || item.suppressionReason || "Delivery failed";
    }

    if (item.status === STATUS.PENDING) {
      return "Awaiting delivery";
    }

    return "";
  }

  formatTimestamp(value) {
    if (!value) {
      return "";
    }

    const eventDate = new Date(value);
    const now = new Date();
    const timeLabel = eventDate.toLocaleTimeString([], {
      hour: "numeric",
      minute: "2-digit"
    });

    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfEventDay = new Date(
      eventDate.getFullYear(),
      eventDate.getMonth(),
      eventDate.getDate()
    );
    const dayDiff = Math.round(
      (startOfToday.getTime() - startOfEventDay.getTime()) / 86400000
    );

    if (dayDiff === 0) {
      return `Today ${timeLabel}`;
    }

    if (dayDiff === 1) {
      return `Yesterday ${timeLabel}`;
    }

    return `${eventDate.toLocaleDateString([], {
      month: "short",
      day: "numeric"
    })}, ${timeLabel}`;
  }
}