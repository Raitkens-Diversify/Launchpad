/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Field-set-driven record detail section for Experience Cloud. Reuses arcRecordDetailSection
 * styling and the envelopeFormSchema display pipeline.
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import ToastContainer from 'lightning/toastContainer';
import LightningToast from 'lightning/toast';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import { resolveRecordIdFromPageReference, isValidSalesforceRecordId } from 'c/recordNavigationUtils';
import {
  inferObjectApiNameFromPath,
  resolveCurrentPath
} from 'c/arcNavTrailState';
import loadFieldSetDetail from '@salesforce/apex/ArcRecordDetailByFieldSetController.load';
import saveFieldSetDetail from '@salesforce/apex/ArcRecordDetailByFieldSetController.save';
import { draftValuesEqual, shapeVisibleFields } from 'c/envelopeFormSchema';

const SECTION_KEY = 'field-set-section';

export default class ArcRecordDetailByFieldSet extends LightningElement {
  _recordId;
  _contextRecordId;
  _pageRef;
  _objectApiName = '';
  _fieldSetApiName = '';

  @api
  get recordId() {
    return this._recordId || this._contextRecordId;
  }
  set recordId(value) {
    const nextRecordId = isValidSalesforceRecordId(value) ? value : null;
    if (nextRecordId === this._recordId) {
      return;
    }
    this._recordId = nextRecordId;
    this.scheduleLoad();
  }

  @api
  get objectApiName() {
    return this._objectApiName;
  }
  set objectApiName(value) {
    const nextObjectApiName = value || '';
    if (nextObjectApiName === this._objectApiName) {
      return;
    }
    this._objectApiName = nextObjectApiName;
    this.scheduleLoad();
  }

  @api
  get fieldSetApiName() {
    return this._fieldSetApiName;
  }
  set fieldSetApiName(value) {
    const nextFieldSetApiName = value || '';
    if (nextFieldSetApiName === this._fieldSetApiName) {
      return;
    }
    this._fieldSetApiName = nextFieldSetApiName;
    this.scheduleLoad();
  }

  @api sectionTitle = '';
  @api enableEditing = false;

  fields = [];
  draft = {};
  savedDraft = {};
  isSubmitted = false;
  isLoading = true;
  savingSectionKey = null;
  editingSectionKeys = [];
  errorMessage = '';
  stylesLoaded = false;

