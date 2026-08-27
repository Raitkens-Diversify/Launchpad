/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * Related Work card for the account detail page: the cases and tasks that
 * belong to this contact or household, behind a Cases / Tasks tab strip.
 *
 * The record id is resolved from the page context the same way arcRecordDetail
 * does it, so the card can be dropped on the page without wiring a property.
 */
import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import {
  resolveRecordIdFromPageReference,
  buildRecordNavigationReference
} from "c/recordNavigationUtils";
import getWorkItems from "@salesforce/apex/ArcRecordWorkItemsController.getWorkItems";

const TAB_CASES = "cases";
const TAB_TASKS = "tasks";

/** Matches ArcRecordWorkItemsController.ROW_LIMIT. */
const ROW_LIMIT = 10;

const OBJECT_BY_TAB = {
  [TAB_CASES]: "Case",
  [TAB_TASKS]: "Task"
};

export default class ArcRecordWorkItems extends NavigationMixin(
  LightningElement
) {
  @api cardLabel = "Related Work";

  _recordId;
  _pageRef;
  _stylesLoaded = false;

  activeTab = TAB_CASES;
  cases = [];
  tasks = [];
  isLoading = true;
  errorMessage = "";

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    const resolved = resolveRecordIdFromPageReference(pageRef, null);
    if (resolved && resolved !== this._recordId) {
      this._recordId = resolved;
      this.loadItems();
    }
  }

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    if (!value || value === this._recordId) {
      return;
    }
    this._recordId = value;
    this.loadItems();
  }

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch(() => {
        /* Non-fatal: the component's own stylesheet covers layout. */
      });
    }
  }

  async loadItems() {
    if (!this._recordId) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";

    try {
      const result = await getWorkItems({ recordId: this._recordId });
      this.cases = result?.cases || [];
      this.tasks = result?.tasks || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcRecordWorkItems] Failed to load work items", error);
      this.errorMessage =
        error?.body?.message || "Unable to load related work right now.";
      this.cases = [];
      this.tasks = [];
    } finally {
      this.isLoading = false;
    }
  }

  /*
   * Apex fetches one row past the limit so "10 of more" can be told from
   * "exactly 10" without a second count query; that extra row is a signal, not
   * something to draw.
   */
  countLabel(items) {
    return items.length > ROW_LIMIT ? `${ROW_LIMIT}+` : String(items.length);
  }

  get tabs() {
    return [
      {
        key: TAB_CASES,
        label: `Cases (${this.countLabel(this.cases)})`,
        cssClass: this.tabClass(TAB_CASES),
        ariaSelected: this.activeTab === TAB_CASES ? "true" : "false"
      },
      {
        key: TAB_TASKS,
        label: `Tasks (${this.countLabel(this.tasks)})`,
        cssClass: this.tabClass(TAB_TASKS),
        ariaSelected: this.activeTab === TAB_TASKS ? "true" : "false"
      }
    ];
  }

  tabClass(key) {
    return this.activeTab === key
      ? "work-items__tab work-items__tab--active"
      : "work-items__tab";
  }

  get activeItems() {
    const items = this.activeTab === TAB_CASES ? this.cases : this.tasks;
    return items.slice(0, ROW_LIMIT).map((item) => ({
      ...item,
      hasSubtitle: Boolean(item.subtitle),
      hasStatus: Boolean(item.status),
      hasDetail: Boolean(item.detail)
    }));
  }

  get hasItems() {
    return this.activeItems.length > 0;
  }

  get emptyMessage() {
    return this.activeTab === TAB_CASES
      ? "No cases for this contact yet."
      : "No tasks for this contact yet.";
  }

  handleTabClick(event) {
    const key = event.currentTarget.dataset.key;
    if (key && key !== this.activeTab) {
      this.activeTab = key;
    }
  }

  handleTabKeyDown(event) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") {
      return;
    }
    event.preventDefault();
    this.activeTab = this.activeTab === TAB_CASES ? TAB_TASKS : TAB_CASES;
  }

  handleItemClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.id;
    const reference = buildRecordNavigationReference(
      recordId,
      OBJECT_BY_TAB[this.activeTab]
    );
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}