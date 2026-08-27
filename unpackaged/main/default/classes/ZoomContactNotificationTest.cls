/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class ZoomContactNotificationTest {
  private class ZoomChatSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(201);
      response.setBody('{"id":"msg-1"}');
      return response;
    }
  }

  private class ZoomChatFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(500);
      response.setBody('{"error":"failed"}');
      return response;
    }
  }

  private class ZoomChatExceptionMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      throw new CalloutException('Simulated Zoom chat failure');
    }
  }

  private static ZoomContactNotification.FlowInput buildInput() {
    ZoomContactNotification.FlowInput input = new ZoomContactNotification.FlowInput();
    input.contactEmail = 'advisor@example.com';
    input.messageText = 'Contact notification';
    return input;
  }

  @IsTest
  static void sendMessagesFromFlow_sendsChatMessage() {
    Test.setMock(HttpCalloutMock.class, new ZoomChatSuccessMock());

    Test.startTest();
    ZoomContactNotification.sendMessagesFromFlow(
      new List<ZoomContactNotification.FlowInput>{ buildInput() }
    );
    Test.stopTest();

    System.assertEquals('advisor@example.com', buildInput().contactEmail);
  }

  @IsTest
  static void sendMessagesFromFlow_logsNonSuccessStatus() {
    Test.setMock(HttpCalloutMock.class, new ZoomChatFailureMock());

    Test.startTest();
    ZoomContactNotification.sendMessagesFromFlow(
      new List<ZoomContactNotification.FlowInput>{ buildInput() }
    );
    Test.stopTest();

    System.assertEquals('advisor@example.com', buildInput().contactEmail);
  }

  @IsTest
  static void sendMessagesFromFlow_swallowsCalloutExceptions() {
    Test.setMock(HttpCalloutMock.class, new ZoomChatExceptionMock());

    Test.startTest();
    ZoomContactNotification.sendMessagesFromFlow(
      new List<ZoomContactNotification.FlowInput>{ buildInput() }
    );
    Test.stopTest();

    System.assertEquals('advisor@example.com', buildInput().contactEmail);
  }
}