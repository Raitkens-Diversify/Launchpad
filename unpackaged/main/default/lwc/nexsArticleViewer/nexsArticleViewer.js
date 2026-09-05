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

// Active-content tags stripped by the sanitizer; standard formatting markup
// (headings, lists, tables, images, links) passes through untouched.
const BLOCKED_TAGS = 'script, style, iframe, object, embed, link, meta, form';

/**
 * Authored links INTO the Help Center / Resource Center. Authors paste the
 * page URL they see (`https://<sandbox>.my.site.com/help/resources?rcview=…`),
 * which is host-absolute and site-absolute — wrong on every other org and on
 * the core-app article tab. Rewritten at render time through c/contextNav, so
 * the same body links correctly on the site (client-side), in Lightning
 * (tab URL) and after a domain change. Default site path when no site
 * context is available (the core app) — the shared Help Center's prefix.
 */
const DEFAULT_SITE_PATH = '/help';
const LINK_DATA_KIND = 'data-nexs-link';

function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Site path the ctx describes (`/help`), falling back to the shared one. */
function sitePathOf(ctx) {
    if (ctx && ctx.helpBase) {
        try {
            const path = new URL(ctx.helpBase).pathname.replace(/\/$/, '');
            if (path) {
                return path;
            }
        } catch (e) {
            // fall through
        }
    }
    return DEFAULT_SITE_PATH;
}

/**
 * Parse an authored href into {kind, params} when it targets the Help Center
 * site's resources or article page (with or without a host); null otherwise.
 */
function parseSiteLink(href, sitePath) {
    if (!href) {
        return null;
    }
    const re = new RegExp(
        `^(?:https?://[^/]+)?${escapeRegExp(sitePath)}/(resources|article)/?(?:\\?([^#]*))?(?:#.*)?$`,
        'i'
    );
    const m = href.trim().match(re);
    if (!m) {
        return null;
    }
    // Authored HTML carries `&amp;`; DOMParser has already decoded it here.
    const params = new URLSearchParams(m[2] || '');
    return { kind: m[1].toLowerCase(), params };
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
 * The body is sanitized here (DOMParser pass) and injected into a
 * lwc:dom="manual" div instead of lightning-formatted-rich-text: under native
 * shadow DOM (LWR) that component's shadow root is unreachable, which blocks
 * both per-element body typography and the "In this article" anchor scrolling.
 *
 * Events:
 *   articleload  { title, suggestions }  — fired once the article resolves;
 *     title feeds the breadcrumb, suggestions (server-built: authored picks +
 *     same-topic top-up) feed the host's "Suggested Articles" rail
 */
export default class NexsArticleViewer extends LightningElement {
    @track article;
    @track error;
    @track headings = [];
    loading = false;
    _articleId;
    _bodyHtml = '';
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
            this._bodyHtml = '';
            this._renderedArticleId = undefined;
        }
    }

    /** {surface, helpBase, resourceBase} from c/contextNav; resolved before the
        first body render so authored site links can be rewritten. */
    _linkCtx = null;
    _bodyClickBound = false;

    async load() {
        this.loading = true;
        this.error = undefined;
        this._renderedArticleId = undefined;
        try {
            const [detail, ctx] = await Promise.all([
                getArticle({ articleId: this._articleId }),
                linkContext() // memoized, never rejects
            ]);
            this._linkCtx = ctx;
            const { html, headings } = this.sanitizeAndIndex(detail.body, ctx);
            this._bodyHtml = html;
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
                        // for embed articles (Scribe etc.) — see nexsArticleBrowser.
                        hasEmbed: !!this.embedSrc
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
            this._bodyHtml = '';
            this.error = e?.body?.message || 'Unable to load this article.';
        } finally {
            this.loading = false;
        }
    }

    // Inject the sanitized body once per article; the guard keeps unrelated
    // re-renders from resetting the manual DOM (and the user's scroll position).
    renderedCallback() {
        if (!this.article || this._renderedArticleId === this.article.id) {
            return;
        }
        const container = this.template.querySelector('.nexs-article__body');
        if (!container) {
            return;
        }
        container.innerHTML = this._bodyHtml;
        this._renderedArticleId = this.article.id;
        if (!this._bodyClickBound) {
            // Delegated: the body is manual DOM, re-injected per article.
            container.addEventListener('click', (event) => this.handleBodyClick(event));
            this._bodyClickBound = true;
        }
    }

    /**
     * Rewrite authored links into the Help Center site (resources / article
     * pages, with or without a host) through c/contextNav's href builders, and
     * tag them so handleBodyClick can route plain clicks in place.
     */
    rewriteSiteLinks(doc, ctx) {
        const sitePath = sitePathOf(ctx);
        doc.body.querySelectorAll('a[href]').forEach((a) => {
            const link = parseSiteLink(a.getAttribute('href'), sitePath);
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
     * navigates natively. Middle/modifier clicks keep the anchor.
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
     * handlers and javascript: URLs, and tag h2/h3 with generated ids so the
     * anchor nav can scroll to them.
     */
    sanitizeAndIndex(html, ctx = this._linkCtx) {
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

        return { html: doc.body.innerHTML, headings };
    }

    handleTocClick(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.target;
        const target = this.template.querySelector(`.nexs-article__body [id="${id}"]`);
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    get hasArticle() {
        return !this.loading && !!this.article;
    }

    // Embed frames render only for https URLs (Embed_URL__c is author-entered).
    get embedSrc() {
        const url = this.article && this.article.embedUrl;
        return url && url.startsWith('https://') ? url : undefined;
    }

    // Only worth showing for genuinely sectioned articles.
    get showToc() {
        return this.headings.length >= 2;
    }
}