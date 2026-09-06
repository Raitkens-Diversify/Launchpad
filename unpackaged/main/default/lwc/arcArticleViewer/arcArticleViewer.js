import { LightningElement, api, track } from 'lwc';
import getArticle from '@salesforce/apex/ArcKnowledgeController.getArticle';
import logView from '@salesforce/apex/ArcArticleEngagementController.logView';
import { extractScribeSegments, parseScribeUrl, titleFromSlug } from 'c/scribeUrlUtil';

// Active-content tags stripped by the sanitizer; standard formatting markup
// (headings, lists, tables, images, links) passes through untouched.
const BLOCKED_TAGS = 'script, style, iframe, object, embed, link, meta, form';

/**
 * arcArticleViewer
 *
 * Renders a single article's rich-text body. Purely presentational and
 * context-agnostic — it takes an articleId and asks Apex for the content, so it
 * drops unchanged into the LWR site or a core Lightning App page.
 *
 * Imperative (not @wire) on purpose: getArticle rejects a null id, so we only
 * call once an id is actually set rather than firing an errored wire on mount.
 *
 * The body is sanitized here (DOMParser pass) and injected into
 * lwc:dom="manual" divs instead of lightning-formatted-rich-text: under native
 * shadow DOM (LWR) that component's shadow root is unreachable, which blocks
 * both per-element body typography and the "In this article" anchor scrolling.
 *
 * Scribe guides: a Scribe link pasted on its own line (bare, or a link whose
 * label becomes the guide's title) is lifted out of the body by
 * c/scribeUrlUtil and rendered in place as <c-scribe-embed>. LWC cannot mount
 * a component inside innerHTML, so the body is rendered as ORDERED SEGMENTS —
 * html (its own manual container) / embed / html … — keyed per article so a
 * new article recreates every container. The legacy Embed_URL__c field still
 * works: a Scribe value becomes a trailing embed, any other https value keeps
 * the raw trailing iframe it always had. Only scribehow.com is ever framed.
 * (Mirror of nexsArticleViewer minus c/contextNav — the arc fork.)
 *
 * Events:
 *   articleload  { title, suggestions, hasEmbed }  — fired once the article
 *     resolves; title feeds the breadcrumb, suggestions (server-built: authored
 *     picks + same-topic top-up) feed the host's "Suggested Articles" rail
 */
export default class ArcArticleViewer extends LightningElement {
    @track article;
    @track error;
    @track headings = [];
    @track segments = [];
    loading = false;
    _articleId;
    _segHtml = new Map();
    _renderedArticleId;
    // Articles already counted by this instance — one view per article per
    // mount, so unrelated re-renders don't inflate Article_View__c counts.
    _loggedViews = new Set();

    @api
    get articleId() {
        return this._articleId;
    }
    set articleId(value) {
        this._articleId = value;
        if (value) {
            this.load();
        } else {
            this.article = undefined;
            this.error = undefined;
            this.headings = [];
            this.segments = [];
            this._segHtml = new Map();
            this._renderedArticleId = undefined;
        }
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        this._renderedArticleId = undefined;
        try {
            const detail = await getArticle({ articleId: this._articleId });
            const { segments, headings } = this.sanitizeAndIndex(detail.body, detail.id);
            this.appendLegacyEmbed(segments, detail);
            this._segHtml = new Map(segments.filter((s) => s.isHtml).map((s) => [s.key, s.html]));
            this.segments = segments;
            this.headings = headings;
            this.article = detail;
            this.dispatchEvent(
                new CustomEvent('articleload', {
                    detail: {
                        title: detail.title,
                        suggestions: detail.suggestions || [],
                        // Lets the host drop the Suggested rail and go full width
                        // for guide articles — see arcArticleBrowser.
                        hasEmbed: this.hasEmbed
                    },
                    bubbles: true,
                    composed: true
                })
            );
            // Fire-and-forget view tracking: reading never waits on (or breaks
            // over) analytics. On failure the id is released so a later open
            // of the same article can retry.
            if (!this._loggedViews.has(detail.id)) {
                this._loggedViews.add(detail.id);
                logView({ articleId: detail.id }).catch(() => {
                    this._loggedViews.delete(detail.id);
                });
            }
        } catch (e) {
            this.article = undefined;
            this.headings = [];
            this.segments = [];
            this._segHtml = new Map();
            this.error = e?.body?.message || 'Unable to load this article.';
        } finally {
            this.loading = false;
        }
    }

