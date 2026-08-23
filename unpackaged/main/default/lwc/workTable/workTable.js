/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Work Case list with My / My Team scope, status pills, and expandable task detail.
 */
import { LightningElement, api, wire, track } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import { NavigationMixin } from "lightning/navigation";
import getWorkData from "@salesforce/apex/WorkDatatableController.getWorkData";
import {
  buildRecordNavigationReference,
  openRecordInNewTab,
  resolveRecordUrl
} from "c/recordNavigationUtils";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import envelopeWizardStyles from "@salesforce/resourceUrl/envelopeWizardStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import { SORT_DESC } from "c/dataTableSortUtils";

const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" }
];

const COLUMNS = [
  {
    label: "Case",
    fieldName: "caseName",
    type: "text",
    sortable: true,
    sortType: "text",
    isLink: true,
    showExpandChevron: true
  },
  {
    label: "Case No.",
    fieldName: "caseNumber",
    type: "text",
    sortable: true,
    sortType: "text",
    isLink: true,
    linkObjectApiName: "Case"
  },
  {
    label: "Current Task Subject",
    fieldName: "currentTaskSubject",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Assignee",
    fieldName: "assigneeName",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Overall Status",
    fieldName: "overallStatus",
    type: "pill",
    pillClassField: "overallStatusPillClass",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Milestone",
    fieldName: "milestoneStatus",
    type: "pill",
    pillClassField: "milestoneStatusPillClass",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Main Track Tasks",
    fieldName: "mainTrackTasks",
    type: "text",
    sortable: true,
    sortFieldName: "completedMainTrack",
    sortType: "number"
  }
];

const DEFAULT_PAGE_SIZE = 10;
const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50];

export default class WorkTable extends NavigationMixin(LightningElement) {
  @api title = "Work";

  // Dashboard-preview mode: hides the pager UI (still caps rows to
  // pageSize) and shows a "Showing X of Y" + "View All" footer instead.
  _showViewAllFooter = false;
  @api
  get showViewAllFooter() {
    return this._showViewAllFooter;
  }
  set showViewAllFooter(value) {
    this._showViewAllFooter = value !== false && value !== "false";
  }

  @api viewAllUrl = "";

  // Not wired to real filter criteria yet — Figma shows the button with no
  // filter panel spec; placeholder until there's a real filter UI to build.
  _showFilterButton = false;
  @api
  get showFilterButton() {
    return this._showFilterButton;
  }
  set showFilterButton(value) {
    this._showFilterButton = value !== false && value !== "false";
  }

