/**
 * Rich Product (Approved Products) detail page for Experience sites, built the
 * same way arcCaseDetail was: read the real Lightning record page rather than
 * guess, then reproduce what it shows.
 *
 * Structure and field lists come from ProductRecordPageAdvisors.flexipage --
 * retrieved and parsed directly, not eyeballed off a screenshot:
 *   - Highlights/key facts: the fields the platform's highlightsPanel would
 *     show for this object (Name, Status, Performance Status, Asset Category/
 *     Class, Sponsor, Date Approved).
 *   - General Information / Sponsor Information: the flexipage's own two
 *     always-shown field sections (every other section there -- 1031-DST/TIC
 *     Details, Private Real Estate Details, Public Non-Traded Fund Details,
 *     Waterfall, etc. -- only shows for specific Asset_Subclass__c values; out
 *     of scope for this round per explicit decision).
 *   - Related Products: the flexipage's own related list, Financial_Account_
 *     Related_Product__c filtered on Product__c -- "which financial accounts
 *     hold this product", not "similar products". Rendered with c/
 *     arcRelatedList, already generic and already used this way elsewhere
 *     (arcCaseDetail's own "Related Products" card, from Case's side of the
 *     same object).
 *   - History: the flexipage's own History tab (relatedListApiName
 *     "Histories" = standard field-history tracking). Fetched through
 *     ArcCaseFeedController.getRecordHistory, which already takes an
 *     objectApiName parameter and resolves Product__c -> Product__History
 *     generically -- built for Case but never made Case-only. A new,
 *     Product-scoped tabs component (rather than reusing c/arcCaseFeedTabs
 *     directly) both to drop its Case-only Feed tab and its hardcoded "Case
 *     History" label, and to avoid touching a component under active,
 *     unrelated concurrent development this same day.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getRecordHistory from "@salesforce/apex/ArcCaseFeedController.getRecordHistory";

const OBJECT_API_NAME = "Product__c";

const HEADER_FIELDS = [
  "Product__c.Name",
  "Product__c.Status__c",
  "Product__c.Performance_Status__c",
  "Product__c.Asset_Category__c",
  "Product__c.Asset_Class__c",
  "Product__c.Sponsor__c",
  "Product__c.Date_Approved__c"
];

/** The flexipage's "General Information" section, Name aside (already the header title). */
const GENERAL_INFO_FIELDS = [
  "Investment_Type__c",
  "Anticipated_Hold_Period__c",
  "Asset_Category__c",
  "Asset_Class__c",
  "Asset_Subclass__c",
  "Status__c",
  "Date_Approved__c",
  "Date_of_Last_Review__c",
  "Current_Distribution__c",
  "Current_NAV__c",
  "Life_Cycle_Status__c",
  "Performance_Status__c",
  "Accreditation_Status__c"
];

/** The flexipage's "Sponsor Information" section, field-for-field. */
const SPONSOR_INFO_FIELDS = [
  "Sponsor__c",
  "Website__c",
  "Contact__c",
  "Email_Address__c",
  "Phone_Number__c"
];

/**
 * Same semantic red/yellow/green mapping as arcRecordListView's
 * SEMANTIC_PILL_TONES -- Performance_Status__c's own picklist already
 * defines these colors in Setup, mirrored here rather than duplicated via
 * import since this component doesn't otherwise depend on arcRecordListView.
 */
const PERFORMANCE_STATUS_TONES = {
  "Under Performing": "red",
  "Watch List": "yellow",
  Performing: "green"
};

const TAB_HISTORY = "history";
const TAB_RELATED_PRODUCTS = "relatedProducts";

export default class ArcProductDetail extends LightningElement {
  activeTab = TAB_HISTORY;

  recordId;
  errorMessage;

