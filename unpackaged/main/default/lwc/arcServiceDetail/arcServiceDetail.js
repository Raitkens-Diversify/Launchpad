/**
 * Service detail page for Experience Cloud, shaped like arcTaskDetail /
 * arcFinancialAccountDetail (Case-style header card over the generic
 * c-arc-record-detail sections) instead of the stock dxp_records:detailPanel
 * the page used to be.
 *
 * The header loads through lightning/uiRecordApi — every field on it lives
 * on Service__c or its Account / Case lookups, all readable by the portal
 * profile. Related lists mirror the Lightning record page's: Cases (rows
 * navigate to the site's case pages) and Service History.
 */
import { LightningElement, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import {
  getRecord,
  getFieldValue,
  getFieldDisplayValue
} from "lightning/uiRecordApi";
import {
  resolveRecordIdFromPageReference,
  isValidSalesforceRecordId,
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";

const OBJECT_API_NAME = "Service__c";

const HEADER_FIELDS = [
  "Name",
  "Type__c",
  "Method_of_Payment__c",
  "Annual_Fee__c",
  "Start_Date__c",
  "Household__c",
  "Household__r.Name",
  "Case__c",
  "Case__r.CaseNumber"
].map((path) => `${OBJECT_API_NAME}.${path}`);

export default class ArcServiceDetail extends NavigationMixin(
  LightningElement
) {
  _recordId;
  _record;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._recordId = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
  }

  @wire(getRecord, { recordId: "$_recordId", fields: HEADER_FIELDS })
  wiredRecord({ data }) {
    if (data) {
      this._record = data;
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

  get hasRecordId() {
    return isValidSalesforceRecordId(this._recordId);
  }

  get name() {
    return this.fieldValue("Name") || "";
  }

  get serviceType() {
    return this.fieldValue("Type__c") || "";
  }

  get hasServiceType() {
    return Boolean(this.serviceType);
  }

  get methodOfPayment() {
    return this.fieldValue("Method_of_Payment__c") || "";
  }

  get hasMethodOfPayment() {
    return Boolean(this.methodOfPayment);
  }

  get annualFee() {
    return this.fieldValue("Annual_Fee__c");
  }

  get hasAnnualFee() {
    return this.annualFee !== undefined && this.annualFee !== null;
  }

  get startDate() {
    return this.fieldValue("Start_Date__c") || "";
  }

  get hasStartDate() {
    return Boolean(this.startDate);
  }

  get householdId() {
    return this.fieldValue("Household__c");
  }

  get householdName() {
    return this.fieldValue("Household__r.Name");
  }

  get hasHousehold() {
    return Boolean(this.householdId && this.householdName);
  }

  get caseId() {
    return this.fieldValue("Case__c");
  }

  get caseNumber() {
    return this.fieldValue("Case__r.CaseNumber");
  }

  get hasCase() {
    return Boolean(this.caseId && this.caseNumber);
  }

  handleHouseholdClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.householdId, "Account");
  }

  handleCaseClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.caseId, "Case");
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId || !objectApiName) {
      return;
    }
    const pageReference = buildRecordNavigationReference(recordId, objectApiName);
    if (!pageReference) {
      return;
    }
    this[NavigationMixin.Navigate](pageReference);
  }
}