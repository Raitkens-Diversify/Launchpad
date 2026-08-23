/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class EgnyteOAuthControllerTest {
  private static final String TEST_CODE = 'auth-code-123';
  private static final String TEST_STATE = 'state-abc';
  private static final String TEST_ACCESS_TOKEN = 'access-token';
  private static final String TEST_REFRESH_TOKEN = 'refresh-token';

  @IsTest
  static void buildAuthorizationUrl_includesRequiredOAuthParameters() {
    String redirectUri = 'https://example.my.salesforce.com/apex/EgnyteOAuthCallback';

    String authorizationUrl = EgnyteOAuthController.buildAuthorizationUrl(
      TEST_STATE,
      redirectUri
    );

    System.assert(authorizationUrl.contains('response_type=code'));
    System.assert(authorizationUrl.contains('client_id='));
    System.assert(
      authorizationUrl.contains(
        EncodingUtil.urlEncode(redirectUri, 'UTF-8')
      )
    );
    System.assert(
      authorizationUrl.contains(
        EncodingUtil.urlEncode('Egnyte.salesforce Egnyte.launchwebsession', 'UTF-8')
      )
    );
    System.assert(authorizationUrl.contains('state=' + TEST_STATE));
  }

  @IsTest
  static void exchangeAuthorizationCode_returnsTokens() {
    EgnyteOAuthController.testTokenResponseOverride = new EgnyteOAuthController.TokenResponse();
    EgnyteOAuthController.testTokenResponseOverride.access_token = TEST_ACCESS_TOKEN;
    EgnyteOAuthController.testTokenResponseOverride.refresh_token = TEST_REFRESH_TOKEN;
    EgnyteOAuthController.testTokenResponseOverride.expires_in = 3600;

    Test.startTest();
    EgnyteOAuthController.TokenResponse tokenResponse = EgnyteOAuthController.exchangeAuthorizationCode(
      TEST_CODE,
      'https://example.my.salesforce.com/apex/EgnyteOAuthCallback'
    );
    Test.stopTest();

    System.assertEquals(TEST_ACCESS_TOKEN, tokenResponse.access_token);
    System.assertEquals(TEST_REFRESH_TOKEN, tokenResponse.refresh_token);
  }

  @IsTest
  static void validateOAuthState_rejectsMismatchedState() {
    EgnyteOAuthController.persistOAuthState(TEST_STATE);
    Boolean didThrow = false;

    try {
      EgnyteOAuthController.validateOAuthState('different-state');
    } catch (EgnyteOAuthController.EgnyteOAuthException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('state did not match'),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void validateOAuthState_rejectsMissingState() {
    EgnyteOAuthController.testSessionStateOverride = null;
    Boolean didThrow = false;

    try {
      EgnyteOAuthController.validateOAuthState(TEST_STATE);
    } catch (EgnyteOAuthController.EgnyteOAuthException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('state is missing'),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getOAuthStatus_returnsConnectUrls() {
    EgnyteOAuthController.OAuthStatus status = EgnyteOAuthController.getOAuthStatus();

    System.assert(status.redirectUri.contains('/apex/EgnyteOAuthCallback'));
    System.assert(status.connectUrl.contains('/apex/EgnyteOAuthConnect'));
  }

  @IsTest
  static void handleCallback_exchangesCodeWhenStateMatches() {
    EgnyteOAuthController.persistOAuthState(TEST_STATE);
    EgnyteOAuthController.testTokenResponseOverride = new EgnyteOAuthController.TokenResponse();
    EgnyteOAuthController.testTokenResponseOverride.access_token = TEST_ACCESS_TOKEN;
    EgnyteOAuthController.testTokenResponseOverride.refresh_token = TEST_REFRESH_TOKEN;
    EgnyteOAuthController.testTokenResponseOverride.expires_in = 3600;

    PageReference callbackPage = Page.EgnyteOAuthCallback;
    Test.setCurrentPage(callbackPage);
    ApexPages.currentPage().getParameters().put('code', TEST_CODE);
    ApexPages.currentPage().getParameters().put('state', TEST_STATE);

    EgnyteOAuthController controller = new EgnyteOAuthController();

    Test.startTest();
    controller.handleCallback();
    Test.stopTest();

    System.assertEquals(true, controller.tokensIssued);
    System.assertEquals(TEST_ACCESS_TOKEN, controller.issuedAccessToken);
    System.assertEquals(TEST_REFRESH_TOKEN, controller.issuedRefreshToken);
    System.assertEquals(null, EgnyteOAuthController.testSessionStateOverride);
  }

  @IsTest
  static void getAuthorizationUrl_returnsAuthorizeEndpoint() {
    EgnyteOAuthController.persistOAuthState(TEST_STATE);

    Test.startTest();
    String authorizationUrl = EgnyteOAuthController.getAuthorizationUrl();
    Test.stopTest();

    System.assert(authorizationUrl.contains('response_type=code'));
    System.assert(authorizationUrl.contains('client_id='));
  }

  @IsTest
  static void handleCallback_surfacesAuthorizationErrors() {
    PageReference callbackPage = Page.EgnyteOAuthCallback;
    Test.setCurrentPage(callbackPage);
    ApexPages.currentPage().getParameters().put('error', 'access_denied');

    EgnyteOAuthController controller = new EgnyteOAuthController();
    controller.handleCallback();

    System.assertEquals(1, ApexPages.getMessages().size());
    System.assert(
      ApexPages.getMessages()[0].getSummary().contains('access_denied')
    );
    System.assertEquals(false, controller.tokensIssued);
  }

  @IsTest
  static void handleCallback_requiresAuthorizationCode() {
    EgnyteOAuthController controller = new EgnyteOAuthController();
    controller.handleCallback();

    System.assertEquals(1, ApexPages.getMessages().size());
    System.assert(
      ApexPages.getMessages()[0]
        .getSummary()
        .contains('did not return an authorization code')
    );
  }

  @IsTest
  static void exchangeAuthorizationCode_throwsWhenTokenEndpointFails() {
    Test.setMock(HttpCalloutMock.class, new EgnyteTokenFailureMock());
    Boolean didThrow = false;

    try {
      EgnyteOAuthController.exchangeAuthorizationCode(
        TEST_CODE,
        'https://example.my.salesforce.com/apex/EgnyteOAuthCallback'
      );
    } catch (EgnyteOAuthController.EgnyteOAuthException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('authorization code exchange failed'),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void beginAuthorization_redirectsToEgnyte() {
    EgnyteOAuthController.testAuthorizationUrlOverride =
      'https://launchpad.egnyte.com/puboauth/token?response_type=code';

    EgnyteOAuthController controller = new EgnyteOAuthController();

    Test.startTest();
    PageReference redirectPage = controller.beginAuthorization();
    Test.stopTest();

    System.assertNotEquals(null, redirectPage);
    System.assertEquals(true, redirectPage.getRedirect());
    System.assert(
      redirectPage.getUrl()
        .contains('https://launchpad.egnyte.com/puboauth/token')
    );
    System.assertNotEquals(null, EgnyteOAuthController.testSessionStateOverride);
  }

  private class EgnyteTokenFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(400);
      response.setBody('{"error":"invalid_grant"}');
      return response;
    }
  }
}