/**
 * Financial Account (wizard object) detail page for Experience Cloud, shaped
 * like arcTaskDetail / arcCheckLogDetail (Case-style header card over the
 * generic c-arc-record-detail sections) instead of the stock
 * dxp_records:detailPanel the page used to be.
 *
 * The header loads through lightning/uiRecordApi rather than a bespoke Apex
 * controller: every field on it lives on the custom Financial_Account__c
 * or its Account / Financial_Advisor_Team__c lookups, all readable by the
 * portal profile — nothing here needs the system-mode tricks the Check Log
 * page needed for the FinServ account.
 *
 * Related lists mirror the Lightning record page's: Financial Account Roles
 * (rows navigate to the role's Account — the role object has no page of its
 * own), Related Products (rows open the read-only quick-view popup, same as
 * the Case page — no site route), and Financial Account History.
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

const OBJECT_API_NAME = "Financial_Account__c";

const HEADER_FIELDS = [
  "Name",
  "Account_Status__c",
  "Registration_Type__c",
  "Account_Number__c",
  "Balance__c",
  "Primary_Owner__c",
  "Primary_Owner__r.Name",
  "Household__c",
  "Household__r.Name",
  "Financial_Advisor_Team__r.Name"
].map((path) => `${OBJECT_API_NAME}.${path}`);

export default class ArcFinancialAccountDetail extends NavigationMixin(
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

  get accountStatus() {
    return this.fieldValue("Account_Status__c") || "";
  }

  get registrationType() {
    return this.fieldValue("Registration_Type__c") || "";
  }

  get hasRegistrationType() {
    return Boolean(this.registrationType);
  }

  get accountNumber() {
    return this.fieldValue("Account_Number__c") || "";
  }

  get hasAccountNumber() {
    return Boolean(this.accountNumber);
  }

  get balance() {
    return this.fieldValue("Balance__c");
  }

  get hasBalance() {
    return this.balance !== undefined && this.balance !== null;
  }

  get primaryOwnerId() {
    return this.fieldValue("Primary_Owner__c");
  }

  get primaryOwnerName() {
    return this.fieldValue("Primary_Owner__r.Name");
  }

  get hasPrimaryOwner() {
    return Boolean(this.primaryOwnerId && this.primaryOwnerName);
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

  get advisorTeamName() {
    return this.fieldValue("Financial_Advisor_Team__r.Name") || "";
  }

  get hasAdvisorTeam() {
    return Boolean(this.advisorTeamName);
  }

  handlePrimaryOwnerClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.primaryOwnerId, "Account");
  }

  handleHouseholdClick(event) {
    event.preventDefault();
    this.navigateToRecord(this.householdId, "Account");
  }

  /**
   * Related products have no page in this site, so a row opens the same
   * read-only quick-view popup the Case page uses instead of navigating.
   */
  handleRelatedProductRowNavigate(event) {
    event.preventDefault();
    const recordId = event.detail?.recordId;
    if (recordId) {
      this.refs.relatedProductQuickView?.open(recordId);
    }
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