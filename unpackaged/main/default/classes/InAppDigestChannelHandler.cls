/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public with sharing class InAppDigestChannelHandler implements INotificationDigestChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDigestModels.DigestDeliveryContext context
  ) {
    NotificationCustomNotificationService.sendPreferenceNotifications(
      context.request.recipientId,
      context.logs
    );

    return NotificationDigestResultFactory.succeeded();
  }
}