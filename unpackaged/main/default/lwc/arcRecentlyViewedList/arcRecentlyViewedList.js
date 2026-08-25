/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import { refreshApex } from "@salesforce/apex";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import ARC_ICONS from "@salesforce/resourceUrl/arcicon";
import getRecentlyViewedItems from "@salesforce/apex/ArcRecentlyViewedListController.getRecentlyViewedItems";
import {
  buildRecordNavigationReference,
  resolveRecordUrl,
  shouldAllowNativeRecordNavigation
} from "c/recordNavigationUtils";
import { NAV_PATH_CHANGE_EVENT } from "c/arcNavTrailState";

const LIST_TYPE_CONTACT = "Contact";
const LIST_TYPE_ISA = "ISA";
const ACCOUNT_OBJECT_API_NAME = "Account";
const RECENTLY_VIEWED_MAX = 200;
/** Home dashboard cards always show a fixed top-N, never expand in place. */
const HOME_CARD_DISPLAY_LIMIT = 10;
/* Row box and the list's flex gap; see .arc-recently-viewed__item / __list. */
const ROW_HEIGHT_PX = 40;
const ROW_GAP_PX = 16;
/** Full list view targets for the "View All" link — same routes as the nav rail. */
const ALL_CONTACTS_LIST_PATH = "/account/Account/Default?c__tabId=tab1";
const ALL_ISAS_LIST_PATH = "/financial-account/Financial_Account__c/Default";

const INFO_ICON_FILE = "info.svg";
const OVERFLOW_ICON_FILE = "dots-three-vertical.svg";
const CARET_RIGHT_ICON_FILE = "caret-right.svg";
const DEFAULT_ICON_FILE = "user.svg";
const ISA_ICON_FILE = "notebook.svg";
const CONTACT_ICON_COLOR = "var(--div-color-success-dark, #16a34a)";
const ISA_ICON_COLOR = "var(--div-color-blue-700, #1a76bb)";

// Figma node 760:127144 — every row icon in the Contacts card is green
// regardless of record type (person/business/trust/estate/household/plan
// just change the glyph, never the color); every row icon in the ISA card
// is the same blue Notebook glyph.
const ICON_BY_RECORD_TYPE = Object.freeze({
  personaccount: "user.svg",
  person_account: "user.svg",
  business: "building-office.svg",
  business_account: "building-office.svg",
  industriesbusiness: "building-office.svg",
  trust: "shield.svg",
  industriesinstitution: "shield.svg",
  estate: "scroll.svg",
  household: "house.svg",
  industrieshousehold: "house.svg",
  retirement_plan: "piggy-bank.svg",
  "retirement plan": "piggy-bank.svg"
});

const buildIconUrl = (iconFile) => {
  return iconFile ? `${ARC_ICONS}/${iconFile}` : null;
};

const resolveIconColor = (listType) => {
  return listType === LIST_TYPE_ISA ? ISA_ICON_COLOR : CONTACT_ICON_COLOR;
};

const buildIconStyle = (iconFile, listType) => {
  const iconUrl = buildIconUrl(iconFile);

  if (!iconUrl) {
    return null;
  }

  return `--icon-url: url('${iconUrl}'); --icon-color: ${resolveIconColor(listType)};`;
};

