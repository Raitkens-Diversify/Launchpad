/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Native HTML field control for arcRecordDetail — consistent styling independent of
 * envelopeFieldControl / SLDS base components.
 */
import { LightningElement, api } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import {
  applyInputMask,
  draftValuesEqual,
  isEmptyValue,
  isFormatValid
} from 'c/envelopeFormSchema';

/**
 * A date field's wire value can arrive as 'YYYY-MM-DD', a full ISO datetime,
 * or an epoch number; a native <input type="date"> needs plain 'YYYY-MM-DD'.
 * Declared here because this used to be imported from c/envelopeFormSchema,
 * which never exported it — harmless while inline editing was disabled, fatal
 * ("normalizeDateWireValue is not a function") the moment an edit-mode date
 * control rendered.
 */
const normalizeDateWireValue = (value) => {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  if (typeof value === 'number') {
    const fromEpoch = new Date(value);
    return isNaN(fromEpoch.getTime())
      ? ''
      : fromEpoch.toISOString().slice(0, 10);
  }
  const match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
};
// The owner lookup can't use lightning-record-picker: OwnerId is polymorphic
// (User and Group) and referenceTo resolves to Group, so the picker offered
// only queues. This search is the one the Lightning task tile uses — active
// Users plus Queues together.
import searchUsers from '@salesforce/apex/CaseCurrentTaskController.searchUsers';
// FA team candidates: everything but explicitly Inactive teams (most working
// teams carry no Status__c at all).
import searchFaTeams from '@salesforce/apex/ArcRecordDetailController.searchFinancialAdvisorTeams';

export default class ArcRecordDetailField extends LightningElement {
  @api field;
  /**
   * Renders the control disabled. Only lookups use it: a reference field has no
   * readable text to fall back on — the raw value is an 18-character id — so the
   * row keeps its record picker in read mode and disables it, rather than
   * printing the id the way the plain value box would.
   */
  @api readOnly = false;

  _stylesLoaded = false;
  _validationMessage = '';

  connectedCallback() {
    if (this._stylesLoaded) {
      return;
    }
    loadStyle(this, diversifyStyles).catch(() => {
      // Non-fatal: fall back to local token defaults.
    });
    this._stylesLoaded = true;
  }

  get isTextInput() {
    return (
      this.isText ||
      this.isNumber ||
      this.isDate ||
      this.isDateTime ||
      this.isUnsupported
    );
  }

  /*
   * COMBOBOX is a real Salesforce display type, not a UI widget: Task.Subject is
   * one — free text that also offers the values of a picklist. It stores a
   * string, so it edits as one. Left out of this list it fell through to
   * isUnsupported, which is what put "Unsupported DataType: ComboBox" on every
   * Task and made the whole form refuse to save.
   */
  get isText() {
    return ['STRING', 'EMAIL', 'PHONE', 'URL', 'COMBOBOX'].includes(
      this.normalizedType
    );
  }

  get isReference() {
    return this.normalizedType === 'REFERENCE';
  }

  /**
   * The task owner lookup gets its own search (active Users + Queues, like the
   * Lightning task page): OwnerId is polymorphic and referenceTo resolves to
   * Group, which made the record picker offer only queues.
   */
  get isOwnerLookup() {
    return this.isReference && this.field?.apiName === 'OwnerId';
  }

  /** The object a lookup's candidates come from; blank hides the picker.
   *  WhatId/WhoId are polymorphic and referenceTo lands on the wrong member,
   *  so the task page's Related To / Name are pinned to what they actually
   *  hold in this org: Cases and Contacts. */
  get referenceObjectApiName() {
    const apiName = this.field?.apiName;
    if (apiName === 'WhatId') {
      return 'Case';
    }
    if (apiName === 'WhoId') {
      return 'Contact';
    }
    return this.field?.referenceTo || '';
  }

  get showReferencePicker() {
    return (
      this.isReference &&
      !this.usesCustomSearch &&
      Boolean(this.referenceObjectApiName)
    );
  }

