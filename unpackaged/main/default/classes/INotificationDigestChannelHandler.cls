/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Channel-specific digest delivery handlers.
 */
public interface INotificationDigestChannelHandler {
  NotificationDigestModels.DeliveryResult deliver(
    NotificationDigestModels.DigestDeliveryContext context
  );
}