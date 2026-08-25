/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Shared Diversify breadcrumb trail for LWR Experience Cloud sites.
 * Visuals live in diversifyStyles.css under .arc-breadcrumb*.
 *
 * Nav trail mode (default on Experience sites):
 *   Reads the active sidebar selection from c/arcNavTrailState, which
 *   arcNavigation updates on click and URL sync. Builder props remain as
 *   fallbacks when no nav trail is stored yet.
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
  resolveRecordIdFromPageReference,
  buildRecordNavigationReference
} from "c/recordNavigationUtils";
import {
  readNavTrail,
  findDefaultListTrail,
  NAV_TRAIL_CHANGE_EVENT,
  NAV_PATH_CHANGE_EVENT,
  syncNavTrailFromLocation,
  isOffNavRoute,
  resolveCurrentPath,
  resolveCurrentQueryParams,
  serializeSearch
} from "c/arcNavTrailState";

const LIST_CRUMB_KEY = "list";
const GROUP_CRUMB_KEY = "group";

/**
 * Objects whose display name is not on a field called Name. In nav-trail mode
 * nobody passes `nameField`, so it falls back to "Name" — which Task and Case
 * do not have. The getRecord wire then returned nothing and the crumb printed
 * the raw 18-character id ("Work > Tasks > 00TVF00000OKzG92AL").
 */
const RECORD_NAME_FIELDS = {
  Task: "Subject",
  Case: "Subject"
};

const PARENT_CRUMB_KEY = "parent";

/**
 * Records whose trail should run through their parent rather than through the
 * flat list they happen to live in. A task is always reached as part of
 * something — open one from a case and "back" has to mean that case, not every
 * task in the org.
 */
const PARENT_LOOKUP_FIELDS = {
  Task: "WhatId"
};

/**
 * WhatId is polymorphic, so the parent's object comes from its key prefix.
 * Only the two this site can actually route back to are listed; a task hung
 * off anything else keeps the plain list trail rather than offering a crumb
 * that leads nowhere.
 */
