/**
 * ArticleSubmissionController
 *
 * Contributor workflow for the Admin Console: admins WITHOUT the Knowledge User
 * license author Article_Submission__c records (plain custom object) with the
 * same guided form as real articles; the licensed Knowledge user reviews the
 * queue and promotes a submission into a real Knowledge__kav draft via
 * ArticleAdminController.saveArticle (then publishes from the Articles list).
 *
 * Roles (checked live, so access follows the license as it moves):
 *  - Contributor: Article_Submission__c create/edit. Owns their submissions;
 *    may edit/submit only while status is Draft or Changes requested.
 *  - Reviewer: AdminAccessService.canAuthorArticles() — Knowledge object perms
 *    AND the Knowledge User license. Sees the queue, requests changes, promotes.
 *
 * v1 scope: submissions create NEW articles only (edits to published articles
 * stay licensed-only).
 */
public with sharing class ArticleSubmissionController {

    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_SUBMITTED = 'Submitted';
    private static final String STATUS_CHANGES = 'Changes requested';
    private static final String STATUS_PROMOTED = 'Promoted';
    private static final Integer LIST_LIMIT = 200;

    // ---- DTOs -------------------------------------------------------------------

    public class SubmissionDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String proposedUrlName;
        @AuraEnabled public String summary;
        @AuraEnabled public String content;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String keywords;
        @AuraEnabled public String embedUrl;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public List<String> categoryNames = new List<String>();
        @AuraEnabled public List<String> suggestedUrlNames = new List<String>();
        @AuraEnabled public List<Id> relatedResourceIds = new List<Id>();
        @AuraEnabled public String status;
        @AuraEnabled public String reviewNotes;
        @AuraEnabled public String promotedArticleId;
        @AuraEnabled public String createdByName;
        @AuraEnabled public Datetime lastModified;
        @AuraEnabled public Boolean editable;
    }

    public class SubmissionInput {
        @AuraEnabled public Id id;                       // null = create
        @AuraEnabled public String title;
        @AuraEnabled public String proposedUrlName;
        @AuraEnabled public String summary;
        @AuraEnabled public String content;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String keywords;
        @AuraEnabled public String embedUrl;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public List<String> categoryNames;
        @AuraEnabled public List<String> suggestedUrlNames;
        @AuraEnabled public List<Id> relatedResourceIds;
    }

    // ---- Reads ------------------------------------------------------------------

    @AuraEnabled
    public static List<SubmissionDTO> listMySubmissions() {
        assertContributor();
        List<SubmissionDTO> out = new List<SubmissionDTO>();
        for (Article_Submission__c s : [
            SELECT Id, Name, Proposed_UrlName__c, Summary__c, Content__c, Question__c,
                   Answer__c, Keywords__c, Embed_URL__c, Record_Type_Name__c,
                   Category_Names__c, Suggested_UrlNames__c, Related_Resource_Ids__c,
                   Status__c, Review_Notes__c, Promoted_Article_Id__c,
                   CreatedById, CreatedBy.Name, LastModifiedDate
            FROM Article_Submission__c
            WHERE CreatedById = :UserInfo.getUserId()
            ORDER BY LastModifiedDate DESC
            LIMIT :LIST_LIMIT
        ]) {
            out.add(toDto(s));
        }
        return out;
    }

    @AuraEnabled
    public static List<SubmissionDTO> listReviewQueue() {
        assertReviewer();
        List<SubmissionDTO> out = new List<SubmissionDTO>();
        for (Article_Submission__c s : [
            SELECT Id, Name, Proposed_UrlName__c, Summary__c, Content__c, Question__c,
                   Answer__c, Keywords__c, Embed_URL__c, Record_Type_Name__c,
                   Category_Names__c, Suggested_UrlNames__c, Related_Resource_Ids__c,
                   Status__c, Review_Notes__c, Promoted_Article_Id__c,
                   CreatedById, CreatedBy.Name, LastModifiedDate
            FROM Article_Submission__c
            WHERE Status__c = :STATUS_SUBMITTED
            ORDER BY LastModifiedDate ASC
            LIMIT :LIST_LIMIT
        ]) {
            out.add(toDto(s));
        }
        return out;
    }

    @AuraEnabled
    public static SubmissionDTO getSubmission(Id submissionId) {
        assertContributor();
        Article_Submission__c s = load(submissionId);
        if (s.CreatedById != UserInfo.getUserId() && !isReviewer()) {
            throw auraError('You can only open your own submissions.');
        }
        return toDto(s);
    }

    // ---- Contributor writes -----------------------------------------------------

    @AuraEnabled
    public static Id saveSubmission(String inputJson) {
        assertContributor();
        // JSON-string transport: custom-Apex-type @AuraEnabled parameters arrive
        // null/blank from LWC in this org.
        SubmissionInput input;
        try {
            input = String.isBlank(inputJson)
                ? null : (SubmissionInput) JSON.deserialize(inputJson, SubmissionInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (input == null || String.isBlank(input.title)) {
            throw auraError('Title is required.');
        }
        Article_Submission__c record = new Article_Submission__c(
            Name = input.title.trim().abbreviate(80),
            Proposed_UrlName__c = input.proposedUrlName,
            Summary__c = input.summary,
            Content__c = input.content,
            Question__c = input.question,
            Answer__c = input.answer,
            Keywords__c = input.keywords,
            Embed_URL__c = normalizeEmbedUrl(input.embedUrl),
            Record_Type_Name__c = String.isBlank(input.recordTypeName)
                ? 'Standard' : input.recordTypeName,
            Category_Names__c = joinLines(input.categoryNames),
            Suggested_UrlNames__c = joinLines(input.suggestedUrlNames),
            Related_Resource_Ids__c = joinIdLines(input.relatedResourceIds)
        );
        try {
            if (input.id == null) {
                record.Status__c = STATUS_DRAFT;
                insert record;
            } else {
                Article_Submission__c existing = load(input.id);
                assertOwnerEditable(existing);
                record.Id = input.id;
                update record;
            }
            return record.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw auraError('Could not save the submission: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void submitForReview(Id submissionId) {
        assertContributor();
        Article_Submission__c s = load(submissionId);
        assertOwnerEditable(s);
        if (String.isBlank(s.Content__c) && String.isBlank(s.Summary__c)) {
            throw auraError('Add a summary or body before submitting for review.');
        }
        s.Status__c = STATUS_SUBMITTED;
        update s;
    }

    // ---- Reviewer writes ----------------------------------------------------------

    @AuraEnabled
    public static void requestChanges(Id submissionId, String notes) {
        assertReviewer();
        Article_Submission__c s = load(submissionId);
        if (s.Status__c != STATUS_SUBMITTED) {
            throw auraError('Only submitted items can be sent back for changes.');
        }
        s.Status__c = STATUS_CHANGES;
        s.Review_Notes__c = notes;
        update s;
    }

    /**
     * Turns a submitted staging record into a REAL Knowledge draft (not yet
     * published — publish is an explicit follow-up in the Articles list).
     * Reuses ArticleAdminController.saveArticle, so all article validation
     * (category names, UrlName uniqueness, https embed) applies unchanged.
     */
    @AuraEnabled
    public static String promote(Id submissionId) {
        assertReviewer();
        Article_Submission__c s = load(submissionId);
        if (s.Status__c != STATUS_SUBMITTED) {
            throw auraError('Only submitted items can be promoted.');
        }

        ArticleAdminController.ArticleInput input = new ArticleAdminController.ArticleInput();
        input.title = s.Name;
        input.urlName = String.isBlank(s.Proposed_UrlName__c)
            ? null : s.Proposed_UrlName__c.trim();
        if (String.isBlank(input.urlName)) {
            throw auraError('The submission has no URL name — ask the author to add one.');
        }
        input.summary = s.Summary__c;
        input.content = s.Content__c;
        input.question = s.Question__c;
        input.answer = s.Answer__c;
        input.keywords = s.Keywords__c;
        input.featured = false;
        input.embedUrl = s.Embed_URL__c;
        input.recordTypeId = recordTypeIdFor(s.Record_Type_Name__c);
        input.categoryNames = parseLines(s.Category_Names__c);
        input.suggestedUrlNames = parseLines(s.Suggested_UrlNames__c);
        input.relatedResourceIds = parseIdLines(s.Related_Resource_Ids__c);

        ArticleAdminController.SaveResult result = ArticleAdminController.applyArticleInput(input);

        s.Status__c = STATUS_PROMOTED;
        s.Promoted_Article_Id__c = result.kaId;
        update s;
        return result.kaId;
    }

    // ---- Internals ----------------------------------------------------------------

    private static Article_Submission__c load(Id submissionId) {
        List<Article_Submission__c> rows = [
            SELECT Id, Name, Proposed_UrlName__c, Summary__c, Content__c, Question__c,
                   Answer__c, Keywords__c, Embed_URL__c, Record_Type_Name__c,
                   Category_Names__c, Suggested_UrlNames__c, Related_Resource_Ids__c,
                   Status__c, Review_Notes__c, Promoted_Article_Id__c,
                   CreatedById, CreatedBy.Name, LastModifiedDate
            FROM Article_Submission__c
            WHERE Id = :submissionId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw auraError('Submission not found.');
        }
        return rows[0];
    }

    private static SubmissionDTO toDto(Article_Submission__c s) {
        SubmissionDTO dto = new SubmissionDTO();
        dto.id = s.Id;
        dto.title = s.Name;
        dto.proposedUrlName = s.Proposed_UrlName__c;
        dto.summary = s.Summary__c;
        dto.content = s.Content__c;
        dto.question = s.Question__c;
        dto.answer = s.Answer__c;
        dto.keywords = s.Keywords__c;
        dto.embedUrl = s.Embed_URL__c;
        dto.recordTypeName = s.Record_Type_Name__c;
        dto.categoryNames = parseLines(s.Category_Names__c);
        dto.suggestedUrlNames = parseLines(s.Suggested_UrlNames__c);
        dto.relatedResourceIds = parseIdLines(s.Related_Resource_Ids__c);
        dto.status = s.Status__c;
        dto.reviewNotes = s.Review_Notes__c;
        dto.promotedArticleId = s.Promoted_Article_Id__c;
        dto.createdByName = s.CreatedBy == null ? null : s.CreatedBy.Name;
        dto.lastModified = s.LastModifiedDate;
        dto.editable = s.CreatedById == UserInfo.getUserId()
            && (s.Status__c == STATUS_DRAFT || s.Status__c == STATUS_CHANGES);
        return dto;
    }

    private static Id recordTypeIdFor(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        List<RecordType> types = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Knowledge__kav'
            AND DeveloperName = :developerName AND IsActive = true
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    private static List<String> parseLines(String value) {
        List<String> out = new List<String>();
        if (String.isNotBlank(value)) {
            for (String line : value.split('\n')) {
                if (String.isNotBlank(line)) {
                    out.add(line.trim());
                }
            }
        }
        return out;
    }

    private static List<Id> parseIdLines(String value) {
        List<Id> out = new List<Id>();
        for (String line : parseLines(value)) {
            try {
                out.add((Id) line);
            } catch (Exception e) {
                // skip malformed lines rather than blocking the whole record
            }
        }
        return out;
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

    private static String joinIdLines(List<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return null;
        }
        List<String> lines = new List<String>();
        for (Id i : ids) {
            lines.add(String.valueOf(i));
        }
        return String.join(lines, '\n');
    }

    private static String normalizeEmbedUrl(String embedUrl) {
        if (String.isBlank(embedUrl)) {
            return null;
        }
        String clean = embedUrl.trim();
        if (!clean.startsWithIgnoreCase('https://')) {
            throw auraError('Embed URL must start with https://.');
        }
        return clean;
    }

    private static void assertOwnerEditable(Article_Submission__c s) {
        if (s.CreatedById != UserInfo.getUserId()) {
            throw auraError('You can only change your own submissions.');
        }
        if (s.Status__c != STATUS_DRAFT && s.Status__c != STATUS_CHANGES) {
            throw auraError('This submission is ' + s.Status__c.toLowerCase()
                + ' and can no longer be edited.');
        }
    }

    private static Boolean isReviewer() {
        return AdminAccessService.canAuthorArticles();
    }

    private static void assertReviewer() {
        if (!isReviewer()) {
            throw auraError('Reviewing needs Knowledge authoring permissions '
                + 'and the Knowledge User license.');
        }
    }

    private static void assertContributor() {
        if (!Schema.sObjectType.Article_Submission__c.isCreateable()
            || !Schema.sObjectType.Article_Submission__c.isUpdateable()) {
            throw auraError('You do not have access to article submissions.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}