import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { publish, MessageContext } from "lightning/messageService";
import CASE_STATUS_UPDATED from "@salesforce/messageChannel/CaseStatusUpdated__c";
import { refreshApex } from "@salesforce/apex";
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import CASE_STATUS_FIELD from "@salesforce/schema/Case.Status";
import {
  resolveRecordIdFromPageReference
} from "c/recordNavigationUtils";
import { buildRecordNavigationReference } from "c/recordNavigationCommunityUtils";
import getCaseDetail from "@salesforce/apex/ArcCaseDetailController.getCaseDetail";
import getCaseTasks from "@salesforce/apex/ArcCaseDetailController.getCaseTasks";
import getRelatedRecordsBatch from "@salesforce/apex/ArcRelatedListController.getRelatedRecordsBatch";
import getCaseFieldSections from "@salesforce/apex/ArcCaseDetailController.getCaseFieldSections";
import getCaseInformationFieldNames from "@salesforce/apex/ArcCaseDetailController.getCaseInformationFieldNames";
import getRelatedHouseholdCases from "@salesforce/apex/ArcCaseDetailController.getRelatedHouseholdCases";

// The right rail's 7 c-arc-related-list cards, batched into one Apex call
// instead of each card independently fetching its own (7 round trips ->
// 1). Field paths mirror each card's own `columns` attribute in the
// template exactly -- keep the two in sync if a card's columns change.
const TASK_COLUMNS = [
  {
    label: "Subject",
    fieldName: "subject",
    isLink: true,
    linkObjectApiName: "Task"
  },
  { label: "Status", fieldName: "status" },
  { label: "Owner", fieldName: "ownerName" },
  { label: "Due Date", fieldName: "dueDate", type: "date" },
  { label: "Completed", fieldName: "completedDate", type: "date" }
];

const RELATED_CASE_COLUMNS = [
  {
    label: "Case",
    fieldName: "caseNumber",
    isLink: true,
    linkObjectApiName: "Case"
  },
  { label: "Subject", fieldName: "subject" },
  { label: "Status", fieldName: "status" },
  { label: "Owner", fieldName: "ownerName" },
  { label: "Created", fieldName: "createdDate", type: "date" }
];

/*
 * Household Information, in the order and under the labels the Lightning case
 * page uses. Declared as a list so the section renders one loop rather than a
 * template branch per field, and so a field the controller does not carry
 * simply drops out instead of leaving an empty row.
 */
const HOUSEHOLD_FACTS = [
  { key: "billingAddress", label: "Billing Address" },
  { key: "liquidityNeeds", label: "Liquidity Needs" },
  { key: "approximateNetWorth", label: "Approximate Net Worth" },
  { key: "riskTolerance", label: "Risk Tolerance" },
  { key: "approximateAnnualIncome", label: "Approximate Annual Income" },
  { key: "investmentObjective", label: "Investment Objective (Ranked)" },
  {
    key: "approximateHighestTaxBracket",
    label: "Approximate Highest Tax Bracket"
  },
  { key: "advisoryFee", label: "Advisory Fee" }
];

const PRIORITY_CLASS_BY_VALUE = {
  high: "arc-case-detail__priority-pill--high",
  medium: "arc-case-detail__priority-pill--medium",
  low: "arc-case-detail__priority-pill--low"
};


/**
 * Statuses that mean the case is finished, so it takes no new pit-stop work.
 *
 * 'Canceled' is spelled with one "l" — that is the value in the CaseStatus
 * standard value set, verified against the org; 'Cancelled' does not exist
 * there and would silently never match.
 */
const TERMINAL_STATUSES = ["Closed", "Canceled"];

/*
 * Master record type, which is what getPicklistValues wants when the whole
 * ordered Status picklist is needed rather than one record type's subset. Used
 * only to place a status the case's own record type does not offer — see
 * pathValues.
 */
const MASTER_RECORD_TYPE_ID = "012000000000000AAA";

