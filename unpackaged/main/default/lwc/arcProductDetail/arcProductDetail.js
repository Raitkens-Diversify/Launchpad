/**
 * Rich Product (Approved Products) detail page for Experience sites, built the
 * same way arcCaseDetail was: read the real Lightning record page rather than
 * guess, then reproduce what it shows -- read-only.
 *
 * Structure, field lists and visibility rules come from the two internal
 * Product__c record pages, ProductRecordPageAdvisors.flexipage and
 * ProductRecordPageDueDiligence.flexipage (retrieved and parsed, not eyeballed
 * off a screenshot). Both pages share the same sections and the same
 * section-level visibility rules; the DD page is the one the home office
 * works from and is the reference for what is shown here:
 *   - Highlights/key facts: Name, Status, Performance Status, Asset Category/
 *     Class, Sponsor, Date Approved.
 *   - Details, in the flexipage's own order, each section gated exactly as the
 *     flexipage gates it (see SECTION_RULES):
 *       General Information            always
 *       Share Classes (related list)   Asset Category = Alternative Investment
 *       1031 - DST / TIC Details       Asset Subclass = 1031DST/TIC
 *       Fees and Expenses (1031)       Asset Subclass = 1031DST/TIC
 *       Private Real Estate Details    Asset Class = Private Real Estate and
 *                                      Subclass is neither Public Non-Traded
 *                                      Funds nor 1031DST/TIC
 *       Targeted Asset Class (PRE)     Asset Class = Private Real Estate
 *       Fees and Expenses (PRE)        Subclass != 1031DST/TIC and Alt Inv
 *       Public Non-Traded Fund Details Asset Subclass = Public Non-Traded Funds
 *       Waterfall (PRE)                Subclass != 1031DST/TIC and Alt Inv
 *     Field-level rules inside a section are the flexipage's too (Asset Class
 *     only for Alternative Investments, Date Approved only once not Pending,
 *     Redemption Details/Cap only when Redemption Feature = Yes, the two loan
 *     ratios only when not All-Cash). The Advisors page additionally hides any
 *     field that happens to be blank via *_Blank__c formula checkboxes; the DD
 *     page does not, and neither does this component -- a blank reads as a
 *     blank rather than silently disappearing.
 *   - Targeted Asset Class is eighteen checkboxes internally; here only the
 *     checked ones are listed (the Advisors page does the same via per-field
 *     "= true" rules), since a wall of unchecked boxes says nothing.
 *   - Waterfall: the internal page carries a Products_Waterfall_Order flow (a
 *     dual listbox that WRITES the order, gated to Due Diligence users). This
 *     page is read-only, so it renders the flow's result instead --
 *     Waterfall_Order_Ranked__c, the comma-separated ranked list the flow
 *     saves -- as a numbered list, plus Waterfall Description.
 *   - Monitoring Updates and Related Properties: the flexipage's two extra
 *     tabs (lst:dynamicRelatedList on Monitoring_Updates__r and
 *     DST_Properties__r), rendered as cards at the end of the main column
 *     with the same visibility rules as the tabs. The Files tab is an Egnyte
 *     component (third-party file store) with no Experience Cloud equivalent
 *     and is not reproduced.
 *   - Right rail, as on the internal page: Sponsor Information, Notes
 *     (Analyst Notes -- Internal Notes is deliberately left out: the Advisors
 *     page gates it to the Due Diligence permission / System Administrator,
 *     so it is not advisor-facing), and History.
 *   - Related Products: ARC's own addition (not on the DD page; the Advisors
 *     page has it for admins only) -- Financial_Account_Related_Product__c
 *     filtered on Product__c, "which financial accounts hold this product".
 *     Wizard_Financial_Account__c is the lookup to our own Financial_Account__c;
 *     the field literally named Financial_Account__c on that object points at
 *     the unrelated FSC managed-package object instead. Rendered as a
 *     full-width c/arcDataTable fed by ArcRelatedListController
 *     .getRelatedRecordsPage in PAGE_SIZE=100 batches with real server
 *     pagination (a 147-holding product exists). Clicking the name opens
 *     c/arcRelatedProductQuickView instead of navigating.
 *   - History: ArcCaseFeedController.getRecordHistory, which resolves
 *     Product__c -> Product__History generically.
 *
 * Every field section is a lightning-record-form in mode="readonly" -- no
 * inline-edit pencils regardless of the reader's edit rights. Field-level
 * security still applies: a field the reader cannot see is simply omitted by
 * the form, so a section can render fewer fields than listed here.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getRecordHistory from "@salesforce/apex/ArcCaseFeedController.getRecordHistory";
import getRelatedRecordsPage from "@salesforce/apex/ArcRelatedListController.getRelatedRecordsPage";

const OBJECT_API_NAME = "Product__c";

/*
 * Picklist values the flexipage visibility rules compare against, verbatim
 * from Product__c's own picklists (Asset_Category__c, Asset_Class__c,
 * Asset_Subclass__c, Status__c, Redemption_Feature__c, All_Cash__c).
 */
