/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * The controller reads its Egnyte domain and default folder from Egnyte_Settings__mdt
 * (falling back to hard-coded defaults). A test cannot write custom metadata, so every
 * test that asserts on a URL passes TEST_DOMAIN through the `domain` override parameter
 * and derives the folder root from EgnyteController.loadSettings(). Expectations therefore
 * never depend on which Egnyte domain the org happens to be configured for.
 */
@IsTest
private class EgnyteControllerTest {
  private static final String TEST_DOMAIN = 'falconpark.egnyte.com';
  private static final String TEST_BASE_URL = 'https://' + TEST_DOMAIN;
  private static final String MAPPED_PATH = '/Shared/Salesforce.com/Account/AC';
  private static final String REDIRECT_URL = TEST_BASE_URL + '/nav/one-time-session-token';  private static final String TEST_TOKEN = 'test-access-token';
  private static final String SYNC_OBJECT_API_NAME = 'efs__EgnyteSyncObject__c';

  private static Integer refreshCallCount = 0;

  /** A syntactically valid Account Id (15 chars) that no org holds a row for. */
  private static String missingRecordId() {
    return Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
  }

  private static String accountLabel() {
    return Account.SObjectType.getDescribe().getLabel();
  }

  /** Folder root the controller will use for this org, normalized the way the controller does. */
  private static String configuredRoot() {
    return EgnyteController.normalizeFolderPath(
      EgnyteController.loadSettings().defaultFolderPath
    );
  }

  private static Account insertAccount(String name) {
    Account acct = new Account(Name = name, Type = 'Prospect');
    insert acct;
    return acct;
  }

  private static EgnyteController.Settings testSettings() {
    return EgnyteController.buildTestSettings(TEST_BASE_URL, null, null, null);
  }

  private static Boolean syncObjectInstalled() {
    return Schema.getGlobalDescribe().containsKey(SYNC_OBJECT_API_NAME);
  }

  /**
   * Inserts an Egnyte sync configuration row without a compile-time dependency on the efs
   * package. Returns false (instead of throwing) when the org rejects the row for reasons
   * outside this test's control -- e.g. the efs package requires an object's sync trigger to
   * be generated via its own Setup UI before efs__Active__c can be true, which a test can never
   * do. Callers must skip their scenario when this returns false so the suite stays portable
   * across orgs where Egnyte sync automation has and hasn't been activated for Account.
   */
  private static Boolean insertSyncConfig(Map<String, Object> fieldValues) {
    SObject config = Schema.getGlobalDescribe().get(SYNC_OBJECT_API_NAME).newSObject();
    for (String fieldName : fieldValues.keySet()) {
      config.put(fieldName, fieldValues.get(fieldName));
    }
    try {
      insert config;
      return true;
    } catch (DmlException configNotActivatable) {
      return false;
    }
  }

  private class EgnyteSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();

      if (request.getEndpoint().contains('/sfdc/foldermap/')) {
        System.assertEquals('GET', request.getMethod(), 'foldermap lookups use GET');
        System.assert(
          request.getEndpoint().startsWith(TEST_BASE_URL),
          'foldermap should call the overridden domain: ' + request.getEndpoint()        );
        System.assertEquals(
          'Bearer ' + TEST_TOKEN,
          request.getHeader('Authorization')
        );
        response.setStatusCode(200);
        response.setBody('{"path":"' + MAPPED_PATH + '"}');
        return response;
      }

