/**
 * scribeUrlUtil — the ONE place that understands Scribe (scribehow.com) URLs.
 *
 * Pure and dependency-free (no LWC imports) so the article viewers, the
 * Resource Center detail view and c/scribeEmbed all share it and Jest can
 * drive it directly.
 *
 * URL shapes Scribe hands out (verified 2026-09-05, docs/scribe-embeds.md):
 *   https://scribehow.com/shared/<Slug>__<id>     — what "Share → Copy link" copies
 *   https://scribehow.com/viewer/<Slug>__<id>     — the canonical viewer page
 *   https://scribehow.com/embed/<Slug>__<id>?…    — what "Share → Embed" pastes
 * The id is the token after the LAST `__` (the slug itself may end in `_`).
 * Query params Scribe documents: `as=scrollable|video` (default: slides),
 * `removeLogo=true`, `skipIntro=true`. Anything else is dropped.
 *
 * Only scribehow.com origins are ever framed — everything else stays a link.
 */
export const SCRIBE_HOSTS = ['scribehow.com', 'www.scribehow.com'];
const PATH_KINDS = ['shared', 'viewer', 'embed'];
const MODES = ['scrollable', 'video'];
export const DEFAULT_MODE = 'slides';
const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const EMBED_BASE = 'https://scribehow.com/embed/';
const SHARE_BASE = 'https://scribehow.com/shared/';

/**
 * Parse any Scribe link into its parts, or null when it is not a Scribe link
 * we are willing to frame (wrong host, not https, no recognisable id).
 *
 * @returns {{segment:string, slug:string, id:string, mode:string,
 *            removeLogo:boolean, skipIntro:boolean} | null}
 */
export function parseScribeUrl(url) {
    if (typeof url !== 'string') {
        return null;
    }
    const trimmed = url.trim();
    if (!trimmed) {
        return null;
    }
    let parsed;
    try {
        parsed = new URL(trimmed);
    } catch (e) {
        return null;
    }
    if (parsed.protocol !== 'https:') {
        return null;
    }
    if (!SCRIBE_HOSTS.includes(parsed.hostname.toLowerCase())) {
        return null;
    }
    const parts = parsed.pathname.split('/').filter(Boolean);
    if (parts.length < 2) {
        return null;
    }
    const segment = parts[parts.length - 1];
    const kind = parts[parts.length - 2].toLowerCase();
    if (!PATH_KINDS.includes(kind)) {
        return null;
    }
    const cut = segment.lastIndexOf('__');
    if (cut <= 0) {
        return null;
    }
    const id = segment.slice(cut + 2);
    const slug = segment.slice(0, cut);
    if (!ID_RE.test(id)) {
        return null;
    }
    const params = parsed.searchParams;
    const as = (params.get('as') || '').toLowerCase();
    return {
        segment,
        slug,
        id,
        mode: MODES.includes(as) ? as : DEFAULT_MODE,
        removeLogo: params.get('removeLogo') === 'true',
        skipIntro: params.get('skipIntro') === 'true'
    };
}

/** True when `url` is a Scribe link this module will frame. */
export function isScribeUrl(url) {
    return parseScribeUrl(url) !== null;
}

/**
 * Human title recovered from the slug: `Creating_A_Folder_Template` →
 * "Creating A Folder Template". Scribe already title-cases its slugs, so no
 * re-casing here.
 */
