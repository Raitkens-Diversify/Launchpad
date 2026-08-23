/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Shared Diversify breadcrumb trail for LWR Experience Cloud sites.
 * Visuals live in diversifyStyles.css under .arc-breadcrumb*.
 *
 * Nav trail mode (default on Experience sites):
 *   Record pages show the record Name by default. A parent list crumb appears only
 *   when the user selected a matching sidebar nav item (e.g. All Contacts, Work).
 *   Builder listLabel/listPath remain fallbacks for list pages only.
 *
 * Programmatic mode:
 *   Pass @api items — [{ label, key?, muted?, current? }]
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import {
  isValidSalesforceRecordId,
  resolveRecordIdFromPageReference,
} from "c/recordNavigationUtils";
import {
  readNavTrail,
  NAV_TRAIL_CHANGE_EVENT,
  NAV_PATH_CHANGE_EVENT,
  syncNavTrailFromLocation,
  inferObjectApiNameFromPath,
  resolveCurrentPath,
  resolveCurrentQueryParams,
  serializeSearch,
  ARC_NAV_HOME_ID,
  findNavTargetById,
} from "c/arcNavTrailState";

const LIST_CRUMB_KEY = "list";
const HOME_CRUMB_KEY = "home";

const CASE_OBJECT_API_NAME = "Case";
const CASE_DISPLAY_FIELDS = [
  "Case_Branch_Name_DisplayName__c",
  "Subject",
  "CaseNumber",
];

const TASK_OBJECT_API_NAME = "Task";
const TASK_DISPLAY_FIELDS = ["Subject"];

const normalizeFieldValue = (value) => {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
};

const resolveFirstFieldValue = (record, objectApiName, fieldApiNames) => {
  for (const fieldApiName of fieldApiNames) {
    const value = normalizeFieldValue(
      getFieldValue(record, `${objectApiName}.${fieldApiName}`)
    );

    if (value) {
      return value;
    }
  }

  return "";
};

let diversifyStylesLoadPromise;

const ensureDiversifyStyles = (host) => {
  if (!diversifyStylesLoadPromise) {
    diversifyStylesLoadPromise = loadStyle(host, diversifyStyles).catch(
      (error) => {
        diversifyStylesLoadPromise = undefined;
        throw error;
      }
    );
  }

  return diversifyStylesLoadPromise;
};

const buildTextClass = ({ muted = false, current = false } = {}) => {
  const classes = ["arc-breadcrumb__text"];

  if (muted) {
    classes.push("arc-breadcrumb__text_muted");
  }

  if (current) {
    classes.push("arc-breadcrumb__text_current");
  }

  return classes.join(" ");
};

const buildLinkClass = ({ muted = false } = {}) => {
  const classes = ["arc-breadcrumb__link"];

  if (muted) {
    classes.push("arc-breadcrumb__text_muted");
  }

  return classes.join(" ");
};

export default class ArcBreadcrumb extends NavigationMixin(LightningElement) {
  @api items = [];
  @api objectApiName = "";
  @api listLabel = "";
  @api listPath = "";
  @api nameField = "Name";
  @api parentLabel = "";
  @api currentLabel = "";
  @api parentKey = "";
  @api ariaLabel = "Breadcrumb";