const ALTERNATIVE_INVESTMENT = "Alternative Investment";
const PRIVATE_REAL_ESTATE = "Private Real Estate";
const PRIVATE_CREDIT = "Private Credit";
const DST_TIC = "1031DST/TIC";
const PUBLIC_NON_TRADED_FUNDS = "Public Non-Traded Funds";
const STATUS_PENDING = "Pending";
const YES = "Yes";

// ---- Related Products (unchanged) ------------------------------------------

const RELATED_PRODUCTS_OBJECT_API_NAME = "Financial_Account_Related_Product__c";
/**
 * Positional order matters -- ArcRelatedListController.getRelatedRecordsPage
 * returns each row's values as a plain cells[] array in the same order these
 * were requested, not keyed by name. Financial_Account__c on this object points
 * at the wrong (unused FSC) object, so Wizard_Financial_Account__r.Name is
 * used here instead, same substitution already established for this exact
 * object in arcCaseDetail's own Related Products card.
 */
const RELATED_PRODUCTS_FIELD_PATHS = [
  "Name",
  "Wizard_Financial_Account__r.Name",
  "Case__r.CaseNumber"
];
const RELATED_PRODUCTS_COLUMNS = [
  { label: "Related Product Name", fieldName: "name", isLink: true },
  { label: "Financial Account", fieldName: "financialAccount" },
  { label: "Case", fieldName: "caseNumber" }
];
/** Rows per server fetch -- MAX_PAGE_SIZE on the Apex side. */
const RELATED_PRODUCTS_PAGE_SIZE = 100;

/** Apex hands cells back as a positional array; this is the one place that order is named. */
const mapRelatedProductRows = (rows) =>
  (rows || []).map((row) => ({
    id: row.id,
    name: row.cells?.[0] ?? "",
    financialAccount: row.cells?.[1] ?? "",
    caseNumber: row.cells?.[2] ?? ""
  }));

// ---- Header + visibility drivers ------------------------------------------

const HEADER_FIELDS = [
  "Name",
  "Status__c",
  "Performance_Status__c",
  "Asset_Category__c",
  "Asset_Class__c",
  "Sponsor__c",
  "Date_Approved__c"
];

/**
 * Values this component needs in hand (not just rendered by a record form):
 * the fields the flexipage's visibility rules read, plus the two the Waterfall
 * section renders itself.
 */
const DRIVER_FIELDS = [
  "Asset_Category__c",
  "Asset_Class__c",
  "Asset_Subclass__c",
  "Status__c",
  "Redemption_Feature__c",
  "All_Cash__c",
  "Waterfall_Order__c",
  "Waterfall_Order_Ranked__c"
];

/**
 * The flexipage's "Targeted Asset Class (Private Real Estate)" section, in its
 * own order: eighteen checkboxes. Labels come from getObjectInfo at runtime
 * rather than being typed here, so a relabel in Setup shows up without a code
 * change.
 */
