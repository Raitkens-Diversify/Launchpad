/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Metadata-driven record detail form for Experience Cloud. Reuses the envelope
 * schema pipeline (Envelope_Field__mdt → shapeVisibleFields → envelopeFieldControl).
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import ToastContainer from 'lightning/toastContainer';
import LightningToast from 'lightning/toast';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import {
  resolveRecordIdFromPageReference,
  isExperienceBuilderDesignMode,
  isValidSalesforceRecordId
} from 'c/recordNavigationCommunityUtils';
import loadRecordDetail from '@salesforce/apex/ArcRecordDetailController.load';
import saveRecordDetail from '@salesforce/apex/ArcRecordDetailController.save';
import {
  shapeVisibleFields,
  clearHiddenAnswers,
  hasPriorAnswer,
  draftValuesEqual,
  sectionStatus
} from 'c/envelopeFormSchema';

// Inline editing is disabled for this release.
const EDIT_ENABLED = false;

export default class ArcRecordDetail extends LightningElement {
  _recordId;
  _contextRecordId;
  _pageRef;
  _resolvedObjectApiName;
  _resolvedSchemaType;
  _isPersonAccount = false;
  _hiddenBecauseNoRelatedRecord = false;
  _displayRecordId = null;
  _useRelatedRecord = false;
  _relatedRecordLookupField = '';

  // Deprecated Experience Builder property — kept for published community compatibility only.
  // Schema type is always resolved server-side from the record; this value is ignored.
  @api schemaType;

  @api
  get useRelatedRecord() {
    return this._useRelatedRecord;
  }
  set useRelatedRecord(value) {
    const nextValue = value === true;
    if (nextValue === this._useRelatedRecord) {
      return;
    }
    this._useRelatedRecord = nextValue;
    this.scheduleLoad();
  }

  @api
  get relatedRecordLookupField() {
    return this._relatedRecordLookupField;
  }
  set relatedRecordLookupField(value) {
    const nextValue = (value || '').trim();
    if (nextValue === this._relatedRecordLookupField) {
      return;
    }
    this._relatedRecordLookupField = nextValue;
    this.scheduleLoad();
  }

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

  @api title = '';
  /**
   * How read-mode fields are laid out: "rows" is the label-left/value-right
   * pair the Figma contact page specifies, "grid" is a responsive multi-column
   * grid with the label above its value, which scans far better on a page of
   * fifteen short fields. Edit mode is unaffected either way.
   */
  @api fieldLayout = 'rows';
  _sectionFilter = '';

  @api
  get sectionFilter() {
    return this._sectionFilter;
  }
  set sectionFilter(value) {
    this._sectionFilter = value || '';
  }

  sections = [];
  sectionLayout = null;
  draft = {};
  savedDraft = {};
  userContext = {};
  isSubmitted = false;
  isLoading = true;
  savingSectionKey = null;
  editingSectionKeys = [];
  errorMessage = '';
  stylesLoaded = false;

  _sectionsMemo = { inputs: null, value: null };
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

