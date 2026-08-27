/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class ZoomNotificationDevServiceTest {
  private static final String NOTIFICATION_ENDPOINT = 'https://api.zoom.us/v2/app/notifications';
  private static final String TOKEN_ENDPOINT = 'https://zoom.us/oauth/token';

  private class ZoomDevNotificationMock implements HttpCalloutMock {
    private final String mode;

    ZoomDevNotificationMock(String mode) {
      this.mode = mode;
    }

    public HttpResponse respond(HttpRequest request) {
      if (
        request.getEndpoint() == TOKEN_ENDPOINT ||
        request.getHeader('Content-Type') == 'application/x-www-form-urlencoded'
      ) {
        return buildTokenResponse();
      }

      System.assertEquals('POST', request.getMethod());
      System.assertEquals(NOTIFICATION_ENDPOINT, request.getEndpoint());
      System.assertEquals('application/json', request.getHeader('Content-Type'));
      System.assertEquals('Bearer test-access-token', request.getHeader('Authorization'));

      HttpResponse response = new HttpResponse();
      response.setStatusCode(this.mode == 'failure' ? 500 : 202);
      response.setBody('{"status":"accepted"}');
      return response;
    }

    private HttpResponse buildTokenResponse() {
      HttpResponse response = new HttpResponse();
      if (this.mode == 'failure') {
        response.setStatusCode(500);
        response.setBody('{"error":"token_exchange_failed"}');
        return response;
      }

      response.setStatusCode(200);
      response.setBody(
        '{"access_token":"new-access-token","refresh_token":"refresh-token","expires_in":3600,"token_type":"bearer"}'
      );
      return response;
    }
  }

  @IsTest
  static void exchangeAuthorizationCode_returnsAccessToken() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('success'));

    Test.startTest();
    ZoomNotificationDevService.TokenResponse tokenResponse = ZoomNotificationDevService.exchangeAuthorizationCode(
      'auth-code-123',
      'client-secret'
    );
    Test.stopTest();

    System.assertEquals('new-access-token', tokenResponse.access_token);
    System.assertEquals('refresh-token', tokenResponse.refresh_token);
  }

  @IsTest
  static void sendAppNotification_usesBearerToken() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('success'));

    Test.startTest();
    HttpResponse response = ZoomNotificationDevService.sendAppNotification(
      'test-access-token',
      'dev@example.com',
      'Dev notification'
    );
    Test.stopTest();

    System.assertEquals(202, response.getStatusCode());
  }

  @IsTest
  static void sendMessagesFromFlow_processesFutureCallout() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('success'));

    ZoomNotificationDevService.FlowInput input = new ZoomNotificationDevService.FlowInput();
    input.targetEmail = 'dev@example.com';
    input.messageText = 'Future notification';
    input.accessToken = 'test-access-token';

    Test.startTest();
    ZoomNotificationDevService.sendMessagesFromFlow(
      new List<ZoomNotificationDevService.FlowInput>{ input }
    );
    Test.stopTest();
  }

  @IsTest
  static void exchangeAuthorizationCode_throwsWhenTokenExchangeFails() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('failure'));
    Boolean didThrow = false;

    try {
      ZoomNotificationDevService.exchangeAuthorizationCode(
        'auth-code-123',
        'client-secret'
      );
    } catch (ZoomNotificationDevService.ZoomNotificationDevException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void refreshAccessToken_returnsAccessToken() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('success'));

    Test.startTest();
    ZoomNotificationDevService.TokenResponse tokenResponse = ZoomNotificationDevService.refreshAccessToken(
      'refresh-token',
      'client-secret'
    );
    Test.stopTest();

    System.assertEquals('new-access-token', tokenResponse.access_token);
  }

  @IsTest
  static void refreshAccessToken_throwsWhenRefreshFails() {
    Test.setMock(HttpCalloutMock.class, new ZoomDevNotificationMock('failure'));
    Boolean didThrow = false;

    try {
      ZoomNotificationDevService.refreshAccessToken('refresh-token', 'client-secret');
    } catch (ZoomNotificationDevService.ZoomNotificationDevException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }
}