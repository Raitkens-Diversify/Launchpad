import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import getResourceBySlug from '@salesforce/apex/ResourceCenterService.getResourceBySlug';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import getResourceDownloadUrl from '@salesforce/apex/ResourceCenterService.getResourceDownloadUrl';
import {
    TYPE_VIDEO,
    TYPE_EXTERNAL_LINK,
    TYPE_WEBINAR,
    rcRootCrumbs,
    CRUMB_HELP_HOME
} from 'c/rcConstants';
import { linkContext, articleHref, fileHref } from 'c/contextNav';
import { isScribeUrl } from 'c/scribeUrlUtil';
import { sanitizeHtml } from 'c/richTextUtil';

/**
 * resourceDetail — full resource view. File-backed types (PDF/Form/Template):
 * inline paged preview from Salesforce's SVGZ renditions (the download servlet
 * is Content-Disposition: attachment, so it can never render in a frame) +
 * explicit Download. Video: responsive 16:9 embed. External Link: opens in a
 * new tab. Webinar: the whole body is c-event-detail (2026-09-07 — header,
 * agenda, presenters, the details card with viewer-zone times and the
 * clock-derived CTA, sibling events); this host keeps the breadcrumb above
 * it and Related Articles (reverse junction, linking to the Help Center when
 * helpCenterBaseUrl is provided) below. Description__c is rich text: the
 * non-event body injects `descriptionHtml` as manual DOM through
 * c/richTextUtil.
 *
 * Preview paging: page count isn't queryable, so pages grow lazily — each
 * onload appends the next page until one errors (capped). Servlet paths go
 * through c/contextNav.fileHref (site-native `<sitePath>/sfsites/c/sfc/…` on
 * a site, root-relative in the core app); a page-0 error first retries the
 * root-relative form (the one *.my.site.com answers), then falls back to the
 * THUMB720BY480 rendition (plain images), then to a friendly "no preview"
 * card (renditions can lag right after upload). The Download href takes the
 * same path so a custom-domain site never saves a login page as an .htm.
 *
 * Emits (composed): `categoryselect { slug }`. Downloads are tracked
 * directly via trackDownload when the Download button is clicked.
 */
const MAX_PREVIEW_PAGES = 25;