    const resolved = resolveRecordIdFromPageReference(this._pageRef, null);

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
    return [
      this.recordId || '',
      this._useRelatedRecord ? '1' : '0',
      this._relatedRecordLookupField || ''
    ].join('|');
  }

  get isDesignMode() {
    return isExperienceBuilderDesignMode(this._pageRef);
  }

  get shouldHideOnRuntime() {
    if (this.isLoading) {
      return !this.isDesignMode;
    }

    if (this.useRelatedRecord) {
      if (this._hiddenBecauseNoRelatedRecord || this.errorMessage) {
        return true;
      }
      return !this.hasFields;
    }

    return !this.hasFields && !this.errorMessage;
  }

  get shouldRender() {
    if (!this.shouldHideOnRuntime) {
      return true;
    }
    return this.isDesignMode;
  }

  get showDesignerEmptyState() {
    if (!this.isDesignMode) {
      return false;
    }

    if (!this.recordId) {
      return true;
    }

    if (this.isLoading || this.errorMessage) {
      return false;
    }

    if (!this.hasFields) {
      return true;
    }

    return this.useRelatedRecord && this._hiddenBecauseNoRelatedRecord;
  }

  get showEmptyState() {
    return this.showDesignerEmptyState;
  }

  get emptyStateMessage() {
    if (!this.recordId) {
      return 'Place this component on a record page, or open preview with a sample record selected. Record detail fields load from the page record context.';
    }

    if (this._hiddenBecauseNoRelatedRecord) {
      const lookupField = this.relatedRecordLookupField || 'the configured lookup field';
      return `No related record is linked via ${lookupField}. This component is hidden on preview and the live site.`;
    }

    return 'No fields configured for this record.';
  }

  get activeRecordId() {
    return this._displayRecordId || this.recordId;
  }

  get activeObjectApiName() {
    return this._resolvedObjectApiName || '';
  }

  get activeSchemaType() {
    return this._resolvedSchemaType || '';
  }

  get hasTitle() {
    return Boolean(this.title?.trim());
  }

  get hasFields() {
    return this.sectionCards.length > 0;
  }

  get hasUnsavedChanges() {
    return this.hasDraftChanges();
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

  get sectionCards() {
    const memo = this._sectionsMemo;
    const inputs = [
      this.sections,
      this.sectionLayout,
      this.draft,
      this.userContext,
      this.sectionFilter,
      this.editingSectionKeys,
      this.savingSectionKey,
      this.isSubmitted
    ];
    if (memo.value && memo.inputs.every((input, index) => input === inputs[index])) {
      return memo.value;
    }
    memo.inputs = inputs;
    memo.value = this.buildSectionCards();
    return memo.value;
  }

  get _allFields() {
    return (this.sections || []).flatMap((section) => section.fields || []);
  }

  async loadData() {
    const key = this.loadInputsKey;
    this._lastLoadKey = key;

    if (!this.recordId) {
      this.isLoading = false;
      this.errorMessage = this.isDesignMode
        ? ''
        : 'Record Id could not be resolved from the page context.';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const context = await loadRecordDetail({
        recordId: this.recordId,
        objectName: null,
        useRelatedRecord: this.useRelatedRecord === true,
        relatedRecordLookupField: this.relatedRecordLookupField || null
      });

      if (this.loadInputsKey !== key) {
        return;
      }

      this._hiddenBecauseNoRelatedRecord = context?.hidden === true;
      if (this._hiddenBecauseNoRelatedRecord) {
        this._displayRecordId = null;
        this.sections = [];
        this.sectionLayout = null;
        this.draft = {};
        this.savedDraft = {};
        this.errorMessage = '';
        return;
      }

      this._displayRecordId = context?.displayRecordId || this.recordId;
      this._resolvedObjectApiName = context?.objectApiName || '';
      this._resolvedSchemaType = context?.schemaType || '';
      this._isPersonAccount = context?.isPersonAccount === true;
      this.sections = context?.sections || [];
      this.sectionLayout = context?.sectionLayout || null;
      const values = context?.values || {};
      this.draft = { ...values };
      this.savedDraft = { ...values };
      this.userContext = {
        Relationship_to_Firm__c: context?.userContext?.relationshipToFirm ?? null
      };
      this.isSubmitted = context?.isSubmitted === true;
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

  buildSectionCards() {
    const draft = this.draft;
    const filterSet = this.parseSectionFilter();

    let shapedSections = (this.sections || [])
      .map((section, index) => {
        const fields = shapeVisibleFields(section.fields, draft, this.userContext);
        return {
          key: `sec-${index}`,
          label: section.name,
          status: sectionStatus(fields),
          fields,
          hideHeader: false,
          isEditing: false,
          isSaving: false
        };
      })
      .filter((section) => section.fields.length > 0);

    if (filterSet.size > 0) {
      shapedSections = shapedSections.filter((section) => filterSet.has(section.label));
    }

    let ordered = shapedSections;

    if (this.sectionLayout && this.sectionLayout.length) {
      const sectionByName = new Map(
        shapedSections.map((section) => [section.label, section])
      );
      const used = new Set();
      ordered = [];

      this.sectionLayout.forEach((parent) => {
        (parent.childSections || []).forEach((name) => {
          const section = sectionByName.get(name);
          if (section && !used.has(name)) {
            ordered.push(section);
            used.add(name);
          }
        });
      });

      shapedSections
        .filter((section) => !used.has(section.label))
        .forEach((section) => ordered.push(section));
    }

    return ordered.map((section) => ({
      ...section,
      isEditing: this.editingSectionKeys.includes(section.key),
      isSaving: section.key === this.savingSectionKey,
      hasChanges: this.sectionHasChanges(section.fields)
    }));
  }

  sectionHasChanges(fields) {
    return (fields || []).some((field) => {
      const apiName = this.getFieldApiName(field);
      if (!apiName) {
        return false;
      }
      return !draftValuesEqual(this.draft[apiName], this.savedDraft[apiName]);
    });
  }

  parseSectionFilter() {
    if (!this.sectionFilter || !this.sectionFilter.trim()) {
      return new Set();
    }
    return new Set(
      this.sectionFilter
        .split(',')
        .map((name) => name.trim())
        .filter(Boolean)
    );
  }

  handleFieldChange(event) {
    const { sectionKey, field, value } = event.detail || {};
    if (!field || !this.editingSectionKeys.includes(sectionKey)) {
      return;
    }

    if (draftValuesEqual(this.draft[field], value)) {
      return;
    }

    if (this.isKeyPoint(field) && hasPriorAnswer(this.draft, field)) {
      this.draft = clearHiddenAnswers(
        this._allFields,
        { ...this.draft, [field]: value },
        this.userContext
      );
      return;
    }

    this.draft = { ...this.draft, [field]: value };
  }

  handleSectionEdit(event) {
    if (!EDIT_ENABLED) {
      return;
    }

    if (this.isSubmitted) {
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
    if (!EDIT_ENABLED) {
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

    const payload = this.buildSavePayloadForSection(sectionKey);
    if (!Object.keys(payload).length) {
      this.editingSectionKeys = this.editingSectionKeys.filter((key) => key !== sectionKey);
      return;
    }

    this.savingSectionKey = sectionKey;
    try {
      await saveRecordDetail({
        recordId: this.recordId,
        objectName: null,
        useRelatedRecord: this.useRelatedRecord === true,
        relatedRecordLookupField: this.relatedRecordLookupField || null,
        fields: payload
      });

      const section = this.findSectionCard(sectionKey);
      const nextSavedDraft = { ...this.savedDraft };
      (section?.fields || []).forEach((field) => {
        const apiName = this.getFieldApiName(field);
        if (apiName) {
          nextSavedDraft[apiName] = this.draft[apiName];
        }
      });
      this.savedDraft = nextSavedDraft;
      this.editingSectionKeys = this.editingSectionKeys.filter((key) => key !== sectionKey);
      this.showToast('Saved', `${section?.label || 'Section'} updated successfully.`, 'success');
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
    const section = this.findSectionCard(sectionKey);
    const nextDraft = { ...this.draft };
    (section?.fields || []).forEach((field) => {
      const apiName = this.getFieldApiName(field);
      if (apiName) {
        nextDraft[apiName] = this.savedDraft[apiName];
      }
    });
    this.draft = nextDraft;
    this.getSectionElement(sectionKey)?.resetAllFields();
  }

  findSectionCard(sectionKey) {
    return this.sectionCards.find((section) => section.key === sectionKey);
  }

  getSectionElement(sectionKey) {
    return this.template.querySelector(
      `c-arc-record-detail-section[data-section-key="${sectionKey}"]`
    );
  }

  buildSavePayloadForSection(sectionKey) {
    const section = this.findSectionCard(sectionKey);
    const baseline = {};
    (section?.fields || []).forEach((field) => {
      const apiName = this.getFieldApiName(field);
      if (apiName) {
        baseline[apiName] = this.savedDraft[apiName];
      }
    });

    const allowed = new Set(
      (section?.fields || [])
        .filter((field) => !field.addRecord && this.getFieldApiName(field))
        .map((field) => this.getFieldApiName(field))
        .filter((apiName) => !(this._isPersonAccount && apiName === 'Name'))
    );

    const payload = {};
    allowed.forEach((apiName) => {
      if (!Object.prototype.hasOwnProperty.call(this.draft, apiName)) {
        return;
      }
      if (draftValuesEqual(this.draft[apiName], baseline[apiName])) {
        return;
      }
      payload[apiName] = this.draft[apiName];
    });
    return payload;
  }

  getFieldApiName(field) {
    return field?.fieldPath || field?.apiName || '';
  }

  resolveSaveErrorMessage(error) {
    const body = error?.body;
    if (Array.isArray(body)) {
      return body.map((entry) => entry?.message).filter(Boolean).join(' ') ||
        'Something went wrong while saving your changes. Please try again.';
    }

    const pageErrors = body?.pageErrors;
    if (Array.isArray(pageErrors) && pageErrors.length) {
      return pageErrors.map((entry) => entry?.message).filter(Boolean).join(' ');
    }

    const fieldErrors = body?.fieldErrors;
    if (fieldErrors && typeof fieldErrors === 'object') {
      const messages = Object.values(fieldErrors)
        .flat()
        .map((entry) => entry?.message)
        .filter(Boolean);
      if (messages.length) {
        return messages.join(' ');
      }
    }

    const outputErrors = body?.output?.errors;
    if (Array.isArray(outputErrors) && outputErrors.length) {
      return outputErrors.map((entry) => entry?.message).filter(Boolean).join(' ');
    }

    const message = body?.message || error?.message;
    if (message) {
      return this.humanizeSaveErrorMessage(message);
    }

    return 'Something went wrong while saving your changes. Please try again.';
  }

  humanizeSaveErrorMessage(message) {
    const text = String(message).trim();
    if (!text) {
      return 'Something went wrong while saving your changes. Please try again.';
    }
    if (text.includes('bad field names') || text.includes('Person Account field')) {
      return 'Some fields on this page cannot be updated for this record type. Save the fields that apply to this account type, or verify the schema type matches the record.';
    }
    if (text.includes('submitted')) {
      return 'This record has been submitted and can no longer be edited.';
    }
    if (text.includes('permission') || text.includes('Permission')) {
      return 'You do not have permission to update this record.';
    }
    if (text.includes('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {
      return text.replace(/^.*FIELD_CUSTOM_VALIDATION_EXCEPTION[,\\s]*/i, '').trim() ||
        'A validation rule blocked this save. Review the fields and try again.';
    }
    return text;
  }

  isKeyPoint(apiName) {
    return this._allFields.some(
      (field) =>
        (field.fieldPath === apiName || field.apiName === apiName) && field.keyDecision
    );
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