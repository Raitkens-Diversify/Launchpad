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
 *     ArcRelatedListController.getRelatedRecordsPage in PAGE_SIZE=100
 *     batches instead of that component's fixed 10-row card default. The
 *     first batch loads via @wire; paging past it fetches the next batch on
 *     demand through arcDataTable's own hasMoreRows/loadmore mechanism (see
 *     handleRelatedProductsLoadMore) -- real server pagination, not a single
 *     capped fetch, since one product held across more than 100 financial
 *     accounts is a real case (confirmed live: a 147-holding product loaded
 *     only its first 100 before this).
 *     Columns match the CRM reference's own Related Products related list
 *     exactly (Related Product Name, Financial Account, Case). Clicking the
 *     name opens c/arcRelatedProductQuickView, a popup showing/editing that
 *     one record, instead of navigating to a full page -- arcDataTable's
 *     cancelable rownavigate event (see handleRelatedProductRowNavigate) is
 *     what makes that interception possible without arcDataTable itself
 *     knowing anything about popups.
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
 * were requested, not keyed by name. Matches the reference CRM record page's
 * own "Related Products" related list columns exactly (NAME,
 * Financial_Account__c, Case__c) -- Financial_Account__c itself points at the
 * wrong (unused FSC) object, so Wizard_Financial_Account__r.Name is used
 * here instead, same substitution already established for this exact object
 * in arcCaseDetail's own Related Products card.
 */
const RELATED_PRODUCTS_FIELD_PATHS = [
  "Name",
  "Wizard_Financial_Account__r.Name",
  "Case__r.CaseNumber"
];
/**
 * c/arcDataTable's own column shape -- see arcCaseDetail's TASK_COLUMNS for
 * the same pattern. isLink on the first column opens
 * c-arc-related-product-quick-view instead of navigating -- see
 * handleRelatedProductRowNavigate, which intercepts arcDataTable's
 * cancelable rownavigate event.
 */
const RELATED_PRODUCTS_COLUMNS = [
  { label: "Related Product Name", fieldName: "name", isLink: true },
  { label: "Financial Account", fieldName: "financialAccount" },
  { label: "Case", fieldName: "caseNumber" }
];
/** Rows per server fetch -- MAX_PAGE_SIZE on the Apex side. Additional
 * batches are fetched on demand via arcDataTable's own loadmore event (see
 * handleRelatedProductsLoadMore) once the reader pages past what's loaded,
 * so a product held across more than one batch's worth of accounts is not
 * silently truncated. */
const RELATED_PRODUCTS_PAGE_SIZE = 100;

/** Apex hands cells back as a positional array; this is the one place that order is named. */
const mapRelatedProductRows = (rows) =>
  (rows || []).map((row) => ({
    id: row.id,
    name: row.cells?.[0] ?? "",
    financialAccount: row.cells?.[1] ?? "",
    caseNumber: row.cells?.[2] ?? ""
  }));

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
  relatedProductsHasMore = false;
  isLoadingMoreRelatedProducts = false;
  _relatedProductsRequested = false;
  _relatedProductsLoaded = false;
  /** Where the next loadmore fetch should pick up -- advances by RELATED_PRODUCTS_PAGE_SIZE each batch. */
  _relatedProductsOffset = 0;

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
      this.relatedProductsRows = mapRelatedProductRows(data.rows);
      this.relatedProductsHasMore = data.hasMore === true;
      this._relatedProductsOffset = RELATED_PRODUCTS_PAGE_SIZE;
      this.relatedProductsError = undefined;
    } else if (error) {
      this._relatedProductsLoaded = true;
      this.relatedProductsRows = [];
      this.relatedProductsHasMore = false;
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

  /**
   * arcDataTable's cancelable rownavigate event (fires instead of navigating
   * when preventDefault() is called) -- opens the quick-view popup instead
   * of a full page navigation, per explicit request.
   */
  handleRelatedProductRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (!recordId) {
      return;
    }
    this.refs.relatedProductQuickView?.open(recordId);
  }

  /**
   * arcDataTable's own loadmore event -- fires when the reader pages past
   * what's currently loaded while hasMoreRows is true (same mechanism
   * arcRecordListView's own server search uses). Fetches the next
   * RELATED_PRODUCTS_PAGE_SIZE batch and appends it, rather than replacing
   * what's already on screen.
   */
  async handleRelatedProductsLoadMore() {
    if (this.isLoadingMoreRelatedProducts || !this.relatedProductsHasMore) {
      return;
    }

    this.isLoadingMoreRelatedProducts = true;

    try {
      const result = await getRelatedRecordsPage({
        recordId: this.recordId,
        objectApiName: RELATED_PRODUCTS_OBJECT_API_NAME,
        parentFieldApiName: "Product__c",
        fieldApiNames: RELATED_PRODUCTS_FIELD_PATHS,
        linkFieldApiName: null,
        offsetValue: this._relatedProductsOffset,
        pageSize: RELATED_PRODUCTS_PAGE_SIZE
      });
      this.relatedProductsRows = [
        ...this.relatedProductsRows,
        ...mapRelatedProductRows(result?.rows)
      ];
      this._relatedProductsOffset += RELATED_PRODUCTS_PAGE_SIZE;
      this.relatedProductsHasMore = result?.hasMore === true;
    } catch (error) {
      this.relatedProductsError =
        error?.body?.message || "Unable to load more related products right now.";
    } finally {
      this.isLoadingMoreRelatedProducts = false;
    }
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