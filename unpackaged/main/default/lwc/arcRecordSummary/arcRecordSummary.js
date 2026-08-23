/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Read-only Record summary card for Experience Cloud account pages.
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import { resolveRecordIdFromPageReference } from 'c/recordNavigationUtils';
import {
  buildAccountHeaderViewModel,
  resolveAccountTypeDisplayLabel
} from 'c/fscRelMapUtils';
import { CLIENT_ROLE_VALUE } from 'c/fscRelUtils';
import loadRecordSummary from '@salesforce/apex/ArcRecordSummaryController.load';

const DATE_DISPLAY = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric'
});

export default class ArcRecordSummary extends LightningElement {
  _recordId;
  _contextRecordId;
  _pageRef;
  _lastLoadedRecordId;

  summary = null;
  isLoading = true;
  errorMessage = '';

  @api
  get recordId() {
    return this._recordId || this._contextRecordId;
  }

  set recordId(value) {
    const nextRecordId = value || null;
    if (nextRecordId === this._recordId) {
      return;
    }

    this._recordId = nextRecordId;
    this.scheduleLoad();
  }

  @wire(CurrentPageReference)
  handlePageReference(pageRef) {
    this._pageRef = pageRef;
    const resolvedRecordId = resolveRecordIdFromPageReference(pageRef, 'Account');

    if (resolvedRecordId) {
      this._contextRecordId = resolvedRecordId;
      this.scheduleLoad();
    }
  }

  connectedCallback() {
    loadStyle(this, diversifyStyles).catch(() => {});
    this.syncRecordIdFromContext();
    this.scheduleLoad();
  }

  syncRecordIdFromContext() {
    if (this._recordId) {
      return;
    }

    const resolved = resolveRecordIdFromPageReference(this._pageRef, 'Account');
    if (resolved === this._contextRecordId) {
      return;
    }

    this._contextRecordId = resolved;
    this.scheduleLoad();
  }

  scheduleLoad() {
    const recordId = this.recordId;

    if (!recordId) {
      if (this._pageRef) {
        this.isLoading = false;
        this.errorMessage = 'Record Id could not be resolved from the page context.';
      }
      return;
    }

    if (recordId === this._lastLoadedRecordId) {
      return;
    }

    this._lastLoadedRecordId = recordId;
    this.loadSummary(recordId);
  }

  async loadSummary(recordId = this.recordId) {
    if (!recordId) {
      this.isLoading = false;
      this.errorMessage = 'Record Id could not be resolved from the page context.';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const context = await loadRecordSummary({ accountId: recordId });

      if (recordId !== this.recordId) {
        return;
      }

      this.summary = context;
    } catch (error) {
      if (recordId === this.recordId) {
        this.errorMessage =
          error?.body?.message || error?.message || 'Unable to load record summary.';
        this.summary = null;
      }
    } finally {
      if (recordId === this.recordId) {
        this.isLoading = false;
      }
    }
  }

  get hasSummary() {
    return Boolean(this.summary);
  }

  get section() {
    return {
      key: 'record-summary',
      label: 'Record',
      hideHeader: false,
      fields: this.summaryFields
    };
  }

  get summaryFields() {
    if (!this.summary) {
      return [];
    }

    const header = buildAccountHeaderViewModel({
      recordTypeDeveloperName: this.summary.recordTypeDeveloperName,
      recordTypeLabel: this.summary.recordTypeLabel,
      accountType: this.summary.accountType,
      roles: this.summary.roles || []
    });

    const classificationLabel =
      header.secondaryBadges.find((badge) => badge.label === CLIENT_ROLE_VALUE)?.label ||
      this.resolveClassificationLabel(this.summary.classification);

    return [
      this.buildField('contact-type', 'Contact Type', this.contactTypeLabel),
      this.buildField('classification', 'Classification', classificationLabel),
      this.buildField('household', 'Household', this.summary.householdName),
      this.buildField('primary-advisor', 'Primary Advisor', this.summary.primaryAdvisorName),
      this.buildField('date-created', 'Date Created', this.createdDateLabel),
      this.buildField('status', 'Status', this.statusLabel)
    ];
  }

  get contactTypeLabel() {
    if (!this.summary) {
      return '';
    }

    return resolveAccountTypeDisplayLabel(
      this.summary.recordTypeDeveloperName,
      this.summary.recordTypeLabel
    );
  }

  get createdDateLabel() {
    if (!this.summary?.createdDate) {
      return '';
    }

    const parsed = new Date(this.summary.createdDate);
    if (Number.isNaN(parsed.getTime())) {
      return '';
    }

    return DATE_DISPLAY.format(parsed);
  }

  get statusLabel() {
    return this.resolveStatusLabel(this.summary?.status);
  }

  buildField(key, label, value) {
    return {
      key,
      label,
      value: value || null,
      type: 'STRING'
    };
  }

  resolveClassificationLabel(rawValue) {
    const value = String(rawValue || '').trim();
    if (!value) {
      return '';
    }

    return value.split(';').map((entry) => entry.trim()).filter(Boolean)[0] || '';
  }

  resolveStatusLabel(accountType) {
    const value = String(accountType || '').trim();
    if (!value) {
      return '';
    }

    const normalized = value.toLowerCase();
    if (normalized.includes('active')) {
      return 'Active';
    }

    if (normalized.includes('former') || normalized.includes('inactive')) {
      return 'Inactive';
    }

    return value;
  }
}