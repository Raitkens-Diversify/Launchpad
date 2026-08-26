/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class EgnyteControllerTest {
  private static final String RECORD_ID = '001TO000008Zp6JYAS';
  private static final String MAPPED_PATH = '/Shared/Salesforce.com/Account/AC';
  private static final String REDIRECT_URL =
    'https://falconpark.egnyte.com/nav/one-time-session-token';
  private static final String TEST_TOKEN = 'test-access-token';

  private class EgnyteSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();

      if (request.getEndpoint().contains('/sfdc/foldermap/')) {
        System.assertEquals('GET', request.getMethod());
        System.assert(
          request.getEndpoint().startsWith('https://falconpark.egnyte.com')
        );
        System.assertEquals(
          'Bearer ' + TEST_TOKEN,
          request.getHeader('Authorization')
        );
        response.setStatusCode(200);
        response.setBody('{"path":"' + MAPPED_PATH + '"}');
        return response;
      }

      if (request.getEndpoint().contains('/navigate')) {
        System.assertEquals('POST', request.getMethod());
        System.assert(
          request.getEndpoint().startsWith('https://falconpark.egnyte.com')
        );
        System.assertEquals(
          'Bearer ' + TEST_TOKEN,
          request.getHeader('Authorization')
        );
        System.assertEquals(
          'application/json',
          request.getHeader('Content-Type')
        );

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        );
        System.assertEquals(true, payload.get('embedded'));
        System.assertEquals(MAPPED_PATH, payload.get('path'));

        response.setStatusCode(200);
        response.setBody('{"redirect":"' + REDIRECT_URL + '"}');
        return response;
      }

      response.setStatusCode(404);
      response.setBody('{"errorMessage":"Unexpected endpoint"}');
      return response;
    }
  }

  private class EgnyteFolderMapFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();

      if (request.getEndpoint().contains('/sfdc/foldermap/')) {
        response.setStatusCode(404);
        response.setBody('{"errorMessage":"Mapping not found"}');
        return response;
      }

      if (request.getEndpoint().contains('/navigate')) {
        response.setStatusCode(200);
        response.setBody('{"redirect":"' + REDIRECT_URL + '"}');
        return response;
      }

      response.setStatusCode(404);
      response.setBody('{"errorMessage":"Unexpected endpoint"}');
      return response;
    }
  }

  private class EgnyteNavigateFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(401);
      response.setBody(
        '{"fault":{"faultstring":"Invalid Access Token","detail":{"errorcode":"keymanagement.service.invalid_access_token"}}}'
      );
      return response;
    }
  }

  @IsTest
  static void getEgnyteFolderUrl_returnsDirectUrlWithoutApiCredentials() {
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(null, null, null, null, null, null);
    Test.stopTest();

    System.assertEquals(
      'https://falconpark.egnyte.com/navigate/path/Shared/Salesforce.com',
      url
    );
  }

  @IsTest
  static void buildDirectEmbedUrl_buildsNavigatePathDeepLink() {
    System.assertEquals(
      'https://falconpark.egnyte.com/navigate/path/Shared/Salesforce.com/Account/AC',
      EgnyteController.buildDirectEmbedUrl(
        'https://falconpark.egnyte.com',
        '/Shared/Salesforce.com/Account/AC'
      )
    );
    System.assertEquals(
      'https://falconpark.egnyte.com/navigate/path/Shared/Salesforce.com/Account/AC/ACME%20Company',
      EgnyteController.buildDirectEmbedUrl(
        'https://falconpark.egnyte.com',
        '/Shared/Salesforce.com/Account/AC/ACME Company'
      )
    );
  }

  @IsTest
  static void getEgnyteFolderUrl_buildsRecordSpecificPathWithoutApiCredentials() {
    Account acct = new Account(Name = 'ACME Company', Type ='Other', Classification__c = 'Vendor;');
    insert acct;
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(acct.Id, null, null, null, null, null);
    Test.stopTest();

    System.assert(
      url.contains('Account/AC/ACME%20Company'),
      'Expected record-specific folder path in URL: ' + url
    );
  }

  @IsTest
  static void buildTwoLetterNameHash_usesFirstTwoCharacters() {
    System.assertEquals('AC', EgnyteController.buildTwoLetterNameHash('ACME Company'));
    System.assertEquals('X', EgnyteController.buildTwoLetterNameHash('X'));
    System.assertEquals('XX', EgnyteController.buildTwoLetterNameHash(''));
  }

  @IsTest
  static void hasApiCredentials_returnsFalseWhenOAuthSettingsMissing() {
    EgnyteController.testAccessTokenOverride = null;

    System.assertEquals(
      false,
      EgnyteController.hasApiCredentials(
        EgnyteController.buildTestSettings(
          'https://falconpark.egnyte.com',
          null,
          null,
          null
        )
      )
    );
  }

  @IsTest
  static void getEgnyteFolderUrl_returnsRedirectForMappedRecord() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteSuccessMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(RECORD_ID, null, null, null, null, null);
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenMappingMissingEvenIfLocalRecordExists() {
    Account acct = new Account(Name = 'ACME Company', Type ='Other', Classification__c = 'Vendor;');
    insert acct;
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteFolderMapFailureMock());
    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(acct.Id, null, null, null, null, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('No Egnyte folder mapping exists'),
        expected.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenMappingAndLocalRecordMissing() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteFolderMapFailureMock());
    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(RECORD_ID, null, null, null, null, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('No Egnyte folder mapping exists'),
        expected.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getEgnyteFolderUrl_skipsFolderMapWhenRecordIdBlank() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateOnlyMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(null, null, null, null, null, null);
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }

  private class EgnyteNavigateOnlyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      System.assert(
        request.getEndpoint().contains('/navigate'),
        'Blank record Id should skip foldermap and call Navigate API only'
      );
      response.setStatusCode(200);
      response.setBody('{"redirect":"' + REDIRECT_URL + '"}');
      return response;
    }
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenNavigateFails() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateFailureMock());

    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(null, null, null, null, null, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('Egnyte Navigate API failed'),
        expected.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(true, didThrow, 'Navigate failure should throw');
  }

  @IsTest
  static void parseFolderPath_supportsStringAndObjectResponses() {
    System.assertEquals(
      MAPPED_PATH,
      EgnyteController.parseFolderPath('"' + MAPPED_PATH + '"', '/Shared/Salesforce.com')
    );
    System.assertEquals(
      MAPPED_PATH,
      EgnyteController.parseFolderPath(
        '{"folderPath":"' + MAPPED_PATH + '"}',
        '/Shared/Salesforce.com'
      )
    );
    System.assertEquals(
      '/Shared/Salesforce.com',
      EgnyteController.parseFolderPath('{}', '/Shared/Salesforce.com')
    );
  }

  @IsTest
  static void buildBaseUrl_normalizesDomainValues() {
    System.assertEquals(
      'https://falconpark.egnyte.com',
      EgnyteController.buildBaseUrl('falconpark.egnyte.com')
    );
    System.assertEquals(
      'https://falconpark.egnyte.com',
      EgnyteController.buildBaseUrl('https://falconpark.egnyte.com/')
    );
  }

  @IsTest
  static void refreshAccessToken_returnsAccessTokenFromOAuthResponse() {
    Test.setMock(HttpCalloutMock.class, new EgnyteRefreshSuccessMock());

    Test.startTest();
    String token = EgnyteController.refreshAccessToken(
      EgnyteController.buildTestSettings(
        'https://falconpark.egnyte.com',
        'client-id',
        'client-secret',
        'refresh-token'
      )
    );
    Test.stopTest();

    System.assertEquals(TEST_TOKEN, token);
  }

  @IsTest
  static void resolveAccessToken_throwsWhenCredentialsMissing() {
    EgnyteController.testAccessTokenOverride = null;
    Boolean didThrow = false;

    try {
      EgnyteController.resolveAccessToken(
        EgnyteController.buildTestSettings(
          'https://falconpark.egnyte.com',
          null,
          null,
          null
        )
      );
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('Egnyte access token is not configured'),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void applyCredentialOverrides_appliesClientCredentialsAndDomain() {
    EgnyteController.Settings settings = EgnyteController.buildTestSettings(
      'https://falconpark.egnyte.com',
      null,
      null,
      null
    );

    EgnyteController.applyCredentialOverrides(
      settings,
      'test-client-id',
      'test-client-secret',
      'test-refresh-token',
      'custom.egnyte.com',
      'test-access-token'
    );

    System.assertEquals('test-client-id', settings.clientId);
    System.assertEquals('test-client-secret', settings.clientSecret);
    System.assertEquals('test-refresh-token', settings.refreshToken);
    System.assertEquals('test-access-token', settings.accessToken);
    System.assertEquals('https://custom.egnyte.com', settings.baseUrl);
  }

  @IsTest
  static void normalizeMappedFolderPath_supportsRelativeFoldermapPaths() {
    EgnyteController.Settings settings = EgnyteController.buildTestSettings(
      'https://falconpark.egnyte.com',
      null,
      null,
      null
    );

    System.assertEquals(
      '/Shared/Salesforce.com/Accounts/ABC',
      EgnyteController.normalizeMappedFolderPath('Accounts/ABC', settings)
    );
    System.assertEquals(
      '/Shared/Salesforce.com/Account/AC/ACME Company',
      EgnyteController.normalizeMappedFolderPath(
        '/Shared/Salesforce.com/Account/AC/ACME Company',
        settings
      )
    );
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenRecordMissingInOrgWithoutApiCredentials() {
    EgnyteController.testAccessTokenOverride = null;
    Boolean didThrow = false;

    try {
      EgnyteController.getEgnyteFolderUrl(
        RECORD_ID,
        null,
        null,
        null,
        null,
        null
      );
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('foldermap API'),
        expected.getMessage()
      );
      System.assert(
        expected.getMessage().contains(RECORD_ID),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getEgnyteFolderUrl_resolvesFoldermapWithoutLocalRecord() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteSuccessMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(RECORD_ID, null, null, null, null, null);
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }

  private class EgnyteRefreshSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      System.assertEquals('POST', request.getMethod());
      response.setStatusCode(200);
      response.setBody('{"access_token":"' + TEST_TOKEN + '"}');
      return response;
    }
  }
}