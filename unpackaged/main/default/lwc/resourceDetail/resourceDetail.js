import { LightningElement, api, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import getResourceBySlug from '@salesforce/apex/ResourceCenterService.getResourceBySlug';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import getHelpCenterLinkBase from '@salesforce/apex/ResourceCenterService.getHelpCenterLinkBase';
import { TYPE_VIDEO, TYPE_EXTERNAL_LINK } from 'c/rcConstants';

/**
 * resourceDetail — full resource view. File-backed types (PDF/Form/Template):
 * inline paged preview from Salesforce's SVGZ renditions (the download servlet
 * is Content-Disposition: attachment, so it can never render in a frame) +
 * explicit Download. Video: responsive 16:9 embed. External Link: opens in a
 * new tab. Shows Related Articles (reverse junction), linking to the Help
 * Center when helpCenterBaseUrl is provided.
 *
 * Preview paging: page count isn't queryable, so pages grow lazily — each
 * onload appends the next page until one errors (capped). A page-0 error falls
 * back to the THUMB720BY480 rendition (plain images), then to a friendly
 * "no preview" card (renditions can lag right after upload).
 *
 * Emits (composed): `rchome`, `categoryselect { slug }`. Downloads are tracked
 * directly via trackDownload when the Download button is clicked.
 */
const MAX_PREVIEW_PAGES = 25;

export default class ResourceDetail extends LightningElement {
    @api slug;
    /** Optional override; defaults to the site root resolved server-side. */
    @api helpCenterBaseUrl;

    resolvedHelpBase;

    @wire(getHelpCenterLinkBase)
    wiredHelpBase({ data }) {
        if (data) {
            this.resolvedHelpBase = data;
        }
    }

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
        return this.hasFile && !this.isVideo && !this.isExternal;
    }
    get isVideo() {
        return this.detail && this.detail.resourceType === TYPE_VIDEO && !!this.detail.videoEmbedUrl;
    }
    get isExternal() {
        return this.detail && this.detail.resourceType === TYPE_EXTERNAL_LINK && !!this.detail.externalUrl;
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
        const raw = this.helpCenterBaseUrl || this.resolvedHelpBase;
        const base = raw ? raw.replace(/\/$/, '') : null;
        return this.detail.relatedArticles.map((a) => ({
            ...a,
            // Query-param deep link — the site has no /article/ route.
            href: base && a.urlName ? `${base}/?article=${encodeURIComponent(a.urlName)}` : null
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
        const file = this.detail && this.detail.file;
        if (this.isFileBacked && file && file.previewUrl) {
            this.previewPages = [this.page(0)];
        } else if (this.isFileBacked) {
            this.previewFailed = true;
        }
    }

    page(index) {
        return {
            index,
            key: `page-${index}`,
            src: `${this.detail.file.previewUrl}&page=${index}`,
            alt: `${this.detail.name} — page ${index + 1}`
        };
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
        const file = this.detail && this.detail.file;
        if (!this.usingImageFallback && file && file.imagePreviewUrl) {
            this.usingImageFallback = true;
            this.previewPages = [{
                index: 0,
                key: 'image-preview',
                src: file.imagePreviewUrl,
                alt: this.detail.name
            }];
            return;
        }
        this.previewPages = [];
        this.previewFailed = true;
    }

    // ---- Events -----------------------------------------------------------------

    handleHome() {
        this.dispatchEvent(new CustomEvent('rchome', { bubbles: true, composed: true }));
    }

    /** Full-path crumb trail: RC › [main topic ›] [subtopic ›] resource. */
    get crumbItems() {
        const crumbs = [{ label: 'Resource Center', key: 'home' }];
        if (this.detail) {
            if (this.detail.categoryParentSlug) {
                crumbs.push({
                    label: this.detail.categoryParentName,
                    key: this.detail.categoryParentSlug
                });
            }
            if (this.detail.categorySlug) {
                crumbs.push({ label: this.detail.categoryName, key: this.detail.categorySlug });
            }
            crumbs.push({ label: this.detail.name });
        }
        return crumbs;
    }

    handleCrumb(event) {
        const key = event.detail.key;
        if (key === 'home') {
            this.handleHome();
        } else {
            this.dispatchEvent(new CustomEvent('categoryselect', {
                detail: { slug: key }, bubbles: true, composed: true
            }));
        }
    }
    handleDownload() {
        if (this.detail) {
            trackDownload({ resourceId: this.detail.id }).catch(() => {});
        }
    }
}