/**
 * ARC equivalent of the Lightning Task page's console:relatedRecord
 * "Financial Account Details" component -- see arcTaskDetail's
 * showFinancialAccountDetails for when the parent shows this at all.
 * Only ever edits Task.DFPG_Financial_Account__c's Name and
 * Account_Number__c, matching the Financial_Account__c.Update_Account_Number
 * quick action the Lightning page uses. Not to be confused with
 * arcFinancialAccountDetail, the unrelated full Financial_Account__c record
 * page.
 */
import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getFinancialAccountDetail from "@salesforce/apex/ArcTaskFinAcctPanelController.getFinancialAccountDetail";
import saveFinancialAccountDetail from "@salesforce/apex/ArcTaskFinAcctPanelController.saveFinancialAccountDetail";

export default class ArcTaskFinancialAccountPanel extends LightningElement {
  @api taskId;
  /** Same gate as arcTaskDetail's Task Information section (canEditTask,
   *  resolved server-side from the task's Financial Advisor Team). */
  @api editable = false;

  detail = {};
  _detailResult;
  isEditing = false;
  isSaving = false;
  errorMessage = "";
  draftName = "";
  draftAccountNumber = "";

  @wire(getFinancialAccountDetail, { taskId: "$taskId" })
  wiredDetail(result) {
    this._detailResult = result;
    this.detail = result?.data || {};
  }

  get hasFinancialAccount() {
    return Boolean(this.detail?.financialAccountId);
  }

  get name() {
    return this.detail?.name || "";
  }

  get accountNumber() {
    return this.detail?.accountNumber || "";
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  handleEditClick() {
    if (!this.editable) {
      return;
    }
    this.draftName = this.name;
    this.draftAccountNumber = this.accountNumber;
    this.errorMessage = "";
    this.isEditing = true;
  }

  handleCancelClick() {
    if (this.isSaving) {
      return;
    }
    this.isEditing = false;
    this.errorMessage = "";
  }

  handleNameChange(event) {
    this.draftName = event.detail.value;
  }

  handleAccountNumberChange(event) {
    this.draftAccountNumber = event.detail.value;
  }

  async handleSaveClick() {
    if (this.isSaving) {
      return;
    }
    const name = (this.draftName || "").trim();
    if (!name) {
      this.errorMessage = "Financial Account Name is required.";
      return;
    }

    this.isSaving = true;
    this.errorMessage = "";
    try {
      await saveFinancialAccountDetail({
        financialAccountId: this.detail.financialAccountId,
        name,
        accountNumber: this.draftAccountNumber || ""
      });
      await refreshApex(this._detailResult);
      this.isEditing = false;
    } catch (error) {
      this.errorMessage =
        error?.body?.message || error?.message || "Could not save the financial account.";
    } finally {
      this.isSaving = false;
    }
  }
}