/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Builds source prepare context for chunked notification recipient processing.
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

    List<Id> recipientIds = new NotificationRecipientService()
      .getRecipientsForSourceRecord(sourceType, sourceRecord, householdId);

    if (recipientIds.isEmpty()) {
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
    prepareContext.recipientIds = recipientIds;

    if (sourceRecord instanceof Task) {
      Task taskRecord = (Task) sourceRecord;

      if (NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord)) {
        prepareContext.pitStopBypassRecipientIds.addAll(
          NotificationTaskPitStopService.resolveRecipients(taskRecord)
        );
      }
    }

    return prepareContext;
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