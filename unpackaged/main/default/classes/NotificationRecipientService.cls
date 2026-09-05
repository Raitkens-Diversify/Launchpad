/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Resolves eligible notification recipients from FA Team membership and preferences.
 *
 * Recipients include active FA team members. Notification preferences and org
 * system defaults determine whether each recipient actually receives delivery.
 */
public without sharing class NotificationRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

  public List<Id> getRecipientsForSourceRecord(
    String sourceType,
    SObject sourceRecord,
    Id householdId
  ) {
    List<Id> testOverrideRecipientIds = resolveTestRecipientOverride(
      sourceType,
      sourceRecord,
      householdId
    );
    if (testOverrideRecipientIds != null) {
      return resolveTaskRecipientsWithTestOverride(
        sourceType,
        sourceRecord,
        testOverrideRecipientIds
      );
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_CASE &&
      sourceRecord instanceof Case
    ) {
      return new NotificationCaseRecipientService()
        .resolveRecipients((Case) sourceRecord, householdId);
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_EVENT &&
      sourceRecord instanceof Event
    ) {
      return new NotificationEventRecipientService()
        .resolveRecipients((Event) sourceRecord, householdId);
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_TASK &&
      sourceRecord instanceof Task
    ) {
      Task taskRecord = (Task) sourceRecord;
      Set<Id> recipientIdSet = new Set<Id>();

      if (
        NotificationConstants.isPitStopTask(taskRecord) &&
        NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord)
      ) {
        recipientIdSet.addAll(
          NotificationTaskPitStopService.resolveRecipients(taskRecord)
        );
      }

      if (NotificationConstants.shouldResolveNormalTaskRecipientsForPitStopTask(
        taskRecord
      )) {
        List<Id> normalRecipientIds = new NotificationTaskRecipientService()
          .resolveRecipients(taskRecord, householdId);
        recipientIdSet.addAll(
          filterNormalTaskRecipientsForPitStopTask(
            taskRecord,
            normalRecipientIds
          )
        );
      }

      return new List<Id>(recipientIdSet);
    }

    if (householdId == null) {
      return new List<Id>();
    }

    Map<Id, List<Id>> householdIdToRecipientIds = getRecipientsByHousehold(
      new Set<Id>{ householdId }
    );
    List<Id> recipientIds = householdIdToRecipientIds.get(householdId);

    return recipientIds == null ? new List<Id>() : recipientIds;
  }

  public Map<Id, List<Id>> getRecipientsByHousehold(Set<Id> householdIds) {
    Map<Id, List<Id>> householdIdToRecipientIds = new Map<Id, List<Id>>();
    if (householdIds == null || householdIds.isEmpty()) {
      return householdIdToRecipientIds;
    }

    if (Test.isRunningTest() && testRecipientOverrides != null) {
      for (Id householdId : householdIds) {
        if (testRecipientOverrides.containsKey(householdId)) {
          householdIdToRecipientIds.put(
            householdId,
            testRecipientOverrides.get(householdId)
          );
        }
      }
      return householdIdToRecipientIds;
    }

    Map<Id, Id> householdIdToTeamId = selectTeamIdByHouseholdId(householdIds);
    if (householdIdToTeamId.isEmpty()) {
      return householdIdToRecipientIds;
    }

    Set<Id> teamIds = new Set<Id>(householdIdToTeamId.values());
    Map<Id, Set<Id>> teamIdToActiveMemberUserIds = NotificationRecipientUserRepository.selectEligibleActiveMemberUserIdsByTeamId(
      teamIds
    );

    for (Id householdId : householdIdToTeamId.keySet()) {
      Id teamId = householdIdToTeamId.get(householdId);
      Set<Id> activeMemberUserIds = teamIdToActiveMemberUserIds.get(teamId);
      if (activeMemberUserIds == null || activeMemberUserIds.isEmpty()) {
        continue;
      }

      householdIdToRecipientIds.put(
        householdId,
        new List<Id>(activeMemberUserIds)
      );
    }

    return householdIdToRecipientIds;
  }

  private Map<Id, Id> selectTeamIdByHouseholdId(Set<Id> householdIds) {
    Map<Id, Id> householdIdToTeamId = new Map<Id, Id>();

    for (Account household : [
      SELECT Id, Financial_Advisor_Team__c
      FROM Account
      WHERE Id IN :householdIds AND Financial_Advisor_Team__c != NULL
    ]) {
      householdIdToTeamId.put(household.Id, household.Financial_Advisor_Team__c);
    }

    return householdIdToTeamId;
  }

  private List<Id> resolveTestRecipientOverride(
    String sourceType,
    SObject sourceRecord,
    Id householdId
  ) {
    if (!Test.isRunningTest() || testRecipientOverrides == null) {
      return null;
    }

    if (sourceRecord != null && testRecipientOverrides.containsKey(sourceRecord.Id)) {
      return new List<Id>(testRecipientOverrides.get(sourceRecord.Id));
    }

    if (householdId != null && testRecipientOverrides.containsKey(householdId)) {
      return new List<Id>(testRecipientOverrides.get(householdId));
    }

    Id relatedHouseholdId = resolveRelatedHouseholdIdForOverride(
      sourceType,
      sourceRecord
    );
    if (
      relatedHouseholdId != null &&
      testRecipientOverrides.containsKey(relatedHouseholdId)
    ) {
      return new List<Id>(testRecipientOverrides.get(relatedHouseholdId));
    }

    return null;
  }

  private Id resolveRelatedHouseholdIdForOverride(
    String sourceType,
    SObject sourceRecord
  ) {
    if (sourceRecord == null) {
      return null;
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_CASE &&
      sourceRecord instanceof Case
    ) {
      return ((Case) sourceRecord).AccountId;
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_TASK &&
      sourceRecord instanceof Task
    ) {
      return ((Task) sourceRecord).WhatId;
    }

    if (
      sourceType == NotificationConstants.OBJECT_TYPE_EVENT &&
      sourceRecord instanceof Event
    ) {
      return ((Event) sourceRecord).WhatId;
    }

    return null;
  }

  private List<Id> resolveTaskRecipientsWithTestOverride(
    String sourceType,
    SObject sourceRecord,
    List<Id> testOverrideRecipientIds
  ) {
    if (
      sourceType != NotificationConstants.OBJECT_TYPE_TASK ||
      !(sourceRecord instanceof Task)
    ) {
      return testOverrideRecipientIds;
    }

    Task taskRecord = (Task) sourceRecord;
    List<Id> filteredOverrideRecipientIds = filterNormalTaskRecipientsForPitStopTask(
      taskRecord,
      testOverrideRecipientIds
    );

    if (
      NotificationConstants.isPitStopTask(taskRecord) &&
      NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord)
    ) {
      Set<Id> recipientIdSet = new Set<Id>(filteredOverrideRecipientIds);
      recipientIdSet.addAll(
        NotificationTaskPitStopService.resolveRecipients(taskRecord)
      );
      return new List<Id>(recipientIdSet);
    }

    return filteredOverrideRecipientIds;
  }

  private List<Id> filterNormalTaskRecipientsForPitStopTask(
    Task taskRecord,
    List<Id> recipientIds
  ) {
    if (
      recipientIds == null ||
      recipientIds.isEmpty() ||
      !NotificationConstants.isPitStopTask(taskRecord)
    ) {
      return recipientIds == null ? new List<Id>() : recipientIds;
    }

    Map<Id, User> eligibleUsersById = NotificationRecipientUserRepository.selectEligibleUsersById(
      new Set<Id>(recipientIds)
    );
    List<Id> filteredRecipientIds = new List<Id>();

    for (Id recipientId : recipientIds) {
      User eligibleUser = eligibleUsersById.get(recipientId);
      if (eligibleUser == null) {
        continue;
      }

      if (
        NotificationConstants.shouldIncludeRecipientInNormalTaskNotifications(
          taskRecord,
          eligibleUser.Profile.Name,
          eligibleUser.UserType
        )
      ) {
        filteredRecipientIds.add(recipientId);
      }
    }

    return filteredRecipientIds;
  }
}