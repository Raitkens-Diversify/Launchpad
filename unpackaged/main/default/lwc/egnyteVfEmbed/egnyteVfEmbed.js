/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 *
 * Embeds Egnyte in an iframe for LWR Experience sites.
 * Record pages use Egnyte_integration_page; standalone pages use My Egnyte VF.
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    resolveRecordIdFromPageReference,
    isValidSalesforceRecordId
} from 'c/recordNavigationUtils';
import buildVfEmbedUrl from '@salesforce/apex/EgnyteVfEmbedController.buildVfEmbedUrl';

const STANDALONE_VF_PAGE = 'efs__MyEgnyte';
const SITE_PATH_PREFIX = 'vforcesite';
const RECORD_VF_PAGE = 'Egnyte_integration_page';
const DEFAULT_DOMAIN = 'https://arc-launchpad.diversify.com';
const IFRAME_TITLE = 'Egnyte';
const MIN_HEIGHT_PX = 600;
const PREVIEW_HOST_PATTERN = 'preview.salesforce-experience.com';

const toSameOriginEmbedPath = (urlFromApex) => {
    if (!urlFromApex) {
        return null;
    }

    if (/^https?:\/\//i.test(urlFromApex)) {
        try {
            const parsed = new URL(urlFromApex);
            if (
                typeof window !== 'undefined' &&
                parsed.hostname === window.location.hostname
            ) {
                return parsed.pathname + parsed.search;
            }
            return urlFromApex;
        } catch {
            return null;
        }
    }

    return urlFromApex.startsWith('/') ? urlFromApex : `/${urlFromApex}`;
};

export default class EgnyteVfEmbed extends NavigationMixin(LightningElement) {
    @api domain = DEFAULT_DOMAIN;

    loading = true;
    error;
    vfPageUrl;
    _pageRef;
    _contextRecordId;
    _resolvedKey;
    _isPreviewHost;

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        this._pageRef = pageReference;
        this.syncRecordIdFromContext();
    }

    connectedCallback() {
        this._isPreviewHost =
            typeof window !== 'undefined' &&
            window.location.hostname.includes(PREVIEW_HOST_PATTERN);
        this.syncRecordIdFromContext();
        this.resolveEmbedUrl();
    }

    get activeRecordId() {
        return this._contextRecordId || null;
    }

    get iframeTitle() {
        return IFRAME_TITLE;
    }

    get isPreviewHost() {
        return this._isPreviewHost;
    }

    get isStandaloneView() {
        return !this.activeRecordId;
    }

    get hasUrl() {
        return !!this.vfPageUrl;
    }

    get showPreviewFallback() {
        return this.hasUrl && this.isPreviewHost && this.isStandaloneView;
    }

    get showIframe() {
        return this.hasUrl && !this.showPreviewFallback;
    }

    get iframeStyle() {
        return `min-height: ${MIN_HEIGHT_PX}px; height: 100%; width: 100%; background: #fff;`;
    }

    get showStatusSpinner() {
        return this.loading && !this.error && this.showIframe;
    }

    get showOpenFullPageLink() {
        return false;
    }

    syncRecordIdFromContext() {
        const resolved = resolveRecordIdFromPageReference(this._pageRef, null);
        const nextRecordId = isValidSalesforceRecordId(resolved) ? resolved : null;

        if (nextRecordId === this._contextRecordId) {
            return;
        }

        this._contextRecordId = nextRecordId;
        this.resolveEmbedUrl();
    }

    async resolveEmbedUrl() {
        const recordId = this.activeRecordId;
        const siteDomain = this.normalizeDomain(this.domain);
        const mode = recordId ? 'record' : 'standalone';
        const resolveKey = `${siteDomain}|${mode}|${recordId || ''}`;

        if (this._resolvedKey === resolveKey && this.vfPageUrl) {
            return;
        }

        this._resolvedKey = resolveKey;
        this.loading = true;
        this.error = undefined;
        this.vfPageUrl = undefined;

        try {
            const url = await buildVfEmbedUrl({
                domain: siteDomain,
                recordId: recordId || null
            });

            if (!url) {
                throw new Error('Visualforce URL could not be built.');
            }

            this.vfPageUrl = this.isPreviewHost
                ? url
                : toSameOriginEmbedPath(url) || url;
        } catch (apexError) {
            this.vfPageUrl = this.buildClientFallbackUrl(siteDomain, recordId);
            if (!this.vfPageUrl) {
                this.error =
                    apexError?.body?.message ||
                    'Unable to build the Egnyte Visualforce URL. Confirm the page exists and is enabled for this site.';
            }
        }

        if (this.isPreviewHost && this.isStandaloneView) {
            this.loading = false;
        }
    }

    buildClientFallbackUrl(siteDomain, recordId) {
        const params = new URLSearchParams();
        const vfPageName = recordId ? RECORD_VF_PAGE : STANDALONE_VF_PAGE;

        if (recordId) {
            params.set('id', recordId);
        }
        params.set('isdtp', 'nv');

        const relativeUrl = `/${SITE_PATH_PREFIX}/apex/${vfPageName}?${params.toString()}`;
        return this.isPreviewHost
            ? `${siteDomain}${relativeUrl}`
            : relativeUrl;
    }

    normalizeDomain(value) {
        const normalized = (value || DEFAULT_DOMAIN).trim().replace(/\/$/, '');
        if (/^https?:\/\//i.test(normalized)) {
            return normalized;
        }
        return `https://${normalized}`;
    }

    handleIframeLoad() {
        this.loading = false;
        this.error = undefined;
    }

    handleIframeError() {
        this.loading = false;
        this.error =
            'Unable to load Egnyte. Confirm the Visualforce page is enabled for this site and your profile has access.';
    }

    handleOpenEgnyteNewTab() {
        const url = this.vfPageUrl;
        if (!url) {
            return;
        }
        window.open(url, '_blank', 'noopener,noreferrer');
    }

    handleOpenFullPage(event) {
        event.preventDefault();
        const url = this.vfPageUrl;
        if (!url) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url
            }
        });
    }
}