/**
 * Cases tab content for arcHouseholdDetail: every Case linked to this
 * Account/Household/Business/Trust/Retirement Plan (directly or through its
 * household -- see ArcAccountCasesController), same 8-column shape as the
 * standardized "All Cases" list. Self-contained, embedded only -- resolves
 * its own recordId the same way arcAccountRelationships does.
 *
 * Real server-side pagination (ArcAccountCasesController.getCasesForAccount
 * takes offset/pageSize) rather than a capped fetch: unlike Investments &
 * Services, a household's case history can genuinely run long. Rows already
 * fetched accumulate client-side; arcDataTable's own pager pages over that
 * growing list and fires `loadmore` only once the user reaches its edge.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { resolveRecordIdFromPageReference } from "c/recordNavigationCommunityUtils";
import getCasesForAccount from "@salesforce/apex/ArcAccountCasesController.getCasesForAccount";

const OBJECT_API_NAME = "Account";
const PAGE_SIZE = 25;

/** Same field set/order/labels as Case_List's standardized viewTabs columns. */
const COLUMNS = [
  {
    label: "Case Number",
    fieldName: "caseNumber",
    type: "text",
    sortable: true,
    sortType: "text",
    isLink: true,
    linkObjectApiName: "Case"
  },
  { label: "Case", fieldName: "caseName", type: "text", sortable: true, sortType: "text" },
  {
    label: "Assignee | Current Task Subject",
    fieldName: "currentTaskSubjectAssignee",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Case Overall Status",
    fieldName: "overallStatus",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  { label: "Milestone", fieldName: "milestone", type: "text", sortable: true, sortType: "text" },
  { label: "Case Owner", fieldName: "ownerName", type: "text", sortable: true, sortType: "text" },
  {
    label: "Date/Time Opened",
    fieldName: "createdDate",
    type: "datetime",
    sortable: true,
    sortType: "date"
  },
  {
    label: "Financial Advisor Team",
    fieldName: "financialAdvisorTeamName",
    type: "text",
    sortable: true,
    sortType: "text"
  }
];

const mapRow = (row) => ({
  id: row.id,
  objectApiName: "Case",
  caseNumber: row.caseNumber,
  caseName: row.caseName,
  currentTaskSubjectAssignee: row.currentTaskSubjectAssignee,
  overallStatus: row.overallStatus,
  milestone: row.milestone,
  ownerName: row.ownerName,
  createdDate: row.createdDate,
  financialAdvisorTeamName: row.financialAdvisorTeamName
});

export default class ArcAccountCasesList extends LightningElement {
  columns = COLUMNS;
  pageSize = PAGE_SIZE;
  rows = [];
  hasMoreRows = false;
  isLoading = true;
  isLoadingMore = false;
  errorMessage = "";

  recordId;
  _loadedOffset = 0;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const next = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
    if (next && next !== this.recordId) {
      this.recordId = next;
      this.resetAndLoad();
    }
  }

  resetAndLoad() {
    this.rows = [];
    this._loadedOffset = 0;
    this.hasMoreRows = false;
    this.errorMessage = "";
    this.isLoading = true;
    this.fetchPage(0);
  }

  fetchPage(offsetValue) {
    getCasesForAccount({
      accountId: this.recordId,
      offsetValue,
      pageSize: this.pageSize
    })
      .then((page) => {
        const newRows = (page?.rows || []).map(mapRow);
        this.rows = [...this.rows, ...newRows];
        this.hasMoreRows = Boolean(page?.hasMore);
        this._loadedOffset = offsetValue + newRows.length;
        this.errorMessage = "";
      })
      .catch((error) => {
        this.errorMessage = error?.body?.message || "Unable to load cases.";
      })
      .finally(() => {
        this.isLoading = false;
        this.isLoadingMore = false;
      });
  }

  handleLoadMore() {
    if (this.isLoadingMore || !this.hasMoreRows) {
      return;
    }
    this.isLoadingMore = true;
    this.fetchPage(this._loadedOffset);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.errorMessage && !this.hasRows;
  }
}