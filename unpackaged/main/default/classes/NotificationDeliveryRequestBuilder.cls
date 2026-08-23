/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Builds unified delivery requests from log ids and legacy digest requests.
 */
public without sharing class NotificationDeliveryRequestBuilder {
  public static NotificationDeliveryModels.DeliveryRequest fromLogId(Id logId) {
    NotificationDeliveryModels.DeliveryRequest request = new NotificationDeliveryModels.DeliveryRequest();
    request.logIds = new List<Id>{ logId };
    return request;
  }

  public static NotificationDeliveryModels.DeliveryRequest fromDigest(
    NotificationDigestModels.DigestDeliveryRequest digestRequest
  ) {
    NotificationDeliveryModels.DeliveryRequest request = new NotificationDeliveryModels.DeliveryRequest();
    request.logIds = digestRequest.logIds == null
      ? new List<Id>()
      : new List<Id>(digestRequest.logIds);
    request.recipientId = digestRequest.recipientId;
    request.channel = digestRequest.channel;
    request.sourceType = digestRequest.sourceType;
    request.frequency = NotificationConstants.FREQUENCY_DIGEST;
    request.cadence = digestRequest.cadence;
    request.attemptNumber = digestRequest.attemptNumber;
    return request;
  }

  public static List<NotificationDeliveryModels.DeliveryRequest> fromLogIds(
    List<Id> logIds
  ) {
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    if (logIds == null || logIds.isEmpty()) {
      return requests;
    }

    List<Notification_Log__c> logs = new NotificationLogRepository().selectLogsByIds(
      logIds
    );

    return fromLogs(logs);
  }

  public static List<NotificationDeliveryModels.DeliveryRequest> fromLogIdStrings(
    List<String> logIdStrings
  ) {
    List<Id> logIds = new List<Id>();

    if (logIdStrings == null || logIdStrings.isEmpty()) {
      return new List<NotificationDeliveryModels.DeliveryRequest>();
    }

    for (String logIdValue : logIdStrings) {
      String trimmedValue = logIdValue == null ? null : logIdValue.trim();

      if (String.isBlank(trimmedValue)) {
        continue;
      }

      logIds.add((Id) trimmedValue);
    }

    return fromLogIds(logIds);
  }

  public static List<NotificationDeliveryModels.DeliveryRequest> fromLogs(
    List<Notification_Log__c> logs
  ) {
    return fromLogs(logs, false);
  }

  public static List<NotificationDeliveryModels.DeliveryRequest> fromLogs(
    List<Notification_Log__c> logs,
    Boolean immediateOnly
  ) {
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    if (logs == null || logs.isEmpty()) {
      return requests;
    }

    List<Notification_Log__c> immediateLogs = new List<Notification_Log__c>();
    List<Notification_Log__c> digestLogs = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      if (logRecord.Status__c != NotificationConstants.STATUS_PENDING &&
        logRecord.Status__c != NotificationConstants.STATUS_QUEUED) {
        continue;
      }

      if (logRecord.Frequency__c == NotificationConstants.FREQUENCY_DIGEST) {
        digestLogs.add(logRecord);
        continue;
      }

      if (logRecord.Frequency__c == NotificationConstants.FREQUENCY_IMMEDIATE) {
        immediateLogs.add(logRecord);
      }
    }

    for (List<Notification_Log__c> logGroup : NotificationDeliveryGroupingService.groupImmediateLogsByRecipientSource(
      immediateLogs
    ).values()) {
      requests.add(buildImmediateDeliveryRequest(logGroup));
    }

    Map<String, List<Notification_Log__c>> groupedDigestLogs = NotificationDeliveryGroupingService.groupLogsByDeliveryKey(
      digestLogs
    );

    for (List<Notification_Log__c> logGroup : groupedDigestLogs.values()) {
      if (immediateOnly == true) {
        continue;
      }

      NotificationDigestModels.DigestDeliveryRequest digestRequest = NotificationDeliveryGroupingService.buildDeliveryRequest(
        logGroup,
        null,
        0
      );
      requests.add(fromDigest(digestRequest));
    }

    return requests;
  }

  public static List<NotificationDeliveryModels.DeliveryRequest> fromDeliveryItems(
    List<NotificationCenterDeliveryItem> deliveryItems
  ) {
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    if (deliveryItems == null || deliveryItems.isEmpty()) {
      return requests;
    }

    Map<String, List<NotificationCenterDeliveryItem>> groupedItems = new Map<String, List<NotificationCenterDeliveryItem>>();

    for (NotificationCenterDeliveryItem deliveryItem : deliveryItems) {
      if (deliveryItem == null || deliveryItem.logId == null) {
        continue;
      }

      if (
        deliveryItem.frequency != null &&
        deliveryItem.frequency != NotificationConstants.FREQUENCY_IMMEDIATE
      ) {
        continue;
      }

      String groupKey = NotificationDeliveryGroupingService.buildImmediateGroupKey(
        deliveryItem
      );

      if (!groupedItems.containsKey(groupKey)) {
        groupedItems.put(groupKey, new List<NotificationCenterDeliveryItem>());
      }

      groupedItems.get(groupKey).add(deliveryItem);
    }

    for (List<NotificationCenterDeliveryItem> itemGroup : groupedItems.values()) {
      requests.add(buildImmediateDeliveryRequestFromItems(itemGroup));
    }

    return requests;
  }

  private static NotificationDeliveryModels.DeliveryRequest buildImmediateDeliveryRequest(
    List<Notification_Log__c> logs
  ) {
    Notification_Log__c firstLog = logs[0];
    NotificationDeliveryModels.DeliveryRequest request = new NotificationDeliveryModels.DeliveryRequest();
    request.recipientId = firstLog.Recipient__c;
    request.sourceType = firstLog.Source_Type__c;
    request.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;

    for (Notification_Log__c logRecord : logs) {
      request.logIds.add(logRecord.Id);
    }

    if (logs.size() == 1) {
      request.channel = NotificationChannelUtils.resolveSingleChannel(
        firstLog.Channel__c,
        null
      );
    }

    return request;
  }

  private static NotificationDeliveryModels.DeliveryRequest buildImmediateDeliveryRequestFromItems(
    List<NotificationCenterDeliveryItem> deliveryItems
  ) {
    NotificationCenterDeliveryItem firstItem = deliveryItems[0];
    NotificationDeliveryModels.DeliveryRequest request = new NotificationDeliveryModels.DeliveryRequest();
    request.recipientId = firstItem.recipientId;
    request.sourceType = firstItem.sourceType;
    request.frequency = String.isBlank(firstItem.frequency)
      ? NotificationConstants.FREQUENCY_IMMEDIATE
      : firstItem.frequency;

    for (NotificationCenterDeliveryItem deliveryItem : deliveryItems) {
      request.logIds.add(deliveryItem.logId);
    }

    if (deliveryItems.size() == 1) {
      request.channel = deliveryItemChannel(firstItem);
    }

    return request;
  }

  private static String deliveryItemChannel(NotificationCenterDeliveryItem deliveryItem) {
    return NotificationChannelUtils.resolveSingleChannel(
      deliveryItem.channel,
      null
    );
  }
}