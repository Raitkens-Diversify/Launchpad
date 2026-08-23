/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Renders one metadata section as responsive label/control rows for arcRecordDetail.
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { formatFieldDisplayValue } from 'c/envelopeFormSchema';
import {
  buildExperienceRecordPath,
  buildRecordNavigationReference,
  shouldAllowNativeRecordNavigation
} from 'c/recordNavigationCommunityUtils';

const SALESFORCE_ID_PATTERN = /^[a-zA-Z0-9]{15,18}$/;

const isSalesforceId = (value) =>
  typeof value === 'string' && SALESFORCE_ID_PATTERN.test(value);

// SVG path from staticresources/Diversify_Icons/pencil.svg
const PENCIL_ICON_PATH =
  'M18.3103 4.62915L14.1216 0.439461C13.9823 0.300137 13.8169 0.189617 13.6349 0.114213C13.4529 0.03881 13.2578 0 13.0608 0C12.8638 0 12.6687 0.03881 12.4867 0.114213C12.3047 0.189617 12.1393 0.300137 12 0.439461L0.439695 12.0007C0.299801 12.1395 0.188889 12.3047 0.113407 12.4867C0.0379245 12.6688 -0.000621974 12.864 7.58902e-06 13.061V17.2507C7.58902e-06 17.6485 0.158043 18.0301 0.439347 18.3114C0.720652 18.5927 1.10218 18.7507 1.50001 18.7507H5.6897C5.88675 18.7513 6.08197 18.7128 6.26399 18.6373C6.44602 18.5618 6.61122 18.4509 6.75001 18.311L18.3103 6.75071C18.4496 6.61142 18.5602 6.44604 18.6356 6.26403C18.711 6.08202 18.7498 5.88694 18.7498 5.68993C18.7498 5.49292 18.711 5.29784 18.6356 5.11582C18.5602 4.93381 18.4496 4.76844 18.3103 4.62915ZM5.6897 17.2507H1.50001V13.061L9.75001 4.81102L13.9397 9.00071L5.6897 17.2507ZM15 7.93946L10.8103 3.75071L13.0603 1.50071L17.25 5.68946L15 7.93946Z';

// SVG path from staticresources/arcicon/lock.svg
const LOCK_ICON_PATH =
  'M9.625 3.9375H7.875V2.625C7.875 1.92881 7.59844 1.26113 7.10616 0.768845C6.61387 0.276562 5.94619 0 5.25 0C4.55381 0 3.88613 0.276562 3.39384 0.768845C2.90156 1.26113 2.625 1.92881 2.625 2.625V3.9375H0.875C0.642936 3.9375 0.420376 4.02969 0.256282 4.19378C0.0921872 4.35788 0 4.58044 0 4.8125V10.9375C0 11.1696 0.0921872 11.3921 0.256282 11.5562C0.420376 11.7203 0.642936 11.8125 0.875 11.8125H9.625C9.85706 11.8125 10.0796 11.7203 10.2437 11.5562C10.4078 11.3921 10.5 11.1696 10.5 10.9375V4.8125C10.5 4.58044 10.4078 4.35788 10.2437 4.19378C10.0796 4.02969 9.85706 3.9375 9.625 3.9375ZM5.25 8.53125C5.12021 8.53125 4.99333 8.49276 4.88541 8.42065C4.77749 8.34854 4.69337 8.24605 4.6437 8.12614C4.59403 8.00622 4.58104 7.87427 4.60636 7.74697C4.63168 7.61967 4.69418 7.50274 4.78596 7.41096C4.87774 7.31918 4.99467 7.25668 5.12197 7.23136C5.24927 7.20604 5.38122 7.21903 5.50114 7.2687C5.62105 7.31837 5.72354 7.40249 5.79565 7.51041C5.86776 7.61833 5.90625 7.74521 5.90625 7.875C5.90625 8.04905 5.83711 8.21597 5.71404 8.33904C5.59097 8.46211 5.42405 8.53125 5.25 8.53125ZM7 3.9375H3.5V2.625C3.5 2.16087 3.68437 1.71575 4.01256 1.38756C4.34075 1.05937 4.78587 0.875 5.25 0.875C5.71413 0.875 6.15925 1.05937 6.48744 1.38756C6.81563 1.71575 7 2.16087 7 2.625V3.9375Z';

export default class ArcRecordDetailSection extends NavigationMixin(LightningElement) {
  @api section;
  @api isEditing = false;
  @api isSaving = false;
  @api hasChanges = false;
  @api isSubmitted = false;
  @api summaryMode = false;
  @api infoTooltip = '';
  @api enableEditing = false;

  get pencilIconPath() {
    return PENCIL_ICON_PATH;
  }

  get lockIconPath() {
    return LOCK_ICON_PATH;
  }

  get label() {
    return this.section?.label || '';
  }

