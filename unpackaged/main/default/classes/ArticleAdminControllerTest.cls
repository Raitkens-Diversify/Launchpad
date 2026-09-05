@IsTest
private class ArticleAdminControllerTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    // ---- Builders ---------------------------------------------------------------

    private static ArticleAdminController.ArticleInput input(String title, String urlName) {
        ArticleAdminController.ArticleInput a = new ArticleAdminController.ArticleInput();
        a.title = title;
        a.urlName = urlName;
        a.summary = 'Summary for ' + title;
        a.content = '<h2>Section</h2><p>Body</p>';
        a.keywords = 'console, test';
        a.featured = false;
        return a;
    }

    private static Resource__c makeResource(Id categoryId, String name, String slug) {
        return new Resource__c(
            Name = name,
            Category__c = categoryId,
            Slug__c = slug,
            Resource_Type__c = 'PDF',
            Is_Active__c = true
        );
    }

    private static Id makeCategory() {
        Resource_Category__c cat = new Resource_Category__c(
            Name = 'Console Test Category',
            Slug__c = 'console-test-category',
            Is_Active__c = true
        );
        insert cat;
        return cat.Id;
    }

    private static List<Knowledge__DataCategorySelection> selectionsFor(Id versionId) {
        List<Knowledge__DataCategorySelection> out = new List<Knowledge__DataCategorySelection>();
        for (Knowledge__DataCategorySelection sel : [
            SELECT DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection WHERE ParentId = :versionId
        ]) {
            if (sel.DataCategoryGroupName == 'Help_Topics') {
                out.add(sel);
            }
        }
        return out;
    }

    // ---- Tests -------------------------------------------------------------------

    @IsTest
    static void createDraftWithCategoriesThenPublish() {
        ArticleAdminController.ArticleInput a = input('Console Article', 'console-article');
        a.categoryNames = new List<String>{ 'The_Basics' };
        a.suggestedUrlNames = new List<String>{ 'some-other-article', '' };

        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));

        Knowledge__kav draft = [
            SELECT PublishStatus, Title, Suggested_Articles__c
            FROM Knowledge__kav WHERE Id = :res.versionId
        ];
        System.assertEquals('Draft', draft.PublishStatus);
        /*System.assertEquals('some-other-article', draft.Suggested_Articles__c,
            'Blank suggestion lines are dropped; entries join with newlines');*/
        List<Knowledge__DataCategorySelection> sels = selectionsFor(res.versionId);
        System.assertEquals(1, sels.size(), 'Category selection written on the draft');
        System.assertEquals('The_Basics', sels[0].DataCategoryName);

        ArticleAdminController.publishArticle(res.kaId);
        System.assertEquals(1, [
            SELECT COUNT() FROM Knowledge__kav
            WHERE KnowledgeArticleId = :res.kaId AND PublishStatus = 'Online'
        ], 'Publish put the article online');
    }

    @IsTest
    static void categoryDiffSwapsSelections() {
        ArticleAdminController.ArticleInput a = input('Diff Article', 'diff-article');
        a.categoryNames = new List<String>{ 'The_Basics' };
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));

        a.versionId = res.versionId;
        a.categoryNames = new List<String>{ 'Creating_Cases' };
        ArticleAdminController.saveArticle(JSON.serialize(a));

        List<Knowledge__DataCategorySelection> sels = selectionsFor(res.versionId);
        System.assertEquals(1, sels.size(), 'Old selection deleted, new inserted');
        System.assertEquals('Creating_Cases', sels[0].DataCategoryName);
    }

    @IsTest
    static void unknownCategoryRejectedAndRolledBack() {
        ArticleAdminController.ArticleInput a = input('Bad Cat Article', 'bad-cat-article');
        a.categoryNames = new List<String>{ 'Not_A_Real_Topic' };
        try {
            ArticleAdminController.saveArticle(JSON.serialize(a));
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(0, [
            SELECT COUNT() FROM Knowledge__kav WHERE UrlName = 'bad-cat-article'
        ], 'The whole save rolls back when the category is invalid');
    }

    @IsTest
    static void relatedResourceSyncWritesStableKaIdAndOrder() {
        Id catId = makeCategory();
        Resource__c r1 = makeResource(catId, 'Alpha Guide', 'alpha-guide');
        Resource__c r2 = makeResource(catId, 'Beta Form', 'beta-form');
        insert new List<Resource__c>{ r1, r2 };

        ArticleAdminController.ArticleInput a = input('Linked Article', 'linked-article');
        a.relatedResourceIds = new List<Id>{ r1.Id, r2.Id };
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));

        List<Article_Resource__c> links = [
            SELECT Resource__c, Knowledge_Article_Id__c, Article_UrlName__c, Display_Order__c
            FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :res.kaId
            ORDER BY Display_Order__c ASC
        ];
        System.assertEquals(2, links.size());
        System.assertEquals(r1.Id, links[0].Resource__c);
        System.assertEquals(1, links[0].Display_Order__c);
        System.assertEquals('linked-article', links[0].Article_UrlName__c,
            'UrlName resolved server-side');
        System.assertEquals(res.kaId, links[0].Knowledge_Article_Id__c,
            'Junction stores the stable KA Id, never typed by hand');

        // Drop r1, keep r2 â†’ delete + reorder.
        a.versionId = res.versionId;
        a.relatedResourceIds = new List<Id>{ r2.Id };
        ArticleAdminController.saveArticle(JSON.serialize(a));
        links = [
            SELECT Resource__c, Display_Order__c FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :res.kaId
        ];
        System.assertEquals(1, links.size(), 'Removed link deleted');
        System.assertEquals(r2.Id, links[0].Resource__c);
        System.assertEquals(1, links[0].Display_Order__c, 'Remaining link reordered');
    }

    @IsTest
    static void editOnlineSpawnsDraftAndCarriesCategories() {
        ArticleAdminController.ArticleInput a = input('Carryover Article', 'carryover-article');
        a.categoryNames = new List<String>{ 'The_Basics' };
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));
        ArticleAdminController.publishArticle(res.kaId);

        Test.startTest();
        ArticleAdminController.ArticleDetail detail =
            ArticleAdminController.getArticleForEdit(res.kaId);
        Test.stopTest();

        System.assertNotEquals(res.versionId, detail.versionId,
            'A fresh draft version was spawned from the online article');
        System.assertEquals(true, detail.hasOnlineVersion,
            'The online version keeps serving readers');
        System.assertEquals(new List<String>{ 'The_Basics' }, detail.categoryNames,
            'Data-category selections carry over to the spawned draft');
    }

    @IsTest
    static void unpublishTakesArticleOffline() {
        ArticleAdminController.ArticleInput a = input('Retire Article', 'retire-article');
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));
        ArticleAdminController.publishArticle(res.kaId);

        Test.startTest();
        ArticleAdminController.unpublishArticle(res.kaId);
        Test.stopTest();

        System.assertEquals(0, [
            SELECT COUNT() FROM Knowledge__kav
            WHERE KnowledgeArticleId = :res.kaId AND PublishStatus = 'Online'
        ], 'No online version remains');
        System.assertEquals(1, [
            SELECT COUNT() FROM Knowledge__kav
            WHERE KnowledgeArticleId = :res.kaId AND PublishStatus = 'Draft'
        ], 'The content lives on as a draft');
    }

    @IsTest
    static void listArticlesMergesDraftOntoOnline() {
        ArticleAdminController.ArticleInput a = input('Listed Article', 'listed-article');
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));
        ArticleAdminController.publishArticle(res.kaId);
        ArticleAdminController.getArticleForEdit(res.kaId); // spawn pending draft

        List<ArticleAdminController.ArticleRow> rows = ArticleAdminController.listArticles();

        ArticleAdminController.ArticleRow mine;
        for (ArticleAdminController.ArticleRow row : rows) {
            if (row.kaId == res.kaId) {
                mine = row;
            }
        }
        System.assertNotEquals(null, mine, 'The article appears exactly once');
        System.assertEquals('Online + draft', mine.status);
    }

    @IsTest
    static void urlNameHelpersAndDuplicates() {
        ArticleAdminController.ArticleInput a = input('Unique Article', 'unique-article');
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));

        System.assertEquals(false,
            ArticleAdminController.isUrlNameAvailable('unique-article', null),
            'Taken by another article');
        System.assertEquals(true,
            ArticleAdminController.isUrlNameAvailable('unique-article', res.kaId),
            'The owner can keep its own UrlName');
        System.assertEquals(true,
            ArticleAdminController.isUrlNameAvailable('never-used-name', null));

        ArticleAdminController.ArticleInput dup = input('Dup Article', 'unique-article');
        try {
            ArticleAdminController.saveArticle(JSON.serialize(dup));
            System.assert(false, 'Expected a duplicate UrlName error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void embedUrlMustBeHttps() {
        ArticleAdminController.ArticleInput a = input('Embed Article', 'embed-article');
        a.embedUrl = 'http://scribehow.com/embed/x';
        try {
            ArticleAdminController.saveArticle(JSON.serialize(a));
            System.assert(false, 'Expected an https:// validation error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void authoringMetaListsRecordTypesAndTaxonomy() {
        ArticleAdminController.AuthoringMeta meta = ArticleAdminController.getAuthoringMeta();
        System.assert(!meta.recordTypes.isEmpty(), 'Active record types surface');
        System.assert(!meta.categoryTree.isEmpty(), 'Help topics surface');
        Boolean hasSubtopics = false;
        for (ArticleAdminController.CategoryNode topic : meta.categoryTree) {
            if (!topic.children.isEmpty()) {
                hasSubtopics = true;
            }
        }
        System.assert(hasSubtopics, 'Subtopics come through as children');
    }

    @IsTest
    static void pickersFindResourcesAndArticles() {
        Id catId = makeCategory();
        insert makeResource(catId, 'Pickable Guide', 'pickable-guide');
        ArticleAdminController.ArticleInput a = input('Pickable Article', 'pickable-article');
        ArticleAdminController.SaveResult res = ArticleAdminController.saveArticle(JSON.serialize(a));
        ArticleAdminController.publishArticle(res.kaId);

        List<ArticleAdminController.PickItem> resources =
            ArticleAdminController.searchResourcesForPicker('Pickable');
        System.assertEquals(1, resources.size());
        System.assertEquals('Pickable Guide', resources[0].label);
        System.assertEquals('pickable-guide', resources[0].slug,
            'Resource picker carries the slug (feeds the Copy link action)');

        List<ArticleAdminController.PickItem> articles =
            ArticleAdminController.searchArticlesForPicker('Pickable');
        System.assertEquals(1, articles.size());
        System.assertEquals('pickable-article', articles[0].value,
            'Article picker returns the UrlName (what Suggested_Articles__c stores)');

        System.assertEquals(0,
            ArticleAdminController.searchResourcesForPicker('x').size(),
            'Sub-2-character terms return nothing');
    }

    @IsTest
    static void engagementSummaryAggregatesAndFiltersBySurface() {
        insert new List<Article_View__c>{
            new Article_View__c(Article_Title__c = 'Hot Article', Article_Id__c = 'kA0HOT0000000001',
                View_Count__c = 5, Surface__c = 'NexS', User_Article_Key__c = 'k1'),
            new Article_View__c(Article_Title__c = 'Hot Article', Article_Id__c = 'kA0HOT0000000001',
                View_Count__c = 3, Surface__c = 'Help Center', User_Article_Key__c = 'k2'),
            new Article_View__c(Article_Title__c = 'Cold Article', Article_Id__c = 'kA0COLD000000001',
                View_Count__c = 1, Surface__c = 'NexS', User_Article_Key__c = 'k3')
        };
        insert new List<Article_Feedback__c>{
            new Article_Feedback__c(Article_Title__c = 'Hot Article', Vote_Type__c = 'Up',
                Surface__c = 'NexS'),
            new Article_Feedback__c(Article_Title__c = 'Hot Article', Vote_Type__c = 'Down',
                Comment__c = 'Outdated screenshot', Surface__c = 'NexS')
        };
        insert new List<Article_Search__c>{
            new Article_Search__c(Term__c = 'reset password', Normalized_Query__c = 'reset password',
                Result_Count__c = 3, Surface__c = 'NexS'),
            new Article_Search__c(Term__c = 'reset password', Normalized_Query__c = 'reset password',
                Result_Count__c = 3, Surface__c = 'NexS'),
            new Article_Search__c(Term__c = 'quantum flux', Normalized_Query__c = 'quantum flux',
                Result_Count__c = 0, Surface__c = 'Help Center')
        };

        ArticleAdminController.EngagementSummary all =
            ArticleAdminController.getEngagementSummary(null);
        System.assertEquals('Hot Article', all.topViewed[0].label);
        System.assertEquals(8, all.topViewed[0].count, 'View counts sum across surfaces');
        System.assertEquals('kA0HOT0000000001', all.topViewed[0].key,
            'Top-viewed rows carry the stable KA Id for click-through');
        System.assertEquals(1, all.upVotes);
        System.assertEquals(1, all.downVotes);
        System.assertEquals(1, all.recentComments.size());
        System.assertEquals('Outdated screenshot', all.recentComments[0].comment);
        System.assert(String.isNotBlank(all.recentComments[0].authorName),
            'Feedback shows who gave it');
        System.assertEquals('reset password', all.topSearches[0].label);
        System.assertEquals(2, all.topSearches[0].count);
        System.assertEquals(1, all.zeroResultSearches.size(), 'Knowledge gap surfaces');
        System.assertEquals('quantum flux', all.zeroResultSearches[0].label);
        System.assertEquals(new List<String>{ 'Help Center', 'NexS' }, all.surfaces);

        ArticleAdminController.EngagementSummary nexs =
            ArticleAdminController.getEngagementSummary('NexS');
        System.assertEquals(5, nexs.topViewed[0].count,
            'Surface filter applies: only the NexS views of Hot Article count');
        System.assertEquals(0, nexs.zeroResultSearches.size(),
            'The zero-result search happened on the other surface');
    }

    @IsTest
    static void summaryStatsKeyOnNormalizedQueryOnly() {
        // Stats aggregate on Normalized_Query__c (legacy null rows were
        // backfilled once at deploy time). An unstamped row stays out of the
        // summary cards — it is still visible in the listSearches drill-down.
        insert new List<Article_Search__c>{
            new Article_Search__c(Term__c = 'How to Win', Result_Count__c = 0,
                Surface__c = 'NexS'),
            new Article_Search__c(Term__c = 'Stamped Gap', Normalized_Query__c = 'stamped gap',
                Result_Count__c = 0, Surface__c = 'NexS'),
            new Article_Search__c(Term__c = 'Stamped', Normalized_Query__c = 'stamped',
                Result_Count__c = 2, Surface__c = 'NexS')
        };

        ArticleAdminController.EngagementSummary s =
            ArticleAdminController.getEngagementSummary(null);
        System.assertEquals(2, s.topSearches.size(),
            'Only stamped rows aggregate into the summary');
        System.assertEquals(1, s.zeroResultSearches.size());
        System.assertEquals('stamped gap', s.zeroResultSearches[0].label);
        System.assertEquals(1, s.zeroResultSearches[0].count);

        List<ArticleAdminController.SearchRow> log =
            ArticleAdminController.listSearches(null, null, false, null, null);
        System.assertEquals(3, log.size(),
            'The drill-down still shows every row, stamped or not');
    }

    @IsTest
    static void searchAndViewLogsFilterAndPaginate() {
        insert new List<Article_Search__c>{
            new Article_Search__c(Term__c = 'reset password', Normalized_Query__c = 'reset password',
                Result_Count__c = 3, Surface__c = 'NexS'),
            new Article_Search__c(Term__c = 'quantum flux', Normalized_Query__c = 'quantum flux',
                Result_Count__c = 0, Surface__c = 'Help Center')
        };
        insert new List<Article_View__c>{
            new Article_View__c(Article_Title__c = 'Guide A', Article_Id__c = 'kA0AAAA000000001',
                View_Count__c = 4, Last_Viewed__c = System.now(),
                Surface__c = 'NexS', User_Article_Key__c = 'v1'),
            new Article_View__c(Article_Title__c = 'Guide B', Article_Id__c = 'kA0BBBB000000001',
                View_Count__c = 2, Last_Viewed__c = System.now().addHours(-1),
                Surface__c = 'Help Center', User_Article_Key__c = 'v2')
        };

        List<ArticleAdminController.SearchRow> all =
            ArticleAdminController.listSearches(null, null, null, null, null);
        System.assertEquals(2, all.size());
        System.assert(String.isNotBlank(all[0].userName), 'Search rows show who searched');

        System.assertEquals(1,
            ArticleAdminController.listSearches(null, 'reset', null, null, null).size(),
            'Term filter narrows the log');
        List<ArticleAdminController.SearchRow> zero =
            ArticleAdminController.listSearches(null, null, true, null, null);
        System.assertEquals(1, zero.size(), 'Zero-only filter');
        System.assertEquals('quantum flux', zero[0].term);
        System.assertEquals(0,
            ArticleAdminController.listSearches(null, null, null,
                System.now().addDays(-1), null).size(),
            'Cursor excludes rows created after it');

        List<ArticleAdminController.ViewRow> views =
            ArticleAdminController.listViews(null, null);
        System.assertEquals(2, views.size());
        System.assertEquals('Guide A', views[0].articleTitle, 'Most recently viewed first');
        System.assert(String.isNotBlank(views[0].userName), 'View rows show who viewed');
        System.assertEquals(1, ArticleAdminController.listViews('NexS', null).size());
        System.assertEquals(1,
            ArticleAdminController.listViews(null, System.now().addMinutes(-30)).size(),
            'View cursor pages on lastViewed');
    }

    @IsTest
    static void articleEngagementDetailJoinsAllThreeLogs() {
        String ka = 'kA0DEEP000000001';
        insert new List<Article_View__c>{
            new Article_View__c(Article_Title__c = 'Deep Dive', Article_Id__c = ka,
                View_Count__c = 3, Last_Viewed__c = System.now(),
                Surface__c = 'NexS', User_Article_Key__c = 'd1'),
            new Article_View__c(Article_Title__c = 'Deep Dive', Article_Id__c = ka,
                View_Count__c = 2, Last_Viewed__c = System.now().addHours(-2),
                Surface__c = 'Help Center', User_Article_Key__c = 'd2')
        };
        insert new Article_Feedback__c(Article_Title__c = 'Deep Dive', Article_Id__c = ka,
            Vote_Type__c = 'Up', Comment__c = 'Great walkthrough', Surface__c = 'NexS');
        insert new Article_Search__c(Term__c = 'deep dive', Normalized_Query__c = 'deep dive',
            Result_Count__c = 4, Clicked_Article_Id__c = ka,
            Clicked_Article_Title__c = 'Deep Dive', Surface__c = 'NexS');

        ArticleAdminController.ArticleEngagementDetail detail =
            ArticleAdminController.getArticleEngagement(ka);
        System.assertEquals('Deep Dive', detail.title);
        System.assertEquals(5, detail.totalViews, 'Views sum across viewers');
        System.assertEquals(2, detail.viewers.size());
        System.assert(String.isNotBlank(detail.viewers[0].userName));
        System.assertEquals(1, detail.upVotes);
        System.assertEquals(0, detail.downVotes);
        System.assertEquals(1, detail.feedback.size());
        System.assert(String.isNotBlank(detail.feedback[0].authorName));
        System.assertEquals(1, detail.searches.size());
        System.assertEquals('deep dive', detail.searches[0].term);

        try {
            ArticleAdminController.getArticleEngagement('');
            System.assert(false, 'Blank Id should throw');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }

    @IsTest
    static void minimalUserIsRejected() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            Alias = 'artmin',
            Email = 'art.min@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ArtMin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'art.min.' + System.currentTimeMillis() + '@example.com.cosmosdev'
        );
        insert u;
        System.runAs(u) {
            try {
                ArticleAdminController.saveArticle(JSON.serialize(input('Nope', 'nope')));
                System.assert(false, 'Expected an access exception');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }
}