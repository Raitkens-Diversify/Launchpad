/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-07
 *
 * Builds source prepare context for chunked notification recipient processing.
 * Task insert and Assigned To updates resolve the Assigned To user only.
 * FA Team members and queue Assigned To values never receive Task notifications.
 */
public without sharing class NotificationPrepareContextFactory {
  public static NotificationRecipientPrepareModels.SourcePrepareContext build(
    String sourceType,
    String sourceId,
    String changeContextJson
  ) {
    if (String.isBlank(sourceType) || String.isBlank(sourceId)) {
      return null;
    }

    SObject sourceRecord = querySourceRecord(sourceType, sourceId);
    if (sourceRecord == null) {
      return null;
    }

    NotificationHouseholdResolver householdResolver = new NotificationHouseholdResolver();
    Map<Id, Id> recordIdToHouseholdId = householdResolver.resolveHouseholds(
      new List<SObject>{ sourceRecord },
      sourceType
    );
    Id householdId = recordIdToHouseholdId.get(sourceRecord.Id);

    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      changeContextJson
    );
    Boolean isTaskSource =
      sourceType == NotificationConstants.OBJECT_TYPE_TASK &&
      sourceRecord instanceof Task;
    Boolean isTaskUpdate = isTaskAssigneeUpdate(
      sourceType,
      sourceRecord,
      changeContext
    );

    List<Id> recipientIds = isTaskSource
      ? resolveTaskRecipientIds((Task) sourceRecord, changeContext, isTaskUpdate)
      : new NotificationRecipientService()
          .getRecipientsForSourceRecord(sourceType, sourceRecord, householdId);

    Set<Id> pitStopBypassRecipientIds = new Set<Id>();
    if (
      isTaskSource &&
      !isTaskUpdate &&
      !NotificationTaskRecipientService.isAssignedToQueue((Task) sourceRecord)
    ) {
      Task taskRecord = (Task) sourceRecord;
      if (NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord)) {
        pitStopBypassRecipientIds.addAll(
          NotificationTaskRecipientService.excludeCreatorRecipients(
            taskRecord,
            NotificationTaskPitStopService.resolveRecipients(taskRecord)
          )
        );
      }
    }

    Set<Id> mergedRecipientIds = new Set<Id>(recipientIds);
    mergedRecipientIds.addAll(pitStopBypassRecipientIds);
    if (mergedRecipientIds.isEmpty()) {
      return null;
    }

    NotificationRecipientPrepareModels.SourcePrepareContext prepareContext = new NotificationRecipientPrepareModels.SourcePrepareContext();
    prepareContext.sourceType = sourceType;
    prepareContext.sourceId = sourceId;
    prepareContext.householdId = householdId;
    prepareContext.correlationKey = buildCorrelationKey(sourceRecord.Id);
    prepareContext.changeContextJson = changeContextJson;
    prepareContext.enrichedChangeContextJson = NotificationChangeModels.mergeAndEnrichJson(
      changeContextJson,
      sourceRecord,
      sourceType
    );
    prepareContext.recipientIds = new List<Id>(mergedRecipientIds);
    prepareContext.pitStopBypassRecipientIds.addAll(pitStopBypassRecipientIds);

    return prepareContext;
  }

  private static List<Id> resolveTaskRecipientIds(
    Task taskRecord,
    NotificationChangeModels.ChangeContext changeContext,
    Boolean isTaskUpdate
  ) {
    List<Id> recipientIds = new NotificationTaskRecipientService()
      .resolveAssigneeOnlyRecipients(taskRecord, changeContext);

    if (isTaskUpdate) {
      return recipientIds;
    }

    if (
      !NotificationConstants.shouldResolveNormalTaskRecipientsForPitStopTask(
        taskRecord
      )
    ) {
      return new List<Id>();
    }

    return filterNormalTaskRecipientsForPitStopTask(taskRecord, recipientIds);
  }

  private static List<Id> filterNormalTaskRecipientsForPitStopTask(
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

  private static Boolean isTaskAssigneeUpdate(
    String sourceType,
    SObject sourceRecord,
    NotificationChangeModels.ChangeContext changeContext
  ) {
    return sourceType == NotificationConstants.OBJECT_TYPE_TASK &&
      sourceRecord instanceof Task &&
      changeContext != null &&
      NotificationConstants.CHANGE_TYPE_UPDATE.equalsIgnoreCase(
        changeContext.triggerType
      );
  }

  public static NotificationRecipientPrepareModels.SourcePrepareContext buildFromContinuation(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest
  ) {
    if (continuationRequest == null) {
      return null;
    }

    NotificationRecipientPrepareModels.SourcePrepareContext prepareContext = build(
      continuationRequest.sourceType,
      continuationRequest.sourceId,
      continuationRequest.changeContextJson
    );

    if (prepareContext == null) {
      return null;
    }

    if (!String.isBlank(continuationRequest.correlationKey)) {
      prepareContext.correlationKey = continuationRequest.correlationKey;
    }

    return prepareContext;
  }

  private static SObject querySourceRecord(String sourceType, String sourceId) {
    Id recordId = (Id) sourceId;

    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      List<Case> cases = [
        SELECT
          Id,
          CaseNumber,
          Subject,
          AccountId,
          OwnerId,
          CreatedById,
          Financial_Advisor_Team__c
        FROM Case
        WHERE Id = :recordId
        LIMIT 1
      ];
      return cases.isEmpty() ? null : cases[0];
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_TASK) {
      List<Task> tasks = [
        SELECT
          Id,
          Subject,
          WhatId,
          OwnerId,
          CreatedById,
          Branch_Pit_Stop__c,
          Home_Office_Pit_Stop__c
        FROM Task
        WHERE Id = :recordId
        LIMIT 1
      ];

      if (tasks.isEmpty()) {
        return null;
      }

      return tasks[0];
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_EVENT) {
      List<Event> events = [
        SELECT Id, Subject, WhoId, WhatId, OwnerId, CreatedById
        FROM Event
        WHERE Id = :recordId
        LIMIT 1
      ];
      return events.isEmpty() ? null : events[0];
    }

    return null;
  }

  private static String buildCorrelationKey(Id recordId) {
    return recordId + '-' + String.valueOf(System.now().getTime());
  }
}