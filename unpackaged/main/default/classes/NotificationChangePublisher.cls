/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-09
 *
 * Shared trigger helper for publishing notification center events on record changes.
 * Inserts published in the same transaction are not republished as updates, so Case
 * automation that updates a just-created record does not send "Case Updated".
 */
public with sharing class NotificationChangePublisher {
  private static Set<Id> publishedInsertRecordIds = new Set<Id>();
  private static Set<String> publishedUpdateFingerprints = new Set<String>();

  @TestVisible
  public static void resetPublishedInsertsForTest() {
    publishedInsertRecordIds = new Set<Id>();
    publishedUpdateFingerprints = new Set<String>();
  }

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

    if (oldMap == null) {
      publishedInsertRecordIds.addAll(contextByRecordId.keySet());
    } else {
      contextByRecordId = excludePublishedInserts(contextByRecordId);
      contextByRecordId = excludePublishedUpdateFingerprints(contextByRecordId);
    }

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

    if (oldMap != null) {
      addPublishedUpdateFingerprints(contextByRecordId);
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

  private static Map<Id, NotificationChangeModels.ChangeContext> excludePublishedInserts(
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> filteredContextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (contextByRecordId == null || contextByRecordId.isEmpty()) {
      return filteredContextByRecordId;
    }

    for (Id recordId : contextByRecordId.keySet()) {
      if (!publishedInsertRecordIds.contains(recordId)) {
        filteredContextByRecordId.put(recordId, contextByRecordId.get(recordId));
      }
    }

    return filteredContextByRecordId;
  }

  @TestVisible
  private static Map<Id, NotificationChangeModels.ChangeContext> excludePublishedUpdateFingerprints(
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    Map<Id, NotificationChangeModels.ChangeContext> filteredContextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();

    if (contextByRecordId == null || contextByRecordId.isEmpty()) {
      return filteredContextByRecordId;
    }

    for (Id recordId : contextByRecordId.keySet()) {
      String fingerprint = buildUpdateFingerprint(
        recordId,
        contextByRecordId.get(recordId)
      );
      if (String.isBlank(fingerprint) || publishedUpdateFingerprints.contains(fingerprint)) {
        continue;
      }

      filteredContextByRecordId.put(recordId, contextByRecordId.get(recordId));
    }

    return filteredContextByRecordId;
  }

  private static void addPublishedUpdateFingerprints(
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    if (contextByRecordId == null || contextByRecordId.isEmpty()) {
      return;
    }

    for (Id recordId : contextByRecordId.keySet()) {
      String fingerprint = buildUpdateFingerprint(
        recordId,
        contextByRecordId.get(recordId)
      );
      if (!String.isBlank(fingerprint)) {
        publishedUpdateFingerprints.add(fingerprint);
      }
    }
  }

  private static String buildUpdateFingerprint(
    Id recordId,
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (recordId == null) {
      return null;
    }

    String changeFingerprint = NotificationChangeModels.buildChangeFingerprint(
      changeContext
    );
    if (String.isBlank(changeFingerprint)) {
      return null;
    }

    return String.valueOf(recordId) + '|' + changeFingerprint;
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