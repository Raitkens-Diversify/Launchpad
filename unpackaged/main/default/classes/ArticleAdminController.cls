/**
 * ArticleAdminController
 *
 * Admin Console authoring API for Knowledge articles: list, guided create/edit
 * on draft versions, data-category assignment, related-resource links, and the
 * standard Knowledge publish lifecycle wrapped as simple actions.
 *
 * Lifecycle facts this class is built on (verified empirically in cosmosdev):
 *  - editOnlineArticle(kaId, false) spawns a draft version AND copies the
 *    article's Knowledge__DataCategorySelection rows to it; the Online version
 *    stays Online (readers are unaffected until publish).
 *  - Both a pending draft and the latest Online version report
 *    IsLatestVersion=true (the flag is per publish status).
 *  - Knowledge__DataCategorySelection is createable + deletable, never
 *    updateable: category changes are diff-based insert + delete on the draft.
 *  - DataCategoryGroupName is not filterable in SOQL — query by ParentId and
 *    filter the group in Apex (same workaround as NexSKnowledgeController).
 *
 * Junction integrity: Article_Resource__c rows are always written with the
 * version-stable KnowledgeArticleId + UrlName resolved server-side from records
 * the admin picked — raw Ids are never typed or trusted from the client.
 *
 * Conventions: `with sharing`, explicit describe asserts + stripInaccessible
 * before DML, AuraHandledException with actionable messages, no SOQL in loops.
 */
