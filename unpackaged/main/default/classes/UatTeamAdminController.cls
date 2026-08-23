/**
 * UatTeamAdminController
 *
 * Apex behind the Admin Console's UAT Teams section (adminUatTeams): team
 * list with member management, the tester pool, and "add a new tester".
 *
 * The tester pool is defined by the UAT_Tester permission set: holding it is
 * what makes a user a tester, so the pool checklist offers exactly those
 * users. The spec's inline "add a new tester" cannot create a User record
 * (licensing) — it is reinterpreted as "assign UAT_Tester to an existing
 * internal user", which requires the running admin to hold Assign Permission
 * Sets (granted by UAT_Admin).
 *
 * Team delete (2026-08-05, superseding the 03-doc deferred decision): allowed
 * only when NO open cycle references the team — a deleted team SetNulls
 * Test_Cycle__c.Assigned_Team__c, and a null team means "open to every
 * tester" in all tester-facing queries, so deleting a referenced team would
 * silently WIDEN visibility instead of narrowing it. Closed-cycle references
 * clear silently (the confirm copy states the reopen hazard).
 * Conventions: with sharing, describe asserts + stripInaccessible,
 * AuraHandledException, JSON-string write payloads (org quirk).
 */
public with sharing class UatTeamAdminController {

    // ---- DTOs ----------------------------------------------------------------

    public class MemberDTO {
        @AuraEnabled public Id memberId;   // Team_Member__c Id
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
    }

    public class TeamDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public List<MemberDTO> members = new List<MemberDTO>();
    }

    public class OptionDTO {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class TeamInput {
        public Id id;                 // null = create
        public String name;
        public List<Id> memberUserIds = new List<Id>();
    }

    // ---- Reads ---------------------------------------------------------------

    @AuraEnabled
    public static List<TeamDTO> getTeams() {
        assertTeamsReadable();
        List<TeamDTO> result = new List<TeamDTO>();
        for (Team__c t : [
            SELECT Id, Name,
                (SELECT Id, User__c, User__r.Name FROM Team_Members__r ORDER BY User__r.Name)
            FROM Team__c
            ORDER BY Name
        ]) {
            TeamDTO dto = new TeamDTO();
            dto.id = t.Id;
            dto.name = t.Name;
            for (Team_Member__c m : t.Team_Members__r) {
                MemberDTO md = new MemberDTO();
                md.memberId = m.Id;
                md.userId = m.User__c;
                md.userName = m.User__r.Name;
                dto.members.add(md);
            }
            result.add(dto);
        }
        return result;
    }

    /** Active users holding the UAT_Tester permission set, ordered by name. */
    @AuraEnabled
    public static List<OptionDTO> getTesterPool() {
        assertTeamsReadable();
        Map<Id, OptionDTO> byUser = new Map<Id, OptionDTO>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, Assignee.Name
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'UAT_Tester'
            AND Assignee.IsActive = true
            ORDER BY Assignee.Name
        ]) {
            OptionDTO o = new OptionDTO();
            o.value = psa.AssigneeId;
            o.label = psa.Assignee.Name;
            byUser.put(psa.AssigneeId, o);
        }
        return byUser.values();
    }

    /** Active internal users matching the term who are NOT yet in the pool. */
    @AuraEnabled
    public static List<OptionDTO> searchUsers(String term) {
        assertTeamAdmin();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return new List<OptionDTO>();
        }
        Set<Id> pool = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'UAT_Tester'
        ]) {
            pool.add(psa.AssigneeId);
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        List<OptionDTO> result = new List<OptionDTO>();
        for (User u : [
            SELECT Id, Name FROM User
            WHERE IsActive = true AND UserType = 'Standard'
            AND Name LIKE :likeTerm AND Id NOT IN :pool
            ORDER BY Name
            LIMIT 10
        ]) {
            OptionDTO o = new OptionDTO();
            o.value = u.Id;
            o.label = u.Name;
            result.add(o);
        }
        return result;
    }

    // ---- Writes ---------------------------------------------------------------

    /** Create/rename a team and reconcile its member list in one call. */
    @AuraEnabled
    public static Id saveTeam(String inputJson) {
        assertTeamAdmin();
        TeamInput input;
        try {
            input = String.isBlank(inputJson)
                ? null
                : (TeamInput) JSON.deserialize(inputJson, TeamInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
        if (input == null || String.isBlank(input.name)) {
            throw auraError('Give the team a name.');
        }

        Team__c team = new Team__c(Id = input.id, Name = input.name.trim());
        SObjectAccessDecision decision = Security.stripInaccessible(
            team.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
            new List<Team__c>{ team }
        );
        Team__c stripped = (Team__c) decision.getRecords()[0];
        if (team.Id == null) {
            insert stripped;
            team.Id = stripped.Id;
        } else {
            update stripped;
        }

        // Reconcile members: delete the removed, insert the added.
        Set<Id> wanted = new Set<Id>(input.memberUserIds != null ? input.memberUserIds : new List<Id>());
        List<Team_Member__c> toDelete = new List<Team_Member__c>();
        for (Team_Member__c existing : [
            SELECT Id, User__c FROM Team_Member__c WHERE Team__c = :team.Id
        ]) {
            if (wanted.contains(existing.User__c)) {
                wanted.remove(existing.User__c); // already a member
            } else {
                toDelete.add(existing);
            }
        }
        List<Team_Member__c> toInsert = new List<Team_Member__c>();
        for (Id userId : wanted) {
            toInsert.add(new Team_Member__c(Team__c = team.Id, User__c = userId));
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        return team.Id;
    }

    /** Assign UAT_Tester to an existing internal user (grow the pool). */
    @AuraEnabled
    public static void addUserToPool(Id userId) {
        assertTeamAdmin();
        if (userId == null) {
            throw auraError('Pick a user to add.');
        }
        PermissionSet testerSet = [
            SELECT Id FROM PermissionSet WHERE Name = 'UAT_Tester' LIMIT 1
        ];
        Integer already = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :testerSet.Id
        ];
        if (already > 0) {
            return; // idempotent — they're already a tester
        }
        try {
            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = testerSet.Id
            );
        } catch (DmlException e) {
            throw auraError('Could not make that user a tester — you need the '
                + '"Assign Permission Sets" permission. Ask a system admin to grant it '
                + 'or to assign UAT Tester directly.');
        }
    }

    // ---- Delete (2026-08-05) ----------------------------------------------------

    public class TeamDeleteImpactDTO {
        @AuraEnabled public String teamName;
        @AuraEnabled public List<String> openCycleNames = new List<String>(); // any = blocked
        @AuraEnabled public Integer closedCycleCount;
        @AuraEnabled public Integer memberCount;
    }

    /** What blocks (open cycles) or is affected (closed-cycle references,
     *  member links) — drives the delete confirm. */
    @AuraEnabled
    public static TeamDeleteImpactDTO getTeamDeleteImpact(Id teamId) {
        assertTeamsReadable();
        Team__c team;
        try {
            team = [SELECT Name FROM Team__c WHERE Id = :teamId];
        } catch (QueryException e) {
            throw auraError('That team no longer exists.');
        }
        TeamDeleteImpactDTO dto = new TeamDeleteImpactDTO();
        dto.teamName = team.Name;
        // != Closed deliberately includes null-status cycles (legacy Active).
        for (Test_Cycle__c c : [
            SELECT Name FROM Test_Cycle__c
            WHERE Assigned_Team__c = :teamId
            AND Status__c != :UatConstants.CYCLE_CLOSED
            ORDER BY Name
            LIMIT 10
        ]) {
            dto.openCycleNames.add(c.Name);
        }
        dto.closedCycleCount = [
            SELECT COUNT() FROM Test_Cycle__c
            WHERE Assigned_Team__c = :teamId
            AND Status__c = :UatConstants.CYCLE_CLOSED
        ];
        dto.memberCount = [SELECT COUNT() FROM Team_Member__c WHERE Team__c = :teamId];
        return dto;
    }

    /** Blocked while any open cycle is assigned to the team (see class doc —
     *  deleting would open that work to every tester). Member links cascade;
     *  users keep their tester access (the permset, not the team, grants it). */
    @AuraEnabled
    public static void deleteTeam(Id teamId) {
        assertTeamAdmin();
        if (!Schema.sObjectType.Team__c.isDeletable()) {
            throw auraError('You do not have access to delete UAT teams.');
        }
        TeamDeleteImpactDTO impact = getTeamDeleteImpact(teamId);
        if (!impact.openCycleNames.isEmpty()) {
            throw auraError('Can\'t delete ' + impact.teamName + ' — '
                + (impact.openCycleNames.size() == 1 ? 'cycle ' : 'cycles ')
                + String.join(impact.openCycleNames, ', ')
                + (impact.openCycleNames.size() == 1 ? ' is' : ' are')
                + ' assigned to it. Reassign or close those cycles first; deleting this team would open their work to every tester.');
        }
        try {
            delete new Team__c(Id = teamId);
        } catch (DmlException e) {
            throw auraError('The team could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    // ---- Internals -------------------------------------------------------------

    private static void assertTeamAdmin() {
        if (!Schema.sObjectType.Team__c.isCreateable()
            || !Schema.sObjectType.Team__c.isUpdateable()) {
            throw auraError('You do not have access to manage UAT teams.');
        }
    }

    private static void assertTeamsReadable() {
        if (!Schema.sObjectType.Team__c.isAccessible()
            || !Schema.sObjectType.Team_Member__c.isAccessible()) {
            throw auraError('You do not have access to UAT teams.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}