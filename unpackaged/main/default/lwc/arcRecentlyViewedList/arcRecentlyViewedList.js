/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import ARC_ICONS from "@salesforce/resourceUrl/arcicon";
import getRecentlyViewedItems from "@salesforce/apex/ArcRecentlyViewedListController.getRecentlyViewedItems";
import {
  buildRecordNavigationReference,
  buildPublishedExperienceSiteUrl,
  resolveRecordUrl,
  shouldAllowNativeRecordNavigation,
} from "c/recordNavigationCommunityUtils";
import {
  ARC_NAV_ALL_CONTACTS_ID,
  findNavTargetById,
  recordNavSelection,
} from "c/arcNavTrailState";

const LIST_TYPE_CONTACT = "Contact";
const LIST_TYPE_ISA = "ISA";
const ACCOUNT_OBJECT_API_NAME = "Account";
const MAX_VISIBLE_ROWS = 10;

const DEFAULT_ICON_FILE = "person.svg";
const ISA_ICON_FILE = "notebook.svg";
const CONTACT_ICON_COLOR = "var(--div-color-success-dark, #16a34a)";
const ISA_ICON_COLOR = "var(--div-color-blue-700, #1a76bb)";

const ICON_BY_RECORD_TYPE = Object.freeze({
  personaccount: "person.svg",
  person_account: "person.svg",
  business: "business.svg",
  business_account: "business.svg",
  industriesbusiness: "business.svg",
  trust: "trust.svg",
  industriesinstitution: "trust.svg",
  estate: "estate.svg",
  household: "household.svg",
  diversify_related_person: "person.svg",
  industrieshousehold: "household.svg",
  retirement_plan: "401k.svg",
  "retirement plan": "401k.svg",
});

const buildIconUrl = (iconFile) =>
  iconFile ? `${ARC_ICONS}/${iconFile}` : null;

const resolveIconColor = (iconFile, listType) => {
  if (listType === LIST_TYPE_ISA || iconFile === ISA_ICON_FILE) {
    return ISA_ICON_COLOR;
  }

  return CONTACT_ICON_COLOR;
};

const buildIconStyle = (iconFile, listType) => {
  const iconUrl = buildIconUrl(iconFile);

  if (!iconUrl) {
    return null;
  }

  return `--icon-url: url('${iconUrl}'); --icon-color: ${resolveIconColor(iconFile, listType)};`;
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
    return "401k.svg";
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
  @api displayLimit;

  title = "";
  objectApiName = "";
  listItems = [];
  errorMessage = "";
  isInitialLoading = true;
  _stylesLoaded = false;
  _activeListType = LIST_TYPE_CONTACT;

  get recordNavigationObjectApiName() {
    if (this.listType === LIST_TYPE_CONTACT) {
      return ACCOUNT_OBJECT_API_NAME;
    }

    return this.objectApiName;
  }

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch((error) => {
        // eslint-disable-next-line no-console
        console.error(
          "[arcRecentlyViewedList] Failed to load diversifyStyles",
          error
        );
      });
    }

    this._activeListType = this.listType;
    this.loadRecentlyViewedItems();
  }

  renderedCallback() {
    if (this._activeListType === this.listType) {
      return;
    }

    this._activeListType = this.listType;
    this.loadRecentlyViewedItems();
  }

  async loadRecentlyViewedItems() {
    this.isInitialLoading = true;
    const requestedListType = this.listType;

    try {
      const data = await getRecentlyViewedItems({
        listType: requestedListType,
        displayLimit: MAX_VISIBLE_ROWS,
      });

      if (this.listType !== requestedListType) {
        return;
      }

      this.errorMessage = "";
      this.title = data?.title || "";
      this.objectApiName = data?.objectApiName || "";

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
    } catch (error) {
      if (this.listType !== requestedListType) {
        return;
      }

      this.errorMessage =
        error?.body?.message || "Unable to load recently viewed records.";
      this.listItems = [];
      this.title = "";
      this.objectApiName = "";
    } finally {
      if (this.listType === requestedListType) {
        this.isInitialLoading = false;
      }
    }
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

  get hasTitle() {
    return Boolean(this.title?.trim());
  }

  get showViewAllContacts() {
    if (this.isInitialLoading) {
      return false;
    }

    return this.listType === LIST_TYPE_CONTACT || !this.hasItems;
  }

  get viewAllContactsHref() {
    const navTarget = findNavTargetById(ARC_NAV_ALL_CONTACTS_ID);

    if (!navTarget?.target) {
      return "#";
    }

    return buildPublishedExperienceSiteUrl(navTarget.target);
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

  handleViewAllContactsClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();

    const navTarget = findNavTargetById(ARC_NAV_ALL_CONTACTS_ID);

    if (!navTarget?.target) {
      return;
    }

    recordNavSelection({
      id: navTarget.id,
      label: navTarget.label,
      path: navTarget.target,
      objectApiName: navTarget.objectApiName,
    });

    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: navTarget.target },
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