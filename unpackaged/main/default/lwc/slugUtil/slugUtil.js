/**
 * slugUtil — shared slug/UrlName generator for the Admin Console.
 * "My Great  Resume!" → "my-great-resume". Used for Knowledge UrlName
 * auto-suggest (articles) and Resource__c.Slug__c auto-suggest (resources).
 */
const DEFAULT_MAX = 80;
const COMBINING_MARKS = new RegExp('[\\u0300-\\u036f]', 'g');

export function slugify(text, maxLength = DEFAULT_MAX) {
    if (!text) {
        return '';
    }
    return String(text)
        .toLowerCase()
        .normalize('NFKD')
        .replace(COMBINING_MARKS, '') // strip diacritics left by NFKD
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, maxLength)
        .replace(/-+$/, '');
}