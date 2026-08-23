import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { publish, MessageContext } from "lightning/messageService";
import CASE_STATUS_UPDATED from "@salesforce/messageChannel/CaseStatusUpdated__c";
import { refreshApex } from "@salesforce/apex";
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import CASE_STATUS_FIELD from "@salesforce/schema/Case.Status";
import {
  resolveRecordIdFromPageReference,
  buildRecordNavigationReference
} from "c/recordNavigationUtils";
import getCaseDetail from "@salesforce/apex/ArcCaseDetailController.getCaseDetail";
import getCaseTasks from "@salesforce/apex/ArcCaseDetailController.getCaseTasks";
import getCaseFieldSections from "@salesforce/apex/ArcCaseDetailController.getCaseFieldSections";
import getCaseInformationFieldNames from "@salesforce/apex/ArcCaseDetailController.getCaseInformationFieldNames";
import getRelatedHouseholdCases from "@salesforce/apex/ArcCaseDetailController.getRelatedHouseholdCases";

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

const TAB_FILES = "files";

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
  activeTab = TAB_FILES;
  _statusValues = [];
  _masterStatusValues = [];
  _pageRef;
  _tasksResult;
  _detailResult;

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

  @wire(getRelatedHouseholdCases, { caseId: "$_recordId" })
  wiredHouseholdCases({ data, error }) {
    if (data) {
      this.householdCases = data;
    } else if (error) {
      this.householdCases = { openCases: [], closedCases: [] };
    }
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
    return this.statusPath.length > 0;
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

  /* ---- Tabs ------------------------------------------------------------- */

  get isFilesTab() {
    return this.activeTab === TAB_FILES;
  }

  get filesTabClass() {
    return this._tabClass(this.isFilesTab);
  }

  _tabClass(isActive) {
    return isActive
      ? "case-tabs__tab case-tabs__tab--active"
      : "case-tabs__tab";
  }

  handleTabSelect(event) {
    const tab = event.currentTarget?.dataset?.tab;
    if (tab === TAB_FILES) {
      this.activeTab = tab;
    }
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