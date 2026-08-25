/**
 * New Advertising Request modal — replicates Case_Screen_Flow_New_Ad_Hoc_Case's single screen
 * (Account Name search, Subject, Description, Priority, Status) as an in-page dialog opened from
 * the Home dashboard header, instead of launching the full-screen flow. Save creates the Case via
 * ArcNewAdvertisingRequestController.createAdvertisingRequest, which mirrors the flow's own
 * Set_Case/Create_Case field assignments.
 */
import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LightningToast from "lightning/toast";
import searchAccounts from "@salesforce/apex/ArcNewAdvertisingRequestController.searchAccounts";
import createAdvertisingRequest from "@salesforce/apex/ArcNewAdvertisingRequestController.createAdvertisingRequest";
import { buildRecordNavigationReference } from "c/recordNavigationUtils";

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_TERM_LENGTH = 2;

const PRIORITY_OPTIONS = [
  { label: "High", value: "High" },
  { label: "Medium", value: "Medium" },
  { label: "Low", value: "Low" }
];

const STATUS_OPTIONS = [
  { label: "New", value: "New" },
  { label: "In Progress", value: "In Progress" },
  { label: "Escalated", value: "Escalated" },
  { label: "Closed", value: "Closed" }
];

const DEFAULT_STATUS = "New";

const EMPTY_FORM = {
  accountId: "",
  accountName: "",
  subject: "",
  description: "",
  priority: "",
  status: DEFAULT_STATUS
};

export default class ArcNewAdvertisingRequestModal extends NavigationMixin(
  LightningElement
) {
  @track form = { ...EMPTY_FORM };
  @track accountOptions = [];
  isAccountMenuOpen = false;
  accountSearchTerm = "";
  isSaving = false;

  priorityOptions = PRIORITY_OPTIONS;
  statusOptions = STATUS_OPTIONS;

  _searchTimer;
  _isOpen = false;

  @api
  get isOpen() {
    return this._isOpen;
  }
  set isOpen(value) {
    this._isOpen = value;
    if (value) {
      this.resetForm();
    }
  }

  get accountDisplayValue() {
    return this.isAccountMenuOpen
      ? this.accountSearchTerm
      : this.form.accountName;
  }

  get hasAccountOptions() {
    return this.accountOptions.length > 0;
  }

  get showAccountEmptyState() {
    return (
      this.isAccountMenuOpen &&
      !this.hasAccountOptions &&
      this.accountSearchTerm.trim().length >= MIN_SEARCH_TERM_LENGTH
    );
  }

  get isSaveDisabled() {
    if (this.isSaving) {
      return true;
    }
    return !(
      this.form.accountId &&
      this.form.subject.trim() &&
      this.form.priority &&
      this.form.status
    );
  }

  handleAccountFocus() {
    this.isAccountMenuOpen = true;
    this.accountSearchTerm = "";
  }

  handleAccountInput(event) {
    this.isAccountMenuOpen = true;
    this.accountSearchTerm = event.target.value;
    this.form = { ...this.form, accountId: "", accountName: "" };

    window.clearTimeout(this._searchTimer);
    const term = this.accountSearchTerm.trim();
    if (term.length < MIN_SEARCH_TERM_LENGTH) {
      this.accountOptions = [];
      return;
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._searchTimer = window.setTimeout(() => {
      searchAccounts({ term })
        .then((results) => {
          this.accountOptions = results || [];
        })
        .catch((error) => {
          // eslint-disable-next-line no-console
          console.error(
            "[arcNewAdvertisingRequestModal] Account search failed",
            error
          );
          this.accountOptions = [];
        });
    }, SEARCH_DEBOUNCE_MS);
  }

  handleAccountOptionMouseDown(event) {
    // Keep focus in the input on option press, matching envelopeSearchableCombobox — otherwise
    // the input's blur/focusout would close the menu before the click registers.
    event.preventDefault();
  }

  handleAccountOptionClick(event) {
    const { id, name } = event.currentTarget.dataset;
    this.form = { ...this.form, accountId: id, accountName: name };
    this.accountSearchTerm = "";
    this.accountOptions = [];
    this.isAccountMenuOpen = false;
  }

  handleAccountBlur(event) {
    // Menu options live inside this same template, so a blur that lands on one of them isn't a
    // real "leave the field" — only close when focus goes somewhere outside this component.
    if (event.relatedTarget && this.template.contains(event.relatedTarget)) {
      return;
    }
    this.isAccountMenuOpen = false;
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }
    const value = event.detail?.value ?? event.target.value;
    this.form = { ...this.form, [field]: value };
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  async handleSave() {
    const { accountId, subject, description, priority, status } = this.form;
    this.isSaving = true;
    try {
      const caseId = await createAdvertisingRequest({
        accountId,
        subject,
        description,
        priority,
        status
      });

      this.dispatchEvent(new CustomEvent("close"));

      const pageReference = buildRecordNavigationReference(caseId, "Case");
      if (pageReference) {
        this[NavigationMixin.Navigate](pageReference);
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(
        "[arcNewAdvertisingRequestModal] Failed to create advertising request",
        error
      );
      const message =
        error?.body?.message ||
        error?.message ||
        "Unable to create the advertising request.";
      LightningToast.show(
        { label: "Create failed", message, variant: "error" },
        this
      );
    } finally {
      this.isSaving = false;
    }
  }

  resetForm() {
    this.form = { ...EMPTY_FORM };
    this.accountSearchTerm = "";
    this.accountOptions = [];
    this.isAccountMenuOpen = false;
    this.isSaving = false;
  }
}