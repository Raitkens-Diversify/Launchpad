/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class NotificationChannelRouterTest {
  @IsTest
  static void getHandler_returnsInAppHandler() {
    INotificationChannelHandler handler = NotificationChannelRouter.getHandler(
      NotificationConstants.CHANNEL_IN_APP
    );

    System.assert(handler instanceof InAppChannelHandler);
  }

  @IsTest
  static void getHandler_returnsEmailHandler() {
    INotificationChannelHandler handler = NotificationChannelRouter.getHandler(
      NotificationConstants.CHANNEL_EMAIL
    );

    System.assert(handler instanceof EmailChannelHandler);
  }

  @IsTest
  static void getHandler_throwsForUnsupportedChannel() {
    Boolean didThrow = false;

    try {
      NotificationChannelRouter.getHandler('Unsupported');
    } catch (NotificationChannelRouter.NotificationChannelRouterException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }
}