  get filterIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/funnel-simple.svg');`;
  }

  _enableSearch = true;
  @api
  get enableSearch() {
    return this._enableSearch;
  }
  set enableSearch(value) {
    this._enableSearch = value !== false && value !== "false";
  }

  @api searchPlaceholder = "Search work...";

  _enablePagination = true;
  @api
  get enablePagination() {
    return this._enablePagination;
  }
  set enablePagination(value) {
    this._enablePagination = value !== false && value !== "false";
  }

  @api pageSize = DEFAULT_PAGE_SIZE;

  pageSizeOptions = DEFAULT_PAGE_SIZE_OPTIONS;
  enableRowClick = true;

  scopeFilter = SCOPE_MY;
  showFilterMenu = false;
  /** Column and contains-value behind the Filter popover. */
  filterField = "";
  filterValue = "";
  scopeOptions = SCOPE_OPTIONS;
  @track columns = [...COLUMNS];

  /* The same three the list pages offer, so a row behaves the same wherever it
     is shown. Rows here are Cases. */
  rowActions = [
    { name: "edit", label: "Edit", iconName: "utility:edit" },
    { name: "newtab", label: "Open in new tab", iconName: "utility:new_window" },
    { name: "copy", label: "Copy link", iconName: "utility:copy_to_clipboard" }
  ];

  async handleRowAction(event) {
    const { action, row } = event.detail || {};
    const recordId = row?.id;
    if (!action?.name || !recordId) {
      return;
    }

    if (action.name === "newtab") {
      await openRecordInNewTab(this, recordId, "Case");
      return;
    }

    if (action.name === "copy") {
      try {
        const url = await resolveRecordUrl(this, recordId, "Case");
        await navigator.clipboard.writeText(
          new URL(url, window.location.origin).href
        );
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("[workTable] Could not copy the record link", error);
      }
      return;
    }

    // Edit — records are edited inline on their detail page.
    const reference = buildRecordNavigationReference(recordId, "Case");
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  /**
   * Applies a header drag. styledDataTable reports the new field order and
   * leaves rendering it to the host, the same contract nexSListView honours.
   */
  handleColumnReorder(event) {
    const order = event.detail?.columns;
    if (!Array.isArray(order) || !order.length) {
      return;
    }
    const byName = new Map(this.columns.map((col) => [col.fieldName, col]));
    const next = order.map((name) => byName.get(name)).filter(Boolean);
    const missing = this.columns.filter((col) => !order.includes(col.fieldName));
    this.columns = [...next, ...missing];
  }
  defaultSortField = "lastModifiedRaw";
  defaultSortDirection = SORT_DESC;

  searchTerm = "";
  sourceCases = [];
  @track expandedCaseIds = [];
  errorMessage = "";
  isLoading = true;

  _stylesLoaded = false;

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      Promise.all([
        loadStyle(this, diversifyStyles),
        loadStyle(this, envelopeWizardStyles)
      ]).catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[workTable] Failed to load styles", error);
      });
    }
  }

  @wire(getWorkData, { scope: "$wireScope" })
  wiredWorkData({ data, error }) {
    this.isLoading = false;

    if (data) {
      this.sourceCases = data.cases || [];
      this.errorMessage = "";
      this.pruneExpandedCaseIds();
      return;
    }

    if (error) {
      this.sourceCases = [];
      this.expandedCaseIds = [];
      this.errorMessage = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[workTable] Failed to load work data", error);
    }
  }

  get wireScope() {
    return this.scopeFilter === SCOPE_MY ? "My" : "Team";
  }

  get filteredCases() {
    const term = this.searchTerm.trim().toLowerCase();

    return (this.sourceCases || []).filter((caseRow) => {
      if (!term) {
        return true;
      }

      const haystack = [
        caseRow.caseName,
        caseRow.caseNumber,
        caseRow.currentTaskSubject,
        caseRow.assigneeName,
        caseRow.overallStatus,
        caseRow.milestoneStatus
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return haystack.includes(term);
    });
  }

  /**
   * Applied after the search filter so the popover narrows what is already on
   * screen, the way a list view's chips do.
   */
  filterByChip(rows) {
    const term = this.filterValue.trim().toLowerCase();
    if (!this.filterField || !term) {
      return rows;
    }
    return rows.filter((row) =>
      String(row[this.filterField] ?? "")
        .toLowerCase()
        .includes(term)
    );
  }

  get tableRows() {
    return this.filterByChip(this.filteredCases).map((caseRow) => ({
      ...caseRow,
      objectApiName: "Case",
      linkObjectApiName: "Case"
    }));
  }

  get hasCases() {
    return this.tableRows.length > 0;
  }

  get totalCount() {
    return this.sourceCases.length;
  }

  handleScopeChange(event) {
    this.scopeFilter = event.detail?.value ?? SCOPE_MY;
    this.expandedCaseIds = [];
  }

  handleSearchChange(event) {
    this.searchTerm = event.detail?.value ?? event.target?.value ?? "";
    this.pruneExpandedCaseIds();
  }

  handleRowClick(event) {
    const caseId = event.detail?.row?.id;
    if (!caseId) {
      return;
    }

    if (this.expandedCaseIds.includes(caseId)) {
      this.expandedCaseIds = this.expandedCaseIds.filter((id) => id !== caseId);
      return;
    }

    this.expandedCaseIds = [...this.expandedCaseIds, caseId];
  }

  /**
   * Opens the filter popover. This was a no-op placeholder, so the button did
   * nothing at all. It now matches the list views: pick a column, type a value,
   * apply — filtering the rows already on screen, alongside search and scope.
   */
  handleFilterClick() {
    this.showFilterMenu = !this.showFilterMenu;
  }

  get filterFieldOptions() {
    return COLUMNS.filter((col) => col.fieldName).map((col) => ({
      label: col.label,
      value: col.fieldName,
      selected: col.fieldName === this.filterField
    }));
  }

  get filterFieldLabel() {
    return (
      COLUMNS.find((col) => col.fieldName === this.filterField)?.label || ""
    );
  }

  handleFilterFieldChange(event) {
    this.filterField = event.target.value;
  }

  handleFilterValueChange(event) {
    this.filterValue = event.target.value;
  }

  handleFilterApply() {
    this.showFilterMenu = false;
  }

  handleFilterClear() {
    this.filterField = "";
    this.filterValue = "";
    this.showFilterMenu = false;
  }

  pruneExpandedCaseIds() {
    const visibleIds = new Set(this.tableRows.map((caseRow) => caseRow.id));
    this.expandedCaseIds = this.expandedCaseIds.filter((caseId) =>
      visibleIds.has(caseId)
    );
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((entry) => entry.message).join(", ");
    }

    return (
      error?.body?.message || error?.message || "Failed to load work records."
    );
  }
}