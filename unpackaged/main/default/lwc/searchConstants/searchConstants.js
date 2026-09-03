/**
 * searchConstants
 *
 * Client-side mirror of classes/SearchConstants.cls — the one remaining
 * cross-language duplication of the shared search constants. Apex constants
 * are not reachable from LWC without a server round-trip, so the values are
 * mirrored here for client-side consumers (e.g. c/nexsHighlight, which must
 * skip exactly the words the engine never scored on). Change the two files
 * together.
 *
 * No template — shared service module (isExposed: false).
 */

/**
 * Common English + question words that carry no search signal. Lowercase.
 * Mirrors SearchConstants.STOPWORDS.
 */
export const STOPWORDS = new Set([
    'how', 'do', 'i', 'a', 'an', 'the', 'to', 'of', 'is', 'are', 'what',
    'why', 'when', 'where', 'which', 'who', 'and', 'or', 'in', 'on', 'for',
    'with', 'my', 'me', 'can', 'does', 'will', 'this', 'that', 'it', 'be',
    'at', 'as', 'by', 'if', 'from', 'into', 'about', 'your', 'you'
]);

/**
 * Query fragments shorter than this must match exactly (no prefix/fuzzy).
 * Mirrors SearchConstants.MIN_PREFIX_LEN.
 */
export const MIN_PREFIX_LEN = 3;

/**
 * Display-order sentinel that sorts after all real taxonomy entries.
 * Mirrors SearchConstants.ORDER_SENTINEL.
 */
export const ORDER_SENTINEL = 900;

/**
 * Minimum significant (alphanumeric) characters before a typeahead fires or a
 * zero-result term counts as a gap. Client-only — the server never sees
 * sub-threshold terms.
 */
export const MIN_SIGNIFICANT_CHARS = 2;

/** Count of significant (alphanumeric) characters in a raw term. */
export function significantLength(term) {
    return (term || '').replace(/[^a-z0-9]/gi, '').length;
}