      if (request.getEndpoint().contains('/navigate')) {
        System.assertEquals('POST', request.getMethod(), 'Navigate uses POST');
        System.assert(
          request.getEndpoint().startsWith(TEST_BASE_URL),
          'Navigate should call the overridden domain: ' + request.getEndpoint()        );
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

  private class EgnyteFolderMapServerErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(500);
      response.setBody('{"errorMessage":"Internal error"}');
      return response;
    }
  }

  /** Foldermap answers with a path relative to the default folder, under an alternate key. */
  private class EgnyteRelativeFolderMapMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"folder_path":"Account/AC/ACME Company"}');
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

  private class EgnyteNavigateNoRedirectMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"status":"ok"}');
      return response;
    }
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

  private class EgnyteRefreshSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      System.assertEquals('POST', request.getMethod());
      response.setStatusCode(200);
      response.setBody('{"access_token":"' + TEST_TOKEN + '"}');
      return response;
    }
  }

  private class EgnyteRefreshFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(401);
      response.setBody('{"error":"invalid_grant"}');
      return response;
    }
  }

  private class EgnyteRefreshNoTokenMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"token_type":"bearer","expires_in":3600}');
      return response;
    }
  }

  /** Full OAuth flow: token refresh, then foldermap and Navigate carrying the refreshed token. */
  private class EgnyteOAuthFlowMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      String endpoint = request.getEndpoint();

      if (endpoint.contains('/puboauth/token')) {
        refreshCallCount++;
        System.assertEquals('POST', request.getMethod(), 'token refresh uses POST');
        System.assert(
          endpoint.startsWith(TEST_BASE_URL),
          'token refresh should use the overridden domain: ' + endpoint
        );
        System.assertEquals(
          'application/x-www-form-urlencoded',
          request.getHeader('Content-Type')
        );
        String body = request.getBody();
        System.assert(body.contains('grant_type=refresh_token'), body);
        System.assert(body.contains('client_id=test-client-id'), body);
        System.assert(body.contains('client_secret=test-client-secret'), body);
        System.assert(body.contains('refresh_token=test-refresh-token'), body);
        response.setStatusCode(200);
        response.setBody('{"access_token":"' + TEST_TOKEN + '","token_type":"bearer"}');
        return response;
      }

      System.assertEquals(
        'Bearer ' + TEST_TOKEN,
        request.getHeader('Authorization'),
        'API requests should carry the refreshed access token'
      );

      if (endpoint.contains('/sfdc/foldermap/')) {
        response.setStatusCode(200);
        response.setBody('{"path":"' + MAPPED_PATH + '"}');
        return response;
      }

      if (endpoint.contains('/navigate')) {
        response.setStatusCode(200);
        response.setBody('{"redirect":"' + REDIRECT_URL + '"}');
        return response;
      }

      response.setStatusCode(404);
      response.setBody('{"errorMessage":"Unexpected endpoint"}');
      return response;
    }
  }

  @IsTest
  static void getEgnyteFolderUrl_returnsDirectUrlWithoutApiCredentials() {
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(null, null, null, null, TEST_DOMAIN, null);
    Test.stopTest();

    System.assertEquals(
      TEST_BASE_URL + '/navigate/path/' +
        EgnyteController.encodePathForNavigateUrl(configuredRoot().substring(1)),
      url,
      'without credentials the direct link uses the overridden domain and the configured default folder'    );
  }

  @IsTest
  static void getEgnyteFolderUrl_usesConfiguredSettingsWhenNoOverrideGiven() {
    EgnyteController.testAccessTokenOverride = null;
    EgnyteController.Settings configured = EgnyteController.loadSettings();
    System.assert(configured.baseUrl.startsWith('https://'), configured.baseUrl);
    System.assert(String.isNotBlank(configured.defaultFolderPath), 'default folder path');
    // Safety net: if this org's Egnyte_Settings__mdt carries API credentials the controller
    // goes through the Navigate API instead of building a direct link.
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateOnlyMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(null, null, null, null, null, null);
    Test.stopTest();

    if (EgnyteController.hasApiCredentials(configured)) {
      System.assertEquals(REDIRECT_URL, url, 'configured credentials route through Navigate');
    } else {
      System.assertEquals(
        EgnyteController.buildDirectEmbedUrl(configured.baseUrl, configured.defaultFolderPath),
        url,
        'without credentials the direct link is built from the configured domain and default folder'
      );
      System.assert(url.startsWith(configured.baseUrl), url);
    }
  }

  @IsTest
  static void buildDirectEmbedUrl_buildsNavigatePathDeepLink() {
    System.assertEquals(
      TEST_BASE_URL + '/navigate/path/Shared/Salesforce.com/Account/AC',
      EgnyteController.buildDirectEmbedUrl(
        TEST_BASE_URL,        '/Shared/Salesforce.com/Account/AC'
      )
    );
    System.assertEquals(
      TEST_BASE_URL + '/navigate/path/Shared/Salesforce.com/Account/AC/ACME%20Company',
      EgnyteController.buildDirectEmbedUrl(
        TEST_BASE_URL,        '/Shared/Salesforce.com/Account/AC/ACME Company'
      )
    );
    System.assertEquals(
      TEST_BASE_URL + '/navigate/path/Shared/Salesforce.com',
      EgnyteController.buildDirectEmbedUrl(TEST_BASE_URL, null),
      'blank folder path falls back to the shared default'
    );
    System.assertEquals(
      TEST_BASE_URL + '/navigate/path/Shared/A%20%26%20B',
      EgnyteController.buildDirectEmbedUrl(TEST_BASE_URL, 'Shared//A & B/'),
      'missing leading slash is added, empty segments are skipped and segments are encoded'
    );
  }

  @IsTest
  static void encodePathForNavigateUrl_handlesBlankAndEmptySegments() {
    System.assertEquals('', EgnyteController.encodePathForNavigateUrl(null));
    System.assertEquals('', EgnyteController.encodePathForNavigateUrl('  '));
    System.assertEquals(
      'Shared/Sales%20Team',
      EgnyteController.encodePathForNavigateUrl('Shared// Sales Team ')
    );
  }

  @IsTest
  static void normalizeFolderPath_addsLeadingSlashAndDefaultsBlank() {
    System.assertEquals('/Shared/Salesforce.com', EgnyteController.normalizeFolderPath(null));
    System.assertEquals('/Shared/Salesforce.com', EgnyteController.normalizeFolderPath(' '));
    System.assertEquals('/Shared/Clients', EgnyteController.normalizeFolderPath(' Shared/Clients '));
    System.assertEquals('/Shared/Clients', EgnyteController.normalizeFolderPath('/Shared/Clients'));
  }

  @IsTest
  static void getEgnyteFolderUrl_buildsRecordSpecificPathWithoutApiCredentials() {
    Account acct = insertAccount('ACME Company');
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(acct.Id, null, null, null, TEST_DOMAIN, null);
    Test.stopTest();

    System.assertEquals(
      EgnyteController.buildDirectEmbedUrl(
        TEST_BASE_URL,
        configuredRoot() + '/' + accountLabel() + '/AC/ACME Company'
      ),
      url,
      'Expected record-specific folder path in URL: ' + url
    );
    System.assert(url.startsWith(TEST_BASE_URL), 'domain override should win: ' + url);
  }

  @IsTest
  static void getEgnyteFolderUrl_usesCustomFolderPathAndNameFieldFromSyncConfig() {
    if (!syncObjectInstalled()) {
      return; // Egnyte for Salesforce package not installed; nothing to configure.
    }
    Boolean configActivated = insertSyncConfig(
      new Map<String, Object>{
        'Name' => 'Account',
        'efs__ObjectLabel__c' => 'Account',
        'efs__Active__c' => true,
        'efs__IsDefaultFolderPath__c' => false,
        'efs__CustomFolderPath__c' => 'Clients',
        'efs__IsDefaultFolderName__c' => false,
        'efs__CustomFolderNameField__c' => 'AccountNumber',
        'efs__ObjectNameField__c' => 'Name'
      }
    );
    if (!configActivated) {
      return; // Egnyte sync automation is not activated for Account in this org (efs package
      // requires its sync trigger to be generated via Setup before a config can be Active).
    }
    Account acct = new Account(
      Name = 'ACME Company',
      AccountNumber = 'ACME-001',
      Type = 'Prospect'
    );
    insert acct;
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(acct.Id, null, null, null, TEST_DOMAIN, null);
    Test.stopTest();

    System.assertEquals(
      EgnyteController.buildDirectEmbedUrl(
        TEST_BASE_URL,
        '/Shared/Clients/' + accountLabel() + '/AC/ACME-001'
      ),
      url,
      'custom folder path replaces the default root, the custom name field names the folder and the object name field drives the hash: ' + url
    );
  }

  @IsTest
  static void getEgnyteFolderUrl_nestsChildFolderUnderParentFromSyncConfig() {
    if (!syncObjectInstalled()) {
      return; // Egnyte for Salesforce package not installed; nothing to configure.
    }
    Boolean configActivated = insertSyncConfig(
      new Map<String, Object>{
        'Name' => 'Account',
        'efs__ObjectLabel__c' => 'Account',
        'efs__Active__c' => true,
        'efs__IsDefaultFolderPath__c' => true,
        'efs__IsDefaultFolderName__c' => true,
        'efs__ParentObjectFieldAPIName__c' => 'ParentId',
        'efs__ParentObject__c' => 'Account',
        'efs__ParentObjectNameField__c' => 'Name',
        'efs__ObjectNameField__c' => 'Name'
      }
    );
    if (!configActivated) {
      return; // Egnyte sync automation is not activated for Account in this org (efs package
      // requires its sync trigger to be generated via Setup before a config can be Active).
    }
    Account parent = insertAccount('Harrison Holdings');
    Account child = new Account(
      Name = 'ACME Company',
      Type = 'Prospect',
      ParentId = parent.Id
    );
    insert child;
    EgnyteController.testAccessTokenOverride = null;

    Test.startTest();
    String parentUrl = EgnyteController.getEgnyteFolderUrl(parent.Id, null, null, null, TEST_DOMAIN, null);
    String childUrl = EgnyteController.getEgnyteFolderUrl(child.Id, null, null, null, TEST_DOMAIN, null);
    Test.stopTest();

    String parentPath = configuredRoot() + '/' + accountLabel() + '/Ha/Harrison Holdings';
    System.assertEquals(
      EgnyteController.buildDirectEmbedUrl(TEST_BASE_URL, parentPath),
      parentUrl,
      'a record without a parent falls back to the default root: ' + parentUrl
    );
    System.assertEquals(
      EgnyteController.buildDirectEmbedUrl(
        TEST_BASE_URL,
        parentPath + '/' + accountLabel() + '/AC/ACME Company'
      ),
      childUrl,
      'a child record nests under its parent folder: ' + childUrl
    );
  }

  @IsTest
  static void resolveFolderPathFromRecord_returnsDefaultPathForInvalidId() {
    EgnyteController.Settings settings = testSettings();
    System.assertEquals(
      settings.defaultFolderPath,
      EgnyteController.resolveFolderPathFromRecord('not-an-id', settings)
    );
  }

  @IsTest
  static void resolveFolderPath_returnsDefaultPathWhenRecordIdBlank() {
    EgnyteController.testAccessTokenOverride = null;
    EgnyteController.Settings settings = testSettings();
    System.assertEquals(settings.defaultFolderPath, EgnyteController.resolveFolderPath(null, settings));
    System.assertEquals(settings.defaultFolderPath, EgnyteController.resolveFolderPath('  ', settings));
  }

  @IsTest
  static void buildTwoLetterNameHash_usesFirstTwoCharacters() {
    System.assertEquals('AC', EgnyteController.buildTwoLetterNameHash('ACME Company'));
    System.assertEquals('X', EgnyteController.buildTwoLetterNameHash('X'));
    System.assertEquals('XX', EgnyteController.buildTwoLetterNameHash(''));
    System.assertEquals('XX', EgnyteController.buildTwoLetterNameHash(null));
    System.assertEquals('Jo', EgnyteController.buildTwoLetterNameHash('  John '));
  }

  @IsTest
  static void hasApiCredentials_returnsFalseWhenOAuthSettingsMissing() {
    EgnyteController.testAccessTokenOverride = null;

    System.assertEquals(
      false,
      EgnyteController.hasApiCredentials(testSettings())    );
  }

  @IsTest
  static void hasApiCredentials_recognizesAccessTokenOrOAuthTriplet() {
    EgnyteController.testAccessTokenOverride = null;

    EgnyteController.Settings withAccessToken = testSettings();
    withAccessToken.accessToken = 'abc123';
    System.assertEquals(true, EgnyteController.hasApiCredentials(withAccessToken), 'access token');

    EgnyteController.Settings withPlaceholder = testSettings();
    withPlaceholder.accessToken = 'REPLACE_WITH_EGNYTE_ACCESS_TOKEN';
    System.assertEquals(false, EgnyteController.hasApiCredentials(withPlaceholder), 'placeholder token');

    EgnyteController.Settings withRefresh = EgnyteController.buildTestSettings(
      TEST_BASE_URL,
      'client-id',
      'client-secret',
      'refresh-token'
    );
    System.assertEquals(true, EgnyteController.hasApiCredentials(withRefresh), 'OAuth triplet');

    EgnyteController.Settings partialTriplet = EgnyteController.buildTestSettings(
      TEST_BASE_URL,
      'client-id',
      null,
      'refresh-token'
    );
    System.assertEquals(false, EgnyteController.hasApiCredentials(partialTriplet), 'missing secret');

    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    System.assertEquals(true, EgnyteController.hasApiCredentials(testSettings()), 'test override');
    System.assertEquals(true, EgnyteController.hasFoldermapCredentials(testSettings()), 'foldermap uses the same rule');
  }

  @IsTest
  static void isConfiguredToken_rejectsBlankAndPlaceholderValues() {
    System.assertEquals(false, EgnyteController.isConfiguredToken(null));
    System.assertEquals(false, EgnyteController.isConfiguredToken(''));
    System.assertEquals(false, EgnyteController.isConfiguredToken('REPLACE_WITH_EGNYTE_ACCESS_TOKEN'));
    System.assertEquals(false, EgnyteController.isConfiguredToken('REPLACE_WITH_EGNYTE_REFRESH_TOKEN'));
    System.assertEquals(true, EgnyteController.isConfiguredToken('real-token'));
    System.assertEquals('', EgnyteController.normalizeToken(null));
    System.assertEquals('abc', EgnyteController.normalizeToken('  abc '));
  }

  @IsTest
  static void getEgnyteFolderUrl_returnsRedirectForMappedRecord() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteSuccessMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(
      missingRecordId(),
      null,
      null,
      null,
      TEST_DOMAIN,
      null
    );
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }

  @IsTest
  static void getEgnyteFolderUrl_refreshesTokenWhenOAuthOverridesProvided() {
    EgnyteController.testAccessTokenOverride = null;
    refreshCallCount = 0;
    Test.setMock(HttpCalloutMock.class, new EgnyteOAuthFlowMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(
      missingRecordId(),
      'test-client-id',
      'test-client-secret',
      'test-refresh-token',
      TEST_DOMAIN,
      null
    );
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
    System.assertEquals(
      2,
      refreshCallCount,
      'the token is refreshed once per API request (foldermap, then Navigate); no caching today'
    );
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenMappingMissingEvenIfLocalRecordExists() {
    Account acct = insertAccount('ACME Company');
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteFolderMapFailureMock());
    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(acct.Id, null, null, null, TEST_DOMAIN, null);
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
    String recordId = missingRecordId();

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(recordId, null, null, null, TEST_DOMAIN, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('No Egnyte folder mapping exists'),
        expected.getMessage()
      );
      System.assert(expected.getMessage().contains(recordId), expected.getMessage());
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenFoldermapReturnsServerError() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteFolderMapServerErrorMock());
    Boolean didThrow = false;
    String recordId = missingRecordId();

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(recordId, null, null, null, TEST_DOMAIN, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('Egnyte foldermap API failed'),
        expected.getMessage()
      );
      System.assert(expected.getMessage().contains('Status: 500'), expected.getMessage());
      System.assert(expected.getMessage().contains(recordId), expected.getMessage());
    }
    Test.stopTest();

    System.assertEquals(true, didThrow, 'non-404 foldermap failures should throw');
  }

  @IsTest
  static void getEgnyteFolderUrl_skipsFolderMapWhenRecordIdBlank() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateOnlyMock());

    Test.startTest();
    String url = EgnyteController.getEgnyteFolderUrl(null, null, null, null, TEST_DOMAIN, null);
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenNavigateFails() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateFailureMock());

    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(null, null, null, null, TEST_DOMAIN, null);
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
  static void getEgnyteFolderUrl_throwsWhenNavigateOmitsRedirect() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteNavigateNoRedirectMock());

    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.getEgnyteFolderUrl(null, null, null, null, TEST_DOMAIN, null);
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('did not return a redirect URL'),
        expected.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(true, didThrow, 'Navigate response without redirect should throw');
  }

  @IsTest
  static void requestFolderMapPath_returnsNormalizedRelativePath() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteRelativeFolderMapMock());

    Test.startTest();
    String path = EgnyteController.requestFolderMapPath(missingRecordId(), testSettings());
    Test.stopTest();

    System.assertEquals(
      '/Shared/Salesforce.com/Account/AC/ACME Company',
      path,
      'relative foldermap paths are anchored under the default folder'
    );
  }

  @IsTest
  static void requestFolderMapPath_returnsNullWhenMappingMissing() {
    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    Test.setMock(HttpCalloutMock.class, new EgnyteFolderMapFailureMock());

    Test.startTest();
    String path = EgnyteController.requestFolderMapPath(missingRecordId(), testSettings());
    Test.stopTest();

    System.assertEquals(null, path, 'a 404 mapping yields no path');
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
  static void parseFolderPath_fallsBackToDefaultForUnsupportedPayloads() {
    String fallback = '/Shared/Default';
    System.assertEquals(fallback, EgnyteController.parseFolderPath(null, fallback), 'null body');
    System.assertEquals(fallback, EgnyteController.parseFolderPath('   ', fallback), 'blank body');
    System.assertEquals(fallback, EgnyteController.parseFolderPath('"   "', fallback), 'blank string body');
    System.assertEquals(fallback, EgnyteController.parseFolderPath('[1,2]', fallback), 'array body');
    System.assertEquals(fallback, EgnyteController.parseFolderPath('{"path":123}', fallback), 'non-string path');
    System.assertEquals(
      '/Shared/X',
      EgnyteController.parseFolderPath('{"path":"  ","folder":"/Shared/X"}', fallback),
      'blank candidate keys are skipped in favour of later ones'
    );
    System.assertEquals(
      '/Shared/Y',
      EgnyteController.parseFolderPath('{"folder_path":" /Shared/Y "}', fallback),
      'folder_path key is trimmed'    );
  }

  @IsTest
  static void buildBaseUrl_normalizesDomainValues() {
    System.assertEquals(TEST_BASE_URL, EgnyteController.buildBaseUrl(TEST_DOMAIN));
    System.assertEquals(TEST_BASE_URL, EgnyteController.buildBaseUrl(TEST_BASE_URL + '/'));
    System.assertEquals(TEST_BASE_URL, EgnyteController.buildBaseUrl('http://' + TEST_DOMAIN + '//'));
    System.assertEquals(TEST_BASE_URL, EgnyteController.buildBaseUrl('  ' + TEST_DOMAIN + '  '));

    String fallback = EgnyteController.buildBaseUrl(null);
    System.assert(fallback.startsWith('https://') && fallback.endsWith('.egnyte.com'), fallback);
    System.assertEquals(fallback, EgnyteController.buildBaseUrl('  '), 'blank behaves like null');
  }

  @IsTest
  static void refreshAccessToken_returnsAccessTokenFromOAuthResponse() {
    Test.setMock(HttpCalloutMock.class, new EgnyteRefreshSuccessMock());

    Test.startTest();
    String token = EgnyteController.refreshAccessToken(
      EgnyteController.buildTestSettings(
        TEST_BASE_URL,        'client-id',
        'client-secret',
        'refresh-token'
      )
    );
    Test.stopTest();

    System.assertEquals(TEST_TOKEN, token);
  }

  @IsTest
  static void refreshAccessToken_throwsWhenTokenEndpointFails() {
    Test.setMock(HttpCalloutMock.class, new EgnyteRefreshFailureMock());
    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.refreshAccessToken(
        EgnyteController.buildTestSettings(TEST_BASE_URL, 'client-id', 'client-secret', 'refresh-token')
      );
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(expected.getMessage().contains('Egnyte token refresh failed'), expected.getMessage());
      System.assert(expected.getMessage().contains('Status: 401'), expected.getMessage());
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void refreshAccessToken_throwsWhenResponseHasNoAccessToken() {
    Test.setMock(HttpCalloutMock.class, new EgnyteRefreshNoTokenMock());
    Boolean didThrow = false;

    Test.startTest();
    try {
      EgnyteController.refreshAccessToken(
        EgnyteController.buildTestSettings(TEST_BASE_URL, 'client-id', 'client-secret', 'refresh-token')
      );
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('did not return an access_token'),
        expected.getMessage()
      );
    }
    Test.stopTest();

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void resolveAccessToken_throwsWhenCredentialsMissing() {
    EgnyteController.testAccessTokenOverride = null;
    Boolean didThrow = false;

    try {
      EgnyteController.resolveAccessToken(testSettings());    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('Egnyte access token is not configured'),
        expected.getMessage()
      );
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void resolveAccessToken_prefersConfiguredAccessTokenOverRefresh() {
    EgnyteController.testAccessTokenOverride = null;
    EgnyteController.Settings settings = EgnyteController.buildTestSettings(
      TEST_BASE_URL,
      'client-id',
      'client-secret',
      'refresh-token'
    );
    settings.accessToken = 'configured-token';

    // No mock is registered: a callout here would fail, proving the refresh was skipped.
    System.assertEquals('configured-token', EgnyteController.resolveAccessToken(settings));

    EgnyteController.testAccessTokenOverride = TEST_TOKEN;
    System.assertEquals(
      TEST_TOKEN,
      EgnyteController.resolveAccessToken(settings),
      'the test override wins over configured tokens'
    );
  }

  @IsTest
  static void resolveAccessToken_refreshesWhenOnlyOAuthCredentialsConfigured() {
    EgnyteController.testAccessTokenOverride = null;
    Test.setMock(HttpCalloutMock.class, new EgnyteRefreshSuccessMock());

    Test.startTest();
    String token = EgnyteController.resolveAccessToken(
      EgnyteController.buildTestSettings(TEST_BASE_URL, 'client-id', 'client-secret', 'refresh-token')    );
    HttpRequest prepared = EgnyteController.prepareRequest(
      EgnyteController.buildTestSettings(TEST_BASE_URL, 'client-id', 'client-secret', 'refresh-token'),
      TEST_BASE_URL + '/pubapi/v2/navigate',
      'POST'
    );
    Test.stopTest();

    System.assertEquals(TEST_TOKEN, token);
    System.assertEquals('Bearer ' + TEST_TOKEN, prepared.getHeader('Authorization'));
    System.assertEquals('POST', prepared.getMethod());
    System.assertEquals(TEST_BASE_URL + '/pubapi/v2/navigate', prepared.getEndpoint());
  }

  @IsTest
  static void applyCredentialOverrides_appliesClientCredentialsAndDomain() {
    EgnyteController.Settings settings = testSettings();

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
  static void applyCredentialOverrides_ignoresBlankValuesAndTrims() {
    EgnyteController.Settings settings = EgnyteController.buildTestSettings(
      TEST_BASE_URL,
      'client-id',
      'client-secret',
      'refresh-token'    );
    settings.accessToken = 'existing-token';

    EgnyteController.applyCredentialOverrides(settings, null, '  ', '', null, ' ');

    System.assertEquals('client-id', settings.clientId, 'null override keeps value');
    System.assertEquals('client-secret', settings.clientSecret, 'blank override keeps value');
    System.assertEquals('refresh-token', settings.refreshToken, 'empty override keeps value');
    System.assertEquals('existing-token', settings.accessToken, 'whitespace override keeps value');
    System.assertEquals(TEST_BASE_URL, settings.baseUrl, 'null domain keeps base url');

    EgnyteController.applyCredentialOverrides(settings, ' id ', ' secret ', ' refresh ', ' https://x.egnyte.com/ ', ' token ');
    System.assertEquals('id', settings.clientId);
    System.assertEquals('secret', settings.clientSecret);
    System.assertEquals('refresh', settings.refreshToken);
    System.assertEquals('token', settings.accessToken);
    System.assertEquals('https://x.egnyte.com', settings.baseUrl);
  }

  @IsTest
  static void normalizeMappedFolderPath_supportsRelativeFoldermapPaths() {
    EgnyteController.Settings settings = testSettings();

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
    System.assertEquals(null, EgnyteController.normalizeMappedFolderPath(null, settings), 'null path');
    System.assertEquals(null, EgnyteController.normalizeMappedFolderPath('  ', settings), 'blank path');
  }

  @IsTest
  static void buildFolderResolutionError_mentionsRecordAndFoldermapApi() {
    String message = EgnyteController.buildFolderResolutionError('abc123', testSettings());
    System.assert(message.contains('abc123'), message);
    System.assert(message.contains('foldermap API'), message);
  }

  @IsTest
  static void getEgnyteFolderUrl_throwsWhenRecordMissingInOrgWithoutApiCredentials() {
    EgnyteController.testAccessTokenOverride = null;
    Boolean didThrow = false;
    String recordId = missingRecordId();

    try {
      EgnyteController.getEgnyteFolderUrl(
        recordId,
        null,
        null,
        null,
        TEST_DOMAIN,
        null
      );
    } catch (EgnyteController.EgnyteControllerException expected) {
      didThrow = true;
      System.assert(
        expected.getMessage().contains('foldermap API'),
        expected.getMessage()
      );
      System.assert(
        expected.getMessage().contains(recordId),
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
    String url = EgnyteController.getEgnyteFolderUrl(
      missingRecordId(),
      null,
      null,
      null,
      TEST_DOMAIN,
      null
    );
    Test.stopTest();

    System.assertEquals(REDIRECT_URL, url);
  }
}