export default class ResourceDetail extends LightningElement {
    @api slug;
    /** Optional override; defaults to the site root resolved server-side. */
    @api helpCenterBaseUrl;

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
            // The wire may have landed first with no surface known: rebuild
            // the servlet URLs now that the site path is.
            if (this.detail) {
                this.resetPreview();
            }
        });
    }

    /** Candidate preview bases in retry order (site-native, then root-relative). */
    _previewForms = [];
    _formIndex = 0;

    detail;
    error;
    loading = true;

    previewPages = [];
    previewFailed = false;
    usingImageFallback = false;

    @wire(getResourceBySlug, { slug: '$slug' })
    wiredResource({ data, error }) {
        if (data) {
            this.detail = data;
            this.error = undefined;
            this.loading = false;
            this.resetPreview();
        } else if (error) {
            this.detail = undefined;
            this.error = (error.body && error.body.message) || 'Something went wrong.';
            this.loading = false;
        }
    }

    get isFileBacked() {
        return this.hasFile && !this.showEmbed && !this.isExternal && !this.isWebinar;
    }
    /** Embedded player: a Video (a webinar's recording plays inside c-event-detail). */
    get showEmbed() {
        return !!this.detail && !!this.detail.videoEmbedUrl
            && this.detail.resourceType === TYPE_VIDEO;
    }
    get isWebinar() {
        return !!this.detail && this.detail.resourceType === TYPE_WEBINAR;
    }
    get descriptionHtml() {
        const html = this.detail && this.detail.descriptionHtml;
        return html && html.trim() ? html : null;
    }
    get hasDescription() {
        return !!this.descriptionHtml;
    }

    /** The HTML last injected into the manual container (re-inject only on change). */
    _renderedHtml = null;

    renderedCallback() {
        const container = this.template.querySelector('.rd__desc');
        const html = this.descriptionHtml;
        if (container && this._renderedHtml !== html) {
            container.innerHTML = sanitizeHtml(html);
            this._renderedHtml = html;
        }
        if (!container) {
            this._renderedHtml = null;
        }
    }
    get isExternal() {
        return this.detail && this.detail.resourceType === TYPE_EXTERNAL_LINK && !!this.detail.externalUrl;
    }
    /** An External Link that is a Scribe guide renders inline (c-scribe-embed
        carries its own "Open in Scribe"); any other link keeps the button. */
    get isScribeLink() {
        return !!this.isExternal && isScribeUrl(this.detail.externalUrl);
    }
    get isPlainExternal() {
        return !!this.isExternal && !this.isScribeLink;
    }
    get hasFile() {
        return !!(this.detail && this.detail.file && this.detail.file.downloadUrl);
    }
    get showPreview() {
        return this.previewPages.length > 0 && !this.previewFailed;
    }
    get showPreviewFallback() {
        return this.previewFailed || this.previewPages.length === 0;
    }
    get fileLabel() {
        return (this.detail && this.detail.file && this.detail.file.title) || 'Attached file';
    }
    get fileIconPath() {
        return iconPath('documents');
    }
    get relatedArticles() {
        if (!this.detail || !this.detail.relatedArticles) {
            return [];
        }
        return this.detail.relatedArticles.map((a) => ({
            ...a,
            href: this.helpCenterBaseUrl
                ? articleHref({ helpBase: this.helpCenterBaseUrl }, a.urlName)
                : articleHref(this.linkCtx, a.urlName)
        }));
    }
    get hasRelated() {
        return this.relatedArticles.length > 0;
    }
    get downloadLabel() {
        const size = this.detail && this.detail.file && this.detail.file.fileSizeLabel;
        return size ? `Download (${size})` : 'Download';
    }

    // ---- Preview paging -------------------------------------------------------------

    resetPreview() {
        this.previewFailed = false;
        this.usingImageFallback = false;
        this.previewPages = [];
        this._previewForms = [];
        this._formIndex = 0;
        const file = this.detail && this.detail.file;
        if (this.isFileBacked && file && file.previewUrl) {
            const site = fileHref(this.linkCtx, file.previewUrl);
            this._previewForms = site === file.previewUrl
                ? [file.previewUrl]
                : [site, file.previewUrl];
            this.previewPages = [this.page(0)];
        } else if (this.isFileBacked) {
            this.previewFailed = true;
        }
    }

    page(index) {
        return {
            index,
            // The form index is in the key so a retry mounts a fresh <img>.
            key: `form-${this._formIndex}-page-${index}`,
            src: `${this._previewForms[this._formIndex]}&page=${index}`,
            alt: `${this.detail.name} — page ${index + 1}`
        };
    }

    /** Download href on this surface (see fileHref); null without a file. */
    get downloadHref() {
        const file = this.detail && this.detail.file;
        return file ? fileHref(this.linkCtx, file.downloadUrl) : null;
    }

    handlePageLoad(event) {
        const index = Number(event.target.dataset.index);
        if (
            !this.usingImageFallback &&
            index === this.previewPages.length - 1 &&
            this.previewPages.length < MAX_PREVIEW_PAGES
        ) {
            this.previewPages = [...this.previewPages, this.page(index + 1)];
        }
    }

    handlePageError(event) {
        const index = Number(event.target.dataset.index);
        if (index > 0) {
            // Ran past the last page — trim the failed one and stop growing.
            this.previewPages = this.previewPages.slice(0, index);
            return;
        }
        if (this._formIndex + 1 < this._previewForms.length) {
            // The site-native servlet path did not answer: try the root form.
            this._formIndex += 1;
            this.previewPages = [this.page(0)];
            return;
        }
        const file = this.detail && this.detail.file;
        if (!this.usingImageFallback && file && file.imagePreviewUrl) {
            this.usingImageFallback = true;
            this.previewPages = [{
                index: 0,
                key: 'image-preview',
                src: fileHref(this.linkCtx, file.imagePreviewUrl),
                alt: this.detail.name
            }];
            return;
        }
        this.previewPages = [];
        this.previewFailed = true;
    }

    // ---- Events -----------------------------------------------------------------

    /** The unified home is another page; the shell routes it via c/contextNav. */
    handleHelpHome() {
        this.dispatchEvent(new CustomEvent('helphome', { bubbles: true, composed: true }));
    }

    /** Full-path crumb trail: Help & Resources › RC › [ancestors… ›] category › resource
        (always the HOME category's chain, never a secondary placement). */
    get crumbItems() {
        const crumbs = rcRootCrumbs();
        if (this.detail) {
            (this.detail.categoryAncestors || []).forEach((a) => {
                crumbs.push({ label: a.name, key: a.slug });
            });
            if (this.detail.categorySlug) {
                crumbs.push({ label: this.detail.categoryName, key: this.detail.categorySlug });
            }
            crumbs.push({ label: this.detail.name });
        }
        return crumbs;
    }

    handleCrumb(event) {
        const key = event.detail.key;
        if (key === CRUMB_HELP_HOME) {
            this.handleHelpHome();
        } else {
            this.dispatchEvent(new CustomEvent('categoryselect', {
                detail: { slug: key }, bubbles: true, composed: true
            }));
        }
    }
    handleDownload(event) {
        if (!this.detail) {
            return;
        }
        trackDownload({ resourceId: this.detail.id }).catch(() => {});

        // The href baked into `detail.file.downloadUrl` is only ever the
        // authenticated Shepherd URL (resolved during the cacheable wire) —
        // resolve the real, guest-safe URL fresh at click time instead.
        const fallbackUrl = this.downloadHref;
        const contentDocumentId = this.detail.file?.contentDocumentId;
        if (!contentDocumentId) {
            return;
        }

        event.preventDefault();
        getResourceDownloadUrl({ contentDocumentId })
            .then((url) => {
                window.location.href = fileHref(this.linkCtx, url) || fallbackUrl;
            })
            .catch(() => {
                if (fallbackUrl) {
                    window.location.href = fallbackUrl;
                }
            });
    }
}