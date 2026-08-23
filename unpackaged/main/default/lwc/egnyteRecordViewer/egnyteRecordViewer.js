/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Embeds Egnyte directly for a Salesforce record via EgnyteController.
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { resolveRecordIdFromPageReference, isValidSalesforceRecordId } from 'c/recordNavigationUtils';
import getEgnyteFolderUrl from '@salesforce/apex/EgnyteController.getEgnyteFolderUrl';
import getOAuthStatus from '@salesforce/apex/EgnyteOAuthController.getOAuthStatus';

const DEFAULT_PAGE_HEIGHT = '600px';
const EXPERIENCE_DESIGN_HOST_PATTERN = /live-preview\.salesforce-experience\.com$/i;
const EMPTY_APEX_CREDENTIALS = Object.freeze({
  recordId: null,
  clientId: null,
  clientSecret: null,
  refreshToken: null,
  domain: null,
  accessToken: null
});

const isExperienceBuilderDesign = () => {
  if (typeof window === 'undefined') {
    return false;
  }

  const hostname = window.location?.hostname || '';
  const pathname = window.location?.pathname || '';
  const href = window.location?.href || '';

  return (
    EXPERIENCE_DESIGN_HOST_PATTERN.test(hostname) ||
    pathname.includes('/webruntime/design') ||
    href.includes('/webruntime/design')
  );
};

export default class EgnyteRecordViewer extends LightningElement {
  _recordId;
  _contextRecordId;
  _pageRef;
  egnyteUrl;
  errorMessage;
  oauthConnectUrl;
  showOAuthConnectLink = false;
  isLoading = false;
  _loadToken = 0;
  _loadScheduled = false;

  @api pageHeight = DEFAULT_PAGE_HEIGHT;

  @api useTestConfig = false;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    const nextRecordId = isValidSalesforceRecordId(value) ? value : null;
    if (nextRecordId === this._recordId) {
      return;
    }

    this._recordId = nextRecordId;

    if (!this.isDesignMode) {
      this.scheduleLoad();
    }
  }

  get activeRecordId() {
    return this._contextRecordId || this._recordId || null;
  }

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    this._pageRef = pageRef;

    if (this.isDesignMode) {
      return;
    }

    this.syncRecordIdFromContext();
  }

  connectedCallback() {
    if (this.isDesignMode) {
      return;
    }

    this.syncRecordIdFromContext();
    this.scheduleLoad();
  }

  get isDesignMode() {
    return isExperienceBuilderDesign();
  }

  get showDesignPlaceholder() {
    return this.isDesignMode;
  }

  get showEmptyPlaceholder() {
    return (
      !this.isDesignMode &&
      !this.activeRecordId &&
      !this.isLoading &&
      !this.hasIframe &&
      !this.errorMessage
    );
  }

  get containerStyle() {
    const height = (this.pageHeight || DEFAULT_PAGE_HEIGHT).trim() || DEFAULT_PAGE_HEIGHT;
    return `min-height: ${height};`;
  }

  get hasIframe() {
    return !!this.egnyteUrl && !this.isDesignMode;
  }

  get iframeStyle() {
    const height = (this.pageHeight || DEFAULT_PAGE_HEIGHT).trim() || DEFAULT_PAGE_HEIGHT;
    return `min-height: ${height}; height: ${height};`;
  }

  syncRecordIdFromContext() {
    const resolved = resolveRecordIdFromPageReference(this._pageRef, null);
    if (resolved === this._contextRecordId) {
      return;
    }

    this._contextRecordId = resolved;
    this.scheduleLoad();
  }

  scheduleLoad() {
    if (this.isDesignMode || this._loadScheduled) {
      return;
    }

    this._loadScheduled = true;
    Promise.resolve().then(() => {
      this._loadScheduled = false;
      this.loadEgnyteUrl();
    });
  }

  buildApexRequest(activeRecordId) {
    return {
      ...EMPTY_APEX_CREDENTIALS,
      recordId: activeRecordId
    };
  }

  async loadEgnyteUrl() {
    if (this.isDesignMode) {
      return;
    }

    const loadToken = ++this._loadToken;
    const activeRecordId = this.activeRecordId;

    this.isLoading = true;
    this.errorMessage = undefined;
    this.egnyteUrl = undefined;
    this.oauthConnectUrl = undefined;
    this.showOAuthConnectLink = false;

    if (!activeRecordId) {
      if (loadToken === this._loadToken) {
        this.isLoading = false;
      }
      return;
    }

    try {
      const folderUrl = await getEgnyteFolderUrl(this.buildApexRequest(activeRecordId));

      if (loadToken !== this._loadToken) {
        return;
      }

      if (!folderUrl) {
        this.errorMessage = 'Unable to resolve the Egnyte folder URL for this record.';
        return;
      }

      this.egnyteUrl = folderUrl;
    } catch (error) {
      if (loadToken !== this._loadToken) {
        return;
      }

      this.errorMessage =
        error?.body?.message ||
        error?.message ||
        'Unable to load Egnyte for this record.';
      await this.loadOAuthConnectLink(this.errorMessage);
    } finally {
      if (loadToken === this._loadToken) {
        this.isLoading = false;
      }
    }
  }

  async loadOAuthConnectLink(message) {
    const normalizedMessage = (message || '').toLowerCase();
    const needsOAuth =
      normalizedMessage.includes('refresh token') ||
      normalizedMessage.includes('access token') ||
      normalizedMessage.includes('foldermap api');

    if (!needsOAuth) {
      return;
    }

    try {
      const status = await getOAuthStatus();
      this.oauthConnectUrl = status?.connectUrl;
      this.showOAuthConnectLink = !!this.oauthConnectUrl;
    } catch (statusError) {
      this.showOAuthConnectLink = false;
    }
  }
}