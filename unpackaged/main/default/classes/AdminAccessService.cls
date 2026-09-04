/**
 * AdminAccessService
 *
 * Server-side access gate for the Admin Console (adminConsole LWC) — the Help
 * Center / Resource Center content tools. The Admin_Console tab only hides the
 * entry point; every console section renders — and every Admin*Controller
 * method executes — only when the checks here pass for the running user.
 *
 * Conventions (mirrors ResourceCenterService / HelpGuideAdminController):
 *  - `with sharing`, describe-based CRUD checks, no DML.
 *  - Sections map to capabilities, not permission sets: any perm set granting
 *    the same object/user perms lights the section up.
 *  - Article authoring additionally requires the Knowledge User license flag
 *    (User.UserPermissionsKnowledgeUser) — a per-user license checkbox no
 *    permission set can grant. The DTO separates the license flag from the
 *    object perms so the UI can say "you have permissions but need a Knowledge
 *    license" precisely instead of silently hiding the section.
 *
 * History: until 2026-09-04 this class also gated the Helios test-management
 * sections and carried a persona layer (two custom permissions) so sysadmins
 * would not see both rails. Those sections now have their own root and their
 * own access gate, which removes the need for persona scoping here: this
 * console only ever offers Help Center sections.
 */
public with sharing class AdminAccessService {

    /**
     * Test seam: the Knowledge User flag needs a feature license that tests
     * can't reliably assign to a fresh user, so tests override it to exercise
     * both branches of the articles gate.
     */
    @TestVisible private static Boolean knowledgeUserOverride;

    public class AccessDTO {
        /** Article authoring: object perms AND the Knowledge User license. */
        @AuraEnabled public Boolean articles;
        /** Knowledge__kav create+edit (perm sets/profile), ignoring the license. */
        @AuraEnabled public Boolean articlePerms;
        /** User.UserPermissionsKnowledgeUser — the per-user license checkbox. */
        @AuraEnabled public Boolean knowledgeUser;
        /** Contributor authoring: Article_Submission__c staging (no license needed). */
        @AuraEnabled public Boolean submissions;
        @AuraEnabled public Boolean resources;
        @AuraEnabled public Boolean categories;
        @AuraEnabled public Boolean guides;
        @AuraEnabled public Boolean synonyms;
        @AuraEnabled public Boolean analytics;
        /** True when at least one section is visible. */
        @AuraEnabled public Boolean anySection;
    }

    @AuraEnabled(cacheable=true)
    public static AccessDTO getAccess() {
        AccessDTO dto = new AccessDTO();

        dto.articlePerms = canWriteKnowledge();
        dto.knowledgeUser = isKnowledgeUser();
        dto.articles = dto.articlePerms && dto.knowledgeUser;
        dto.submissions = Schema.sObjectType.Article_Submission__c.isCreateable()
            && Schema.sObjectType.Article_Submission__c.isUpdateable();

        dto.resources = Schema.sObjectType.Resource__c.isCreateable()
            && Schema.sObjectType.Resource__c.isUpdateable();
        dto.categories = Schema.sObjectType.Resource_Category__c.isCreateable()
            && Schema.sObjectType.Resource_Category__c.isUpdateable();
        dto.guides = Schema.sObjectType.Help_Guide_Draft__c.isCreateable();

        // Synonym edits deploy custom metadata, so they need Modify Metadata
        // (same requirement as the Help Guide publish).
        dto.synonyms = Schema.sObjectType.Search_Synonym__mdt.isAccessible()
            && hasModifyMetadata();

        dto.analytics = Schema.sObjectType.Article_View__c.isAccessible()
            && Schema.sObjectType.Article_Search__c.isAccessible()
            && Schema.sObjectType.Article_Feedback__c.isAccessible();

        dto.anySection = dto.articles || dto.submissions || dto.resources
            || dto.categories || dto.guides || dto.synonyms || dto.analytics;
        return dto;
    }

    /**
     * True when the running user can really author Knowledge: object perms AND
     * the Knowledge User license. The single gate the review/promote paths use.
     */
    public static Boolean canAuthorArticles() {
        return canWriteKnowledge() && isKnowledgeUser();
    }

    // ---- Internals ------------------------------------------------------------

    /**
     * Knowledge__kav create+edit. A user with no Knowledge access at all (no
     * AllowViewKnowledge anywhere) makes the describe itself throw
     * NoAccessException rather than answer false; that user simply has no
     * article section, so the gate answers false instead of failing the wire.
     */
    private static Boolean canWriteKnowledge() {
        try {
            return Schema.sObjectType.Knowledge__kav.isCreateable()
                && Schema.sObjectType.Knowledge__kav.isUpdateable();
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isKnowledgeUser() {
        if (knowledgeUserOverride != null) {
            return knowledgeUserOverride;
        }
        List<User> rows = [
            SELECT UserPermissionsKnowledgeUser
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return !rows.isEmpty() && rows[0].UserPermissionsKnowledgeUser == true;
    }

    public static Boolean hasModifyMetadata() {
        // Profile-granted perms are covered too: every user holds an assignment
        // to their profile's underlying (IsOwnedByProfile) permission set.
        try {
            return [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSet.PermissionsModifyMetadata = true
            ] > 0;
        } catch (Exception e) {
            return false;
        }
    }
}