/*
 * The two sections whose contents are fixed rather than derived: Description
 * Information and System Information hold the same fields on every case, as they
 * do on the Lightning layout.
 */
const DESCRIPTION_FIELDS = ["Subject", "Description"];
const SYSTEM_FIELDS = [
  "CreatedById",
  "CreatedDate",
  "LastModifiedById",
  "LastModifiedDate"
];

const PIT_STOP_FLOWS = {
  branch: {
    flowName: "Task_Creator_Branch_Pit_Stop",
    title: "Create Branch Pit Stop Task"
  },
  homeOffice: {
    flowName: "Task_Creator_Home_Office_Pit_Stop",
    title: "Create Home Office Pit Stop Task"
  }
};

/**
 * Whether the case status bar -- the New / In Progress / On Hold / Closed /
 * Canceled chevron track across the top of a case -- is drawn.
 *
 * Turned off 2026-08-27 at the request of the business: the same information is
 * already on the page as the Status field, and the track took a full row of
 * vertical space above the fold.
 *
 * Hidden rather than deleted. statusPath, hasStatusPath and pathValues are left
 * intact, as is the Status picklist wire that feeds them, so setting this back
 * to true restores the bar with nothing else to put back. pathValues in
 * particular is worth keeping: it exists because the raw picklist made every
 * step read as "upcoming", so the track rendered as a row of grey chevrons with
 * the case appearing to be nowhere.
 */
const SHOW_STATUS_PATH = false;

/**
 * The rail's related-list cards, fetched in one Apex call.
 *
 * Six, not seven: the Files card and its tabset were removed on request
 * (2026-08-27), so ContentDocumentLink is no longer requested. These mirror
 * Lightning's right COLUMN, which is not the same as its Related TAB — that
 * tab holds only Case History, and c/arcCaseFeedTabs renders it.
 */
const RELATED_LIST_REQUESTS = [
  {
    key: "caseComments",
    objectApiName: "CaseComment",
    parentFieldApiName: "ParentId",
    fieldApiNames: ["CommentBody", "CreatedBy.Name", "CreatedDate"]
  },
  {
    key: "orderTickets",
    objectApiName: "Order_Ticket__c",
    parentFieldApiName: "Case__c",
    fieldApiNames: ["Name", "Wizard_Financial_Account__r.Name", "CreatedDate"]
  },
  {
    key: "relatedProducts",
    objectApiName: "Financial_Account_Related_Product__c",
    parentFieldApiName: "Case__c",
    // Product_Name__c and Financial_Account__c, not the row's auto-number
    // Name and the wizard-only lookup: the Lightning case layout's Related
    // Products list shows the plain Financial_Account__c, Product_Name__c is
    // set on every row, and Wizard_Financial_Account__c is null on rows
    // created outside the wizard -- which rendered as a blank column under
    // an RP-000000 title that identified nothing.
    fieldApiNames: [
      "Product_Name__c",
      "Financial_Account__r.Name",
      "CreatedDate"
    ]
  },
  {
    key: "checkLogs",
    objectApiName: "Check_Log__c",
    parentFieldApiName: "Case__c",
    fieldApiNames: ["Name", "Amount__c", "Status__c"]
  },
  {
    key: "tradeErrors",
    objectApiName: "Trade_Error_Log__c",
    parentFieldApiName: "Case__c",
    fieldApiNames: ["Name", "Total_Trade_Error_Amount__c", "Status__c"]
  },
  {
    key: "services",
    objectApiName: "Service__c",
    parentFieldApiName: "Case__c",
    fieldApiNames: ["Name", "Type__c", "Start_Date__c"]
  },
];

