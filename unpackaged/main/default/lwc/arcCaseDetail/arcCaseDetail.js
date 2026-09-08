import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import {
  publish,
  subscribe as subscribeToMessageChannel,
  unsubscribe as unsubscribeFromMessageChannel,
  MessageContext,
  APPLICATION_SCOPE
} from "lightning/messageService";
import CASE_STATUS_UPDATED from "@salesforce/messageChannel/CaseStatusUpdated__c";
import { refreshApex } from "@salesforce/apex";
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import CASE_STATUS_FIELD from "@salesforce/schema/Case.Status";
import ADDITIONAL_CASE_NOTES_FIELD from "@salesforce/schema/Case.Additional_Case_Notes__c";
import {
  resolveRecordIdFromPageReference
} from "c/recordNavigationUtils";
import { buildRecordNavigationReference } from "c/recordNavigationCommunityUtils";
import getCaseDetail from "@salesforce/apex/ArcCaseDetailController.getCaseDetail";
import getCaseTasks from "@salesforce/apex/ArcCaseDetailController.getCaseTasks";
import getRelatedRecordsBatch from "@salesforce/apex/ArcRelatedListController.getRelatedRecordsBatch";
import addCaseComment from "@salesforce/apex/ArcCaseCommentController.addComment";
import getTaskLinksForCaseComments from "@salesforce/apex/TaskCommentController.getTaskLinksForCaseComments";
import getCaseFieldSections from "@salesforce/apex/ArcCaseDetailController.getCaseFieldSections";
import getRelatedHouseholdCases from "@salesforce/apex/ArcCaseDetailController.getRelatedHouseholdCases";

// The right rail's 7 c-arc-related-list cards, batched into one Apex call
// instead of each card independently fetching its own (7 round trips ->
// 1). Field paths mirror each card's own `columns` attribute in the
// template exactly -- keep the two in sync if a card's columns change.
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
 * Re-read schedule after a CaseStatusUpdated message or a finished flow -- the
 * same one the three track tiles use. The save that publishes the message
 * returns before the server is finished with the case: the Task trigger's
 * @future work, the pit stop flows and Batch_TaskUpdate stamp the next task's
 * owner and the case's current task a beat later, so a single immediate
 * re-read showed the old values.
 */
const SETTLE_DELAYS_MS = [2000, 5000, 10000];

/*
 * Master record type, which is what getPicklistValues wants when the whole
 * ordered Status picklist is needed rather than one record type's subset. Used
 * only to place a status the case's own record type does not offer — see
 * pathValues.
 */
const MASTER_RECORD_TYPE_ID = "012000000000000AAA";

/** A blank value in a fixed-layout section, so the grid keeps its shape. */
const EMPTY_VALUE = "\u2013";

