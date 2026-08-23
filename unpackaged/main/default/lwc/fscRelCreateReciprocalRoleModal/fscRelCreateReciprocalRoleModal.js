/*
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 */
import { api, track } from "lwc";
import LightningModal from "lightning/modal";
import validateReciprocalRoleForCreate from "@salesforce/apex/FscRelHouseholdController.validateReciprocalRoleForCreate";
import createReciprocalRole from "@salesforce/apex/FscRelHouseholdController.createReciprocalRole";
import { ensureFscRelModalStyles } from "c/fscRelUtils";

export default class FscRelCreateReciprocalRoleModal extends LightningModal {
  @api headerLabel = "New Reciprocal Role";
  @api recordTypeDeveloperName;

  @track role = "";
  @track bannerMessage = "";
  @track bannerVariant = "error";
  @track isSaving = false;
  @track duplicateConfirmed = false;
  @track showDuplicateWarning = false;

  connectedCallback() {
    ensureFscRelModalStyles(this);
  }

  get modalHeaderLabel() {
    return this.headerLabel || "New Reciprocal Role";
  }

  get saveButtonLabel() {
    if (this.isSaving) {
      return "Saving...";
    }

    return this.showDuplicateWarning ? "Save Anyway" : "Save";
  }

  get cancelButtonLabel() {
    return this.isSaving ? "Saving..." : "Cancel";
  }

  get isSaveDisabled() {
    return this.isSaving || !this.role?.trim();
  }

  get bannerClass() {
    const variant =
      this.bannerVariant === "warning"
        ? "slds-theme_warning"
        : "slds-theme_error";
    return `modal-banner slds-notify slds-notify_alert ${variant}`;
  }

  get hasBanner() {
    return Boolean(this.bannerMessage);
  }

  handleRoleChange(event) {
    this.role = event.detail.value || "";
    this.resetDuplicateState();
  }

  resetDuplicateState() {
    this.duplicateConfirmed = false;
    this.showDuplicateWarning = false;
    this.bannerMessage = "";
    this.bannerVariant = "error";
  }

  handleCancel() {
    this.close();
  }

  async handleSave() {
    if (this.isSaving) {
      return;
    }

    const trimmedRole = (this.role || "").trim();

    if (!trimmedRole) {
      this.bannerVariant = "error";
      this.bannerMessage = "Role is required.";
      return;
    }

    this.isSaving = true;
    this.bannerMessage = "";

    try {
      if (!this.duplicateConfirmed) {
        const validation = await validateReciprocalRoleForCreate({
          role: trimmedRole
        });

        if (validation?.blockSave) {
          this.bannerVariant = "error";
          this.bannerMessage =
            validation.message || "This reciprocal role already exists.";
          this.showDuplicateWarning = false;
          this.duplicateConfirmed = false;
          return;
        }

        if (validation?.requiresConfirmation) {
          this.bannerVariant = "warning";
          this.bannerMessage = validation.message;
          this.showDuplicateWarning = true;
          this.duplicateConfirmed = true;
          return;
        }
      }

      const result = await createReciprocalRole({
        role: trimmedRole,
        confirmDuplicate: this.duplicateConfirmed === true,
        recordTypeDeveloperName: this.recordTypeDeveloperName || null
      });

      if (!result?.success) {
        this.bannerVariant = "error";
        this.bannerMessage = result?.message || "Failed to create reciprocal role.";
        this.resetDuplicateState();
        return;
      }

      this.close({
        recordId: result.reciprocalRoleId,
        roleLabel: result.roleLabel
      });
    } catch (error) {
      this.bannerVariant = "error";
      this.bannerMessage =
        error?.body?.message ||
        error?.message ||
        "Failed to create reciprocal role.";
      this.resetDuplicateState();
    } finally {
      this.isSaving = false;
    }
  }
}