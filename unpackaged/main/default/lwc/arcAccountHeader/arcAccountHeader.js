/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Account record header for Experience Cloud. Resolves member type and client
 * badges using the same rules as the relationship map (fscRelMapUtils).
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';
import { resolveRecordIdFromPageReference } from 'c/recordNavigationUtils';
import { buildAccountHeaderViewModel } from 'c/fscRelMapUtils';
import loadAccountHeader from '@salesforce/apex/ArcAccountHeaderController.load';

export default class ArcAccountHeader extends LightningElement {
  _recordId;
  _contextRecordId;
  _pageRef;
  _lastLoadedRecordId;

  isLoading = true;
  errorMessage = '';
  header = null;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this._recordId = value;
    this._contextRecordId = value;
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

  get effectiveRecordId() {
    return this._contextRecordId || this._recordId;
  }

  get hasHeader() {
    return Boolean(this.header?.name);
  }

  connectedCallback() {
    loadStyle(this, diversifyStyles).catch(() => {});
    this.scheduleLoad();
  }

  scheduleLoad() {
    const recordId = this.effectiveRecordId;

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
    this.loadHeader(recordId);
  }

  async loadHeader(recordId = this.effectiveRecordId) {

    if (!recordId) {
      this.isLoading = false;
      this.errorMessage = 'Record Id could not be resolved from the page context.';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const context = await loadAccountHeader({ accountId: recordId });

      if (recordId !== this.effectiveRecordId) {
        return;
      }

      this.header = buildAccountHeaderViewModel({
        name: context?.name,
        recordTypeDeveloperName: context?.recordTypeDeveloperName,
        recordTypeLabel: context?.recordTypeLabel,
        accountType: context?.accountType,
        roles: context?.roles || []
      });
    } catch (error) {
      if (recordId === this.effectiveRecordId) {
        this.errorMessage =
          error?.body?.message || error?.message || 'Unable to load account header.';
        this.header = null;
      }
    } finally {
      if (recordId === this.effectiveRecordId) {
        this.isLoading = false;
      }
    }
  }
}