/**
 * SearchConstants
 *
 * Single Apex source for the search-tuning constants that were previously
 * triplicated across NexSKnowledgeController, ResourceCenterService, and the
 * client. Both search engines (Help Center knowledge search and the Resource
 * Center) must treat these identically, so they live here once.
 *
 *  - STOPWORDS: common English + question words that carry no search signal.
 *    Kept small and obvious — the goal is to stop "how"/"do"/"the" from
 *    matching the whole knowledge base, not to build a full linguistic
 *    stoplist.
 *  - MIN_PREFIX_LEN: query fragments shorter than this must match exactly
 *    (no prefix/fuzzy matching).
 *  - ORDER_SENTINEL: "sorts after all real taxonomy" display-order value for
 *    trailing/fallback sections (e.g. the Resource Center's General section
 *    and the Help Center browser's fallback groups).
 *
 * Cross-language mirror: lwc/searchConstants mirrors STOPWORDS and these
 * values for client-side consumers (highlighting must skip exactly the words
 * the engine never scored on). Apex constants are not reachable from LWC
 * without a server round-trip, so that one JS mirror remains — change the
 * two files together.
 */
public with sharing class SearchConstants {

    /** Words dropped from queries before matching/scoring. Lowercase. */
    public static final Set<String> STOPWORDS = new Set<String>{
        'how', 'do', 'i', 'a', 'an', 'the', 'to', 'of', 'is', 'are', 'what',
        'why', 'when', 'where', 'which', 'who', 'and', 'or', 'in', 'on', 'for',
        'with', 'my', 'me', 'can', 'does', 'will', 'this', 'that', 'it', 'be',
        'at', 'as', 'by', 'if', 'from', 'into', 'about', 'your', 'you'
    };

    /** Fragments shorter than this must match exactly (no prefix/fuzzy). */
    public static final Integer MIN_PREFIX_LEN = 3;

    /** Display-order sentinel that sorts after all real taxonomy entries. */
    public static final Integer ORDER_SENTINEL = 900;
}