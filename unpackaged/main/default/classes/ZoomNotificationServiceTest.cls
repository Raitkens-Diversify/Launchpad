/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class ZoomNotificationServiceTest {
  private static final String ENDPOINT = 'callout:Zoom_CCC/v2/app/notifications';

  @TestVisible
  private class ZoomNotificationSuccessMock implements HttpCalloutMock {
    private final Integer statusCode;

    ZoomNotificationSuccessMock(Integer statusCode) {
      this.statusCode = statusCode;
    }

    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assertEquals(ENDPOINT, request.getEndpoint());
      System.assertEquals('application/json', request.getHeader('Content-Type'));

      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        request.getBody()
      );
      System.assert(payload.containsKey('user_id'), 'Payload should include user_id');
      System.assert(payload.containsKey('notification_id'), 'Payload should include notification_id');
      System.assert(payload.containsKey('message'), 'Payload should include message');

      Map<String, Object> message = (Map<String, Object>) payload.get('message');
      System.assertNotEquals(null, message.get('text'), 'Message text should be set');

      HttpResponse response = new HttpResponse();
      response.setStatusCode(this.statusCode);
      response.setBody('{"status":"accepted"}');
      return response;
    }
  }

  private class ZoomNotificationFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(500);
      response.setBody('{"error":"internal_server_error"}');
      return response;
    }
  }

  private class ZoomNotificationExceptionMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      throw new CalloutException('Simulated callout failure');
    }
  }

  private static ZoomNotificationService.FlowInput buildFlowInput(
    String targetEmail,
    String messageText
  ) {
    ZoomNotificationService.FlowInput input = new ZoomNotificationService.FlowInput();
    input.targetEmail = targetEmail;
    input.messageText = messageText;
    return input;
  }

  @IsTest
  static void sendMessagesFromFlow_sendsNotificationWithAcceptedStatus() {
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationSuccessMock(202));

    ZoomNotificationService.FlowInput input = buildFlowInput(
      'advisor@example.com',
      'Your meeting starts in 15 minutes.'
    );

    Test.startTest();
    ZoomNotificationService.sendMessagesFromFlow(
      new List<ZoomNotificationService.FlowInput>{ input }
    );
    Test.stopTest();
  }

  @IsTest
  static void sendMessagesFromFlow_handlesCreatedAndOkStatusCodes() {
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationSuccessMock(201));

    ZoomNotificationService.FlowInput createdInput = buildFlowInput(
      'user1@example.com',
      'Created notification'
    );
    ZoomNotificationService.FlowInput okInput = buildFlowInput(
      'user2@example.com',
      'OK notification'
    );

    Test.startTest();
    ZoomNotificationService.sendMessagesFromFlow(
      new List<ZoomNotificationService.FlowInput>{ createdInput }
    );
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationSuccessMock(200));
    ZoomNotificationService.sendMessagesFromFlow(
      new List<ZoomNotificationService.FlowInput>{ okInput }
    );
    Test.stopTest();
  }

  @IsTest
  static void sendMessagesFromFlow_processesMultipleRequests() {
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationSuccessMock(202));

    List<ZoomNotificationService.FlowInput> requests = new List<ZoomNotificationService.FlowInput>{
      buildFlowInput('first@example.com', 'First message'),
      buildFlowInput('second@example.com', 'Second message')
    };

    Test.startTest();
    ZoomNotificationService.sendMessagesFromFlow(requests);
    Test.stopTest();
  }

  @IsTest
  static void sendMessagesFromFlow_throwsForNonSuccessResponse() {
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationFailureMock());

    ZoomNotificationService.FlowInput input = buildFlowInput(
      'failure@example.com',
      'This request should fail.'
    );

    Boolean threw = false;

    Test.startTest();
    try {
      ZoomNotificationService.sendMessagesFromFlow(
        new List<ZoomNotificationService.FlowInput>{ input }
      );
    } catch (ZoomNotificationService.ZoomNotificationException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void sendMessagesFromFlow_throwsForCalloutException() {
    Test.setMock(HttpCalloutMock.class, new ZoomNotificationExceptionMock());

    ZoomNotificationService.FlowInput input = buildFlowInput(
      'exception@example.com',
      'This request should catch callout exceptions.'
    );

    Boolean threw = false;

    Test.startTest();
    try {
      ZoomNotificationService.sendMessagesFromFlow(
        new List<ZoomNotificationService.FlowInput>{ input }
      );
    } catch (CalloutException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }
}