const PARENT_OBJECT_BY_KEY_PREFIX = {
  500: "Case",
  "001": "Account"
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

  /*
   * Set on a route that no stored trail describes -- see isOffNavRoute. Held
   * separately from _navTrail because the trail itself stays in session storage
   * on purpose: leaving Settings for a nav destination should not have to
   * rebuild it.
   */
  _offNavRoute = false;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    this.refreshNavTrail();
    this.syncRecordIdFromContext();
  }

  @wire(getRecord, {
    recordId: "$_recordId",
    fields: "$recordFields",
    optionalFields: "$recordOptionalFields"
  })
  wiredRecord;

  @wire(getRecord, { recordId: "$parentRecordId", fields: "$parentNameFields" })
  wiredParentRecord;

  connectedCallback() {
    ensureDiversifyStyles(this).catch(() => {
      // Parent shells may already load the sheet.
    });
    this.refreshNavTrail();
    this.syncRecordIdFromContext();

    /*
     * The two events mean different things and must not be handled the same
     * way.
     *
     * A trail change says someone has just decided what the trail is —
     * arcNavigation records the clicked item before it navigates. Re-deriving
     * the trail from the URL at that moment reads the page being left, and
     * wrote it straight back over the selection: clicking Home recorded Home,
     * this listener immediately restored Tasks, and the old breadcrumb stayed
     * until a second click, by which time the URL had caught up. So a trail
     * change is adopted as given.
     *
     * A path change says the location moved, which is exactly when the trail
     * does need re-deriving.
     */
    this._onNavTrailChange = () => {
      this.adoptStoredNavTrail();
    };
    this._onNavPathChange = () => {
      this.refreshNavTrail();
    };
    window.addEventListener(NAV_TRAIL_CHANGE_EVENT, this._onNavTrailChange);
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);
  }

  disconnectedCallback() {
    window.removeEventListener(NAV_TRAIL_CHANGE_EVENT, this._onNavTrailChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);
  }

  /** Takes the stored trail as it stands, without consulting the URL. */
  adoptStoredNavTrail() {
    this._navTrail = readNavTrail();
    this._offNavRoute = false;
  }

  refreshNavTrail() {
    const pathname = resolveCurrentPath(this._pageRef);
    const search = serializeSearch(resolveCurrentQueryParams(this._pageRef));
    const syncedTrail = syncNavTrailFromLocation(
      pathname,
      search,
      this._pageRef
    );

    this._offNavRoute = isOffNavRoute(pathname, search, this._pageRef);
    this._navTrail = syncedTrail || readNavTrail();
  }

  get activeTrail() {
    if (this._offNavRoute) {
      return null;
    }

    return this._navTrail || readNavTrail();
  }

  get activeListLabel() {
    return this.activeTrail?.label || this.listLabel;
  }

  get activeListPath() {
    return this.activeTrail?.path || this.listPath;
  }

  get activeObjectApiName() {
    return this.activeTrail?.objectApiName || this.objectApiName;
  }

  get activeGroupLabel() {
    return this.activeTrail?.groupLabel || "";
  }

  get activeGroupPath() {
    return this.activeTrail?.groupPath || "";
  }

  /** Skipped when the group *is* the list (e.g. "Work" list item itself). */
  get hasDistinctGroup() {
    return Boolean(
      this.activeGroupLabel && this.activeGroupLabel !== this.activeListLabel
    );
  }

  get groupCrumb() {
    if (!this.hasDistinctGroup) {
      return null;
    }

    return {
      label: this.activeGroupLabel,
      key: this.activeGroupPath ? GROUP_CRUMB_KEY : undefined,
      muted: true
    };
  }

  /**
   * The group crumb for a trail that runs through a parent record.
   *
   * It has to come from the parent's own nav entry, not the record's. A task
   * hung off an account goes back through All Contacts, which lives under
   * Contacts — pairing it with the task's own group produced "Work › All
   * Contacts", two halves of different trails. A group that repeats its list
   * ("Work" above "Work") is dropped, the same rule hasDistinctGroup applies.
   */
  get parentGroupCrumb() {
    const trail = this.parentListTrail;
    if (!trail?.groupLabel || trail.groupLabel === trail.label) {
      return null;
    }

    return {
      label: trail.groupLabel,
      key: trail.groupPath ? GROUP_CRUMB_KEY : undefined,
      muted: true
    };
  }

  /** The group a click on the group crumb navigates to. */
  get effectiveGroupPath() {
    return this.parentDisplayName
      ? this.parentListTrail?.groupPath || ""
      : this.activeGroupPath;
  }

  /** An explicitly configured nameField still wins over the map. */
  get resolvedNameField() {
    const objectApiName = this.activeObjectApiName;
    if (this.nameField && this.nameField !== "Name") {
      return this.nameField;
    }
    return RECORD_NAME_FIELDS[objectApiName] || this.nameField;
  }

  get recordFields() {
    if (
      !this._recordId ||
      !this.activeObjectApiName ||
      !this.resolvedNameField
    ) {
      return [];
    }

    return [`${this.activeObjectApiName}.${this.resolvedNameField}`];
  }

  /* ---- Parent record (Task -> its Case) --------------------------------- */

  get parentLookupField() {
    return PARENT_LOOKUP_FIELDS[this.activeObjectApiName] || "";
  }

  get recordOptionalFields() {
    const field = this.parentLookupField;
    if (!field || !this._recordId || !this.activeObjectApiName) {
      return [];
    }
    return [`${this.activeObjectApiName}.${field}`];
  }

  get parentRecordId() {
    const fields = this.recordOptionalFields;
    if (!fields.length || !this.wiredRecord?.data) {
      return null;
    }

    const value = getFieldValue(this.wiredRecord.data, fields[0]);
    if (!value) {
      return null;
    }

    return PARENT_OBJECT_BY_KEY_PREFIX[String(value).slice(0, 3)]
      ? value
      : null;
  }

  get parentObjectApiName() {
    const recordId = this.parentRecordId;
    return recordId
      ? PARENT_OBJECT_BY_KEY_PREFIX[String(recordId).slice(0, 3)] || ""
      : "";
  }

  get parentNameFields() {
    const objectApiName = this.parentObjectApiName;
    if (!objectApiName || !this.parentRecordId) {
      return [];
    }
    return [`${objectApiName}.${RECORD_NAME_FIELDS[objectApiName] || "Name"}`];
  }

  get parentDisplayName() {
    const fields = this.parentNameFields;
    if (!fields.length || !this.wiredParentRecord?.data) {
      return "";
    }
    return getFieldValue(this.wiredParentRecord.data, fields[0]) || "";
  }

  /** The parent's own list, so the first crumb matches the parent's home. */
  get parentListTrail() {
    return this.parentDisplayName
      ? findDefaultListTrail(this.parentObjectApiName)
      : null;
  }

  get recordDisplayName() {
    if (!this.recordFields.length || !this.wiredRecord?.data) {
      return "";
    }

    return getFieldValue(this.wiredRecord.data, this.recordFields[0]) || "";
  }

  get usesDynamicTrail() {
    return (
      (!Array.isArray(this.items) || this.items.length === 0) &&
      Boolean(this.activeListLabel && this.activeObjectApiName)
    );
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

  get hasItems() {
    return this.resolvedItems.length > 0;
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
        linkClass: buildLinkClass({ muted: isMuted })
      };
    });
  }

  syncRecordIdFromContext() {
    const resolved = resolveRecordIdFromPageReference(
      this._pageRef,
      this.activeObjectApiName
    );

    this._recordId = resolved || null;
  }

  buildDynamicItems() {
    const listLabel = this.activeListLabel;
    const groupCrumb = this.groupCrumb;

    if (!this._recordId) {
      const crumbs = groupCrumb ? [groupCrumb] : [];
      return [...crumbs, { label: listLabel, current: true }];
    }

    const recordName = this.recordDisplayName;
    const listCrumb = { label: listLabel, key: LIST_CRUMB_KEY, muted: true };
    const crumbs = groupCrumb ? [groupCrumb, listCrumb] : [listCrumb];

    if (this.wiredRecord?.loading && !recordName) {
      return [...crumbs, { label: "Loading…", current: true }];
    }

    // An unresolved name means the list crumb stands alone. A raw record id
    // is not a breadcrumb — it tells the user nothing and reads as a bug.
    if (!recordName) {
      const emptyCrumbs = groupCrumb ? [groupCrumb] : [];
      return [...emptyCrumbs, { label: listLabel, current: true }];
    }

    // A record with a parent leads back through it. Opening a task from a
    // case and finding "back" points at every task in the org loses the one
    // piece of context the user was working in.
    const parentName = this.parentDisplayName;
    if (parentName) {
      // The parent's list, not the record's: a task under a case goes back to
      // the case list, and a task under an account to All Contacts. The group
      // comes from the same place for the same reason.
      const parentListLabel = this.parentListTrail?.label || listLabel;
      const parentGroup = this.parentGroupCrumb;
      const parentCrumbs =
        parentGroup && parentGroup.label !== parentListLabel
          ? [parentGroup]
          : [];
      return [
        ...parentCrumbs,
        {
          label: parentListLabel,
          key: LIST_CRUMB_KEY,
          muted: true
        },
        { label: parentName, key: PARENT_CRUMB_KEY, muted: true },
        { label: recordName, current: true }
      ];
    }

    return [...crumbs, { label: recordName, current: true }];
  }

  buildStaticItems() {
    const crumbs = [];

    if (this.parentLabel) {
      crumbs.push({
        label: this.parentLabel,
        key: this.parentKey || undefined,
        muted: true
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

    if (key === PARENT_CRUMB_KEY) {
      const reference = buildRecordNavigationReference(
        this.parentRecordId,
        this.parentObjectApiName
      );
      if (reference) {
        this[NavigationMixin.Navigate](reference);
      }
      return;
    }

    // With a parent in the trail the first crumb is the parent's list, so it
    // has to navigate there rather than to the record's own list.
    const listPath = this.parentListTrail?.path || this.activeListPath;

    if (key === LIST_CRUMB_KEY && listPath) {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: listPath }
      });
      return;
    }

    const groupPath = this.effectiveGroupPath;

    if (key === GROUP_CRUMB_KEY && groupPath) {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: groupPath }
      });
      return;
    }

    this.dispatchEvent(
      new CustomEvent("crumbselect", {
        detail: { key },
        bubbles: true,
        composed: true
      })
    );
  }
}