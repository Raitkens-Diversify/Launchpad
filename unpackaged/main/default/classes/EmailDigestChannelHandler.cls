/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 */
public with sharing class EmailDigestChannelHandler implements INotificationDigestChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDigestModels.DigestDeliveryContext context
  ) {
    NotificationDigestModels.ConsolidatedMessage message = context.message;

    NotificationEmailDeliveryService.sendNotification(
      context.request.recipientId,
      message.title,
      message.body,
      context.logs
    );

    return NotificationDigestResultFactory.succeeded();
  }
}