const TARGETED_ASSET_CLASS_FIELDS = [
  "Multifamily__c",
  "Industrial__c",
  "Multi_Tenant_Retail__c",
  "Single_Tenant_Retail__c",
  "Hospitality__c",
  "Multi_Tenant_Office__c",
  "Single_Tenant_Office__c",
  "Direct_Loans_1st_Lien__c",
  "Direct_Loans_2nd_Lien__c",
  "Mezzanine_Loans__c",
  "Syndicated_Loans__c",
  "Self_Storage__c",
  "Senior_Housing__c",
  "Student_Housing__c",
  "Single_Family_Rental__c",
  "Manufactured_Housing__c",
  "Land__c",
  "Other__c"
];

const qualify = (fields) => fields.map((api) => `${OBJECT_API_NAME}.${api}`);

/** One getRecord wire covers the header, every rule input and the checkboxes. */
const RECORD_FIELDS = qualify([
  ...new Set([...HEADER_FIELDS, ...DRIVER_FIELDS, ...TARGETED_ASSET_CLASS_FIELDS])
]);

// ---- Visibility rules (from the flexipage, expressed on plain values) -------

/** The handful of record values the rules read, pulled once per record. */
const readRuleValues = (record) => ({
  assetCategory: getFieldValue(record, `${OBJECT_API_NAME}.Asset_Category__c`),
  assetClass: getFieldValue(record, `${OBJECT_API_NAME}.Asset_Class__c`),
  assetSubclass: getFieldValue(record, `${OBJECT_API_NAME}.Asset_Subclass__c`),
  status: getFieldValue(record, `${OBJECT_API_NAME}.Status__c`),
  redemptionFeature: getFieldValue(
    record,
    `${OBJECT_API_NAME}.Redemption_Feature__c`
  ),
  allCash: getFieldValue(record, `${OBJECT_API_NAME}.All_Cash__c`)
});

const isAlternativeInvestment = (v) => v.assetCategory === ALTERNATIVE_INVESTMENT;
const isPrivateRealEstate = (v) => v.assetClass === PRIVATE_REAL_ESTATE;
const isDstTic = (v) => v.assetSubclass === DST_TIC;
const isPublicNonTraded = (v) => v.assetSubclass === PUBLIC_NON_TRADED_FUNDS;
const isNotPending = (v) => v.status !== STATUS_PENDING;

/**
 * A field entry is either a bare API name (always shown) or
 * { api, when(values) } for the flexipage's field-level visibility rules.
 */
const field = (api, when) => ({ api, when });

/**
 * The flexipage's field sections in page order, each as its two columns
 * (left, right) exactly as laid out there, with its section-level rule.
 * Share Classes, Targeted Asset Class, Waterfall and the two related-list tabs
 * are not plain field sections and are assembled separately in buildSections.
 */
