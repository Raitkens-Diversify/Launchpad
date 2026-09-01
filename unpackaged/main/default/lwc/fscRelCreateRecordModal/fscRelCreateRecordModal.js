/*
 * Author: Hoang Long Vu To
 * Date: 2026-09-01
 */
import { api, track, wire } from "lwc";
import LightningModal from "lightning/modal";
import { getRecordCreateDefaults } from "lightning/uiRecordApi";
import { ensureFscRelModalStyles } from "c/fscRelUtils";

const COMPACT_LAYOUT_QUERY = "(max-width: 48rem)";
const LAYOUT_FIELD_BLOCKLIST = new Set(["RecordTypeId"]);

const extractLayoutFieldApiNames = (createDefaults) => {
  const fieldNames = [];
  const seen = new Set();

  for (const section of createDefaults?.layout?.sections || []) {
    for (const row of section.layoutRows || []) {
      for (const item of row.layoutItems || []) {
        for (const component of item.layoutComponents || []) {
          const apiName = String(component?.apiName || "").trim();
          if (!apiName || seen.has(apiName) || LAYOUT_FIELD_BLOCKLIST.has(apiName)) {
            continue;
          }

          seen.add(apiName);
          fieldNames.push(apiName);
        }
      }
    }
  }

  return fieldNames;
};

export default class FscRelCreateRecordModal extends LightningModal {
  @api objectApiName;
  @api recordTypeId;
  @api headerLabel;
  @api layoutType = "Full";
  @api formColumns = 2;
  @api defaultFieldValues = {};

  @track resolvedFormColumns = 2;
  @track layoutFieldNames = [];
  @track layoutLoadFailed = false;
  @track layoutLoadComplete = false;

  _compactLayoutQuery;
  _handleCompactLayoutChange;

  get modalHeaderLabel() {
    return this.headerLabel || "New Record";
  }

  get normalizedDefaultFieldValues() {
    return this.defaultFieldValues &&
      typeof this.defaultFieldValues === "object" &&
      !Array.isArray(this.defaultFieldValues)
      ? this.defaultFieldValues
      : {};
  }

  get hasRecordTypeId() {
    return Boolean(this.recordTypeId);
  }

  get useLayoutDrivenForm() {
    return this.hasRecordTypeId && this.layoutFieldNames.length > 0;
  }

  get useFallbackRecordForm() {
    if (!this.hasRecordTypeId) {
      return true;
    }

    return this.layoutLoadComplete && (this.layoutLoadFailed || this.layoutFieldNames.length === 0);
  }

  get showLayoutSpinner() {
    return this.hasRecordTypeId && !this.layoutLoadComplete;
  }

  get layoutFields() {
    const defaults = this.normalizedDefaultFieldValues;

    return this.layoutFieldNames.map((fieldName) => {
      const value = defaults[fieldName];
      const hasValue =
        value !== undefined && value !== null && String(value).trim() !== "";

      return {
        key: fieldName,
        name: fieldName,
        value: hasValue ? value : undefined,
        hasValue
      };
    });
  }

  @wire(getRecordCreateDefaults, {
    objectApiName: "$objectApiName",
    recordTypeId: "$recordTypeId",
    formFactor: "Large"
  })
  wiredRecordCreateDefaults({ data, error }) {
    if (!this.hasRecordTypeId) {
      this.layoutFieldNames = [];
      this.layoutLoadFailed = false;
      this.layoutLoadComplete = true;
      return;
    }

    if (data) {
      this.layoutFieldNames = extractLayoutFieldApiNames(data);
      this.layoutLoadFailed = this.layoutFieldNames.length === 0;
      this.layoutLoadComplete = true;
      return;
    }

    if (error) {
      this.layoutFieldNames = [];
      this.layoutLoadFailed = true;
      this.layoutLoadComplete = true;
    }
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
      this.close({
        recordId,
        recordLabel: this.resolveCreatedRecordLabel(event.detail?.fields)
      });
    }
  }

  resolveCreatedRecordLabel(fields) {
    const nameValue = fields?.Name?.value;
    if (nameValue) {
      return String(nameValue);
    }

    const firstName = fields?.FirstName?.value;
    const lastName = fields?.LastName?.value;
    const personName = [firstName, lastName].filter(Boolean).join(" ").trim();

    return personName;
  }

  handleCancel() {
    this.close();
  }

  handleError() {
    // Field-level errors render inline on the form.
  }
}