/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getRecentlyViewedItems from "@salesforce/apex/NexSRecentlyViewedListController.getRecentlyViewedItems";
import {
  resolveRecordUrl,
  shouldAllowNativeRecordNavigation
} from "c/recordNavigationUtils";
import {
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";

const LIST_TYPE_CONTACT = "Contact";
const LIST_TYPE_ISA = "ISA";
const ACCOUNT_OBJECT_API_NAME = "Account";
const DEFAULT_DISPLAY_LIMIT = 5;
const RECENTLY_VIEWED_MAX = 200;

const ICON_BY_RECORD_TYPE = Object.freeze({
  personaccount: "utility:user",
  person_account: "utility:user",
  business: "utility:company",
  business_account: "utility:company",
  industriesbusiness: "utility:company",
  trust: "utility:shield",
  industriesinstitution: "utility:shield",
  estate: "utility:scroll",
  household: "utility:home",
  industrieshousehold: "utility:home",
  retirement_plan: "utility:savings",
  "retirement plan": "utility:savings",
});

const normalizeRecordTypeKey = (recordTypeDeveloperName) =>
  String(recordTypeDeveloperName || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");

const resolveIconName = (recordTypeDeveloperName, listType) => {
  if (listType === LIST_TYPE_ISA) {
    return "utility:currency";
  }

  const normalizedKey = normalizeRecordTypeKey(recordTypeDeveloperName);

  if (normalizedKey.includes("retirement") && normalizedKey.includes("plan")) {
    return "utility:savings";
  }

  if (ICON_BY_RECORD_TYPE[normalizedKey]) {
    return ICON_BY_RECORD_TYPE[normalizedKey];
  }

  return "utility:record";
};

export default class NexSRecentlyViewedList extends NavigationMixin(
  LightningElement
) {
  @api listType = LIST_TYPE_CONTACT;
  @api displayLimit = DEFAULT_DISPLAY_LIMIT;

  title = "";
  objectApiName = "";
  totalCount = 0;
  listItems = [];
  errorMessage = "";
  isInitialLoading = true;
  isShowingAll = false;
  _stylesLoaded = false;
  _activeListType = LIST_TYPE_CONTACT;

  get recordNavigationObjectApiName() {
    if (this.listType === LIST_TYPE_CONTACT) {
      return ACCOUNT_OBJECT_API_NAME;
    }

    return this.objectApiName;
  }

  get wireDisplayLimit() {
    if (this.isShowingAll) {
      const totalCount = this.totalCount || RECENTLY_VIEWED_MAX;
      return Math.min(totalCount, RECENTLY_VIEWED_MAX);
    }

    return this.displayLimit || DEFAULT_DISPLAY_LIMIT;
  }

  connectedCallback() {
    if (this._stylesLoaded) {
      return;
    }

    this._stylesLoaded = true;
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error(
        "[nexSRecentlyViewedList] Failed to load diversifyStyles",
        error
      );
    });
  }

  @wire(getRecentlyViewedItems, {
    listType: "$listType",
    displayLimit: "$wireDisplayLimit",
  })
  wiredRecentlyViewedItems({ data, error }) {
    this.isInitialLoading = false;

    if (this._activeListType !== this.listType) {
      this.isShowingAll = false;
      this._activeListType = this.listType;
    }

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
    this.listItems = (data?.items || []).map((item) =>
      this.decorateListItem(item)
    );
    this.resolveRecordUrls(this.listItems);
  }

  decorateListItem(item) {
    return {
      ...item,
      iconName: resolveIconName(item.recordTypeDeveloperName, this.listType),
      hasMetadata: Boolean(item.metadata),
      ariaLabel: item.metadata
        ? `${item.name}, ${item.metadata}`
        : item.name,
      recordUrl: "#",
      hasRecordLink: false,
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
      hasRecordLink: Boolean(recordUrlById[item.id]),
    }));
  }

  get hasItems() {
    return this.listItems.length > 0;
  }

  get footerLabel() {
    return `Showing ${this.listItems.length} of ${this.totalCount}`;
  }

  get showViewAll() {
    return (
      !this.isShowingAll &&
      this.totalCount > this.listItems.length &&
      Boolean(this.objectApiName)
    );
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

    if (this.isShowingAll || this.totalCount <= this.listItems.length) {
      return;
    }

    this.isShowingAll = true;
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