const SECTION_RULES = {
  general: {
    label: "General Information",
    when: () => true,
    left: [
      "Investment_Type__c",
      "Anticipated_Hold_Period__c",
      "Asset_Category__c",
      field("Asset_Class__c", isAlternativeInvestment),
      field(
        "Asset_Subclass__c",
        (v) => [PRIVATE_REAL_ESTATE, PRIVATE_CREDIT].includes(v.assetClass)
      )
    ],
    right: [
      "Status__c",
      field("Date_Approved__c", isNotPending),
      "Date_of_Last_Review__c",
      "Current_Distribution__c",
      field("Current_NAV__c", isAlternativeInvestment),
      field("Life_Cycle_Status__c", isAlternativeInvestment),
      field(
        "Performance_Status__c",
        (v) => isAlternativeInvestment(v) && isNotPending(v)
      ),
      field("Accreditation_Status__c", isAlternativeInvestment)
    ]
  },
  dstDetails: {
    label: "1031 - DST / TIC Details",
    when: isDstTic,
    left: [
      "Investment_Summary__c",
      "Registration_Exemptions__c",
      "Maximum_Offering__c",
      "Minimum_Investment_Amount__c",
      "PPM_Date__c",
      "IC_Approval_Date__c"
    ],
    right: [
      "All_Cash__c",
      field("Loan_to_Offering_Ratio__c", (v) => v.allCash !== YES),
      field("Loan_to_Purchase_Ratio__c", (v) => v.allCash !== YES),
      "Est_Year_1_Cash_on_Cash_Return__c",
      "Est_Avg_Cash_on_Cash_Returns__c",
      "Frequency_of_Investor_Reporting__c",
      "Tax_Opinion__c"
    ]
  },
  dstFees: {
    label: "Fees and Expenses (1031 - DST / TIC)",
    when: isDstTic,
    left: [
      "Selling_Commissions__c",
      "BD_Reallowance__c",
      "Mark_Up_to_Purchase__c",
      "Upfront_Load_on_Equity__c"
    ],
    right: [
      "Property_Management_Fee__c",
      "Disposition_Fee__c",
      "Total_Upfront_Reserves__c"
    ]
  },
  privateRealEstateDetails: {
    label: "Private Real Estate Details",
    when: (v) => isPrivateRealEstate(v) && !isPublicNonTraded(v) && !isDstTic(v),
    left: [
      "Investment_Summary__c",
      "Investment_Type__c",
      "Registration_Exemptions__c",
      "Fund_Life_Cycle__c",
      "Anticipated_Hold_Period__c",
      "Maximum_Offering__c",
      "Minimum_Investment_Amount__c",
      "Equity_Contribution_Method__c",
      "PPM_Date__c",
      "Equity_Raised_to_Date__c",
      "IC_Approval_Date__c",
      "Anticipated_Offering_Close_Date__c",
      "Objective__c",
      "Preferred_Return_Hurdle_Rate__c",
      "Targeted_Distribution_Rate__c"
    ],
    right: [
      "Targeted_Net_IRR__c",
      "Targeted_MOIC__c",
      "Platform_Availability__c",
      "Redemption_Feature__c",
      field("Redemption_Details__c", (v) => v.redemptionFeature === YES),
      field("Redemption_Cap__c", (v) => v.redemptionFeature === YES),
      "Tax_Reporting__c",
      "UBTI_for_Qualified_Accounts__c",
      "Strategy_Type__c",
      "Blind_Pool__c",
      "Targeted_Fund_Level_Leverage__c",
      "Sponsor_Co_Invest__c",
      "Sponsor_Co_Invest_Amount__c",
      "Audited_Fund_Financials__c",
      "Current_NAV_Unit_Price__c",
      "Valuation_Frequency__c"
    ]
  },
  privateRealEstateFees: {
    label: "Fees and Expenses (Private Real Estate)",
    when: (v) => !isDstTic(v) && isAlternativeInvestment(v),
    left: [
      "Selling_Commissions__c",
      "BD_Reallowance__c",
      "Upfront_Load_on_Equity__c",
      "Asset_Management_Fee__c"
    ],
    right: ["Property_Management_Fee__c", "Development_Fee__c", "Manager_Promote__c"]
  },
  publicNonTradedFundDetails: {
    label: "Public Non-Traded Fund Details",
    when: isPublicNonTraded,
    left: ["Registration_Type__c", "Effective_Date__c"],
    right: [
      "International_Exposure__c",
      "of_Current_Assets__c",
      "Targeted_Portfolio_Leverage__c"
    ]
  }
};

/** Section rules that are not plain field sections. */
const SHOW_TARGETED_ASSET_CLASS = isPrivateRealEstate;
const SHOW_WATERFALL = (v) => !isDstTic(v) && isAlternativeInvestment(v);
const SHOW_SHARE_CLASSES = isAlternativeInvestment;
const SHOW_MONITORING_UPDATES = isAlternativeInvestment;
const SHOW_RELATED_PROPERTIES = isDstTic;