  history;
  historyError;
  _historyRequested = false;
  _record;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const resolved = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
    if (resolved && resolved !== this.recordId) {
      this.recordId = resolved;
    }
  }

  @wire(getRecord, { recordId: "$recordId", fields: HEADER_FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this._record = data;
      this.errorMessage = undefined;
    } else if (error) {
      this._record = undefined;
      this.errorMessage =
        error?.body?.message || "Unable to load this product right now.";
    }
  }

  @wire(getRecordHistory, {
    recordId: "$recordId",
    objectApiName: OBJECT_API_NAME,
    pageSize: 20
  })
  wiredHistory({ data, error }) {
    this._historyRequested = true;
    if (data) {
      this.history = data;
      this.historyError = undefined;
    } else if (error) {
      this.history = undefined;
      this.historyError = "Unable to load the history for this record.";
    }
  }

  get isLoading() {
    return !this._record && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._record);
  }

  fieldValue(apiName) {
    return this._record
      ? getFieldValue(this._record, `${OBJECT_API_NAME}.${apiName}`)
      : undefined;
  }

  get productName() {
    return this.fieldValue("Name");
  }

  get statusValue() {
    return this.fieldValue("Status__c");
  }

  get hasStatus() {
    return Boolean(this.statusValue);
  }

  get performanceStatusValue() {
    return this.fieldValue("Performance_Status__c");
  }

  get hasPerformanceStatus() {
    return Boolean(this.performanceStatusValue);
  }

  get performanceStatusClass() {
    const tone = PERFORMANCE_STATUS_TONES[this.performanceStatusValue];
    return tone
      ? `arc-product-detail__badge arc-product-detail__badge--${tone}`
      : "arc-product-detail__badge";
  }

  get assetCategoryValue() {
    return this.fieldValue("Asset_Category__c");
  }

  get hasAssetCategory() {
    return Boolean(this.assetCategoryValue);
  }

  get assetClassValue() {
    return this.fieldValue("Asset_Class__c");
  }

  get hasAssetClass() {
    return Boolean(this.assetClassValue);
  }

  get sponsorValue() {
    return this.fieldValue("Sponsor__c");
  }

  get hasSponsor() {
    return Boolean(this.sponsorValue);
  }

  get dateApprovedValue() {
    return this.fieldValue("Date_Approved__c");
  }

  get hasDateApproved() {
    return Boolean(this.dateApprovedValue);
  }

  get generalInfoFields() {
    return GENERAL_INFO_FIELDS;
  }

  get sponsorInfoFields() {
    return SPONSOR_INFO_FIELDS;
  }

  get objectApiName() {
    return OBJECT_API_NAME;
  }

  // ---- Left-column tabs: History / Related Products ----------------------

  get tabs() {
    return [
      { value: TAB_HISTORY, label: "History" },
      { value: TAB_RELATED_PRODUCTS, label: "Related Products" }
    ];
  }

  handleTabChange(event) {
    this.activeTab = event.detail.value;
  }

  get showHistory() {
    return this.activeTab === TAB_HISTORY;
  }

  get showRelatedProducts() {
    return this.activeTab === TAB_RELATED_PRODUCTS;
  }

  /**
   * Date, Field, User, Original Value, New Value -- the same shape and the
   * same "keep blanks, they're information" rule as arcCaseFeedTabs' own
   * history rendering (a creation entry has no old value, and that absence
   * is exactly what Lightning's own history card shows too).
   */
  get historyEntries() {
    return (this.history?.entries || []).map((entry) => ({
      id: entry.id,
      createdDate: entry.createdDate,
      actorName: entry.actorName || "Unknown user",
      fieldLabel: entry.fieldLabel,
      oldValue: entry.oldValue,
      newValue: entry.newValue
    }));
  }

  get hasHistory() {
    return this.historyEntries.length > 0;
  }

  get historyCount() {
    return this.historyEntries.length;
  }

  get historyHasMore() {
    return Boolean(this.history?.hasMore);
  }

  get isHistoryLoading() {
    return (
      this._historyRequested &&
      Boolean(this.recordId) &&
      !this.history &&
      !this.historyError
    );
  }

  get showHistoryEmpty() {
    return (
      this._historyRequested &&
      !this.isHistoryLoading &&
      !this.historyError &&
      !this.hasHistory
    );
  }
}