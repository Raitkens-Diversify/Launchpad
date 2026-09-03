/**
 * NexSKnowledgeController
 *
 * Read API for the NexS help center. Context-agnostic: the same methods back
 * both the Experience Cloud (LWR) surface and the core Lightning App surface.
 *
 * Conventions:
 *  - `with sharing` + explicit isAccessible() guards so we never leak articles
 *    the running user can't read (CRUD/FLS respected on top of record sharing).
 *  - Published-only: PublishStatus = 'Online', latest version, English.
 *  - Category filtering uses WITH DATA CATEGORY. Data-category names cannot be
 *    bind variables, so the category is validated against the live taxonomy
 *    (getCategories) before being concatenated into the query — this is the
 *    injection guard for that token.
 *  - Bulk-safe: no SOQL inside loops.
 */
public with sharing class NexSKnowledgeController {

    private static final String DATA_CATEGORY_GROUP = 'Help_Topics';
    private static final Integer MAX_RESULTS = 50;
    private static final Integer MAX_SUGGESTIONS = 6;
    private static final Integer MAX_TYPEAHEAD = 7;   // typeahead dropdown cap
    private static final Integer FALLBACK_COUNT = 5;  // zero-result fallback articles

    // ---- Search ranking knobs -----------------------------------------------
    // The search engine retrieves a broad candidate set, then re-ranks it in
    // Apex (see searchArticles). These constants are the tuning surface.
    //
    // Scaling note: recall is bounded by MAX_RESULTS (SOSL) and, when exact
    // recall is thin, POOL_SIZE (the fuzzy/typo SOQL pool). Both are safe for a
    // few hundred articles; past that, move ranking to an indexed store.
    private static final Integer FUZZY_TRIGGER = 5;   // run the typo pass when exact recall is below this
    private static final Integer POOL_SIZE = 300;     // max published articles pulled for the typo pass
    private static final Double  MIN_SCORE = 4;        // drop anything less relevant than one prefix title hit
    // Shared with ResourceCenterService via SearchConstants: fragments shorter
    // than this must match exactly (no prefix/fuzzy).
    private static final Integer MIN_PREFIX_LEN = SearchConstants.MIN_PREFIX_LEN;
    private static final Integer FUZZY_PREFIX = 2;    // a typo-match must share this many leading chars (keeps corrections anchored)

    // Field boosts — a term in the Title matters far more than one in the body.
    public static final Double W_TITLE    = 10;
    private static final Double W_KEYWORDS = 7;
    private static final Double W_QUESTION = 6;
    public static final Double W_SUMMARY  = 4;
    private static final Double W_ANSWER   = 2;
    private static final Double W_BODY     = 1;   // matched via SOSL body index only

    // Synonym match multiplier (Phase 2): a configured-synonym hit scores at this
    // fraction of the same match by the original term. Must stay < 1.0 so an
    // original term always outranks its synonym for an identical match — a
    // constant, not a CMDT, precisely to keep that invariant un-editable.
    public static final Double SYN_MULTIPLIER = 0.8;

    // Phrase-proximity boosts (Phase 4), following the same constant pattern as
    // the field weights. Verbatim = the full query phrase appears literally;
    // bigram = an adjacent query-word pair appears within BIGRAM_WINDOW positions
    // of each other (either order). Per field the two never stack — the higher
    // wins — and title-vs-other stays mutually exclusive (the single highest
    // boost applies), so with no bigram this is byte-identical to the prior
    // verbatim-only behavior.
    private static final Double  PHRASE_TITLE  = 25; // verbatim phrase in Title
    private static final Double  PHRASE_OTHER  = 12; // verbatim phrase in Keywords/Summary/Question
    private static final Double  BIGRAM_TITLE  = 15; // near-phrase (adjacent pair) in Title
    private static final Double  BIGRAM_OTHER  = 8;  // near-phrase in Keywords/Summary/Question
    private static final Integer BIGRAM_WINDOW = 2;  // max positional distance counted as a "window"

    // ---- Wrappers exposed to LWC --------------------------------------------

    public class ArticleSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String urlName;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public String recordType;      // DeveloperName, fallback grouping
        @AuraEnabled public String recordTypeLabel;  // fallback section header
        /** Subtopic (child Data Category) label — the Hulu-style section header
            within a topic. Null when the article sits on the topic itself. */
        @AuraEnabled public String section;
        /** Subtopic position in the taxonomy, for section ordering. */
        @AuraEnabled public Integer sectionOrder;
        /** Relevance score (searchRanked results only; null on browse paths).
            Exposed so cross-app aggregators can rank articles against other
            content types on one scale. */
        @AuraEnabled public Double score;
    }

    public class ArticleDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String urlName;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public String body;
        /** Optional embed URL (e.g. Scribe guide) rendered below the body. */
        @AuraEnabled public String embedUrl;
        /** "Suggested Articles" rail: authored picks first, topped up with
            same-topic articles (Featured first), capped, excluding self. */
        @AuraEnabled public List<ArticleSummary> suggestions;
    }

    public class CategoryInfo {
        @AuraEnabled public String name;   // API name, e.g. Getting_Started
        @AuraEnabled public String label;  // display label, e.g. Getting Started
        public CategoryInfo(String name, String label) {
            this.name = name;
            this.label = label;
        }
    }

    /** Full-search result plus the metadata the two-tier UI needs. */
    public class SearchResult {
        @AuraEnabled public List<ArticleSummary> articles;
        /** True when the typo pass produced (some of) these results. */
        @AuraEnabled public Boolean fuzzy;
        /** Best-effort corrected phrase, only set when fuzzy is true. */
        @AuraEnabled public String corrected;
        /** The significant-token query, for the "search instead" link. */
        @AuraEnabled public String original;
        public SearchResult() {
            this.articles = new List<ArticleSummary>();
            this.fuzzy = false;
        }
    }

    // ---- Public API ----------------------------------------------------------

    /**
     * Relevance-ranked search, optionally scoped to a Data Category. Backs both
     * the full results page and the typeahead dropdown.
     *
     * Modelled on how modern search engines work — retrieve broadly, then rank
     * precisely:
     *   1. Recall: one broad SOSL OR-wildcard pass over all indexed fields
     *      (Title, Summary, Keywords, Question/Answer, body).
     *   2. Typo tolerance: when exact recall is thin, a bounded SOQL pool pass
     *      adds articles whose text is within an edit or two of a query word.
     *   3. Ranking: each candidate is scored by field-weighted term matches
     *      (Title >> body), query-term coverage, exact-phrase boosts, whether
     *      it's Featured, and how often it's been viewed (popularity).
     *   4. Threshold: anything below MIN_SCORE is dropped, so "close" articles
     *      surface but incidental (e.g. body-only common-word) hits don't.
     *
     * @param term      search text; blank returns the category/all browse list
     * @param category  optional Data Category API name (e.g. 'Cases_and_Tasks')
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleSummary> searchArticles(String term, String category) {
        // Back-compat entry (unchanged contract for existing callers/tests):
        // full ranked search, fuzzy enabled, articles only.
        return searchRanked(term, category, false).articles;
    }

    /**
     * Full ranked search with result metadata. Same engine as searchArticles,
     * plus two-tier-UI affordances:
     *  - disableFuzzy re-runs a query without the typo pass (the
     *    "search for {original} instead" link).
     *  - the returned SearchResult flags when the typo pass produced the results
     *    and supplies a best-effort corrected phrase, so the UI can render
     *    "Showing results for {corrected}".
     */
    @AuraEnabled(cacheable=true)
    public static SearchResult searchRanked(String term, String category, Boolean disableFuzzy) {
        assertAccessible();
        SearchResult res = new SearchResult();

        // A blank term means "browse" — optionally scoped to a category.
        if (String.isBlank(term)) {
            res.articles = getArticlesByCategory(category);
            return res;
        }

        String cleanTerm = sanitizeSearch(term);
        List<String> qTokens = significantTokens(cleanTerm);
        if (qTokens.isEmpty()) {
            // Stopword-only queries ("how to", "what is", "how do i") — the
            // ranking engine has nothing to rank, but autocomplete users still
            // expect the literal phrase to match article titles.
            res.articles = titlePhraseFallback(cleanTerm, category);
            return res;
        }
        String phrase = String.join(qTokens, ' ');
        res.original = phrase;

        // Synonym expansion (Phase 2): map each query token to its configured
        // synonym tokens. Synonyms widen recall (OR'd into the FIND, already
        // sanitized/lowercased, same 3+ char wildcard rule) and are scored at
        // SYN_MULTIPLIER — but they never form phrase boosts and never lift the
        // coverage denominator. An empty synonym table leaves every path
        // byte-identical to before.
        Map<String, List<String>> tokenSynonyms = new Map<String, List<String>>();
        List<String> recallTokens = new List<String>(qTokens);
        Set<String> recallSeen = new Set<String>(qTokens);
        Map<String, Set<String>> synMap = synonymMap();
        for (String qt : qTokens) {
            Set<String> syns = synMap.get(qt);
            if (syns == null || syns.isEmpty()) {
                continue;
            }
            tokenSynonyms.put(qt, new List<String>(syns));
            for (String s : syns) {
                if (recallSeen.add(s)) {
                    recallTokens.add(s);
                }
            }
        }

        // 1. Broad recall via SOSL (IN ALL FIELDS, so body matches count too).
        Map<Id, Knowledge__kav> byId = new Map<Id, Knowledge__kav>();
        Set<Id> bodyHits = new Set<Id>();
        for (Knowledge__kav k : runSearch(buildFind(recallTokens, 'OR'), category)) {
            byId.put(k.Id, k);
            bodyHits.add(k.Id);
        }

        // 2. Typo tolerance: only when exact recall is thin (likely a misspell)
        //    and the caller hasn't opted out via the "search instead" link.
        Set<Id> fuzzyIds = new Set<Id>();
        if (!disableFuzzy && byId.size() < FUZZY_TRIGGER) {
            for (Knowledge__kav k : queryPool(category)) {
                if (!byId.containsKey(k.Id) && fuzzyMatches(qTokens, k)) {
                    byId.put(k.Id, k);
                    fuzzyIds.add(k.Id);
                }
            }
        }
        if (byId.isEmpty()) {
            return res;
        }

        // 3. Popularity signal — aggregate view counts across all users.
        Set<String> kaIds = new Set<String>();
        for (Knowledge__kav k : byId.values()) {
            if (k.KnowledgeArticleId != null) {
                kaIds.add(k.KnowledgeArticleId);
            }
        }
        Map<String, Integer> views = new PopularityService().viewsByArticle(kaIds);

        // 4. Score, threshold, sort. The threshold is applied to textual
        //    relevance only; Featured/popularity then tune the order among
        //    articles that already earned their place (so a Featured or popular
        //    article can't surface on an irrelevant query).
        List<Scored> scored = new List<Scored>();
        for (Knowledge__kav k : byId.values()) {
            Double relevance = scoreArticle(qTokens, tokenSynonyms, phrase, k, bodyHits.contains(k.Id));
            if (relevance < MIN_SCORE) {
                continue;
            }
            Integer v = (k.KnowledgeArticleId != null && views.containsKey(k.KnowledgeArticleId))
                ? views.get(k.KnowledgeArticleId) : 0;
            scored.add(new Scored(k, relevance + rankBoosts(k, v)));
        }
        scored.sort();

        List<Knowledge__kav> ranked = new List<Knowledge__kav>();
        Map<Id, Double> scoreById = new Map<Id, Double>();
        for (Integer i = 0; i < scored.size() && i < MAX_RESULTS; i++) {
            ranked.add(scored[i].kav);
            scoreById.put(scored[i].kav.Id, scored[i].score);
        }

        // Flag fuzzy provenance: true when a typo-pass article survived ranking,
        // so the UI can offer "Showing results for {corrected}".
        for (Knowledge__kav k : ranked) {
            if (fuzzyIds.contains(k.Id)) {
                res.fuzzy = true;
                break;
            }
        }
        if (res.fuzzy) {
            res.corrected = correctionPhrase(qTokens, ranked);
        }
        res.articles = toSummaries(ranked);
        for (ArticleSummary s : res.articles) {
            s.score = scoreById.get(s.id);
        }
        return res;
    }

    /**
     * Best-effort "did you mean" phrase for a fuzzy-sourced result set: keep each
     * query token that already matches a surviving-result word (exact/prefix),
     * else swap in the nearest such word within the token's edit budget. Pool is
     * the ranked results' Title/Keywords/Question words, so it's small.
     */
    private static String correctionPhrase(List<String> qTokens, List<Knowledge__kav> ranked) {
        Set<String> pool = new Set<String>();
        for (Knowledge__kav k : ranked) {
            pool.addAll(tokenize(k.Title));
            pool.addAll(tokenize(k.Keywords__c));
            pool.addAll(tokenize(k.Question__c));
        }
        List<String> corrected = new List<String>();
        for (String qt : qTokens) {
            Boolean matches = false;
            for (String w : pool) {
                if (w == qt || (qt.length() >= MIN_PREFIX_LEN && w.startsWith(qt))) {
                    matches = true;
                    break;
                }
            }
            String best = qt;
            if (!matches) {
                Integer budget = maxEditsFor(qt);
                Integer bestDist = budget + 1;
                for (String w : pool) {
                    if (Math.abs(w.length() - qt.length()) > budget) {
                        continue;
                    }
                    for (Integer d = 0; d < bestDist; d++) {
                        if (editWithin(w, qt, d)) {
                            bestDist = d;
                            best = w;
                            break;
                        }
                    }
                }
            }
            corrected.add(best);
        }
        return String.join(corrected, ' ');
    }

    /**
     * Lightweight typeahead tier for the as-you-type dropdown. One SOQL, word-
     * prefix matching on Title + Keywords only (no SOSL, no scoring engine, no
     * fuzzy pass, no popularity). Returns at most MAX_TYPEAHEAD results carrying
     * only Id, Title and UrlName. Title-prefix matches rank ahead of keyword-only
     * matches; ties fall to Featured then Title A→Z.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleSummary> typeahead(String term, String category) {
        assertAccessible();
        String cleanTerm = sanitizeSearch(term);
        List<String> tokens = significantTokens(cleanTerm);
        if (tokens.isEmpty()) {
            // Pure-stopword query ("how to") — mirror the full engine's title-
            // phrase fallback so typeahead surfaces the same titles Enter would,
            // capped to the typeahead limit and kept lightweight.
            return typeaheadRows(titlePhraseFallback(cleanTerm, category));
        }

        // Keywords__c is a long-text field, which SOQL can't filter with LIKE, so
        // the prefix match can't live in the WHERE clause. Instead pull a bounded
        // published pool in one SOQL (Featured-then-Title ordered) and word-prefix
        // match Title + Keywords in Apex — no SOSL, no scoring engine, no fuzzy.
        String soql =
            'SELECT Id, Title, UrlName, Featured__c, Keywords__c FROM Knowledge__kav WHERE '
            + publishedFilter()
            + dataCategoryClause(category)
            + ' ORDER BY Featured__c DESC, Title ASC LIMIT ' + POOL_SIZE;

        List<Knowledge__kav> rows;
        try {
            rows = Database.query(soql);
        } catch (QueryException e) {
            throw new AuraHandledException('Unknown category: ' + category);
        }

        // Every token must word-prefix-match. Title-only hits rank ahead of hits
        // that needed keywords; each group keeps the SOQL Featured-then-Title order.
        List<Knowledge__kav> titleHits = new List<Knowledge__kav>();
        List<Knowledge__kav> keywordHits = new List<Knowledge__kav>();
        for (Knowledge__kav k : rows) {
            List<String> titleWords = tokenize(k.Title);
            if (allTokensPrefixMatch(tokens, titleWords)) {
                titleHits.add(k);
                continue;
            }
            List<String> combined = new List<String>(titleWords);
            combined.addAll(tokenize(k.Keywords__c));
            if (allTokensPrefixMatch(tokens, combined)) {
                keywordHits.add(k);
            }
        }
        titleHits.addAll(keywordHits);

        List<ArticleSummary> out = new List<ArticleSummary>();
        for (Integer i = 0; i < titleHits.size() && i < MAX_TYPEAHEAD; i++) {
            ArticleSummary s = new ArticleSummary();  // Id/Title/UrlName only
            s.id = titleHits[i].Id;
            s.title = titleHits[i].Title;
            s.urlName = titleHits[i].UrlName;
            out.add(s);
        }
        return out;
    }

    /** Cap a summary list to MAX_TYPEAHEAD and keep only the lightweight fields. */
    private static List<ArticleSummary> typeaheadRows(List<ArticleSummary> src) {
        List<ArticleSummary> out = new List<ArticleSummary>();
        for (Integer i = 0; i < src.size() && i < MAX_TYPEAHEAD; i++) {
            ArticleSummary s = new ArticleSummary();  // Id/Title/UrlName only
            s.id = src[i].id;
            s.title = src[i].title;
            s.urlName = src[i].urlName;
            out.add(s);
        }
        return out;
    }

    /** True only if every query token is a word-prefix of some word in the list. */
    private static Boolean allTokensPrefixMatch(List<String> tokens, List<String> words) {
        for (String t : tokens) {
            Boolean found = false;
            for (String w : words) {
                if (w.startsWith(t)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    /**
     * Articles for a zero-result state: Featured first, then most-viewed, capped
     * at FALLBACK_COUNT. One cacheable call; popularity comes from the same
     * without-sharing aggregate the ranker uses.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleSummary> getFallbackArticles(String category) {
        assertAccessible();
        String soql =
            'SELECT ' + SCORING_FIELDS +
            ' FROM Knowledge__kav WHERE ' + publishedFilter() +
            dataCategoryClause(category) +
            ' ORDER BY Featured__c DESC, Title ASC LIMIT ' + POOL_SIZE;
        List<Knowledge__kav> rows;
        try {
            rows = Database.query(soql);
        } catch (QueryException e) {
            throw new AuraHandledException('Unknown category: ' + category);
        }
        if (rows.isEmpty()) {
            return new List<ArticleSummary>();
        }

        Set<String> kaIds = new Set<String>();
        for (Knowledge__kav k : rows) {
            if (k.KnowledgeArticleId != null) {
                kaIds.add(k.KnowledgeArticleId);
            }
        }
        Map<String, Integer> views = new PopularityService().viewsByArticle(kaIds);

        List<Scored> scored = new List<Scored>();
        for (Knowledge__kav k : rows) {
            Integer v = (k.KnowledgeArticleId != null && views.containsKey(k.KnowledgeArticleId))
                ? views.get(k.KnowledgeArticleId) : 0;
            // Featured dominates; popularity (log-damped) orders within each tier.
            Double s = (k.Featured__c == true ? 1000 : 0)
                + Math.min(2 * (Math.log((Double) (1 + v)) / Math.log(2.0)), 10);
            scored.add(new Scored(k, s));
        }
        scored.sort();

        List<Knowledge__kav> top = new List<Knowledge__kav>();
        for (Integer i = 0; i < scored.size() && i < FALLBACK_COUNT; i++) {
            top.add(scored[i].kav);
        }
        return toSummaries(top);
    }

    /** One broad SOSL pass; returns the raw article rows (relevance-ranked in Apex). */
    private static List<Knowledge__kav> runSearch(String findExpr, String category) {
        String sosl =
            'FIND \'' + findExpr + '\' IN ALL FIELDS RETURNING Knowledge__kav(' +
            SCORING_FIELDS +
            ' WHERE ' + publishedFilter() + ')' +
            dataCategoryClause(category) +
            ' LIMIT ' + MAX_RESULTS;

        try {
            List<List<SObject>> results = Search.query(sosl);
            return results.isEmpty()
                ? new List<Knowledge__kav>()
                : (List<Knowledge__kav>) results[0];
        } catch (QueryException e) {
            throw new AuraHandledException('Unknown category: ' + category);
        }
    }

    /**
     * Bounded pool of published articles for the typo pass. Uses SOQL (not the
     * search index) so we can compare query words against article text directly
     * with edit-distance — the search index can't do fuzzy matching itself.
     */
    private static List<Knowledge__kav> queryPool(String category) {
        String soql =
            'SELECT ' + SCORING_FIELDS +
            ' FROM Knowledge__kav WHERE ' + publishedFilter() +
            dataCategoryClause(category) +
            ' LIMIT ' + POOL_SIZE;
        try {
            return Database.query(soql);
        } catch (QueryException e) {
            throw new AuraHandledException('Unknown category: ' + category);
        }
    }

    // Fields both search passes fetch — everything the ranker scores on, plus
    // KnowledgeArticleId to join popularity data.
    private static final String SCORING_FIELDS =
        'Id, Title, Summary, UrlName, Featured__c, Keywords__c, Question__c, Answer__c, ' +
        'KnowledgeArticleId, RecordType.DeveloperName, RecordType.Name';

    /**
     * Autocomplete fallback for queries that are entirely stopwords ("how to",
     * "what is"). The ranking engine has no significant word to score, so we
     * match the literal phrase against article Titles instead — titles that
     * start with the phrase first, then Featured, then A→Z.
     */
    private static List<ArticleSummary> titlePhraseFallback(String cleanTerm, String category) {
        String phrase = (cleanTerm == null) ? '' : cleanTerm.trim().toLowerCase();

        // Need at least one real word so stray fragments ("a i") don't match
        // random title substrings.
        Boolean meaningful = false;
        if (phrase.length() > 0) {
            for (String w : phrase.split('\\s+')) {
                if (w.length() >= MIN_PREFIX_LEN) {
                    meaningful = true;
                    break;
                }
            }
        }
        if (!meaningful) {
            return new List<ArticleSummary>();
        }

        // phrase is already sanitized to [a-zA-Z0-9 ], so no LIKE wildcards or
        // quotes to escape — the bind is purely for cleanliness.
        String titleLike = '%' + phrase + '%';
        String soql =
            'SELECT ' + SCORING_FIELDS +
            ' FROM Knowledge__kav WHERE ' + publishedFilter() +
            ' AND Title LIKE :titleLike' +
            dataCategoryClause(category) +
            ' LIMIT ' + MAX_RESULTS;

        List<Knowledge__kav> rows;
        try {
            rows = Database.query(soql);
        } catch (QueryException e) {
            throw new AuraHandledException('Unknown category: ' + category);
        }

        List<Scored> scored = new List<Scored>();
        for (Knowledge__kav k : rows) {
            Boolean startsWithPhrase = (k.Title != null) && k.Title.toLowerCase().startsWith(phrase);
            scored.add(new Scored(k, (startsWithPhrase ? 100 : 50) + rankBoosts(k, 0)));
        }
        scored.sort();

        List<Knowledge__kav> ordered = new List<Knowledge__kav>();
        for (Scored sc : scored) {
            ordered.add(sc.kav);
        }
        return toSummaries(ordered);
    }

    /**
     * List published articles in a Data Category, Featured first.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleSummary> getArticlesByCategory(String category) {
        assertAccessible();

        String soql =
            'SELECT Id, Title, Summary, UrlName, Featured__c, RecordType.DeveloperName, RecordType.Name ' +
            'FROM Knowledge__kav ' +
            'WHERE ' + publishedFilter() +
            dataCategoryClause(category) +
            ' ORDER BY Featured__c DESC, Title ASC LIMIT ' + MAX_RESULTS;

        try {
            List<ArticleSummary> summaries = toSummaries(Database.query(soql));
            applySections(summaries, category);
            return summaries;
        } catch (QueryException e) {
            // A syntactically-valid but non-existent category makes the DB reject
            // the WITH DATA CATEGORY clause — surface it cleanly to the client.
            throw new AuraHandledException('Unknown category: ' + category);
        }
    }

    /**
     * Fetch a single published article including its rich-text body (Content__c).
     */
    @AuraEnabled(cacheable=true)
    public static ArticleDetail getArticle(Id articleId) {
        assertAccessible();
        if (articleId == null) {
            throw new AuraHandledException('No article specified.');
        }

        List<Knowledge__kav> rows = [
            SELECT Id, Title, Summary, UrlName, Featured__c, Content__c,
                Suggested_Articles__c, Embed_URL__c
            FROM Knowledge__kav
            WHERE Id = :articleId
            AND PublishStatus = 'Online'
            AND IsLatestVersion = true
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new AuraHandledException('Article not found or not published.');
        }

        return toDetail(rows[0]);
    }

    /**
     * Fetch a single published article by its URL name (slug). Backs the LWR
     * site's /article/<UrlName> deep links; mirrors getArticle(Id) exactly.
     */
    @AuraEnabled(cacheable=true)
    public static ArticleDetail getArticleByUrlName(String urlName) {
        assertAccessible();
        if (String.isBlank(urlName)) {
            throw new AuraHandledException('No article specified.');
        }

        List<Knowledge__kav> rows = [
            SELECT Id, Title, Summary, UrlName, Featured__c, Content__c,
                Suggested_Articles__c, Embed_URL__c
            FROM Knowledge__kav
            WHERE UrlName = :urlName
            AND PublishStatus = 'Online'
            AND IsLatestVersion = true
            AND Language = 'en_US'
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new AuraHandledException('Article not found or not published.');
        }

        return toDetail(rows[0]);
    }

    /** Map a fully-selected Knowledge__kav row to the ArticleDetail wrapper. */
    private static ArticleDetail toDetail(Knowledge__kav kav) {
        ArticleDetail detail = new ArticleDetail();
        detail.id = kav.Id;
        detail.title = kav.Title;
        detail.summary = kav.Summary;
        detail.urlName = kav.UrlName;
        detail.featured = kav.Featured__c;
        detail.body = kav.Content__c;
        detail.embedUrl = kav.Embed_URL__c;
        detail.suggestions = buildSuggestions(kav);
        return detail;
    }

    /**
     * "Suggested Articles" for an open article: the author's curated URL-name
     * list (Suggested_Articles__c, one per line) comes first in authored order,
     * then same-topic articles (already Featured-first from the category query)
     * top the list up to MAX_SUGGESTIONS. The article itself is excluded, and
     * unpublished/misspelled authored names silently drop out.
     */
    private static List<ArticleSummary> buildSuggestions(Knowledge__kav article) {
        List<ArticleSummary> out = new List<ArticleSummary>();
        Set<Id> pickedIds = new Set<Id>{ article.Id };

        // 1. Authored picks, in the order they were written.
        String authored = Schema.sObjectType.Knowledge__kav.fields.Suggested_Articles__c.isAccessible()
            ? article.Suggested_Articles__c
            : null;
        if (String.isNotBlank(authored)) {
            List<String> names = new List<String>();
            for (String line : authored.split('\n')) {
                String name = line.trim();
                if (String.isNotBlank(name)) {
                    names.add(name);
                }
            }
            if (!names.isEmpty()) {
                Map<String, ArticleSummary> byUrlName = new Map<String, ArticleSummary>();
                for (ArticleSummary s : toSummaries([
                    SELECT Id, Title, Summary, UrlName, Featured__c,
                        RecordType.DeveloperName, RecordType.Name
                    FROM Knowledge__kav
                    WHERE UrlName IN :names
                    AND PublishStatus = 'Online'
                    AND IsLatestVersion = true
                    AND Language = 'en_US'
                ])) {
                    byUrlName.put(s.urlName, s);
                }
                for (String name : names) {
                    ArticleSummary s = byUrlName.get(name);
                    if (s != null && !pickedIds.contains(s.id) && out.size() < MAX_SUGGESTIONS) {
                        pickedIds.add(s.id);
                        out.add(s);
                    }
                }
            }
        }

        // 2. Top up with articles from the same Help Topic.
        // (DataCategoryGroupName is not filterable in SOQL, so filter in Apex.)
        if (out.size() < MAX_SUGGESTIONS) {
            String topic;
            for (Knowledge__DataCategorySelection sel : [
                SELECT DataCategoryGroupName, DataCategoryName
                FROM Knowledge__DataCategorySelection
                WHERE ParentId = :article.Id
            ]) {
                if (sel.DataCategoryGroupName == DATA_CATEGORY_GROUP) {
                    topic = sel.DataCategoryName;
                    break;
                }
            }
            if (topic != null) {
                // The article may be filed under a subtopic — suggest across
                // its whole top-level topic, like the section pages do.
                loadTaxonomy();
                if (childToTopicCache.containsKey(topic)) {
                    topic = childToTopicCache.get(topic);
                }
                for (ArticleSummary s : getArticlesByCategory(topic)) {
                    if (out.size() >= MAX_SUGGESTIONS) {
                        break;
                    }
                    if (!pickedIds.contains(s.id)) {
                        pickedIds.add(s.id);
                        out.add(s);
                    }
                }
            }
        }
        return out;
    }


    /**
     * The leaf categories under Help_Topics, for the left-hand nav. Read from
     * the live taxonomy so authors can add categories without a code change.
     */
    @AuraEnabled(cacheable=true)
    public static List<CategoryInfo> getCategories() {
        List<CategoryInfo> result = new List<CategoryInfo>();

        List<Schema.DescribeDataCategoryGroupResult> groups =
            Schema.describeDataCategoryGroups(new List<String>{ 'KnowledgeArticleVersion' });

        List<Schema.DataCategoryGroupSobjectTypePair> pairs =
            new List<Schema.DataCategoryGroupSobjectTypePair>();
        for (Schema.DescribeDataCategoryGroupResult g : groups) {
            if (g.getName() == DATA_CATEGORY_GROUP) {
                Schema.DataCategoryGroupSobjectTypePair pair =
                    new Schema.DataCategoryGroupSobjectTypePair();
                pair.setSobject(g.getSobject());
                pair.setDataCategoryGroupName(g.getName());
                pairs.add(pair);
            }
        }
        if (pairs.isEmpty()) {
            return result;
        }

        List<Schema.DescribeDataCategoryGroupStructureResult> structures =
            Schema.describeDataCategoryGroupStructures(pairs, false);

        for (Schema.DescribeDataCategoryGroupStructureResult structure : structures) {
            for (Schema.DataCategory top : structure.getTopCategories()) {
                // top is the root ("All"); its children are the help topics.
                for (Schema.DataCategory child : top.getChildCategories()) {
                    result.add(new CategoryInfo(child.getName(), child.getLabel()));
                }
            }
        }
        return result;
    }

    public class SupportSettings {
        @AuraEnabled public String supportEmail;
        @AuraEnabled public String supportRequestUrl;
        /** Rollout gate for the unified landing search (default true). */
        @AuraEnabled public Boolean unifiedSearchEnabled;
    }

    /**
     * Support contact targets for the "Need more help?" band (resourceHelpBand)
     * and the Get Help case terminal. Lives on this controller because the
     * NexSHelpCenter permission set — auto-assigned to every internal user —
     * grants it, so both Help Center and Resource Center surfaces can read it.
     * Values come from Resource_Center_Setting__mdt.Default; blanks mean the
     * consuming card hides itself.
     */
    @AuraEnabled(cacheable=true)
    public static SupportSettings getSupportSettings() {
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        SupportSettings dto = new SupportSettings();
        dto.unifiedSearchEnabled = true;
        if (setting != null) {
            dto.supportEmail = setting.Support_Email__c;
            dto.supportRequestUrl = setting.Support_Request_URL__c;
            // Field ships with this feature — read defensively so the class
            // still compiles/behaves if the record predates the field.
            Object gate = setting.getPopulatedFieldsAsMap().get('Unified_Search_Enabled__c');
            if (gate instanceof Boolean) {
                dto.unifiedSearchEnabled = (Boolean) gate;
            }
        }
        return dto;
    }

    // ---- Taxonomy helpers (transaction-cached describe) -----------------------

    /** Subtopic (child category) name → its top-level topic name. */
    private static Map<String, String> childToTopicCache;
    /** Topic name → its subtopics, in taxonomy order. */
    private static Map<String, List<CategoryInfo>> topicChildrenCache;

    private static void loadTaxonomy() {
        if (childToTopicCache != null) {
            return;
        }
        childToTopicCache = new Map<String, String>();
        topicChildrenCache = new Map<String, List<CategoryInfo>>();

        List<Schema.DescribeDataCategoryGroupResult> groups =
            Schema.describeDataCategoryGroups(new List<String>{ 'KnowledgeArticleVersion' });
        List<Schema.DataCategoryGroupSobjectTypePair> pairs =
            new List<Schema.DataCategoryGroupSobjectTypePair>();
        for (Schema.DescribeDataCategoryGroupResult g : groups) {
            if (g.getName() == DATA_CATEGORY_GROUP) {
                Schema.DataCategoryGroupSobjectTypePair pair =
                    new Schema.DataCategoryGroupSobjectTypePair();
                pair.setSobject(g.getSobject());
                pair.setDataCategoryGroupName(g.getName());
                pairs.add(pair);
            }
        }
        if (pairs.isEmpty()) {
            return;
        }

        for (Schema.DescribeDataCategoryGroupStructureResult structure :
                Schema.describeDataCategoryGroupStructures(pairs, false)) {
            for (Schema.DataCategory root : structure.getTopCategories()) {
                for (Schema.DataCategory topic : root.getChildCategories()) {
                    List<CategoryInfo> children = new List<CategoryInfo>();
                    for (Schema.DataCategory sub : topic.getChildCategories()) {
                        children.add(new CategoryInfo(sub.getName(), sub.getLabel()));
                        childToTopicCache.put(sub.getName(), topic.getName());
                    }
                    topicChildrenCache.put(topic.getName(), children);
                }
            }
        }
    }

    /**
     * Fill section/sectionOrder on a topic-scoped list: an article filed under
     * one of the topic's subtopics gets that subtopic's label as its section
     * header (taxonomy order preserved). Articles filed on the topic itself keep
     * section = null and fall back to record-type grouping client-side.
     */
    private static void applySections(List<ArticleSummary> summaries, String topic) {
        if (String.isBlank(topic) || summaries.isEmpty()) {
            return;
        }
        loadTaxonomy();
        List<CategoryInfo> children = topicChildrenCache.get(topic);
        if (children == null || children.isEmpty()) {
            return;
        }

        Map<String, Integer> orderByName = new Map<String, Integer>();
        Map<String, String> labelByName = new Map<String, String>();
        for (Integer i = 0; i < children.size(); i++) {
            orderByName.put(children[i].name, i);
            labelByName.put(children[i].name, children[i].label);
        }

        Map<Id, ArticleSummary> byId = new Map<Id, ArticleSummary>();
        for (ArticleSummary s : summaries) {
            byId.put(s.id, s);
        }
        // The group-name field isn't filterable in SOQL; filter in Apex.
        for (Knowledge__DataCategorySelection sel : [
            SELECT ParentId, DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            WHERE ParentId IN :byId.keySet()
        ]) {
            if (sel.DataCategoryGroupName == DATA_CATEGORY_GROUP
                && labelByName.containsKey(sel.DataCategoryName)) {
                ArticleSummary s = byId.get(sel.ParentId);
                s.section = labelByName.get(sel.DataCategoryName);
                s.sectionOrder = orderByName.get(sel.DataCategoryName);
            }
        }
    }

    // ---- Helpers -------------------------------------------------------------

    private static String publishedFilter() {
        return 'PublishStatus = \'Online\' AND IsLatestVersion = true AND Language = \'en_US\'';
    }

    /**
     * Build a WITH DATA CATEGORY clause, or '' when no/blank category.
     *
     * The category name can't be a bind variable, so it's concatenated into the
     * query — the injection guard is a strict character-class check (word chars
     * only), which leaves nothing to break out of `AT <category>__c` with. We
     * deliberately do NOT describe the taxonomy here to validate existence: that
     * describe (describeDataCategoryGroupStructures) is expensive and used to run
     * on every list/article load. A non-existent (but word-char) category is
     * caught at query time by the callers and rethrown as a clean error.
     */
    private static String dataCategoryClause(String category) {
        if (String.isBlank(category)) {
            return '';
        }
        if (!Pattern.matches('^[A-Za-z0-9_]{1,80}$', category)) {
            throw new AuraHandledException('Invalid category.');
        }
        // BELOW (not AT): a topic query also matches articles filed under its
        // subtopics — the Hulu-style section headers within a topic.
        return ' WITH DATA CATEGORY ' + DATA_CATEGORY_GROUP + '__c BELOW ' + category + '__c';
    }

    private static void assertAccessible() {
        if (!Schema.sObjectType.Knowledge__kav.isAccessible()
            || !Schema.sObjectType.Knowledge__kav.fields.Title.isAccessible()
            || !Schema.sObjectType.Knowledge__kav.fields.Content__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to knowledge articles.');
        }
    }

    private static List<ArticleSummary> toSummaries(List<Knowledge__kav> rows) {
        List<ArticleSummary> out = new List<ArticleSummary>();
        for (Knowledge__kav kav : rows) {
            ArticleSummary s = new ArticleSummary();
            s.id = kav.Id;
            s.title = kav.Title;
            s.summary = kav.Summary;
            s.urlName = kav.UrlName;
            s.featured = kav.Featured__c;
            s.recordType = (kav.RecordType != null) ? kav.RecordType.DeveloperName : null;
            s.recordTypeLabel = (kav.RecordType != null) ? kav.RecordType.Name : null;
            out.add(s);
        }
        return out;
    }

    /**
     * Make a user term safe to inline into a SOSL FIND clause by stripping
     * everything except alphanumerics and spaces. This removes SOSL reserved
     * characters (and quotes) entirely, so there's nothing to inject with.
     */
    public static String sanitizeSearch(String input) {
        if (input == null) {
            return '';
        }
        return input.replaceAll('[^a-zA-Z0-9 ]', ' ').trim();
    }

    // Common English + question words that carry no search signal. Single
    // source: SearchConstants.STOPWORDS (client-side mirror lives in
    // lwc/searchConstants).
    private static final Set<String> STOPWORDS = SearchConstants.STOPWORDS;

    /**
     * Reduce a sanitized term to its significant search words (lowercased): drop
     * stopwords and single-character tokens. These bare words drive both the
     * SOSL FIND (with wildcards, via buildFind) and the Apex relevance scoring.
     */
    public static List<String> significantTokens(String cleanTerm) {
        List<String> tokens = new List<String>();
        if (String.isBlank(cleanTerm)) {
            return tokens;
        }
        for (String raw : cleanTerm.split('\\s+')) {
            if (raw.length() >= 2 && !STOPWORDS.contains(raw.toLowerCase())) {
                tokens.add(raw.toLowerCase());
            }
        }
        return tokens;
    }

    /**
     * The canonical normalized form of a raw query: sanitize -> tokenize ->
     * stopword/single-char drop, significant tokens space-joined. Exposed so the
     * analytics layer (NexSArticleEngagementController.logSearch) keys gap reports
     * on exactly what the engine searched on — same sanitizer, no divergence, and
     * the required alphanumeric strip is applied to that code path too. Pure string
     * work: no SOQL/DML, safe from any context.
     */
    public static String normalizeQuery(String rawTerm) {
        return String.join(significantTokens(sanitizeSearch(rawTerm)), ' ');
    }

    // ---- Synonyms (Phase 2) --------------------------------------------------

    // Per-transaction cache of the synonym map (token -> synonym tokens). Built
    // once from Search_Synonym__mdt via getAll(), which reads the platform cache
    // and costs no SOQL query. Static lifetime = this transaction.
    private static Map<String, Set<String>> synonymCache;

    // Test seam: when set, the map builds from these rows instead of the deployed
    // CMDT, so ranking tests are deterministic and independent of the shipped
    // seed rows. Null (the default, including in tests) yields an empty map,
    // which is exactly how we prove "empty table = identical behavior."
    @TestVisible private static List<Search_Synonym__mdt> testSynonymRows;

    /**
     * token -> the set of synonym tokens it expands to. Multi-word terms and
     * synonyms are reduced to their significant tokens (same sanitize+stopword
     * pass as the query), so "sign in" contributes only "sign". A group is
     * {term tokens} ∪ {synonym tokens}: the term always expands to the rest of
     * the group; when Bidirectional__c, every synonym does too.
     */
    public static Map<String, Set<String>> synonymMap() {
        if (synonymCache != null) {
            return synonymCache;
        }
        synonymCache = new Map<String, Set<String>>();
        for (Search_Synonym__mdt row : synonymRows()) {
            List<String> termTokens = significantTokens(sanitizeSearch(row.Term__c));
            Set<String> groupTokens = new Set<String>(termTokens);
            if (String.isNotBlank(row.Synonyms__c)) {
                for (String piece : row.Synonyms__c.split(',')) {
                    groupTokens.addAll(significantTokens(sanitizeSearch(piece)));
                }
            }
            Set<String> synTokens = new Set<String>(groupTokens);
            synTokens.removeAll(termTokens);
            if (termTokens.isEmpty() || synTokens.isEmpty()) {
                continue;   // nothing usable on one side — skip
            }
            for (String t : termTokens) {
                link(t, groupTokens);
            }
            if (row.Bidirectional__c == true) {
                for (String s : synTokens) {
                    link(s, groupTokens);
                }
            }
        }
        return synonymCache;
    }

    private static List<Search_Synonym__mdt> synonymRows() {
        List<Search_Synonym__mdt> rows;
        if (Test.isRunningTest()) {
            rows = (testSynonymRows == null)
                ? new List<Search_Synonym__mdt>()
                : testSynonymRows;
        } else {
            rows = Search_Synonym__mdt.getAll().values();
        }
        // The Admin Console "deletes" a synonym by re-emitting it with
        // Is_Active__c=false (CMDT rows can't be deleted from Apex). Only an
        // EXPLICIT false deactivates: unset checkbox fields read as false on
        // in-memory rows (test seam) even though live getAll() rows are always
        // populated, so the populated-fields map is the reliable signal.
        List<Search_Synonym__mdt> active = new List<Search_Synonym__mdt>();
        for (Search_Synonym__mdt row : rows) {
            Object flag = row.getPopulatedFieldsAsMap().get('Is_Active__c');
            Boolean explicitlyInactive =
                (flag instanceof Boolean) && ((Boolean) flag == false);
            if (!explicitlyInactive) {
                active.add(row);
            }
        }
        return active;
    }

    /** Add every group token except `key` itself to key's synonym set. */
    private static void link(String key, Set<String> groupTokens) {
        Set<String> vals = synonymCache.get(key);
        if (vals == null) {
            vals = new Set<String>();
            synonymCache.put(key, vals);
        }
        for (String g : groupTokens) {
            if (g != key) {
                vals.add(g);
            }
        }
    }

    /**
     * Build a SOSL boolean FIND from bare words. Words long enough to prefix-match
     * get a trailing wildcard; short fragments go in exact so they don't flood
     * recall (e.g. 'at*' matching every Atlas/Account/attribute in the index).
     */
    private static String buildFind(List<String> words, String op) {
        List<String> terms = new List<String>();
        for (String w : words) {
            terms.add(w.length() >= MIN_PREFIX_LEN ? w + '*' : w);
        }
        return String.join(terms, ' ' + op + ' ');
    }

    // ---- Relevance ranking ---------------------------------------------------

    /** A candidate article paired with its computed relevance score. */
    private class Scored implements Comparable {
        Knowledge__kav kav;
        Double score;
        Scored(Knowledge__kav kav, Double score) {
            this.kav = kav;
            this.score = score;
        }
        // Highest score first; ties broken by Featured, then Title A→Z.
        public Integer compareTo(Object o) {
            Scored other = (Scored) o;
            if (score < other.score) { return 1; }
            if (score > other.score) { return -1; }
            Boolean af = (kav.Featured__c == true), bf = (other.kav.Featured__c == true);
            if (af != bf) { return af ? -1 : 1; }
            String at = (kav.Title == null) ? '' : kav.Title;
            String bt = (other.kav.Title == null) ? '' : other.kav.Title;
            return at.compareTo(bt);
        }
    }

    /**
     * Textual relevance of one article to the query: field-weighted term matches
     * (exact > prefix > fuzzy), scaled by how much of the query it covers, plus
     * an exact-phrase boost. This is what the MIN_SCORE threshold gates on —
     * Featured/popularity are applied separately (rankBoosts) so they only tune
     * order, never rescue an irrelevant article.
     */
    private static Double scoreArticle(List<String> qTokens,
                                       Map<String, List<String>> tokenSynonyms,
                                       String phrase, Knowledge__kav kav, Boolean bodyMatched) {
        List<String> titleW = tokenize(kav.Title);
        List<String> kwW    = tokenize(kav.Keywords__c);
        List<String> qW     = tokenize(kav.Question__c);
        List<String> sumW   = tokenize(kav.Summary);
        List<String> ansW   = tokenize(kav.Answer__c);

        Double total = 0;
        Integer realMatched = 0;   // matches in a curated field — the honest coverage signal
        for (String qt : qTokens) {
            // Best score for this query concept: the original token, or any of its
            // synonyms at SYN_MULTIPLIER. Max (not sum) so a synonym never
            // double-counts, and — SYN_MULTIPLIER being < 1 — an original always
            // wins an identical match. A synonym-only hit still increments
            // realMatched, so it counts toward coverage (the point of expansion).
            Double s = tokenFieldSum(qt, titleW, kwW, qW, sumW, ansW);
            List<String> syns = tokenSynonyms.get(qt);
            if (syns != null) {
                Double synBest = 0;
                for (String syn : syns) {
                    synBest = Math.max(synBest, tokenFieldSum(syn, titleW, kwW, qW, sumW, ansW));
                }
                s = Math.max(s, SYN_MULTIPLIER * synBest);
            }
            if (s > 0) {
                realMatched++;
                total += s;
            } else if (bodyMatched) {
                // Found only in the body index — a weak signal that must NOT count
                // toward coverage, or every recalled article would look complete.
                total += W_BODY;
            }
        }
        // An article that matches no curated field is only incidentally relevant.
        if (realMatched == 0) {
            return 0;
        }

        // Coverage: reward matching more of the query in real fields (soft AND).
        Double coverage = (Double) realMatched / qTokens.size();
        total = total * (0.4 + 0.6 * coverage);

        // Phrase / near-phrase boost — a strong relevance signal. Applied here,
        // pre-threshold, exactly as the verbatim boost always has been: it is part
        // of textual relevance (MIN_SCORE gates on it), so a near-phrase article
        // survives where scattered double-word matches don't. It still can't
        // rescue an irrelevant article — realMatched == 0 already returned 0 above,
        // and a bigram can only match words that are physically in the fields (and
        // thus already scored per-word). Per field: verbatim OR bigram, whichever
        // is higher, never both; title and other stay mutually exclusive.
        if (phrase.length() > 0) {
            String tLower = (kav.Title == null) ? '' : kav.Title.toLowerCase();
            Double titleBoost = 0;
            if (tLower.contains(phrase)) {
                titleBoost = PHRASE_TITLE;
            } else if (hasBigram(qTokens, titleW)) {
                titleBoost = BIGRAM_TITLE;
            }

            String haystack = (
                (kav.Summary == null ? '' : kav.Summary) + ' ' +
                (kav.Keywords__c == null ? '' : kav.Keywords__c) + ' ' +
                (kav.Question__c == null ? '' : kav.Question__c)
            ).toLowerCase();
            Double otherBoost = 0;
            if (haystack.contains(phrase)) {
                otherBoost = PHRASE_OTHER;
            } else if (hasBigram(qTokens, kwW) || hasBigram(qTokens, sumW) || hasBigram(qTokens, qW)) {
                otherBoost = BIGRAM_OTHER;
            }

            total += Math.max(titleBoost, otherBoost);
        }
        return total;
    }

    /**
     * True if any adjacent pair of significant query words appears within
     * BIGRAM_WINDOW positions of each other (either order) in the field's words —
     * a near-phrase signal for "reset password" vs a title reading "Password
     * Reset". Each field is checked on its own word list, so matches never span a
     * field boundary. Bounded by field length; no effect on coverage.
     */
    private static Boolean hasBigram(List<String> qTokens, List<String> fieldWords) {
        if (qTokens.size() < 2 || fieldWords == null || fieldWords.isEmpty()) {
            return false;
        }
        Map<String, List<Integer>> positions = new Map<String, List<Integer>>();
        for (Integer i = 0; i < fieldWords.size(); i++) {
            String w = fieldWords[i];
            if (!positions.containsKey(w)) {
                positions.put(w, new List<Integer>());
            }
            positions.get(w).add(i);
        }
        for (Integer i = 0; i < qTokens.size() - 1; i++) {
            List<Integer> pa = positions.get(qTokens[i]);
            List<Integer> pb = positions.get(qTokens[i + 1]);
            if (pa == null || pb == null) {
                continue;
            }
            for (Integer x : pa) {
                for (Integer y : pb) {
                    if (x != y && Math.abs(x - y) <= BIGRAM_WINDOW) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /**
     * Ranking boosts applied only to already-relevant articles: Featured status
     * and popularity (view count, with diminishing returns so it tips ties
     * rather than dominating relevance).
     */
    private static Double rankBoosts(Knowledge__kav kav, Integer views) {
        Double boost = (kav.Featured__c == true) ? 3 : 0;
        if (views != null && views > 0) {
            boost += Math.min(2 * (Math.log((Double) (1 + views)) / Math.log(2.0)), 10);
        }
        return boost;
    }

    /** One token's summed best-match score across all curated fields. */
    private static Double tokenFieldSum(String t, List<String> titleW, List<String> kwW,
                                        List<String> qW, List<String> sumW, List<String> ansW) {
        return bestFieldScore(t, titleW, W_TITLE)
             + bestFieldScore(t, kwW,   W_KEYWORDS)
             + bestFieldScore(t, qW,    W_QUESTION)
             + bestFieldScore(t, sumW,  W_SUMMARY)
             + bestFieldScore(t, ansW,  W_ANSWER);
    }

    /** Best score a query word earns from one field's words: exact > prefix > fuzzy. */
    private static Double bestFieldScore(String qToken, List<String> fieldWords, Double weight) {
        Double best = 0;
        for (String w : fieldWords) {
            if (w == qToken) {
                return weight;                       // exact — any length, can't do better
            }
            if (qToken.length() >= MIN_PREFIX_LEN && w.startsWith(qToken)) {
                best = Math.max(best, weight * 0.6); // query is a prefix of the field word
            } else if (w.length() >= MIN_PREFIX_LEN && qToken.startsWith(w)) {
                best = Math.max(best, weight * 0.6); // field word is a prefix of the query
            } else if (fuzzyMatch(w, qToken)) {
                best = Math.max(best, weight * 0.4); // fuzzy / typo (conservative policy)
            }
        }
        return best;
    }

    /** True if any Title/Keywords/Question word is a prefix or near-match of a query word. */
    private static Boolean fuzzyMatches(List<String> qTokens, Knowledge__kav kav) {
        List<String> pool = new List<String>();
        pool.addAll(tokenize(kav.Title));
        pool.addAll(tokenize(kav.Keywords__c));
        pool.addAll(tokenize(kav.Question__c));
        for (String qt : qTokens) {
            for (String w : pool) {
                if (w == qt) {
                    return true;
                }
                if (qt.length() >= MIN_PREFIX_LEN && w.startsWith(qt)) {
                    return true;
                }
                if (w.length() >= MIN_PREFIX_LEN && qt.startsWith(w)) {
                    return true;
                }
                if (fuzzyMatch(w, qt)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Fuzz budget: longer words tolerate more typos; short words must be exact.
     * The <5 cutoff (a token needs >=5 chars for any typo tolerance) is the
     * conservative, mainstream setting that stops real short words from being
     * "corrected" into unrelated ones (e.g. talk -> task).
     */
    private static Integer maxEditsFor(String token) {
        Integer len = token.length();
        if (len >= 8) { return 2; }
        if (len >= 5) { return 1; }
        return 0;
    }

    /**
     * Whether a candidate field word is a typo-match for a query token, under the
     * conservative policy: within the token's edit budget AND sharing the first
     * FUZZY_PREFIX characters (like Elasticsearch's prefix_length), so a
     * correction stays anchored to what the user typed. Single source of truth
     * for both the recall pass and scoring.
     */
    private static Boolean fuzzyMatch(String candidate, String qToken) {
        Integer budget = maxEditsFor(qToken);
        if (budget == 0 || candidate == null) {
            return false;
        }
        if (candidate.length() < FUZZY_PREFIX
            || candidate.substring(0, FUZZY_PREFIX) != qToken.substring(0, FUZZY_PREFIX)) {
            return false;
        }
        return editWithin(candidate, qToken, budget);
    }

    /** Split text into lowercased alphanumeric words. */
    @TestVisible
    private static List<String> tokenize(String text) {
        List<String> out = new List<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String w : text.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() >= 1) {
                out.add(w);
            }
        }
        return out;
    }

    /** Bounded Levenshtein: true if a and b are within maxEdits of each other. */
    @TestVisible
    private static Boolean editWithin(String a, String b, Integer maxEdits) {
        Integer la = a.length(), lb = b.length();
        if (Math.abs(la - lb) > maxEdits) {
            return false;
        }
        List<Integer> prev = new List<Integer>();
        for (Integer j = 0; j <= lb; j++) {
            prev.add(j);
        }
        for (Integer i = 1; i <= la; i++) {
            List<Integer> cur = new List<Integer>{ i };
            Integer rowMin = i;
            String ca = a.substring(i - 1, i);
            for (Integer j = 1; j <= lb; j++) {
                Integer cost = (ca == b.substring(j - 1, j)) ? 0 : 1;
                Integer v = Math.min(Math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
                cur.add(v);
                if (v < rowMin) { rowMin = v; }
            }
            if (rowMin > maxEdits) {
                return false;   // whole row already over budget — bail early
            }
            prev = cur;
        }
        return prev[lb] <= maxEdits;
    }

    /**
     * Aggregates article view counts for popularity ranking. Runs `without
     * sharing` because engagement rows are private-owned per user — ranking
     * needs the org-wide total, and only an aggregate count (never record data)
     * leaves this class.
     */
    private without sharing class PopularityService {
        Map<String, Integer> viewsByArticle(Set<String> kaIds) {
            Map<String, Integer> out = new Map<String, Integer>();
            if (kaIds == null || kaIds.isEmpty()
                || !Schema.sObjectType.Article_View__c.isAccessible()) {
                return out;
            }
            for (AggregateResult ar : [
                SELECT Article_Id__c aid, SUM(View_Count__c) total
                FROM Article_View__c
                WHERE Article_Id__c IN :kaIds
                GROUP BY Article_Id__c
            ]) {
                Object t = ar.get('total');
                out.put((String) ar.get('aid'), t == null ? 0 : ((Decimal) t).intValue());
            }
            return out;
        }
    }
}