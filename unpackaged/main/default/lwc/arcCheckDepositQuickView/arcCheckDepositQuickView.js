/**
 * Read-only popup card for one Check_Deposit__c record, opened from the
 * Check Log page's Check Deposits card via arcDataTable's cancelable
 * `rownavigate` event — the same pattern as arcOrderTicketQuickView, chosen
 * here because every field on a deposit is read-only, so a popup keeps the
 * user on the check log instead of bouncing them to a separate screen.
 *
 * Loaded through ArcCheckLogController.getCheckDeposit rather than
 * lightning/uiRecordApi: the deposit's financial account is the FinServ
 * object, which the UI API cannot read for portal users (no object
 * permission, Private external sharing), so getRecord would render the
 * account name and number blank — the very fields the popup exists to show.
 */
import { LightningElement, api, wire } from "lwc";
import getCheckDeposit from "@salesforce/apex/ArcCheckLogController.getCheckDeposit";

const CURRENCY_FORMAT = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD"
});

const DATE_TIME_FORMAT = new Intl.DateTimeFormat("en-US", {
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit"
});

const EMPTY = "—";

function asCurrency(value) {
  return value === null || value === undefined
    ? EMPTY
    : CURRENCY_FORMAT.format(value);
}

function asDateTime(value) {
  if (!value) {
    return EMPTY;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? EMPTY : DATE_TIME_FORMAT.format(parsed);
}

function asText(value) {
  return value === null || value === undefined || value === "" ? EMPTY : value;
}

export default class ArcCheckDepositQuickView extends LightningElement {
  isOpen = false;
  errorMessage = "";

  _recordId;
  _detail;

  /** Opens the popup for the given record — called by the parent's rownavigate handler. */
  @api
  open(recordId) {
    this._recordId = recordId;
    this.errorMessage = "";
    this.isOpen = true;
  }

  @wire(getCheckDeposit, { checkDepositId: "$_recordId" })
  wiredDetail({ data, error }) {
    if (data) {
      this._detail = data;
      this.errorMessage = "";
    } else if (error) {
      this._detail = undefined;
      this.errorMessage =
        error?.body?.message || "Unable to load this check deposit right now.";
    }
  }

  get isLoading() {
    return this.isOpen && !this._detail && !this.errorMessage;
  }

  get hasDetail() {
    return Boolean(this._detail);
  }

  get headingLabel() {
    const name = this._detail?.name;
    return name ? `Check Deposit: ${name}` : "Check Deposit";
  }

  /** Every popup row, resolved to display text; empty values show an em dash. */
  get detailRows() {
    const detail = this._detail || {};
    return [
      { label: "Financial Account", value: asText(detail.financialAccountName) },
      { label: "Account Number", value: asText(detail.financialAccountNumber) },
      { label: "Check Log", value: asText(detail.checkLogName) },
      { label: "Amount", value: asCurrency(detail.amount) },
      {
        label: "Employee Deferral Amount",
        value: asCurrency(detail.employeeDeferralAmount)
      },
      {
        label: "Employer Contribution Amount",
        value: asCurrency(detail.employerContributionAmount)
      },
      { label: "Created By", value: asText(detail.createdByName) },
      { label: "Created Date", value: asDateTime(detail.createdDate) },
      { label: "Last Modified By", value: asText(detail.lastModifiedByName) },
      { label: "Last Modified Date", value: asDateTime(detail.lastModifiedDate) }
    ];
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