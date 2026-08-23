/**
 * UatAudienceService
 *
 * The tester surface's access gates, extracted verbatim from UatRunController
 * (2026-08) so UatSessionController can share them instead of copying the
 * audience rule — its live-claim-holder nuance is exactly the kind of logic
 * that rots when duplicated.
 *
 * Audience (open-pool design §1): a cycle's audience is its assigned team —
 * or every tester when it has no team — plus anyone holding a live claim in
 * the cycle (their run stays visible, so the cycle's exploratory surface
 * must too).
 *
 * Ownership layer for the personal-but-team-visible records (exploratory
 * sessions + findings): owner-or-admin, where admin = the UAT_Console
 * persona custom permission (carried by UAT_Admin).
 */
public with sharing class UatAudienceService {

    /** Test seam for the persona permission: checkPermission() reads the
     *  running user's real assignments, which tests can't always shape —
     *  the AdminAccessService pattern. */
    @TestVisible private static Boolean uatConsoleOverride;

    public static void assertTester() {
        if (!Schema.sObjectType.Test_Execution__c.isAccessible()
            || !Schema.sObjectType.Test_Step_Result__c.isAccessible()) {
            throw auraError('You do not have access to UAT testing.');
        }
    }

    public static Set<Id> myTeamIds(Id userId) {
        Set<Id> teams = new Set<Id>();
        for (Team_Member__c membership : [
            SELECT Team__c FROM Team_Member__c WHERE User__c = :userId
        ]) {
            teams.add(membership.Team__c);
        }
        return teams;
    }

    public static Boolean isOnTeam(Id teamId, Id userId) {
        return [
            SELECT COUNT() FROM Team_Member__c
            WHERE Team__c = :teamId AND User__c = :userId
        ] > 0;
    }

    /** A cycle's audience: its assigned team — or every tester when it has no
     *  team. A tester holding a live claim in the cycle stays in the audience
     *  even if the team was later switched (their run stays visible, so the
     *  cycle's findings log must too). UAT_Console admins pass regardless of
     *  team — without this, the owner-or-admin moderation override could
     *  never reach a teamed cycle the admin isn't on. */
    public static void assertCycleAudience(Id cycleId) {
        if (cycleId == null) {
            throw auraError('Missing cycle — refresh and try again.');
        }
        Test_Cycle__c cycle;
        try {
            cycle = [SELECT Assigned_Team__c FROM Test_Cycle__c WHERE Id = :cycleId];
        } catch (QueryException ex) {
            throw auraError('That cycle no longer exists — refresh and try again.');
        }
        Id me = UserInfo.getUserId();
        if (cycle.Assigned_Team__c == null || isOnTeam(cycle.Assigned_Team__c, me)
            || isUatAdmin()) {
            return;
        }
        Integer myClaims = [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c = :me
            AND Released__c = false
        ];
        if (myClaims > 0) {
            return;
        }
        throw auraError('This cycle belongs to another team — refresh your queue.');
    }

    /** Session gate: a cycled session is team-visible through the cycle
     *  audience; a standalone (null-cycle) session is personal — only its
     *  tester or a UAT_Console admin may touch it, reads included. */
    public static void assertSessionAudience(Id cycleId, Id testerId) {
        if (cycleId != null) {
            assertCycleAudience(cycleId);
            return;
        }
        if (testerId == UserInfo.getUserId() || isUatAdmin()) {
            return;
        }
        throw auraError('This standalone session is personal to its tester.');
    }

    public static Boolean isUatAdmin() {
        if (uatConsoleOverride != null) {
            return uatConsoleOverride;
        }
        return FeatureManagement.checkPermission('UAT_Console');
    }

    /** Owner-or-admin: the write gate for sessions and findings. The noun
     *  lands in the error ("finding", "session"). */
    public static void assertOwnerOrAdmin(Id ownerId, String noun) {
        if (ownerId == UserInfo.getUserId() || isUatAdmin()) {
            return;
        }
        throw auraError('Only the tester who created this ' + noun + ' can change it.');
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}