/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 */
import { api } from "lwc";
import LightningModal from "lightning/modal";
import { ensureFscRelModalStyles } from "c/fscRelUtils";

export default class FscRelCreateRecordModal extends LightningModal {
  @api objectApiName;
  @api recordTypeId;
  @api headerLabel;
  @api layoutType = "Full";
  @api formColumns = 2;

  get modalHeaderLabel() {
    return this.headerLabel || "New Record";
  }

  get hasRecordTypeId() {
    return Boolean(this.recordTypeId);
  }

  connectedCallback() {
    ensureFscRelModalStyles(this);
  }

  handleSuccess(event) {
    const recordId = event.detail?.id;
    if (recordId) {
      this.close({ recordId });
    }
  }

  handleCancel() {
    this.close();
  }

  handleError() {
    // lightning-record-form surfaces field errors inline.
  }
}