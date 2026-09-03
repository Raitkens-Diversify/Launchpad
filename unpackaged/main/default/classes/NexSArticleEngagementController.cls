/**
 * NexSArticleEngagementController
 *
 * Write API for help-center engagement: helpfulness votes, feedback comments,
 * per-user view tracking and search logging. Context-agnostic like the read
 * controller — the same methods back the LWR sites and the core app.
 *
 * Conventions (mirrors NexSWelcomeController):
 *  - `with sharing` + explicit isCreateable()/isUpdateable() guards; every
 *    record is written as (and owned by) the running user, and the engagement
 *    objects are Private OWD, so users only ever see their own rows.
 *  - Callers pass the Knowledge__kav (version) Id the LWCs already hold; the
 *    server maps it to the version-stable Knowledge__ka Id and re-applies the
 *    published filter, so drafts can't be probed and analytics survive
 *    republishing.
 *  - Nothing here is cacheable: vote state must be fresh after voting, and
 *    cacheable methods can't do DML anyway.
 *
 * Voting rides the native Vote object so scores land in
 * KnowledgeArticleVoteStat and match the standard widget on the internal
 * Knowledge record page. This org's knowledge base votes in 1–5 star mode
 * (Vote.Type 'Up'/'Down' is rejected with FIELD_INTEGRITY_EXCEPTION), so the
 * thumbs UI maps Up -> '5' and Down -> '1' — exactly how Lightning renders
 * star-mode votes as thumbs (3+ stars displays as thumbs-up).
 */
