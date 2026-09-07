import { LightningElement, api, track } from 'lwc';
import getArticle from '@salesforce/apex/NexSKnowledgeController.getArticle';
import logView from '@salesforce/apex/NexSArticleEngagementController.logView';
import {
    linkContext,
    isInternal,
    isSameSite,
    articleHref,
    topicHref,
    resourceHref,
    goToResource
} from 'c/contextNav';
import { extractScribeSegments, parseScribeUrl, titleFromSlug } from 'c/scribeUrlUtil';

// Active-content tags stripped by the sanitizer; standard formatting markup
// (headings, lists, tables, images, links) passes through untouched.
const BLOCKED_TAGS = 'script, style, iframe, object, embed, link, meta, form';

/**
 * Authored links INTO the Help Center / Resource Center. Authors paste the
 * page URL they see (`https://<sandbox>.my.site.com/help/resources?rcview=…`
 * or, on Arc, `…/learning?rcview=…`), which is host-absolute and
 * site-absolute — wrong on every other org and on the core-app article tab.
 * Rewritten at render time through c/contextNav, so the same body links
 * correctly on the site (client-side), in Lightning (tab URL) and after a
 * domain change. The current site's path is matched first; the retired
 * /help site's path is always matched too, because article bodies authored
 * before the move to Arc still carry it (2026-09-07).
 */
const LEGACY_SITE_PATHS = ['/help'];
const LINK_DATA_KIND = 'data-nexs-link';

function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Site paths an authored link may carry: the ctx's own site (`/help`, `/ARC`,
    or '' for a custom-domain root) first, then the legacy ones. */
function sitePathsOf(ctx) {
    const paths = [];
    if (ctx && ctx.helpBase) {
        try {
            paths.push(new URL(ctx.helpBase).pathname.replace(/\/$/, ''));
        } catch (e) {
            // fall through
        }
    }
    LEGACY_SITE_PATHS.forEach((p) => {
        if (!paths.includes(p)) {
            paths.push(p);
        }
    });
    return paths;
}

/**
 * Parse an authored href into {kind, params} when it targets a Help & Resources
 * page on one of the site paths — `resources` / `learning` (the Resource
 * Center page's two names) or `article` — with or without a host; null otherwise.
 */
function parseSiteLink(href, sitePaths) {
    if (!href) {
        return null;
    }
    const target = href.trim();
    for (const sitePath of sitePaths) {
        const re = new RegExp(
            `^(?:https?://[^/]+)?${escapeRegExp(sitePath)}/(resources|learning|article)/?(?:\\?([^#]*))?(?:#.*)?$`,
            'i'
        );
        const m = target.match(re);
        if (m) {
            // Authored HTML carries `&amp;`; DOMParser has already decoded it here.
            const params = new URLSearchParams(m[2] || '');
            const kind = m[1].toLowerCase();
            return { kind: kind === 'learning' ? 'resources' : kind, params };
        }
    }
    return null;
}

/**
 * nexsArticleViewer
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
 *
 * Events:
 *   articleload  { title, urlName, suggestions, hasEmbed }  — fired once the
 *     article resolves; title feeds the breadcrumb, suggestions (server-built:
 *     authored picks + same-topic top-up) feed the host's "Suggested Articles"
 *     rail, hasEmbed lets the host go full width
 */
export default class NexsArticleViewer extends LightningElement {
    @track article;
    @track error;
    @track headings = [];
    @track segments = [];
    loading = false;
    _articleId;
    _segHtml = new Map();
    _renderedArticleId;
    // Stale-response guard. A reader who searches again and clicks a second
    // result swaps articleId while the first getArticle is still in flight, and
    // whichever resolved last used to win — putting them back on the previous
    // result, and (via articleload) pushing its ?name= back into the URL.
    _loadSeq = 0;
    // Articles already counted by this instance — one view per article per
    // mount, so unrelated re-renders don't inflate Article_View__c counts.
    _loggedViews = new Set();

    @api
    get articleId() {
        return this._articleId;
    }
    set articleId(value) {
        this._articleId = value;
        this._loadSeq += 1; // any in-flight load is now stale
        if (value) {
            this.load(this._loadSeq);
        } else {
            this.article = undefined;
            this.error = undefined;
            this.headings = [];
            this.segments = [];
            this._segHtml = new Map();
            this._renderedArticleId = undefined;
        }
    }

    /** {surface, helpBase, resourceBase} from c/contextNav; resolved before the
        first body render so authored site links can be rewritten. */
    _linkCtx = null;

