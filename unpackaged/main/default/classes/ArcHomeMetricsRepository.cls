/**
 * Counts for the 5 Home dashboard metric tiles (Cases/Tasks assigned to me
 * and to my teams', plus My Pitstop Tasks). Mirrors the scope semantics
 * already established by ArcCaseMetricsRepository / ArcTaskMetricsRepository:
 * "mine" = Case/Task OwnerId, "my teams'" = Financial_Advisor_Team__c
 * membership via FinancialAdvisorTeamAccessService.
 *
 * "My Pitstop Tasks" = the user's own open Tasks flagged Branch_Pit_Stop__c
 * or Home_Office_Pit_Stop__c -- the same two booleans ArcTaskMetricsRepository
 * treats as the source of truth for the Task donut's pit stop slices, so this
 * tile equals that donut's "HO pit stop" + "Branch pit stop" for the same
 * user. (Until 2026-09-04 the tile instead counted the user's own Cases that
 * had an open Home Office pit stop task -- a case-owner scope that stayed at
 * 0 for advisors whose pit stop tasks sit on other people's cases.)
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

    result.pitStopTasksAssignedToMe = [
        SELECT Id
        FROM Task
        WHERE
          OwnerId = :currentUserId
          AND IsClosed = FALSE
          AND (Branch_Pit_Stop__c = TRUE OR Home_Office_Pit_Stop__c = TRUE)
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