public with sharing class NexSArticleEngagementController {

    // Client-side mirror: lwc/nexsArticleRating MAX_COMMENT — change both together.
    private static final Integer MAX_COMMENT = 4000;
    private static final Integer MAX_TERM = 255;
    private static final Integer MAX_SESSION_KEY = 64;
    // Allowed Search_Type__c values (mirrors the restricted picklist). Anything
    // else falls back to 'Full' so an unknown value can't drop the row.
    private static final Set<String> SEARCH_TYPES = new Set<String>{
        'Full', 'Typeahead', 'Fallback', 'Fuzzy'
    };
    // Allowed App__c values (mirrors the restricted picklist). Unknown or blank
    // leaves the field null rather than dropping the row — legacy callers that
    // don't send an app must keep logging.
    private static final Set<String> APPS = new Set<String>{
        'Help Center', 'Resource Center', 'Landing'
    };

    public class EngagementState {
        /** 'Up', 'Down', or null when the user hasn't voted on the article. */
        @AuraEnabled public String voteType;
    }

    /**
     * Payload for logSearch. Carries the raw query plus the little the client
     * knows about the result set; the server derives the normalized query and
     * resolves the top-result kav Id to the version-stable Knowledge__ka Id.
     */
    public class SearchLogEntry {
        /** Raw, pre-sanitization query text as typed. */
        @AuraEnabled public String term;
        /** Number of results the search returned (0 = knowledge gap). */
        @AuraEnabled public Integer resultCount;
        /** Knowledge__kav (version) Id of the rank-1 result, or null. */
        @AuraEnabled public String topResultArticleId;
        /** 'Full' | 'Typeahead' | 'Fallback' | 'Fuzzy'; unknown -> 'Full'. */
        @AuraEnabled public String searchType;
        /** Anonymous per-tab correlation key (never a user id). */
        @AuraEnabled public String sessionKey;
        /** 'Help Center' | 'Resource Center' | 'Landing'; unknown -> null.
            App-level discriminator — Surface__c only carries the network, and
            both apps share one site. */
        @AuraEnabled public String app;
    }

    // ---- Public API ----------------------------------------------------------

    /**
     * The running user's engagement with an article — currently just their
     * existing vote, so the rating widget can pre-select it.
     */
    @AuraEnabled
    public static EngagementState getEngagement(Id articleId) {
        Knowledge__kav article = resolveArticle(articleId);
        EngagementState state = new EngagementState();
        List<Vote> votes = [
            SELECT Type FROM Vote
            WHERE ParentId = :article.KnowledgeArticleId
            AND CreatedById = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!votes.isEmpty()) {
            state.voteType = toThumb(votes[0].Type);
        }
        return state;
    }

    /**
     * Cast or change the running user's helpfulness vote.
     *
     * @param voteType 'Up' or 'Down'
     * @return the saved thumb ('Up'/'Down')
     */
    @AuraEnabled
    public static String castVote(Id articleId, String voteType) {
        String starType = toStar(voteType); // validates
        Knowledge__kav article = resolveArticle(articleId);

        List<Vote> existing = [
            SELECT Id, Type FROM Vote
            WHERE ParentId = :article.KnowledgeArticleId
            AND CreatedById = :UserInfo.getUserId()
            LIMIT 1
        ];

        try {
            if (existing.isEmpty()) {
                insertVote(article.KnowledgeArticleId, starType);
            } else if (toThumb(existing[0].Type) != voteType) {
                // Type is updateable in this org; delete+insert is the fallback
                // for contexts where the platform rejects the update.
                try {
                    existing[0].Type = starType;
                    update existing[0];
                } catch (DmlException e) {
                    delete existing[0];
                    insertVote(article.KnowledgeArticleId, starType);
                }
            }
            // Same thumb again is a no-op.
        } catch (Exception e) {
            throw new AuraHandledException('Could not save your vote: ' + e.getMessage());
        }
        return voteType;
    }

    /** Insert a vote, absorbing the insert/insert race on the platform's
        one-vote-per-user constraint (the concurrent vote wins). */
    private static void insertVote(Id knowledgeArticleId, String starType) {
        try {
            insert new Vote(ParentId = knowledgeArticleId, Type = starType);
        } catch (DmlException e) {
            if (e.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                throw e;
            }
        }
    }

    /**
     * Save an optional free-text comment accompanying a vote
     * ("What could be better?").
     */
    @AuraEnabled
    public static void submitFeedback(Id articleId, String voteType, String comments) {
        toStar(voteType); // validates the thumb
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Please enter a comment.');
        }
        if (!Schema.sObjectType.Article_Feedback__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to leave feedback.');
        }
        Knowledge__kav article = resolveArticle(articleId);
        try {
            insert new Article_Feedback__c(
                Article_Id__c = article.KnowledgeArticleId,
                Article_Title__c = article.Title,
                Vote_Type__c = voteType,
                Comment__c = comments.abbreviate(MAX_COMMENT),
                Surface__c = resolveSurface()
            );
        } catch (Exception e) {
            throw new AuraHandledException('Could not save your feedback: ' + e.getMessage());
        }
    }

    /**
     * Record that the running user opened an article: one Article_View__c per
     * user+article, incremented per view. Fire-and-forget from the LWC — a
     * failure here must never block reading, so callers swallow rejections.
     */
    @AuraEnabled
    public static void logView(Id articleId) {
        if (!Schema.sObjectType.Article_View__c.isCreateable()
            || !Schema.sObjectType.Article_View__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to log article views.');
        }
        Knowledge__kav article = resolveArticle(articleId);
        String key = UserInfo.getUserId() + '_' + article.KnowledgeArticleId;

        try {
            List<Article_View__c> views = [
                SELECT Id, View_Count__c FROM Article_View__c
                WHERE User_Article_Key__c = :key
                LIMIT 1
            ];
            if (views.isEmpty()) {
                try {
                    insert buildView(key, article, 1);
                    return;
                } catch (DmlException e) {
                    if (e.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                        throw e;
                    }
                    // Insert/insert race: another transaction created the row
                    // between our query and insert — fall through and update it.
                    views = [
                        SELECT Id, View_Count__c FROM Article_View__c
                        WHERE User_Article_Key__c = :key
                        LIMIT 1
                    ];
                }
            }
            Article_View__c row = views[0];
            // Concurrent increments can drop a count — acceptable for analytics.
            row.View_Count__c = (row.View_Count__c == null ? 0 : row.View_Count__c) + 1;
            row.Last_Viewed__c = System.now();
            row.Article_Title__c = article.Title;
            row.Surface__c = resolveSurface();
            update row;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not log the article view: ' + e.getMessage());
        }
    }

    /**
     * Log a search for analytics/tuning. Called by the LWC as a separate,
     * post-results step (searchArticles is cacheable and cacheable Apex can't do
     * DML), so this is pure fire-and-forget: ANY failure — blank term, missing
     * FLS, DML error — returns null instead of throwing. A logging problem must
     * never surface to, or slow down, the search itself. Zero-result rows are the
     * knowledge-gap signal.
     *
     * @param entryJson JSON-serialized SearchLogEntry. String transport because
     *        custom-type @AuraEnabled params arrive null in this org.
     * @return the new Article_Search__c Id (so the client can pass it to
     *         logClick), or null if nothing was logged.
     */
    @AuraEnabled
    public static Id logSearch(String entryJson) {
        if (String.isBlank(entryJson)
            || !Schema.sObjectType.Article_Search__c.isCreateable()) {
            return null;
        }
        try {
            SearchLogEntry entry = (SearchLogEntry) JSON.deserialize(entryJson, SearchLogEntry.class);
            if (entry == null || String.isBlank(entry.term)) {
                return null;
            }
            Knowledge__kav top = resolveArticleQuiet(entry.topResultArticleId);
            Article_Search__c row = new Article_Search__c(
                Term__c = entry.term.trim().abbreviate(MAX_TERM),
                Normalized_Query__c = NexSKnowledgeController.normalizeQuery(entry.term).abbreviate(MAX_TERM),
                Result_Count__c = (entry.resultCount == null || entry.resultCount < 0) ? 0 : entry.resultCount,
                Search_Type__c = SEARCH_TYPES.contains(entry.searchType) ? entry.searchType : 'Full',
                Session_Key__c = String.isBlank(entry.sessionKey) ? null : entry.sessionKey.abbreviate(MAX_SESSION_KEY),
                Top_Result_Article_Id__c = (top == null) ? null : top.KnowledgeArticleId,
                Top_Result_Title__c = (top == null) ? null : top.Title,
                Surface__c = resolveSurface(),
                App__c = APPS.contains(entry.app) ? entry.app : null
            );
            insert row;
            return row.Id;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Correlate a result click back to the search that produced it, updating the
     * row in place. `with sharing` scopes the lookup to the caller's own rows, so
     * a user can only annotate their own searches. Fire-and-forget: any failure is
     * swallowed so opening an article is never blocked.
     *
     * @param searchLogId      the Article_Search__c Id returned by logSearch
     * @param clickedArticleId Knowledge__kav (version) Id the user opened
     * @param rank             1-based position of that result in the list
     */
    @AuraEnabled
    public static void logClick(Id searchLogId, String clickedArticleId, Integer rank) {
        if (searchLogId == null || !Schema.sObjectType.Article_Search__c.isUpdateable()) {
            return;
        }
        try {
            List<Article_Search__c> rows = [
                SELECT Id FROM Article_Search__c WHERE Id = :searchLogId LIMIT 1
            ];
            if (rows.isEmpty()) {
                return;
            }
            Knowledge__kav clicked = resolveArticleQuiet(clickedArticleId);
            Article_Search__c row = rows[0];
            row.Clicked_Article_Id__c = (clicked == null) ? null : clicked.KnowledgeArticleId;
            row.Clicked_Article_Title__c = (clicked == null) ? null : clicked.Title;
            row.Clicked_Rank__c = (rank == null || rank < 1) ? null : rank;
            update row;
        } catch (Exception e) {
            // Swallowed — analytics only, never blocks the click.
        }
    }

    // ---- Helpers -------------------------------------------------------------

    /** A fresh first-view row for the running user. */
    private static Article_View__c buildView(String key, Knowledge__kav article, Integer count) {
        return new Article_View__c(
            User_Article_Key__c = key,
            Article_Id__c = article.KnowledgeArticleId,
            Article_Title__c = article.Title,
            View_Count__c = count,
            Last_Viewed__c = System.now(),
            Surface__c = resolveSurface()
        );
    }

    /**
     * Map the caller's kav (version) Id to the published article, exposing the
     * version-stable Knowledge__ka Id and the current title. Re-applies the
     * published filter so this controller can't be used to probe drafts.
     */
    private static Knowledge__kav resolveArticle(Id articleId) {
        if (articleId == null) {
            throw new AuraHandledException('No article specified.');
        }
        if (!Schema.sObjectType.Knowledge__kav.isAccessible()) {
            throw new AuraHandledException('You do not have access to knowledge articles.');
        }
        List<Knowledge__kav> rows = [
            SELECT Id, KnowledgeArticleId, Title
            FROM Knowledge__kav
            WHERE Id = :articleId
            AND PublishStatus = 'Online'
            AND IsLatestVersion = true
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Article not found or not published.');
        }
        return rows[0];
    }

    /**
     * Null-safe variant of resolveArticle for the analytics paths: map a kav
     * (version) Id to its published article, returning null (never throwing) for
     * a blank/malformed Id or a draft/unknown article. Logging must never fail.
     */
    private static Knowledge__kav resolveArticleQuiet(String articleId) {
        if (String.isBlank(articleId) || !Schema.sObjectType.Knowledge__kav.isAccessible()) {
            return null;
        }
        Id kavId;
        try {
            kavId = Id.valueOf(articleId);
        } catch (Exception e) {
            return null;
        }
        List<Knowledge__kav> rows = [
            SELECT KnowledgeArticleId, Title FROM Knowledge__kav
            WHERE Id = :kavId
            AND PublishStatus = 'Online'
            AND IsLatestVersion = true
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * 'Internal' in the core app; the network (site) name in Experience Cloud.
     * Public because ResourceCenterService.getLinkContext() resolves the same
     * surface for c/contextNav — one detector, not a third copy.
     * (ArcArticleEngagementController still carries its own clone; converging
     * that belongs with the arc* fork decision, not here.)
     */
    public static String resolveSurface() {
        Id networkId = Network.getNetworkId();
        if (networkId == null) {
            return 'Internal';
        }
        try {
            return [SELECT Name FROM Network WHERE Id = :networkId LIMIT 1].Name;
        } catch (Exception e) {
            return String.valueOf(networkId);
        }
    }

    /** Thumb -> this org's star-mode Vote.Type. Rejects anything else. */
    private static String toStar(String voteType) {
        if (voteType == 'Up') {
            return '5';
        }
        if (voteType == 'Down') {
            return '1';
        }
        throw new AuraHandledException('Invalid vote type.');
    }

    /** Any stored Vote.Type (stars or thumbs) -> 'Up'/'Down', matching how
        Lightning displays star-mode votes (3+ stars reads as thumbs-up). */
    private static String toThumb(String storedType) {
        if (storedType == 'Up' || storedType == 'Down') {
            return storedType;
        }
        return Integer.valueOf(storedType) >= 3 ? 'Up' : 'Down';
    }
}