/**
 * Read-only popup card for one Order_Ticket__c record, opened from the Case
 * page's Order Tickets card via arcRelatedList's cancelable `rownavigate`
 * event -- the same interception c/arcRelatedProductQuickView uses on Product
 * Detail, and for the same reason: the object has no page of its own in this
 * site, so navigating lands on Invalid Page.
 *
 * Field set matches Order_Ticket_Record_Page.flexipage's own field items --
 * not guessed. View-only, unlike the related-product popup: nothing on an
 * order ticket was asked to be editable from the case page.
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
import {
  buildRecordNavigationReference,
  buildExperienceRecordPath
} from "c/recordNavigationCommunityUtils";

const OBJECT_API_NAME = "Order_Ticket__c";

/** Label/path pairs for the plain (non-lookup) rows, in record-page order. */
const DETAIL_FIELDS = [
  { label: "Status", path: "Status__c" },
  { label: "Type of Request", path: "Type_of_Request__c" },
  { label: "Amount", path: "Amount__c" },
  { label: "Frequency", path: "Frequency__c" },
  { label: "Method of Cash Raise", path: "Method_of_Cash_Raise__c" },
  { label: "Method to Allocate", path: "Method_to_Allocate__c" },
  { label: "Expected Account Value", path: "Expected_Account_Value__c" },
  {
    label: "Expected Value / Initial Funding Reason",
    path: "Expected_Value_Initial_Funding_Reason__c"
  },
  { label: "Date of First Withdrawal", path: "Date_of_First_Withdrawal__c" },
  { label: "End Date", path: "End_Date__c" },
  { label: "Order Completed Date", path: "Order_Completed_Date__c" },
  { label: "Household Name", path: "Household_Name__c" },
  {
    label: "Financial Advisor Team Name",
    path: "Financial_Advisor_Team_Name__c"
  },
  { label: "Advisor Notes", path: "Advisor_Notes__c" },
  { label: "Additional Details", path: "Additional_Details__c" },
  { label: "Internal Trade Notes", path: "Internal_Trade_Notes__c" },
  { label: "Created By", path: "CreatedBy.Name" },
  { label: "Last Modified By", path: "LastModifiedBy.Name" }
];

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
  errorMessage = "";

  _recordId;
  _record;

  /** Opens the popup for the given record -- called by the parent's rownavigate handler. */
  @api
  open(recordId) {
    this._recordId = recordId;
    this.errorMessage = "";
    this.isOpen = true;
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

  /** The plain rows, resolved to display values; empty values show as an em dash. */
  get detailRows() {
    return DETAIL_FIELDS.map((field) => {
      const value = this.fieldValue(field.path);
      return {
        label: field.label,
        value: value === undefined || value === null || value === ""
          ? "—"
          : value
      };
    });
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
  }

  /** Escape closes, matching the other quick-view dialogs. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}