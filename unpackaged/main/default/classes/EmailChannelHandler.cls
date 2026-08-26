/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 */
public without sharing class EmailChannelHandler implements INotificationChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDeliveryModels.DeliveryContext context
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