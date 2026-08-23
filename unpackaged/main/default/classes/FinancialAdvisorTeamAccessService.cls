/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Resolves Financial Advisor Team membership for the running user.
 */
public with sharing class FinancialAdvisorTeamAccessService {
  public class TeamAccessContext {
    public Set<Id> teamIds { get; private set; }
    public Set<Id> teamMemberUserIds { get; private set; }

    public TeamAccessContext(Set<Id> teamIds, Set<Id> teamMemberUserIds) {
      this.teamIds = teamIds == null ? new Set<Id>() : teamIds;
      this.teamMemberUserIds = teamMemberUserIds == null
        ? new Set<Id>()
        : teamMemberUserIds;
    }
  }

  public TeamAccessContext getCurrentUserTeamAccess() {
    Id currentUserId = UserInfo.getUserId();
    Set<Id> teamIds = new Set<Id>();

    for (Financial_Advisor_Team_Member__c membership : [
      SELECT Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :currentUserId
      WITH SECURITY_ENFORCED
    ]) {
      if (membership.Financial_Advisor_Team__c != null) {
        teamIds.add(membership.Financial_Advisor_Team__c);
      }
    }

    Set<Id> teamMemberUserIds = new Set<Id>{ currentUserId };
    if (!teamIds.isEmpty()) {
      for (Financial_Advisor_Team_Member__c member : [
        SELECT User__c
        FROM Financial_Advisor_Team_Member__c
        WHERE
          Financial_Advisor_Team__c IN :teamIds
          AND User__c != NULL
        WITH SECURITY_ENFORCED
      ]) {
        teamMemberUserIds.add(member.User__c);
      }
    }

    return new TeamAccessContext(teamIds, teamMemberUserIds);
  }
}