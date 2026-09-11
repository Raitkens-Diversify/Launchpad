/**
 * View/edit popup card for one Order_Ticket__c record, opened from the Case
 * page's Order Tickets card via arcRelatedList's cancelable `rownavigate`
 * event -- the same interception c/arcRelatedProductQuickView uses on Product
 * Detail, and for the same reason: the object has no page of its own in this
 * site, so navigating lands on Invalid Page.
 *
 * Field set and edit/read-only split matches Order_Ticket_Record_Page.
 * flexipage's own field items and behavior -- not guessed. Every field the
 * internal record page lets a user type into becomes editable here too
 * (Edit toggles the row into lightning-input-field, same pattern
 * c/arcRelatedProductQuickView uses); Household Name and Financial Advisor
 * Team Name stay display-only because they are formula fields on the object
 * itself (never editable regardless of UI), and Created By/Last Modified By
 * because the platform never allows editing those. The 3 lookups
 * (Financial Account, Wizard Financial Account, Case) stay plain links in
 * both modes -- reassigning which account/case a ticket belongs to was not
 * asked for, matching the related-product popup's own precedent.
 *
 * This is ARC-only: nothing here touches Order_Ticket_Record_Page itself,
 * the object's fields, or any shared/internal metadata -- only this
 * Experience-Cloud-only component.
 *
 * Additional_Details__c is conditionally shown/editable, mirroring the
 * record page's own three single-condition visibility rules for that field
 * (each placing the field once, visible when a different one of
 * Method_of_Cash_Raise__c/Method_to_Allocate__c/Frequency__c equals
 * "Custom" -- together an OR across the three): visible when the record's
 * saved value of any of those three is "Custom", or, while editing, when
 * the in-progress (unsaved) value of any of those three is "Custom".
 *
 * Values render through getFieldDisplayValue first so dates, currencies and
 * picklists arrive already formatted for the reader's locale, with the raw
 * value as the fallback for fields the UI API returns no display value for.
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import {
  getRecord,
  getFieldValue,
  getFieldDisplayValue
} from "lightning/uiRecordApi";
import LightningToast from "lightning/toast";
import {
  buildRecordNavigationReference,
  buildExperienceRecordPath
} from "c/recordNavigationCommunityUtils";
import getRelatedOrders from "@salesforce/apex/ArcRelatedListController.getRelatedRecords";

const OBJECT_API_NAME = "Order_Ticket__c";

/** Child Order__c object, related to this ticket through Order_Ticket__c. */
const ORDERS_OBJECT_API_NAME = "Order__c";
const ORDERS_PARENT_FIELD_API_NAME = "Order_Ticket__c";

/**
 * Columns for the Orders section, in the order returned by
 * getRelatedRecords. Matches Order_Ticket_Record_Page.flexipage's own
 * "Orders" dynamicRelatedList field aliases (NAME, Strategy__c,
 * Initial_Funding_Percentage__c, Initial_Funding_Amount__c) -- not guessed --
 * and every path here is FLS-granted to the community permission set, same
 * discipline as this ticket's own DETAIL_FIELDS below.
 */
const ORDER_COLUMNS = [
  { label: "Order", path: "Name" },
  { label: "Strategy", path: "Strategy__r.Name" },
  { label: "Initial Funding %", path: "Initial_Funding_Percentage__c" },
  { label: "Initial Funding Amount", path: "Initial_Funding_Amount__c" }
];

/**
 * Fetched alongside ORDER_COLUMNS but not rendered as its own column --
 * the Strategy cell links on this id, opening arcStrategyQuickView.
 */
const ORDER_STRATEGY_ID_PATH = "Strategy__c";

/**
 * Label/path pairs for the plain (non-lookup) rows, in record-page order.
 * `editable: false` marks the four rows that can never become an input --
 * Household Name and Financial Advisor Team Name are formula fields on
 * Order_Ticket__c itself (mirroring a lookup's own Name), and Created
 * By/Last Modified By are platform-managed -- regardless of edit mode, all
 * four always render as plain text.
 */
