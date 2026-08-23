/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Egnyte OAuth 2.0 Authorization Code flow for admin login.
 * Tokens are displayed after login for storage in Egnyte Settings custom metadata.
 */
public without sharing class EgnyteOAuthController {
  private static final String AUTHORIZE_PATH = '/puboauth/token';
  private static final String TOKEN_PATH = '/puboauth/token';
  private static final String CALLBACK_PAGE = 'EgnyteOAuthCallback';
  private static final String STATE_CACHE_KEY = 'egnyte_oauth_state';
  private static final Integer STATE_TTL_SECONDS = 600;
  private static final String HARDCODED_DOMAIN = 'launchpad.egnyte.com';
  private static final String HARDCODED_CLIENT_ID = 'aDVGkFbtQkPDUkZkLN8Q2IYgLNZgD5DlCEtsozDXwV5BN3mg';
  private static final String HARDCODED_CLIENT_SECRET = '3uZq6xF56XphkZbA6fX5Kp4mIAz64JQAewkhuZcT1NrepCkwGzPcNk7tExsyfkI5';
  private static final String OAUTH_SCOPES = 'Egnyte.salesforce Egnyte.launchwebsession';

  @TestVisible
  private static String testAuthorizationUrlOverride;

  @TestVisible
  private static TokenResponse testTokenResponseOverride;

  @TestVisible
  private static String testSessionStateOverride;

  public String redirectUri {
    get {
      return buildRedirectUri();
    }
  }

  public String connectUrl {
    get {
      return buildConnectPageUrl();
    }
  }

  public String issuedAccessToken { get; private set; }
  public String issuedRefreshToken { get; private set; }
  public Boolean tokensIssued { get; private set; }

  public class EgnyteOAuthException extends Exception {
  }

  public class TokenResponse {
    public String access_token;
    public String refresh_token;
    public Integer expires_in;
    public String token_type;
  }

  public class OAuthStatus {
    @AuraEnabled
    public Boolean isConnected;

    @AuraEnabled
    public String redirectUri;

    @AuraEnabled
    public String connectUrl;
  }

  @AuraEnabled
  public static OAuthStatus getOAuthStatus() {
    OAuthStatus status = new OAuthStatus();
    status.redirectUri = buildRedirectUri();
    status.connectUrl = buildConnectPageUrl();
    status.isConnected = String.isNotBlank(loadConfiguredRefreshToken());
    return status;
  }

  @AuraEnabled
  public static String getAuthorizationUrl() {
    return buildAuthorizationUrl(generateState(), buildRedirectUri());
  }

  public PageReference beginAuthorization() {
    String state = generateState();
    persistOAuthState(state);
    PageReference authorizePage = new PageReference(
      buildAuthorizationUrl(state, buildRedirectUri())
    );
    authorizePage.setRedirect(true);
    return authorizePage;
  }

  public PageReference handleCallback() {
    tokensIssued = false;
    issuedAccessToken = null;
    issuedRefreshToken = null;

    String error = ApexPages.currentPage().getParameters().get('error');
    if (String.isNotBlank(error)) {
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.ERROR,
          'Egnyte authorization was denied: ' + error
        )
      );
      return null;
    }

    String code = ApexPages.currentPage().getParameters().get('code');
    String state = ApexPages.currentPage().getParameters().get('state');

    if (String.isBlank(code)) {
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.ERROR,
          'Egnyte did not return an authorization code.'
        )
      );
      return null;
    }

    try {
      validateOAuthState(state);
      TokenResponse tokenResponse = exchangeAuthorizationCode(
        code,
        buildRedirectUri()
      );
      clearOAuthState();
      issuedAccessToken = tokenResponse.access_token;
      issuedRefreshToken = tokenResponse.refresh_token;
      tokensIssued = true;
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.CONFIRM,
          'Egnyte authorized successfully. Copy the refresh token below into Egnyte Settings custom metadata.'
        )
      );
    } catch (Exception e) {
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage())
      );
    }

    return null;
  }

  @TestVisible
  private static String buildConnectPageUrl() {
    return URL.getOrgDomainUrl().toExternalForm() + '/apex/EgnyteOAuthConnect';
  }

  @TestVisible
  private static String buildRedirectUri() {
    return URL.getOrgDomainUrl().toExternalForm() + '/apex/' + CALLBACK_PAGE;
  }

  @TestVisible
  private static String buildAuthorizationUrl(String state, String redirectUri) {
    if (Test.isRunningTest() && String.isNotBlank(testAuthorizationUrlOverride)) {
      return testAuthorizationUrlOverride;
    }

    String baseUrl = EgnyteController.buildBaseUrl(HARDCODED_DOMAIN);
    List<String> queryParts = new List<String>{
      'client_id=' + EncodingUtil.urlEncode(HARDCODED_CLIENT_ID, 'UTF-8'),
      'redirect_uri=' + EncodingUtil.urlEncode(redirectUri, 'UTF-8'),
      'response_type=code',
      'scope=' + EncodingUtil.urlEncode(OAUTH_SCOPES, 'UTF-8'),
      'state=' + EncodingUtil.urlEncode(state, 'UTF-8')
    };

    return baseUrl + AUTHORIZE_PATH + '?' + String.join(queryParts, '&');
  }

  @TestVisible
  private static String generateState() {
    Blob randomBytes = Crypto.generateAesKey(128);
    return EncodingUtil.convertToHex(randomBytes);
  }

  @TestVisible
  private static void persistOAuthState(String state) {
    if (Test.isRunningTest()) {
      testSessionStateOverride = state;
      return;
    }

    Cache.Session.put(STATE_CACHE_KEY, state, STATE_TTL_SECONDS);
  }

  @TestVisible
  private static void clearOAuthState() {
    if (Test.isRunningTest()) {
      testSessionStateOverride = null;
      return;
    }

    Cache.Session.remove(STATE_CACHE_KEY);
  }

  @TestVisible
  private static void validateOAuthState(String state) {
    String expectedState = Test.isRunningTest()
      ? testSessionStateOverride
      : (String) Cache.Session.get(STATE_CACHE_KEY);

    if (String.isBlank(expectedState)) {
      throw new EgnyteOAuthException(
        'Egnyte OAuth state is missing. Start the connection flow again from the Connect page.'
      );
    }

    if (state != expectedState) {
      throw new EgnyteOAuthException(
        'Egnyte OAuth state did not match. Start the connection flow again from the Connect page.'
      );
    }
  }

  @TestVisible
  private static TokenResponse exchangeAuthorizationCode(
    String authorizationCode,
    String redirectUri
  ) {
    if (Test.isRunningTest() && testTokenResponseOverride != null) {
      return testTokenResponseOverride;
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(EgnyteController.buildBaseUrl(HARDCODED_DOMAIN) + TOKEN_PATH);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

    List<String> bodyParts = new List<String>{
      'grant_type=' + EncodingUtil.urlEncode('authorization_code', 'UTF-8'),
      'client_id=' + EncodingUtil.urlEncode(HARDCODED_CLIENT_ID, 'UTF-8'),
      'client_secret=' + EncodingUtil.urlEncode(HARDCODED_CLIENT_SECRET, 'UTF-8'),
      'redirect_uri=' + EncodingUtil.urlEncode(redirectUri, 'UTF-8'),
      'code=' + EncodingUtil.urlEncode(authorizationCode, 'UTF-8'),
      'scope=' + EncodingUtil.urlEncode(OAUTH_SCOPES, 'UTF-8')
    };
    request.setBody(String.join(bodyParts, '&'));

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200) {
      throw new EgnyteOAuthException(
        'Egnyte authorization code exchange failed. Status: ' +
          response.getStatusCode() +
          ' Body: ' +
          response.getBody()
      );
    }

    TokenResponse tokenResponse = (TokenResponse) JSON.deserialize(
      response.getBody(),
      TokenResponse.class
    );

    if (String.isBlank(tokenResponse.access_token)) {
      throw new EgnyteOAuthException(
        'Egnyte authorization code exchange did not return an access_token.'
      );
    }

    return tokenResponse;
  }

  @TestVisible
  private static String loadConfiguredRefreshToken() {
    if (!Schema.getGlobalDescribe().containsKey('Egnyte_Settings__mdt')) {
      return null;
    }

    List<Egnyte_Settings__mdt> configuredSettings = [
      SELECT Refresh_Token__c
      FROM Egnyte_Settings__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];

    if (configuredSettings.isEmpty()) {
      return null;
    }

    return configuredSettings[0].Refresh_Token__c;
  }
}