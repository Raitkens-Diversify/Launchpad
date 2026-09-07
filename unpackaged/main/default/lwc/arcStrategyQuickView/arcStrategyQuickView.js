/**
 * Read-only popup card for one Strategy__c record, opened from the Strategy
 * hyperlink on both arcOrderQuickView and the Orders table in
 * arcOrderTicketQuickView. Strategy__c has no page of its own in this site,
 * so a click opens this instead of navigating -- the same reasoning
 * c/arcOrderTicketQuickView documents for itself.
 *
 * Field set matches the internal Strategy record page's Details tab
 * (Status, Owner, Strategy Code, the four "is this a ... ?" checkboxes,
 * Created/Last Modified By) -- not guessed. Community FLS for these fields
 * did not exist before this popup; it ships alongside the permission set
 * grant that makes them actually readable (Envelope_Wizard_Community).
 */
import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getFieldDisplayValue
} from "lightning/uiRecordApi";

const OBJECT_API_NAME = "Strategy__c";
const BOOLEAN_TYPE = "boolean";

/** Label/path pairs for the plain rows, in the order they render. */
const DETAIL_FIELDS = [
  { label: "Status", path: "Status__c" },
  { label: "Owner", path: "Owner.Name" },
  { label: "Strategy Code", path: "Strategy_Code__c" },
  { label: "Interval Fund?", path: "Interval_Fund__c", type: BOOLEAN_TYPE },
  { label: "Bond Ladder?", path: "Bond_Ladder__c", type: BOOLEAN_TYPE },
  {
    label: "Structured Note?",
    path: "Structured_Note__c",
    type: BOOLEAN_TYPE
  },
  {
    label: "Short Term Cash Management?",
    path: "Short_Term_Cash_Management__c",
    type: BOOLEAN_TYPE
  },
  { label: "Created By", path: "CreatedBy.Name" },
  { label: "Last Modified By", path: "LastModifiedBy.Name" }
];

const FIELDS = [
  `${OBJECT_API_NAME}.Name`,
  ...DETAIL_FIELDS.map((field) => `${OBJECT_API_NAME}.${field.path}`)
];

export default class ArcStrategyQuickView extends LightningElement {
  isOpen = false;
  errorMessage = "";

  _recordId;
  _record;

  /** Opens the popup for the given record -- called by the parent's Strategy link click handler. */
  @api
  open(recordId) {
    this._recordId = recordId;
    this.errorMessage = "";
    this.isOpen = true;
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

  fieldValue(path) {
    if (!this._record) {
      return undefined;
    }
    const qualified = `${OBJECT_API_NAME}.${path}`;
    const displayValue = getFieldDisplayValue(this._record, qualified);
    return displayValue ?? getFieldValue(this._record, qualified);
  }

  get isLoading() {
    return this.isOpen && !this._record && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._record);
  }

  get headingLabel() {
    const name = this.fieldValue("Name");
    return name ? `Strategy: ${name}` : "Strategy";
  }

  /** The plain rows, resolved to display values; booleans render as Yes/No, empty values as an em dash. */
  get detailRows() {
    return DETAIL_FIELDS.map((field) => {
      const value = this.fieldValue(field.path);
      if (field.type === BOOLEAN_TYPE) {
        return {
          label: field.label,
          value: value === true ? "Yes" : value === false ? "No" : "—"
        };
      }
      return {
        label: field.label,
        value: value === undefined || value === null || value === ""
          ? "—"
          : value
      };
    });
  }

  handleClose() {
    this.isOpen = false;
  }

  /** Escape closes, matching the other quick-view dialogs. */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.handleClose();
    }
  }
}