/**
 * rcLinkUtil — shared helpers for shareable Resource Center links.
 *
 * The canonical resource URL is the Resources page on the Help Center LWR site
 * plus the RC shell's query-param routing (resourceCenter.js reads rcview/rcslug
 * from the page state). The base comes from
 * ResourceCenterService.getResourceLinkBase(), e.g. https://…/help/resources.
 */

/** Absolute URL of a resource's detail view, or null when base/slug is missing. */
export function resourceDetailUrl(base, slug) {
    if (!base || !slug) {
        return null;
    }
    return `${base.replace(/\/$/, '')}?rcview=detail&rcslug=${encodeURIComponent(slug)}`;
}

/**
 * Absolute URL of a Help Center article, or null when base/urlName is missing.
 * Canonical since the /article route shipped (2026-08 unification):
 * <siteRoot>/article?name=<UrlName>. The legacy <siteRoot>/?article= form
 * still resolves via the home-route shim — never build it for new links.
 * `base` is the SITE root (ResourceCenterService.getHelpCenterLinkBase()).
 */
export function articleUrl(base, urlName) {
    if (!base || !urlName) {
        return null;
    }
    return `${base.replace(/\/$/, '')}/article?name=${encodeURIComponent(urlName)}`;
}

/**
 * Copy text to the clipboard. Resolves on success, rejects on failure.
 * navigator.clipboard needs a secure context + user activation; the hidden
 * textarea + execCommand path covers environments where it's unavailable.
 */
export function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(text).catch(() => copyViaTextarea(text));
    }
    return copyViaTextarea(text);
}

function copyViaTextarea(text) {
    return new Promise((resolve, reject) => {
        const el = document.createElement('textarea');
        el.value = text;
        el.setAttribute('readonly', '');
        el.style.position = 'fixed';
        el.style.opacity = '0';
        document.body.appendChild(el);
        el.select();
        let ok = false;
        try {
            ok = document.execCommand('copy');
        } catch (e) {
            ok = false;
        }
        document.body.removeChild(el);
        if (ok) {
            resolve();
        } else {
            reject(new Error('copy-failed'));
        }
    });
}