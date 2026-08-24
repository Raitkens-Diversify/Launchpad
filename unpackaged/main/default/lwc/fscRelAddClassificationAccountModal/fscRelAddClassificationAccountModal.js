/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 */
import { api, track } from "lwc";
import LightningModal from "lightning/modal";
import linkClassificationAccountToHousehold from "@salesforce/apex/FscRelHouseholdController.linkClassificationAccountToHousehold";
import { ensureFscRelModalStyles, extractApexError } from "c/fscRelUtils";

export default class FscRelAddClassificationAccountModal extends LightningModal {
  @api rootAccountId;
  @api rootAccountName = "";
  @api classificationValue = "";
  @api classificationLabel = "";

  @track accountId = "";
  @track accountName = "";
  @track bannerMessage = "";
  @track bannerVariant = "error";
  @track isSaving = false;

  connectedCallback() {
    ensureFscRelModalStyles(this);
  }

  get lookupCreateEnabled() {
    return false;
  }

  get resolvedClassificationLabel() {
    const label = String(
      this.classificationLabel || this.classificationValue || "Account"
    ).trim();

    return label.startsWith("Add ") ? label.slice(4) : label;
  }

  get modalTitle() {
    return `Add ${this.resolvedClassificationLabel}`;
  }

  get modalInstruction() {
    return "Search for any account to link to this household. Saving creates a Household account relationship.";
  }

  get hasBanner() {
    return Boolean(this.bannerMessage);
  }

  get bannerClass() {
    const variant =
      this.bannerVariant === "success"
        ? "slds-theme_success"
        : this.bannerVariant === "warning"
          ? "slds-theme_warning"
          : "slds-theme_error";
    return `modal-banner slds-notify slds-notify_alert ${variant}`;
  }

  get isSaveDisabled() {
    return this.isSaving || !this.accountId;
  }

  get saveButtonLabel() {
    return this.isSaving ? "Saving..." : "Save";
  }

  get cancelButtonLabel() {
    return this.isSaving ? "Saving..." : "Cancel";
  }

  handleAccountChange(event) {
    this.accountId = event.detail?.recordId || "";
    this.accountName = event.detail?.recordLabel || "";
    this.bannerMessage = "";
  }

  handleModalBodyClick() {
    this.bannerMessage = "";
  }

  handleCancel() {
    this.close({ confirmed: false });
  }

  async handleSave() {
    if (this.isSaveDisabled) {
      return;
    }

    this.isSaving = true;
    this.bannerMessage = "";

    try {
      const result = await linkClassificationAccountToHousehold({
        rootAccountId: this.rootAccountId,
        accountId: this.accountId,
        classificationValue: this.classificationValue
      });

      if (result?.success) {
        this.close({
          confirmed: true,
          message: result.message || "Account added.",
          accountId: result.accountId || this.accountId
        });
        return;
      }

      this.bannerMessage = result?.message || "Unable to add the selected account.";
      this.bannerVariant = "error";
    } catch (error) {
      this.bannerMessage = extractApexError(
        error,
        "Unexpected error adding the selected account."
      );
      this.bannerVariant = "error";
    } finally {
      this.isSaving = false;
    }
  }
}