/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Work Case list with My / My Team scope, status pills, and expandable task detail.
 */
import { LightningElement, api, wire, track } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import getWorkData from "@salesforce/apex/WorkDatatableController.getWorkData";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import envelopeWizardStyles from "@salesforce/resourceUrl/envelopeWizardStyles";
import { SORT_DESC } from "c/dataTableSortUtils";

const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" },
];

const COLUMNS = [
  {
    label: "Case",
    fieldName: "caseName",
    type: "text",
    sortable: true,
    sortType: "text",
    isLink: true,
    showExpandChevron: true,
  },
  {
    label: "Case No.",
    fieldName: "caseNumber",
    type: "text",
    sortable: true,
    sortType: "text",
    isLink: true,
    linkObjectApiName: "Case",
  },
  {
    label: "Current Task Subject",
    fieldName: "currentTaskSubject",
    type: "text",
    sortable: true,
    sortType: "text",
  },
  {
    label: "Assignee",
    fieldName: "assigneeName",
    type: "text",
    sortable: true,
    sortType: "text",
  },
  {
    label: "Overall Status",
    fieldName: "overallStatus",
    type: "pill",
    pillClassField: "overallStatusPillClass",
    sortable: true,
    sortType: "text",
  },
  {
    label: "Milestone",
    fieldName: "milestone",
    type: "pill",
    pillClassField: "milestonePillClass",
    sortable: true,
    sortType: "text",
  },
  {
    label: "Main Track Tasks",
    fieldName: "mainTrackTasks",
    type: "text",
    sortable: true,
    sortFieldName: "completedMainTrack",
    sortType: "number",
  },
];

const DEFAULT_PAGE_SIZE = 10;
const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50];

export default class WorkDatatable extends LightningElement {
  @api title = "Work";

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
  scopeOptions = SCOPE_OPTIONS;
  columns = COLUMNS;
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
        loadStyle(this, envelopeWizardStyles),
      ]).catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[workDatatable] Failed to load styles", error);
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
      console.error("[workDatatable] Failed to load work data", error);
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
        caseRow.milestone,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return haystack.includes(term);
    });
  }

  get tableRows() {
    return this.filteredCases.map((caseRow) => ({
      ...caseRow,
      objectApiName: "Case",
      linkObjectApiName: "Case",
    }));
  }

  get hasCases() {
    return this.tableRows.length > 0;
  }

  get totalCount() {
    return this.sourceCases.length;
  }

  get showCustomFooter() {
    return !this.enablePagination;
  }

  get showingSummary() {
    const visible = this.tableRows.length;
    const total = this.totalCount;
    return `Showing ${visible} of ${total}`;
  }

  get showViewAll() {
    return this.enablePagination && this.totalCount > this.pageSize;
  }

  handleScopeChange(event) {
    this.scopeFilter = event.detail?.value ?? SCOPE_MY;
    this.isLoading = true;
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

    return error?.body?.message || error?.message || "Failed to load work records.";
  }
}