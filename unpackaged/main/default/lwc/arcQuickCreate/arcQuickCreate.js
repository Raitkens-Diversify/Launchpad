/**
 * Generic "new record" dialog for objects that have no bespoke create form.
 *
 * Rather than hand-roll a bespoke form with its own Apex, this wraps
 * lightning-record-edit-form, which already handles the DML, field-level
 * security, required-field validation and lookup pickers for whatever object
 * and field list it is handed.
 *
 * The field list is supplied by the caller rather than read from the object's
 * page layout: Check_Log__c's assigned layout carries only Name, Financial
 * Account and Owner, which is not the set the old Salesforce list works in.
 */
import { LightningElement, api } from "lwc";
import LightningToast from "lightning/toast";

export default class ArcQuickCreate extends LightningElement {
  @api objectApiName = "";
  @api headingLabel = "New record";
  /** Comma-separated field API names, in the order they should appear. */
  @api fieldApiNames = "";

  isSaving = false;
  errorMessage = "";

  get fields() {
    return (this.fieldApiNames || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean)
      .map((name) => ({ key: name, name }));
  }

  get hasFields() {
    return this.fields.length > 0;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  handleSubmit() {
    this.isSaving = true;
    this.errorMessage = "";
  }

  handleSuccess(event) {
    this.isSaving = false;
    LightningToast.show(
      { label: `${this.headingLabel} saved`, variant: "success" },
      this
    );
    this.dispatchEvent(
      new CustomEvent("created", {
        detail: { recordId: event.detail.id }
      })
    );
  }

  handleError(event) {
    this.isSaving = false;
    // record-edit-form surfaces field errors inline; this is for the rest —
    // a validation rule, a trigger, a required field the caller left out.
    this.errorMessage =
      event.detail?.detail || event.detail?.message || "Could not save.";
  }

  handleSave() {
    this.template.querySelector("lightning-record-edit-form")?.submit();
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  /** Escape closes, matching the app's other dialogs. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}