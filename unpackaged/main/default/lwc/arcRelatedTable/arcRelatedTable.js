/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, api, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getTableData from "@salesforce/apex/ArcRelatedTableController.getTableData";
import { SORT_DESC } from "c/dataTableSortUtils";

const OBJECT_ENVELOPE = "Envelope";
const OBJECT_WORK = "Work";
const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" }
];

const PAGE_SIZE_DEFAULT = 10;
const PAGE_SIZE_OPTIONS = [10, 25, 50];

const ENVELOPE_COLUMNS = [
  {
    key: "name",
    label: "Envelope Name",
    fieldName: "name",
    isLink: true,
    sortable: true,
    sortType: "text"
  },
  {
    key: "household",
    label: "Household",
    fieldName: "household",
    sortable: true,
    sortType: "text"
  },
  {
    key: "advisorTeam",
    label: "Advisor Team",
    fieldName: "advisorTeam",
    sortable: true,
    sortType: "text"
  },
  {
    key: "status",
    label: "Status",
    fieldName: "status",
    sortable: true,
    sortType: "text"
  },
  {
    key: "lastModified",
    label: "Last Activity",
    fieldName: "lastModified",
    sortFieldName: "lastModifiedRaw",
    sortable: true,
    sortType: "date"
  }
];

const WORK_COLUMNS = [
  {
    key: "recordType",
    label: "Type",
    fieldName: "recordType",
    sortable: true,
    sortType: "text"
  },
  {
    key: "subject",
    label: "Subject",
    fieldName: "subject",
    isLink: true,
    sortable: true,
    sortType: "text"
  },
  {
    key: "status",
    label: "Status",
    fieldName: "status",
    sortable: true,
    sortType: "text"
  },
  {
    key: "mainTrackTasks",
    label: "Main Track Tasks",
    fieldName: "mainTrackTasks",
    sortFieldName: "completedMainTrack",
    sortable: true,
    sortType: "number",
    cellClass: "div-table__cell--numeric"
  },
  {
    key: "ownerName",
    label: "Owner",
    fieldName: "ownerName",
    sortable: true,
    sortType: "text"
  },
  {
    key: "activityDate",
    label: "Due / Activity",
    fieldName: "activityDate",
    sortFieldName: "activityDateRaw",
    sortable: true,
    sortType: "date"
  },
  {
    key: "relatedTo",
    label: "Related To",
    fieldName: "relatedTo",
    sortable: true,
    sortType: "text"
  }
];

export default class ArcRelatedTable extends LightningElement {
  @api defaultObjectType = OBJECT_ENVELOPE;

  objectType = OBJECT_ENVELOPE;
  scope = SCOPE_MY;
  searchTerm = "";
  sourceRows = [];
  errorMessage = "";
  isLoading = true;
  pageSize = PAGE_SIZE_DEFAULT;
  _stylesLoaded = false;

  connectedCallback() {
    this.objectType = this.normalizeObjectType(this.defaultObjectType);
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch((error) => {
        // eslint-disable-next-line no-console
        console.error(
          "[arcRelatedTable] Failed to load diversifyStyles",
          error
        );
      });
    }
  }

  @wire(getTableData, { objectType: "$objectType", scope: "$scope" })
  wiredTableData({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.sourceRows = data.rows || [];
      this.errorMessage = "";
    } else if (error) {
      this.sourceRows = [];
      this.errorMessage = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[arcRelatedTable] Failed to load table data", error);
    }
  }

  get title() {
    return this.objectType === OBJECT_WORK ? "Work" : "Envelopes";
  }

  get scopeOptions() {
    return SCOPE_OPTIONS;
  }

  get columns() {
    return this.objectType === OBJECT_WORK ? WORK_COLUMNS : ENVELOPE_COLUMNS;
  }

  get defaultSortField() {
    return this.objectType === OBJECT_WORK ? "activityDate" : "lastModified";
  }

  get defaultSortDirection() {
    return SORT_DESC;
  }

  get pageSizeOptions() {
    return PAGE_SIZE_OPTIONS;
  }

  get filteredRows() {
    const term = this.searchTerm.trim().toLowerCase();

    return (this.sourceRows || []).filter((row) => {
      if (!term) {
        return true;
      }

      const haystack = [
        row.name,
        row.subject,
        row.household,
        row.advisorTeam,
        row.status,
        row.ownerName,
        row.relatedTo,
        row.recordType,
        row.mainTrackTasks
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return haystack.includes(term);
    });
  }

  get tableRows() {
    return this.filteredRows.map((row) => ({
      ...row,
      objectApiName: this.resolveObjectApiName(row)
    }));
  }

  get hasRows() {
    return this.filteredRows.length > 0;
  }

  handleSearchChange(event) {
    this.searchTerm = event.detail?.value ?? event.target?.value ?? "";
  }

  handleScopeChange(event) {
    this.setScope(event.detail.value);
  }

  resolveObjectApiName(row) {
    if (this.objectType === OBJECT_ENVELOPE) {
      return "Envelope__c";
    }

    return row.recordType === "Case" ? "Case" : "Task";
  }

  setScope(nextScope) {
    if (nextScope === this.scope) {
      return;
    }

    this.scope = nextScope;
    this.isLoading = true;
  }

  normalizeObjectType(value) {
    return value === OBJECT_WORK ? OBJECT_WORK : OBJECT_ENVELOPE;
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((entry) => entry.message).join(", ");
    }

    if (typeof error?.body?.message === "string") {
      return error.body.message;
    }

    return "Unable to load records.";
  }
}