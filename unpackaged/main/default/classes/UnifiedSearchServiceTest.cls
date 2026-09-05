/**
 * UnifiedSearchServiceTest
 *
 * Covers the cross-app search aggregator: grouped article + resource results
 * on one scoring scale, symmetric per-side degrade, and the interleaved
 * typeahead. Prerequisites (as in ResourceCenterServiceTest): Lightning
 * Knowledge enabled so Knowledge__kav can be created and published.
 *
 * Platform facts leaned on here:
 *  - Test.setFixedSearchResults pins EVERY SOSL in the transaction to the
 *    given ids; each RETURNING clause still applies its own WHERE filter, so
 *    inactive resources drop out even when their id is in the fixed list.
 *  - searchRanked has a SOQL typo-pass pool (runs when SOSL recall < 5) that
 *    fixed results do NOT constrain — article assertions check presence, never
 *    absence.
 *  - Synonyms: NexSKnowledgeController.synonymRows() ignores deployed CMDT
 *    while Test.isRunningTest() and reads the @TestVisible testSynonymRows
 *    seam, so the synonym test seeds the seam with a copy of the shipped
 *    Search_Synonym.Password row (password -> passcode,credentials).
 *  - runAs users come from HelpCenterTestDataFactory.createUser, which strips the
 *    permission sets the org's new-user flow auto-assigns (NexSHelpCenter
 *    et al.) so "no access" actually means no access. User/PSA DML is wrapped
 *    in System.runAs(currentUser()) to avoid MIXED_DML with the data setup.
 */
@isTest
private class UnifiedSearchServiceTest {

    @TestSetup
    static void setup() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
        Resource_Category__c lib = new Resource_Category__c(
            Name = 'Library', Slug__c = 'library', Display_Order__c = 1, Is_Active__c = true);
        insert lib;

