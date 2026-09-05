/**
 * ArticleSubmissionControllerTest
 *
 * Reviewer-ness = Knowledge perms + the Knowledge User license. Every test runs
 * as a licensed Knowledge user (see makeKnowledgeUser) so the object-permission
 * half is real; the license half is switched per "hat" through
 * AdminAccessService.knowledgeUserOverride (the same seam getAccess uses) so
 * one user can act as contributor and reviewer within a test.
 */
@IsTest
private class ArticleSubmissionControllerTest {

    // ---- Knowledge User test identity ------------------------------------------
    // Knowledge__kav DML, KbManagement publishing and the Knowledge__kav
    // create/update describes all require the Knowledge User feature license
    // (User.UserPermissionsKnowledgeUser). No permission set can grant it and the
    // deploying user need not hold it, so every test runs as a dedicated licensed
    // user created here. @TestSetup and each test method are separate contexts,
    // so kbUser() re-queries that user by alias before each System.runAs.
    private static final String KB_ALIAS = 'asubusr';
    private static final String KB_DOMAIN = '@asub.test.invalid';

    static User makeKnowledgeUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'asub' + Math.abs(Crypto.getRandomLong());
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

    /**
     * Internal user on the Standard User profile holding only the permission
     * sets named. Org automation assigns Help Center permission sets to every
     * new user, so those are stripped first: the user has exactly what the test
     * grants. Callers wrap this in System.runAs to keep the setup-object DML out
     * of the MIXED_DML trap when data was inserted earlier in the same test.
     */
    static User makeStandardUser(String aliasPrefix, List<String> permissionSetNames) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = aliasPrefix + Math.abs(Crypto.getRandomLong());
        User u = new User(
            Alias = aliasPrefix.left(8),
            Email = uniq + '@hc.test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'HC ' + aliasPrefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@hc.test.invalid'
        );
        insert u;
        delete [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :u.Id
            AND (PermissionSetGroupId != null OR PermissionSet.IsOwnedByProfile = false)
        ];
        for (String name : permissionSetNames) {
            grantIfMissing(u.Id, name);
        }
        return u;
    }

    /** Every test runs as a licensed Knowledge user; see makeKnowledgeUser. */
    @TestSetup
    static void grantAccess() {
        makeKnowledgeUser();
    }

    private static ArticleSubmissionController.SubmissionInput input(String title) {
        ArticleSubmissionController.SubmissionInput s =
            new ArticleSubmissionController.SubmissionInput();
        s.title = title;
        s.proposedUrlName = 'sub-' + title.toLowerCase().replaceAll('[^a-z0-9]+', '-');
        s.summary = 'Summary for ' + title;
        s.content = '<h2>Intro</h2><p>Body</p>';
        s.keywords = 'submission, test';
        s.recordTypeName = 'Standard';
        return s;
    }

    @IsTest
    static void contributorSavesAndSubmits() {
        System.runAs(kbUser()) {
            AdminAccessService.knowledgeUserOverride = false;

            Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(input('Sub One')));
            Article_Submission__c saved = [
                SELECT Status__c, Record_Type_Name__c FROM Article_Submission__c WHERE Id = :subId
            ];
            System.assertEquals('Draft', saved.Status__c);
            System.assertEquals('Standard', saved.Record_Type_Name__c);

            List<ArticleSubmissionController.SubmissionDTO> mine =
                ArticleSubmissionController.listMySubmissions();
            System.assertEquals(1, mine.size());
            System.assertEquals(true, mine[0].editable, 'Draft is editable by its owner');

            ArticleSubmissionController.submitForReview(subId);
            System.assertEquals('Submitted', [
                SELECT Status__c FROM Article_Submission__c WHERE Id = :subId
            ].Status__c);

            // Once submitted, the owner can no longer edit it.
            ArticleSubmissionController.SubmissionInput edit = input('Sub One Edited');
            edit.id = subId;
            try {
                ArticleSubmissionController.saveSubmission(JSON.serialize(edit));
                System.assert(false, 'Submitted items must be locked');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('no longer be edited'), e.getMessage());
            }
        }
    }

    @IsTest
    static void reviewerRequestsChangesAndContributorResubmits() {
        System.runAs(kbUser()) {
            AdminAccessService.knowledgeUserOverride = false;
            Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(input('Sub Two')));
            ArticleSubmissionController.submitForReview(subId);

            AdminAccessService.knowledgeUserOverride = true; // reviewer hat
            ArticleSubmissionController.requestChanges(subId, 'Please add a heading.');

            Article_Submission__c s = [
                SELECT Status__c, Review_Notes__c FROM Article_Submission__c WHERE Id = :subId
            ];
            System.assertEquals('Changes requested', s.Status__c);
            System.assertEquals('Please add a heading.', s.Review_Notes__c);

            AdminAccessService.knowledgeUserOverride = false; // contributor hat
            ArticleSubmissionController.SubmissionInput edit = input('Sub Two');
            edit.id = subId;
            ArticleSubmissionController.saveSubmission(JSON.serialize(edit));
            ArticleSubmissionController.submitForReview(subId);
            System.assertEquals('Submitted', [
                SELECT Status__c FROM Article_Submission__c WHERE Id = :subId
            ].Status__c);
        }
    }

    @IsTest
    static void promoteCreatesRealDraftWithCategoriesAndLinks() {
        System.runAs(kbUser()) {
            Resource_Category__c cat = new Resource_Category__c(
                Name = 'Sub Test Category', Slug__c = 'sub-test-category', Is_Active__c = true);
            insert cat;
            Resource__c res = new Resource__c(
                Name = 'Sub Test Resource', Category__c = cat.Id,
                Slug__c = 'sub-test-resource', Resource_Type__c = 'PDF', Is_Active__c = true);
            insert res;

            AdminAccessService.knowledgeUserOverride = false;
            ArticleSubmissionController.SubmissionInput s = input('Promotable Article');
            s.categoryNames = new List<String>{ 'The_Basics' };
            s.relatedResourceIds = new List<Id>{ res.Id };
            Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(s));
            ArticleSubmissionController.submitForReview(subId);

            AdminAccessService.knowledgeUserOverride = true;
            Test.startTest();
            String kaId = ArticleSubmissionController.promote(subId);
            Test.stopTest();

            Article_Submission__c promoted = [
                SELECT Status__c, Promoted_Article_Id__c FROM Article_Submission__c WHERE Id = :subId
            ];
            System.assertEquals('Promoted', promoted.Status__c);
            System.assertEquals(kaId, promoted.Promoted_Article_Id__c);

            Knowledge__kav draft = [
                SELECT Id, Title, UrlName, PublishStatus FROM Knowledge__kav
                WHERE KnowledgeArticleId = :kaId
            ];
            System.assertEquals('Draft', draft.PublishStatus,
                'Promotion creates a draft; publish stays an explicit follow-up');
            System.assertEquals('sub-promotable-article', draft.UrlName);

            Integer selections = 0;
            for (Knowledge__DataCategorySelection sel : [
                SELECT DataCategoryGroupName, DataCategoryName
                FROM Knowledge__DataCategorySelection WHERE ParentId = :draft.Id
            ]) {
                if (sel.DataCategoryGroupName == 'Help_Topics'
                    && sel.DataCategoryName == 'The_Basics') {
                    selections++;
                }
            }
            System.assertEquals(1, selections, 'Category carried into the real draft');

            List<Article_Resource__c> links = [
                SELECT Resource__c FROM Article_Resource__c WHERE Knowledge_Article_Id__c = :kaId
            ];
            System.assertEquals(1, links.size(), 'Resource link created with the stable KA Id');
            System.assertEquals(res.Id, links[0].Resource__c);
        }
    }

    @IsTest
    static void promoteRequiresReviewerAndSubmittedStatus() {
        System.runAs(kbUser()) {
            AdminAccessService.knowledgeUserOverride = false;
            Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(input('Guard Article')));

            // Not submitted yet â†’ reviewer can't promote it.
            AdminAccessService.knowledgeUserOverride = true;
            try {
                ArticleSubmissionController.promote(subId);
                System.assert(false, 'Draft must not be promotable');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('submitted'), e.getMessage());
            }

            // Non-licensed user is not a reviewer, even with object perms.
            AdminAccessService.knowledgeUserOverride = false;
            try {
                ArticleSubmissionController.listReviewQueue();
                System.assert(false, 'Review queue requires the license');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Knowledge User license'), e.getMessage());
            }
        }
    }

    @IsTest
    static void ownershipEnforcedAcrossUsers() {
        System.runAs(kbUser()) {
            AdminAccessService.knowledgeUserOverride = false;
            Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(input('Owned Article')));

            // Setup-object DML after the submission insert above: runAs keeps it
            // out of the MIXED_DML trap.
            User other;
            System.runAs(kbUser()) {
                other = makeStandardUser('subown', new List<String>{ 'Resource_Center_Admin' });
            }

            System.runAs(other) {
                AdminAccessService.knowledgeUserOverride = false;
                try {
                    ArticleSubmissionController.submitForReview(subId);
                    System.assert(false, 'Only the owner may submit');
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().contains('your own'), e.getMessage());
                }
            }
        }
    }

    @IsTest
    static void minimalUserIsRejected() {
        System.runAs(kbUser()) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
            User u = new User(
                Alias = 'submin',
                Email = 'sub.min@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'SubMin',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = p.Id,
                TimeZoneSidKey = 'America/Denver',
                UserName = 'sub.min.' + System.currentTimeMillis() + '@example.com.cosmosdev'
            );
            insert u;
            System.runAs(u) {
                try {
                    ArticleSubmissionController.saveSubmission(JSON.serialize(input('Nope')));
                    System.assert(false, 'Expected an access exception');
                } catch (AuraHandledException e) {
                    System.assert(true);
                }
            }
        }
    }
}