/**
 * Case Types that call for each conditional related-list card.
 *
 * Lifted from Case_Record_Page.flexipage's component visibility rules, which is
 * where Lightning actually keeps them -- not in Apex:
 *
 *   Check_Logs__r        {!Record.Type} EQUAL Deposit Check
 *   Trade_Errors_Log__r  {!Record.Type} EQUAL Trade Error
 *   Services__r          {!Record.Type} EQUAL Financial Planning
 *                     OR {!Record.Type} EQUAL Multi-Family Office
 *
 * Case Comments, Order Tickets and Related Products carry no Type rule on that
 * page, so they stay on every case. (Order Tickets has two instances there,
 * split on profile rather than on the record.)
 *
 * The three cards were showing on every case, each reading "(0)" -- six cards
 * where the Lightning page shows three.
 */
const TYPE_CHECK_LOGS = "Deposit Check";
const TYPE_TRADE_ERRORS = "Trade Error";
const TYPES_SERVICES = new Set([
  "Financial Planning",
  "Multi-Family Office"
]);

export default class ArcCaseDetail extends NavigationMixin(LightningElement) {
  taskColumns = TASK_COLUMNS;
  relatedCaseColumns = RELATED_CASE_COLUMNS;

  detail;
  tasks = [];
  fieldSections = [];
  caseInfoFields = [];
  descriptionFields = DESCRIPTION_FIELDS;
  systemFields = SYSTEM_FIELDS;
  householdCases = { openCases: [], closedCases: [] };
  errorMessage = "";
  isInitialLoading = true;
  _statusValues = [];
  _masterStatusValues = [];
  _pageRef;
  _tasksResult;
  _detailResult;
  _householdCasesResult;
  /** Disables the refresh control and shows its spinning state while in flight. */
  isRefreshingHouseholdCases = false;

