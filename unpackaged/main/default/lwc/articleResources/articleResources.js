import { LightningElement, api, wire } from 'lwc';
import { typeMeta } from 'c/resourceTypeIcons';
import { linkContext, resourceHref, isSameSite, goToResource } from 'c/contextNav';
import { isFileType, resourceAction } from 'c/rcConstants';
import getResourcesForArticle from '@salesforce/apex/ResourceCenterService.getResourcesForArticle';
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
    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;
    loading = true;

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
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
            const detailUrl = resourceHref(this.linkCtx, r.slug);
            // One CTA rule with the card grids: an off-site href (External
            // Link, an upcoming webinar's sign-up) wins over the detail page.
            const cta = resourceAction(r);
            const isFile = !!r.downloadUrl && isFileType(r.resourceType);
            let href = null;
            let target = null;
            let download = false;
            let trackClick = false;
            if (cta.href) {
                href = cta.href;
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
                slug: r.slug,
                iconPath: meta.iconPath,
                badge: meta.badge,
                action: cta.action,
                href,
                target,
                // A same-site detail link: plain clicks route in place (see
                // handleLinkClick); the href stays for middle/modifier clicks.
                isDetail: !cta.href && !!detailUrl,
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
        // A plain click on a same-site detail link routes in place instead of
        // following the target="_blank" anchor: goToResource has no mixin here,
        // so contextNav dispatches `resourceselect` for the host with a mixin
        // (helpArticlePage / resourceCenter / unifiedLanding) to route
        // client-side. Middle/modifier clicks keep the anchor's new-tab
        // semantics. Gated on isSameSite: the core-app hosts (nexsLanding) do
        // not listen for resourceselect, and there the anchor already goes to
        // the Resource_Center tab.
        const isPlainClick =
            event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
        if (event.currentTarget.dataset.detail === 'true' && isPlainClick && isSameSite(this.linkCtx)) {
            event.preventDefault();
            goToResource(this, this.linkCtx, { slug: event.currentTarget.dataset.slug });
            return;
        }

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