/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Sends Zoom App Notifications via Named Credential callout.
 */
public class ZoomNotificationService {
  public class FlowInput {
    @InvocableVariable(
      label='Target User Email'
      description='The dynamic email of the user receiving the App Notification'
      required=true
    )
    public String targetEmail;

    @InvocableVariable(
      label='Message Text'
      description='The notification message to send'
      required=true
    )
    public String messageText;
  }

  @InvocableMethod(
    label='Send Zoom Notification via System User'
    description='Sends dynamic App Notifications to the Activity Center using the Named Principal'
  )
  public static void sendMessagesFromFlow(List<FlowInput> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    for (FlowInput request : requests) {
      sendNotification(request.targetEmail, request.messageText);
    }
  }

  public static void sendNotification(String targetUserId, String messageText) {
    HttpResponse response = executeCallout(targetUserId, messageText);

    if (
      response.getStatusCode() != 202 &&
      response.getStatusCode() != 200 &&
      response.getStatusCode() != 201
    ) {
      throw new ZoomNotificationException(
        'Failed to notify ' +
          targetUserId +
          '. Status: ' +
          response.getStatusCode() +
          ' Body: ' +
          response.getBody()
      );
    }
  }

  private static HttpResponse executeCallout(
    String targetUserId,
    String messageText
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:Zoom_CCC/v2/app/notifications');
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/json');

    Map<String, Object> messageContent = new Map<String, Object>();
    messageContent.put('text', messageText);

    String uniqueNotificationId = EncodingUtil.convertToHex(
      Crypto.generateAesKey(128)
    );

    Map<String, Object> payload = new Map<String, Object>();
    payload.put('user_id', targetUserId);
    payload.put('notification_id', uniqueNotificationId);
    payload.put('message', messageContent);

    request.setBody(JSON.serialize(payload));

    return new Http().send(request);
  }

  public class ZoomNotificationException extends Exception {
  }
}