/** System Information holds the same audit fields on every case. */
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
    // The Product cell links to the approved product (Product__c) detail page --
    // the site's /product route -- so the row lands on the product itself, not
    // the account. Name is the related-product record, linked to its quick-view.
    fieldApiNames: [
      "Product_Name__c",
      "Amount__c",
      "Name"
    ],
    linkFieldApiName: "Product__c"
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
  relatedCaseColumns = RELATED_CASE_COLUMNS;

  detail;
  tasks = [];
  fieldSections = [];
  systemFields = SYSTEM_FIELDS;
  householdCases = { openCases: [], closedCases: [] };
  errorMessage = "";
  isInitialLoading = true;
  _statusValues = [];
  _masterStatusValues = [];
  _pageRef;
  _householdCasesResult;
  _caseStatusSubscription = null;
  _settleTimers = [];
  /** Disables the refresh control and shows its spinning state while in flight. */
  isRefreshingHouseholdCases = false;

  @wire(MessageContext)
  messageContext;
  _recordId;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    const recordId = resolveRecordIdFromPageReference(pageRef, "Case");
    if (recordId !== this._recordId) {
      this._recordId = recordId;
      this.clearSettleTimers();
      this.isInitialLoading = Boolean(recordId);
      this.loadCase();
    }
  }

  connectedCallback() {
    this.subscribeToCaseStatus();
  }

  disconnectedCallback() {
    this.unsubscribeFromCaseStatus();
    this.clearSettleTimers();
  }

  /*
   * The case header, the task-track gating and the field sections are loaded
   * imperatively, not through cacheable @wires (2026-09-08). On the Arc LWR
   * site a cacheable wire kept serving the client cache for minutes, so the
   * status path, the progress ring, the on-track pill, whether the three
   * track tiles render at all, and the field sections all lagged the case: a
   * task completed elsewhere, a flow's async work or another user's edit never
   * showed until a reload. getCaseDetail / getCaseTasks / getCaseFieldSections
   * are no longer cacheable, so every read here goes to the server. Re-read
   * on: the record changing, a finished flow, and any CaseStatusUpdated
   * message for this case (the current-task tile publishes it too), each with
   * the settle schedule the track tiles use.
   */
  loadCase() {
    this.loadCaseDetail();
    this.loadCaseTasks();
    this.loadFieldSections();
  }

  loadCaseDetail() {
    const caseId = this._recordId;
    if (!caseId) {
      return;
    }
    getCaseDetail({ caseId })
      .then((data) => {
        if (caseId !== this._recordId) {
          return; // the page moved to another case while this was in flight
        }
        this.detail = data;
        this.errorMessage = "";
      })
      .catch((error) => {
        if (caseId !== this._recordId) {
          return;
        }
        this.detail = null;
        this.errorMessage =
          error?.body?.message || "Unable to load this case.";
      })
      .finally(() => {
        if (caseId === this._recordId) {
          this.isInitialLoading = false;
        }
      });
  }

  loadCaseTasks() {
    const caseId = this._recordId;
    if (!caseId) {
      return;
    }
    getCaseTasks({ caseId })
      .then((data) => {
        if (caseId === this._recordId) {
          this.tasks = data || [];
        }
      })
      .catch(() => {
        if (caseId === this._recordId) {
          this.tasks = [];
        }
      });
  }

  loadFieldSections() {
    const caseId = this._recordId;
    if (!caseId) {
      return;
    }
    getCaseFieldSections({ caseId })
      .then((data) => {
        if (caseId !== this._recordId) {
          return;
        }
        this.fieldSections = (data || []).map((section, index) => ({
          key: `${section.name}-${index}`,
          name: section.name,
          fields: section.fields.map((field, fieldIndex) => ({
            key: `${section.name}-${fieldIndex}`,
            label: field.label,
            value: field.value
          }))
        }));
      })
      .catch(() => {
        if (caseId === this._recordId) {
          this.fieldSections = [];
        }
      });
  }

  /*
   * CaseStatusUpdated: published by this component after a flow and by the
   * current-task tile after Mark Complete / Assign to Me. Any publisher's
   * message for this case re-reads the header, tasks and sections (the
   * empApi Refresh_Detail__e path does not deliver on the LWR site).
   */
  subscribeToCaseStatus() {
    if (this._caseStatusSubscription || !this.messageContext) {
      return;
    }
    this._caseStatusSubscription = subscribeToMessageChannel(
      this.messageContext,
      CASE_STATUS_UPDATED,
      (message) => this.handleCaseStatusMessage(message),
      { scope: APPLICATION_SCOPE }
    );
  }

  unsubscribeFromCaseStatus() {
    if (this._caseStatusSubscription) {
      unsubscribeFromMessageChannel(this._caseStatusSubscription);
      this._caseStatusSubscription = null;
    }
  }

  handleCaseStatusMessage(message) {
    if (
      !message?.recordId ||
      String(message.recordId) !== String(this._recordId)
    ) {
      return;
    }
    this.reloadUntilSettled();
  }

  /** Reloads now and again at each SETTLE_DELAYS_MS step; see that constant. */
  reloadUntilSettled() {
    this.clearSettleTimers();
    this.loadCase();
    this._settleTimers = SETTLE_DELAYS_MS.map((delay) =>
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => this.loadCase(), delay)
    );
  }

  clearSettleTimers() {
    this._settleTimers.forEach((timer) => clearTimeout(timer));
    this._settleTimers = [];
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

  /*
   * The whole result is held, not just its data. This is the function form of
   * @wire, so refreshApex has nothing to work with unless the wrapper object
   * itself is kept. (Kept cacheable: the household lists change rarely and
   * the cards have their own refresh control.)
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
  _relatedListsResult;
  _relatedListsRefreshedOnce = false;

  /** CaseComment Id -> { taskId, taskSubject } for comments mirrored from a task. */
  taskLinksByCaseCommentId = {};
  _caseCommentsDecorated;

  // Header Actions dropdown.
  isActionsMenuOpen = false;

  // Add Comment (the launchpad Case quick action): modal state.
  isCommentModalOpen = false;
  commentBody = "";
  isSavingComment = false;
  commentError = "";

  // Serialized because the endpoint nulls out a List<inner class> param --
  // see getRelatedRecordsBatch's own doc comment.
  @wire(getRelatedRecordsBatch, {
    recordId: "$_recordId",
    requestsJson: JSON.stringify(RELATED_LIST_REQUESTS)
  })
  wiredRelatedListsBatch(result) {
    this._relatedListsResult = result;
    if (result.data) {
      this.relatedListsByKey = result.data;
      this.loadTaskLinksForCaseComments(result.data.caseComments);
      /*
       * getRelatedRecordsBatch is cacheable, so landing here from the Task
       * page right after leaving a task comment can serve the rail from the
       * client cache -- without the CaseComment the trigger just mirrored.
       * One refresh per visit brings the cards in line with the org.
       */
      if (!this._relatedListsRefreshedOnce) {
        this._relatedListsRefreshedOnce = true;
        refreshApex(result);
      }
    } else if (result.error) {
      this.relatedListsByKey = {};
    }
  }

  /**
   * Which Case Comments were mirrored from a task, so the card can show the
   * task and link to it. Failing here only costs the Task column.
   */
  loadTaskLinksForCaseComments(caseComments) {
    const ids = (caseComments?.rows || []).map((row) => row.id).filter(Boolean);
    if (!ids.length) {
      this.taskLinksByCaseCommentId = {};
      return;
    }
    getTaskLinksForCaseComments({ caseCommentIds: ids })
      .then((links) => {
        const byId = {};
        (links || []).forEach((link) => {
          if (link?.caseCommentId) {
            byId[link.caseCommentId] = link;
          }
        });
        this.taskLinksByCaseCommentId = byId;
      })
      .catch(() => {
        this.taskLinksByCaseCommentId = {};
      });
  }

  /**
   * The Case Comments card's rows with a trailing "Task" cell: the subject of
   * the task a mirrored comment came from (blank for a comment left on the
   * case itself). Memoised on the two inputs so the card is not re-applied on
   * every render.
   */
  get caseCommentsResult() {
    const base = this.relatedListsByKey.caseComments;
    if (!base) {
      return base;
    }
    const links = this.taskLinksByCaseCommentId || {};
    const cached = this._caseCommentsDecorated;
    if (cached && cached.base === base && cached.links === links) {
      return cached.value;
    }
    const value = {
      ...base,
      types: [...(base.types || []), "STRING"],
      rows: (base.rows || []).map((row) => {
        const link = links[row.id];
        return {
          ...row,
          cells: [...(row.cells || []), link ? link.taskSubject || "Task" : ""]
        };
      })
    };
    this._caseCommentsDecorated = { base, links, value };
    return value;
  }

  /** The "Task" cell of a mirrored case comment opens the task it was left on. */
  handleCaseCommentTaskNavigate(event) {
    event.preventDefault();
    const link = this.taskLinksByCaseCommentId?.[event.detail?.recordId];
    if (link?.taskId) {
      this.navigateToRecord(link.taskId, "Task");
    }
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

  /*
   * Mirrors the red "This case has not yet been submitted." banner
   * Case_Record_Page shows internally (a flexipage:richText gated on
   * Record.Submitted__c = false) -- same condition, same wording.
   */
  get isUnsubmitted() {
    return this.detail?.submitted === false;
  }

  get hasEnvelopeLink() {
    return this.isUnsubmitted && Boolean(this.detail?.openEnvelopeId);
  }

  /* The on-track badge/milestone tile has nothing to show for a case that is
     still a wizard draft, so it's hidden alongside the banner. */
  get showCaseOverviewTile() {
    return !this.isUnsubmitted;
  }

  handleTakeToEnvelopeClick() {
    this.navigateToRecord(this.detail?.openEnvelopeId, "Envelope__c");
  }

  get hasHouseholdLink() {
    return Boolean(this.detail?.householdId);
  }

  /* Label for the Household link in the header. Falls back when the case has a
     household id but no readable name. */
  get householdLinkLabel() {
    return this.detail?.householdName || "View Household";
  }

  get hasFinancialAccountLink() {
    return Boolean(this.detail?.financialAccountId);
  }

  get financialAccountLinkLabel() {
    return this.detail?.financialAccountName || "View Financial Account";
  }

  /**
   * Financial Account Details in the Lightning case page's arrangement. Its
   * two columns read account, primary owner, joint owner, platform on the
   * left and rep code, custodian, registration type, product type on the
   * right, so the rows are interleaved for a two-column grid. The section is
   * on every case, and every row is kept, blank ones as a dash, so a case
   * with no account still shows the same shape.
   */
  get financialAccountFacts() {
    const detail = this.detail || {};
    const account = detail.financialAccount || {};
    const link = (key, label, value, recordId, objectApiName) => ({
      key,
      label,
      value: value || EMPTY_VALUE,
      isLink: Boolean(recordId && value),
      recordId,
      objectApiName
    });
    const text = (key, label, value) => ({
      key,
      label,
      value: value || EMPTY_VALUE,
      isLink: false
    });

    return [
      link(
        "account",
        "Financial Account",
        detail.financialAccountName,
        detail.financialAccountId,
        "Financial_Account__c"
      ),
      text("repCode", "Rep Code", account.repCode),
      link(
        "primaryOwner",
        "Primary Owner",
        account.primaryOwnerName,
        account.primaryOwnerId,
        "Account"
      ),
      text("custodian", "Custodian", account.custodian),
      link(
        "jointOwner",
        "Joint Owner",
        account.jointOwnerName,
        account.jointOwnerId,
        "Account"
      ),
      text("registrationType", "Registration Type", account.registrationType),
      text("platform", "Managed Account Platform", account.managedAccountPlatform),
      text("productType", "Product Type", account.productType)
    ];
  }

  handleFinancialAccountFactClick(event) {
    event.preventDefault();
    const { recordId, objectApiName } = event.currentTarget.dataset;
    this.navigateToRecord(recordId, objectApiName);
  }

  /*
   * Additional Case Notes, read through the record API rather than the case
   * controller: the section is display-only here, and this keeps the change
   * to the page itself.
   */
  @wire(getRecord, {
    recordId: "$_recordId",
    fields: [ADDITIONAL_CASE_NOTES_FIELD]
  })
  caseNotesRecord;

  /** The notes, or a dash when there are none. */
  get additionalCaseNotes() {
    const record = this.caseNotesRecord?.data;
    const notes = record ? getFieldValue(record, ADDITIONAL_CASE_NOTES_FIELD) : null;
    return notes || EMPTY_VALUE;
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
    this.openPitStopFlow(event.currentTarget?.dataset?.flow);
  }

  openPitStopFlow(key) {
    const config = PIT_STOP_FLOWS[key];
    if (!config || !this.detail?.id) {
      return;
    }
    this.refs.flowModal?.open({
      flowName: config.flowName,
      title: config.title,
      params: [{ name: "recordId", type: "String", value: this.detail.id }]
    });
  }

  /** The launchpad case page's Log a Check quick action: its ARC-site flow
   *  copy, seeded with this case so the financial account prefills. */
  handleLogACheck() {
    if (!this.detail?.id) {
      return;
    }
    this.refs.flowModal?.open({
      flowName: "ARC_Log_a_Check",
      title: "Log a Check",
      size: "large",
      params: [{ name: "recordId", type: "String", value: this.detail.id }]
    });
  }

  /* ── Header Actions menu ─────────────────────────────────────────────── */

  toggleActionsMenu() {
    this.isActionsMenuOpen = !this.isActionsMenuOpen;
  }

  closeActionsMenu() {
    this.isActionsMenuOpen = false;
  }

  handleActionsMenuSelect(event) {
    const action = event.currentTarget?.dataset?.action;
    this.isActionsMenuOpen = false;

    if (action === "branch" || action === "homeOffice") {
      this.openPitStopFlow(action);
      return;
    }
    if (action === "logACheck") {
      this.handleLogACheck();
      return;
    }
    if (action === "addComment") {
      this.handleAddCommentClick();
    }
  }

  /* ── Add Comment: the launchpad Case quick action (creates a CaseComment
        and it shows in the rail's Case Comments card) ─────────────────── */

  get hasCommentError() {
    return Boolean(this.commentError);
  }

  handleAddCommentClick() {
    this.commentBody = "";
    this.commentError = "";
    this.isCommentModalOpen = true;
  }

  handleCommentChange(event) {
    this.commentBody = event.detail.value;
    if (this.commentError) {
      this.commentError = "";
    }
  }

  handleCommentCancel() {
    if (this.isSavingComment) {
      return;
    }
    this.isCommentModalOpen = false;
    this.commentBody = "";
    this.commentError = "";
  }

  async handleCommentSave() {
    if (this.isSavingComment) {
      return;
    }
    const body = (this.commentBody || "").trim();
    if (!body) {
      this.commentError = "Enter a comment.";
      return;
    }

    this.isSavingComment = true;
    this.commentError = "";
    try {
      await addCaseComment({ caseId: this.detail.id, body });
      this.isCommentModalOpen = false;
      this.commentBody = "";
      // The rail's Case Comments card reads the batch wire; re-run it so the
      // new comment shows without a page reload.
      if (this._relatedListsResult) {
        await refreshApex(this._relatedListsResult);
      }
    } catch (error) {
      this.commentError =
        error?.body?.message || error?.message || "Could not add this comment.";
    } finally {
      this.isSavingComment = false;
    }
  }

  /*
   * A finished flow has created a task, so this component's list is stale and so
   * are the three track tiles. The tiles fetch their own data and cannot be
   * refreshed from here, but they subscribe to CaseStatusUpdated — so one
   * publish refreshes all of them along with the Current Task tile.
   */
  /*
   * Order tickets have no page of their own in this site -- navigating to one
   * lands on Invalid Page -- so the card's cancelable rownavigate is
   * intercepted and a quick-view popup opens instead.
   */
  handleOrderTicketRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.orderTicketQuickView?.open(recordId);
    }
  }

  /*
   * The Related Product Name cell opens the product quick-view, while the rest
   * of the row links to the account. preventDefault keeps arcRelatedList from
   * navigating to the related product (it has no page of its own in the site).
   */
  handleRelatedProductSecondaryNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.relatedProductQuickView?.open(recordId);
    }
  }

  handleFlowFinished() {
    /* This component's own reads (header, task gating, field sections), on the
       settle schedule; the message below reaches the track tiles and the
       current-task tile -- and this component's own subscription, whose
       restart of the same schedule is harmless. */
    this.reloadUntilSettled();
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

  handleHouseholdClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.detail.householdId, "Account");
  }

  handleFinancialAccountClick(event) {
    event.preventDefault();
    this.navigateToRecord(
      this.detail.financialAccountId,
      "Financial_Account__c"
    );
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