/**
 * Counts for the 5 Home dashboard metric tiles (Cases/Tasks assigned to me
 * and to my teams', plus Cases awaiting Home Office review). Mirrors the
 * scope semantics already established by ArcCaseMetricsRepository /
 * ArcTaskMetricsRepository: "mine" = Case/Task OwnerId, "my teams'" =
 * Financial_Advisor_Team__c membership via FinancialAdvisorTeamAccessService.
 *
 * "Awaiting Home Office" has no direct status field on Case — it's derived
 * from the same Home_Office_Pit_Stop__c boolean ArcTaskMetricsRepository
 * already treats as the source of truth for "HO" on Task, joined back to
 * the owning Case.
 */
public with sharing class ArcHomeMetricsRepository {
  private final FinancialAdvisorTeamAccessService teamAccessService;

  public ArcHomeMetricsRepository() {
    this(new FinancialAdvisorTeamAccessService());
  }

  public ArcHomeMetricsRepository(
    FinancialAdvisorTeamAccessService teamAccessService
  ) {
    this.teamAccessService = teamAccessService;
  }

  public ArcHomeMetricsModels.MetricsResult selectMetrics() {
    ArcHomeMetricsModels.MetricsResult result = new ArcHomeMetricsModels.MetricsResult();
    Id currentUserId = UserInfo.getUserId();

    result.casesAssignedToMe = [
        SELECT Id
        FROM Case
        WHERE OwnerId = :currentUserId AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ]
      .size();

    result.tasksAssignedToMe = [
        SELECT Id
        FROM Task
        WHERE OwnerId = :currentUserId AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ]
      .size();

    Set<Id> hoPitStopCaseIds = new Set<Id>();
    for (Task hoTask : [
      SELECT WhatId
      FROM Task
      WHERE
        Home_Office_Pit_Stop__c = TRUE
        AND IsClosed = FALSE
        AND WhatId != NULL
      WITH SECURITY_ENFORCED
    ]) {
      hoPitStopCaseIds.add(hoTask.WhatId);
    }

    result.casesAwaitingHomeOffice = hoPitStopCaseIds.isEmpty()
      ? 0
      : [
            SELECT Id
            FROM Case
            WHERE
              OwnerId = :currentUserId
              AND IsClosed = FALSE
              AND Id IN :hoPitStopCaseIds
            WITH SECURITY_ENFORCED
          ]
          .size();

    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();
    if (teamAccess.teamIds.isEmpty()) {
      return result;
    }

    result.casesAssignedToMyTeams = [
        SELECT Id
        FROM Case
        WHERE
          Financial_Advisor_Team__c IN :teamAccess.teamIds
          AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ]
      .size();

    Set<Id> relatedRecordIds = new Set<Id>();
    for (Case caseRecord : [
      SELECT Id
      FROM Case
      WHERE Financial_Advisor_Team__c IN :teamAccess.teamIds
      WITH SECURITY_ENFORCED
    ]) {
      relatedRecordIds.add(caseRecord.Id);
    }
    for (Account accountRecord : [
      SELECT Id
      FROM Account
      WHERE Financial_Advisor_Team__c IN :teamAccess.teamIds
      WITH SECURITY_ENFORCED
    ]) {
      relatedRecordIds.add(accountRecord.Id);
    }

    if (!relatedRecordIds.isEmpty()) {
      result.tasksAssignedToMyTeams = [
          SELECT Id
          FROM Task
          WHERE IsClosed = FALSE AND WhatId IN :relatedRecordIds
          WITH SECURITY_ENFORCED
        ]
        .size();
    }

    return result;
  }
}