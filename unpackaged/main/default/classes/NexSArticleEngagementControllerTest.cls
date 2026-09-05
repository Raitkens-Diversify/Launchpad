/**
 * Tests for NexSArticleEngagementController.
 *
 * Knowledge test data follows the NexSKnowledgeControllerTest pattern: insert
 * a draft Knowledge__kav, assign a Data Category, publish via
 * KbManagement.PublishingService so the controller's published filter matches.
 *
 * Vote assertions use this org's star voting mode: the thumbs UI maps
 * Up -> '5' and Down -> '1'.
 */
@IsTest
private class NexSArticleEngagementControllerTest {

    // ---- Knowledge User test identity ------------------------------------------
    // Knowledge__kav DML, KbManagement publishing and the Knowledge__kav
    // create/update describes all require the Knowledge User feature license
    // (User.UserPermissionsKnowledgeUser). No permission set can grant it and the
    // deploying user need not hold it, so every test runs as a dedicated licensed
    // user created here. @TestSetup and each test method are separate contexts,
    // so kbUser() re-queries that user by alias before each System.runAs.
    private static final String KB_ALIAS = 'nxegusr';
    private static final String KB_DOMAIN = '@nxeg.test.invalid';

    static User makeKnowledgeUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'nxeg' + Math.abs(Crypto.getRandomLong());
        User u = new User(
            Alias = KB_ALIAS,
            Email = uniq + KB_DOMAIN,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Knowledge',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + KB_DOMAIN,
            UserPermissionsKnowledgeUser = true
        );
        insert u;
        grantIfMissing(u.Id, 'NexSHelpCenter');
        grantIfMissing(u.Id, 'Resource_Center_Admin');
        return u;
    }

    /** Assign a permission set (when the org ships it) unless automation already did. */
    static void grantIfMissing(Id userId, String permissionSetName) {
        List<PermissionSet> sets = [
            SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1
        ];
        if (sets.isEmpty()) {
            return;
        }
        Integer assigned = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :sets[0].Id
        ];
        if (assigned == 0) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = sets[0].Id);
        }
    }

    /** The licensed user created in @TestSetup (re-queried per test context). */
    static User kbUser() {
        String emailPattern = '%' + KB_DOMAIN;
        return [
            SELECT Id FROM User
            WHERE Alias = :KB_ALIAS AND Email LIKE :emailPattern
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @TestSetup
    static void setup() {
        System.runAs(makeKnowledgeUser()) {
            Knowledge__kav kav = new Knowledge__kav(
                Title = 'Engagement Target',
                UrlName = 'engagement-target',
                Summary = 'Article to engage with.',
                Language = 'en_US'
            );
            insert kav;
            insert new Knowledge__DataCategorySelection(
                ParentId = kav.Id,
                DataCategoryGroupName = 'Help_Topics',
                DataCategoryName = 'Getting_Started'
            );
            Knowledge__kav refreshed = [
                SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :kav.Id LIMIT 1
            ];
            KbManagement.PublishingService.publishArticle(refreshed.KnowledgeArticleId, true);
        }
    }

    static Knowledge__kav published() {
        return [
            SELECT Id, KnowledgeArticleId, Title FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND UrlName = 'engagement-target'
            LIMIT 1
        ];
    }

    @IsTest
    static void castVoteUpCreatesNativeVote() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            String saved = NexSArticleEngagementController.castVote(kav.Id, 'Up');
            Test.stopTest();

            Assert.areEqual('Up', saved);
            List<Vote> votes = [SELECT Type, ParentId FROM Vote WHERE ParentId = :kav.KnowledgeArticleId];
            Assert.areEqual(1, votes.size(), 'One vote lands on the Knowledge__ka parent.');
            Assert.areEqual('5', votes[0].Type, 'Thumbs-up stores as a 5-star vote in this org.');

            NexSArticleEngagementController.EngagementState state =
                NexSArticleEngagementController.getEngagement(kav.Id);
            Assert.areEqual('Up', state.voteType, 'getEngagement maps the stored star back to a thumb.');
        }
    }

    @IsTest
    static void castVoteChangeKeepsSingleVote() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            NexSArticleEngagementController.castVote(kav.Id, 'Up');
            NexSArticleEngagementController.castVote(kav.Id, 'Down');
            Test.stopTest();

            List<Vote> votes = [SELECT Type FROM Vote WHERE ParentId = :kav.KnowledgeArticleId];
            Assert.areEqual(1, votes.size(), 'Changing a vote never duplicates it.');
            Assert.areEqual('1', votes[0].Type, 'Thumbs-down stores as a 1-star vote.');
        }
    }

    @IsTest
    static void castVoteSameTypeIsNoop() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            NexSArticleEngagementController.castVote(kav.Id, 'Up');
            NexSArticleEngagementController.castVote(kav.Id, 'Up');
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Vote WHERE ParentId = :kav.KnowledgeArticleId]);
        }
    }

    @IsTest
    static void castVoteRejectsInvalidType() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();
            try {
                NexSArticleEngagementController.castVote(kav.Id, 'Sideways');
                Assert.fail('Expected an exception for an invalid vote type.');
            } catch (AuraHandledException e) {
                // expected
            }
        }
    }

    @IsTest
    static void draftArticleRejected() {
        System.runAs(kbUser()) {
            Knowledge__kav draft = new Knowledge__kav(
                Title = 'Draft Only',
                UrlName = 'draft-only',
                Language = 'en_US'
            );
            insert draft;

            try {
                NexSArticleEngagementController.castVote(draft.Id, 'Up');
                Assert.fail('Expected an exception for an unpublished article.');
            } catch (AuraHandledException e) {
                // expected — published filter blocks draft probing
            }
        }
    }

    @IsTest
    static void getEngagementUnvotedReturnsNull() {
        System.runAs(kbUser()) {
            NexSArticleEngagementController.EngagementState state =
                NexSArticleEngagementController.getEngagement(published().Id);
            Assert.isNull(state.voteType, 'No vote yet means a null thumb.');
        }
    }

    @IsTest
    static void submitFeedbackPersistsComment() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            NexSArticleEngagementController.submitFeedback(kav.Id, 'Down', 'Steps 3-4 are out of date.');
            Test.stopTest();

            Article_Feedback__c fb = [
                SELECT Article_Id__c, Article_Title__c, Vote_Type__c, Comment__c, Surface__c
                FROM Article_Feedback__c
            ];
            Assert.areEqual(kav.KnowledgeArticleId, fb.Article_Id__c, 'Feedback keys on the KA Id.');
            Assert.areEqual('Engagement Target', fb.Article_Title__c, 'Title denormalized server-side.');
            Assert.areEqual('Down', fb.Vote_Type__c);
            Assert.areEqual('Steps 3-4 are out of date.', fb.Comment__c);
            Assert.areEqual('Internal', fb.Surface__c, 'Non-community context logs as Internal.');
        }
    }

    @IsTest
    static void submitFeedbackRejectsBlankComment() {
        System.runAs(kbUser()) {
            try {
                NexSArticleEngagementController.submitFeedback(published().Id, 'Down', '  ');
                Assert.fail('Expected an exception for a blank comment.');
            } catch (AuraHandledException e) {
                // expected
            }
        }
    }

    @IsTest
    static void logViewCreatesThenIncrements() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            NexSArticleEngagementController.logView(kav.Id);
            NexSArticleEngagementController.logView(kav.Id);
            Test.stopTest();

            Article_View__c view = [
                SELECT User_Article_Key__c, Article_Id__c, Article_Title__c,
                    View_Count__c, Last_Viewed__c, Surface__c
                FROM Article_View__c
            ];
            Assert.areEqual(UserInfo.getUserId() + '_' + kav.KnowledgeArticleId,
                view.User_Article_Key__c, 'Key is userId_kaId.');
            Assert.areEqual(2, view.View_Count__c, 'Two views, one record.');
            Assert.areEqual(kav.KnowledgeArticleId, view.Article_Id__c);
            Assert.areEqual('Engagement Target', view.Article_Title__c);
            Assert.isNotNull(view.Last_Viewed__c);
            Assert.areEqual('Internal', view.Surface__c);
        }
    }

    @IsTest
    static void logViewIncrementsPreexistingRow() {
        System.runAs(kbUser()) {
            // Simulates the insert/insert race outcome: the row already exists
            // (with a stale title) when logView runs — it must update, not insert.
            Knowledge__kav kav = published();
            insert new Article_View__c(
                User_Article_Key__c = UserInfo.getUserId() + '_' + kav.KnowledgeArticleId,
                Article_Id__c = kav.KnowledgeArticleId,
                Article_Title__c = 'Stale Title',
                View_Count__c = 4,
                Last_Viewed__c = System.now().addDays(-1)
            );

            Test.startTest();
            NexSArticleEngagementController.logView(kav.Id);
            Test.stopTest();

            List<Article_View__c> views = [
                SELECT Article_Title__c, View_Count__c FROM Article_View__c
            ];
            Assert.areEqual(1, views.size(), 'Still one row per user+article.');
            Assert.areEqual(5, views[0].View_Count__c, 'Count incremented.');
            Assert.areEqual('Engagement Target', views[0].Article_Title__c, 'Title refreshed on view.');
        }
    }

    // ---- Search logging (enriched per Phase 1) -------------------------------
    // logSearch takes a JSON-serialized SearchLogEntry (string transport because
    // custom-type @AuraEnabled params arrive null in this org), returns the new
    // row Id (for click correlation), and is pure fire-and-forget: it never
    // throws — any failure returns null and logs nothing, so logging can't
    // break or block search.

    /** Build a serialized SearchLogEntry inline. */
    private static String entry(
        String term, Integer count, String topKavId, String type, String session
    ) {
        NexSArticleEngagementController.SearchLogEntry e =
            new NexSArticleEngagementController.SearchLogEntry();
        e.term = term;
        e.resultCount = count;
        e.topResultArticleId = topKavId;
        e.searchType = type;
        e.sessionKey = session;
        return JSON.serialize(e);
    }

    @IsTest
    static void logSearchStampsAllFields() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();

            Test.startTest();
            Id logId = NexSArticleEngagementController.logSearch(
                entry('  Reset Password?  ', 3, kav.Id, 'Full', 'sess-123')
            );
            Test.stopTest();

            Assert.isNotNull(logId, 'logSearch returns the new row Id for click correlation.');
            Article_Search__c row = [
                SELECT Term__c, Normalized_Query__c, Result_Count__c, Search_Type__c,
                    Session_Key__c, Top_Result_Article_Id__c, Top_Result_Title__c, Surface__c
                FROM Article_Search__c WHERE Id = :logId
            ];
            Assert.areEqual('Reset Password?', row.Term__c, 'Raw term is trimmed, punctuation kept.');
            Assert.areEqual('reset password', row.Normalized_Query__c,
                'Normalized query strips punctuation and lowercases via the engine tokenizer.');
            Assert.areEqual(3, row.Result_Count__c);
            Assert.areEqual('Full', row.Search_Type__c);
            Assert.areEqual('sess-123', row.Session_Key__c);
            Assert.areEqual(kav.KnowledgeArticleId, row.Top_Result_Article_Id__c,
                'Top result stored as the version-stable KA Id, not the kav version Id.');
            Assert.areEqual('Engagement Target', row.Top_Result_Title__c);
            Assert.areEqual('Internal', row.Surface__c);
        }
    }

    @IsTest
    static void logSearchDefaultsUnknownTypeAndNormalizesCount() {
        System.runAs(kbUser()) {
            Test.startTest();
            Id logId = NexSArticleEngagementController.logSearch(
                entry('custodian setup', -7, null, 'Bogus', null)
            );
            Test.stopTest();

            Article_Search__c row = [
                SELECT Search_Type__c, Result_Count__c, Top_Result_Article_Id__c, Session_Key__c
                FROM Article_Search__c WHERE Id = :logId
            ];
            Assert.areEqual('Full', row.Search_Type__c, 'Unknown search type falls back to Full.');
            Assert.areEqual(0, row.Result_Count__c, 'Negative counts normalize to zero.');
            Assert.isNull(row.Top_Result_Article_Id__c, 'No top result for a null id.');
            Assert.isNull(row.Session_Key__c, 'Blank session key stored as null.');
        }
    }

    @IsTest
    static void logSearchAcceptsTypeaheadStub() {
        System.runAs(kbUser()) {
            // Phase 3 wires typeahead click logging; the type is already accepted.
            Test.startTest();
            Id logId = NexSArticleEngagementController.logSearch(
                entry('cust', 5, null, 'Typeahead', 'sess-x')
            );
            Test.stopTest();
            Assert.areEqual('Typeahead',
                [SELECT Search_Type__c FROM Article_Search__c WHERE Id = :logId].Search_Type__c);
        }
    }

    @IsTest
    static void logSearchBlankOrNullReturnsNull() {
        System.runAs(kbUser()) {
            // Was: threw AuraHandledException on a blank term. Enriched per Phase 1
            // to fire-and-forget — blank/null now logs nothing and returns null.
            Test.startTest();
            Id blankId = NexSArticleEngagementController.logSearch(entry('   ', 3, null, 'Full', null));
            Id nullId = NexSArticleEngagementController.logSearch(null);
            Id garbageId = NexSArticleEngagementController.logSearch('{not json');
            Test.stopTest();

            Assert.isNull(blankId, 'Blank term logs nothing.');
            Assert.isNull(nullId, 'Null payload logs nothing.');
            Assert.isNull(garbageId, 'Malformed JSON logs nothing, never throws.');
            Assert.areEqual(0, [SELECT COUNT() FROM Article_Search__c], 'No rows written.');
        }
    }

    @IsTest
    static void logClickUpdatesRowInPlace() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();
            Id logId = NexSArticleEngagementController.logSearch(
                entry('engagement', 4, kav.Id, 'Full', 'sess-9')
            );

            Test.startTest();
            NexSArticleEngagementController.logClick(logId, kav.Id, 2);
            Test.stopTest();

            Article_Search__c row = [
                SELECT Clicked_Article_Id__c, Clicked_Article_Title__c, Clicked_Rank__c
                FROM Article_Search__c WHERE Id = :logId
            ];
            Assert.areEqual(kav.KnowledgeArticleId, row.Clicked_Article_Id__c,
                'Click keys on the version-stable KA Id.');
            Assert.areEqual('Engagement Target', row.Clicked_Article_Title__c);
            Assert.areEqual(2, row.Clicked_Rank__c);
            Assert.areEqual(1, [SELECT COUNT() FROM Article_Search__c],
                'logClick updates in place — no new row.');
        }
    }

    @IsTest
    static void logClickInvalidInputsAreSafe() {
        System.runAs(kbUser()) {
            Knowledge__kav kav = published();
            Id logId = NexSArticleEngagementController.logSearch(
                entry('engagement', 4, kav.Id, 'Full', null)
            );

            Test.startTest();
            // Null search-log id: no-op, no throw, nothing to update.
            NexSArticleEngagementController.logClick(null, kav.Id, 1);
            // Malformed article id: row still updates; clicked article left null.
            NexSArticleEngagementController.logClick(logId, 'not-an-id', 1);
            Test.stopTest();

            Article_Search__c row = [
                SELECT Clicked_Article_Id__c, Clicked_Rank__c FROM Article_Search__c WHERE Id = :logId
            ];
            Assert.isNull(row.Clicked_Article_Id__c, 'Unresolvable article id clears the clicked article.');
            Assert.areEqual(1, row.Clicked_Rank__c, 'Rank still recorded.');
        }
    }

    @IsTest
    static void logSearchWithoutPermissionIsSwallowed() {
        System.runAs(kbUser()) {
            // A user with no create access to Article_Search__c (a misconfigured
            // guest/permset) must get null, not an exception — proving a logging
            // failure can never surface to the (separate) search call.
            User minimal = minimalAccessUser();
            Id logId;
            System.runAs(minimal) {
                Test.startTest();
                logId = NexSArticleEngagementController.logSearch(
                    entry('anything', 1, null, 'Full', null)
                );
                Test.stopTest();
            }
            Assert.isNull(logId, 'No create permission -> null, no throw.');
            Assert.areEqual(0, [SELECT COUNT() FROM Article_Search__c], 'Nothing logged.');
        }
    }

    /** A user on the Minimum Access profile — no access to the Private
        Article_Search__c object, so isCreateable() is false. */
    private static User minimalAccessUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String uniq = 'nexs' + Math.abs(Crypto.getRandomLong());
        User u = new User(
            Alias = 'nexsmin',
            Email = uniq + '@nexs.test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'MinAccess',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@nexs.test.invalid'
        );
        insert u;
        // Org automation (Assign_NexS_App_To_New_Users flow) grants every new
        // user the NexSHelpCenter permission set, which includes create on
        // Article_Search__c. Strip automation-assigned permission sets so this
        // user really is minimum-access.
        delete [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :u.Id
            AND (PermissionSetGroupId != null OR PermissionSet.IsOwnedByProfile = false)
        ];
        return u;
    }
}