const DETAIL_FIELDS = [
  { label: "Status", path: "Status__c", editable: true },
  { label: "Type of Request", path: "Type_of_Request__c", editable: true },
  { label: "Amount", path: "Amount__c", editable: true },
  { label: "Frequency", path: "Frequency__c", editable: true },
  { label: "Method of Cash Raise", path: "Method_of_Cash_Raise__c", editable: true },
  { label: "Method to Allocate", path: "Method_to_Allocate__c", editable: true },
  { label: "Expected Account Value", path: "Expected_Account_Value__c", editable: true },
  {
    label: "Expected Value / Initial Funding Reason",
    path: "Expected_Value_Initial_Funding_Reason__c",
    editable: true
  },
  { label: "Date of First Withdrawal", path: "Date_of_First_Withdrawal__c", editable: true },
  { label: "End Date", path: "End_Date__c", editable: true },
  { label: "Order Completed Date", path: "Order_Completed_Date__c", editable: true },
  { label: "Household Name", path: "Household_Name__c", editable: false },
  {
    label: "Financial Advisor Team Name",
    path: "Financial_Advisor_Team_Name__c",
    editable: false
  },
  { label: "Advisor Notes", path: "Advisor_Notes__c", editable: true },
  {
    label: "Additional Details",
    path: "Additional_Details__c",
    editable: true,
    conditional: true
  },
  { label: "Internal Trade Notes", path: "Internal_Trade_Notes__c", editable: true },
  { label: "Created By", path: "CreatedBy.Name", editable: false },
  { label: "Last Modified By", path: "LastModifiedBy.Name", editable: false }
];

const CUSTOM_VALUE = "Custom";

/**
 * The three fields whose value governs Additional_Details__c's visibility --
 * mirrors the record page's three separate single-condition visibilityRule
 * placements of that field (Method_of_Cash_Raise__c, Method_to_Allocate__c,
 * Frequency__c each independently showing it when set to "Custom"; together
 * an OR across all three, since a record page field can only carry one
 * placement per condition, not a combined OR expression).
 */
const ADDITIONAL_DETAILS_TRIGGER_FIELDS = [
  "Method_of_Cash_Raise__c",
  "Method_to_Allocate__c",
  "Frequency__c"
];

/** getRelatedRecords hands every cell over as a string; these two are the only types ORDER_COLUMNS carries. */
function formatCurrencyCell(value, currencyCode) {
  const numeric = Number(value);
  if (value === "" || value === undefined || !Number.isFinite(numeric)) {
    return "—";
  }
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: currencyCode
  }).format(numeric);
}

function formatPercentCell(value) {
  const numeric = Number(value);
  if (value === "" || value === undefined || !Number.isFinite(numeric)) {
    return "—";
  }
  return new Intl.NumberFormat(undefined, {
    style: "percent",
    maximumFractionDigits: 2
  }).format(numeric / 100);
}

/**
 * The stored value of one funding cell as a finite number, or null when it is
 * blank / non-numeric. getRelatedRecords hands cells over as strings ("" for an
 * empty field), so a bare Number() would turn "" into 0 -- this keeps "not
 * stored" distinct from a real 0 so a blank side can be recognised and derived.
 */
