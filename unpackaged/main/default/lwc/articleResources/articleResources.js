import { LightningElement, api, wire } from 'lwc';
import { typeMeta } from 'c/resourceTypeIcons';
import { resourceDetailUrl } from 'c/rcLinkUtil';
import { isFileType, TYPE_EXTERNAL_LINK } from 'c/rcConstants';
import getResourcesForArticle from '@salesforce/apex/ResourceCenterService.getResourcesForArticle';
import getResourceLinkBase from '@salesforce/apex/ResourceCenterService.getResourceLinkBase';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import getResourceDownloadUrl from '@salesforce/apex/ResourceCenterService.getResourceDownloadUrl';

/**
 * articleResources — "Downloads & Resources" card in the article page's right
 * rail (hosted by nexsArticleBrowser next to Suggested Articles). Given the
 * Knowledge__kav version Id, it lists the resources linked to that article's
 * stable KA Id. Renders nothing when there are none, and reports the count to
 * the host via `resourcesload` so the rail column can collapse.
 *
 * View-first: rows link to the resource's detail page on the Resource Center
 * (preview + tracked download live there). Only when no Resource Center page
 * is available does a file row fall back to a direct download.
 *
 * @api articleId — the Knowledge__kav version Id (from the browser)
 */
export default class ArticleResources extends LightningElement {
    @api articleId;

    resources = [];
    linkBase = null;
    loading = true;

    connectedCallback() {
        getResourceLinkBase()
            .then((base) => {
                this.linkBase = base || null;
            })
            .catch(() => {
                this.linkBase = null;
            });
    }

    @wire(getResourcesForArticle, { knowledgeArticleVersionId: '$articleId' })
    wiredResources({ data, error }) {
        if (data) {
            this.resources = data;
            this.loading = false;
        } else if (error) {
            // Graceful: no card at all on error.
            this.resources = [];
            this.loading = false;
        } else {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('resourcesload', { detail: { count: this.resources.length } })
        );
    }

    get rows() {
        return this.resources.map((r) => {
            const meta = typeMeta(r.resourceType);
            const detailUrl = resourceDetailUrl(this.linkBase, r.slug);
            const isExternal = r.resourceType === TYPE_EXTERNAL_LINK && !!r.externalUrl;
            const isFile = !!r.downloadUrl && isFileType(r.resourceType);
            let href = null;
            let target = null;
            let download = false;
            let trackClick = false;
            if (isExternal) {
                href = r.externalUrl;
                target = '_blank';
            } else if (detailUrl) {
                href = detailUrl;
                target = '_blank';
            } else if (isFile) {
                // No Resource Center page to link to — direct download fallback.
                href = r.downloadUrl;
                download = true;
                trackClick = true;
            }
            return {
                id: r.id,
                name: r.name,
                iconPath: meta.iconPath,
                badge: meta.badge,
                action: meta.action,
                href,
                target,
                download,
                trackClick,
                contentDocumentId: isFile ? r.contentDocumentId : null
            };
        });
    }

    get hasResources() {
        return this.resources.length > 0;
    }

    handleLinkClick(event) {
        // Downloads are normally tracked on the detail page; only the direct-
        // download fallback needs to track here.
        const id = event.currentTarget.dataset.id;
        const track = event.currentTarget.dataset.track === 'true';
        if (!id || !track) {
            return;
        }

        trackDownload({ resourceId: id }).catch(() => {
            /* fire-and-forget */
        });

        // The row's href is only ever the authenticated Shepherd URL baked in
        // at wire time — resolve the real, guest-safe URL fresh on click.
        const contentDocumentId = event.currentTarget.dataset.contentDocumentId;
        const fallbackUrl = event.currentTarget.href;
        if (!contentDocumentId) {
            return;
        }

        event.preventDefault();
        getResourceDownloadUrl({ contentDocumentId })
            .then((url) => {
                window.location.href = url || fallbackUrl;
            })
            .catch(() => {
                if (fallbackUrl) {
                    window.location.href = fallbackUrl;
                }
            });
    }
}