/**
 * contextNav — the ONE surface-aware navigation seam for the Help Center and
 * Resource Center surfaces.
 *
 * The problem it exists to solve: ResourceCenterService's link bases are
 * site-absolute on every surface, so a core-app user clicking an article was
 * sent to *.my.site.com — out of Lightning Experience, losing the nav bar,
 * console tabs and record context (and hitting a login). This module decides,
 * per surface, whether a target is a site URL or a Lightning PageReference.
 *
 * Surface contract (mirrors ResourceCenterService.getLinkContext):
 *   site      → helpBase is the CURRENT site's root and homeBase /
 *               articleBase / resourceBase / eventsBase are that site's page
 *               URLs (Help_Surface__mdt, keyed by Network name) — so a user
 *               inside ARC stays inside ARC. Navigate by URL. A ctx that only
 *               carries helpBase (older shapes, host-synthesized literals)
 *               derives the pages from the root with the default names.
 *   internal  → every base is null; navigate with NavigationMixin.
 * "No base" already meant "handle it in-app" in this codebase (see
 * articleResources' CTA ladder) — that semantic is what the internal branch
 * hangs off, so nothing had to be re-taught.
 *
 * Deliberately free of anything Experience-Cloud-only: no
 * @salesforce/community/* import, so it loads on both surfaces. The href
 * builders are pure functions over an explicit ctx, holding no component
 * state — that is what lets the arc* family adopt this later without a
 * third clone of the same logic.
 *
 * Mirror: ResourceCenterService.INTERNAL_SURFACE /
 * NexSArticleEngagementController.resolveSurface() — change together.
 */
import { NavigationMixin } from 'lightning/navigation';
import getLinkContext from '@salesforce/apex/ResourceCenterService.getLinkContext';

export const INTERNAL = 'Internal';

/** Core-app tab API names — the ONE internal-URL contract in this codebase. */
const TABS = Object.freeze({
    home: 'Unified_Support_Home',
    article: 'Help_Center_Article',
    resources: 'Resource_Center',
    events: 'Help_Center_Events'
});

/** Lightning namespaces custom page-reference state; LWR does not. */
const C_PREFIX = 'c__';
/** Article route: name / article (legacy) / topic. Resources: rcview / rcslug /
    rcterm. Events: view ('upcoming' | 'calendar') / month ('YYYY-MM'). */
const PARAM_NAMES = ['name', 'article', 'topic', 'rcview', 'rcslug', 'rcterm', 'view', 'month'];

const INTERNAL_CTX = Object.freeze({ surface: INTERNAL, helpBase: null, resourceBase: null });

// ---- context -------------------------------------------------------------

let ctxPromise = null;

/**
 * Resolve {surface, helpBase, resourceBase} once per page and share it.
 *
 * Memoized on purpose: before this module the same base was wired up to three
 * times in a single Resource Center detail render (parent + resourceDetail +
 * the results view, each with its own @wire). One imperative call replaces them.
 *
 * Never rejects — an Apex failure degrades to the internal context, which is
 * the safe branch (navigate in-app rather than guess at a site URL).
 */
export function linkContext() {
    if (!ctxPromise) {
        ctxPromise = getLinkContext()
            .then((ctx) => ctx || INTERNAL_CTX)
            .catch(() => INTERNAL_CTX);
    }
    return ctxPromise;
}

/** Test seam — the memo is module-level, so suites must clear it. */
export function resetLinkContext() {
    ctxPromise = null;
}

/** True when there is no site base to navigate to, i.e. the core app. */
export function isInternal(ctx) {
    return !ctx || !ctx.helpBase;
}

// ---- inbound URL state ---------------------------------------------------

/** True when the page reference belongs to an Experience Cloud site. */
export function isSiteRef(pageRef) {
    return !!(pageRef && pageRef.type && pageRef.type.indexOf('comm__') === 0);
}

