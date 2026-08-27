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
    System.assert(
      NotificationDigestChannelRouter.getHandler(
        NotificationConstants.CHANNEL_ZOOM
      ) instanceof ZoomDigestChannelHandler
    );
  }

  @IsTest
  static void getHandler_throwsForUnsupportedChannel() {
    Boolean didThrow = false;

    try {
      NotificationDigestChannelRouter.getHandler('Unsupported');
    } catch (
      NotificationDigestChannelRouter.NotificationDigestChannelRouterException expected
    ) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }
}