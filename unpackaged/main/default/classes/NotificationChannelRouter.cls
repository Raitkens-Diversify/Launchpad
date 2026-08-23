/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Routes notification delivery to channel-specific handlers.
 */
public without sharing class NotificationChannelRouter {
  public static INotificationChannelHandler getHandler(String channel) {
    if (channel == NotificationConstants.CHANNEL_IN_APP) {
      return new InAppChannelHandler();
    }

    if (channel == NotificationConstants.CHANNEL_EMAIL) {
      return new EmailChannelHandler();
    }

    throw new NotificationChannelRouterException(
      'Unsupported notification channel: ' + channel
    );
  }

  public class NotificationChannelRouterException extends Exception {
  }
}