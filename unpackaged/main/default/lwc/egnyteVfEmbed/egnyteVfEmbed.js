/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 *
 * Embeds Egnyte in an iframe for LWR Experience sites.
 * Record pages use Egnyte_integration_page; standalone pages use My Egnyte VF.
 *
 * ── 2026-08-27: the Approve link ──────────────────────────────────────────────
 *
 * Egnyte_integration_page renders <efs:egnyteload>, and until the user has
 * authorised the Egnyte app that renders "Application Approval Required" with an
 * Approve link instead of the file list. Clicking it did nothing.
 *
 * WHAT IS ACTUALLY IN THERE, read off /apex/Egnyte_integration_page directly:
 *
 *   this component's iframe            (site origin, sandboxed)
 *     └── the Visualforce document     (body.innerText is EMPTY)
 *           └── iframe id="canvas-outer-…:canvasapp"  height="600px"
 *                 └── CROSS-ORIGIN. The approval prompt lives here.
 *
 * efs:egnyteload is a Canvas app. The prompt is two frames down and on another
 * origin, so nothing on this side can read it, rewrite its link, or measure it.
 * An earlier pass here tried to detect the prompt by reading the frame's document
 * and lifting the Approve href out of it; that could never have worked and has
 * been removed rather than left in looking useful.
 *
 * Two things are done instead:
 *
 *   1. allow-top-navigation-by-user-activation on the sandbox. Sandbox flags are
 *      inherited by nested frames, so this is what lets the in-canvas Approve
 *      link attempt to leave the frame at all. NECESSARY BUT NOT SUFFICIENT --
 *      this shipped on its own first and Approve still did nothing.
 *
 *   2. The reason it still did nothing: the ARC site's CSP allows frame-src for
 *      launchpad.egnyte.com and falconpark.egnyte.com only, and the approval page
 *      is a Salesforce page on the ORG domain. The site's own policy refuses the
 *      navigation whatever the sandbox permits, and the same CSP applies to every
 *      tab on the ARC origin -- so opening the SITE's own Visualforce URL in a new
 *      tab, which is what an earlier pass here did, does not help either.
 *
 *      "Approve access" therefore opens the page on the ORG domain, via
 *      ArcEgnyteAccessController.getApprovalUrl. No community CSP applies there
 *      and the flow behaves as it does in the CRM app, which is where it works
 *      today. Approve there, come back, hit Reload.
 *
 * The action is always present, because the approval state cannot be detected
 * from here and a button that is occasionally redundant beats one that is missing
 * when it matters.
 *
 * The permanent fix is org configuration, not code: pre-authorise the Egnyte
 * connected app for these profiles and the prompt never appears for anyone.
 *
 * ── The empty space ──────────────────────────────────────────────────────────
 *
 * The canvas iframe is fixed at height="600px" by the pageHeight passed to
 * efs:egnyteload, whatever it is showing. The approval prompt is about half that,
 * which is where the blank half of the panel came from. 600px cannot be changed
 * from here, so the OUTER frame is sized to FRAME_HEIGHT_PX instead and the
 * canvas scrolls inside it — the prompt sits at the top of the canvas, so it
 * stays fully visible and it is the blank half that gets clipped. Exposed as a
 * property so it can be raised once the file browser is what people see.
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    resolveRecordIdFromPageReference,
    isValidSalesforceRecordId
} from 'c/recordNavigationUtils';
import buildVfEmbedUrl from '@salesforce/apex/EgnyteVfEmbedController.buildVfEmbedUrl';
import getApprovalUrl from '@salesforce/apex/ArcEgnyteAccessController.getApprovalUrl';

const STANDALONE_VF_PAGE = 'efs__MyEgnyte';
const SITE_PATH_PREFIX = 'vforcesite';
const RECORD_VF_PAGE = 'Egnyte_integration_page';
/** Any object other than Account -- see EgnyteVfEmbedController.resolveRecordVfPage. */
const GENERIC_RECORD_VF_PAGE = 'Egnyte_record_page';
const ACCOUNT_KEY_PREFIX = '001';
const DEFAULT_DOMAIN = 'https://arc-launchpad.diversify.com';
const IFRAME_TITLE = 'Egnyte';
/**
 * Height of the outer frame. Deliberately less than the canvas app's own fixed
 * 600px: see the note above. Overridable per placement.
 */
const FRAME_HEIGHT_PX = 440;
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

    /** Card heading. Blank renders the panel without one. */
    @api cardTitle = 'Documents';

    /**
     * Outer frame height in pixels. The canvas app inside is fixed at 600px and
     * scrolls, so this is how tall the panel is, not how tall Egnyte thinks it is.
     */
    @api frameHeight = FRAME_HEIGHT_PX;

    loading = true;
    error;
    vfPageUrl;

    _pageRef;
    _contextRecordId;
    _resolvedKey;
    _isPreviewHost;
    approvalUrl;

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
        return `height: ${this.resolvedFrameHeight}px; width: 100%; background: #fff;`;
    }

    get showStatusSpinner() {
        return this.loading && !this.error && this.showIframe;
    }

    /** The header carries the actions, so it renders even with no title set. */
    get showCardHeader() {
        return true;
    }

    get resolvedFrameHeight() {
        const parsed = parseInt(this.frameHeight, 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : FRAME_HEIGHT_PX;
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
        // Mirrors EgnyteVfEmbedController.resolveRecordVfPage: only Accounts may
        // use the Account-bound page.
        const vfPageName = recordId
            ? recordId.startsWith(ACCOUNT_KEY_PREFIX)
                ? RECORD_VF_PAGE
                : GENERIC_RECORD_VF_PAGE
            : STANDALONE_VF_PAGE;

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

    /**
     * Opens the Egnyte page on the ORG domain, in its own tab, where the canvas
     * app's Approve link works: no sandbox, and none of the ARC site's CSP.
     *
     * Resolved lazily on click rather than up front, so a component that never
     * needs it costs no server call.
     */
    async handleApproveInNewTab() {
        let url = this.approvalUrl;

        if (!url) {
            try {
                url = await getApprovalUrl({ recordId: this.activeRecordId });
                this.approvalUrl = url;
            } catch (apexError) {
                /*
                 * Falling back to the site URL is worth doing even though the CSP
                 * may block the approval there: the page still loads, and a user
                 * looking at the prompt is better off than at a dead button.
                 */
                url = this.vfPageUrl;
            }
        }

        if (!url) {
            return;
        }

        const absolute = /^https?:\/\//i.test(url)
            ? url
            : `${window.location.origin}${url}`;
        window.open(absolute, '_blank', 'noopener,noreferrer');
    }

    /** Puts the file list back after approving in the other tab. */
    handleReloadEgnyte() {
        this.loading = true;
        const frame = this.template.querySelector('iframe');
        if (!frame) {
            return;
        }
        try {
            frame.contentWindow.location.reload();
        } catch {
            // Cross-origin — re-assigning src reloads it either way.
            frame.setAttribute('src', frame.getAttribute('src'));
        }
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