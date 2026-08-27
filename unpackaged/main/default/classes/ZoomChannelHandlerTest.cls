/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class ZoomChannelHandlerTest {
  private class ZoomSuccessMock implements HttpCalloutMock {
    private final Integer statusCode;

    ZoomSuccessMock(Integer statusCode) {
      this.statusCode = statusCode;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(this.statusCode);
      response.setBody('{"status":"accepted"}');
      return response;
    }
  }

  @IsTest
  static void deliver_throwsWhenNoZoomTargetIsConfigured() {
    NotificationDeliveryModels.DeliveryContext context = new NotificationDeliveryModels.DeliveryContext();
    context.message = new NotificationDigestModels.ConsolidatedMessage();
    context.message.body = 'Zoom body';
    Boolean didThrow = false;

    try {
      new ZoomChannelHandler().deliver(context);
    } catch (ZoomChannelHandler.ZoomChannelHandlerException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void deliver_sendsUsingZoomUsername() {
    Test.setMock(HttpCalloutMock.class, new ZoomSuccessMock(202));

    NotificationUserChannelService.ChannelSettings settings =
      new NotificationUserChannelService.ChannelSettings();
    settings.zoomUsername = ' advisor@example.com ';
    settings.userEmail = 'fallback@example.com';

    NotificationDeliveryModels.DeliveryContext context = new NotificationDeliveryModels.DeliveryContext();
    context.channelSettings = settings;
    context.message = new NotificationDigestModels.ConsolidatedMessage();
    context.message.body = 'Immediate Zoom body';

    Test.startTest();
    NotificationDigestModels.DeliveryResult result = new ZoomChannelHandler()
      .deliver(context);
    Test.stopTest();

    System.assertEquals(true, result.success);
  }

  @IsTest
  static void digestHandler_sendsUsingUserEmailFallback() {
    Test.setMock(HttpCalloutMock.class, new ZoomSuccessMock(200));

    NotificationUserChannelService.ChannelSettings settings =
      new NotificationUserChannelService.ChannelSettings();
    settings.userEmail = 'digest@example.com';

    NotificationDigestModels.DigestDeliveryContext digestContext =
      new NotificationDigestModels.DigestDeliveryContext();
    digestContext.channelSettings = settings;
    digestContext.message = new NotificationDigestModels.ConsolidatedMessage();
    digestContext.message.body = 'Digest Zoom body';
    digestContext.request.recipientId = UserInfo.getUserId();
    digestContext.request.channel = NotificationConstants.CHANNEL_ZOOM;

    Test.startTest();
    NotificationDigestModels.DeliveryResult result = new ZoomDigestChannelHandler()
      .deliver(digestContext);
    Test.stopTest();

    System.assertEquals(true, result.success);
  }
}