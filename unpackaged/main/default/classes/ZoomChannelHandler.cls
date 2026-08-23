/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public without sharing class ZoomChannelHandler implements INotificationChannelHandler {
  public NotificationDigestModels.DeliveryResult deliver(
    NotificationDeliveryModels.DeliveryContext context
  ) {
    String targetUserId = resolveTargetUserId(context.channelSettings);

    if (String.isBlank(targetUserId)) {
      throw new ZoomChannelHandlerException(
        'No Zoom username or email is configured for this user.'
      );
    }

    ZoomNotificationService.sendNotification(
      targetUserId,
      context.message.body
    );

    return NotificationDigestResultFactory.succeeded();
  }

  private static String resolveTargetUserId(
    NotificationUserChannelService.ChannelSettings settings
  ) {
    if (settings == null) {
      return null;
    }

    if (!String.isBlank(settings.zoomUsername)) {
      return settings.zoomUsername.trim();
    }

    return settings.userEmail;
  }

  public class ZoomChannelHandlerException extends Exception {
  }
}