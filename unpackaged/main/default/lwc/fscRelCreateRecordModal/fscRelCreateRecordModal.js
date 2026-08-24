/*
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 */
import { api, track } from "lwc";
import LightningModal from "lightning/modal";
import { ensureFscRelModalStyles } from "c/fscRelUtils";

const COMPACT_LAYOUT_QUERY = "(max-width: 48rem)";

export default class FscRelCreateRecordModal extends LightningModal {
  @api objectApiName;
  @api recordTypeId;
  @api headerLabel;
  @api layoutType = "Full";
  @api formColumns = 2;

  @track resolvedFormColumns = 2;
  _compactLayoutQuery;
  _handleCompactLayoutChange;

  get modalHeaderLabel() {
    return this.headerLabel || "New Record";
  }

  get hasRecordTypeId() {
    return Boolean(this.recordTypeId);
  }

  connectedCallback() {
    ensureFscRelModalStyles(this);
    this.syncFormColumns();

    if (typeof window !== "undefined" && window.matchMedia) {
      this._compactLayoutQuery = window.matchMedia(COMPACT_LAYOUT_QUERY);
      this._handleCompactLayoutChange = () => this.syncFormColumns();
      this._compactLayoutQuery.addEventListener(
        "change",
        this._handleCompactLayoutChange
      );
    }
  }

  disconnectedCallback() {
    this._compactLayoutQuery?.removeEventListener(
      "change",
      this._handleCompactLayoutChange
    );
  }

  syncFormColumns() {
    const requestedColumns = Number(this.formColumns) || 2;
    const isCompactLayout =
      typeof window !== "undefined" &&
      window.matchMedia?.(COMPACT_LAYOUT_QUERY)?.matches;

    this.resolvedFormColumns = isCompactLayout ? 1 : requestedColumns;
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