/**
 * Task detail page for Experience Cloud: a Case-Detail-style header (built
 * from ArcTaskDetailController.getTaskContext, since c-arc-record-detail
 * doesn't expose its loaded values to a parent) wrapping the generic
 * c-arc-record-detail field sections (unchanged), plus the two related lists
 * the CRM Task page has that the generic Envelope_Field__mdt pipeline can't
 * produce: Open Activities for Parent Case and Open Cases for Household.
 */
import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import {
  resolveRecordIdFromPageReference,
  isValidSalesforceRecordId,
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";
import getTaskContext from "@salesforce/apex/ArcTaskDetailController.getTaskContext";
import getOpenActivitiesForParentCase from "@salesforce/apex/ArcTaskDetailController.getOpenActivitiesForParentCase";
import getOpenActivitiesForParent from "@salesforce/apex/ArcTaskDetailController.getOpenActivitiesForParent";
import getOpenCasesForHousehold from "@salesforce/apex/ArcTaskDetailController.getOpenCasesForHousehold";
import markComplete from "@salesforce/apex/CaseCurrentTaskController.markComplete";
import addComment from "@salesforce/apex/TaskCommentController.addComment";

const ACTIVITY_COLUMNS = [
  {
    label: "Subject",
    fieldName: "subject",
    isLink: true,
    linkObjectApiName: "Task"
  },
  { label: "Status", fieldName: "status" },
  { label: "Owner", fieldName: "ownerName" },
  { label: "Due Date", fieldName: "dueDate", type: "date" }
];

/*
 * The non-Case parent's open activities, with the columns Lightning's own
 * OpenActivities related list shows: Subject, the activity's Who, whether the
 * row is a task (events mix into the same list), and the due date.
 */
const PARENT_ACTIVITY_COLUMNS = [
  {
    label: "Subject",
    fieldName: "subject",
    isLink: true,
    linkObjectApiName: "Task"
  },
  { label: "Name", fieldName: "whoName" },
  { label: "Task", fieldName: "taskMark" },
  { label: "Due Date", fieldName: "dueDate", type: "date" }
];

const HOUSEHOLD_CASE_COLUMNS = [
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

export default class ArcTaskDetail extends NavigationMixin(LightningElement) {
  _recordId;
  _pageRef;
  activityColumns = ACTIVITY_COLUMNS;
  parentActivityColumns = PARENT_ACTIVITY_COLUMNS;
  householdCaseColumns = HOUSEHOLD_CASE_COLUMNS;

  taskContext = {};
  _taskContextResult;
  openActivities = [];
  _activitiesResult;
  parentActivities = [];
  householdCases = [];
  _householdCasesResult;

  isMarkingComplete = false;
  markCompleteErrorMessage = "";

  isCommentModalOpen = false;
  commentBody = "";
  isSavingComment = false;
  commentError = "";

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    this._recordId = resolveRecordIdFromPageReference(pageRef, "Task");
  }

  @wire(getTaskContext, { taskId: "$_recordId" })
  wiredTaskContext(result) {
    this._taskContextResult = result;
    this.taskContext = result?.data || {};
  }

  @wire(getOpenActivitiesForParentCase, { taskId: "$_recordId" })
  wiredActivities(result) {
    this._activitiesResult = result;
    this.openActivities = result?.data || [];
  }

  @wire(getOpenActivitiesForParent, { taskId: "$_recordId" })
  wiredParentActivities(result) {
    this.parentActivities = (result?.data || []).map((activity) => ({
      ...activity,
      // The screenshot's Task column is a checkbox; a mark reads the same
      // in a plain text cell, and an event row simply leaves it blank.
      taskMark: activity.isTask ? "✓" : ""
    }));
  }

  @wire(getOpenCasesForHousehold, { taskId: "$_recordId" })
  wiredHouseholdCases(result) {
    this._householdCasesResult = result;
    this.householdCases = result?.data || [];
  }

  get hasRecordId() {
    return isValidSalesforceRecordId(this._recordId);
  }

  get recordId() {
    return this._recordId;
  }

  get subject() {
    return this.taskContext?.subject || "";
  }

  get status() {
    return this.taskContext?.status || "";
  }

  get priority() {
    return this.taskContext?.priority || "";
  }

  get hasPriority() {
    return Boolean(this.priority);
  }

  get priorityPillClass() {
    const base = "arc-task-detail__pill";
    const variant = this.priority.toLowerCase();
    return `${base} ${base}--${variant}`;
  }

  get hasDueDate() {
    return Boolean(this.taskContext?.dueDate);
  }

  get formattedDueDate() {
    if (!this.taskContext?.dueDate) {
      return "";
    }
    const [year, month, day] = this.taskContext.dueDate.split("-");
    return `${month}/${day}/${year}`;
  }

  /**
   * Inline editing (the Task Information section) is for users on the task's
   * Financial Advisor Team — the Lightning Task page's gate, resolved
   * server-side from User_on_FA_Team__c or an active team-member record.
   */
  get canEditTask() {
    return this.taskContext?.isUserOnFaTeam === true;
  }

  get hasWhat() {
    return Boolean(this.taskContext?.whatId && this.taskContext?.whatName);
  }

  get hasWho() {
    return Boolean(this.taskContext?.whoId && this.taskContext?.whoName);
  }

  get isCompleted() {
    return this.status === "Completed";
  }

  /**
   * Mark Complete mirrors the Lightning Task page: the action is present on
   * any loaded task and enabled while the task is still open, greying out once
   * it is Completed — not restricted to the task owner.
   */
  get showMarkComplete() {
    return this.hasRecordId && Boolean(this.status);
  }

  get disableMarkComplete() {
    return this.isMarkingComplete || this.isCompleted;
  }

  get showOpenActivities() {
    return this.taskContext?.isParentCase === true;
  }

  get hasOpenActivities() {
    return this.openActivities.length > 0;
  }

  get openActivitiesLabel() {
    return `Open Activities for Parent Case (${this.openActivities.length})`;
  }

  /** Case parents keep their own richer section above; everything else gets
   *  the parent's open activities, the way the Lightning task page does. */
  get showParentActivities() {
    return Boolean(this.taskContext?.whatId) && !this.taskContext?.isParentCase;
  }

  get hasParentActivities() {
    return this.parentActivities.length > 0;
  }

  get parentActivitiesLabel() {
    const label = this.taskContext?.whatObjectLabel || "Record";
    return `Open Activities for Parent ${label} (${this.parentActivities.length})`;
  }

  /**
   * Events mix into OpenActivities but have no page in this site, so a click
   * on an event row is swallowed rather than sent to an invalid /task URL.
   */
  handleParentActivityRowNavigate(event) {
    const recordId = String(event.detail?.recordId || "");
    if (recordId.startsWith("00U")) {
      event.preventDefault();
    }
  }

  get hasHouseholdCases() {
    return this.householdCases.length > 0;
  }

  get householdCasesLabel() {
    return `Open Cases for Household (${this.householdCases.length})`;
  }

  get hasMarkCompleteError() {
    return Boolean(this.markCompleteErrorMessage);
  }

  get hasCommentError() {
    return Boolean(this.commentError);
  }

  handleWhatClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.taskContext.whatId, this.taskContext.whatObjectApiName);
  }

  handleWhoClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.taskContext.whoId, this.taskContext.whoObjectApiName);
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId || !objectApiName) {
      return;
    }
    const pageReference = buildRecordNavigationReference(recordId, objectApiName);
    if (!pageReference) {
      return;
    }
    this[NavigationMixin.Navigate](pageReference);
  }

  async handleMarkComplete() {
    if (this.isMarkingComplete || this.isCompleted) {
      return;
    }

    this.isMarkingComplete = true;
    this.markCompleteErrorMessage = "";
    try {
      await markComplete({ taskId: this._recordId });
      await Promise.all([
        refreshApex(this._taskContextResult),
        refreshApex(this._activitiesResult)
      ]);
      this.getRecordDetail()?.refresh();
    } catch (error) {
      this.markCompleteErrorMessage =
        error?.body?.message || error?.message || "Could not mark this task complete.";
    } finally {
      this.isMarkingComplete = false;
    }
  }

  getRecordDetail() {
    return this.template.querySelector("c-arc-record-detail");
  }

  /**
   * The Task Information section saved (arcRecordDetail's inline edit) — pull
   * the header facts (Due Date, subject, status) back in line with it.
   */
  handleRecordSaved() {
    refreshApex(this._taskContextResult);
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
      await addComment({ taskId: this._recordId, body });
      this.isCommentModalOpen = false;
      this.commentBody = "";
      // Reload the right-hand Task Comments list so the new comment shows.
      this.refs.taskComments?.refresh();
    } catch (error) {
      this.commentError =
        error?.body?.message || error?.message || "Could not add this comment.";
    } finally {
      this.isSavingComment = false;
    }
  }
}