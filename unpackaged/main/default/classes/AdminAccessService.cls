/**
 * AdminAccessService
 *
 * Server-side access gate for the consolidated Admin Console (adminConsole LWC).
 * The Admin_Console tab only hides the entry point; every console section
 * renders — and every Admin*Controller method executes — only when the checks
 * here pass for the running user.
 *
 * Conventions (mirrors ResourceCenterService / HelpGuideAdminController):
 *  - `with sharing`, describe-based CRUD checks, no DML.
 *  - Sections map to capabilities, not permission sets: any perm set granting
 *    the same object/user perms lights the section up.
 *  - Persona layer on top of the capabilities: the Help_Center_Console and
 *    UAT_Console custom permissions (carried by Resource_Center_Admin and
 *    UAT_Admin respectively) scope the rail by group. They exist because
 *    ModifyAllData makes every describe below return true, so without them a
 *    System Administrator always saw all twelve sections. A user holding
 *    either permission only sees the group(s) they hold; a user holding
 *    neither keeps the legacy capability-only behavior, so rollout needs no
 *    day-one assignment sweep. Data access is still enforced by the describe
 *    checks here and in every Admin*Controller — the custom permissions only
 *    scope what the console offers to render.
 *  - Article authoring additionally requires the Knowledge User license flag
 *    (User.UserPermissionsKnowledgeUser) — a per-user license checkbox no
 *    permission set can grant. The DTO separates the license flag from the
 *    object perms so the UI can say "you have permissions but need a Knowledge
 *    license" precisely instead of silently hiding the section.
 */
