/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public without sharing class InAppChannelHandler implements INotificationChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDeliveryModels.DeliveryContext context
  ) {
    if (
      context.request.frequency != NotificationConstants.FREQUENCY_IMMEDIATE &&
      context.request.deliverIndividually != true
    ) {
      return NotificationDigestResultFactory.suppressed(
        NotificationConstants.SUPPRESSION_USER_DIGEST_DISABLED
      );
    }

    deliverImmediate(context);
    return NotificationDigestResultFactory.succeeded();
  }

  private static void deliverImmediate(
    NotificationDeliveryModels.DeliveryContext context
  ) {
    Notification_Log__c logRecord = context.logs[0];
    String title = resolveTitle(logRecord, context.message);
    String body = resolveBody(logRecord, context.message);
    Id targetId = NotificationDigestContentService.resolveTargetId(logRecord);

    NotificationCustomNotificationService.sendNotification(
      context.request.recipientId,
      title,
      body,
      targetId
    );
  }

  private static String resolveTitle(
    Notification_Log__c logRecord,
    NotificationDigestModels.ConsolidatedMessage message
  ) {
    if (!String.isBlank(logRecord.Title__c)) {
      return logRecord.Title__c;
    }

    return message == null ? 'Notification' : message.title;
  }

  private static String resolveBody(
    Notification_Log__c logRecord,
    NotificationDigestModels.ConsolidatedMessage message
  ) {
    if (!String.isBlank(logRecord.Body__c)) {
      return logRecord.Body__c;
    }

    return message == null ? 'Open the notification to view details.' : message.body;
  }
}