  _pageRef;
  _recordId;
  _navTrail = null;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    this.refreshNavTrail();
    this.syncRecordIdFromContext();
  }

  get wiredRecordId() {
    return isValidSalesforceRecordId(this._recordId) ? this._recordId : undefined;
  }

  @wire(getRecord, { recordId: "$wiredRecordId", fields: "$recordFields" })
  wiredRecord;

  connectedCallback() {
    ensureDiversifyStyles(this).catch(() => {
      // Parent shells may already load the sheet.
    });
    this.refreshNavTrail();
    this.syncRecordIdFromContext();
    this._onNavTrailChange = () => {
      this.refreshNavTrail();
    };
    window.addEventListener(NAV_TRAIL_CHANGE_EVENT, this._onNavTrailChange);
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onNavTrailChange);
  }

  disconnectedCallback() {
    window.removeEventListener(NAV_TRAIL_CHANGE_EVENT, this._onNavTrailChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onNavTrailChange);
  }

  refreshNavTrail() {
    const pathname = resolveCurrentPath(this._pageRef);
    const search = serializeSearch(resolveCurrentQueryParams(this._pageRef));
    const syncedTrail = syncNavTrailFromLocation(pathname, search, this._pageRef);

    this._navTrail = syncedTrail || readNavTrail();
  }

  get sessionNavTrail() {
    return readNavTrail();
  }

  get activeTrail() {
    return this._navTrail || this.sessionNavTrail;
  }

  get activeListLabel() {
    return this.sessionNavTrail?.label || this.listLabel;
  }

  get activeListPath() {
    return this.sessionNavTrail?.path || this.listPath;
  }

  get activeObjectApiName() {
    return this.sessionNavTrail?.objectApiName || this.objectApiName;
  }

  get inferredObjectApiNameFromPath() {
    return inferObjectApiNameFromPath(resolveCurrentPath(this._pageRef));
  }

  get pageRefObjectApiName() {
    return (
      this._pageRef?.attributes?.objectApiName ||
      this._pageRef?.state?.objectApiName ||
      ""
    );
  }

  get recordObjectApiName() {
    if (this.inferredObjectApiNameFromPath) {
      return this.inferredObjectApiNameFromPath;
    }

    if (this.pageRefObjectApiName) {
      return this.pageRefObjectApiName;
    }

    if (this.wiredRecord?.data?.apiName) {
      return this.wiredRecord.data.apiName;
    }

    if (!this._recordId) {
      return this.objectApiName;
    }

    return "";
  }

  get shouldShowHomeCrumb() {
    return Boolean(this._recordId) && !this.shouldShowListCrumb;
  }

  get homeCrumb() {
    const homeTarget = findNavTargetById(ARC_NAV_HOME_ID);

    return {
      label: homeTarget?.label || "Home",
      key: HOME_CRUMB_KEY,
      muted: true,
    };
  }

  get homePath() {
    return findNavTargetById(ARC_NAV_HOME_ID)?.target || "/";
  }

  get shouldShowListCrumb() {
    const trail = this.sessionNavTrail;

    if (!trail?.navItemId || !trail?.label || !trail?.path) {
      return false;
    }

    if (trail.navItemId === ARC_NAV_HOME_ID) {
      return false;
    }

    if (!this._recordId) {
      return true;
    }

    if (!trail.objectApiName || !this.recordObjectApiName) {
      return false;
    }

    return (
      trail.objectApiName.toLowerCase() === this.recordObjectApiName.toLowerCase()
    );
  }

  get recordFields() {
    if (!this.wiredRecordId || !this.recordObjectApiName) {
      return undefined;
    }

    if (this.recordObjectApiName === CASE_OBJECT_API_NAME) {
      return CASE_DISPLAY_FIELDS.map(
        (fieldApiName) => `${CASE_OBJECT_API_NAME}.${fieldApiName}`
      );
    }

    if (this.recordObjectApiName === TASK_OBJECT_API_NAME) {
      return TASK_DISPLAY_FIELDS.map(
        (fieldApiName) => `${TASK_OBJECT_API_NAME}.${fieldApiName}`
      );
    }

    if (!this.nameField) {
      return undefined;
    }

    return [`${this.recordObjectApiName}.${this.nameField}`];
  }

  get recordDisplayName() {
    if (!this.recordFields?.length || !this.wiredRecord?.data) {
      return "";
    }

    if (this.recordObjectApiName === CASE_OBJECT_API_NAME) {
      return resolveFirstFieldValue(
        this.wiredRecord.data,
        CASE_OBJECT_API_NAME,
        CASE_DISPLAY_FIELDS
      );
    }

    if (this.recordObjectApiName === TASK_OBJECT_API_NAME) {
      return resolveFirstFieldValue(
        this.wiredRecord.data,
        TASK_OBJECT_API_NAME,
        TASK_DISPLAY_FIELDS
      );
    }

    return getFieldValue(this.wiredRecord.data, this.recordFields[0]) || "";
  }

  get usesDynamicTrail() {
    if (Array.isArray(this.items) && this.items.length > 0) {
      return false;
    }

    if (this._recordId) {
      return Boolean(this.recordObjectApiName);
    }

    return Boolean(this.activeListLabel && this.activeObjectApiName);
  }

  get resolvedItems() {
    if (Array.isArray(this.items) && this.items.length > 0) {
      return this.items;
    }

    if (this.usesDynamicTrail) {
      return this.buildDynamicItems();
    }

    return this.buildStaticItems();
  }

  get itemView() {
    return this.resolvedItems.map((item, index) => {
      const isCurrent = Boolean(item.current);
      const isMuted = Boolean(item.muted);
      const isClickable = Boolean(item.key) && !isCurrent;

      return {
        ...item,
        renderKey: item.key || `crumb-${index}`,
        isClickable,
        ariaCurrent: isCurrent ? "page" : undefined,
        textClass: buildTextClass({ muted: isMuted, current: isCurrent }),
        linkClass: buildLinkClass({ muted: isMuted }),
      };
    });
  }

  syncRecordIdFromContext() {
    const resolved = resolveRecordIdFromPageReference(
      this._pageRef,
      this.inferredObjectApiNameFromPath || this.pageRefObjectApiName || null
    );

    this._recordId = resolved || null;
  }

  buildDynamicItems() {
    const listLabel = this.activeListLabel;
    const showListCrumb = this.shouldShowListCrumb;
    const homeCrumb = this.shouldShowHomeCrumb ? this.homeCrumb : null;

    if (!this._recordId) {
      return [{ label: listLabel || this.activeObjectApiName, current: true }];
    }

    const recordName = this.recordDisplayName;
    const isLoading =
      this.wiredRecord?.loading && !recordName;

    if (!showListCrumb) {
      if (isLoading) {
        return [
          ...(homeCrumb ? [homeCrumb] : []),
          { label: "Loading…", current: true },
        ];
      }

      return [
        ...(homeCrumb ? [homeCrumb] : []),
        { label: recordName || this._recordId, current: true },
      ];
    }

    if (isLoading) {
      return [
        { label: listLabel, key: LIST_CRUMB_KEY, muted: true },
        { label: "Loading…", current: true },
      ];
    }

    return [
      { label: listLabel, key: LIST_CRUMB_KEY, muted: true },
      { label: recordName || this._recordId, current: true },
    ];
  }

  buildStaticItems() {
    const crumbs = [];

    if (this.parentLabel) {
      crumbs.push({
        label: this.parentLabel,
        key: this.parentKey || undefined,
        muted: true,
      });
    }

    if (this.currentLabel) {
      crumbs.push({ label: this.currentLabel, current: true });
    }

    return crumbs;
  }

  handleCrumbClick(event) {
    const key = event.currentTarget.dataset.key;

    if (!key) {
      return;
    }

    if (key === HOME_CRUMB_KEY) {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: this.homePath },
      });
      return;
    }

    const listPath = this.activeListPath;

    if (key === LIST_CRUMB_KEY && listPath) {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: listPath },
      });
      return;
    }

    this.dispatchEvent(
      new CustomEvent("crumbselect", {
        detail: { key },
        bubbles: true,
        composed: true,
      })
    );
  }
}