public with sharing class ArticleAdminController {

    private static final String GROUP_NAME = 'Help_Topics';
    private static final String LANG = 'en_US';
    private static final Integer LIST_LIMIT = 500;
    private static final Integer PICKER_LIMIT = 10;
    private static final Integer PAGE_SIZE = 50;

    // ---- DTOs -------------------------------------------------------------------

    public class RecordTypeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
    }

    public class CategoryNode {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public List<CategoryNode> children = new List<CategoryNode>();
        public CategoryNode(String name, String label) {
            this.name = name;
            this.label = label;
        }
    }

    public class AuthoringMeta {
        @AuraEnabled public List<RecordTypeInfo> recordTypes;
        @AuraEnabled public List<CategoryNode> categoryTree;
    }

    public class ArticleRow {
        @AuraEnabled public String kaId;
        @AuraEnabled public Id versionId;         // the version the console edits/shows
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
        @AuraEnabled public String status;        // Draft | Online | Online + draft
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Datetime lastModified;
        @AuraEnabled public List<String> categoryLabels = new List<String>();
    }

    public class ResourceLink {
        @AuraEnabled public Id resourceId;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String resourceType;
    }

    public class ArticleDetail {
        @AuraEnabled public Id versionId;
        @AuraEnabled public String kaId;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
        @AuraEnabled public String summary;
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String content;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String keywords;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public String embedUrl;
        @AuraEnabled public List<String> suggestedUrlNames = new List<String>();
        @AuraEnabled public List<String> categoryNames = new List<String>();
        @AuraEnabled public List<ResourceLink> relatedResources = new List<ResourceLink>();
        @AuraEnabled public Boolean hasOnlineVersion;
    }

    /** saveArticle input (public fields deserialize from the LWC). */
    public class ArticleInput {
        @AuraEnabled public Id versionId;                 // null = create
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
        @AuraEnabled public String summary;
        @AuraEnabled public String content;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String keywords;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public String embedUrl;
        @AuraEnabled public List<String> suggestedUrlNames;
        @AuraEnabled public List<String> categoryNames;
        @AuraEnabled public List<Id> relatedResourceIds;
    }

    public class SaveResult {
        @AuraEnabled public String kaId;
        @AuraEnabled public Id versionId;
    }

    public class PickItem {
        @AuraEnabled public String value;     // resource Id / article UrlName
        @AuraEnabled public String label;
        @AuraEnabled public String sublabel;
        @AuraEnabled public String slug;      // resource Slug__c (resource pickers only)
    }

    public class StatItem {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        // topViewed: the stable KnowledgeArticleId, for click-through to the
        // per-article engagement detail. Null for search stats.
        @AuraEnabled public String key;
    }

    public class FeedbackItem {
        @AuraEnabled public String articleTitle;
        @AuraEnabled public String articleId;   // stable KA Id (click-through)
        @AuraEnabled public String authorName;
        @AuraEnabled public String voteType;
        @AuraEnabled public String comment;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String surface;
    }

    public class EngagementSummary {
        @AuraEnabled public List<StatItem> topViewed = new List<StatItem>();
        @AuraEnabled public Integer upVotes = 0;
        @AuraEnabled public Integer downVotes = 0;
        @AuraEnabled public List<FeedbackItem> recentComments = new List<FeedbackItem>();
        @AuraEnabled public List<StatItem> topSearches = new List<StatItem>();
        @AuraEnabled public List<StatItem> zeroResultSearches = new List<StatItem>();
        @AuraEnabled public List<String> surfaces = new List<String>();
    }

    public class SearchRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String term;
        @AuraEnabled public String normalizedTerm;
        @AuraEnabled public Integer resultCount;
        @AuraEnabled public String searchType;
        @AuraEnabled public String clickedArticleId;
        @AuraEnabled public String clickedTitle;
        @AuraEnabled public String topResultTitle;
        @AuraEnabled public String surface;
        @AuraEnabled public String userName;
        @AuraEnabled public Datetime createdDate;
    }

    public class ViewRow {
        @AuraEnabled public String articleId;   // stable KA Id
        @AuraEnabled public String articleTitle;
        @AuraEnabled public String userName;
        @AuraEnabled public Integer viewCount;
        @AuraEnabled public Datetime lastViewed;
        @AuraEnabled public String surface;
    }

    public class ArticleEngagementDetail {
        @AuraEnabled public String articleId;
        @AuraEnabled public String title;
        @AuraEnabled public Integer totalViews = 0;
        @AuraEnabled public Integer upVotes = 0;
        @AuraEnabled public Integer downVotes = 0;
        @AuraEnabled public List<ViewRow> viewers = new List<ViewRow>();
        @AuraEnabled public List<FeedbackItem> feedback = new List<FeedbackItem>();
        @AuraEnabled public List<SearchRow> searches = new List<SearchRow>();
    }

    // ---- Reads ------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static AuthoringMeta getAuthoringMeta() {
        assertReadable();
        AuthoringMeta meta = new AuthoringMeta();
        meta.recordTypes = new List<RecordTypeInfo>();
        for (RecordType rt : [
            SELECT Id, DeveloperName, Name, Description
            FROM RecordType
            WHERE SobjectType = 'Knowledge__kav' AND IsActive = true
            ORDER BY Name ASC
        ]) {
            RecordTypeInfo info = new RecordTypeInfo();
            info.id = rt.Id;
            info.developerName = rt.DeveloperName;
            info.label = rt.Name;
            info.description = rt.Description;
            meta.recordTypes.add(info);
        }
        meta.categoryTree = describeCategoryTree();
        return meta;
    }

    /** One row per article (drafts merged onto their online version). */
    @AuraEnabled
    public static List<ArticleRow> listArticles() {
        assertReadable();
        Map<String, ArticleRow> byKa = new Map<String, ArticleRow>();

        for (Knowledge__kav v : [
            SELECT Id, KnowledgeArticleId, Title, UrlName, RecordType.Name,
                   Featured__c, LastModifiedDate
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND IsLatestVersion = true AND Language = :LANG
            ORDER BY Title ASC
            LIMIT :LIST_LIMIT
        ]) {
            byKa.put(v.KnowledgeArticleId, toRow(v, 'Online'));
        }
        for (Knowledge__kav v : [
            SELECT Id, KnowledgeArticleId, Title, UrlName, RecordType.Name,
                   Featured__c, LastModifiedDate
            FROM Knowledge__kav
            WHERE PublishStatus = 'Draft' AND Language = :LANG
            ORDER BY Title ASC
            LIMIT :LIST_LIMIT
        ]) {
            ArticleRow existing = byKa.get(v.KnowledgeArticleId);
            if (existing == null) {
                byKa.put(v.KnowledgeArticleId, toRow(v, 'Draft'));
            } else {
                // Show the draft's content-in-progress but flag the live copy.
                ArticleRow merged = toRow(v, 'Online + draft');
                byKa.put(v.KnowledgeArticleId, merged);
            }
        }

        List<ArticleRow> rows = byKa.values();
        decorateCategories(rows);
        sortRows(rows);
        return rows;
    }

    @AuraEnabled
    public static ArticleDetail getArticleForEdit(String kaId) {
        assertWritable();
        Knowledge__kav draft;
        Boolean hasOnline = false;
        for (Knowledge__kav v : versionsFor(kaId)) {
            if (v.PublishStatus == 'Draft') {
                draft = v;
            } else if (v.PublishStatus == 'Online') {
                hasOnline = true;
            }
        }
        if (draft == null) {
            if (!hasOnline) {
                throw auraError('No editable version found for this article.');
            }
            // Spawns the draft AND copies its data-category selections (verified);
            // the Online version keeps serving readers until publish.
            String draftId;
            try {
                draftId = KbManagement.PublishingService.editOnlineArticle(kaId, false);
            } catch (Exception e) {
                throw auraError('Could not open a draft for editing: ' + e.getMessage());
            }
            List<Knowledge__kav> spawned = versionsFor(kaId);
            for (Knowledge__kav v : spawned) {
                if (v.PublishStatus == 'Draft') {
                    draft = v;
                }
            }
            if (draft == null) {
                throw auraError('The draft could not be loaded after it was created.');
            }
        }
        return buildDetail(draft, hasOnline);
    }

    @AuraEnabled
    public static Boolean isUrlNameAvailable(String urlName, String kaId) {
        assertReadable();
        if (String.isBlank(urlName)) {
            return false;
        }
        for (Knowledge__kav v : [
            SELECT KnowledgeArticleId FROM Knowledge__kav
            WHERE UrlName = :urlName.trim()
            LIMIT 10
        ]) {
            if (kaId == null || v.KnowledgeArticleId != kaId) {
                return false;
            }
        }
        return true;
    }

    @AuraEnabled
    public static List<PickItem> searchArticlesForPicker(String term) {
        assertReadable();
        List<PickItem> out = new List<PickItem>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        for (Knowledge__kav v : [
            SELECT Title, UrlName FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND IsLatestVersion = true
            AND Language = :LANG AND Title LIKE :likeTerm
            ORDER BY Title ASC
            LIMIT :PICKER_LIMIT
        ]) {
            PickItem item = new PickItem();
            item.value = v.UrlName;
            item.label = v.Title;
            item.sublabel = v.UrlName;
            out.add(item);
        }
        return out;
    }

    @AuraEnabled
    public static List<PickItem> searchResourcesForPicker(String term) {
        if (!Schema.sObjectType.Resource__c.isAccessible()) {
            throw auraError('You do not have access to resources.');
        }
        List<PickItem> out = new List<PickItem>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        for (Resource__c r : [
            SELECT Id, Name, Slug__c, Resource_Type__c FROM Resource__c
            WHERE Is_Active__c = true AND Name LIKE :likeTerm
            ORDER BY Name ASC
            LIMIT :PICKER_LIMIT
        ]) {
            PickItem item = new PickItem();
            item.value = r.Id;
            item.label = r.Name;
            item.sublabel = r.Resource_Type__c;
            item.slug = r.Slug__c;
            out.add(item);
        }
        return out;
    }

    // ---- Analytics (phase e) -------------------------------------------------------

    /**
     * Engagement roll-up for the console's Analytics section — replaces the
     * Article_Engagement app's raw list views. Optional surface filter; the
     * zero-result list is the knowledge-gap signal.
     */
    @AuraEnabled
    public static EngagementSummary getEngagementSummary(String surface) {
        assertAnalyticsReadable();
        EngagementSummary summary = new EngagementSummary();
        Boolean hasSurface = String.isNotBlank(surface);

        String viewQuery = 'SELECT Article_Id__c aid, Article_Title__c title, SUM(View_Count__c) total'
            + ' FROM Article_View__c'
            + (hasSurface ? ' WHERE Surface__c = :surface' : '')
            + ' GROUP BY Article_Id__c, Article_Title__c'
            + ' ORDER BY SUM(View_Count__c) DESC LIMIT 10';
        for (AggregateResult ar : Database.query(viewQuery)) {
            StatItem item = new StatItem();
            item.key = (String) ar.get('aid');
            item.label = (String) ar.get('title');
            Decimal total = (Decimal) ar.get('total');
            item.count = total == null ? 0 : Integer.valueOf(total);
            summary.topViewed.add(item);
        }

        String voteQuery = 'SELECT Vote_Type__c vote, COUNT(Id) total'
            + ' FROM Article_Feedback__c'
            + (hasSurface ? ' WHERE Surface__c = :surface' : '')
            + ' GROUP BY Vote_Type__c';
        for (AggregateResult ar : Database.query(voteQuery)) {
            String vote = (String) ar.get('vote');
            Integer total = (Integer) ar.get('total');
            if (vote == 'Up') {
                summary.upVotes = total;
            } else if (vote == 'Down') {
                summary.downVotes = total;
            }
        }

        // Comment__c is a long text area — not filterable in SOQL, so pull the
        // most recent feedback rows and keep the commented ones in Apex.
        String commentQuery = 'SELECT Article_Title__c, Article_Id__c, Vote_Type__c, Comment__c,'
            + ' CreatedDate, CreatedBy.Name, Surface__c'
            + ' FROM Article_Feedback__c'
            + (hasSurface ? ' WHERE Surface__c = :surface' : '')
            + ' ORDER BY CreatedDate DESC LIMIT 200';
        for (Article_Feedback__c fb : Database.query(commentQuery)) {
            if (String.isBlank(fb.Comment__c)) {
                continue;
            }
            summary.recentComments.add(toFeedbackItem(fb));
            if (summary.recentComments.size() >= 10) {
                break;
            }
        }

        bucketSearchStats(summary, surface, hasSurface);

        Set<String> surfaceSet = new Set<String>();
        for (AggregateResult ar : [
            SELECT Surface__c s FROM Article_View__c GROUP BY Surface__c
        ]) {
            String s = (String) ar.get('s');
            if (String.isNotBlank(s)) {
                surfaceSet.add(s);
            }
        }
        for (AggregateResult ar : [
            SELECT Surface__c s FROM Article_Search__c GROUP BY Surface__c
        ]) {
            String s = (String) ar.get('s');
            if (String.isNotBlank(s)) {
                surfaceSet.add(s);
            }
        }
        summary.surfaces = new List<String>(surfaceSet);
        summary.surfaces.sort();
        return summary;
    }

    /**
     * Search stats via SOQL aggregates over the whole table — same pattern as
     * the views/votes cards — so rare zero-result rows can never age out of a
     * recency window. Keys on Normalized_Query__c, which logSearch always
     * stamps (the handful of legacy rows without it were backfilled once).
     */
    private static void bucketSearchStats(EngagementSummary summary, String surface,
            Boolean hasSurface) {
        summary.topSearches = topSearchStats(surface, hasSurface, false);
        summary.zeroResultSearches = topSearchStats(surface, hasSurface, true);
    }

    private static List<StatItem> topSearchStats(String surface, Boolean hasSurface,
            Boolean zeroOnly) {
        String query = 'SELECT Normalized_Query__c q, COUNT(Id) total'
            + ' FROM Article_Search__c'
            + ' WHERE Normalized_Query__c != null'
            + (zeroOnly ? ' AND Result_Count__c = 0' : '')
            + (hasSurface ? ' AND Surface__c = :surface' : '')
            + ' GROUP BY Normalized_Query__c'
            + ' ORDER BY COUNT(Id) DESC, Normalized_Query__c LIMIT 10';
        List<StatItem> out = new List<StatItem>();
        for (AggregateResult ar : Database.query(query)) {
            StatItem item = new StatItem();
            item.label = (String) ar.get('q');
            Integer total = (Integer) ar.get('total');
            item.count = total == null ? 0 : total;
            out.add(item);
        }
        return out;
    }

    /**
     * The raw search log, newest first — "every search" one click from the
     * summary. Keyset pagination: pass the last row's createdDate back as
     * beforeCursor to load the next page.
     */
    @AuraEnabled
    public static List<SearchRow> listSearches(String surface, String termFilter,
            Boolean zeroOnly, Datetime beforeCursor) {
        assertAnalyticsReadable();
        List<String> clauses = new List<String>();
        String likeTerm;
        if (String.isNotBlank(termFilter)) {
            likeTerm = '%' + termFilter.trim() + '%';
            clauses.add('Term__c LIKE :likeTerm');
        }
        if (zeroOnly == true) {
            clauses.add('Result_Count__c = 0');
        }
        if (String.isNotBlank(surface)) {
            clauses.add('Surface__c = :surface');
        }
        if (beforeCursor != null) {
            clauses.add('CreatedDate < :beforeCursor');
        }
        String query = 'SELECT Id, Term__c, Normalized_Query__c, Result_Count__c, Search_Type__c,'
            + ' Clicked_Article_Id__c, Clicked_Article_Title__c, Top_Result_Title__c,'
            + ' Surface__c, CreatedBy.Name, CreatedDate'
            + ' FROM Article_Search__c'
            + (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND '))
            + ' ORDER BY CreatedDate DESC LIMIT ' + PAGE_SIZE;
        List<SearchRow> out = new List<SearchRow>();
        for (Article_Search__c row : Database.query(query)) {
            out.add(toSearchRow(row));
        }
        return out;
    }

    /**
     * The raw view log (one row per user+article), most recently viewed first.
     * Keyset pagination on lastViewed.
     */
    @AuraEnabled
    public static List<ViewRow> listViews(String surface, Datetime beforeCursor) {
        assertAnalyticsReadable();
        List<String> clauses = new List<String>();
        if (String.isNotBlank(surface)) {
            clauses.add('Surface__c = :surface');
        }
        if (beforeCursor != null) {
            clauses.add('Last_Viewed__c < :beforeCursor');
        }
        String query = 'SELECT Article_Id__c, Article_Title__c, View_Count__c, Last_Viewed__c,'
            + ' Surface__c, CreatedBy.Name'
            + ' FROM Article_View__c'
            + (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND '))
            + ' ORDER BY Last_Viewed__c DESC NULLS LAST LIMIT ' + PAGE_SIZE;
        List<ViewRow> out = new List<ViewRow>();
        for (Article_View__c row : Database.query(query)) {
            out.add(toViewRow(row));
        }
        return out;
    }

    /**
     * Everything captured about one article, keyed by its stable KA Id: who
     * viewed it (and when/how often), all feedback, and the searches whose
     * click landed on it.
     */
    @AuraEnabled
    public static ArticleEngagementDetail getArticleEngagement(String articleId) {
        assertAnalyticsReadable();
        if (String.isBlank(articleId)) {
            throw auraError('Article Id is required.');
        }
        ArticleEngagementDetail detail = new ArticleEngagementDetail();
        detail.articleId = articleId;

        for (Article_View__c row : [
            SELECT Article_Id__c, Article_Title__c, View_Count__c, Last_Viewed__c,
                Surface__c, CreatedBy.Name
            FROM Article_View__c
            WHERE Article_Id__c = :articleId
            ORDER BY Last_Viewed__c DESC NULLS LAST
            LIMIT 200
        ]) {
            ViewRow vr = toViewRow(row);
            detail.viewers.add(vr);
            detail.totalViews += vr.viewCount;
            if (detail.title == null) {
                detail.title = row.Article_Title__c;
            }
        }

        for (Article_Feedback__c fb : [
            SELECT Article_Title__c, Article_Id__c, Vote_Type__c, Comment__c,
                CreatedDate, CreatedBy.Name, Surface__c
            FROM Article_Feedback__c
            WHERE Article_Id__c = :articleId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            detail.feedback.add(toFeedbackItem(fb));
            if (fb.Vote_Type__c == 'Up') {
                detail.upVotes++;
            } else if (fb.Vote_Type__c == 'Down') {
                detail.downVotes++;
            }
            if (detail.title == null) {
                detail.title = fb.Article_Title__c;
            }
        }

        for (Article_Search__c row : [
            SELECT Id, Term__c, Normalized_Query__c, Result_Count__c, Search_Type__c,
                Clicked_Article_Id__c, Clicked_Article_Title__c, Clicked_Rank__c,
                Top_Result_Title__c, Surface__c, CreatedBy.Name, CreatedDate
            FROM Article_Search__c
            WHERE Clicked_Article_Id__c = :articleId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            detail.searches.add(toSearchRow(row));
            if (detail.title == null) {
                detail.title = row.Clicked_Article_Title__c;
            }
        }

        if (detail.title == null) {
            detail.title = 'Unknown article';
        }
        return detail;
    }

    private static FeedbackItem toFeedbackItem(Article_Feedback__c fb) {
        FeedbackItem item = new FeedbackItem();
        item.articleTitle = fb.Article_Title__c;
        item.articleId = fb.Article_Id__c;
        item.authorName = fb.CreatedBy == null ? null : fb.CreatedBy.Name;
        item.voteType = fb.Vote_Type__c;
        item.comment = fb.Comment__c;
        item.createdDate = fb.CreatedDate;
        item.surface = fb.Surface__c;
        return item;
    }

    private static SearchRow toSearchRow(Article_Search__c row) {
        SearchRow sr = new SearchRow();
        sr.id = row.Id;
        sr.term = row.Term__c;
        sr.normalizedTerm = row.Normalized_Query__c;
        sr.resultCount = row.Result_Count__c == null ? 0 : Integer.valueOf(row.Result_Count__c);
        sr.searchType = row.Search_Type__c;
        sr.clickedArticleId = row.Clicked_Article_Id__c;
        sr.clickedTitle = row.Clicked_Article_Title__c;
        sr.topResultTitle = row.Top_Result_Title__c;
        sr.surface = row.Surface__c;
        sr.userName = row.CreatedBy == null ? null : row.CreatedBy.Name;
        sr.createdDate = row.CreatedDate;
        return sr;
    }

    private static ViewRow toViewRow(Article_View__c row) {
        ViewRow vr = new ViewRow();
        vr.articleId = row.Article_Id__c;
        vr.articleTitle = row.Article_Title__c;
        vr.userName = row.CreatedBy == null ? null : row.CreatedBy.Name;
        vr.viewCount = row.View_Count__c == null ? 0 : Integer.valueOf(row.View_Count__c);
        vr.lastViewed = row.Last_Viewed__c;
        vr.surface = row.Surface__c;
        return vr;
    }

    private static void assertAnalyticsReadable() {
        if (!Schema.sObjectType.Article_View__c.isAccessible()
            || !Schema.sObjectType.Article_Search__c.isAccessible()
            || !Schema.sObjectType.Article_Feedback__c.isAccessible()) {
            throw auraError('You do not have access to engagement analytics.');
        }
    }

    // ---- Writes -----------------------------------------------------------------

    /**
     * Create or update a draft, its categories, and its resource links atomically.
     * The payload crosses the LWC→Apex boundary as a JSON string: custom-Apex-type
     * @AuraEnabled parameters arrive null/blank from LWC in this org.
     */
    @AuraEnabled
    public static SaveResult saveArticle(String inputJson) {
        ArticleInput input;
        try {
            input = String.isBlank(inputJson)
                ? null : (ArticleInput) JSON.deserialize(inputJson, ArticleInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        return applyArticleInput(input);
    }

    /** DTO-typed entry used by saveArticle and ArticleSubmissionController.promote. */
    public static SaveResult applyArticleInput(ArticleInput input) {
        assertWritable();
        if (input == null || String.isBlank(input.title) || String.isBlank(input.urlName)) {
            throw auraError('Title and URL Name are required.');
        }

        Knowledge__kav draft = new Knowledge__kav(
            Title = input.title.trim(),
            UrlName = input.urlName.trim(),
            Summary = input.summary,
            Content__c = input.content,
            Question__c = input.question,
            Answer__c = input.answer,
            Keywords__c = input.keywords,
            Featured__c = input.featured == true,
            Embed_URL__c = normalizeEmbedUrl(input.embedUrl),
            Suggested_Articles__c = joinLines(input.suggestedUrlNames)
        );
        // Explicitly-set null RecordTypeId is rejected on DML — set only when chosen
        // (unset = the org's default record type).
        if (input.recordTypeId != null) {
            draft.RecordTypeId = input.recordTypeId;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (input.versionId == null) {
                SObjectAccessDecision d = Security.stripInaccessible(
                    AccessType.CREATABLE, new List<Knowledge__kav>{ draft });
                insert d.getRecords();
                draft.Id = d.getRecords()[0].Id;
            } else {
                assertIsDraft(input.versionId);
                draft.Id = input.versionId;
                SObjectAccessDecision d = Security.stripInaccessible(
                    AccessType.UPDATABLE, new List<Knowledge__kav>{ draft });
                SObject stripped = d.getRecords()[0];
                stripped.Id = input.versionId;
                update stripped;
            }

            Knowledge__kav saved = [
                SELECT Id, KnowledgeArticleId, UrlName FROM Knowledge__kav
                WHERE Id = :draft.Id LIMIT 1
            ];

            syncCategories(saved.Id, input.categoryNames);
            syncRelatedResources(saved.KnowledgeArticleId, input.relatedResourceIds, saved.UrlName);

            SaveResult res = new SaveResult();
            res.kaId = saved.KnowledgeArticleId;
            res.versionId = saved.Id;
            return res;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (DmlException e) {
            Database.rollback(sp);
            if (e.getMessage().contains('DUPLICATE_VALUE')) {
                throw auraError(
                    'That URL Name is already used by another article — pick a different one.');
            }
            throw auraError('Could not save the article: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw auraError('Could not save the article: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void publishArticle(String kaId) {
        assertWritable();
        try {
            KbManagement.PublishingService.publishArticle(kaId, true);
        } catch (Exception e) {
            throw auraError('Could not publish: ' + e.getMessage());
        }
    }

    /** Takes the Online version down to a draft (readers stop seeing it). */
    @AuraEnabled
    public static void unpublishArticle(String kaId) {
        assertWritable();
        try {
            KbManagement.PublishingService.editOnlineArticle(kaId, true);
        } catch (Exception e) {
            throw auraError('Could not unpublish: ' + e.getMessage());
        }
    }

    /** Discards the pending draft; the Online version (if any) is untouched. */
    @AuraEnabled
    public static void discardDraft(String kaId) {
        assertWritable();
        try {
            KbManagement.PublishingService.deleteDraftArticle(kaId);
        } catch (Exception e) {
            throw auraError('Could not discard the draft: ' + e.getMessage());
        }
    }

    // ---- Category sync ------------------------------------------------------------

    /**
     * Diff-based: Knowledge__DataCategorySelection is createable + deletable but
     * never updateable, so changes are insert-new + delete-removed on the draft.
     */
    private static void syncCategories(Id draftVersionId, List<String> categoryNames) {
        Set<String> wanted = new Set<String>();
        if (categoryNames != null) {
            for (String name : categoryNames) {
                if (String.isNotBlank(name)) {
                    wanted.add(name.trim());
                }
            }
        }
        Set<String> valid = validCategoryNames();
        for (String name : wanted) {
            if (!valid.contains(name)) {
                throw auraError('Unknown help topic: ' + name);
            }
        }

        List<Knowledge__DataCategorySelection> toDelete =
            new List<Knowledge__DataCategorySelection>();
        Set<String> existing = new Set<String>();
        for (Knowledge__DataCategorySelection sel : [
            SELECT Id, DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            WHERE ParentId = :draftVersionId
        ]) {
            if (sel.DataCategoryGroupName != GROUP_NAME) {
                continue; // never touch selections from other category groups
            }
            if (wanted.contains(sel.DataCategoryName)) {
                existing.add(sel.DataCategoryName);
            } else {
                toDelete.add(sel);
            }
        }

        List<Knowledge__DataCategorySelection> toInsert =
            new List<Knowledge__DataCategorySelection>();
        for (String name : wanted) {
            if (!existing.contains(name)) {
                toInsert.add(new Knowledge__DataCategorySelection(
                    ParentId = draftVersionId,
                    DataCategoryGroupName = GROUP_NAME,
                    DataCategoryName = name
                ));
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    // ---- Related-resource sync -------------------------------------------------

    private static void syncRelatedResources(String kaId, List<Id> resourceIds, String urlName) {
        if (resourceIds == null) {
            return; // caller did not touch the links
        }
        if (!Schema.sObjectType.Article_Resource__c.isCreateable()
            || !Schema.sObjectType.Article_Resource__c.isUpdateable()
            || !Schema.sObjectType.Article_Resource__c.isDeletable()) {
            throw auraError('You do not have access to manage article-resource links.');
        }

        Set<Id> wanted = new Set<Id>(resourceIds);
        Map<Id, Article_Resource__c> existingByResource = new Map<Id, Article_Resource__c>();
        List<Article_Resource__c> toDelete = new List<Article_Resource__c>();
        for (Article_Resource__c link : [
            SELECT Id, Resource__c, Display_Order__c, Article_UrlName__c
            FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :kaId
        ]) {
            if (wanted.contains(link.Resource__c)) {
                existingByResource.put(link.Resource__c, link);
            } else {
                toDelete.add(link);
            }
        }

        List<Article_Resource__c> toUpsert = new List<Article_Resource__c>();
        for (Integer i = 0; i < resourceIds.size(); i++) {
            Article_Resource__c link = existingByResource.get(resourceIds[i]);
            if (link == null) {
                link = new Article_Resource__c(
                    Knowledge_Article_Id__c = kaId,
                    Resource__c = resourceIds[i]
                );
            }
            link.Display_Order__c = i + 1;
            link.Article_UrlName__c = urlName;
            toUpsert.add(link);
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    // ---- Detail / list assembly ---------------------------------------------------

    private static List<Knowledge__kav> versionsFor(String kaId) {
        return [
            SELECT Id, KnowledgeArticleId, PublishStatus, Title, UrlName, Summary,
                   RecordTypeId, Content__c, Question__c, Answer__c, Keywords__c,
                   Featured__c, Embed_URL__c, Suggested_Articles__c
            FROM Knowledge__kav
            WHERE KnowledgeArticleId = :kaId
            AND PublishStatus IN ('Draft', 'Online')
            AND Language = :LANG
        ];
    }

    private static ArticleDetail buildDetail(Knowledge__kav draft, Boolean hasOnline) {
        ArticleDetail detail = new ArticleDetail();
        detail.versionId = draft.Id;
        detail.kaId = draft.KnowledgeArticleId;
        detail.title = draft.Title;
        detail.urlName = draft.UrlName;
        detail.summary = draft.Summary;
        detail.recordTypeId = draft.RecordTypeId;
        detail.content = draft.Content__c;
        detail.question = draft.Question__c;
        detail.answer = draft.Answer__c;
        detail.keywords = draft.Keywords__c;
        detail.featured = draft.Featured__c == true;
        detail.embedUrl = draft.Embed_URL__c;
        detail.hasOnlineVersion = hasOnline;

        if (String.isNotBlank(draft.Suggested_Articles__c)) {
            for (String line : draft.Suggested_Articles__c.split('\n')) {
                if (String.isNotBlank(line)) {
                    detail.suggestedUrlNames.add(line.trim());
                }
            }
        }
        for (Knowledge__DataCategorySelection sel : [
            SELECT DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            WHERE ParentId = :draft.Id
        ]) {
            if (sel.DataCategoryGroupName == GROUP_NAME) {
                detail.categoryNames.add(sel.DataCategoryName);
            }
        }
        for (Article_Resource__c link : [
            SELECT Resource__c, Resource__r.Name, Resource__r.Slug__c,
                   Resource__r.Resource_Type__c
            FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :draft.KnowledgeArticleId
            ORDER BY Display_Order__c ASC NULLS LAST
        ]) {
            ResourceLink rl = new ResourceLink();
            rl.resourceId = link.Resource__c;
            rl.name = link.Resource__r.Name;
            rl.slug = link.Resource__r.Slug__c;
            rl.resourceType = link.Resource__r.Resource_Type__c;
            detail.relatedResources.add(rl);
        }
        return detail;
    }

    private static ArticleRow toRow(Knowledge__kav v, String status) {
        ArticleRow row = new ArticleRow();
        row.kaId = v.KnowledgeArticleId;
        row.versionId = v.Id;
        row.title = v.Title;
        row.urlName = v.UrlName;
        row.status = status;
        row.recordTypeLabel = v.RecordType == null ? null : v.RecordType.Name;
        row.featured = v.Featured__c == true;
        row.lastModified = v.LastModifiedDate;
        return row;
    }

    private static void decorateCategories(List<ArticleRow> rows) {
        Map<Id, ArticleRow> byVersion = new Map<Id, ArticleRow>();
        for (ArticleRow row : rows) {
            byVersion.put(row.versionId, row);
        }
        if (byVersion.isEmpty()) {
            return;
        }
        Map<String, String> labels = categoryLabelMap();
        for (Knowledge__DataCategorySelection sel : [
            SELECT ParentId, DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            WHERE ParentId IN :byVersion.keySet()
        ]) {
            if (sel.DataCategoryGroupName != GROUP_NAME) {
                continue;
            }
            ArticleRow row = byVersion.get(sel.ParentId);
            String label = labels.get(sel.DataCategoryName);
            row.categoryLabels.add(label == null ? sel.DataCategoryName : label);
        }
    }

    private static void sortRows(List<ArticleRow> rows) {
        Map<String, ArticleRow> byKey = new Map<String, ArticleRow>();
        List<String> keys = new List<String>();
        for (ArticleRow row : rows) {
            String key = (row.title == null ? '' : row.title.toLowerCase()) + '|' + row.kaId;
            byKey.put(key, row);
            keys.add(key);
        }
        keys.sort();
        rows.clear();
        for (String key : keys) {
            rows.add(byKey.get(key));
        }
    }

    // ---- Taxonomy describe (same pattern as NexSKnowledgeController) -----------

    private static List<CategoryNode> treeCache;

    private static List<CategoryNode> describeCategoryTree() {
        if (treeCache != null) {
            return treeCache;
        }
        treeCache = new List<CategoryNode>();
        List<Schema.DescribeDataCategoryGroupResult> groups =
            Schema.describeDataCategoryGroups(new List<String>{ 'KnowledgeArticleVersion' });
        List<Schema.DataCategoryGroupSobjectTypePair> pairs =
            new List<Schema.DataCategoryGroupSobjectTypePair>();
        for (Schema.DescribeDataCategoryGroupResult g : groups) {
            if (g.getName() == GROUP_NAME) {
                Schema.DataCategoryGroupSobjectTypePair pair =
                    new Schema.DataCategoryGroupSobjectTypePair();
                pair.setSobject(g.getSobject());
                pair.setDataCategoryGroupName(g.getName());
                pairs.add(pair);
            }
        }
        if (pairs.isEmpty()) {
            return treeCache;
        }
        for (Schema.DescribeDataCategoryGroupStructureResult structure :
                Schema.describeDataCategoryGroupStructures(pairs, false)) {
            for (Schema.DataCategory root : structure.getTopCategories()) {
                for (Schema.DataCategory topic : root.getChildCategories()) {
                    CategoryNode node = new CategoryNode(topic.getName(), topic.getLabel());
                    for (Schema.DataCategory sub : topic.getChildCategories()) {
                        node.children.add(new CategoryNode(sub.getName(), sub.getLabel()));
                    }
                    treeCache.add(node);
                }
            }
        }
        return treeCache;
    }

    private static Set<String> validCategoryNames() {
        Set<String> names = new Set<String>();
        for (CategoryNode topic : describeCategoryTree()) {
            names.add(topic.name);
            for (CategoryNode sub : topic.children) {
                names.add(sub.name);
            }
        }
        return names;
    }

    private static Map<String, String> categoryLabelMap() {
        Map<String, String> labels = new Map<String, String>();
        for (CategoryNode topic : describeCategoryTree()) {
            labels.put(topic.name, topic.label);
            for (CategoryNode sub : topic.children) {
                labels.put(sub.name, sub.label);
            }
        }
        return labels;
    }

    // ---- Guards -----------------------------------------------------------------

    private static String normalizeEmbedUrl(String embedUrl) {
        if (String.isBlank(embedUrl)) {
            return null;
        }
        String clean = embedUrl.trim();
        if (!clean.startsWithIgnoreCase('https://')) {
            throw auraError(
                'Embed URL must start with https:// (the viewer refuses anything else).');
        }
        return clean;
    }

    private static String joinLines(List<String> lines) {
        if (lines == null || lines.isEmpty()) {
            return null;
        }
        List<String> clean = new List<String>();
        for (String line : lines) {
            if (String.isNotBlank(line)) {
                clean.add(line.trim());
            }
        }
        return clean.isEmpty() ? null : String.join(clean, '\n');
    }

    private static void assertIsDraft(Id versionId) {
        List<Knowledge__kav> versions = [
            SELECT PublishStatus FROM Knowledge__kav WHERE Id = :versionId LIMIT 1
        ];
        if (versions.isEmpty() || versions[0].PublishStatus != 'Draft') {
            throw auraError(
                'Only draft versions can be edited. Reload the article to get its draft.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static void assertReadable() {
        if (!Schema.sObjectType.Knowledge__kav.isAccessible()) {
            throw auraError('You do not have access to Knowledge articles.');
        }
    }

    private static void assertWritable() {
        if (!Schema.sObjectType.Knowledge__kav.isCreateable()
            || !Schema.sObjectType.Knowledge__kav.isUpdateable()) {
            throw auraError(
                'You need Knowledge authoring permissions (and the Knowledge User license) to do this.');
        }
    }
}