/**
 * The flexipage's three related-list tabs/cards, as c/arcRelatedList
 * configurations. Internally each shows only the Name column (the org's
 * default related-list layout); a couple of the object's own fields are added
 * here so the list says something. None of these objects has a page of its
 * own in this site, so rows do not link.
 */
const SHARE_CLASSES_LIST = {
  key: "shareClasses",
  label: "Share Classes",
  objectApiName: "Share_Class__c",
  parentFieldApiName: "Product__c",
  columns:
    "Share Class Name:Name,Share Class:Share_Class__c,Investment Type:Investment_Type__c"
};
const MONITORING_UPDATES_LIST = {
  key: "monitoringUpdates",
  label: "Monitoring Updates",
  objectApiName: "Monitoring_Update__c",
  parentFieldApiName: "Product__c",
  columns:
    "Monitoring Update Name:Name,Review Date:Review_Date__c,Review Type:Review_Type__c,Performance Status:Performance_Status__c,Distribution:Distribution__c,Occupancy:Occupancy__c"
};
const RELATED_PROPERTIES_LIST = {
  key: "relatedProperties",
  label: "Related Properties",
  objectApiName: "Property__c",
  parentFieldApiName: "Related_Product__c",
  columns:
    "Property Name:Name,Property Type:Property_Type__c,Purchase Price:Purchase_Price__c,Acquisition Date:Acquisition_Date__c,Occupancy:Property_Occupancy__c"
};

/** The flexipage's right-rail "Sponsor Information" section, field-for-field. */
const SPONSOR_INFO_FIELDS = [
  "Sponsor__c",
  "Website__c",
  "Contact__c",
  "Email_Address__c",
  "Phone_Number__c"
];

/**
 * The flexipage's right-rail "Notes" section minus Internal_Notes__c -- see
 * the class comment. Analyst Notes only.
 */
const NOTES_FIELDS = ["Analyst_Notes__c"];

const WATERFALL_DESCRIPTION_FIELDS = ["Waterfall_Description__c"];

/**
 * lightning-record-form lays a columns="2" field list out row by row, while
 * the flexipage defines a left column and a right column. Interleaving the two
 * reproduces the flexipage's side-by-side placement for as long as both
 * columns have rows; whichever column is longer simply flows on afterwards.
 */
const interleaveColumns = (left, right) => {
  const out = [];
  const rows = Math.max(left.length, right.length);
  for (let index = 0; index < rows; index++) {
    if (index < left.length) out.push(left[index]);
    if (index < right.length) out.push(right[index]);
  }
  return out;
};

/** Applies each entry's own rule and returns bare API names. */
const visibleFields = (entries, values) =>
  entries
    .filter((entry) =>
      typeof entry === "string" ? true : !entry.when || entry.when(values)
    )
    .map((entry) => (typeof entry === "string" ? entry : entry.api));