const normalizeRecordTypeKey = (recordTypeDeveloperName) =>
  String(recordTypeDeveloperName || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");

const resolveIconFile = (recordTypeDeveloperName, listType) => {
  if (listType === LIST_TYPE_ISA) {
    return ISA_ICON_FILE;
  }

  const normalizedKey = normalizeRecordTypeKey(recordTypeDeveloperName);

  if (normalizedKey.includes("retirement") && normalizedKey.includes("plan")) {
    return "piggy-bank.svg";
  }

  if (ICON_BY_RECORD_TYPE[normalizedKey]) {
    return ICON_BY_RECORD_TYPE[normalizedKey];
  }

  return DEFAULT_ICON_FILE;
};

export default class ArcRecentlyViewedList extends NavigationMixin(
  LightningElement
) {
  @api listType = LIST_TYPE_CONTACT;
  @api displayLimit = HOME_CARD_DISPLAY_LIMIT;

  title = "";
  objectApiName = "";
  totalCount = 0;
  listItems = [];
  errorMessage = "";
  isInitialLoading = true;
  _stylesLoaded = false;
  _activeListType = LIST_TYPE_CONTACT;
  _wiredRecentlyViewedResult;
  _onNavPathChange;

  get infoIconStyle() {
    return `--icon-url: url('${buildIconUrl(INFO_ICON_FILE)}');`;
  }

  get overflowIconStyle() {
    return `--icon-url: url('${buildIconUrl(OVERFLOW_ICON_FILE)}');`;
  }

  get caretIconStyle() {
    return `--icon-url: url('${buildIconUrl(CARET_RIGHT_ICON_FILE)}');`;
  }

  get recordNavigationObjectApiName() {
    if (this.listType === LIST_TYPE_CONTACT) {
      return ACCOUNT_OBJECT_API_NAME;
    }

    return this.objectApiName;
  }

  /** Home cards always show a fixed top-N; never expands in place. */
  get wireDisplayLimit() {
    return Math.min(
      this.displayLimit || HOME_CARD_DISPLAY_LIMIT,
      RECENTLY_VIEWED_MAX
    );
  }

  get viewAllUrl() {
    return this.listType === LIST_TYPE_ISA
      ? ALL_ISAS_LIST_PATH
      : ALL_CONTACTS_LIST_PATH;
  }

  connectedCallback() {
    /*
     * getRecentlyViewedItems is cacheable, so returning to Home after
     * viewing a record serves the stale wire-service cache rather than a
     * fresh Apex call — a plain page reload is the only thing that used to
     * fix it. patchHistoryForNavigation (already wired up by arcNavigation)
     * dispatches this event right after any pushState/replaceState, which
     * covers exactly that "navigated back to Home" moment.
     */
    this._onNavPathChange = () => {
      this.refreshRecentlyViewedItems();
    };
    window.addEventListener("popstate", this._onNavPathChange);
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);

    if (this._stylesLoaded) {
      return;
    }

    this._stylesLoaded = true;
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error(
        "[arcRecentlyViewedList] Failed to load diversifyStyles",
        error
      );
    });
  }

  disconnectedCallback() {
    window.removeEventListener("popstate", this._onNavPathChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);
  }

  refreshRecentlyViewedItems() {
    if (this._wiredRecentlyViewedResult) {
      refreshApex(this._wiredRecentlyViewedResult);
    }
  }

  @wire(getRecentlyViewedItems, {
    listType: "$listType",
    displayLimit: "$wireDisplayLimit"
  })
  wiredRecentlyViewedItems(value) {
    this._wiredRecentlyViewedResult = value;
    const { data, error } = value;
    this.isInitialLoading = false;

    this._activeListType = this.listType;

    if (error) {
      this.errorMessage =
        error?.body?.message || "Unable to load recently viewed records.";
      this.listItems = [];
      this.totalCount = 0;
      this.title = "";
      this.objectApiName = "";
      return;
    }

    this.errorMessage = "";
    this.title = data?.title || "";
    this.objectApiName = data?.objectApiName || "";
    this.totalCount = data?.totalCount || 0;

    const seenItemIds = new Set();
    this.listItems = (data?.items || [])
      .filter((item) => {
        if (!item?.id || seenItemIds.has(item.id)) {
          return false;
        }

        seenItemIds.add(item.id);
        return true;
      })
      .map((item) => this.decorateListItem(item));
    this.resolveRecordUrls(this.listItems);
  }

  decorateListItem(item) {
    const iconFile = resolveIconFile(
      item.recordTypeDeveloperName,
      this.listType
    );

    return {
      ...item,
      iconStyle: buildIconStyle(iconFile, this.listType),
      hasIcon: Boolean(iconFile),
      hasMetadata: Boolean(item.metadata),
      ariaLabel: item.metadata ? `${item.name}, ${item.metadata}` : item.name,
      recordUrl: "#",
      hasRecordLink: false
    };
  }

  async resolveRecordUrls(items) {
    const navigationObjectApiName = this.recordNavigationObjectApiName;

    if (!items?.length || !navigationObjectApiName) {
      return;
    }

    const urlEntries = await Promise.all(
      items.map(async (item) => {
        const recordUrl = await resolveRecordUrl(
          this,
          item.id,
          navigationObjectApiName
        );
        return [item.id, recordUrl];
      })
    );

    const recordUrlById = Object.fromEntries(
      urlEntries.filter(([, recordUrl]) => Boolean(recordUrl))
    );

    if (this._activeListType !== this.listType) {
      return;
    }

    this.listItems = this.listItems.map((item) => ({
      ...item,
      recordUrl: recordUrlById[item.id] || "#",
      hasRecordLink: Boolean(recordUrlById[item.id])
    }));
  }

  /**
   * Reserves the height of a full card's worth of rows, so two cards side by
   * side match even when one holds fewer records than the other.
   *
   * The earlier fix asked the card to grow as a flex item in its layout column,
   * which is correct and works on the published site — but Experience Builder's
   * preview wraps every component in a display:inline node of its own, and a
   * component cannot style or measure its way out of that (Lightning Web
   * Security blocks reaching outside its own tree). Reserving the space from
   * within is the one approach that holds in the builder, in live preview and
   * published alike. Kept in step with the row metrics in the stylesheet.
   */
  get listStyle() {
    const rows = this.resolvedDisplayLimit;
    return `min-height: ${rows * ROW_HEIGHT_PX + (rows - 1) * ROW_GAP_PX}px;`;
  }

  get resolvedDisplayLimit() {
    const limit = Number(this.displayLimit);
    return Number.isFinite(limit) && limit > 0
      ? limit
      : HOME_CARD_DISPLAY_LIMIT;
  }

  get hasItems() {
    return this.listItems.length > 0;
  }

  get footerLabel() {
    return `Showing ${this.listItems.length} of ${this.totalCount}`;
  }

  get showFooter() {
    return this.hasItems && Boolean(this.objectApiName);
  }

  get showViewAll() {
    return this.totalCount > this.listItems.length;
  }

  handleRowClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();

    const recordId = event.currentTarget.dataset.recordId;

    if (!recordId || !this.recordNavigationObjectApiName) {
      return;
    }

    this.navigateToRecord(recordId);
  }

  handleViewAllClick(event) {
    event.preventDefault();

    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: this.viewAllUrl }
    });
  }

  navigateToRecord(recordId) {
    const pageReference = buildRecordNavigationReference(
      recordId,
      this.recordNavigationObjectApiName
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }
}