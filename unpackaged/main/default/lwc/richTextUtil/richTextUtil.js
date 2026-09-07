/**
 * richTextUtil — the ONE client-side pass over stored rich text before it is
 * injected as manual DOM (`lwc:dom="manual"` + innerHTML, the idiom that lets
 * a component's own stylesheet reach the markup under native shadow DOM on
 * LWR, where lightning-formatted-rich-text's shadow is unreachable).
 *
 * The platform already sanitizes a rich text area on save; this is the
 * belt to that suspenders for the two consumers that render
 * `Resource__c.Description__c` (eventDetail, resourceDetail). Article bodies
 * keep nexsArticleViewer's own segmenting sanitizer — it also rewrites links
 * and lifts Scribe embeds, which is more than "sanitize".
 */

const ACTIVE_CONTENT = 'script, style, iframe, object, embed, form, input, textarea, button, link, meta';

/** Drop scripts, frames, forms and on* handlers; keep the authored markup. */
export function sanitizeHtml(html) {
    if (!html) {
        return '';
    }
    if (typeof DOMParser === 'undefined') {
        return html;
    }
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.querySelectorAll(ACTIVE_CONTENT).forEach((node) => node.remove());
    doc.body.querySelectorAll('*').forEach((node) => {
        [...node.attributes].forEach((attr) => {
            const name = attr.name.toLowerCase();
            const value = (attr.value || '').trim().toLowerCase();
            const urlAttr = name === 'href' || name === 'src' || name === 'xlink:href';
            if (name.startsWith('on') || (urlAttr && value.startsWith('javascript:'))) {
                node.removeAttribute(attr.name);
            }
        });
    });
    return doc.body.innerHTML;
}