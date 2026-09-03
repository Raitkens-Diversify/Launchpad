/**
 * nexsHighlight
 *
 * Split article-derived text into segments for match highlighting. Returns
 * [{ text, match, key }] which the template renders with matched segments in
 * <strong>. Because every segment is bound as text ({seg.text}), LWC escapes it
 * — there is no innerHTML and no way to inject markup through an article title.
 *
 * Highlighting mirrors what the engine actually scored on: stopwords are not
 * highlighted, and a term only highlights where it begins a word (word-prefix),
 * never mid-word — so "to" never bolds inside "Stop".
 */

// Shared stoplist: c/searchConstants is the client-side mirror of the Apex
// SearchConstants class, so highlighting skips exactly the words the search
// engine never scored on.
import { STOPWORDS } from 'c/searchConstants';

// A match counts only at a word start: string start, or preceded by a non-
// alphanumeric character.
function isWordStart(lower, pos) {
    return pos === 0 || !/[a-z0-9]/.test(lower[pos - 1]);
}

export function highlightSegments(text, query) {
    const src = text == null ? '' : String(text);
    const terms = (query || '')
        .toLowerCase()
        .split(/[^a-z0-9]+/)
        .filter((t) => t.length >= 2 && !STOPWORDS.has(t));

    if (!terms.length || !src) {
        return [{ text: src, match: false, key: 0 }];
    }

    const lower = src.toLowerCase();
    const segments = [];
    let i = 0;
    let key = 0;

    while (i < src.length) {
        // Earliest word-start match at/after i, preferring the longest term on a tie.
        let bestPos = -1;
        let bestLen = 0;
        for (const t of terms) {
            let pos = lower.indexOf(t, i);
            while (pos !== -1 && !isWordStart(lower, pos)) {
                pos = lower.indexOf(t, pos + 1);
            }
            if (pos !== -1 && (bestPos === -1 || pos < bestPos || (pos === bestPos && t.length > bestLen))) {
                bestPos = pos;
                bestLen = t.length;
            }
        }
        if (bestPos === -1) {
            segments.push({ text: src.slice(i), match: false, key: key++ });
            break;
        }
        if (bestPos > i) {
            segments.push({ text: src.slice(i, bestPos), match: false, key: key++ });
        }
        segments.push({ text: src.slice(bestPos, bestPos + bestLen), match: true, key: key++ });
        i = bestPos + bestLen;
    }
    return segments;
}