  _sectionMemo = { inputs: null, value: null };
  _loadScheduled = false;
  boundBeforeUnloadHandler = this.handleBeforeUnload.bind(this);

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;
    this.syncRecordIdFromContext();
  }

  connectedCallback() {
    try {
      ToastContainer.instance().toastPosition = 'top-center';
    } catch (error) {
      // Non-fatal: toasts still attempt to render without a configured container.
    }

    if (!this.stylesLoaded) {
      loadStyle(this, diversifyStyles).catch(() => {
        // Non-fatal: fall back to SLDS defaults.
      });
      this.stylesLoaded = true;
    }
    window.addEventListener('beforeunload', this.boundBeforeUnloadHandler);
    this.syncRecordIdFromContext();
    this.scheduleLoad();
  }

  disconnectedCallback() {
    window.removeEventListener('beforeunload', this.boundBeforeUnloadHandler);
  }

  syncRecordIdFromContext() {
    if (this._recordId) {
      return;
    }

    const objectApiName =
      inferObjectApiNameFromPath(resolveCurrentPath(this._pageRef)) || null;
    const resolved = resolveRecordIdFromPageReference(this._pageRef, objectApiName);

    if (resolved === this._contextRecordId) {
      return;
    }

    this._contextRecordId = resolved;
    this.scheduleLoad();
  }

  scheduleLoad() {
    if (this._loadScheduled) {
      return;
    }
    this._loadScheduled = true;
    Promise.resolve().then(() => {
      this._loadScheduled = false;
      this.loadData();
    });
  }

  get loadInputsKey() {
    return [this.recordId, this.objectApiName, this.fieldSetApiName].join('|');
  }

  get hasFields() {
    return (this.sectionCard?.fields || []).length > 0;
  }

  get hasUnsavedChanges() {
    return this.hasDraftChanges();
  }

  get sectionIsEditing() {
    return this.editingSectionKeys.includes(SECTION_KEY);
  }

  get sectionIsSaving() {
    return this.savingSectionKey === SECTION_KEY;
  }

  get sectionHasChanges() {
    return this.sectionHasDraftChanges(this.sectionCard?.fields || []);
  }

  get sectionCard() {
    const memo = this._sectionMemo;
    const inputs = [
      this.fields,
      this.draft,
      this.sectionTitle,
      this.editingSectionKeys,
      this.savingSectionKey
    ];
    if (memo.value && memo.inputs.every((input, index) => input === inputs[index])) {
      return memo.value;
    }

    const shapedFields = shapeVisibleFields(this.fields, this.draft, {});
    const title = (this.sectionTitle || '').trim();

    memo.inputs = inputs;
    memo.value = {
      key: SECTION_KEY,
      label: title,
      hideHeader: !title,
      fields: shapedFields,
      isEditing: this.editingSectionKeys.includes(SECTION_KEY),
      isSaving: this.savingSectionKey === SECTION_KEY,
      hasChanges: this.sectionHasDraftChanges(shapedFields)
    };
    return memo.value;
  }

  hasDraftChanges() {
    const keys = new Set([
      ...Object.keys(this.draft || {}),
      ...Object.keys(this.savedDraft || {})
    ]);

    for (const key of keys) {
      if (!draftValuesEqual(this.draft[key], this.savedDraft[key])) {
        return true;
      }
    }

    return false;
  }

  sectionHasDraftChanges(fields) {
    return (fields || []).some((field) => {
      const apiName = field.fieldPath || field.apiName;
      if (!apiName) {
        return false;
      }
      return !draftValuesEqual(this.draft[apiName], this.savedDraft[apiName]);
    });
  }

  async loadData() {
    const key = this.loadInputsKey;
    this._lastLoadKey = key;

    if (!this.recordId) {
      this.isLoading = false;
      this.errorMessage = 'Record Id could not be resolved from the page context.';
      return;
    }

    if (!this.objectApiName || !this.fieldSetApiName) {
      this.isLoading = false;
      this.errorMessage = 'Object API Name and Field Set API Name are required.';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const context = await loadFieldSetDetail({
        recordId: this.recordId,
        objectApiName: this.objectApiName,
        fieldSetApiName: this.fieldSetApiName
      });

      if (this.loadInputsKey !== key) {
        return;
      }

      this.fields = context?.fields || [];
      const values = this.normalizeValues(this.fields, context?.values || {});
      this.draft = { ...values };
      this.savedDraft = { ...values };
      this.editingSectionKeys = [];
      this.savingSectionKey = null;
    } catch (error) {
      if (this.loadInputsKey === key) {
        this.errorMessage =
          error?.body?.message || error?.message || 'Unable to load record details.';
      }
    } finally {
      if (this.loadInputsKey === key) {
        this.isLoading = false;
      }
    }
  }

  handleFieldChange(event) {
    if (!this.enableEditing) {
      return;
    }

    const { sectionKey, field, value } = event.detail || {};
    if (!field || !this.editingSectionKeys.includes(sectionKey)) {
      return;
    }

    if (draftValuesEqual(this.draft[field], value)) {
      return;
    }

    this.draft = { ...this.draft, [field]: value };
  }

  handleSectionEdit(event) {
    if (!this.enableEditing || this.isSubmitted) {
      return;
    }

    const { sectionKey } = event.detail || {};
    if (!sectionKey || this.editingSectionKeys.includes(sectionKey)) {
      return;
    }

    this.editingSectionKeys = [...this.editingSectionKeys, sectionKey];
  }

  handleSectionCancel(event) {
    const { sectionKey } = event.detail || {};
    if (!sectionKey || !this.editingSectionKeys.includes(sectionKey)) {
      return;
    }

    this.revertSectionDraft(sectionKey);
    this.editingSectionKeys = this.editingSectionKeys.filter((key) => key !== sectionKey);
  }

  async handleSectionSave(event) {
    if (!this.enableEditing) {
      return;
    }

    const { sectionKey } = event.detail || {};
    if (!sectionKey || !this.editingSectionKeys.includes(sectionKey)) {
      return;
    }

    const sectionElement = this.getSectionElement(sectionKey);
    sectionElement?.flushPendingEdits();

    if (sectionElement && sectionElement.reportValidity() === false) {
      this.showToast('Validation error', 'Fix the highlighted fields before saving.', 'error');
      return;
    }

    const payload = this.buildSavePayload(sectionKey);
    if (!Object.keys(payload).length) {
      this.editingSectionKeys = this.editingSectionKeys.filter((key) => key !== sectionKey);
      return;
    }

    this.savingSectionKey = sectionKey;
    try {
      await saveFieldSetDetail({
        recordId: this.recordId,
        objectApiName: this.objectApiName,
        fieldSetApiName: this.fieldSetApiName,
        fields: payload
      });

      const section = this.sectionCard;
      const nextSavedDraft = { ...this.savedDraft };
      (section?.fields || []).forEach((field) => {
        const apiName = field.fieldPath || field.apiName;
        if (apiName) {
          nextSavedDraft[apiName] = this.draft[apiName];
        }
      });
      this.savedDraft = nextSavedDraft;
      this.editingSectionKeys = this.editingSectionKeys.filter((key) => key !== sectionKey);
      this.showToast(
        'Saved',
        `${section?.label || this.sectionTitle || 'Section'} updated successfully.`,
        'success'
      );
    } catch (error) {
      this.showToast('Unable to save', this.resolveSaveErrorMessage(error), 'error');
    } finally {
      this.savingSectionKey = null;
    }
  }

  handleBeforeUnload(event) {
    if (!this.hasUnsavedChanges) {
      return;
    }

    event.preventDefault();
    event.returnValue = '';
  }

  revertSectionDraft(sectionKey) {
    const section = this.sectionCard;
    const nextDraft = { ...this.draft };
    (section?.fields || []).forEach((field) => {
      const apiName = field.fieldPath || field.apiName;
      if (apiName) {
        nextDraft[apiName] = this.savedDraft[apiName];
      }
    });
    this.draft = nextDraft;
    this.getSectionElement(sectionKey)?.resetAllFields();
  }

  getSectionElement(sectionKey) {
    return this.template.querySelector(
      `c-arc-record-detail-section[data-section-key="${sectionKey}"]`
    );
  }

  buildSavePayload(sectionKey) {
    if (sectionKey !== SECTION_KEY) {
      return {};
    }

    const allowed = new Set(
      (this.fields || [])
        .filter((field) => field.fieldPath && !field.disabled && !field.fieldPath.includes('.'))
        .map((field) => field.fieldPath)
    );

    const payload = {};
    allowed.forEach((apiName) => {
      if (!Object.prototype.hasOwnProperty.call(this.draft, apiName)) {
        return;
      }
      if (draftValuesEqual(this.draft[apiName], this.savedDraft[apiName])) {
        return;
      }
      payload[apiName] = this.draft[apiName];
    });
    return payload;
  }

  resolveSaveErrorMessage(error) {
    const body = error?.body;
    if (Array.isArray(body)) {
      return (
        body
          .map((entry) => entry?.message)
          .filter(Boolean)
          .join(' ') || 'Something went wrong while saving your changes. Please try again.'
      );
    }

    const message = body?.message || error?.message;
    if (message) {
      return message;
    }

    return 'Something went wrong while saving your changes. Please try again.';
  }

  normalizeValues(fields, values) {
    const normalized = { ...(values || {}) };

    (fields || []).forEach((field) => {
      const apiName = field?.fieldPath;
      if (!apiName) {
        return;
      }

      const value = normalized[apiName];
      if (field.type === 'MULTIPICKLIST' && typeof value === 'string' && value) {
        normalized[apiName] = value.split(';');
      }
    });

    return normalized;
  }

  showToast(title, message, variant) {
    LightningToast.show(
      {
        label: title,
        message,
        variant,
        mode: 'dismissable'
      },
      this
    );
  }
}