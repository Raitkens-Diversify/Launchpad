/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-18
 *
 * Groups queued digest logs into delivery requests by recipient, channel, and source type.
 */
public without sharing class NotificationDeliveryGroupingService {
  public static List<NotificationDigestModels.DigestDeliveryRequest> buildDeliveryRequestsForRuleIds(
    Set<Id> ruleIds,
    String cadence
  ) {
    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests = new List<NotificationDigestModels.DigestDeliveryRequest>();
    List<Notification_Log__c> queuedLogs = new NotificationLogRepository().selectQueuedLogsForRules(
      ruleIds
    );

    if (queuedLogs.isEmpty()) {
      return deliveryRequests;
    }

    Map<String, List<Notification_Log__c>> groupedLogs = groupLogsByDeliveryKey(queuedLogs);

    for (List<Notification_Log__c> logGroup : groupedLogs.values()) {
      deliveryRequests.add(buildDeliveryRequest(logGroup, cadence, 0));
    }

    return deliveryRequests;
  }

  public static Map<String, List<Notification_Log__c>> groupLogsByDeliveryKey(
    List<Notification_Log__c> logs
  ) {
    Map<String, List<Notification_Log__c>> groupedLogs = new Map<String, List<Notification_Log__c>>();

    for (Notification_Log__c logRecord : logs) {
      String groupKey = buildGroupKey(
        logRecord.Recipient__c,
        logRecord.Channel__c,
        logRecord.Source_Type__c
      );

      if (!groupedLogs.containsKey(groupKey)) {
        groupedLogs.put(groupKey, new List<Notification_Log__c>());
      }

      groupedLogs.get(groupKey).add(logRecord);
    }

    return groupedLogs;
  }

  public static NotificationDigestModels.DigestDeliveryRequest buildDeliveryRequest(
    List<Notification_Log__c> logs,
    String cadence,
    Integer attemptNumber
  ) {
    return buildDeliveryRequest(logs, cadence, attemptNumber, null);
  }

  public static NotificationDigestModels.DigestDeliveryRequest buildDeliveryRequest(
    List<Notification_Log__c> logs,
    String cadence,
    Integer attemptNumber,
    String preferredChannel
  ) {
    Notification_Log__c firstLog = logs[0];
    NotificationDigestModels.DigestDeliveryRequest request = new NotificationDigestModels.DigestDeliveryRequest();
    request.recipientId = firstLog.Recipient__c;
    request.channel = NotificationChannelUtils.resolveSingleChannel(
      firstLog.Channel__c,
      preferredChannel
    );
    request.sourceType = firstLog.Source_Type__c;
    request.cadence = cadence;
    request.attemptNumber = attemptNumber == null ? 0 : attemptNumber;

    for (Notification_Log__c logRecord : logs) {
      request.logIds.add(logRecord.Id);
    }

    return request;
  }

  public static String buildGroupKey(Id recipientId, String channel, String sourceType) {
    return String.valueOf(recipientId) + '|' + channel + '|' + sourceType;
  }

  public static Map<String, List<Notification_Log__c>> groupImmediateLogsByRecipientSource(
    List<Notification_Log__c> logs
  ) {
    Map<String, List<Notification_Log__c>> groupedLogs = new Map<String, List<Notification_Log__c>>();

    for (Notification_Log__c logRecord : logs) {
      String groupKey = buildImmediateGroupKey(logRecord);

      if (!groupedLogs.containsKey(groupKey)) {
        groupedLogs.put(groupKey, new List<Notification_Log__c>());
      }

      groupedLogs.get(groupKey).add(logRecord);
    }

    return groupedLogs;
  }

  public static String buildImmediateGroupKey(Notification_Log__c logRecord) {
    return String.valueOf(logRecord.Recipient__c) +
      '|' +
      logRecord.Source_Record_Id__c +
      '|' +
      logRecord.Frequency__c;
  }

  public static String buildImmediateGroupKey(NotificationCenterDeliveryItem deliveryItem) {
    return String.valueOf(deliveryItem.recipientId) +
      '|' +
      deliveryItem.sourceRecordId +
      '|' +
      deliveryItem.frequency;
  }
}