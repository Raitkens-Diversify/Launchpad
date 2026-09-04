/**
 * UatAdminAccessService
 *
 * Server-side access gate for the UAT Admin Console (uatAdminConsole LWC).
 * Split out of AdminAccessService on 2026-09-04 so the Help Center / Resource
 * Center admin console carries no UAT metadata. The UAT_Admin_Console tab only
 * hides the entry point; every section renders — and every Uat*AdminController
 * method executes — only when the checks here pass for the running user.
 *
 * Conventions (same as AdminAccessService):
 *  - `with sharing`, describe-based CRUD checks, no DML.
 *  - Sections map to capabilities, not permission sets: any permission set
 *    granting create+edit on the section's backing object lights the section
 *    up (UAT_Admin is the intended grant).
 *  - Moderation rights (author-or-admin edits on findings/sessions) are a
 *    separate concern gated by UatAudienceService on the UAT_Console custom
 *    permission; this class only decides what the console offers to render.
 */
public with sharing class UatAdminAccessService {

    public class AccessDTO {
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

        dto.uatCycles = Schema.sObjectType.Test_Cycle__c.isCreateable()
            && Schema.sObjectType.Test_Cycle__c.isUpdateable();
        dto.uatBooks = Schema.sObjectType.Test_Book__c.isCreateable()
            && Schema.sObjectType.Test_Book__c.isUpdateable();
        dto.uatCases = Schema.sObjectType.Test_Case__c.isCreateable()
            && Schema.sObjectType.Test_Case__c.isUpdateable();
        dto.uatTaxonomy = Schema.sObjectType.System__c.isCreateable()
            && Schema.sObjectType.System__c.isUpdateable();
        dto.uatTeams = Schema.sObjectType.Team__c.isCreateable()
            && Schema.sObjectType.Team__c.isUpdateable();
        // Coverage is a read-only view, but it exposes the assignment audit
        // trail, so it keys on the same manage capability as the Cycles
        // section rather than bare read access.
        dto.uatCoverage = dto.uatCycles
            && Schema.sObjectType.Test_Assignment_Event__c.isAccessible();
        dto.uatDashboard = dto.uatCoverage;
        dto.uatReport = dto.uatCoverage;

        dto.anySection = dto.uatCycles || dto.uatBooks || dto.uatCases
            || dto.uatTaxonomy || dto.uatTeams || dto.uatCoverage
            || dto.uatDashboard || dto.uatReport;
        return dto;
    }
}