/**
 * Read the deep-link params these surfaces understand (PARAM_NAMES), from wherever the
 * current surface puts them: bare query params on the LWR site, c__-prefixed
 * page-reference state in Lightning.
 *
 * Both sources are consulted regardless of surface (a c__ key is accepted on
 * the site and a bare key in Lightning) so a hand-typed or copied URL still
 * resolves. Returns a plain object; missing params are undefined.
 *
 * Pass `null` to read the CURRENT URL only. Page-reference state wins over
 * the query string, and the CurrentPageReference wire does not re-emit after
 * a component's own history.pushState — so a host that writes the URL itself
 * must read it back with readParams(null), not with its cached page ref.
 */
export function readParams(pageRef) {
    const out = {};
    const state = (pageRef && pageRef.state) || {};

    PARAM_NAMES.forEach((key) => {
        const fromState = state[C_PREFIX + key] || state[key];
        if (fromState) {
            out[key] = fromState;
        }
    });

    try {
        const search = new URLSearchParams(window.location.search);
        PARAM_NAMES.forEach((key) => {
            if (out[key]) {
                return;
            }
            const fromUrl = search.get(key) || search.get(C_PREFIX + key);
            if (fromUrl) {
                out[key] = fromUrl;
            }
        });
    } catch (e) {
        // URL parsing is best-effort — page-reference state already applied.
    }

    return out;
}

// ---- href builders (synchronous, for templates) --------------------------

function trimEnd(base) {
    return base.replace(/\/$/, '');
}

/** The site page URL for `key`, or the default page under the site root. */
function pageBase(ctx, key, defaultPath) {
    return ctx[key] ? trimEnd(ctx[key]) : trimEnd(ctx.helpBase) + defaultPath;
}

function internalHref(tab, state) {
    const query = Object.keys(state)
        .filter((key) => state[key])
        .map((key) => C_PREFIX + key + '=' + encodeURIComponent(state[key]))
        .join('&');
    return '/lightning/n/' + tab + (query ? '?' + query : '');
}

/** Article deep link, or null when there is nothing to link to. */
export function articleHref(ctx, urlName) {
    if (!urlName) {
        return null;
    }
    return isInternal(ctx)
        ? internalHref(TABS.article, { name: urlName })
        : pageBase(ctx, 'articleBase', '/article') + '?name=' + encodeURIComponent(urlName);
}

/** Topic-browse deep link (no article named). */
export function topicHref(ctx, topicApiName) {
    if (!topicApiName) {
        return null;
    }
    return isInternal(ctx)
        ? internalHref(TABS.article, { topic: topicApiName })
        : pageBase(ctx, 'articleBase', '/article') + '?topic=' + encodeURIComponent(topicApiName);
}

/**
 * Resource Center deep link. `slug` is optional — omit it (with view 'home')
 * for the Resource Center front door, which is what the cross-app "Resources"
 * links want.
 */
export function resourceHref(ctx, slug, view) {
    const rcview = view || 'detail';

    if (isInternal(ctx)) {
        return internalHref(TABS.resources, slug ? { rcview, rcslug: slug } : {});
    }
    if (!ctx.resourceBase) {
        return null;
    }
    // The resource base is already the Resources PAGE url, so the query string
    // appends directly — unlike the help base, which is the site root.
    const base = trimEnd(ctx.resourceBase);
    if (!slug) {
        return base;
    }
    return base +
        '?rcview=' + encodeURIComponent(rcview) +
        '&rcslug=' + encodeURIComponent(slug);
}

/** Resource Center search results for a term. */
function resourceSearchHref(ctx, term) {
    if (isInternal(ctx)) {
        return internalHref(TABS.resources, { rcview: 'search', rcterm: term });
    }
    if (!ctx.resourceBase) {
        return null;
    }
    return trimEnd(ctx.resourceBase) + '?rcview=search&rcterm=' + encodeURIComponent(term);
}

export function eventsHref(ctx) {
    return isInternal(ctx)
        ? internalHref(TABS.events, {})
        : pageBase(ctx, 'eventsBase', '/events');
}

