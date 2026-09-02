/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 *
 * User-facing notification log grouped by day with AC1-AC5 filters.
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getNotificationLog from "@salesforce/apex/NotificationCenterController.getNotificationLog";
import {
  attachLogRecordUrls
} from "c/recordNavigationUtils";
import {
  DISPLAY_NOT_APPLICABLE,
  ICON,
  LOG_RECORD_TYPE_FILTER_OPTIONS,
  LOG_STATUS_FILTER,
  buildDivFilterOptionClass,
  buildSourceTypeDisplay,
  formatLogDayLabelFromTimestamp,
  groupLogRowsByDay,
  parseSalesforceDatetime,
  reduceError,
  dispatchNotificationCenterViewReady
} from "c/notificationCenterUtils";

const PAGE_SIZE = 50;
const LOG_TABLE_COLUMNS = Object.freeze([
  { label: "Subject", fieldName: "subject" },
  { label: "Type", fieldName: "sourceType" },
  { label: "Change Made", fieldName: "changeMade" },
  { label: "Assigned To", fieldName: "assignedTo" },
  { label: "Change Date", fieldName: "changeDateLabel" },
  { label: "Household", fieldName: "householdLabel" },
  { label: "Branch", fieldName: "branchLabel" },
  { label: "Financial Advisor Team", fieldName: "financialAdvisorTeamLabel" }
]);

const formatIsoDate = (date) => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

const buildDefaultFilters = () => ({
  statusFilter: LOG_STATUS_FILTER.ALL,
  sourceTypeFilter: "ALL",
  subjectSearch: "",
  selectedHouseholdIds: [],
  selectedBranchNames: [],
  startDate: formatIsoDate(new Date()),
  endDate: formatIsoDate(new Date())
});

const mergeFilterOptions = (existingOptions, incomingOptions) => {
  const optionsByValue = new Map();

  (existingOptions || []).forEach((option) => {
    if (option?.value) {
      optionsByValue.set(option.value, option);
    }
  });

  (incomingOptions || []).forEach((option) => {
    if (option?.value) {
      optionsByValue.set(option.value, option);
    }
  });

  return [...optionsByValue.values()].sort((first, second) =>
    String(first.label || "").localeCompare(String(second.label || ""), undefined, {
      sensitivity: "base"
    })
  );
};

const compareLogRowsByChangeDateDesc = (left, right) => {
  const leftTimestamp = left?.changeTimestamp;
  const rightTimestamp = right?.changeTimestamp;

  if (leftTimestamp == null && rightTimestamp == null) {
    return String(right?.id || "").localeCompare(String(left?.id || ""));
  }

  if (leftTimestamp == null) {
    return 1;
  }

  if (rightTimestamp == null) {
    return -1;
  }

  if (leftTimestamp !== rightTimestamp) {
    return rightTimestamp - leftTimestamp;
  }

  return String(right?.id || "").localeCompare(String(left?.id || ""));
};

const groupLogRowsByDayDesc = (rows) => {
  const groups = groupLogRowsByDay(rows);

  groups.forEach((group) => {
    group.rows.sort(compareLogRowsByChangeDateDesc);
  });

  return groups.sort((left, right) => right.dayKey.localeCompare(left.dayKey));
};