  @wire(MessageContext)
  messageContext;
  _recordId;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    this._recordId = resolveRecordIdFromPageReference(pageRef, "Case");
  }

  /*
   * The result is held so it can be refreshed after a flow. getCaseDetail is
   * cacheable, so without this the status path, the progress ring and the
   * on-track pill all kept showing the pre-flow values — the case had moved on
   * and the top of the page had not.
   */
  @wire(getCaseDetail, { caseId: "$_recordId" })
  wiredCaseDetail(result) {
    this._detailResult = result;
    this.isInitialLoading = false;

    if (result.data) {
      this.detail = result.data;
      this.errorMessage = "";
      return;
    }

    if (result.error) {
      this.detail = null;
      this.errorMessage =
        result.error?.body?.message || "Unable to load this case.";
    }
  }

  /*
   * Status picklist for this case's record type, which is what the path draws.
   * A failure leaves the list empty and the path unrendered — the rest of the
   * page does not depend on it.
   */
  @wire(getPicklistValues, {
    recordTypeId: "$recordTypeId",
    fieldApiName: CASE_STATUS_FIELD
  })
  wiredStatusValues({ data, error }) {
    if (data) {
      this._statusValues = data.values || [];
    } else if (error) {
      this._statusValues = [];
    }
  }

  /*
   * The full ordered picklist, used only for its ordering: when a case holds a
   * status its record type does not offer, this is what says where that status
   * belongs relative to the ones the record type does offer.
   */
  @wire(getPicklistValues, {
    recordTypeId: MASTER_RECORD_TYPE_ID,
    fieldApiName: CASE_STATUS_FIELD
  })
  wiredMasterStatusValues({ data, error }) {
    if (data) {
      this._masterStatusValues = data.values || [];
    } else if (error) {
      this._masterStatusValues = [];
    }
  }

  @wire(getCaseTasks, { caseId: "$_recordId" })
  wiredCaseTasks(result) {
    this._tasksResult = result;
    if (result.data) {
      this.tasks = result.data;
    } else if (result.error) {
      this.tasks = [];
    }
  }

  @wire(getCaseFieldSections, { caseId: "$_recordId" })
  wiredFieldSections({ data, error }) {
    if (data) {
      this.fieldSections = data.map((section, index) => ({
        key: `${section.name}-${index}`,
        name: section.name,
        fields: section.fields.map((field, fieldIndex) => ({
          key: `${section.name}-${fieldIndex}`,
          label: field.label,
          value: field.value
        }))
      }));
    } else if (error) {
      this.fieldSections = [];
    }
  }

  @wire(getCaseInformationFieldNames, { caseId: "$_recordId" })
  wiredCaseInfoFields({ data, error }) {
    if (data) {
      this.caseInfoFields = data;
    } else if (error) {
      this.caseInfoFields = [];
    }
  }

  /*
   * The whole result is held, not just its data. This is the function form of
   * @wire, so refreshApex has nothing to work with unless the wrapper object
   * itself is kept -- the same reason _detailResult and _tasksResult are held.
   */
  @wire(getRelatedHouseholdCases, { caseId: "$_recordId" })
  wiredHouseholdCases(result) {
    this._householdCasesResult = result;

    if (result.data) {
      this.householdCases = result.data;
    } else if (result.error) {
      this.householdCases = { openCases: [], closedCases: [] };
    }
  }

  /** The rail's six related-list cards, fetched in one Apex call. */
  relatedListsByKey = {};

  // Serialized because the endpoint nulls out a List<inner class> param --
  // see getRelatedRecordsBatch's own doc comment.
  @wire(getRelatedRecordsBatch, {
    recordId: "$_recordId",
    requestsJson: JSON.stringify(RELATED_LIST_REQUESTS)
  })
  wiredRelatedListsBatch({ data, error }) {
    if (data) {
      this.relatedListsByKey = data;
    } else if (error) {
      this.relatedListsByKey = {};
    }
  }

  get caseCommentsResult() {
    return this.relatedListsByKey.caseComments;
  }

  get orderTicketsResult() {
    return this.relatedListsByKey.orderTickets;
  }

  get relatedProductsResult() {
    return this.relatedListsByKey.relatedProducts;
  }

  get checkLogsResult() {
    return this.relatedListsByKey.checkLogs;
  }

  get tradeErrorsResult() {
    return this.relatedListsByKey.tradeErrors;
  }

  get servicesResult() {
    return this.relatedListsByKey.services;
  }

  /**
   * Conditional related-list cards, gated on Case.Type the way the Lightning
   * page gates them. Optional-chained so nothing shows before detail arrives —
   * a card that flashes in and then vanishes is worse than one that appears a
   * beat late.
   */
  get showCheckLogs() {
    return this.detail?.type === TYPE_CHECK_LOGS;
  }

  get showTradeErrorsLog() {
    return this.detail?.type === TYPE_TRADE_ERRORS;
  }

  get showServices() {
    // Set.has(undefined) is false, so this needs no separate guard.
    return TYPES_SERVICES.has(this.detail?.type);
  }

  get hasDetail() {
    return Boolean(this.detail) && !this.errorMessage;
  }

  get recordTypeId() {
    return this.detail?.recordTypeId;
  }

  /* ---- Status path ------------------------------------------------------ */

  /*
   * Steps behind, at, and ahead of where the case sits, matched by value.
   *
   * The case's status is not always one its record type offers — a record type
   * restricts the picklist for the UI, but nothing stops automation or a data
   * load from writing a value outside that set, and a value can be retired from
   * the picklist while records still hold it. This previously left every step
   * "upcoming", so the path rendered as a row of grey chevrons with nothing
   * marked and the case appearing to be nowhere. pathValues folds the real
   * status in instead, so there is always exactly one current step.
   */
  get statusPath() {
    const current = this.detail?.status;
    const values = this.pathValues(current);
    const currentIndex = values.findIndex((entry) => entry.value === current);

    return values.map((entry, index) => {
      let state = "upcoming";
      if (currentIndex >= 0 && index < currentIndex) {
        state = "complete";
      } else if (index === currentIndex) {
        state = "current";
      }
      return {
        value: entry.value,
        label: entry.label,
        className: `case-path__step case-path__step--${state}`
      };
    });
  }

  get hasStatusPath() {
    return SHOW_STATUS_PATH && this.statusPath.length > 0;
  }

  /*
   * The record type's status values, with the case's current status folded in
   * when the record type does not offer it.
   *
   * Placement comes from the master picklist's own ordering rather than being
   * guessed: the status is inserted ahead of the first record-type value that
   * ranks after it there. A value the master picklist no longer holds — retired
   * from the field while records still carry it — has no ordering to honour, so
   * it goes first, which marks nothing behind it as done rather than implying
   * the whole track was completed.
   */
  pathValues(current) {
    const values = this._statusValues;

    if (!current || !values.length) {
      return values;
    }
    if (values.some((entry) => entry.value === current)) {
      return values;
    }

    const master = this._masterStatusValues;
    const rankOf = (value) =>
      master.findIndex((entry) => entry.value === value);
    const currentRank = rankOf(current);

    // Prefer the master picklist's label; fall back to the raw value so a
    // retired status still reads as something.
    const currentEntry = master[currentRank] || {
      value: current,
      label: current
    };

    if (currentRank < 0) {
      return [currentEntry, ...values];
    }

    const insertAt = values.findIndex((entry) => {
      const rank = rankOf(entry.value);
      return rank >= 0 && rank > currentRank;
    });

    if (insertAt < 0) {
      return [...values, currentEntry];
    }

    const next = [...values];
    next.splice(insertAt, 0, currentEntry);
    return next;
  }

  /* ---- Content ---------------------------------------------------------- */

  get hasTasks() {
    return this.tasks.length > 0;
  }

  get allTasksLabel() {
    return `Tasks (${this.tasks.length})`;
  }

  /** A case with no tasks has nothing to be "currently on". */
  get hasAnyTasks() {
    return this.tasks.length > 0;
  }

  /**
   * A finished case takes no new work, so the two pit-stop actions are hidden
   * once it is closed or cancelled rather than left to fail later.
   *
   * Note the value is 'Canceled', one "l" — that is how it is spelled in the
   * CaseStatus standard value set, and 'Cancelled' would silently never match.
   * Only these two are treated as finished, per the request; be aware the
   * picklist also marks Approved, Rejected and Duplicate as closed statuses,
   * so those still show the buttons.
   */
  get isCaseFinished() {
    return TERMINAL_STATUSES.includes(this.detail?.status);
  }

  /*
   * Deliberately not also gated on hasAnyTasks. Requiring an existing task meant
   * a case with none offered no way to create its first pit stop task, so the
   * only condition is that the case is not finished. Changed in the org and
   * pulled back here, not the other way round.
   */
  get canCreatePitStopTask() {
    return !this.isCaseFinished;
  }

  get hasCaseInfoFields() {
    return this.caseInfoFields.length > 0;
  }

  get hasFieldSections() {
    return this.fieldSections.length > 0;
  }

  /*
   * The Advertising Item card belongs to the Advertising Review layout, so it
   * shows for that record type and nowhere else — including, deliberately, when
   * the lookup is empty, because that is the state the Lightning page shows
   * ("Link a related record.").
   */
  get showAdvertisingItem() {
    return this.detail?.recordTypeName === "Advertising Review";
  }

  handleAdvertisingItemClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.detail.advertisingItemId, "Advertising_Item__c");
  }

  get hasAccountLink() {
    return Boolean(this.detail?.accountId);
  }

  get hasHouseholdLink() {
    return Boolean(this.detail?.householdId);
  }

  get household() {
    return this.detail?.household;
  }

  get hasHouseholdSummary() {
    return this.householdFacts.length > 0;
  }

  /** Only the household fields that actually carry a value. */
  get householdFacts() {
    const household = this.household;
    if (!household) {
      return [];
    }
    return HOUSEHOLD_FACTS.filter((fact) => household[fact.key]).map(
      (fact) => ({
        key: fact.key,
        label: fact.label,
        value: household[fact.key]
      })
    );
  }

  get openHouseholdCases() {
    return this.householdCases?.openCases || [];
  }

  get closedHouseholdCases() {
    return this.householdCases?.closedCases || [];
  }

  get hasOpenHouseholdCases() {
    return this.openHouseholdCases.length > 0;
  }

  get hasClosedHouseholdCases() {
    return this.closedHouseholdCases.length > 0;
  }

  get openHouseholdCasesLabel() {
    return `Open Cases for Household (${this.openHouseholdCases.length})`;
  }

  get closedHouseholdCasesLabel() {
    return `Closed Cases for Household (${this.closedHouseholdCases.length})`;
  }

  get priorityPillClass() {
    const key = (this.detail?.priority || "").toLowerCase();
    const modifier = PRIORITY_CLASS_BY_VALUE[key] || "";
    return `arc-case-detail__priority-pill ${modifier}`.trim();
  }

  /*
   * Runs the same flow the Lightning page's quick action runs, in a modal. The
   * flow owns creating the task, so there is one definition of what a pit stop
   * task is rather than a second one here.
   */
  handleCreatePitStopTask(event) {
    const config = PIT_STOP_FLOWS[event.currentTarget?.dataset?.flow];
    if (!config || !this.detail?.id) {
      return;
    }
    this.refs.flowModal?.open({
      flowName: config.flowName,
      title: config.title,
      params: [{ name: "recordId", type: "String", value: this.detail.id }]
    });
  }

  /*
   * A finished flow has created a task, so this component's list is stale and so
   * are the three track tiles. The tiles fetch their own data and cannot be
   * refreshed from here, but they subscribe to CaseStatusUpdated — so one
   * publish refreshes all of them along with the Current Task tile.
   */
  /*
   * Order tickets and related products have no page of their own in this
   * site -- navigating to them lands on Invalid Page -- so their cards'
   * cancelable rownavigate is intercepted and a quick-view popup opens
   * instead, the same pattern Product Detail's Related Products table uses.
   */
  handleOrderTicketRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.orderTicketQuickView?.open(recordId);
    }
  }

  handleRelatedProductRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.relatedProductQuickView?.open(recordId);
    }
  }

  handleFlowFinished() {
    if (this._tasksResult) {
      refreshApex(this._tasksResult);
    }
    /* The header reads from getCaseDetail, so it needs its own refresh or the
       status path, progress ring and on-track pill stay on the old values. */
    if (this._detailResult) {
      refreshApex(this._detailResult);
    }
    if (this.messageContext && this.detail?.id) {
      publish(this.messageContext, CASE_STATUS_UPDATED, {
        recordId: this.detail.id
      });
    }
  }

  /**
   * Re-reads the household case lists without reloading the page.
   *
   * Both cards are fed by one getRelatedHouseholdCases wire, so a single
   * refreshApex updates Open and Closed together -- which is right: a case
   * being closed moves it between the two, and refreshing only one would leave
   * the pair disagreeing.
   *
   * getRelatedHouseholdCases is cacheable, so without refreshApex the client
   * would serve its cached copy and the button would appear to do nothing. This
   * is the one call that actually goes back to the server.
   */
  handleRefreshHouseholdCases() {
    if (!this._householdCasesResult || this.isRefreshingHouseholdCases) {
      return;
    }

    this.isRefreshingHouseholdCases = true;

    refreshApex(this._householdCasesResult)
      .catch((error) => {
        // Leave the existing rows on screen rather than blanking them: stale
        // rows are more useful than none, and the counts in the card titles
        // would otherwise disagree with what is listed.
        // eslint-disable-next-line no-console
        console.error(
          "[arcCaseDetail] Failed to refresh household cases",
          error
        );
      })
      .finally(() => {
        this.isRefreshingHouseholdCases = false;
      });
  }

  handleAccountClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.detail.accountId, "Account");
  }

  handleHouseholdClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.detail.householdId, "Account");
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId) {
      return;
    }

    const pageReference = buildRecordNavigationReference(
      recordId,
      objectApiName
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }
}