    /**
     * Embed_URL__c holding a Scribe link renders through the same component as
     * an in-body guide, after the body — unless the body already embeds that
     * very guide.
     */
    appendLegacyEmbed(segments, detail) {
        const legacy = parseScribeUrl(detail.embedUrl);
        if (!legacy) {
            return;
        }
        const alreadyInBody = segments.some((s) => {
            const p = s.isEmbed ? parseScribeUrl(s.url) : null;
            return p && p.id === legacy.id;
        });
        if (alreadyInBody) {
            return;
        }
        segments.push({
            key: `${detail.id}:${segments.length}`,
            kind: 'embed',
            isHtml: false,
            isEmbed: true,
            url: detail.embedUrl,
            title: titleFromSlug(legacy.slug) || undefined
        });
    }

    // Inject every html segment once per article; the guard keeps unrelated
    // re-renders from resetting the manual DOM (and the user's scroll position).
    renderedCallback() {
        if (!this.article || this._renderedArticleId === this.article.id) {
            return;
        }
        const containers = this.template.querySelectorAll('[data-seg]');
        if (!containers.length && this._segHtml.size) {
            return;
        }
        containers.forEach((container) => {
            container.innerHTML = this._segHtml.get(container.dataset.seg) || '';
        });
        this._renderedArticleId = this.article.id;
    }

    /**
     * DOMParser-based sanitize: drop active-content elements, strip on*
     * handlers and javascript: URLs, tag h2/h3 with generated ids so the
     * anchor nav can scroll to them, then split the body into html / Scribe
     * embed segments keyed by article id.
     */
    sanitizeAndIndex(html, articleId = this._articleId) {
        const doc = new DOMParser().parseFromString(html || '', 'text/html');

        doc.body.querySelectorAll(BLOCKED_TAGS).forEach((el) => el.remove());

        doc.body.querySelectorAll('*').forEach((el) => {
            [...el.attributes].forEach((attr) => {
                const name = attr.name.toLowerCase();
                const value = attr.value.trim().toLowerCase();
                if (
                    name.startsWith('on') ||
                    ((name === 'href' || name === 'src' || name === 'xlink:href') &&
                        value.startsWith('javascript:'))
                ) {
                    el.removeAttribute(attr.name);
                }
            });
        });

        const headings = [];
        doc.body.querySelectorAll('h2, h3').forEach((h, i) => {
            const id = `section-${i}`;
            h.id = id;
            headings.push({
                id,
                text: h.textContent.trim(),
                cssClass:
                    h.tagName === 'H3'
                        ? 'arc-article__toc-link arc-article__toc-link--sub'
                        : 'arc-article__toc-link'
            });
        });

        return { segments: extractScribeSegments(doc.body, `${articleId}:`), headings };
    }

    handleTocClick(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.target;
        const target = this.template.querySelector(`.arc-article__content [id="${id}"]`);
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    get hasArticle() {
        return !this.loading && !!this.article;
    }

    /** Embed_URL__c that is https but NOT a Scribe link keeps its raw frame. */
    get legacyEmbedSrc() {
        const url = this.article && this.article.embedUrl;
        return url && url.startsWith('https://') && !parseScribeUrl(url) ? url : undefined;
    }

    get hasEmbed() {
        return this.segments.some((s) => s.isEmbed) || !!this.legacyEmbedSrc;
    }

    // Only worth showing for genuinely sectioned articles.
    get showToc() {
        return this.headings.length >= 2;
    }
}