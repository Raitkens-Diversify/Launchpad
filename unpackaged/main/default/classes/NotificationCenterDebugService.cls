/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Debug-only digest helpers for manual email and in-app digest testing.
 */
public with sharing class NotificationCenterDebugService {
  private static final Integer DIGEST_SOURCE_RECORD_LIMIT = 10;
  private static final Integer ASSIGNMENT_LOOKUP_LIMIT = 100;
  private static final Set<String> SUPPORTED_OBJECT_TYPES = new Set<String>{
    NotificationConstants.OBJECT_TYPE_CASE,
    NotificationConstants.OBJECT_TYPE_TASK,
    NotificationConstants.OBJECT_TYPE_EVENT
  };

  public List<NotificationCenterDebugModels.DebugDigestItem> getDigestPreview(
    Id recipientId,
    String objectType
  ) {
    validateRecipientId(recipientId);
    validateObjectType(objectType);

    return toDebugItems(
      selectRecentDigestItems(
        recipientId,
        objectType,
        DIGEST_SOURCE_RECORD_LIMIT
      )
    );
  }

  public NotificationCenterDebugModels.DigestTriggerResult triggerDigest(
    Id recipientId,
    String objectType
  ) {
    validateRecipientId(recipientId);
    validateObjectType(objectType);

    List<Notification_Log__c> previewItems = selectRecentDigestItems(
      recipientId,
      objectType,
      null
    );

    if (previewItems.isEmpty()) {
      throw new IllegalArgumentException(buildEmptyItemsMessage(objectType));
    }

    List<Notification_Log__c> deliveryItems = expandDigestLogsForSourceRecords(
      recipientId,
      objectType,
      extractSourceRecordIds(previewItems)
    );

    NotificationLogDeliveryService.requeueForDebugDelivery(deliveryItems);
    List<Id> queuedLogIds = selectQueuedLogIds(extractLogIds(deliveryItems));
    publishDigestLogEvents(queuedLogIds);

    NotificationCenterDebugModels.DigestTriggerResult result = new NotificationCenterDebugModels.DigestTriggerResult();
    result.objectType = objectType;
    result.previewCount = previewItems.size();
    result.sourceRecordCount = extractSourceRecordIds(previewItems).size();
    result.publishedEventCount = queuedLogIds.size();
    result.deliveredCount = 0;
    result.customNotificationCount = 0;
    result.items = toDebugItems(deliveryItems);
    return result;
  }

  private static List<Notification_Log__c> selectRecentDigestItems(
    Id recipientId,
    String objectType,
    Integer maxSourceRecords
  ) {
    Integer queryLimit = requiresAssignmentFilter(objectType)
      ? ASSIGNMENT_LOOKUP_LIMIT
      : DIGEST_SOURCE_RECORD_LIMIT;

    List<Notification_Log__c> candidates = queryDigestCandidates(
      recipientId,
      objectType,
      queryLimit
    );

    if (!requiresAssignmentFilter(objectType)) {
      return candidates;
    }

    return filterToAssignedRecords(
      candidates,
      recipientId,
      objectType,
      maxSourceRecords
    );
  }

  private static List<Notification_Log__c> queryDigestCandidates(
    Id recipientId,
    String objectType,
    Integer queryLimit
  ) {
    return [
      SELECT
        Id,
        Title__c,
        Body__c,
        Channel__c,
        Frequency__c,
        Status__c,
        Delivered_At__c,
        CreatedDate,
        Source_Type__c,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Source_Type__c = :objectType
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        AND (
          Channel__c INCLUDES (:NotificationConstants.CHANNEL_EMAIL)
          OR Channel__c INCLUDES (:NotificationConstants.CHANNEL_IN_APP)
        )
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT :queryLimit
    ];
  }

  private static List<Notification_Log__c> expandDigestLogsForSourceRecords(
    Id recipientId,
    String objectType,
    Set<Id> sourceRecordIds
  ) {
    if (sourceRecordIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    List<String> sourceRecordIdStrings = new List<String>();
    for (Id sourceRecordId : sourceRecordIds) {
      sourceRecordIdStrings.add(String.valueOf(sourceRecordId));
    }

    return [
      SELECT
        Id,
        Title__c,
        Body__c,
        Channel__c,
        Frequency__c,
        Status__c,
        Delivered_At__c,
        CreatedDate,
        Source_Type__c,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Source_Type__c = :objectType
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        AND Source_Record_Id__c IN :sourceRecordIdStrings
        AND (
          Channel__c INCLUDES (:NotificationConstants.CHANNEL_EMAIL)
          OR Channel__c INCLUDES (:NotificationConstants.CHANNEL_IN_APP)
        )
      ORDER BY CreatedDate DESC, Id DESC
    ];
  }

  private static List<Id> extractLogIds(List<Notification_Log__c> items) {
    List<Id> logIds = new List<Id>();

    for (Notification_Log__c item : items) {
      logIds.add(item.Id);
    }

    return logIds;
  }

  private static Set<Id> extractSourceRecordIds(List<Notification_Log__c> items) {
    Set<Id> sourceRecordIds = new Set<Id>();

    for (Notification_Log__c item : items) {
      if (!String.isBlank(item.Source_Record_Id__c)) {
        sourceRecordIds.add((Id) item.Source_Record_Id__c);
      }
    }

    return sourceRecordIds;
  }

  private static List<Id> selectQueuedLogIds(List<Id> logIds) {
    List<Id> queuedLogIds = new List<Id>();

    if (logIds.isEmpty()) {
      return queuedLogIds;
    }

    for (Notification_Log__c logRecord : [
      SELECT Id
      FROM Notification_Log__c
      WHERE
        Id IN :logIds
        AND Status__c = :NotificationConstants.STATUS_QUEUED
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
    ]) {
      queuedLogIds.add(logRecord.Id);
    }

    return queuedLogIds;
  }

  private static void publishDigestLogEvents(List<Id> logIds) {
    if (logIds.isEmpty()) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (Id logId : logIds) {
      NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
        logId
      );
      request.frequency = NotificationConstants.FREQUENCY_DIGEST;
      request.deliverIndividually = true;
      requests.add(request);
    }

    NotificationDeliveryDispatcher.enqueueRequests(requests);
  }

  private static Boolean requiresAssignmentFilter(String objectType) {
    return objectType == NotificationConstants.OBJECT_TYPE_CASE ||
      objectType == NotificationConstants.OBJECT_TYPE_TASK;
  }

  private static List<Notification_Log__c> filterToAssignedRecords(
    List<Notification_Log__c> candidates,
    Id recipientId,
    String objectType,
    Integer maxSourceRecords
  ) {
    Set<Id> sourceRecordIds = extractSourceRecordIds(candidates);
    Set<Id> assignedRecordIds = selectAssignedRecordIds(
      sourceRecordIds,
      recipientId,
      objectType
    );
    List<Id> orderedAssignedSourceRecordIds = new List<Id>();
    Set<Id> seenSourceRecordIds = new Set<Id>();

    for (Notification_Log__c item : candidates) {
      if (String.isBlank(item.Source_Record_Id__c)) {
        continue;
      }

      Id sourceRecordId = (Id) item.Source_Record_Id__c;

      if (
        !assignedRecordIds.contains(sourceRecordId) ||
        seenSourceRecordIds.contains(sourceRecordId)
      ) {
        continue;
      }

      seenSourceRecordIds.add(sourceRecordId);
      orderedAssignedSourceRecordIds.add(sourceRecordId);

      if (
        maxSourceRecords != null &&
        orderedAssignedSourceRecordIds.size() >= maxSourceRecords
      ) {
        break;
      }
    }

    Set<Id> selectedSourceRecordIds = new Set<Id>(orderedAssignedSourceRecordIds);
    List<Notification_Log__c> assignedItems = new List<Notification_Log__c>();

    for (Notification_Log__c item : candidates) {
      if (
        !String.isBlank(item.Source_Record_Id__c) &&
        selectedSourceRecordIds.contains((Id) item.Source_Record_Id__c)
      ) {
        assignedItems.add(item);
      }
    }

    return assignedItems;
  }

  private static Set<Id> selectAssignedRecordIds(
    Set<Id> recordIds,
    Id recipientId,
    String objectType
  ) {
    Set<Id> assignedRecordIds = new Set<Id>();

    if (recordIds.isEmpty()) {
      return assignedRecordIds;
    }

    if (objectType == NotificationConstants.OBJECT_TYPE_CASE) {
      for (Case caseRecord : [
        SELECT Id
        FROM Case
        WHERE Id IN :recordIds AND OwnerId = :recipientId
      ]) {
        assignedRecordIds.add(caseRecord.Id);
      }

      return assignedRecordIds;
    }

    for (Task taskRecord : [
      SELECT Id
      FROM Task
      WHERE Id IN :recordIds AND OwnerId = :recipientId
    ]) {
      assignedRecordIds.add(taskRecord.Id);
    }

    return assignedRecordIds;
  }

  private static String buildEmptyItemsMessage(String objectType) {
    if (requiresAssignmentFilter(objectType)) {
      return 'No digest notifications were found for ' +
        objectType +
        ' records assigned to you.';
    }

    return 'No digest notifications were found for ' + objectType + '.';
  }

  private static List<NotificationCenterDebugModels.DebugDigestItem> toDebugItems(
    List<Notification_Log__c> items
  ) {
    List<NotificationCenterDebugModels.DebugDigestItem> debugItems = new List<NotificationCenterDebugModels.DebugDigestItem>();

    for (Notification_Log__c item : items) {
      NotificationCenterDebugModels.DebugDigestItem debugItem = new NotificationCenterDebugModels.DebugDigestItem();
      debugItem.id = item.Id;
      debugItem.title = item.Title__c;
      debugItem.body = item.Body__c;
      debugItem.channel = NotificationChannelUtils.resolveSingleChannel(
        item.Channel__c,
        null
      );
      debugItem.sourceRecordId = item.Source_Record_Id__c;
      debugItem.frequency = item.Frequency__c;
      debugItem.status = item.Status__c;
      debugItem.createdAt = item.CreatedDate;
      debugItem.deliveredAt = item.Delivered_At__c;
      debugItems.add(debugItem);
    }

    return debugItems;
  }

  private static void validateRecipientId(Id recipientId) {
    if (recipientId == null) {
      throw new IllegalArgumentException('Recipient Id is required.');
    }
  }

  private static void validateObjectType(String objectType) {
    if (String.isBlank(objectType) || !SUPPORTED_OBJECT_TYPES.contains(objectType)) {
      throw new IllegalArgumentException('Object type must be Case, Task, or Event.');
    }
  }
}