    async load(seq = ++this._loadSeq) {
        this.loading = true;
        this.error = undefined;
        this._renderedArticleId = undefined;
        try {
            const [detail, ctx] = await Promise.all([
                getArticle({ articleId: this._articleId }),
                linkContext() // memoized, never rejects
            ]);
            if (seq !== this._loadSeq) {
                return; // a newer article was requested while this was in flight
            }
            this._linkCtx = ctx;
            const { segments, headings } = this.sanitizeAndIndex(detail.body, ctx, detail.id);
            this.appendLegacyEmbed(segments, detail);
            this._segHtml = new Map(segments.filter((s) => s.isHtml).map((s) => [s.key, s.html]));
            this.segments = segments;
            this.headings = headings;
            this.article = detail;
            this.dispatchEvent(
                new CustomEvent('articleload', {
                    detail: {
                        title: detail.title,
                        // UrlName lets a routed host (helpArticlePage) keep the
                        // ?name= URL param honest on every in-browser navigation.
                        urlName: detail.urlName,
                        suggestions: detail.suggestions || [],
                        // Lets the host drop the Suggested rail and go full width
                        // for guide articles — see nexsArticleBrowser.
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
            if (seq !== this._loadSeq) {
                return; // a stale failure must not blank the article now on screen
            }
            this.article = undefined;
            this.headings = [];
            this.segments = [];
            this._segHtml = new Map();
            this.error = e?.body?.message || 'Unable to load this article.';
        } finally {
            if (seq === this._loadSeq) {
                this.loading = false;
            }
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
     * Rewrite authored links into the Help Center site (resources / article
     * pages, with or without a host) through c/contextNav's href builders, and
     * tag them so handleBodyClick can route plain clicks in place.
     */
    rewriteSiteLinks(doc, ctx) {
        const sitePaths = sitePathsOf(ctx);
        doc.body.querySelectorAll('a[href]').forEach((a) => {
            const link = parseSiteLink(a.getAttribute('href'), sitePaths);
            if (!link) {
                return;
            }
            const p = link.params;
            let href = null;
            if (link.kind === 'resources') {
                const slug = p.get('rcslug');
                const view = p.get('rcview') || 'detail';
                if (!slug || view === 'search') {
                    return; // term-only / bare front door: leave as authored
                }
                href = resourceHref(ctx, slug, view);
                if (href) {
                    a.setAttribute(LINK_DATA_KIND, 'resource');
                    a.setAttribute('data-nexs-slug', slug);
                    a.setAttribute('data-nexs-view', view);
                }
            } else {
                const name = p.get('name') || p.get('article');
                const topic = p.get('topic');
                href = name ? articleHref(ctx, name) : topicHref(ctx, topic);
                if (href && name) {
                    a.setAttribute(LINK_DATA_KIND, 'article');
                    a.setAttribute('data-nexs-name', name);
                }
            }
            if (href) {
                a.setAttribute('href', href);
                a.removeAttribute('target'); // same site or same app — never a new tab
            }
        });
    }

    /**
     * Plain clicks on rewritten links route in place: a resource link goes
     * through contextNav (no mixin here → `resourceselect` bubbles to the
     * routed host, helpArticlePage); an article link asks the browser to open
     * it inline (`articlelink`, handled by nexsArticleBrowser). Only on the
     * site being viewed — in the core app the rewritten Lightning tab URL
     * navigates natively. Middle/modifier clicks keep the anchor. Bound
     * declaratively on the segments wrapper: clicks from the manual DOM
     * bubble up to it inside the shadow.
     */
    handleBodyClick(event) {
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        const anchor = path.find((n) => n && n.getAttribute && n.hasAttribute && n.hasAttribute(LINK_DATA_KIND));
        if (!anchor) {
            return;
        }
        const isPlainClick =
            event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
        if (!isPlainClick || isInternal(this._linkCtx) || !isSameSite(this._linkCtx)) {
            return;
        }
        event.preventDefault();
        if (anchor.getAttribute(LINK_DATA_KIND) === 'resource') {
            goToResource(this, this._linkCtx, {
                slug: anchor.getAttribute('data-nexs-slug'),
                view: anchor.getAttribute('data-nexs-view') || 'detail'
            });
            return;
        }
        this.dispatchEvent(
            new CustomEvent('articlelink', {
                detail: { urlName: anchor.getAttribute('data-nexs-name') },
                bubbles: true,
                composed: true
            })
        );
    }

    /**
     * DOMParser-based sanitize: drop active-content elements, strip on*
     * handlers and javascript: URLs, tag h2/h3 with generated ids so the
     * anchor nav can scroll to them, then split the body into html / Scribe
     * embed segments keyed by article id.
     */
    sanitizeAndIndex(html, ctx = this._linkCtx, articleId = this._articleId) {
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

        this.rewriteSiteLinks(doc, ctx);

        const headings = [];
        doc.body.querySelectorAll('h2, h3').forEach((h, i) => {
            const id = `section-${i}`;
            h.id = id;
            headings.push({
                id,
                text: h.textContent.trim(),
                cssClass:
                    h.tagName === 'H3'
                        ? 'nexs-article__toc-link nexs-article__toc-link--sub'
                        : 'nexs-article__toc-link'
            });
        });

        return { segments: extractScribeSegments(doc.body, `${articleId}:`), headings };
    }

    handleTocClick(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.target;
        const target = this.template.querySelector(`.nexs-article__content [id="${id}"]`);
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