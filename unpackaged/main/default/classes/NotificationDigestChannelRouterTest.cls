/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class NotificationDigestChannelRouterTest {
  @IsTest
  static void getHandler_returnsSupportedDigestHandlers() {
    System.assert(
      NotificationDigestChannelRouter.getHandler(
        NotificationConstants.CHANNEL_IN_APP
      ) instanceof InAppDigestChannelHandler
    );
    System.assert(
      NotificationDigestChannelRouter.getHandler(
        NotificationConstants.CHANNEL_EMAIL
      ) instanceof EmailDigestChannelHandler
    );
  }

  @IsTest
  static void getHandler_throwsForUnsupportedChannel() {
    for (String channel : new List<String>{
      'Unsupported',
      NotificationConstants.CHANNEL_ZOOM
    }) {
      Boolean didThrow = false;

      try {
        NotificationDigestChannelRouter.getHandler(channel);
      } catch (
        NotificationDigestChannelRouter.NotificationDigestChannelRouterException expected
      ) {
        didThrow = true;
      }

      System.assertEquals(true, didThrow, 'Expected unsupported channel: ' + channel);
    }
  }
}