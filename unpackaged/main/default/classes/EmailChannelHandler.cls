/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public without sharing class EmailChannelHandler implements INotificationChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDeliveryModels.DeliveryContext context
  ) {
    NotificationDigestModels.ConsolidatedMessage message = context.message;

    NotificationEmailDeliveryService.sendNotification(
      context.request.recipientId,
      message.title,
      message.body
    );

    return NotificationDigestResultFactory.succeeded();
  }
}