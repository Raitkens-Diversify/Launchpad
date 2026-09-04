/**
 * Tests for NexSKnowledgeController.
 *
 * Knowledge test data is built by inserting draft Knowledge__kav records,
 * assigning a Data Category to each, and publishing them with
 * KbManagement.PublishingService so they satisfy the controller's
 * PublishStatus='Online' filter.
 *
 * Note: this requires Lightning Knowledge enabled and the Help_Topics data
 * category group present in the org (both are prerequisites for the feature).
 */
@IsTest
private class NexSKnowledgeControllerTest {

    private static final String LANG = 'en_US';

    @TestSetup
    static void setup() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
        // Three published articles across two categories; one featured.
        publishArticle('Getting Started With NexS', 'getting-started-with-nexs',
            'How to get going.', 'onboarding setup welcome', true, 'Getting_Started');
        publishArticle('Creating a Case', 'creating-a-case',
            'Open and route a case.', 'case task ticket', false, 'Cases_and_Tasks');
        publishArticle('Resolving Envelope Errors', 'resolving-envelope-errors',
            'Fix common envelope issues.', 'wizard envelope error', true, 'Wizard_and_Envelopes');
    }

    /** Insert a draft, assign a category, publish it online. */
    static void publishArticle(String title, String urlName, String summary,
                               String keywords, Boolean featured, String category) {
        publishArticle(title, urlName, summary, keywords, featured, category, null);
    }

    /** Variant with an authored Suggested Articles list (URL names, one per line). */
    static void publishArticle(String title, String urlName, String summary,
                               String keywords, Boolean featured, String category,
                               String suggested) {
        Knowledge__kav kav = new Knowledge__kav(
            Title = title,
            UrlName = urlName,
            Summary = summary,
            Language = LANG,
            Keywords__c = keywords,
            Featured__c = featured,
            Suggested_Articles__c = suggested
        );
        insert kav;

        insert new Knowledge__DataCategorySelection(
            ParentId = kav.Id,
            DataCategoryGroupName = 'Help_Topics',
            DataCategoryName = category
        );

        Knowledge__kav refreshed = [
            SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :kav.Id LIMIT 1
        ];
        KbManagement.PublishingService.publishArticle(refreshed.KnowledgeArticleId, true);
    }

    /** SOSL returns no rows in tests unless we seed fixed results. */
    static List<Id> seedFixedSearchResults() {
        List<Id> ids = new List<Id>();
        for (Knowledge__kav k : [SELECT Id FROM Knowledge__kav WHERE PublishStatus = 'Online']) {
            ids.add(k.Id);
        }
        Test.setFixedSearchResults(ids);
        return ids;
    }

    @IsTest
    static void searchReturnsPublishedMatches() {
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('nexs', null);
        Test.stopTest();

        // Only the article with "NexS" in its title scores above the relevance
        // threshold; the others were only in the (seeded) candidate set and have
        // no visible match, so ranking drops them.
        Assert.areEqual(1, results.size(), 'Only the relevant article survives ranking.');
        Assert.areEqual('Getting Started With NexS', results[0].title,
            'The title match ranks first.');
    }

    @IsTest
    static void blankTermReturnsAllPublished() {
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('', null);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Blank term returns every published article.');
        // Featured-first ordering: the two featured articles come before the non-featured one.
        Assert.isTrue(results[0].featured, 'Featured articles sort first.');
        Assert.isTrue(results[1].featured, 'Featured articles sort first.');
        Assert.isFalse(results[2].featured, 'Non-featured article sorts last.');
    }

    @IsTest
    static void searchWithCategoryExecutes() {
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('case', 'Cases_and_Tasks');
        Test.stopTest();

        // Test.setFixedSearchResults bypasses WITH DATA CATEGORY in test context,
        // so all seeded rows enter ranking; only "Creating a Case" (term in its
        // title and keywords) clears the relevance threshold. This proves the
        // category-scoped path builds, runs, and ranks without error.
        Assert.areEqual(1, results.size(), 'Only the matching article survives ranking.');
        Assert.areEqual('Creating a Case', results[0].title);
    }

    @IsTest
    static void listByCategory() {
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.getArticlesByCategory('Getting_Started');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One article lives in Getting_Started.');
        Assert.areEqual('Getting Started With NexS', results[0].title);
    }

    @IsTest
    static void getArticleReturnsBody() {
        Knowledge__kav kav = [
            SELECT Id FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND Title = 'Creating a Case' LIMIT 1
        ];

        Test.startTest();
        NexSKnowledgeController.ArticleDetail detail =
            NexSKnowledgeController.getArticle(kav.Id);
        Test.stopTest();

        Assert.areEqual('Creating a Case', detail.title);
        Assert.areEqual('Open and route a case.', detail.summary);
    }

    @IsTest
    static void getArticleByUrlNameReturnsBody() {
        Test.startTest();
        NexSKnowledgeController.ArticleDetail detail =
            NexSKnowledgeController.getArticleByUrlName('creating-a-case');
        Test.stopTest();

        Assert.areEqual('Creating a Case', detail.title, 'Slug lookup returns the matching article.');
        Assert.areEqual('creating-a-case', detail.urlName);
        Assert.areEqual('Open and route a case.', detail.summary);
    }

    @IsTest
    static void getArticleByUrlNameUnknownThrows() {
        Test.startTest();
        try {
            NexSKnowledgeController.getArticleByUrlName('no-such-slug');
            Assert.fail('Expected an exception for an unknown url name.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @IsTest
    static void subtopicArticlesReturnedWithSectionLabels() {
        // An article filed under a subtopic is returned by its parent-topic
        // query (BELOW semantics) and carries the subtopic as its section;
        // articles filed on the topic itself have no section.
        publishArticle('Creating Your First Case', 'creating-your-first-case',
            'Step-by-step case creation.', 'case create new', false, 'Creating_Cases');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.getArticlesByCategory('Cases_and_Tasks');
        Test.stopTest();

        Assert.areEqual(2, results.size(),
            'Topic query includes articles filed under its subtopics.');
        for (NexSKnowledgeController.ArticleSummary s : results) {
            if (s.urlName == 'creating-your-first-case') {
                Assert.areEqual('Creating Cases', s.section,
                    'Subtopic article carries its subtopic label as the section.');
                Assert.areEqual(0, s.sectionOrder, 'First subtopic in taxonomy order.');
            } else {
                Assert.isNull(s.section, 'Topic-level article has no section.');
            }
        }
    }

    @IsTest
    static void suggestionsAutoSameTopic() {
        // A second article in the same topic becomes the automatic suggestion.
        publishArticle('Closing a Case', 'closing-a-case',
            'Wrap up a case.', 'case close', false, 'Cases_and_Tasks');
        Knowledge__kav kav = [
            SELECT Id FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND Title = 'Creating a Case' LIMIT 1
        ];

        Test.startTest();
        NexSKnowledgeController.ArticleDetail detail =
            NexSKnowledgeController.getArticle(kav.Id);
        Test.stopTest();

        Assert.areEqual(1, detail.suggestions.size(), 'Same-topic article is suggested.');
        Assert.areEqual('Closing a Case', detail.suggestions[0].title);
        for (NexSKnowledgeController.ArticleSummary s : detail.suggestions) {
            Assert.areNotEqual(kav.Id, s.id, 'The open article never suggests itself.');
        }
    }

    @IsTest
    static void suggestionsAuthoredOverrideComesFirstThenTopUp() {
        // Authored picks (cross-topic, with a bogus line that must drop out)
        // come first in authored order; same-topic articles top the list up.
        publishArticle('Suggestion Source', 'suggestion-source',
            'Has curated suggestions.', 'curated', false, 'Getting_Started',
            'resolving-envelope-errors\ncreating-a-case\nnot-a-real-article');
        Knowledge__kav kav = [
            SELECT Id FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND Title = 'Suggestion Source' LIMIT 1
        ];

        Test.startTest();
        NexSKnowledgeController.ArticleDetail detail =
            NexSKnowledgeController.getArticle(kav.Id);
        Test.stopTest();

        Assert.areEqual(3, detail.suggestions.size(),
            'Two authored picks plus the same-topic top-up.');
        Assert.areEqual('resolving-envelope-errors', detail.suggestions[0].urlName,
            'Authored picks keep their authored order.');
        Assert.areEqual('creating-a-case', detail.suggestions[1].urlName,
            'Authored picks keep their authored order.');
        Assert.areEqual('getting-started-with-nexs', detail.suggestions[2].urlName,
            'Same-topic article tops up after authored picks.');
    }

    @IsTest
    static void getArticleNullThrows() {
        Test.startTest();
        try {
            NexSKnowledgeController.getArticle(null);
            Assert.fail('Expected an exception for a null id.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @IsTest
    static void getCategoriesReturnsTaxonomy() {
        Test.startTest();
        List<NexSKnowledgeController.CategoryInfo> cats =
            NexSKnowledgeController.getCategories();
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (NexSKnowledgeController.CategoryInfo c : cats) {
            names.add(c.name);
        }
        Assert.isTrue(names.contains('Getting_Started'), 'Taxonomy should include Getting_Started.');
        Assert.isTrue(names.contains('Data_Model'), 'Taxonomy should include Data_Model.');
    }

    @IsTest
    static void unknownCategoryRejected() {
        Test.startTest();
        try {
            NexSKnowledgeController.getArticlesByCategory('Not_A_Real_Category');
            Assert.fail('Expected an exception for an unknown category.');
        } catch (AuraHandledException e) {
            // expected — injection guard rejected the token
        }
        Test.stopTest();
    }

    @IsTest
    static void punctuationOnlyTermReturnsEmpty() {
        // A punctuation-only term sanitizes to blank → empty result, no SOSL, no error.
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('%%%', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'A punctuation-only term should yield nothing.');
    }

    @IsTest
    static void stopwordOnlyWithNoTitleMatchReturnsEmpty() {
        // A stopword-only query runs the title-phrase fallback; with no title
        // containing "how do i", it still yields nothing (no all-fields flood).
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('how do i', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(),
            'A stopword-only query with no matching title yields nothing.');
    }

    @IsTest
    static void stopwordPhraseMatchesTitle() {
        // "how to" is all stopwords, but autocomplete should still surface
        // articles whose TITLE contains the typed phrase.
        publishArticle('How To Reset Your Password', 'how-to-reset-password',
            'Steps to reset.', 'password reset', false, 'Getting_Started');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('how to', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the how-to article title contains the phrase.');
        Assert.areEqual('How To Reset Your Password', results[0].title);
    }

    @IsTest
    static void stopwordFallbackPrefersTitlePrefix() {
        // Among title matches, one that STARTS with the phrase ranks first.
        publishArticle('How To Enroll', 'how-to-enroll',
            'Enrollment steps.', 'enroll', false, 'Getting_Started');
        publishArticle('Steps: How To Begin', 'steps-how-to-begin',
            'Beginning steps.', 'begin', false, 'Getting_Started');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('how to', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Both titles contain the phrase.');
        Assert.areEqual('How To Enroll', results[0].title,
            'A title that starts with the phrase ranks above one that merely contains it.');
    }

    @IsTest
    static void shortNoiseTermReturnsEmpty() {
        // Single-character and stopword tokens are both dropped.
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('a i', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Tiny/stopword-only tokens should yield nothing.');
    }

    // ---- Relevance ranking ---------------------------------------------------

    @IsTest
    static void titleMatchOutranksSummaryMatch() {
        // Same term in one article's title vs another's summary → title wins.
        publishArticle('Sasquatch Overview', 'sasquatch-overview',
            'General notes.', 'cryptid', false, 'Getting_Started');
        publishArticle('Field Guide', 'field-guide',
            'A sasquatch was reportedly seen here.', 'wildlife', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('sasquatch', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Both articles mention the term and clear the threshold.');
        Assert.areEqual('Sasquatch Overview', results[0].title,
            'The title match outranks the summary-only match.');
    }

    @IsTest
    static void weakBodyOnlyMatchIsDropped() {
        // A term that appears in NO returned field scores only the tiny body
        // signal, which is below the relevance threshold.
        publishArticle('Neutral Title', 'neutral-title',
            'Nothing notable here.', 'plain', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Neutral Title' LIMIT 1].Id
        });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('zzqqx', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(),
            'A body-only match on an irrelevant term is below the threshold.');
    }

    @IsTest
    static void fullQueryCoverageOutranksPartial() {
        // Article matching both query words beats one matching only the first.
        publishArticle('Alpha Bravo', 'alpha-bravo',
            'Covers both.', 'x', false, 'Getting_Started');
        publishArticle('Alpha Charlie', 'alpha-charlie',
            'Covers one.', 'y', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Alpha Bravo' LIMIT 1].Id,
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Alpha Charlie' LIMIT 1].Id
        });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('alpha bravo', null);
        Test.stopTest();

        Assert.areEqual('Alpha Bravo', results[0].title,
            'Matching more of the query ranks higher.');
    }

    @IsTest
    static void misspelledTermStillFindsArticle() {
        // No exact recall (no seeded SOSL results) → the fuzzy pool pass catches
        // the typo via edit distance.
        publishArticle('Custodian Overview', 'custodian-overview',
            'About custodians.', 'custodian minor asset', false, 'Getting_Started');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('custdian', null);  // missing 'o'
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Fuzzy matching recovers the misspelled term.');
        Assert.areEqual('Custodian Overview', results[0].title);
    }

    @IsTest
    static void shortWordDoesNotFuzzyMatchUnrelatedWord() {
        // Regression: "talk" (4 chars) must NOT be typo-corrected to "task".
        // Short words get no fuzzy tolerance under the conservative policy.
        publishArticle('Main Track Task', 'main-track-task',
            'About tasks.', 'task workflow', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{});  // no exact recall — only the fuzzy pass could match

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('talk', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'A 4-char word is not corrected into an unrelated word.');
    }

    @IsTest
    static void fuzzyRequiresSharedPrefix() {
        // "brown" vs "crown" is edit distance 1, but they differ in the leading
        // prefix, so the anchored-prefix rule blocks the correction.
        publishArticle('Crown Details', 'crown-details',
            'About crowns.', 'crown', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{});

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('brown', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'A differing leading prefix blocks the fuzzy correction.');
    }

    @IsTest
    static void fiveCharTypoStillCorrectsWithSharedPrefix() {
        // "logon" -> "login": 5 chars, shared "lo" prefix, distance 1 — still fuzzy-matches.
        publishArticle('Login Help', 'login-help',
            'Signing in.', 'login', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{});

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('logon', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'A 5-char typo with a shared prefix still corrects.');
        Assert.areEqual('Login Help', results[0].title);
    }

    @IsTest
    static void popularityBreaksRelevanceTies() {
        // Two articles with identical text relevance; the more-viewed wins.
        publishArticle('Signal Bar', 'signal-bar', 'One.', 'x', false, 'Getting_Started');
        publishArticle('Signal Foo', 'signal-foo', 'Two.', 'y', false, 'Getting_Started');
        Knowledge__kav bar = [
            SELECT Id, KnowledgeArticleId FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND Title = 'Signal Bar' LIMIT 1
        ];
        Knowledge__kav foo = [
            SELECT Id, KnowledgeArticleId FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND Title = 'Signal Foo' LIMIT 1
        ];
        // "Signal Bar" would win the alphabetical tiebreak; give "Signal Foo" the views.
        insert new Article_View__c(
            User_Article_Key__c = 'u_' + foo.KnowledgeArticleId,
            Article_Id__c = foo.KnowledgeArticleId,
            Article_Title__c = 'Signal Foo',
            View_Count__c = 500
        );
        Test.setFixedSearchResults(new List<Id>{ bar.Id, foo.Id });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('signal', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Both articles match the term.');
        Assert.areEqual('Signal Foo', results[0].title,
            'The more-viewed article wins the tie via the popularity signal.');
    }

    @IsTest
    static void editWithinRespectsBudget() {
        Assert.isTrue(NexSKnowledgeController.editWithin('custodian', 'custdian', 2),
            'One deletion is within budget.');
        Assert.isTrue(NexSKnowledgeController.editWithin('case', 'cse', 1),
            'One deletion within budget.');
        Assert.isFalse(NexSKnowledgeController.editWithin('envelope', 'xyzabc', 2),
            'Wildly different words are not near matches.');
    }

    @IsTest
    static void tokenizeSplitsAndLowercases() {
        List<String> words = NexSKnowledgeController.tokenize('Hello, World-99!');
        Assert.areEqual(new List<String>{ 'hello', 'world', '99' }, words,
            'Text is lowercased and split on non-alphanumerics.');
        Assert.areEqual(0, NexSKnowledgeController.tokenize(null).size(),
            'Null text yields no tokens.');
    }

    @IsTest
    static void shortTokenDoesNotPrefixMatch() {
        // A 2-char fragment must match exactly, never prefix — "ca" must not hit
        // "Cadence" (the class of bug where "at" matched "Atlas").
        publishArticle('Cadence Basics', 'cadence-basics',
            'About cadences.', 'cadence grouping', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Cadence Basics' LIMIT 1].Id
        });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('ca', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'A short fragment must not prefix-match a longer word.');
    }

    @IsTest
    static void partialQueryNoiseIsDropped() {
        // The reported bug: "How to win at life" returned unrelated articles.
        // Stopwords drop how/to/at; win/life match nothing → nothing relevant.
        publishArticle('Atlas Guide', 'atlas-guide',
            'All about Atlas.', 'atlas platform', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Atlas Guide' LIMIT 1].Id
        });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('how to win at life', null);
        Test.stopTest();

        Assert.areEqual(0, results.size(),
            'A query whose real words match no article returns nothing.');
    }

    @IsTest
    static void bodyOnlyMatchDoesNotInflateCoverage() {
        // Article matching both query words in real fields must outrank one that
        // matches only one word (the other coming only from the body index).
        publishArticle('Zeta Omega Combined', 'zeta-omega-combined',
            'Covers both terms.', 'x', false, 'Getting_Started');
        publishArticle('Zeta Solo', 'zeta-solo',
            'Covers one term.', 'y', false, 'Getting_Started');
        Test.setFixedSearchResults(new List<Id>{
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Zeta Omega Combined' LIMIT 1].Id,
            [SELECT Id FROM Knowledge__kav
             WHERE PublishStatus = 'Online' AND Title = 'Zeta Solo' LIMIT 1].Id
        });

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('zeta omega', null);
        Test.stopTest();

        Assert.areEqual('Zeta Omega Combined', results[0].title,
            'Real coverage of both words outranks a one-word (plus body) match.');
    }

    // ---- Synonyms (Phase 2) --------------------------------------------------
    // testSynonymRows is the test seam: unset (default) => empty synonym map, so
    // the baseline suite above runs exactly as before (empty table = no change).

    @IsTest
    static void synonymSurfacesRelatedArticleBelowExact() {
        // Acceptance: "trustee" surfaces an article whose title has only
        // "fiduciary", ranked below an exact "trustee" match.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'trustee', Synonyms__c = 'fiduciary', Bidirectional__c = true)
        };
        publishArticle('Trustee Basics', 'trustee-basics', 'About trustees.', 'help', false, 'Getting_Started');
        publishArticle('Fiduciary Responsibilities', 'fiduciary-responsibilities', 'About fiduciaries.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('trustee', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Exact and synonym matches both surface.');
        Assert.areEqual('Trustee Basics', results[0].title, 'The exact term outranks the synonym.');
        Assert.areEqual('Fiduciary Responsibilities', results[1].title, 'The synonym-only match surfaces below it.');
    }

    @IsTest
    static void synonymExpansionIsBidirectional() {
        // The reverse direction: searching the synonym finds the term's article.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'trustee', Synonyms__c = 'fiduciary', Bidirectional__c = true)
        };
        publishArticle('Trustee Basics', 'trustee-basics', 'About trustees.', 'help', false, 'Getting_Started');
        publishArticle('Fiduciary Responsibilities', 'fiduciary-responsibilities', 'About fiduciaries.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('fiduciary', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Searching the synonym finds both.');
        Assert.areEqual('Fiduciary Responsibilities', results[0].title, 'The exact term (now fiduciary) ranks first.');
        Assert.areEqual('Trustee Basics', results[1].title, 'Trustee surfaces via the reverse synonym link.');
    }

    @IsTest
    static void deactivatedSynonymStopsExpanding() {
        // Admin Console "delete" = Is_Active__c=false; the loader must ignore
        // the row, so the synonym-only article no longer surfaces.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'trustee', Synonyms__c = 'fiduciary',
                Bidirectional__c = true, Is_Active__c = false)
        };
        publishArticle('Trustee Basics', 'trustee-basics', 'About trustees.', 'help', false, 'Getting_Started');
        publishArticle('Fiduciary Responsibilities', 'fiduciary-responsibilities', 'About fiduciaries.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('trustee', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'A deactivated synonym must not expand the query.');
        Assert.areEqual('Trustee Basics', results[0].title, 'Only the exact match surfaces.');
    }

    @IsTest
    static void legacySynonymRowsWithNoActiveValueStayActive() {
        // The 12 pre-existing records were deployed before Is_Active__c existed;
        // a null value must behave as active so they keep working.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'trustee', Synonyms__c = 'fiduciary',
                Bidirectional__c = true)   // Is_Active__c deliberately unset
        };
        publishArticle('Trustee Basics', 'trustee-basics', 'About trustees.', 'help', false, 'Getting_Started');
        publishArticle('Fiduciary Responsibilities', 'fiduciary-responsibilities', 'About fiduciaries.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('trustee', null);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'A row without an explicit active value keeps expanding.');
    }

    @IsTest
    static void multiWordSynonymExpandsToSignificantToken() {
        // "sign in" must contribute only its significant token "sign" ("in" is a
        // stopword), so a query for "login" finds a "Sign In" titled article.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'login', Synonyms__c = 'sign in', Bidirectional__c = true)
        };
        publishArticle('Sign In Steps', 'sign-in-steps', 'How to sign in.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('login', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'The multi-word synonym token "sign" matched.');
        Assert.areEqual('Sign In Steps', results[0].title);
    }

    @IsTest
    static void nonBidirectionalSynonymIsOneWay() {
        // term -> synonym only. Searching the synonym must NOT expand back to the
        // term, so a "login"-only article stays hidden from a "sign" search.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'login', Synonyms__c = 'sign in', Bidirectional__c = false)
        };
        publishArticle('Login Help', 'login-help', 'Logging in.', 'help', false, 'Getting_Started');
        publishArticle('Sign In Steps', 'sign-in-steps', 'How to sign in.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('sign', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the exact "sign" match; no reverse expansion to login.');
        Assert.areEqual('Sign In Steps', results[0].title);
    }

    @IsTest
    static void synonymOnlyMatchCountsTowardCoverage() {
        // A two-word query where one word matches only via a synonym still earns
        // full coverage, so it outranks an article that covers only one word.
        NexSKnowledgeController.testSynonymRows = new List<Search_Synonym__mdt>{
            new Search_Synonym__mdt(Term__c = 'charge', Synonyms__c = 'fee', Bidirectional__c = true)
        };
        publishArticle('Account Fee Guide', 'account-fee-guide', 'Account fees.', 'help', false, 'Getting_Started');
        publishArticle('Account Basics', 'account-basics', 'Account overview.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('account charge', null);
        Test.stopTest();

        Assert.areEqual('Account Fee Guide', results[0].title,
            'Synonym-covered second word beats a one-word (plus body) match.');
    }

    @IsTest
    static void emptySynonymTableLeavesBehaviorUnchanged() {
        // Default seam (testSynonymRows unset) => empty map => identical to today.
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('nexs', null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'With no synonyms, ranking is unchanged.');
        Assert.areEqual('Getting Started With NexS', results[0].title);
    }

    // ---- Typeahead + two-tier UX (Phase 3) -----------------------------------

    @IsTest
    static void typeaheadRanksTitlePrefixBeforeKeyword() {
        // "Creating a Case" matches in the title; "Billing Overview" only in
        // keywords — the title hit must come first, and rows are lightweight.
        publishArticle('Billing Overview', 'billing-overview',
            'Understand billing.', 'case invoice', false, 'Cases_and_Tasks');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> hits =
            NexSKnowledgeController.typeahead('case', null);
        Test.stopTest();

        Assert.isTrue(hits.size() >= 2, 'Both the title and keyword matches return.');
        Assert.areEqual('Creating a Case', hits[0].title, 'Title-prefix match ranks first.');
        Assert.isNull(hits[0].summary, 'Typeahead rows are lightweight (Id/Title/UrlName only).');
        Assert.isNotNull(hits[0].urlName, 'UrlName is populated for navigation.');
        Boolean sawKeywordHit = false;
        for (NexSKnowledgeController.ArticleSummary h : hits) {
            if (h.title == 'Billing Overview') { sawKeywordHit = true; }
        }
        Assert.isTrue(sawKeywordHit, 'Keyword-only match still surfaces, after title hits.');
    }

    @IsTest
    static void typeaheadEmptyWhenNoTitleMatches() {
        // A stopword-only query now falls back to a title-phrase match (like the
        // full engine), so "how to" is empty here only because no @TestSetup title
        // contains "how to" — not because the tokens are empty. The positive case
        // is covered by typeaheadStopwordQueryMatchesTitlePhrase.
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> hits =
            NexSKnowledgeController.typeahead('how to', null);
        Test.stopTest();

        Assert.areEqual(0, hits.size(), 'No published title contains the phrase — nothing to show.');
    }

    @IsTest
    static void typeaheadStopwordQueryMatchesTitlePhrase() {
        // Regression: "How to" is all stopwords, but typeahead must still surface
        // titles containing the literal phrase, matching what Enter (full search)
        // returns.
        publishArticle('How to Reset Password', 'how-to-reset-password',
            'Reset your password.', 'password', false, 'Getting_Started');

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> hits =
            NexSKnowledgeController.typeahead('how to', null);
        Test.stopTest();

        Assert.areEqual(1, hits.size(), 'The stopword phrase matches the title.');
        Assert.areEqual('How to Reset Password', hits[0].title);
        Assert.isNull(hits[0].summary, 'Typeahead rows stay lightweight (Id/Title/UrlName only).');
        Assert.isNotNull(hits[0].urlName);
    }

    @IsTest
    static void searchRankedFlagsFuzzyAndDisableFuzzyBypasses() {
        publishArticle('Fiduciary Guide', 'fiduciary-guide',
            'About fiduciary duties.', 'fiduciary trustee', false, 'Getting_Started');
        // Empty SOSL recall forces the typo pass (SOQL pool) to be the source.
        Test.setFixedSearchResults(new List<Id>{});

        Test.startTest();
        NexSKnowledgeController.SearchResult fuzzy =
            NexSKnowledgeController.searchRanked('fiduciory', null, false);
        NexSKnowledgeController.SearchResult off =
            NexSKnowledgeController.searchRanked('fiduciory', null, true);
        Test.stopTest();

        Assert.isTrue(fuzzy.fuzzy, 'A typo-pass result flags fuzzy.');
        Assert.areEqual('fiduciary', fuzzy.corrected, 'Correction resolves the typo.');
        Assert.areEqual(1, fuzzy.articles.size(), 'The fuzzy-matched article surfaces.');
        Assert.isFalse(off.fuzzy, 'disableFuzzy skips the typo pass.');
        Assert.areEqual(0, off.articles.size(),
            'With fuzzy off and no exact recall, nothing surfaces.');
    }

    @IsTest
    static void getFallbackArticlesLeadsWithFeatured() {
        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> fb =
            NexSKnowledgeController.getFallbackArticles(null);
        Test.stopTest();

        Assert.isFalse(fb.isEmpty(), 'Fallback returns articles for a zero-result state.');
        Assert.isTrue(fb[0].featured, 'Featured articles lead the fallback list.');
        Assert.isTrue(fb.size() <= 5, 'Capped at FALLBACK_COUNT.');
    }

    // ---- Bigram phrase scoring (Phase 4) -------------------------------------

    @IsTest
    static void bigramNearPhraseOutranksScatteredWords() {
        // "Password Reset" (adjacent reversed pair) earns the title bigram boost;
        // an article with both words scattered across title + keywords does not.
        publishArticle('Password Reset', 'password-reset',
            'Reset it.', 'help', false, 'Getting_Started');
        publishArticle('Account Password Options', 'account-password-options',
            'Options.', 'reset billing', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('reset password', null);
        Test.stopTest();

        Assert.areEqual('Password Reset', results[0].title,
            'The near-phrase (bigram) title outranks scattered double-word matches.');
    }

    @IsTest
    static void verbatimPhraseOutranksReversedBigram() {
        // A verbatim "Reset Password" title beats the reversed "Password Reset"
        // bigram — verbatim (25) > bigram (15), never both.
        publishArticle('Reset Password Guide', 'reset-password-guide',
            'Guide.', 'help', false, 'Getting_Started');
        publishArticle('Password Reset', 'password-reset',
            'Reset it.', 'help', false, 'Getting_Started');
        seedFixedSearchResults();

        Test.startTest();
        List<NexSKnowledgeController.ArticleSummary> results =
            NexSKnowledgeController.searchArticles('reset password', null);
        Test.stopTest();

        Assert.areEqual('Reset Password Guide', results[0].title,
            'Verbatim phrase outranks the reversed-order bigram.');
        Assert.areEqual('Password Reset', results[1].title,
            'The reversed bigram still surfaces, just below verbatim.');
    }

    @IsTest
    static void supportSettingsReadFromCmdtWithoutThrowing() {
        // Values come from the org's Resource_Center_Setting__mdt.Default record
        // (visible to tests without SeeAllData), so assert shape, not content —
        // admins may re-point the mailbox without a deploy.
        NexSKnowledgeController.SupportSettings dto =
            NexSKnowledgeController.getSupportSettings();
        Assert.isNotNull(dto, 'Settings DTO always returns');
    }
}