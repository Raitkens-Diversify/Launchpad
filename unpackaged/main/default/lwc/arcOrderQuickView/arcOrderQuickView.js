/**
 * Read-only popup card for one Order__c record, opened from the Order
 * Ticket quick view's Orders section. Order__c has no page of its own in
 * this site (no entry in recordNavigationCommunityUtils' route map), so a
 * row click opens this instead of navigating -- the same reasoning
 * c/arcOrderTicketQuickView documents for itself.
 *
 * Field set is limited to what the community permission set actually
 * grants FLS on for Order__c (Strategy__c, Initial_Funding_Amount__c,
 * Initial_Funding_Percentage__c, Total_Initial_Funding_Amount__c,
 * Order_Ticket__c) plus the standard Name/audit fields -- confirmed against
 * a live describe of Order__c on launchpad, not the permission set's field
 * list alone: it still carries a stale FLS entry for Funding_Basis__c, a
 * field that does not actually exist on this object. Nothing here is
 * editable.
 */
import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getFieldDisplayValue
} from "lightning/uiRecordApi";

const OBJECT_API_NAME = "Order__c";

/** Label/path pairs for the plain rows, in the order they render. */
const DETAIL_FIELDS = [
  { label: "Strategy", path: "Strategy__r.Name" },
  { label: "Initial Funding Amount", path: "Initial_Funding_Amount__c" },
  {
    label: "Initial Funding Percentage",
    path: "Initial_Funding_Percentage__c"
  },
  {
    label: "Total Initial Funding Amount",
    path: "Total_Initial_Funding_Amount__c"
  },
  { label: "Order Ticket", path: "Order_Ticket__r.Name" },
  { label: "Created By", path: "CreatedBy.Name" },
  { label: "Last Modified By", path: "LastModifiedBy.Name" }
];

const FIELDS = [
  `${OBJECT_API_NAME}.Name`,
  ...DETAIL_FIELDS.map((field) => `${OBJECT_API_NAME}.${field.path}`)
];

export default class ArcOrderQuickView extends LightningElement {
  isOpen = false;
  errorMessage = "";

  _recordId;
  _record;

  /** Opens the popup for the given record -- called by arcOrderTicketQuickView's row click handler. */
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
    return name ? `Order: ${name}` : "Order";
  }

  /** The plain rows, resolved to display values; empty values show as an em dash. */
  get detailRows() {
    return DETAIL_FIELDS.map((field) => {
      const value = this.fieldValue(field.path);
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