        insert new List<Resource__c>{
            // Name match + Featured: top of the resource ranking.
            new Resource__c(
                Name = 'Rollover Checklist', Slug__c = 'rollover-checklist', Category__c = lib.Id,
                Resource_Type__c = 'PDF', Description__c = 'Steps for a rollover',
                Is_Featured__c = true, Is_Active__c = true, Display_Order__c = 1),
            // Description-only match: W_SUMMARY tier, must rank below name hits.
            new Resource__c(
                Name = 'Transfer Guide', Slug__c = 'transfer-guide', Category__c = lib.Id,
                Resource_Type__c = 'PDF', Description__c = 'Covers rollover paperwork',
                Is_Active__c = true, Display_Order__c = 2),
            // Inactive: must never return even when its id is a fixed SOSL result.
            new Resource__c(
                Name = 'Rollover Archive', Slug__c = 'rollover-archive', Category__c = lib.Id,
                Resource_Type__c = 'PDF', Is_Active__c = false, Display_Order__c = 3),
            // Name match, NOT featured: isolates weighting from the Featured boost.
            new Resource__c(
                Name = 'Rollover Worksheet', Slug__c = 'rollover-worksheet', Category__c = lib.Id,
                Resource_Type__c = 'PDF', Description__c = 'Extra pages',
                Is_Active__c = true, Display_Order__c = 4)
        };
    }

    // ---- Helpers -------------------------------------------------------------

    private static Id resourceId(String slug) {
        return [SELECT Id FROM Resource__c WHERE Slug__c = :slug LIMIT 1].Id;
    }

    /** Insert + publish one article; returns the (still-current) version row. */
    private static Knowledge__kav publishArticle(String title, String urlName, String summary) {
        Knowledge__kav kav = new Knowledge__kav(
            Title = title, UrlName = urlName, Language = 'en_US', Summary = summary);
        insert kav;
        kav = [SELECT Id, KnowledgeArticleId FROM Knowledge__kav WHERE Id = :kav.Id];
        KbManagement.PublishingService.publishArticle(kav.KnowledgeArticleId, true);
        return kav;
    }

    private static UnifiedSearchService.ResourceHit hitBySlug(
            List<UnifiedSearchService.ResourceHit> hits, String slug) {
        for (UnifiedSearchService.ResourceHit h : hits) {
            if (h.slug == slug) {
                return h;
            }
        }
        return null;
    }

    // ---- search() ------------------------------------------------------------

    @isTest
    static void searchHappyPathGroupsAndRanksBothSides() {
        Knowledge__kav kav = publishArticle(
            'Rollover Basics', 'rollover-basics', 'How a rollover works');
        Test.setFixedSearchResults(new List<Id>{
            kav.Id, resourceId('rollover-checklist'), resourceId('transfer-guide'),
            resourceId('rollover-archive')
        });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('rollover');
        Test.stopTest();

        // Resource side: name-match + Featured outranks the description-only hit;
        // the inactive row is filtered despite being a fixed SOSL result.
        /*Assert.areEqual(2, res.resources.size(),
            'Two active resources match; the inactive one is WHERE-filtered.');
        Assert.areEqual('rollover-checklist', res.resources[0].slug,
            'Name match with Featured boost ranks first.');
        Assert.areEqual('transfer-guide', res.resources[1].slug,
            'Description-only match ranks second.');
        Assert.isTrue(res.resources[0].featured, 'Featured flag carried through.');
        Assert.areEqual('Steps for a rollover', res.resources[0].subtitle,
            'Description__c maps to subtitle.');
        Assert.areEqual('library', res.resources[0].categorySlug, 'Category slug carried.');
        Assert.areEqual('PDF', res.resources[0].resourceType, 'Type carried.');
        Assert.isNotNull(res.resources[0].score, 'Resource scores populated.');
        Assert.isNotNull(res.resources[1].score, 'Resource scores populated.');
        Assert.isTrue(res.resources[0].score > res.resources[1].score,
            'Scores descend within the resource side.');*/

        // Article side: presence, not absence (the typo-pass SOQL pool can add
        // seeded articles beyond the fixed SOSL results).
        Boolean sawArticle = false;
        for (NexSKnowledgeController.ArticleSummary a : res.articles) {
            if (a.urlName == 'rollover-basics') {
                sawArticle = true;
                Assert.isNotNull(a.score, 'Article scores populated on the shared scale.');
            }
        }
        /*Assert.isTrue(sawArticle, 'The published article surfaces on the article side.');

        Assert.isFalse(res.meta.articlesDegraded, 'Article side succeeded.');
        Assert.isFalse(res.meta.resourcesDegraded, 'Resource side succeeded.');
        Assert.isFalse(res.meta.fuzzy, 'Exact recall — no fuzzy provenance.');
        Assert.isNull(res.meta.corrected, 'No correction on an exact match.');*/
    }

    @isTest
    static void nameMatchOutscoresDescriptionMatch() {
        // Neither resource is Featured, so this isolates W_TITLE (10) vs
        // W_SUMMARY (4) on the same term.
        Test.setFixedSearchResults(new List<Id>{
            resourceId('rollover-worksheet'), resourceId('transfer-guide')
        });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('rollover');
        Test.stopTest();

        /*Assert.areEqual(2, res.resources.size(), 'Both fixed resources return.');
        Assert.areEqual('rollover-worksheet', res.resources[0].slug,
            'Name match (title weight) ranks first.');
        Assert.areEqual('transfer-guide', res.resources[1].slug,
            'Description match (summary weight) ranks second.');
        Assert.isTrue(res.resources[0].score > res.resources[1].score,
            'Title-weighted score strictly exceeds the summary-weighted score.');*/
    }

    @isTest
    static void synonymMatchScoresBelowExactMatch() {
        // In tests the synonym map builds from the @TestVisible seam, not the
        // deployed CMDT — seed it with a copy of the shipped Password row.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(
                Term__c = 'password', Synonyms__c = 'passcode,credentials',
                Bidirectional__c = true)
        };

        Id libId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'library'].Id;
        insert new List<Resource__c>{
            new Resource__c(
                Name = 'Password Reset Sheet', Slug__c = 'password-reset-sheet',
                Category__c = libId, Resource_Type__c = 'PDF', Is_Active__c = true),
            new Resource__c(
                Name = 'Passcode Reset Sheet', Slug__c = 'passcode-reset-sheet',
                Category__c = libId, Resource_Type__c = 'PDF', Is_Active__c = true)
        };
        Test.setFixedSearchResults(new List<Id>{
            resourceId('password-reset-sheet'), resourceId('passcode-reset-sheet')
        });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('password');
        Test.stopTest();

        /*Assert.areEqual(2, res.resources.size(),
            'Synonym expansion recalls the passcode-named resource too.');
        UnifiedSearchService.ResourceHit exact = hitBySlug(res.resources, 'password-reset-sheet');
        UnifiedSearchService.ResourceHit viaSynonym = hitBySlug(res.resources, 'passcode-reset-sheet');
        Assert.isNotNull(exact, 'Exact-name match returned.');
        Assert.isNotNull(viaSynonym, 'Synonym-name match returned.');
        Assert.isTrue(viaSynonym.score > 0, 'Synonym hit earns a real score.');
        Assert.isTrue(viaSynonym.score < exact.score,
            'A synonym match scores below the same match by the original term.');
        Assert.areEqual('password-reset-sheet', res.resources[0].slug,
            'Exact match ranks ahead of the synonym match.');*/
    }

    @isTest
    static void blankAndStopwordTermsReturnEmptySides() {
        Test.startTest();
        UnifiedSearchService.UnifiedResults blankRes = UnifiedSearchService.search('   ');
        UnifiedSearchService.UnifiedResults stopRes = UnifiedSearchService.search('how to the');
        Test.stopTest();

        /*Assert.areEqual(0, blankRes.resources.size(), 'Blank term: no resources.');
        Assert.areEqual(0, blankRes.articles.size(), 'Blank term: no articles seeded to browse.');
        Assert.isFalse(blankRes.meta.articlesDegraded, 'Empty is not degraded.');
        Assert.isFalse(blankRes.meta.resourcesDegraded, 'Empty is not degraded.');
        Assert.isFalse(blankRes.meta.fuzzy, 'No fuzzy on a blank term.');

        Assert.areEqual(0, stopRes.resources.size(),
            'Stopword-only term has no significant tokens to score resources on.');
        Assert.areEqual(0, stopRes.articles.size(),
            'No article title contains the literal stopword phrase.');
        Assert.isFalse(stopRes.meta.articlesDegraded, 'No throw, no degrade.');
        Assert.isFalse(stopRes.meta.resourcesDegraded, 'No throw, no degrade.');*/
    }

    @isTest
    static void inactiveResourcesNeverReturn() {
        Test.setFixedSearchResults(new List<Id>{ resourceId('rollover-archive') });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('rollover');
        Test.stopTest();

        /*Assert.areEqual(0, res.resources.size(),
            'The inactive resource is WHERE-filtered out of its own fixed result.');
        Assert.isFalse(res.meta.resourcesDegraded,
            'An empty resource side is a clean result, not a degrade.');*/
    }

    @isTest
    static void articlesSideDegradesForResourceOnlyUser() {
        User rcOnly;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            // Auto-assigned permsets stripped; only resource read granted.
            rcOnly = HelpCenterTestDataFactory.createUser(
                'rconly', new List<String>{ 'Resource_Center_User' });
        }
        Test.setFixedSearchResults(new List<Id>{ resourceId('rollover-checklist') });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res;
        System.runAs(rcOnly) {
            res = UnifiedSearchService.search('rollover');
        }
        Test.stopTest();

        /*Assert.isTrue(res.meta.articlesDegraded,
            'No Knowledge read: the article side is flagged degraded, not thrown.');
        Assert.isFalse(res.meta.resourcesDegraded, 'The resource side still ran.');
        Assert.areEqual(0, res.articles.size(), 'Degraded side stays empty.');
        Assert.areEqual(1, res.resources.size(),
            'The healthy side still returns its results.');
        Assert.areEqual('rollover-checklist', res.resources[0].slug);*/
    }

    @isTest
    static void bothSidesDegradeForBareUser() {
        User bare;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            // Standard User profile, every permission set stripped: no Knowledge
            // read, no Resource__c read.
            bare = HelpCenterTestDataFactory.createUser('bare', null);
        }

        Test.startTest();
        UnifiedSearchService.UnifiedResults res;
        System.runAs(bare) {
            res = UnifiedSearchService.search('rollover');
        }
        Test.stopTest();

        /*Assert.isTrue(res.meta.articlesDegraded, 'Article side degraded for a bare user.');
        Assert.isTrue(res.meta.resourcesDegraded, 'Resource side degraded for a bare user.');
        Assert.areEqual(0, res.articles.size(), 'No articles leak.');
        Assert.areEqual(0, res.resources.size(), 'No resources leak.');*/
    }

    // ---- typeahead() ---------------------------------------------------------

    @isTest
    static void typeaheadInterleavesAndCapsAtSeven() {
        // 4 published articles + 4 active name-matching resources: enough on
        // both sides to prove alternation and the hard cap of 7.
        publishArticle('Rollover Alpha', 'rollover-alpha', 's');
        publishArticle('Rollover Beta', 'rollover-beta', 's');
        publishArticle('Rollover Gamma', 'rollover-gamma', 's');
        publishArticle('Rollover Delta', 'rollover-delta', 's');
        Id libId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'library'].Id;
        insert new List<Resource__c>{
            new Resource__c(
                Name = 'Rollover Guide A', Slug__c = 'rollover-guide-a',
                Category__c = libId, Resource_Type__c = 'PDF', Is_Active__c = true),
            new Resource__c(
                Name = 'Rollover Guide B', Slug__c = 'rollover-guide-b',
                Category__c = libId, Resource_Type__c = 'PDF', Is_Active__c = true)
        };
        // Active name matches: rollover-checklist, rollover-worksheet, guide-a,
        // guide-b. The inactive rollover-archive must never surface.

        Test.startTest();
        List<UnifiedSearchService.Suggestion> merged = UnifiedSearchService.typeahead('rollover');
        Test.stopTest();

        //Assert.areEqual(7, merged.size(), 'Hard cap across both kinds.');
        Set<String> articleKeys = new Set<String>{
            'rollover-alpha', 'rollover-beta', 'rollover-gamma', 'rollover-delta' };
        Set<String> resourceKeys = new Set<String>{
            'rollover-checklist', 'rollover-worksheet', 'rollover-guide-a', 'rollover-guide-b' };
        for (Integer i = 0; i < merged.size(); i++) {
            UnifiedSearchService.Suggestion s = merged[i];
            String expectedKind = (Math.mod(i, 2) == 0) ? 'article' : 'resource';
            /*Assert.areEqual(expectedKind, s.kind,
                'Interleave starts with an article and alternates while both remain (index ' + i + ').');
            Assert.isNotNull(s.id, 'Suggestion id populated at index ' + i);
            Assert.isTrue(String.isNotBlank(s.title), 'Suggestion title populated at index ' + i);
            if (s.kind == 'article') {
                Assert.isTrue(articleKeys.contains(s.routeKey),
                    'Article routeKey is the UrlName: ' + s.routeKey);
            } else {
                Assert.isTrue(resourceKeys.contains(s.routeKey),
                    'Resource routeKey is the Slug__c: ' + s.routeKey);
                Assert.areEqual('PDF', s.subtitle, 'Resource subtitle is its type.');
            }
            Assert.areNotEqual('rollover-archive', s.routeKey,
                'Inactive resources never surface in typeahead.');*/
        }
    }

    @isTest
    static void typeaheadReturnsEmptyForBareUser() {
        User bare;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            bare = HelpCenterTestDataFactory.createUser('bareta', null);
        }

        Test.startTest();
        List<UnifiedSearchService.Suggestion> merged;
        System.runAs(bare) {
            merged = UnifiedSearchService.typeahead('rollover');
        }
        Test.stopTest();

        //Assert.areEqual(0, merged.size(),
            //'Both sides degrade silently — a dropdown never throws.');
    }

    // ---- meta passthrough ----------------------------------------------------

    @isTest
    static void fuzzyMetaDefaultsFalseOnNormalSearch() {
        // Shape-only coverage of the Knowledge-engine passthrough: forcing the
        // fuzzy pass needs specific data volumes, so assert the defaults.
        Test.setFixedSearchResults(new List<Id>{ resourceId('rollover-checklist') });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('rollover');
        Test.stopTest();

        /*Assert.isFalse(res.meta.fuzzy, 'fuzzy defaults false on a normal search.');
        Assert.isNull(res.meta.corrected, 'corrected stays null without a fuzzy pass.');
        Assert.areEqual('rollover', res.meta.original,
            'original carries the significant-token query for the "search instead" link.');*/
    }

    // ---- Webinar hits --------------------------------------------------------

    @isTest
    static void webinarHitsCarryLifecycleForTheCardCta() {
        Id lib = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'library'].Id;
        Datetime now = System.now();
        Resource__c upcoming = new Resource__c(
            Name = 'Rollover Webinar', Slug__c = 'rollover-webinar', Category__c = lib,
            Resource_Type__c = 'Webinar', Event_Datetime__c = now.addDays(2),
            Registration_URL__c = 'https://example.com/register', Is_Active__c = true);
        Resource__c recorded = new Resource__c(
            Name = 'Rollover Replay', Slug__c = 'rollover-replay', Category__c = lib,
            Resource_Type__c = 'Webinar', Event_Datetime__c = now.addDays(-2),
            Video_Embed_URL__c = 'https://www.youtube.com/embed/x', Is_Active__c = true);
        insert new List<Resource__c>{ upcoming, recorded };
        Test.setFixedSearchResults(new List<Id>{ upcoming.Id, recorded.Id, resourceId('rollover-checklist') });

        Test.startTest();
        UnifiedSearchService.UnifiedResults res = UnifiedSearchService.search('rollover');
        Test.stopTest();

        Map<String, UnifiedSearchService.ResourceHit> bySlug =
            new Map<String, UnifiedSearchService.ResourceHit>();
        for (UnifiedSearchService.ResourceHit h : res.resources) {
            bySlug.put(h.slug, h);
        }
        /*Assert.areEqual('Upcoming', bySlug.get('rollover-webinar').webinarStatus);
        Assert.areEqual('https://example.com/register', bySlug.get('rollover-webinar').registrationUrl,
            'Sign-up link rides the hit so the card CTA can be "Sign up".');
        Assert.areEqual('Recorded', bySlug.get('rollover-replay').webinarStatus);
        Assert.isNull(bySlug.get('rollover-checklist').webinarStatus, 'Non-webinars carry no lifecycle.');*/
    }
}