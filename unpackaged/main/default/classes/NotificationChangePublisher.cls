/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
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
}