/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-07
 *
 * Shared trigger helper for publishing notification center events on record changes.
 */
public with sharing class NotificationChangePublisher {
  public static void publishInserts(String objectType, List<SObject> records) {
    publish(objectType, records, null, null);
  }

  public static void publishUpdates(
    String objectType,
    Map<Id, SObject> newMap,
    Map<Id, SObject> oldMap
  ) {
    publish(
      objectType,
      newMap == null ? new List<SObject>() : newMap.values(),
      newMap,
      oldMap
    );
  }

  @TestVisible
  private static void publish(
    String objectType,
    List<SObject> records,
    Map<Id, SObject> newMap,
    Map<Id, SObject> oldMap
  ) {
    if (String.isBlank(objectType) || records == null || records.isEmpty()) {
      return;
    }

    List<SObject> notificationCenterRecords = records;

    Map<Id, SObject> notificationCenterNewMap = newMap == null
      ? newMap
      : buildNotificationCenterNewMap(newMap, notificationCenterRecords);

    NotificationChangeDetector changeDetector = new NotificationChangeDetector();
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = oldMap == null
      ? changeDetector.detectInserts(objectType, notificationCenterRecords)
      : changeDetector.detectUpdates(objectType, notificationCenterNewMap, oldMap);

    if (objectType == NotificationConstants.OBJECT_TYPE_TASK) {
      if (oldMap == null) {
        contextByRecordId = filterTaskQueueInserts(
          contextByRecordId,
          notificationCenterRecords
        );
      } else {
        contextByRecordId = filterTaskAssigneeUpdates(
          contextByRecordId,
          notificationCenterNewMap
        );
      }
    }

    if (contextByRecordId.isEmpty()) {
      return;
    }

    Map<Id, SObject> recordById = new Map<Id, SObject>();
    for (SObject record : notificationCenterRecords) {
      if (record.Id != null) {
        recordById.put(record.Id, record);
      }
    }

    for (Id recordId : contextByRecordId.keySet()) {
      contextByRecordId.get(recordId).enrichDmlContext(recordById.get(recordId));
    }

    List<SObject> recordsToPublish = new List<SObject>();
    for (SObject record : notificationCenterRecords) {
      if (record.Id != null && contextByRecordId.containsKey(record.Id)) {
        recordsToPublish.add(record);
      }
    }

    if (!recordsToPublish.isEmpty()) {
      NotificationPublisher.publishWithContext(
        recordsToPublish,
        objectType,
        contextByRecordId
      );
    }
  }

  @TestVisible
  private static Map<Id, SObject> buildNotificationCenterNewMap(
    Map<Id, SObject> newMap,
    List<SObject> notificationCenterRecords
  ) {
    if (newMap == null || notificationCenterRecords == null || notificationCenterRecords.isEmpty()) {
      return newMap;
    }

    Map<Id, SObject> notificationCenterNewMap = new Map<Id, SObject>();

    for (SObject record : notificationCenterRecords) {
      if (record.Id != null && newMap.containsKey(record.Id)) {
        notificationCenterNewMap.put(record.Id, record);
      }
    }

    return notificationCenterNewMap;
  }

  @TestVisible
  private static Map<Id, NotificationChangeModels.ChangeContext> filterTaskQueueInserts(
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId,
    List<SObject> records
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> filteredContextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (contextByRecordId == null || contextByRecordId.isEmpty()) {
      return filteredContextByRecordId;
    }

    Map<Id, SObject> recordById = new Map<Id, SObject>();
    if (records != null) {
      for (SObject record : records) {
        if (record != null && record.Id != null) {
          recordById.put(record.Id, record);
        }
      }
    }

    for (Id recordId : contextByRecordId.keySet()) {
      SObject record = recordById.get(recordId);
      if (record == null) {
        continue;
      }

      Id ownerId = (Id) record.get('OwnerId');
      if (ownerId != null && !isUserId(ownerId)) {
        continue;
      }

      filteredContextByRecordId.put(recordId, contextByRecordId.get(recordId));
    }

    return filteredContextByRecordId;
  }

  @TestVisible
  private static Map<Id, NotificationChangeModels.ChangeContext> filterTaskAssigneeUpdates(
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId,
    Map<Id, SObject> newMap
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> filteredContextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (contextByRecordId == null || contextByRecordId.isEmpty()) {
      return filteredContextByRecordId;
    }

    Id actorUserId = UserInfo.getUserId();

    for (Id recordId : contextByRecordId.keySet()) {
      NotificationChangeModels.ChangeContext changeContext = contextByRecordId.get(
        recordId
      );
      if (!hasOwnerIdChange(changeContext)) {
        continue;
      }

      SObject record = newMap == null ? null : newMap.get(recordId);
      if (record == null) {
        continue;
      }

      Id ownerId = (Id) record.get('OwnerId');
      if (!isUserId(ownerId) || ownerId == actorUserId) {
        continue;
      }

      filteredContextByRecordId.put(recordId, changeContext);
    }

    return filteredContextByRecordId;
  }

  private static Boolean hasOwnerIdChange(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (changeContext == null || changeContext.changedFields == null) {
      return false;
    }

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      if (fieldChange != null && fieldChange.apiName == 'OwnerId') {
        return true;
      }
    }

    return false;
  }

  private static Boolean isUserId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('005');
  }
}