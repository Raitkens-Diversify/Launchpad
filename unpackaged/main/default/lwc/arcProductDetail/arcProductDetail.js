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
 *     hold this product", not "similar products" (Wizard_Financial_Account__c
 *     is the lookup to our own Financial_Account__c; the field literally
 *     named Financial_Account__c on that object points at the unrelated FSC
 *     managed-package object instead). Rendered as a full-width, collapsible
 *     c/arcDataTable -- the same table every other ARC list uses, per
 *     explicit request, rather than c/arcRelatedList's plain table -- fed by
 *     one batched fetch through ArcRelatedListController.getRelatedRecordsPage
 *     (a generous single page, paginated from there client-side by
 *     arcDataTable's own pager) instead of that component's fixed 10-row
 *     card default: a product can be held across many financial accounts.
 *   - History: the flexipage's own History tab (relatedListApiName
 *     "Histories" = standard field-history tracking), rendered as its own
 *     card in the right rail rather than a tab, per explicit request.
 *     Fetched through ArcCaseFeedController.getRecordHistory, which already
 *     takes an objectApiName parameter and resolves Product__c ->
 *     Product__History generically -- built for Case but never made
 *     Case-only. Rendered with this component's own markup rather than
 *     reusing c/arcCaseFeedTabs directly: that component hardcodes a
 *     Case-only Feed tab and a "Case History" label, and is under active,
 *     unrelated concurrent development this same day.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getRecordHistory from "@salesforce/apex/ArcCaseFeedController.getRecordHistory";
import getRelatedRecordsPage from "@salesforce/apex/ArcRelatedListController.getRelatedRecordsPage";

const OBJECT_API_NAME = "Product__c";

const RELATED_PRODUCTS_OBJECT_API_NAME = "Financial_Account_Related_Product__c";
/**
 * Positional order matters -- ArcRelatedListController.getRelatedRecordsPage
 * returns each row's values as a plain cells[] array in the same order these
 * were requested, not keyed by name.
 */
const RELATED_PRODUCTS_FIELD_PATHS = [
  "Wizard_Financial_Account__r.Name",
  "Household__c",
  "Primary_Owner__c",
  "Amount__c",
  "CreatedDate"
];
/** c/arcDataTable's own column shape -- see arcCaseDetail's TASK_COLUMNS for the same pattern. */
const RELATED_PRODUCTS_COLUMNS = [
  { label: "Financial Account", fieldName: "financialAccount", isLink: true },
  { label: "Household", fieldName: "household" },
  { label: "Owner", fieldName: "owner" },
  { label: "Amount", fieldName: "amount", type: "currency" },
  { label: "Created", fieldName: "created", type: "date" }
];
/** Fetched once, then paginated client-side by c/arcDataTable's own pager --
 * MAX_PAGE_SIZE on the Apex side, generous enough that "load more" clicking
 * isn't needed for the realistic range of accounts holding one product. */
const RELATED_PRODUCTS_PAGE_SIZE = 100;

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

export default class ArcProductDetail extends LightningElement {
  recordId;
  errorMessage;

  history;
  historyError;
  _historyRequested = false;
  _record;

  relatedProductsRows = [];
  relatedProductsError;
  _relatedProductsRequested = false;
  _relatedProductsLoaded = false;

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

  @wire(getRelatedRecordsPage, {
    recordId: "$recordId",
    objectApiName: RELATED_PRODUCTS_OBJECT_API_NAME,
    parentFieldApiName: "Product__c",
    fieldApiNames: RELATED_PRODUCTS_FIELD_PATHS,
    linkFieldApiName: null,
    offsetValue: 0,
    pageSize: RELATED_PRODUCTS_PAGE_SIZE
  })
  wiredRelatedProducts({ data, error }) {
    this._relatedProductsRequested = true;
    if (data) {
      this._relatedProductsLoaded = true;
      this.relatedProductsRows = (data.rows || []).map((row) => ({
        id: row.id,
        financialAccount: row.cells?.[0] ?? "",
        household: row.cells?.[1] ?? "",
        owner: row.cells?.[2] ?? "",
        amount: row.cells?.[3] ?? "",
        created: row.cells?.[4] ?? ""
      }));
      this.relatedProductsError = undefined;
    } else if (error) {
      this._relatedProductsLoaded = true;
      this.relatedProductsRows = [];
      this.relatedProductsError =
        "Unable to load related products right now.";
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

  // ---- Related Products (full-width table) --------------------------------

  get relatedProductsColumns() {
    return RELATED_PRODUCTS_COLUMNS;
  }

  get relatedProductsObjectApiName() {
    return RELATED_PRODUCTS_OBJECT_API_NAME;
  }

  get isRelatedProductsLoading() {
    return (
      this._relatedProductsRequested &&
      Boolean(this.recordId) &&
      !this._relatedProductsLoaded
    );
  }

  // ---- History (right-side card) ------------------------------------------

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