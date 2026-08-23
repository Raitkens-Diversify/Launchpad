/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Resolves Egnyte folder paths for Salesforce records and returns an iframe URL.
 *
 * When an OAuth access or refresh token is configured, folder paths are resolved
 * exclusively through Egnyte's /pubapi/v1/sfdc/foldermap/{recordId} API. That
 * lookup uses the Salesforce record Id only and does not require the record to
 * exist in the current org.
 *
 * Without API credentials, a local Salesforce Name-based path heuristic is used
 * and only works for records that exist in the current org.
 */
public with sharing class EgnyteController {
  private static final String NAVIGATE_PATH = '/pubapi/v2/navigate';
  private static final String FOLDER_MAP_PATH = '/pubapi/v1/sfdc/foldermap/';
  private static final String TOKEN_PATH = '/puboauth/token';
  private static final String HARDCODED_DOMAIN = 'launchpad.egnyte.com';
  private static final String HARDCODED_CLIENT_ID = 'aDVGkFbtQkPDUkZkLN8Q2IYgLNZgD5DlCEtsozDXwV5BN3mg';
  private static final String HARDCODED_CLIENT_SECRET = '3uZq6xF56XphkZbA6fX5Kp4mIAz64JQAewkhuZcT1NrepCkwGzPcNk7tExsyfkI5';
  private static final String HARDCODED_DEFAULT_FOLDER_PATH = '/Shared/Salesforce.com';
  private static final String HARDCODED_REFRESH_TOKEN = '';
  private static final Set<String> PLACEHOLDER_TOKENS = new Set<String>{
    '',
    'REPLACE_WITH_EGNYTE_ACCESS_TOKEN',
    'REPLACE_WITH_EGNYTE_REFRESH_TOKEN'
  };

  @TestVisible
  private static String testAccessTokenOverride;

  @TestVisible
  private static Settings buildTestSettings(
    String baseUrl,
    String clientId,
    String clientSecret,
    String refreshToken
  ) {
    Settings settings = new Settings();
    settings.baseUrl = baseUrl;
    settings.clientId = clientId;
    settings.clientSecret = clientSecret;
    settings.refreshToken = refreshToken;
    settings.defaultFolderPath = '/Shared/Salesforce.com';
    return settings;
  }

  public class EgnyteControllerException extends Exception {
  }

  /**
   * @param recordId Salesforce record Id for folder resolution; blank uses default path.
   * @param clientId Optional OAuth client id override (e.g. from LWC test config).
   * @param clientSecret Optional OAuth client secret override.
   * @param refreshToken Optional OAuth refresh token override.
   * @param domain Optional Egnyte domain override.
   * @param accessToken Optional Egnyte access token override (Egnyte.salesforce scope).
   * @return Egnyte URL for iframe src (direct deep link or Navigate API redirect).
   */
  @AuraEnabled
  public static String getEgnyteFolderUrl(
    String recordId,
    String clientId,
    String clientSecret,
    String refreshToken,
    String domain,
    String accessToken
  ) {
    Settings settings = loadSettings();
    applyCredentialOverrides(
      settings,
      clientId,
      clientSecret,
      refreshToken,
      domain,
      accessToken
    );
    String folderPath = resolveFolderPath(recordId, settings);

    if (hasApiCredentials(settings)) {
      return requestNavigateUrl(folderPath, settings);
    }

    return buildDirectEmbedUrl(settings.baseUrl, folderPath);
  }

  @TestVisible
  private static void applyCredentialOverrides(
    Settings settings,
    String clientId,
    String clientSecret,
    String refreshToken,
    String domain,
    String accessToken
  ) {
    if (String.isNotBlank(clientId)) {
      settings.clientId = clientId.trim();
    }

    if (String.isNotBlank(clientSecret)) {
      settings.clientSecret = clientSecret.trim();
    }

    if (String.isNotBlank(refreshToken)) {
      settings.refreshToken = normalizeToken(refreshToken);
    }

    if (String.isNotBlank(accessToken)) {
      settings.accessToken = normalizeToken(accessToken);
    }

    if (String.isNotBlank(domain)) {
      settings.baseUrl = buildBaseUrl(domain);
    }
  }

  public class Settings {
    public String baseUrl;
    public String accessToken;
    public String clientId;
    public String clientSecret;
    public String refreshToken;
    public String defaultFolderPath;
  }

  private class FolderMapResult {
    public String path;
    public Integer statusCode;
    public String responseBody;
  }

  @TestVisible
  private static Settings loadSettings() {
    Settings settings = new Settings();
    settings.baseUrl = buildBaseUrl(HARDCODED_DOMAIN);
    settings.clientId = HARDCODED_CLIENT_ID;
    settings.clientSecret = HARDCODED_CLIENT_SECRET;
    settings.accessToken = '';
    settings.refreshToken = '';
    settings.defaultFolderPath = HARDCODED_DEFAULT_FOLDER_PATH;
    if (isConfiguredToken(HARDCODED_REFRESH_TOKEN)) {
      settings.refreshToken = HARDCODED_REFRESH_TOKEN.trim();
    }
    applyCustomMetadataSettings(settings);
    return settings;
  }

  @TestVisible
  private static void applyCustomMetadataSettings(Settings settings) {
    if (!Schema.getGlobalDescribe().containsKey('Egnyte_Settings__mdt')) {
      return;
    }

    List<Egnyte_Settings__mdt> configuredSettings = [
      SELECT
        Domain__c,
        Client_Id__c,
        Client_Secret__c,
        Access_Token__c,
        Refresh_Token__c,
        Default_Folder_Path__c
      FROM Egnyte_Settings__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];

    if (configuredSettings.isEmpty()) {
      return;
    }

    Egnyte_Settings__mdt configuredSetting = configuredSettings[0];

    if (String.isNotBlank(configuredSetting.Domain__c)) {
      settings.baseUrl = buildBaseUrl(configuredSetting.Domain__c);
    }

    if (String.isNotBlank(configuredSetting.Client_Id__c)) {
      settings.clientId = configuredSetting.Client_Id__c.trim();
    }

    if (String.isNotBlank(configuredSetting.Client_Secret__c)) {
      settings.clientSecret = configuredSetting.Client_Secret__c.trim();
    }

    if (isConfiguredToken(configuredSetting.Access_Token__c)) {
      settings.accessToken = configuredSetting.Access_Token__c.trim();
    }

    if (isConfiguredToken(configuredSetting.Refresh_Token__c)) {
      settings.refreshToken = configuredSetting.Refresh_Token__c.trim();
    }

    if (String.isNotBlank(configuredSetting.Default_Folder_Path__c)) {
      settings.defaultFolderPath = configuredSetting.Default_Folder_Path__c.trim();
    }
  }

  public static String buildBaseUrl(String domain) {
    String host = String.isBlank(domain) ? 'launchpad.egnyte.com' : domain.trim();
    host = host.replace('https://', '').replace('http://', '');
    while (host.endsWith('/')) {
      host = host.substring(0, host.length() - 1);
    }
    return 'https://' + host;
  }

  @TestVisible
  private static String normalizeToken(String token) {
    return token == null ? '' : token.trim();
  }

  @TestVisible
  private static Boolean isConfiguredToken(String token) {
    return String.isNotBlank(token) && !PLACEHOLDER_TOKENS.contains(token);
  }

  @TestVisible
  private static Boolean hasApiCredentials(Settings settings) {
    if (Test.isRunningTest() && isConfiguredToken(testAccessTokenOverride)) {
      return true;
    }

    return isConfiguredToken(settings.accessToken) ||
      (
        String.isNotBlank(settings.clientId) &&
        String.isNotBlank(settings.clientSecret) &&
        isConfiguredToken(settings.refreshToken)
      );
  }

  @TestVisible
  private static String resolveAccessToken(Settings settings) {
    if (Test.isRunningTest() && isConfiguredToken(testAccessTokenOverride)) {
      return testAccessTokenOverride;
    }

    if (isConfiguredToken(settings.accessToken)) {
      return settings.accessToken;
    }

    if (
      String.isNotBlank(settings.clientId) &&
      String.isNotBlank(settings.clientSecret) &&
      isConfiguredToken(settings.refreshToken)
    ) {
      return refreshAccessToken(settings);
    }

    throw new EgnyteControllerException(
      'Egnyte access token is not configured. In Setup, open Custom Metadata Types → Egnyte Settings → Manage Records → Default, then add a valid Access Token or OAuth Client Id, Client Secret, and Refresh Token with Egnyte.launchwebsession scope.'
    );
  }

  @TestVisible
  private static String refreshAccessToken(Settings settings) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(settings.baseUrl + TOKEN_PATH);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

    List<String> bodyParts = new List<String>{
      'grant_type=' + EncodingUtil.urlEncode('refresh_token', 'UTF-8'),
      'client_id=' + EncodingUtil.urlEncode(settings.clientId, 'UTF-8'),
      'client_secret=' + EncodingUtil.urlEncode(settings.clientSecret, 'UTF-8'),
      'refresh_token=' + EncodingUtil.urlEncode(settings.refreshToken, 'UTF-8')
    };
    request.setBody(String.join(bodyParts, '&'));

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200) {
      throw new EgnyteControllerException(
        'Egnyte token refresh failed. Status: ' +
          response.getStatusCode() +
          ' Body: ' +
          response.getBody()
      );
    }

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    Object accessToken = body.get('access_token');

    if (!(accessToken instanceof String) || String.isBlank((String) accessToken)) {
      throw new EgnyteControllerException(
        'Egnyte token refresh did not return an access_token.'
      );
    }

    return (String) accessToken;
  }

  @TestVisible
  private static HttpRequest prepareRequest(
    Settings settings,
    String endpoint,
    String method
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(endpoint);
    request.setMethod(method);
    request.setHeader(
      'Authorization',
      'Bearer ' + resolveAccessToken(settings)
    );
    return request;
  }

  @TestVisible
  private static String buildDirectEmbedUrl(String baseUrl, String folderPath) {
    String normalizedPath = normalizeFolderPath(folderPath);
    String pathWithoutLeadingSlash = normalizedPath.startsWith('/')
      ? normalizedPath.substring(1)
      : normalizedPath;

    return baseUrl + '/navigate/path/' + encodePathForNavigateUrl(pathWithoutLeadingSlash);
  }

  @TestVisible
  private static String encodePathForNavigateUrl(String pathWithoutLeadingSlash) {
    if (String.isBlank(pathWithoutLeadingSlash)) {
      return '';
    }

    List<String> encodedSegments = new List<String>();
    for (String segment : pathWithoutLeadingSlash.split('/')) {
      if (String.isBlank(segment)) {
        continue;
      }

      encodedSegments.add(
        EncodingUtil.urlEncode(segment.trim(), 'UTF-8').replace('+', '%20')
      );
    }

    return String.join(encodedSegments, '/');
  }

  @TestVisible
  private static String normalizeFolderPath(String folderPath) {
    if (String.isBlank(folderPath)) {
      return '/Shared/Salesforce.com';
    }

    String normalizedPath = folderPath.trim();
    if (!normalizedPath.startsWith('/')) {
      normalizedPath = '/' + normalizedPath;
    }

    return normalizedPath;
  }

  @TestVisible
  private static String resolveFolderPathFromRecord(
    String recordId,
    Settings settings
  ) {
    Id recordIdentifier;
    try {
      recordIdentifier = Id.valueOf(recordId.trim());
    } catch (Exception e) {
      return settings.defaultFolderPath;
    }

    Schema.DescribeSObjectResult objectDescribe = recordIdentifier.getSObjectType()
      .getDescribe();
    String objectApiName = objectDescribe.getName();
    String objectLabel = objectDescribe.getLabel();
    SyncObjectConfig syncConfig = loadSyncObjectConfig(objectDescribe);

    String query = buildRecordQuery(objectDescribe, syncConfig);
    if (String.isBlank(query)) {
      return settings.defaultFolderPath;
    }

    List<SObject> records = Database.queryWithBinds(
      query,
      new Map<String, Object>{ 'recordIdentifier' => recordIdentifier },
      AccessLevel.SYSTEM_MODE
    );

    if (records.isEmpty()) {
      return null;
    }

    SObject record = records[0];
    String recordName = resolveRecordFolderName(record, objectDescribe, syncConfig);
    String nameHashSource = resolveNameHashSource(record, objectDescribe, syncConfig);
    String nameHash = buildTwoLetterNameHash(nameHashSource);
    String pathPrefix = buildPathPrefix(record, objectDescribe, syncConfig, settings);

    if (String.isBlank(recordName)) {
      return pathPrefix + '/' + objectLabel + '/' + nameHash;
    }

    return pathPrefix + '/' + objectLabel + '/' + nameHash + '/' + recordName;
  }

  private class SyncObjectConfig {
    public String customFolderPath;
    public Boolean useDefaultFolderPath;
    public String customFolderNameField;
    public Boolean useDefaultFolderName;
    public String parentLookupField;
    public String parentObjectApiName;
    public String objectNameField;
  }

  @TestVisible
  private static SyncObjectConfig loadSyncObjectConfig(
    Schema.DescribeSObjectResult objectDescribe
  ) {
    if (!Schema.getGlobalDescribe().containsKey('efs__EgnyteSyncObject__c')) {
      return null;
    }

    String objectApiName = objectDescribe.getName();
    String objectLabel = objectDescribe.getLabel();
    String syncQuery =
      'SELECT efs__CustomFolderPath__c, efs__IsDefaultFolderPath__c, ' +
      'efs__CustomFolderNameField__c, efs__IsDefaultFolderName__c, ' +
      'efs__ParentObjectFieldAPIName__c, efs__ParentObject__c, efs__ObjectNameField__c ' +
      'FROM efs__EgnyteSyncObject__c ' +
      'WHERE efs__Active__c = TRUE AND (efs__ObjectLabel__c = :objectApiName OR efs__ObjectLabel__c = :objectLabel) ' +
      'LIMIT 1';

    List<SObject> configs = Database.queryWithBinds(
      syncQuery,
      new Map<String, Object>{
        'objectApiName' => objectApiName,
        'objectLabel' => objectLabel
      },
      AccessLevel.SYSTEM_MODE
    );

    if (configs.isEmpty()) {
      return null;
    }

    SObject config = configs[0];
    SyncObjectConfig syncObjectConfig = new SyncObjectConfig();
    syncObjectConfig.customFolderPath = (String) config.get('efs__CustomFolderPath__c');
    syncObjectConfig.useDefaultFolderPath = (Boolean) config.get(
      'efs__IsDefaultFolderPath__c'
    );
    syncObjectConfig.customFolderNameField = (String) config.get(
      'efs__CustomFolderNameField__c'
    );
    syncObjectConfig.useDefaultFolderName = (Boolean) config.get(
      'efs__IsDefaultFolderName__c'
    );
    syncObjectConfig.parentLookupField = (String) config.get(
      'efs__ParentObjectFieldAPIName__c'
    );
    syncObjectConfig.parentObjectApiName = (String) config.get('efs__ParentObject__c');
    syncObjectConfig.objectNameField = (String) config.get('efs__ObjectNameField__c');
    return syncObjectConfig;
  }

  @TestVisible
  private static String buildRecordQuery(
    Schema.DescribeSObjectResult objectDescribe,
    SyncObjectConfig syncConfig
  ) {
    Set<String> fieldNames = new Set<String>();
    Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

    addQueryableField(fieldNames, fieldMap, 'Name');
    addQueryableField(fieldNames, fieldMap, 'Id');

    if (syncConfig != null) {
      addQueryableField(fieldNames, fieldMap, syncConfig.objectNameField);
      addQueryableField(fieldNames, fieldMap, syncConfig.customFolderNameField);
      addQueryableField(fieldNames, fieldMap, syncConfig.parentLookupField);
    }

    if (fieldNames.isEmpty()) {
      return null;
    }

    return 'SELECT ' +
      String.join(new List<String>(fieldNames), ', ') +
      ' FROM ' +
      objectDescribe.getName() +
      ' WHERE Id = :recordIdentifier LIMIT 1';
  }

  private static void addQueryableField(
    Set<String> fieldNames,
    Map<String, Schema.SObjectField> fieldMap,
    String fieldApiName
  ) {
    if (String.isBlank(fieldApiName) || !fieldMap.containsKey(fieldApiName)) {
      return;
    }

    fieldNames.add(fieldApiName);
  }

  @TestVisible
  private static String buildPathPrefix(
    SObject record,
    Schema.DescribeSObjectResult objectDescribe,
    SyncObjectConfig syncConfig,
    Settings settings
  ) {
    if (
      syncConfig != null &&
      syncConfig.useDefaultFolderPath == false &&
      String.isNotBlank(syncConfig.customFolderPath)
    ) {
      return normalizeFolderPath('/Shared/' + syncConfig.customFolderPath.trim());
    }

    if (
      syncConfig != null &&
      String.isNotBlank(syncConfig.parentLookupField) &&
      String.isNotBlank(syncConfig.parentObjectApiName)
    ) {
      Id parentRecordId = (Id) record.get(syncConfig.parentLookupField);
      if (parentRecordId != null) {
        String parentPath = resolveFolderPathFromRecord(
          String.valueOf(parentRecordId),
          settings
        );
        return parentPath;
      }
    }

    return normalizeFolderPath(settings.defaultFolderPath);
  }

  @TestVisible
  private static String resolveRecordFolderName(
    SObject record,
    Schema.DescribeSObjectResult objectDescribe,
    SyncObjectConfig syncConfig
  ) {
    if (
      syncConfig != null &&
      syncConfig.useDefaultFolderName == false &&
      String.isNotBlank(syncConfig.customFolderNameField) &&
      objectDescribe.fields.getMap().containsKey(syncConfig.customFolderNameField)
    ) {
      Object customName = record.get(syncConfig.customFolderNameField);
      if (customName != null && String.isNotBlank(String.valueOf(customName))) {
        return String.valueOf(customName).trim();
      }
    }

    if (objectDescribe.fields.getMap().containsKey('Name')) {
      return (String) record.get('Name');
    }

    return null;
  }

  @TestVisible
  private static String resolveNameHashSource(
    SObject record,
    Schema.DescribeSObjectResult objectDescribe,
    SyncObjectConfig syncConfig
  ) {
    if (
      syncConfig != null &&
      String.isNotBlank(syncConfig.objectNameField) &&
      objectDescribe.fields.getMap().containsKey(syncConfig.objectNameField)
    ) {
      Object configuredName = record.get(syncConfig.objectNameField);
      if (configuredName != null && String.isNotBlank(String.valueOf(configuredName))) {
        return String.valueOf(configuredName);
      }
    }

    return resolveRecordFolderName(record, objectDescribe, syncConfig);
  }

  @TestVisible
  private static String buildTwoLetterNameHash(String name) {
    if (String.isBlank(name)) {
      return 'XX';
    }

    String trimmedName = name.trim();
    return trimmedName.length() >= 2
      ? trimmedName.substring(0, 2)
      : trimmedName;
  }

  @TestVisible
  private static String resolveFolderPath(String recordId, Settings settings) {
    if (String.isBlank(recordId)) {
      return settings.defaultFolderPath;
    }

    if (hasFoldermapCredentials(settings)) {
      return resolveFolderPathFromFoldermap(recordId, settings);
    }

    String localPath = resolveFolderPathFromRecord(recordId, settings);
    if (String.isNotBlank(localPath)) {
      return localPath;
    }

    throw new EgnyteControllerException(buildFolderResolutionError(recordId, settings));
  }

  @TestVisible
  private static String resolveFolderPathFromFoldermap(
    String recordId,
    Settings settings
  ) {
    FolderMapResult mapping = requestFolderMap(recordId, settings);

    if (String.isNotBlank(mapping.path)) {
      return mapping.path;
    }

    if (mapping.statusCode == 404) {
      throw new EgnyteControllerException(
        'No Egnyte folder mapping exists for Salesforce record ' +
          recordId +
          '.'
      );
    }

    throw new EgnyteControllerException(
      'Egnyte foldermap API failed for record ' +
        recordId +
        '. Status: ' +
        mapping.statusCode +
        ' Body: ' +
        mapping.responseBody
    );
  }

  @TestVisible
  private static Boolean hasFoldermapCredentials(Settings settings) {
    return hasApiCredentials(settings);
  }

  @TestVisible
  private static String buildFolderResolutionError(String recordId, Settings settings) {
    return 'Could not resolve an Egnyte folder for record ' +
      recordId +
      '. Add an Egnyte access token or refresh token with Egnyte.salesforce scope to resolve any Salesforce record Id through the Egnyte foldermap API. Without API credentials, only records that exist in this org can be resolved.';
  }

  @TestVisible
  private static String normalizeMappedFolderPath(String mappedPath, Settings settings) {
    if (String.isBlank(mappedPath)) {
      return null;
    }

    String normalizedPath = mappedPath.trim();
    if (normalizedPath.startsWith('/')) {
      return normalizeFolderPath(normalizedPath);
    }

    String basePath = normalizeFolderPath(settings.defaultFolderPath);
    String relativePath = normalizedPath.replaceAll('^/+', '');
    return basePath + '/' + relativePath;
  }

  @TestVisible
  private static FolderMapResult requestFolderMap(String recordId, Settings settings) {
    FolderMapResult result = new FolderMapResult();

    HttpRequest request = prepareRequest(
      settings,
      settings.baseUrl + FOLDER_MAP_PATH + recordId,
      'GET'
    );

    HttpResponse response = new Http().send(request);
    result.statusCode = response.getStatusCode();
    result.responseBody = response.getBody();

    if (response.getStatusCode() != 200) {
      return result;
    }

    String parsedPath = parseFolderPath(response.getBody(), null);
    result.path = normalizeMappedFolderPath(parsedPath, settings);
    return result;
  }

  @TestVisible
  private static String requestFolderMapPath(String recordId, Settings settings) {
    FolderMapResult result = requestFolderMap(recordId, settings);
    return result.path;
  }

  @TestVisible
  private static String parseFolderPath(
    String responseBody,
    String defaultFolderPath
  ) {
    if (String.isBlank(responseBody)) {
      return defaultFolderPath;
    }

    Object parsed = JSON.deserializeUntyped(responseBody.trim());

    if (parsed instanceof String) {
      String path = ((String) parsed).trim();
      return String.isBlank(path) ? defaultFolderPath : path;
    }

    if (!(parsed instanceof Map<String, Object>)) {
      return defaultFolderPath;
    }

    Map<String, Object> payload = (Map<String, Object>) parsed;
    List<String> candidateKeys = new List<String>{
      'path',
      'folderPath',
      'folder_path',
      'folder'
    };

    for (String key : candidateKeys) {
      if (!payload.containsKey(key)) {
        continue;
      }

      Object value = payload.get(key);
      if (value instanceof String) {
        String path = ((String) value).trim();
        if (String.isNotBlank(path)) {
          return path;
        }
      }
    }

    return defaultFolderPath;
  }

  @TestVisible
  private static String requestNavigateUrl(String folderPath, Settings settings) {
    String path = String.isBlank(folderPath)
      ? settings.defaultFolderPath
      : folderPath;

    HttpRequest request = prepareRequest(
      settings,
      settings.baseUrl + NAVIGATE_PATH,
      'POST'
    );
    request.setHeader('Content-Type', 'application/json');

    Map<String, Object> payload = new Map<String, Object>{
      'embedded' => true,
      'path' => path
    };
    request.setBody(JSON.serialize(payload));

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200) {
      throw new EgnyteControllerException(
        'Egnyte Navigate API failed. Status: ' +
          response.getStatusCode() +
          ' Body: ' +
          response.getBody()
      );
    }

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    Object redirect = body.get('redirect');

    if (!(redirect instanceof String) || String.isBlank((String) redirect)) {
      throw new EgnyteControllerException(
        'Egnyte Navigate API did not return a redirect URL.'
      );
    }

    return (String) redirect;
  }
}