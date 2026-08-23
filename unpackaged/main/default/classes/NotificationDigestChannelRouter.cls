/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public with sharing class NotificationDigestChannelRouter {
  public static INotificationDigestChannelHandler getHandler(String channel) {
    if (channel == NotificationConstants.CHANNEL_IN_APP) {
      return new InAppDigestChannelHandler();
    }

    if (channel == NotificationConstants.CHANNEL_EMAIL) {
      return new EmailDigestChannelHandler();
    }

    if (channel == NotificationConstants.CHANNEL_ZOOM) {
      return new ZoomDigestChannelHandler();
    }

    throw new NotificationDigestChannelRouterException(
      'Unsupported digest channel: ' + channel
    );
  }

  public class NotificationDigestChannelRouterException extends Exception {
  }
}