export function homeHref(ctx) {
    if (isInternal(ctx)) {
        return internalHref(TABS.home, {});
    }
    // A named home page is a page URL; the bare site root keeps its slash.
    return ctx.homeBase ? trimEnd(ctx.homeBase) : trimEnd(ctx.helpBase) + '/';
}

// ---- imperative navigation ----------------------------------------------

/**
 * The fallback ladder every goTo* runs, modelled on articleResources' CTA
 * precedence chain (the one real ladder in this codebase):
 *
 *   1. site      → window.location.assign(absolute)   — unchanged behavior
 *   2. internal, NavigationMixin present → PageReference navigation
 *   3. internal, no mixin → composed CustomEvent so an ancestor swaps in place
 *   4. last resort → the same-site relative URL, exactly as before
 *
 * Rung 3 is why the presentational components (resourceDetail,
 * resourceSearchResults, articleResources, helpGuide) need no mixin.
 */
function navigate(cmp, options) {
    const { absolute, tab, state, fallbackEvent, relative } = options;

    if (absolute) {
        window.location.assign(absolute);
        return;
    }

    if (cmp && typeof cmp[NavigationMixin.Navigate] === 'function') {
        try {
            const pageState = {};
            Object.keys(state || {}).forEach((key) => {
                if (state[key]) {
                    pageState[C_PREFIX + key] = state[key];
                }
            });
            cmp[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: tab },
                state: pageState
            });
            return;
        } catch (e) {
            // Fall through — an unavailable router is not a dead end.
        }
    }

    if (cmp && fallbackEvent) {
        cmp.dispatchEvent(
            new CustomEvent(fallbackEvent.name, {
                detail: fallbackEvent.detail,
                bubbles: true,
                composed: true
            })
        );
        return;
    }

    if (relative) {
        window.location.assign(relative);
    }
}

/** Open an article by UrlName, or open topic-browse when only topic is given. */
export function goToArticle(cmp, ctx, target) {
    const { urlName, topic } = target || {};
    const absolute = urlName ? articleHref(ctx, urlName) : topicHref(ctx, topic);
    navigate(cmp, {
        absolute: isInternal(ctx) ? null : absolute,
        tab: TABS.article,
        state: { name: urlName, topic },
        // Rung 3, symmetric with goToResource: a presentational component
        // with no mixin hands the article up to a host that has one.
        fallbackEvent: urlName ? { name: 'articleselect', detail: { urlName } } : null,
        relative: urlName
            ? './article?name=' + encodeURIComponent(urlName)
            : './article?topic=' + encodeURIComponent(topic || '')
    });
}

/**
 * Open a resource detail (default), a category, a search view, or — with no
 * slug and view 'home' — the Resource Center front door.
 */
export function goToResource(cmp, ctx, target) {
    const { slug, term } = target || {};
    const view = (target && target.view) || 'detail';

    let relativeQuery = '';
    if (term) {
        relativeQuery = '?rcview=search&rcterm=' + encodeURIComponent(term);
    } else if (slug) {
        relativeQuery = '?rcview=' + encodeURIComponent(view) +
            '&rcslug=' + encodeURIComponent(slug);
    }

    navigate(cmp, {
        absolute: isInternal(ctx)
            ? null
            : (term ? resourceSearchHref(ctx, term) : resourceHref(ctx, slug, view)),
        tab: TABS.resources,
        state: { rcview: term ? 'search' : (slug ? view : null), rcslug: slug, rcterm: term },
        fallbackEvent: slug
            ? {
                  name: view === 'category' ? 'categoryselect' : 'resourceselect',
                  detail: { slug }
              }
            : null,
        relative: './resources' + relativeQuery
    });
}

export function goToEvents(cmp, ctx) {
    navigate(cmp, {
        absolute: isInternal(ctx) ? null : eventsHref(ctx),
        tab: TABS.events,
        state: {},
        relative: './events'
    });
}

export function goToHome(cmp, ctx) {
    navigate(cmp, {
        absolute: isInternal(ctx) ? null : homeHref(ctx),
        tab: TABS.home,
        state: {},
        relative: './'
    });
}