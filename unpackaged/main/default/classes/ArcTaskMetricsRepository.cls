/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Task category counts for arcTaskMetrics (main track vs pit stops).
 */
public with sharing class ArcTaskMetricsRepository {
  private final FinancialAdvisorTeamAccessService teamAccessService;

  public ArcTaskMetricsRepository() {
    this(new FinancialAdvisorTeamAccessService());
  }

  public ArcTaskMetricsRepository(
    FinancialAdvisorTeamAccessService teamAccessService
  ) {
    this.teamAccessService = teamAccessService;
  }

  public ArcTaskMetricsModels.MetricsResult selectMetrics(
    ArcRelatedTableScope.Value scope
  ) {
    ArcTaskMetricsModels.MetricsResult metrics = new ArcTaskMetricsModels.MetricsResult();
    Id currentUserId = UserInfo.getUserId();
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = teamAccessService.getCurrentUserTeamAccess();

    List<Task> taskRecords;
    if (scope == ArcRelatedTableScope.Value.MINE) {
      taskRecords = [
        SELECT Id, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
        FROM Task
        WHERE OwnerId = :currentUserId AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ];
    } else if (teamAccess.teamIds.isEmpty()) {
      return metrics;
    } else {
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

      if (relatedRecordIds.isEmpty()) {
        return metrics;
      }

      taskRecords = [
        SELECT Id, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
        FROM Task
        WHERE IsClosed = FALSE AND WhatId IN :relatedRecordIds
        WITH SECURITY_ENFORCED
      ];
    }

    for (Task taskRecord : taskRecords) {
      if (taskRecord.Home_Office_Pit_Stop__c == true) {
        metrics.hoPitStopCount++;
      }

      if (taskRecord.Branch_Pit_Stop__c == true) {
        metrics.branchPitStopCount++;
      }

      if (
        taskRecord.Home_Office_Pit_Stop__c != true &&
        taskRecord.Branch_Pit_Stop__c != true
      ) {
        metrics.mainTrackCount++;
      }
    }

    return metrics;
  }
}