import logSearchApex from '@salesforce/apex/NexSArticleEngagementController.logSearch';
import logClickApex from '@salesforce/apex/NexSArticleEngagementController.logClick';
import { getSessionKey } from 'c/nexsSession';
import { significantLength, MIN_SIGNIFICANT_CHARS } from 'c/searchConstants';

/**
 * searchLogUtil — the ONE client path into Article_Search__c analytics.
 *
 * Replaces the per-component logging that had drifted into two dedup
 * strategies (resourceSearchResults' consecutive-term guard vs nexsSearchBar's
 * per-session zero-log set). The unified strategy, for every consumer:
 *   - Full-search rows dedupe CONSECUTIVE identical terms (a cacheable @wire
 *     can re-emit the same term; a genuine re-search of an earlier term after
 *     searching something else still logs).
 *   - Zero-suggestion typeahead rows log once per term per logger instance,
 *     after an idle pause so mid-word keystrokes never log partial terms.
 *     Abandoning the box lets the pending log fire — abandonment IS the gap
 *     signal. A full search of the term cancels it (the full row supersedes).
 *
 * Every write is fire-and-forget: failures are swallowed here so analytics can
 * never surface to, or slow down, the search itself. JSON-string transport
 * (org gotcha: custom-type @AuraEnabled params arrive null).
 */

// Article_Search__c.App__c values (restricted picklist — mirror the field).
export const APP_HELP_CENTER = 'Help Center';
export const APP_RESOURCE_CENTER = 'Resource Center';
export const APP_LANDING = 'Landing';

// Idle pause after a zero-suggestion typeahead before it's logged as a gap.
export const ZERO_LOG_IDLE_MS = 1200;

/** One raw Article_Search__c row. Returns the row Id (for click correlation) or null. */
export function logSearchEntry({ term, resultCount, topResultArticleId, searchType, app }) {
    return logSearchApex({
        entryJson: JSON.stringify({
            term,
            resultCount,
            topResultArticleId: topResultArticleId || null,
            searchType,
            sessionKey: getSessionKey(),
            app
        })
    }).catch(() => null);
}

/** Correlate a result click back to its search row. */
export function logResultClick(searchLogId, clickedArticleId, rank) {
    if (!searchLogId) {
        return Promise.resolve(null);
    }
    return logClickApex({ searchLogId, clickedArticleId, rank }).catch(() => null);
}

/**
 * Per-host logger. Create one per component instance (its zero-log dedup set
 * and timers are instance-scoped, like the components' were) and call
 * `dispose()` from disconnectedCallback to drop any pending idle timer.
 */
export function createSearchLogger(app) {
    let lastFullTerm = null;
    let lastFullLogId = null;
    let zeroTimer = null;
    const zeroLogged = new Set();

    return {
        /**
         * Log a submitted full search. Dedupes consecutive identical terms —
         * a deduped repeat resolves to the ORIGINAL row's Id (not null) so a
         * click after a re-submitted search still correlates to its row.
         * Resolves to the row Id (also retained for logClickOnLastFull).
         * `searchType` is optional: pass 'Fuzzy' when the engine's typo pass
         * produced the results, 'Fallback' when the zero-result fallback view
         * was shown; defaults to 'Full'.
         */
        logFull({ term, resultCount, topResultArticleId, searchType }) {
            const clean = (term || '').trim();
            if (!clean) {
                return Promise.resolve(null);
            }
            if (clean === lastFullTerm) {
                return Promise.resolve(lastFullLogId);
            }
            lastFullTerm = clean;
            this.cancelZeroLog(); // the full row supersedes a pending gap log
            return logSearchEntry({
                term: clean,
                resultCount: resultCount < 0 ? 0 : resultCount,
                topResultArticleId,
                searchType: searchType || 'Full',
                app
            }).then((logId) => {
                lastFullLogId = logId;
                return logId;
            });
        },

        /** Annotate the most recent full-search row with the clicked result. */
        logClickOnLastFull(clickedArticleId, rank) {
            return logResultClick(lastFullLogId, clickedArticleId, rank);
        },

        /** Typeahead conversion: the search row plus the click that followed. */
        logTypeaheadConversion({ term, suggestions, clickedArticleId, rank }) {
            const list = suggestions || [];
            return logSearchEntry({
                term,
                resultCount: list.length,
                topResultArticleId: list.length ? list[0].id : null,
                searchType: 'Typeahead',
                app
            }).then((logId) => logResultClick(logId, clickedArticleId, rank));
        },

        /**
         * A typeahead settled: schedule a gap log when it came back empty,
         * clear any pending one otherwise (or when the user is still typing —
         * call this on every settle and every new keystroke's fetch).
         */
        settleTypeahead({ term, count }) {
            window.clearTimeout(zeroTimer);
            if (count > 0) {
                return;
            }
            zeroTimer = window.setTimeout(() => {
                const key = (term || '').trim().toLowerCase();
                if (!key || significantLength(term) < MIN_SIGNIFICANT_CHARS || zeroLogged.has(key)) {
                    return;
                }
                zeroLogged.add(key);
                logSearchEntry({
                    term,
                    resultCount: 0,
                    topResultArticleId: null,
                    searchType: 'Typeahead',
                    app
                });
            }, ZERO_LOG_IDLE_MS);
        },

        /** Drop a pending gap log (e.g. a full search of the term is taking over). */
        cancelZeroLog() {
            window.clearTimeout(zeroTimer);
            zeroTimer = null;
        },

        dispose() {
            this.cancelZeroLog();
        }
    };
}