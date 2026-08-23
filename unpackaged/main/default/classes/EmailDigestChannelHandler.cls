/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public with sharing class EmailDigestChannelHandler implements INotificationDigestChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDigestModels.DigestDeliveryContext context
  ) {
    NotificationDigestModels.ConsolidatedMessage message = context.message;

    NotificationEmailDeliveryService.sendNotification(
      context.channelSettings,
      message.title,
      message.body
    );

    return NotificationDigestResultFactory.succeeded();
  }
}