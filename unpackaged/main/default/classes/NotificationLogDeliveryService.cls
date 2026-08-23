/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Shared notification log delivery status updates for immediate and digest flows.
 */
public without sharing class NotificationLogDeliveryService {
  public static Boolean isDeliverableStatus(String status) {
    return status == NotificationConstants.STATUS_QUEUED ||
      status == NotificationConstants.STATUS_PENDING;
  }

  public static Integer markSent(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return 0;
    }

    Datetime deliveredAt = System.now();
    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Status__c = NotificationConstants.STATUS_SENT,
          Delivered_At__c = deliveredAt,
          Error_Message__c = null,
          Suppression_Reason__c = null
        )
      );
    }

    update updates;
    return updates.size();
  }

  public static void markSuppressed(
    List<Notification_Log__c> logs,
    String suppressionReason
  ) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Status__c = NotificationConstants.STATUS_SUPPRESSED,
          Suppression_Reason__c = suppressionReason,
          Error_Message__c = null
        )
      );
    }

    update updates;
  }

  public static void markFailed(List<Notification_Log__c> logs, String errorMessage) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      Decimal attemptCount = logRecord.Delivery_Attempt_Count__c == null
        ? 0
        : logRecord.Delivery_Attempt_Count__c;

      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Status__c = NotificationConstants.STATUS_FAILED,
          Error_Message__c = errorMessage,
          Delivery_Attempt_Count__c = attemptCount + 1
        )
      );
    }

    update updates;
  }

  public static void incrementAttemptCounts(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      Decimal attemptCount = logRecord.Delivery_Attempt_Count__c == null
        ? 0
        : logRecord.Delivery_Attempt_Count__c;

      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Delivery_Attempt_Count__c = attemptCount + 1,
          Error_Message__c = null
        )
      );
    }

    update updates;
  }

  public static Integer requeueForDebugDelivery(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return 0;
    }

    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      if (isDeliverableStatus(logRecord.Status__c)) {
        continue;
      }

      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Status__c = NotificationConstants.STATUS_QUEUED,
          Delivered_At__c = null,
          Error_Message__c = null,
          Suppression_Reason__c = null
        )
      );
    }

    if (updates.isEmpty()) {
      return 0;
    }

    update updates;
    return updates.size();
  }
}