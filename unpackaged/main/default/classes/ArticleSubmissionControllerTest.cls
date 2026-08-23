/**
 * ArticleSubmissionControllerTest
 *
 * Reviewer-ness = Knowledge perms + the Knowledge User license; the license
 * can't be assigned to test users, so tests drive it through
 * AdminAccessService.knowledgeUserOverride (the same seam getAccess uses).
 */
@IsTest
private class ArticleSubmissionControllerTest {

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

    @IsTest
    static void reviewerRequestsChangesAndContributorResubmits() {
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

    @IsTest
    static void promoteCreatesRealDraftWithCategoriesAndLinks() {
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

    @IsTest
    static void promoteRequiresReviewerAndSubmittedStatus() {
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

    @IsTest
    static void ownershipEnforcedAcrossUsers() {
        AdminAccessService.knowledgeUserOverride = false;
        Id subId = ArticleSubmissionController.saveSubmission(JSON.serialize(input('Owned Article')));

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User other = new User(
            Alias = 'subown',
            Email = 'sub.owner@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'SubOther',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'sub.other.' + System.currentTimeMillis() + '@example.com.cosmosdev'
        );
        insert other;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Resource_Center_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = other.Id, PermissionSetId = ps.Id);

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

    @IsTest
    static void minimalUserIsRejected() {
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