export default class NotificationCenterLog extends NavigationMixin(
  LightningElement
) {
  filters = buildDefaultFilters();
  logRows = [];
  dayGroups = [];
  filteredTotalCount = 0;
  hasMore = false;
  isLoading = true;
  isLoadingMore = false;
  errorMessage = "";
  lastSeenId = null;
  icons = ICON;
  hasDispatchedViewReady = false;
  householdOptions = [];
  branchOptions = [];
  _filterReloadTimeout;
  _isDisconnected = false;

  connectedCallback() {
    this.loadLog(true);
  }

  disconnectedCallback() {
    this._isDisconnected = true;
    clearTimeout(this._filterReloadTimeout);
  }

  scheduleFilterReload() {
    clearTimeout(this._filterReloadTimeout);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._filterReloadTimeout = setTimeout(() => {
      if (!this._isDisconnected) {
        this.loadLog(true);
      }
    }, 400);
  }

  get tableColumns() {
    return LOG_TABLE_COLUMNS;
  }

  get tableRows() {
    const rows = [];

    this.dayGroups.forEach((dayGroup) => {
      rows.push({
        id: `day-${dayGroup.id}`,
        isDayHeader: true,
        dayLabel: dayGroup.dayLabel,
        rowClass: "log-table__day-row"
      });

      dayGroup.rows.forEach((row) => {
        rows.push({
          ...row,
          isDayHeader: false,
          rowClass: "div-table__row"
        });
      });
    });

    return rows;
  }

  get columnCount() {
    return LOG_TABLE_COLUMNS.length;
  }

  get recordTypeFilterButtons() {
    return LOG_RECORD_TYPE_FILTER_OPTIONS.map((option) => ({
      ...option,
      cssClass: buildDivFilterOptionClass(
        option.value === this.filters.sourceTypeFilter
      ),
      ariaPressed: String(option.value === this.filters.sourceTypeFilter)
    }));
  }

  get hasRows() {
    return this.dayGroups.length > 0;
  }

  get showInitialViewSkeleton() {
    return this.isLoading && !this.hasDispatchedViewReady;
  }

  get canLoadMore() {
    return this.hasMore && !this.isLoading && !this.isLoadingMore;
  }

  get footerSummary() {
    const visibleCount = this.logRows.length;
    const totalCount = Math.max(this.filteredTotalCount || 0, visibleCount);
    return `Showing ${visibleCount} of ${totalCount} records`;
  }

  get isClearFiltersDisabled() {
    return JSON.stringify(this.filters) === JSON.stringify(buildDefaultFilters());
  }

  @api
  refresh() {
    return this.loadLog(true);
  }

  handleRecordTypeFilter = (event) => {
    this.filters = {
      ...this.filters,
      sourceTypeFilter: event.currentTarget.dataset.filter
    };
    this.loadLog(true);
  };

  handleSubjectSearchChange = (event) => {
    this.filters = {
      ...this.filters,
      subjectSearch: event.target.value || ""
    };
  };

  handleSubjectSearchKeyDown = (event) => {
    if (event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    this.loadLog(true);
  };

  handleHouseholdFilterChange = (event) => {
    this.filters = {
      ...this.filters,
      selectedHouseholdIds: event.detail?.value || []
    };
    this.scheduleFilterReload();
  };

  handleBranchFilterChange = (event) => {
    this.filters = {
      ...this.filters,
      selectedBranchNames: event.detail?.value || []
    };
    this.scheduleFilterReload();
  };

  handleStartDateChange = (event) => {
    const nextStartDate = event.detail.value;
    this.filters = {
      ...this.filters,
      startDate: nextStartDate,
      endDate:
        nextStartDate &&
        this.filters.endDate &&
        nextStartDate > this.filters.endDate
          ? nextStartDate
          : this.filters.endDate
    };
    this.loadLog(true);
  };

  handleEndDateChange = (event) => {
    const nextEndDate = event.detail.value;
    this.filters = {
      ...this.filters,
      endDate: nextEndDate,
      startDate:
        nextEndDate &&
        this.filters.startDate &&
        nextEndDate < this.filters.startDate
          ? nextEndDate
          : this.filters.startDate
    };
    this.loadLog(true);
  };

  handleClearFilters = () => {
    this.filters = buildDefaultFilters();
    this.loadLog(true);
  };

  handleLoadMore = () => {
    this.loadLog(false);
  };

  loadLog = async (reset) => {
    if (reset) {
      this.lastSeenId = null;
      this.isLoading = true;
      this.logRows = [];
      this.dayGroups = [];
    } else {
      this.isLoadingMore = true;
    }

    this.errorMessage = "";

    try {
      const result = await getNotificationLog({
        statusFilter: this.filters.statusFilter,
        categoryFilter: "ALL",
        pageSize: PAGE_SIZE,
        lastSeenId: reset ? null : this.lastSeenId,
        startDate: this.filters.startDate || null,
        endDate: this.filters.endDate || null,
        searchTerm: this.filters.subjectSearch?.trim() || null,
        sourceTypeFilter: this.filters.sourceTypeFilter,
        selectedHouseholdIds: this.filters.selectedHouseholdIds,
        selectedBranchNames: this.filters.selectedBranchNames,
        presentationMode: true
      });

      const itemsWithUrls = await attachLogRecordUrls(this, result?.items || []);
      const incomingItems = itemsWithUrls.map((item) => this.decorateRow(item));

      if (reset || result?.filteredTotalCount != null) {
        this.filteredTotalCount = result?.filteredTotalCount ?? 0;
      }

      if (reset) {
        this.householdOptions = result?.householdOptions || [];
        this.branchOptions = result?.branchOptions || [];
      } else {
        this.householdOptions = mergeFilterOptions(
          this.householdOptions,
          result?.householdOptions
        );
        this.branchOptions = mergeFilterOptions(
          this.branchOptions,
          result?.branchOptions
        );
      }

      this.hasMore = result?.hasMore === true;
      this.logRows = reset ? incomingItems : [...this.logRows, ...incomingItems];
      this.logRows.sort(compareLogRowsByChangeDateDesc);
      this.dayGroups = groupLogRowsByDayDesc(this.logRows);
      this.lastSeenId = result?.nextLastSeenId ?? null;
    } catch (error) {
      this.errorMessage = reduceError(error);
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;

      if (reset) {
        this.dispatchViewReadyOnce();
      }
    }
  };

  dispatchViewReadyOnce() {
    if (this.hasDispatchedViewReady) {
      return;
    }

    this.hasDispatchedViewReady = true;
    dispatchNotificationCenterViewReady(this);
  }

  decorateRow(item) {
    const changeTimestamp = parseSalesforceDatetime(
      item.changeDate || item.eventAt
    );
    const changeDayKey = this.buildChangeDayKey(changeTimestamp);
    const sourceTypeDisplay = buildSourceTypeDisplay(item.sourceType);

    return {
      ...item,
      changeTimestamp,
      changeDayKey,
      changeDayLabel: formatLogDayLabelFromTimestamp(changeTimestamp),
      subjectLabel: item.subject || item.title || DISPLAY_NOT_APPLICABLE,
      sourceTypeLabel: sourceTypeDisplay.label,
      changeMadeLabel: item.changeMade || DISPLAY_NOT_APPLICABLE,
      assignedToLabel: item.assignedTo || DISPLAY_NOT_APPLICABLE,
      householdLabel: item.householdName || DISPLAY_NOT_APPLICABLE,
      branchLabel: item.branchName || DISPLAY_NOT_APPLICABLE,
      branchLinkAriaLabel: item.branchName
        ? `Open branch: ${item.branchName}`
        : "Open branch",
      householdLinkAriaLabel: item.householdName
        ? `Open household: ${item.householdName}`
        : "Open household",
      financialAdvisorTeamLabel:
        item.financialAdvisorTeamName || DISPLAY_NOT_APPLICABLE,
      financialAdvisorTeamLinkAriaLabel: item.financialAdvisorTeamName
        ? `Open financial advisor team: ${item.financialAdvisorTeamName}`
        : "Open financial advisor team",
      subjectLinkAriaLabel: item.subject || item.title
        ? `Open ${item.sourceType || "record"}: ${item.subject || item.title}`
        : "Open source record"
    };
  }

  buildChangeDayKey(timestamp) {
    if (timestamp === null || timestamp === undefined) {
      return "unknown";
    }

    const eventDate = new Date(timestamp);
    const year = eventDate.getFullYear();
    const month = String(eventDate.getMonth() + 1).padStart(2, "0");
    const day = String(eventDate.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }
}