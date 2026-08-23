/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Channel-specific notification delivery handlers for immediate and digest modes.
 */
public interface INotificationChannelHandler {
  NotificationDigestModels.DeliveryResult deliver(
    NotificationDeliveryModels.DeliveryContext context
  );
}