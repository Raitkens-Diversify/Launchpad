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
    ARCConstants.RelatedTableScope scope
  ) {
    ArcTaskMetricsModels.MetricsResult metrics = new ArcTaskMetricsModels.MetricsResult();
    Id currentUserId = UserInfo.getUserId();

    List<Task> taskRecords;
    if (scope == ARCConstants.RelatedTableScope.MINE) {
      taskRecords = selectOwnedOpenTasks(currentUserId);
    } else {
      taskRecords = selectTeamScopeTasks(
        currentUserId,
        teamAccessService.getCurrentUserTeamAccess()
      );
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

  private List<Task> selectOwnedOpenTasks(Id ownerId) {
    return [
      SELECT Id, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
      FROM Task
      WHERE OwnerId = :ownerId AND IsClosed = FALSE
      WITH SECURITY_ENFORCED
    ];
  }

  private List<Task> selectTeamScopeTasks(
    Id currentUserId,
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess
  ) {
    Map<Id, Task> tasksById = new Map<Id, Task>();

    for (Task ownedTask : selectOwnedOpenTasks(currentUserId)) {
      tasksById.put(ownedTask.Id, ownedTask);
    }

    if (teamAccess.teamIds.isEmpty()) {
      return tasksById.values();
    }

    Set<Id> relatedRecordIds = selectTeamRelatedRecordIds(teamAccess.teamIds);
    if (relatedRecordIds.isEmpty()) {
      return tasksById.values();
    }

    for (Task teamTask : [
      SELECT Id, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
      FROM Task
      WHERE IsClosed = FALSE AND WhatId IN :relatedRecordIds
      WITH SECURITY_ENFORCED
    ]) {
      tasksById.put(teamTask.Id, teamTask);
    }

    return tasksById.values();
  }

  private Set<Id> selectTeamRelatedRecordIds(Set<Id> teamIds) {
    Set<Id> relatedRecordIds = new Set<Id>();

    for (Case caseRecord : [
      SELECT Id
      FROM Case
      WHERE Financial_Advisor_Team__c IN :teamIds
      WITH SECURITY_ENFORCED
    ]) {
      relatedRecordIds.add(caseRecord.Id);
    }

    for (Account accountRecord : [
      SELECT Id
      FROM Account
      WHERE Financial_Advisor_Team__c IN :teamIds
      WITH SECURITY_ENFORCED
    ]) {
      relatedRecordIds.add(accountRecord.Id);
    }

    return relatedRecordIds;
  }
}