export function titleFromSlug(slug) {
    if (typeof slug !== 'string') {
        return '';
    }
    let text = slug;
    try {
        text = decodeURIComponent(slug);
    } catch (e) {
        // keep the raw slug
    }
    return text.replace(/_+/g, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * The chrome-less frame URL. `removeLogo` defaults to true — the surrounding
 * card already carries the guide's title and the Scribe glyph — and an
 * explicit option always wins over what the author pasted.
 */
export function toEmbedUrl(parsed, options = {}) {
    if (!parsed || !parsed.segment) {
        return null;
    }
    const mode = options.mode || parsed.mode || DEFAULT_MODE;
    const removeLogo = options.removeLogo === undefined ? true : Boolean(options.removeLogo);
    const skipIntro = options.skipIntro === undefined ? Boolean(parsed.skipIntro) : Boolean(options.skipIntro);
    const query = new URLSearchParams();
    if (MODES.includes(mode)) {
        query.set('as', mode);
    }
    if (removeLogo) {
        query.set('removeLogo', 'true');
    }
    if (skipIntro) {
        query.set('skipIntro', 'true');
    }
    const qs = query.toString();
    return `${EMBED_BASE}${parsed.segment}${qs ? `?${qs}` : ''}`;
}

/** The public share page (Scribe redirects it to the full viewer). */
export function toShareUrl(parsed) {
    if (!parsed || !parsed.segment) {
        return null;
    }
    return `${SHARE_BASE}${parsed.segment}`;
}

// ---- Body segmentation --------------------------------------------------------

const BLOCK_TAGS = ['P', 'DIV', 'A'];
const WRAPPER_TAGS = ['STRONG', 'EM', 'SPAN', 'B', 'I', 'U'];
const MEDIA_SELECTOR = 'img, video, table, hr, ul, ol';

function cleanText(node) {
    return (node.textContent || '').replace(/ /g, ' ').trim();
}

function looksLikeUrl(text) {
    return /^https?:\/\//i.test(text);
}

/** The single `<a>` a block wraps (through one strong/em/span level), or null. */
function soleAnchor(el) {
    const kids = [...el.children].filter((c) => c.tagName !== 'BR');
    if (kids.length !== 1) {
        return null;
    }
    let candidate = kids[0];
    if (WRAPPER_TAGS.includes(candidate.tagName)) {
        const inner = [...candidate.children].filter((c) => c.tagName !== 'BR');
        if (inner.length !== 1) {
            return null;
        }
        candidate = inner[0];
    }
    return candidate.tagName === 'A' && candidate.hasAttribute('href') ? candidate : null;
}

/**
 * Decide whether a top-level node is "a Scribe link on its own line":
 *  (a) its whole text is one Scribe URL (bare paste), or
 *  (b) its only content is one <a href=scribe…>; a label that is not itself a
 *      URL becomes the embed's title.
 * A Scribe link inside a sentence is an intentional reference and stays a link.
 */
function scribeBlock(node) {
    if (node.nodeType === 3) {
        const text = cleanText(node);
        return text && !/\s/.test(text) && parseScribeUrl(text) ? { url: text, title: undefined } : null;
    }
    if (node.nodeType !== 1 || !BLOCK_TAGS.includes(node.tagName)) {
        return null;
    }
    if (node.querySelector(MEDIA_SELECTOR)) {
        return null;
    }
    const text = cleanText(node);
    if (!text) {
        return null;
    }
    const anchor = node.tagName === 'A' ? node : soleAnchor(node);
    if (anchor) {
        const href = (anchor.getAttribute('href') || '').trim();
        if (!parseScribeUrl(href)) {
            return null;
        }
        const label = cleanText(anchor);
        if (text !== label) {
            return null; // other words around the link → a reference, not an embed
        }
        const title = label && !looksLikeUrl(label) ? label : undefined;
        return { url: href, title };
    }
    if (/\s/.test(text) || !parseScribeUrl(text)) {
        return null;
    }
    return { url: text, title: undefined };
}

/**
 * Split an already-sanitised body into ordered render segments:
 *   { key, kind: 'html',  isHtml: true,  html }
 *   { key, kind: 'embed', isEmbed: true, url, title }
 * Runs on a DOMParser body (or any element); the caller owns sanitising.
 * Whitespace-only html runs are dropped so stacked embeds sit flush.
 */
export function extractScribeSegments(bodyEl, keyPrefix = '') {
    const segments = [];
    if (!bodyEl || !bodyEl.ownerDocument) {
        return segments;
    }
    const doc = bodyEl.ownerDocument;
    let buffer = doc.createElement('div');

    const flush = () => {
        const hasText = cleanText(buffer) !== '';
        const hasMedia = buffer.querySelector(MEDIA_SELECTOR) !== null;
        if (hasText || hasMedia) {
            segments.push({
                key: `${keyPrefix}${segments.length}`,
                kind: 'html',
                isHtml: true,
                isEmbed: false,
                html: buffer.innerHTML
            });
        }
        buffer = doc.createElement('div');
    };

    [...bodyEl.childNodes].forEach((node) => {
        const embed = scribeBlock(node);
        if (embed) {
            flush();
            segments.push({
                key: `${keyPrefix}${segments.length}`,
                kind: 'embed',
                isHtml: false,
                isEmbed: true,
                url: embed.url,
                title: embed.title
            });
            return;
        }
        buffer.appendChild(node.cloneNode(true));
    });
    flush();
    return segments;
}