public with sharing class AdminAccessService {

    /**
     * Test seam: the Knowledge User flag needs a feature license that tests
     * can't reliably assign to a fresh user, so tests override it to exercise
     * both branches of the articles gate.
     */
    @TestVisible private static Boolean knowledgeUserOverride;

    /**
     * Test seams for the persona custom permissions: checkPermission() reads
     * the running user's real assignments, which tests can't always shape
     * (the deploying user runs most tests and holds whatever the org gave
     * them), so both branches are exercised through overrides — same pattern
     * as knowledgeUserOverride above.
     */
    @TestVisible private static Boolean helpCenterConsoleOverride;
    @TestVisible private static Boolean uatConsoleOverride;

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
        /** Helios UAT sections (create+edit on the section's backing object). */
        @AuraEnabled public Boolean uatCycles;
        @AuraEnabled public Boolean uatBooks;
        @AuraEnabled public Boolean uatCases;
        @AuraEnabled public Boolean uatTaxonomy;
        @AuraEnabled public Boolean uatTeams;
        /** Pool Health (read-only coverage view — read on cycles + executions). */
        @AuraEnabled public Boolean uatCoverage;
        /** Cycle Dashboard — same capability as Pool Health; it's a reduction
         *  of the same rollups, not a different access level. */
        @AuraEnabled public Boolean uatDashboard;
        /** Cycle Report — the read-only export of everything a cycle produced.
         *  Same capability as Pool Health: it reads the same records plus the
         *  assignment audit trail, so it is not a different access level. */
        @AuraEnabled public Boolean uatReport;
        /** True when at least one section is visible. */
        @AuraEnabled public Boolean anySection;
    }

    @AuraEnabled(cacheable=true)
    public static AccessDTO getAccess() {
        AccessDTO dto = new AccessDTO();

        // Persona gating (see class header): holding either console custom
        // permission scopes the rail to the held group(s); holding neither
        // preserves capability-only behavior.
        Boolean hasHc = hasHelpCenterConsole();
        Boolean hasUat = hasUatConsole();
        Boolean personaMode = hasHc || hasUat;
        Boolean hcAllowed = !personaMode || hasHc;
        Boolean uatAllowed = !personaMode || hasUat;

        dto.articlePerms = hcAllowed
            && Schema.sObjectType.Knowledge__kav.isCreateable()
            && Schema.sObjectType.Knowledge__kav.isUpdateable();
        dto.knowledgeUser = isKnowledgeUser();
        dto.articles = dto.articlePerms && dto.knowledgeUser;
        dto.submissions = hcAllowed
            && Schema.sObjectType.Article_Submission__c.isCreateable()
            && Schema.sObjectType.Article_Submission__c.isUpdateable();

        dto.resources = hcAllowed
            && Schema.sObjectType.Resource__c.isCreateable()
            && Schema.sObjectType.Resource__c.isUpdateable();
        dto.categories = hcAllowed
            && Schema.sObjectType.Resource_Category__c.isCreateable()
            && Schema.sObjectType.Resource_Category__c.isUpdateable();
        dto.guides = hcAllowed
            && Schema.sObjectType.Help_Guide_Draft__c.isCreateable();

        // Synonym edits deploy custom metadata, so they need Modify Metadata
        // (same requirement as the Help Guide publish).
        dto.synonyms = hcAllowed
            && Schema.sObjectType.Search_Synonym__mdt.isAccessible()
            && hasModifyMetadata();

        dto.analytics = hcAllowed
            && Schema.sObjectType.Article_View__c.isAccessible()
            && Schema.sObjectType.Article_Search__c.isAccessible()
            && Schema.sObjectType.Article_Feedback__c.isAccessible();

        // Helios UAT sections — capability-based like the rest: any permission
        // set granting create+edit on the backing object lights the section up
        // (UAT_Admin is the intended grant).
        dto.uatCycles = uatAllowed
            && Schema.sObjectType.Test_Cycle__c.isCreateable()
            && Schema.sObjectType.Test_Cycle__c.isUpdateable();
        dto.uatBooks = uatAllowed
            && Schema.sObjectType.Test_Book__c.isCreateable()
            && Schema.sObjectType.Test_Book__c.isUpdateable();
        dto.uatCases = uatAllowed
            && Schema.sObjectType.Test_Case__c.isCreateable()
            && Schema.sObjectType.Test_Case__c.isUpdateable();
        dto.uatTaxonomy = uatAllowed
            && Schema.sObjectType.System__c.isCreateable()
            && Schema.sObjectType.System__c.isUpdateable();
        dto.uatTeams = uatAllowed
            && Schema.sObjectType.Team__c.isCreateable()
            && Schema.sObjectType.Team__c.isUpdateable();
        // Coverage is a read-only view, but it exposes the assignment audit
        // trail, so it keys on the same manage capability as the Cycles
        // section rather than bare read access.
        dto.uatCoverage = dto.uatCycles
            && Schema.sObjectType.Test_Assignment_Event__c.isAccessible();
        dto.uatDashboard = dto.uatCoverage;
        dto.uatReport = dto.uatCoverage;

        dto.anySection = dto.articles || dto.submissions || dto.resources
            || dto.categories || dto.guides || dto.synonyms || dto.analytics
            || dto.uatCycles || dto.uatBooks || dto.uatCases || dto.uatTaxonomy
            || dto.uatTeams || dto.uatCoverage || dto.uatDashboard || dto.uatReport;
        return dto;
    }

    /**
     * True when the running user can really author Knowledge: object perms AND
     * the Knowledge User license. The single gate the review/promote paths use.
     */
    public static Boolean canAuthorArticles() {
        return Schema.sObjectType.Knowledge__kav.isCreateable()
            && Schema.sObjectType.Knowledge__kav.isUpdateable()
            && isKnowledgeUser();
    }

    // ---- Internals ------------------------------------------------------------

    private static Boolean hasHelpCenterConsole() {
        if (helpCenterConsoleOverride != null) {
            return helpCenterConsoleOverride;
        }
        return FeatureManagement.checkPermission('Help_Center_Console');
    }

    private static Boolean hasUatConsole() {
        if (uatConsoleOverride != null) {
            return uatConsoleOverride;
        }
        return FeatureManagement.checkPermission('UAT_Console');
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