  /**
   * The Financial Advisor Team lookup also gets the custom search: the raw
   * picker offered every team, Inactive included. The Apex search keeps
   * Active and unstamped teams (most working teams have no Status__c) and
   * drops only the explicitly Inactive ones.
   */
  get isFaTeamLookup() {
    return (
      this.isReference && this.field?.apiName === 'Financial_Advisor_Team__c'
    );
  }

  get usesCustomSearch() {
    return this.isOwnerLookup || this.isFaTeamLookup;
  }

  get customSearchPlaceholder() {
    return this.isOwnerLookup
      ? 'Search people and queues...'
      : 'Search financial advisor teams...';
  }

  get referenceValue() {
    const value = this.field?.value;
    return value === null || value === undefined ? null : String(value);
  }

  get isTextarea() {
    return this.field?.type === 'TEXTAREA';
  }

  get isNumber() {
    return ['DOUBLE', 'INTEGER', 'CURRENCY', 'PERCENT'].includes(this.field?.type);
  }

  get isBoolean() {
    return this.field?.type === 'BOOLEAN';
  }

  get isDate() {
    return this.field?.type === 'DATE';
  }

  get isDateTime() {
    return this.field?.type === 'DATETIME';
  }

  get isPicklist() {
    return this.normalizedType === 'PICKLIST';
  }

  get isMultiPicklist() {
    return this.normalizedType === 'MULTIPICKLIST';
  }

  get normalizedType() {
    return String(this.field?.type || '').toUpperCase();
  }

  get isAddRecord() {
    return this.field?.type === 'ADD_RECORD' || !!this.field?.addRecord;
  }

  get isUnsupported() {
    return (
      !!this.field &&
      !this.isAddRecord &&
      !this.isText &&
      !this.isTextarea &&
      !this.isNumber &&
      !this.isBoolean &&
      !this.isDate &&
      !this.isDateTime &&
      !this.isPicklist &&
      !this.isMultiPicklist &&
      !this.usesCustomSearch &&
      !this.showReferencePicker
    );
  }

  get unsupportedMessage() {
    return `Unsupported field type: ${this.field?.type}`;
  }

  get inputType() {
    if (this.isUnsupported) {
      return 'text';
    }
    if (this.field?.type === 'EMAIL') {
      return 'email';
    }
    if (this.field?.type === 'PHONE') {
      return 'tel';
    }
    if (this.field?.type === 'URL') {
      return 'url';
    }
    if (this.isNumber) {
      return 'number';
    }
    if (this.isDate) {
      return 'date';
    }
    if (this.isDateTime) {
      return 'datetime-local';
    }
    return 'text';
  }

  get stringValue() {
    const value = this.field?.value;
    if (value === null || value === undefined) {
      return '';
    }
    if (this.isDate) {
      return normalizeDateWireValue(value) || '';
    }
    if (this.isDateTime) {
      return this.toDatetimeLocalValue(value);
    }
    return String(value);
  }

  get textareaValue() {
    return this.field?.value ?? '';
  }

  get selectValue() {
    return this.resolvePicklistValue(this.field?.value);
  }

  get isChecked() {
    return this.field?.value === true || this.field?.value === 'true';
  }

  get picklistOptions() {
    return this.field?.picklistOptions || [];
  }

  get picklistOptionsWithSelection() {
    const selectedValue = this.selectValue;
    return this.picklistOptions.map((option) => ({
      ...option,
      isSelected: String(option.value) === String(selectedValue)
    }));
  }

  get multiPicklistValues() {
    const raw = this.field?.value;
    if (Array.isArray(raw)) {
      return raw;
    }
    if (typeof raw === 'string' && raw.trim()) {
      return raw.split(';').map((entry) => entry.trim()).filter(Boolean);
    }
    return [];
  }

  get multiPicklistOptions() {
    const selected = new Set(this.multiPicklistValues);
    return this.picklistOptions.map((option) => ({
      ...option,
      checked: selected.has(option.value) || selected.has(option.label)
    }));
  }

  get placeholder() {
    if (this.isUnsupported) {
      return this.unsupportedMessage;
    }
    if (this.isDate) {
      return 'Select a date';
    }
    if (this.isDateTime) {
      return 'Select a date & time';
    }
    if (this.isText || this.isNumber || this.isTextarea) {
      return `Enter ${this.humanizeLabel(this.field?.label)}`;
    }
    return undefined;
  }

