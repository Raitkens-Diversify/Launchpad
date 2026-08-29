/**
 * Popup view/edit card for one Financial_Account_Related_Product__c record,
 * opened from Product Detail's Related Products table (via arcDataTable's
 * cancelable `rownavigate` event) instead of navigating to a full page.
 *
 * Field set matches Related_Product_Record_Page.flexipage's own Information
 * + System Information sections (retrieved and parsed directly, same as
 * every other page built this session) -- not guessed:
 *   Related Product Name, Financial Account, Amount, Product, Maestro
 *   Product Code, Case, Onbase Migration Id, Created By, Last Modified By.
 *
 * View vs edit, deliberately not a single always-editable form: the 3
 * lookups (Financial Account, Product, Case) need to be reliable, real links
 * that close this popup and navigate -- built with the same
 * buildRecordNavigationReference/buildExperienceRecordPath utilities every
 * other ARC page already uses, rather than trusting lightning-record-form's
 * own automatic lookup-to-hyperlink rendering to resolve correctly against
 * this LWR site's custom routes (unverified, and this session doesn't drive
 * a browser to check). Editable fields (Amount, Onbase Migration Id) toggle
 * into lightning-input-field only when "Edit" is clicked; Name (AutoNumber)
 * and Maestro Product Code (a formula field, Product__r.Product_Maestro_ID__c)
 * are never editable regardless of mode. The 3 lookups stay plain links in
 * both view and edit mode -- reassigning which account/product/case a
 * position record belongs to was not asked for.
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import LightningToast from "lightning/toast";
import {
  buildRecordNavigationReference,
  buildExperienceRecordPath
} from "c/recordNavigationCommunityUtils";

const OBJECT_API_NAME = "Financial_Account_Related_Product__c";

const FIELDS = [
  `${OBJECT_API_NAME}.Name`,
  `${OBJECT_API_NAME}.Amount__c`,
  `${OBJECT_API_NAME}.Maestro_Product_Code__c`,
  `${OBJECT_API_NAME}.Onbase_Migration_Id__c`,
  `${OBJECT_API_NAME}.Financial_Account__c`,
  `${OBJECT_API_NAME}.Financial_Account__r.Name`,
  `${OBJECT_API_NAME}.Wizard_Financial_Account__c`,
  `${OBJECT_API_NAME}.Wizard_Financial_Account__r.Name`,
  `${OBJECT_API_NAME}.Product__c`,
  `${OBJECT_API_NAME}.Product__r.Name`,
  `${OBJECT_API_NAME}.Case__c`,
  `${OBJECT_API_NAME}.Case__r.CaseNumber`,
  `${OBJECT_API_NAME}.CreatedBy.Name`,
  `${OBJECT_API_NAME}.LastModifiedBy.Name`
];

export default class ArcRelatedProductQuickView extends NavigationMixin(
  LightningElement
) {
  isOpen = false;
  isEditing = false;
  isSaving = false;
  errorMessage = "";

  _recordId;
  _record;

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

  get objectApiName() {
    return OBJECT_API_NAME;
  }

  fieldValue(path) {
    return this._record
      ? getFieldValue(this._record, `${OBJECT_API_NAME}.${path}`)
      : undefined;
  }

  get isLoading() {
    return this.isOpen && !this._record && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._record);
  }

  get relatedProductName() {
    return this.fieldValue("Name");
  }

  get headingLabel() {
    return this.relatedProductName
      ? `Related Product: ${this.relatedProductName}`
      : "Related Product";
  }

  // ---- Lookup fields: always plain links, never editable ------------------

  get financialAccountId() {
    return this.fieldValue("Wizard_Financial_Account__c");
  }

  get financialAccountName() {
    return this.fieldValue("Wizard_Financial_Account__r.Name");
  }

  get financialAccountUrl() {
    return this.financialAccountId
      ? buildExperienceRecordPath(
          this.financialAccountId,
          "Financial_Account__c"
        )
      : "";
  }

  /**
   * Rows created outside the wizard carry only Financial_Account__c -- the
   * FinServ lookup -- and rendered this row as an empty link. Only the wizard
   * lookup gets a link: the site's /financial-account route serves the custom
   * Financial_Account__c object alone (routeType detail-Financial_Account__c),
   * so the FinServ record has no page here and shows as plain text.
   */
  get hasFinancialAccountLink() {
    return Boolean(this.financialAccountId);
  }

  get financialAccountFallbackName() {
    return this.fieldValue("Financial_Account__r.Name") || "—";
  }

  get productId() {
    return this.fieldValue("Product__c");
  }

  get productName() {
    return this.fieldValue("Product__r.Name");
  }

  get productUrl() {
    return this.productId
      ? buildExperienceRecordPath(this.productId, "Product__c")
      : "";
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

  handleLookupClick(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;
    if (!recordId) {
      return;
    }

    const reference = buildRecordNavigationReference(recordId, objectApiName);
    // Close first, then navigate -- matches the explicit ask ("map back to
    // the respective pages closing the popup") rather than leaving the
    // popup mounted underneath whatever page loads next.
    this.handleClose();
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  // ---- Read-only, non-lookup fields -----------------------------------

  get maestroProductCode() {
    return this.fieldValue("Maestro_Product_Code__c");
  }

  get createdByName() {
    return this.fieldValue("CreatedBy.Name");
  }

  get lastModifiedByName() {
    return this.fieldValue("LastModifiedBy.Name");
  }

  // ---- Editable fields: Amount, Onbase Migration Id --------------------

  get amountValue() {
    return this.fieldValue("Amount__c");
  }

  get onbaseMigrationIdValue() {
    return this.fieldValue("Onbase_Migration_Id__c");
  }

  get showEditButton() {
    return !this.isEditing && this.hasDetail;
  }

  handleEditClick() {
    this.isEditing = true;
    this.errorMessage = "";
  }

  handleCancelEdit() {
    this.isEditing = false;
    this.errorMessage = "";
  }

  handleSubmit() {
    this.isSaving = true;
    this.errorMessage = "";
  }

  handleSuccess() {
    this.isSaving = false;
    this.isEditing = false;
    LightningToast.show(
      { label: "Related Product saved", variant: "success" },
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

  handleClose() {
    this.isOpen = false;
    this.isEditing = false;
  }

  /** Escape closes, matching arcQuickCreate's own dialog. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}