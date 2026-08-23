/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Dev-only Zoom App Notification sender that uses a manual OAuth access token
 * instead of the Zoom Named Credential. Use for cosmosdev testing while OAuth
 * is being wired up outside Salesforce.
 */
public class ZoomNotificationDevService {
  private static final String TOKEN_ENDPOINT = 'https://zoom.us/oauth/token';
  private static final String NOTIFICATION_ENDPOINT = 'https://api.zoom.us/v2/app/notifications';
  private static final String DEV_CLIENT_ID = 'D2tpRX5zTKCriMPTHYVyg';
  private static final String DEV_REDIRECT_URI =
    'https://dfpginvestments--cosmosdev.sandbox.my.salesforce.com/services/authcallback/Zoom';

  public class FlowInput {
    @InvocableVariable(
      label='Target User Email'
      description='The Zoom user email receiving the App Notification'
      required=true
    )
    public String targetEmail;

    @InvocableVariable(
      label='Message Text'
      description='The notification message to send'
      required=true
    )
    public String messageText;

    @InvocableVariable(
      label='Zoom Access Token'
      description='Bearer token from the Zoom OAuth token exchange'
      required=true
    )
    public String accessToken;
  }

  public class TokenResponse {
    public String access_token;
    public String refresh_token;
    public Integer expires_in;
    public String token_type;
  }

  /**
   * Exchanges the one-time authorization code from the Zoom authorize redirect
   * for an access token. Run this synchronously from Anonymous Apex or a script.
   */
  public static TokenResponse exchangeAuthorizationCode(
    String authorizationCode,
    String clientSecret
  ) {
    return exchangeAuthorizationCode(
      authorizationCode,
      DEV_REDIRECT_URI,
      DEV_CLIENT_ID,
      clientSecret
    );
  }

  public static TokenResponse exchangeAuthorizationCode(
    String authorizationCode,
    String redirectUri,
    String clientId,
    String clientSecret
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:Zoom_CCC/v2/app/notifications');
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.setHeader(
      'Authorization',
      'Basic ' +
      EncodingUtil.base64Encode(Blob.valueOf(clientId + ':' + clientSecret))
    );

    String body =
      'grant_type=authorization_code' +
      '&code=' +
      EncodingUtil.urlEncode(authorizationCode, 'UTF-8') +
      '&redirect_uri=' +
      EncodingUtil.urlEncode(redirectUri, 'UTF-8');
    request.setBody(body);

    HttpResponse response = new Http().send(request);

    if (response.getStatusCode() != 200) {
      throw new ZoomNotificationDevException(
        'Token exchange failed. Status: ' +
        response.getStatusCode() +
        ' Body: ' +
        response.getBody()
      );
    }

    return (TokenResponse) JSON.deserialize(response.getBody(), TokenResponse.class);
  }

  public static TokenResponse refreshAccessToken(String refreshToken, String clientSecret) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(TOKEN_ENDPOINT);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    request.setHeader(
      'Authorization',
      'Basic ' +
      EncodingUtil.base64Encode(Blob.valueOf(DEV_CLIENT_ID + ':' + clientSecret))
    );
    request.setBody(
      'grant_type=refresh_token&refresh_token=' +
      EncodingUtil.urlEncode(refreshToken, 'UTF-8')
    );

    HttpResponse response = new Http().send(request);

    if (response.getStatusCode() != 200) {
      throw new ZoomNotificationDevException(
        'Token refresh failed. Status: ' +
        response.getStatusCode() +
        ' Body: ' +
        response.getBody()
      );
    }

    return (TokenResponse) JSON.deserialize(response.getBody(), TokenResponse.class);
  }

  @InvocableMethod(
    label='Send Zoom Notification (Dev Access Token)'
    description='Sends Zoom App Notifications using a manual bearer token for dev testing'
  )
  public static void sendMessagesFromFlow(List<FlowInput> requests) {
    sendAsync(JSON.serialize(requests));
  }

  @future(callout=true)
  private static void sendAsync(String jsonRequests) {
    List<FlowInput> requests = (List<FlowInput>) JSON.deserialize(
      jsonRequests,
      List<FlowInput>.class
    );

    for (FlowInput requestInput : requests) {
      sendAppNotification(requestInput.accessToken, requestInput.targetEmail, requestInput.messageText);
    }
  }

  public static HttpResponse sendAppNotification(
    String accessToken,
    String targetEmail,
    String messageText
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(NOTIFICATION_ENDPOINT);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/json');
    request.setHeader('Authorization', 'Bearer ' + accessToken);
    request.setBody(JSON.serialize(buildPayload(targetEmail, messageText)));

    HttpResponse response = new Http().send(request);
    logResponse(targetEmail, response);
    return response;
  }

  private static Map<String, Object> buildPayload(String targetEmail, String messageText) {
    Map<String, Object> messageContent = new Map<String, Object>();
    messageContent.put('text', messageText);

    Map<String, Object> payload = new Map<String, Object>();
    payload.put('user_id', targetEmail);
    payload.put(
      'notification_id',
      EncodingUtil.convertToHex(Crypto.generateAesKey(128))
    );
    payload.put('message', messageContent);
    return payload;
  }

  private static void logResponse(String targetEmail, HttpResponse response) {
    Integer statusCode = response.getStatusCode();

    if (statusCode == 200 || statusCode == 201 || statusCode == 202) {
      System.debug('Successfully sent App Notification to ' + targetEmail);
      return;
    }

    System.debug(
      'Failed to notify ' +
      targetEmail +
      '. Status: ' +
      statusCode +
      ' Body: ' +
      response.getBody()
    );
  }

  public class ZoomNotificationDevException extends Exception {
  }
}