/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public with sharing class ZoomDigestChannelHandler implements INotificationDigestChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDigestModels.DigestDeliveryContext context
  ) {
    NotificationDeliveryModels.DeliveryContext unifiedContext = new NotificationDeliveryModels.DeliveryContext();
    unifiedContext.request = NotificationDeliveryRequestBuilder.fromDigest(
      context.request
    );
    unifiedContext.logs = context.logs;
    unifiedContext.message = context.message;
    unifiedContext.channelSettings = context.channelSettings;

    return new ZoomChannelHandler().deliver(unifiedContext);
  }
}