  get lookupClass() {
    return this.readOnly ? 'rdf-lookup rdf-lookup--readonly' : 'rdf-lookup';
  }

  get lookupPlaceholder() {
    return `Search ${this.humanizeLabel(this.field?.label)}...`;
  }

  get maxLength() {
    return (this.isText || this.isTextarea) && this.field?.maxLength > 0
      ? this.field.maxLength
      : undefined;
  }

  get numberStep() {
    const scale = this.field?.scale;
    return scale > 0 ? `0.${'0'.repeat(scale - 1)}1` : '1';
  }

  get minValue() {
    return (this.isNumber || this.isDate) && this.field?.minValue
      ? this.field.minValue
      : undefined;
  }

  get maxValue() {
    return (this.isNumber || this.isDate) && this.field?.maxValue
      ? this.field.maxValue
      : undefined;
  }

  get pattern() {
    return this.isText && this.field?.pattern ? this.field.pattern : undefined;
  }

  get ariaLabel() {
    return this.field?.label || 'Field';
  }

  get showValidationMessage() {
    return !!this._validationMessage;
  }

  get validationMessage() {
    return this._validationMessage;
  }

  get hasValidationError() {
    return !!this._validationMessage;
  }

  get inputClass() {
    const base = 'rdf-input div-input div-input--record-detail';
    return this.hasValidationError ? `${base} div-input--error` : base;
  }

  get textareaClass() {
    const base = 'rdf-textarea div-textarea div-input--record-detail';
    return this.hasValidationError ? `${base} div-input--error` : base;
  }

  get selectClass() {
    const base = 'rdf-select div-select div-input--record-detail';
    return this.hasValidationError ? `${base} div-input--error` : base;
  }

  renderedCallback() {
    /*
     * <textarea> has no value attribute — its value is its child text — so the
     * template binding never populated it and every long-text field opened
     * blank however much the record held. Assigned here instead, and only when
     * it differs, so a keystroke is never overwritten mid-edit.
     */
    if (this.isTextarea) {
      const textarea = this.template.querySelector('textarea.rdf-textarea');
      const nextText = String(this.textareaValue ?? '');
      if (textarea && textarea.value !== nextText) {
        textarea.value = nextText;
      }
      return;
    }

    if (!this.isPicklist) {
      return;
    }

    const select = this.template.querySelector('select.rdf-select');
    const nextValue = this.selectValue;
    if (!select || !nextValue || select.value === nextValue) {
      return;
    }

    select.value = nextValue;
  }

  handleInputChange(event) {
    let value = event.target.value;

    if (this.field?.format && this.isText) {
      value = applyInputMask(this.field.format, value, this.stringValue);
      event.target.value = value;
    }

    if (this.isDateTime) {
      value = this.fromDatetimeLocalValue(value);
    }

    if (this.isNumber && value !== '') {
      value = Number(value);
      if (!Number.isFinite(value)) {
        return;
      }
    }

    this.clearValidationMessage();
    this.emitChange(value);
  }

  handleCheckboxChange(event) {
    this.clearValidationMessage();
    this.emitChange(event.target.checked);
  }

  handleSelectChange(event) {
    this.clearValidationMessage();
    this.emitChange(event.target.value);
  }

  handleMultiChange(event) {
    const optionValue = event.target.value;
    const current = this.multiPicklistValues;
    const next = event.target.checked
      ? [...current, optionValue]
      : current.filter((entry) => entry !== optionValue);

    this.clearValidationMessage();
    this.emitChange(next);
  }

  /* record-picker clears to null, which is what the save payload needs too. */
  /* ── Custom lookup search (Assigned To: Users + Queues; FA Team: non-
        Inactive teams) ─────────────────────────────────────────────────── */

  /** null = untouched, so the box seeds with the current value's name. */
  _customSearchTerm = null;
  customSearchResults = [];
  isCustomDropdownOpen = false;

  get customSearchTerm() {
    if (this._customSearchTerm !== null) {
      return this._customSearchTerm;
    }
    return this.field?.referenceLabel || '';
  }