/**
 * Same semantic red/yellow/green mapping as arcRecordListView's
 * SEMANTIC_PILL_TONES -- Performance_Status__c's own picklist already
 * defines these colors in Setup.
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
  _objectInfo;

  /**
   * The main column's sections for THIS record, in flexipage order, each
   * tagged with the one kind flag the template switches on. Rebuilt when the
   * record or the object describe arrives, not on every render, so the record
   * forms underneath are handed stable field arrays.
   */
  sections = [];

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

  @wire(getRecord, { recordId: "$recordId", fields: RECORD_FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this._record = data;
      this.errorMessage = undefined;
      this.rebuildSections();
    } else if (error) {
      this._record = undefined;
      this.sections = [];
      this.errorMessage =
        error?.body?.message || "Unable to load this product right now.";
    }
  }

  /** Field labels for the Targeted Asset Class list -- see TARGETED_ASSET_CLASS_FIELDS. */
  @wire(getObjectInfo, { objectApiName: OBJECT_API_NAME })
  wiredObjectInfo({ data }) {
    if (data) {
      this._objectInfo = data;
      this.rebuildSections();
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

  fieldLabel(apiName) {
    return this._objectInfo?.fields?.[apiName]?.label || apiName;
  }

  // ---- Header ---------------------------------------------------------------

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

  get objectApiName() {
    return OBJECT_API_NAME;
  }

  // ---- Main-column sections ------------------------------------------------

  /**
   * Assembles `sections` for the loaded record: the flexipage's Details tab
   * top to bottom, then its Monitoring Updates and Related Properties tabs as
   * trailing cards. Each entry carries exactly one of isFields /
   * isRelatedList / isTargetedAssetClass / isWaterfall for the template.
   */
  rebuildSections() {
    if (!this._record) {
      this.sections = [];
      return;
    }
    const values = readRuleValues(this._record);
    const out = [];

    const pushFieldSection = (key) => {
      const rule = SECTION_RULES[key];
      if (!rule.when(values)) {
        return;
      }
      const fields = interleaveColumns(
        visibleFields(rule.left, values),
        visibleFields(rule.right, values)
      );
      if (fields.length) {
        out.push({ key, label: rule.label, isFields: true, fields });
      }
    };
    const pushRelatedList = (config, when) => {
      if (when(values)) {
        out.push({ ...config, isRelatedList: true });
      }
    };

    pushFieldSection("general");
    pushRelatedList(SHARE_CLASSES_LIST, SHOW_SHARE_CLASSES);
    pushFieldSection("dstDetails");
    pushFieldSection("dstFees");
    pushFieldSection("privateRealEstateDetails");

    if (SHOW_TARGETED_ASSET_CLASS(values)) {
      const items = TARGETED_ASSET_CLASS_FIELDS.filter(
        (api) => this.fieldValue(api) === true
      ).map((api) => ({ key: api, label: this.fieldLabel(api) }));
      out.push({
        key: "targetedAssetClass",
        label: "Targeted Asset Class (Private Real Estate)",
        isTargetedAssetClass: true,
        items,
        hasItems: items.length > 0
      });
    }

    pushFieldSection("privateRealEstateFees");
    pushFieldSection("publicNonTradedFundDetails");

    if (SHOW_WATERFALL(values)) {
      const steps = this.waterfallSteps;
      out.push({
        key: "waterfall",
        label: "Waterfall (Private Real Estate)",
        isWaterfall: true,
        steps,
        hasSteps: steps.length > 0,
        fields: WATERFALL_DESCRIPTION_FIELDS
      });
    }

    pushRelatedList(MONITORING_UPDATES_LIST, SHOW_MONITORING_UPDATES);
    pushRelatedList(RELATED_PROPERTIES_LIST, SHOW_RELATED_PROPERTIES);

    this.sections = out;
  }

  /**
   * The ranked order the Products_Waterfall_Order flow saved, as
   * [{ position, label }]. Waterfall_Order_Ranked__c is the flow's own
   * comma-separated output and is the authority; Waterfall_Order__c (the
   * multi-select picklist the flow starts from) is only a fallback for a
   * record the flow was never run on, and a multi-select carries no order of
   * its own, so that fallback is unranked selection rather than a ranking.
   */
  get waterfallSteps() {
    const ranked = this.fieldValue("Waterfall_Order_Ranked__c");
    const fallback = this.fieldValue("Waterfall_Order__c");
    const source = ranked
      ? String(ranked).split(",")
      : fallback
        ? String(fallback).split(";")
        : [];
    return source
      .map((label) => label.trim())
      .filter(Boolean)
      .map((label, index) => ({
        key: `${index}-${label}`,
        position: index + 1,
        label
      }));
  }

  get sponsorInfoFields() {
    return SPONSOR_INFO_FIELDS;
  }

  get notesFields() {
    return NOTES_FIELDS;
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
   * of a full page navigation.
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
   * what's currently loaded while hasMoreRows is true. Fetches the next
   * RELATED_PRODUCTS_PAGE_SIZE batch and appends it.
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
   * history rendering.
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