/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * System-context enqueue helper for notification delivery jobs.
 */
public without sharing class NotificationDeliveryEnqueueService {
  public static void enqueueLogIds(List<Id> logIds) {
    enqueueNormalizedLogIds(normalizeLogIds(logIds), false);
  }

  public static void enqueueImmediateLogIds(List<Id> logIds) {
    enqueueNormalizedLogIds(normalizeLogIds(logIds), true);
  }

  public static void enqueueLogIdStrings(List<String> logIdStrings) {
    enqueueNormalizedLogIds(parseLogIdStrings(logIdStrings), false);
  }

  public static void enqueueImmediateLogIdStrings(List<String> logIdStrings) {
    enqueueNormalizedLogIds(parseLogIdStrings(logIdStrings), true);
  }

  public static void enqueueImmediateDeliveryItems(
    List<NotificationCenterDeliveryItem> deliveryItems
  ) {
    if (deliveryItems == null || deliveryItems.isEmpty()) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromDeliveryItems(
      deliveryItems
    );
    NotificationDeliveryDispatcher.enqueueRequests(requests);
  }

  private static void enqueueNormalizedLogIds(
    List<Id> logIds,
    Boolean immediateOnly
  ) {
    if (logIds == null || logIds.isEmpty()) {
      return;
    }

    List<Notification_Log__c> logs = new NotificationLogRepository().selectLogsByIds(
      logIds
    );
    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromLogs(
      logs,
      immediateOnly
    );

    NotificationDeliveryDispatcher.enqueueRequests(requests);
  }

  private static List<Id> normalizeLogIds(List<Id> logIds) {
    List<Id> normalizedLogIds = new List<Id>();

    if (logIds == null || logIds.isEmpty()) {
      return normalizedLogIds;
    }

    Set<Id> seenLogIds = new Set<Id>();

    for (Id logId : logIds) {
      if (logId == null || seenLogIds.contains(logId)) {
        continue;
      }

      seenLogIds.add(logId);
      normalizedLogIds.add(logId);
    }

    return normalizedLogIds;
  }

  private static List<Id> parseLogIdStrings(List<String> logIdStrings) {
    List<Id> logIds = new List<Id>();

    if (logIdStrings == null || logIdStrings.isEmpty()) {
      return logIds;
    }

    Set<Id> seenLogIds = new Set<Id>();

    for (String logIdValue : logIdStrings) {
      String trimmedValue = logIdValue == null ? null : logIdValue.trim();

      if (String.isBlank(trimmedValue)) {
        continue;
      }

      Id logId = (Id) trimmedValue;

      if (seenLogIds.contains(logId)) {
        continue;
      }

      seenLogIds.add(logId);
      logIds.add(logId);
    }

    return logIds;
  }
}