function toFiniteNumber(value) {
  if (value === "" || value === undefined || value === null) {
    return null;
  }
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

const FIELDS = [
  `${OBJECT_API_NAME}.Name`,
  `${OBJECT_API_NAME}.Financial_Account__c`,
  `${OBJECT_API_NAME}.Financial_Account__r.Name`,
  `${OBJECT_API_NAME}.Wizard_Financial_Account__c`,
  `${OBJECT_API_NAME}.Wizard_Financial_Account__r.Name`,
  `${OBJECT_API_NAME}.Case__c`,
  `${OBJECT_API_NAME}.Case__r.CaseNumber`,
  ...DETAIL_FIELDS.map((field) => `${OBJECT_API_NAME}.${field.path}`)
];

export default class ArcOrderTicketQuickView extends NavigationMixin(
  LightningElement
) {
  isOpen = false;
  isEditing = false;
  isSaving = false;
  errorMessage = "";

  _recordId;
  _record;

  /**
   * The three trigger fields' in-progress (unsaved) values while editing --
   * seeded from the saved record when Edit is clicked, then kept current by
   * handleFieldChange as the user types, so Additional Details can show/hide
   * live the same way the internal record page's own visibility rules do,
   * without waiting for a save round trip.
   */
  _liveTriggerValues = {};

  /** Raw getRelatedRecords result for the Orders section; undefined until the first response lands. */
  _ordersResult;
  ordersErrorMessage = "";

  /** Opens the popup for the given record -- called by the parent's rownavigate handler. */
  @api
  open(recordId) {
    this._recordId = recordId;
    this.isEditing = false;
    this.errorMessage = "";
    this.isOpen = true;
  }

  get recordId() {
    return this._recordId;
  }

  get objectApiName() {
    return OBJECT_API_NAME;
  }

  @wire(getRecord, { recordId: "$_recordId", fields: FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this._record = data;
      this.errorMessage = "";
    } else if (error) {
      this._record = undefined;
      this.errorMessage =
        error?.body?.message || "Unable to load this record right now.";
    }
  }

  @wire(getRelatedOrders, {
    recordId: "$_recordId",
    objectApiName: ORDERS_OBJECT_API_NAME,
    parentFieldApiName: ORDERS_PARENT_FIELD_API_NAME,
    fieldApiNames: [
      ...ORDER_COLUMNS.map((column) => column.path),
      ORDER_STRATEGY_ID_PATH
    ],
    linkFieldApiName: null
  })
  wiredOrders({ data, error }) {
    if (data) {
      this._ordersResult = data;
      this.ordersErrorMessage = "";
    } else if (error) {
      this._ordersResult = { rows: [] };
      this.ordersErrorMessage =
        error?.body?.message || "Unable to load orders right now.";
    }
  }

  fieldValue(path) {
    if (!this._record) {
      return undefined;
    }
    const qualified = `${OBJECT_API_NAME}.${path}`;
    const displayValue = getFieldDisplayValue(this._record, qualified);
    return displayValue ?? getFieldValue(this._record, qualified);
  }

  get isLoading() {
    return this.isOpen && !this._record && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._record);
  }

  get headingLabel() {
    const name = this.fieldValue("Name");
    return name ? `Order Ticket: ${name}` : "Order Ticket";
  }

  /**
   * True when Additional_Details__c should show at all, in either mode --
   * the saved record's own field values while viewing, the in-progress
   * (unsaved) edit values while editing, matching how the record page's
   * three visibilityRule placements read live, un-committed picklist
   * selections rather than only the last-saved value.
   */
  get isAdditionalDetailsVisible() {
    return ADDITIONAL_DETAILS_TRIGGER_FIELDS.some((path) => {
      const value = this.isEditing
        ? this._liveTriggerValues[path]
        : this.fieldValue(path);
      return value === CUSTOM_VALUE;
    });
  }

  /** DETAIL_FIELDS, minus Additional Details when its trigger condition isn't met. */
  get visibleDetailFields() {
    return DETAIL_FIELDS.filter(
      (field) => !field.conditional || this.isAdditionalDetailsVisible
    );
  }

  /** The plain (view-mode) rows, resolved to display values; empty values show as an em dash. */
  get detailRows() {
    return this.visibleDetailFields.map((field) => {
      const value = this.fieldValue(field.path);
      return {
        label: field.label,
        value: value === undefined || value === null || value === ""
          ? "—"
          : value
      };
    });
  }

  /**
   * The edit-mode rows: still every visible field, but each one also
   * carries whether it renders as a lightning-input-field or stays plain
   * text (Household Name, Financial Advisor Team Name, Created By, Last
   * Modified By never become inputs -- see DETAIL_FIELDS).
   */
  get editableDetailRows() {
    return this.visibleDetailFields.map((field) => {
      const value = this.fieldValue(field.path);
      return {
        label: field.label,
        path: field.path,
        editable: field.editable,
        value: value === undefined || value === null || value === ""
          ? "—"
          : value
      };
    });
  }

  get showEditButton() {
    return !this.isEditing && this.hasDetail;
  }

  handleEditClick() {
    this.isEditing = true;
    this.errorMessage = "";
    this._liveTriggerValues = Object.fromEntries(
      ADDITIONAL_DETAILS_TRIGGER_FIELDS.map((path) => [
        path,
        this.fieldValue(path)
      ])
    );
  }

  handleCancelEdit() {
    this.isEditing = false;
    this.errorMessage = "";
  }

  /**
   * Fires on every editable lightning-input-field's onchange, but only the
   * three Additional Details trigger fields need to be tracked -- everything
   * else is left to lightning-record-edit-form's own state until Save.
   */
  handleFieldChange(event) {
    const fieldName = event.target?.fieldName;
    if (!fieldName || !ADDITIONAL_DETAILS_TRIGGER_FIELDS.includes(fieldName)) {
      return;
    }
    this._liveTriggerValues = {
      ...this._liveTriggerValues,
      [fieldName]: event.detail.value
    };
  }

  handleSubmit() {
    this.isSaving = true;
    this.errorMessage = "";
  }

  handleSuccess() {
    this.isSaving = false;
    this.isEditing = false;
    LightningToast.show(
      { label: "Order Ticket saved", variant: "success" },
      this
    );
  }

  handleError(event) {
    this.isSaving = false;
    this.errorMessage =
      event.detail?.detail || event.detail?.message || "Could not save.";
  }

  handleSave() {
    this.template.querySelector("lightning-record-edit-form")?.submit();
  }

  // ---- Orders: read-only child list, row click opens arcOrderQuickView ----

  get isLoadingOrders() {
    return this.isOpen && !this._ordersResult && !this.ordersErrorMessage;
  }

  /**
   * The figure a percent-based order's dollars are a share of (and, inversely,
   * that a dollar-based order's percentage is computed against): the ticket's
   * Expected Account Value. This is the same basis the envelope wizard converts
   * against (TradeInstructionController's expectedAccountValue), and it is the
   * value shown in this same modal -- so a derived amount always equals the
   * displayed percentage times the displayed Expected Account Value, with no
   * hidden third number. null (blank/non-numeric) leaves both sides as stored.
   */
  get fundingBasis() {
    if (!this._record) {
      return null;
    }
    return toFiniteNumber(
      getFieldValue(this._record, `${OBJECT_API_NAME}.Expected_Account_Value__c`)
    );
  }

  get orderRows() {
    const currencyCode = this._ordersResult?.currencyCode || "USD";
    const basis = this.fundingBasis;
    return (this._ordersResult?.rows || []).map((row) => {
      const [name, strategyName, fundingPercentage, fundingAmount, strategyId] =
        row.cells || [];

      // Each row stores only one side by design (a Dollar order stamps the
      // amount, a Percent order the percentage -- see TradeInstructionController).
      // When the basis is known, fill the blank side from the stored one so both
      // columns populate; if the basis is missing, or a row stores both/neither,
      // each side just renders whatever it holds (blank -> em dash, as before).
      const storedPercent = toFiniteNumber(fundingPercentage);
      const storedAmount = toFiniteNumber(fundingAmount);
      let percentCell = fundingPercentage;
      let amountCell = fundingAmount;
      if (basis !== null) {
        if (storedAmount === null && storedPercent !== null) {
          amountCell = (storedPercent / 100) * basis;
        }
        if (storedPercent === null && storedAmount !== null && basis !== 0) {
          percentCell = (storedAmount / basis) * 100;
        }
      }

      return {
        id: row.id,
        name: name || "—",
        strategyId: strategyId || "",
        strategyName: strategyName || "—",
        hasStrategy: Boolean(strategyId),
        fundingPercentage: formatPercentCell(percentCell),
        fundingAmount: formatCurrencyCell(amountCell, currencyCode)
      };
    });
  }

  get hasOrders() {
    return this.orderRows.length > 0;
  }

  get ordersCountLabel() {
    return this._ordersResult?.hasMore
      ? `${this.orderRows.length}+`
      : String(this.orderRows.length);
  }

  handleOrderRowClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.recordId;
    if (!recordId) {
      return;
    }
    this.refs.orderQuickView?.open(recordId);
  }

  handleStrategyClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.strategyId;
    if (!recordId) {
      return;
    }
    this.refs.strategyQuickView?.open(recordId);
  }

  // ---- Lookups: plain links that close the popup and navigate -------------

  get financialAccountId() {
    return this.fieldValue("Financial_Account__c");
  }

  get financialAccountName() {
    return this.fieldValue("Financial_Account__r.Name");
  }

  get hasFinancialAccount() {
    return Boolean(this.financialAccountId);
  }

  get wizardFinancialAccountId() {
    return this.fieldValue("Wizard_Financial_Account__c");
  }

  get wizardFinancialAccountName() {
    return this.fieldValue("Wizard_Financial_Account__r.Name");
  }

  get wizardFinancialAccountUrl() {
    return this.wizardFinancialAccountId
      ? buildExperienceRecordPath(
          this.wizardFinancialAccountId,
          "Financial_Account__c"
        )
      : "";
  }

  get hasWizardFinancialAccount() {
    return Boolean(this.wizardFinancialAccountId);
  }

  get caseId() {
    return this.fieldValue("Case__c");
  }

  get caseNumber() {
    return this.fieldValue("Case__r.CaseNumber");
  }

  get caseUrl() {
    return this.caseId ? buildExperienceRecordPath(this.caseId, "Case") : "";
  }

  get hasCase() {
    return Boolean(this.caseId);
  }

  handleLookupClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;
    if (!recordId) {
      return;
    }

    const reference = buildRecordNavigationReference(recordId, objectApiName);
    // Close first, then navigate, so the popup is not left mounted
    // underneath whatever page loads next.
    this.handleClose();
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  handleClose() {
    this.isOpen = false;
    this.isEditing = false;
  }

  /** Escape closes, matching the other quick-view dialogs. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}