  get sectionKey() {
    return this.section?.key || '';
  }

  get showHeader() {
    if (this.enableEditing && !this.isSubmitted) {
      return true;
    }

    return !this.section?.hideHeader;
  }

  get isReadonly() {
    return !this.enableEditing || this.isSubmitted || !this.isEditing;
  }

  get showFieldLock() {
    if (this.summaryMode) {
      return false;
    }

    return !this.enableEditing || this.isSubmitted;
  }

  get showInfoIcon() {
    return !this.summaryMode && Boolean(this.infoTooltip);
  }

  get infoAriaLabel() {
    return this.infoTooltip || `About ${this.label}`;
  }

  get showEditButton() {
    if (this.summaryMode) {
      return false;
    }

    return this.enableEditing && !this.isSubmitted && !this.isEditing;
  }

  get showSectionActions() {
    if (this.summaryMode) {
      return false;
    }

    return this.enableEditing && !this.isSubmitted && this.isEditing;
  }

  get fields() {
    return this.section?.fields || [];
  }

  get fieldRows() {
    return this.fields.map((field) => {
      const recordLink = this.buildRecordLink(field);

      return {
        ...field,
        displayLabel: this.buildDisplayLabel(field),
        displayValue: this.buildDisplayValue(field),
        rowClass: 'field-row',
        isRecordLink: Boolean(recordLink),
        recordUrl: recordLink?.url || '',
        linkRecordId: recordLink?.recordId || '',
        linkObjectApiName: recordLink?.objectApiName || '',
        linkAriaLabel: recordLink
          ? `View ${this.buildDisplayValue(field)}`
          : ''
      };
    });
  }

  get isSaveDisabled() {
    return this.isSaving || !this.hasChanges;
  }

  get isCancelDisabled() {
    return this.isSaving;
  }

  get editAriaLabel() {
    return `Edit ${this.label}`;
  }

  buildDisplayLabel(field) {
    const label = field?.label || '';

    if (this.summaryMode) {
      return label;
    }

    const isBoolean = field?.type === 'BOOLEAN';
    return field?.required || isBoolean ? label : `${label} (optional)`;
  }

  buildDisplayValue(field) {
    const formatted = formatFieldDisplayValue(field);
    return formatted || '—';
  }

  buildRecordLink(field) {
    const recordId = field?.value;
    const objectApiName = field?.referenceTo;

    if (!isSalesforceId(String(recordId || '')) || !objectApiName) {
      return null;
    }

    const url = buildExperienceRecordPath(recordId, objectApiName);
    if (!url) {
      return null;
    }

    return {
      url,
      recordId: String(recordId),
      objectApiName
    };
  }

  handleRecordLinkClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();

    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;
    const pageReference = buildRecordNavigationReference(recordId, objectApiName);

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  handleEditClick() {
    this.dispatchEvent(
      new CustomEvent('edit', {
        detail: { sectionKey: this.sectionKey }
      })
    );
  }

  handleSaveClick() {
    this.dispatchEvent(
      new CustomEvent('save', {
        detail: { sectionKey: this.sectionKey }
      })
    );
  }

  handleCancelClick() {
    this.dispatchEvent(
      new CustomEvent('sectioncancel', {
        detail: { sectionKey: this.sectionKey },
        bubbles: true,
        composed: true
      })
    );
  }

  @api
  reportValidity() {
    let valid = true;
    this.template.querySelectorAll('c-arc-record-detail-field').forEach((control) => {
      if (typeof control.reportValidity === 'function' && control.reportValidity() === false) {
        valid = false;
      }
    });
    return valid;
  }

  @api
  checkValidity() {
    let valid = true;
    this.template.querySelectorAll('c-arc-record-detail-field').forEach((control) => {
      if (typeof control.checkValidity === 'function' && control.checkValidity() === false) {
        valid = false;
      }
    });
    return valid;
  }

  @api
  flushPendingEdits() {
    this.template.querySelectorAll('c-arc-record-detail-field').forEach((control) => {
      if (typeof control.flushPendingEdits === 'function') {
        control.flushPendingEdits();
      }
    });
  }

  @api
  resetField(apiName) {
    const control = this.template.querySelector(
      `c-arc-record-detail-field[data-field="${apiName}"]`
    );
    if (control && typeof control.resetValue === 'function') {
      control.resetValue();
    }
  }

  @api
  resetAllFields() {
    this.template.querySelectorAll('c-arc-record-detail-field').forEach((control) => {
      if (typeof control.resetValue === 'function') {
        control.resetValue();
      }
    });
  }

  handleFieldChange(event) {
    const { field, value } = event.detail || {};
    this.dispatchEvent(
      new CustomEvent('valuechange', {
        detail: { sectionKey: this.sectionKey, field, value }
      })
    );
  }
}