  async handleCustomSearch(event) {
    const value = (event.target.value || '').trim();
    this._customSearchTerm = event.target.value || '';
    if (!value) {
      this.customSearchResults = [];
      this.isCustomDropdownOpen = false;
      return;
    }
    try {
      const search = this.isOwnerLookup ? searchUsers : searchFaTeams;
      this.customSearchResults = await search({ searchKey: value });
      this.isCustomDropdownOpen = this.customSearchResults.length > 0;
    } catch (error) {
      this.customSearchResults = [];
      this.isCustomDropdownOpen = false;
    }
  }

  handleCustomSelect(event) {
    const { value, label } = event.currentTarget.dataset;
    this._customSearchTerm = label || '';
    this.isCustomDropdownOpen = false;
    this.customSearchResults = [];
    this.emitChange(value || null);
  }

  handleReferenceChange(event) {
    this.clearValidationMessage();
    this.emitChange(event.detail?.recordId ?? null);
  }

  handleBlur() {
    this.reportValidity();
  }

  @api
  flushPendingEdits() {
    // Native inputs commit on change; nothing buffered.
  }

  @api
  resetValue() {
    this.clearValidationMessage();

    if (this.usesCustomSearch) {
      this._customSearchTerm = null;
      this.customSearchResults = [];
      this.isCustomDropdownOpen = false;
      return;
    }

    const control = this.primaryControl();
    if (!control) {
      return;
    }

    if (control.type === 'checkbox' && !control.closest('.rdf-multi')) {
      control.checked = this.isChecked;
      return;
    }

    if (control.tagName === 'SELECT') {
      control.value = this.selectValue;
      return;
    }

    if (this.isMultiPicklist) {
      const selected = new Set(this.multiPicklistValues);
      this.template.querySelectorAll('.rdf-multi__checkbox').forEach((input) => {
        input.checked = selected.has(input.value);
      });
      return;
    }

    control.value = this.stringValue;
  }

  @api
  reportValidity() {
    const valid = this.runValidation();
    this._validationMessage = valid ? '' : this.buildValidationMessage();
    return valid;
  }

  @api
  checkValidity() {
    return this.runValidation();
  }

  runValidation() {
    const value = this.field?.value;

    if (this.field?.required && isEmptyValue(value)) {
      return false;
    }

    return isFormatValid(this.field, value);
  }

  buildValidationMessage() {
    if (this.field?.required && isEmptyValue(this.field?.value)) {
      return 'Complete this field.';
    }
    return this.field?.patternError || 'Enter a valid value.';
  }

  clearValidationMessage() {
    this._validationMessage = '';
  }

  emitChange(value) {
    if (draftValuesEqual(this.field?.value, value)) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent('valuechange', {
        detail: {
          field: this.field?.apiName,
          value
        }
      })
    );
  }

  resolvePicklistValue(rawValue) {
    if (rawValue === null || rawValue === undefined || rawValue === '') {
      return '';
    }

    const text = String(rawValue).trim();
    const options = this.picklistOptions;
    const byValue = options.find((option) => String(option.value) === text);
    if (byValue) {
      return String(byValue.value);
    }

    const lowered = text.toLowerCase();
    const byLabel = options.find(
      (option) => String(option.label || '').trim().toLowerCase() === lowered
    );
    return byLabel ? String(byLabel.value) : text;
  }

  primaryControl() {
    return this.template.querySelector(
      '.rdf-input, .rdf-select, .rdf-textarea, .rdf-checkbox'
    );
  }

  toDatetimeLocalValue(value) {
    if (!value) {
      return '';
    }
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      return '';
    }
    const pad = (part) => String(part).padStart(2, '0');
    return `${parsed.getFullYear()}-${pad(parsed.getMonth() + 1)}-${pad(parsed.getDate())}T${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
  }

  fromDatetimeLocalValue(value) {
    if (!value) {
      return '';
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString();
  }

  humanizeLabel(label) {
    if (!label) {
      return '';
    }
    return label
      .split(' ')
      .map((word) => {
        const isAcronym = word === word.toUpperCase() && /[A-Z]/.test(word);
        return isAcronym ? word : word.toLowerCase();
      })
      .join(' ');
  }
}