/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Parses and persists versioned JSON preference blobs for super widgets.
 */
public with sharing class UserPreferenceService {
  private final UserPreferenceRepository preferenceRepository;

  public UserPreferenceService() {
    this(new UserPreferenceRepository());
  }

  @TestVisible
  private UserPreferenceService(UserPreferenceRepository preferenceRepository) {
    this.preferenceRepository = preferenceRepository;
  }

  public UserPreferenceModels.PreferenceResult getSavedViews(
    Id userId,
    String applicationName,
    String recordId
  ) {
    validateApplicationName(applicationName);

    User_Preference__c preference = preferenceRepository.selectByUserAndApp(
      userId,
      applicationName
    );

    if (preference == null || String.isBlank(preference.State__c)) {
      return new UserPreferenceModels.PreferenceResult(null, '[]');
    }

    Map<String, Object> stateMap = parseStateMap(preference.State__c);
    String contextKey = resolveContextKey(recordId);
    List<Object> views = extractViewsForContext(stateMap, contextKey);
    String lastSelectedViewId = extractLastSelectedViewIdForContext(
      stateMap,
      contextKey
    );

    return new UserPreferenceModels.PreferenceResult(
      preference.Id,
      JSON.serialize(views),
      lastSelectedViewId
    );
  }

  public UserPreferenceModels.PreferenceResult saveSavedViews(
    Id userId,
    String applicationName,
    String recordId,
    String viewsJson,
    String lastSelectedViewId
  ) {
    validateApplicationName(applicationName);
    validateViewsJson(viewsJson);

    String contextKey = resolveContextKey(recordId);
    User_Preference__c preference = preferenceRepository.selectByUserAndApp(
      userId,
      applicationName
    );
    Map<String, Object> stateMap = preference == null || String.isBlank(preference.State__c)
      ? createEmptyStateMap()
      : parseStateMap(preference.State__c);

    Map<String, Object> contexts = getContextsMap(stateMap);
    Map<String, Object> contextEntry = new Map<String, Object>{
      'views' => JSON.deserializeUntyped(viewsJson)
    };

    if (String.isNotBlank(lastSelectedViewId)) {
      contextEntry.put('lastSelectedViewId', lastSelectedViewId);
    }

    contexts.put(contextKey, contextEntry);
    stateMap.put(UserPreferenceModels.CONTEXTS_SECTION_KEY, contexts);
    stateMap.put(
      UserPreferenceModels.UPDATED_AT_KEY,
      Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
    );

    String serializedState = JSON.serialize(stateMap);
    validateStateLength(serializedState);

    if (preference == null) {
      preference = new User_Preference__c(
        User__c = userId,
        Application_Name__c = applicationName
      );
    }

    preference.State__c = serializedState;
    preferenceRepository.upsertPreference(preference);

    return new UserPreferenceModels.PreferenceResult(
      preference.Id,
      viewsJson,
      String.isBlank(lastSelectedViewId) ? '' : lastSelectedViewId
    );
  }

  public UserPreferenceModels.StateEntryResult getStateEntry(
    Id userId,
    String applicationName,
    String sectionKey,
    String entryKey
  ) {
    validateApplicationName(applicationName);
    validateSectionKey(sectionKey);
    validateEntryKey(entryKey);

    User_Preference__c preference = preferenceRepository.selectByUserAndApp(
      userId,
      applicationName
    );

    if (preference == null || String.isBlank(preference.State__c)) {
      return new UserPreferenceModels.StateEntryResult(null, '{}');
    }

    Map<String, Object> stateMap = parseStateMap(preference.State__c);
    Map<String, Object> section = getSectionMap(stateMap, sectionKey);
    String normalizedEntryKey = normalizeEntryKey(entryKey);
    Object entry = section.get(normalizedEntryKey);

    return new UserPreferenceModels.StateEntryResult(
      preference.Id,
      entry == null ? '{}' : JSON.serialize(entry)
    );
  }

  public UserPreferenceModels.StateEntryResult saveStateEntry(
    Id userId,
    String applicationName,
    String sectionKey,
    String entryKey,
    String entryJson
  ) {
    return saveStateEntry(userId, applicationName, sectionKey, entryKey, entryJson, null);
  }

  public UserPreferenceModels.StateEntryResult saveStateEntry(
    Id userId,
    String applicationName,
    String sectionKey,
    String entryKey,
    String entryJson,
    String entryIdFieldName
  ) {
    validateApplicationName(applicationName);
    validateSectionKey(sectionKey);
    validateEntryKey(entryKey);
    validateEntryJson(entryJson, entryKey, entryIdFieldName);

    String normalizedEntryKey = normalizeEntryKey(entryKey);
    User_Preference__c preference = preferenceRepository.selectByUserAndApp(
      userId,
      applicationName
    );
    Map<String, Object> stateMap = preference == null || String.isBlank(preference.State__c)
      ? createEmptyStateMap()
      : parseStateMap(preference.State__c);
    Map<String, Object> section = getSectionMap(stateMap, sectionKey);
    Map<String, Object> entry = (Map<String, Object>) JSON.deserializeUntyped(entryJson);

    if (String.isNotBlank(entryIdFieldName)) {
      entry.put(entryIdFieldName, normalizedEntryKey);
    }

    section.put(normalizedEntryKey, entry);
    stateMap.put(sectionKey, section);
    stateMap.put(
      UserPreferenceModels.UPDATED_AT_KEY,
      Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
    );

    String serializedState = JSON.serialize(stateMap);
    validateStateLength(serializedState);

    if (preference == null) {
      preference = new User_Preference__c(
        User__c = userId,
        Application_Name__c = applicationName
      );
    }

    preference.State__c = serializedState;
    preferenceRepository.upsertPreference(preference);

    return new UserPreferenceModels.StateEntryResult(
      preference.Id,
      JSON.serialize(entry)
    );
  }

  public UserPreferenceModels.StateEntryResult getListViewPreference(
    Id userId,
    String applicationName,
    String tableId
  ) {
    return getStateEntry(
      userId,
      applicationName,
      UserPreferenceModels.LIST_VIEWS_SECTION_KEY,
      tableId
    );
  }

  public UserPreferenceModels.StateEntryResult saveListViewPreference(
    Id userId,
    String applicationName,
    String tableId,
    String preferenceJson
  ) {
    return saveStateEntry(
      userId,
      applicationName,
      UserPreferenceModels.LIST_VIEWS_SECTION_KEY,
      tableId,
      preferenceJson,
      'tableId'
    );
  }

  private static void validateViewsJson(String viewsJson) {
    if (String.isBlank(viewsJson)) {
      throw new AuraHandledException('Saved views payload is required.');
    }

    try {
      Object parsed = JSON.deserializeUntyped(viewsJson);

      if (!(parsed instanceof List<Object>)) {
        throw new AuraHandledException('Saved views payload must be a JSON array.');
      }
    } catch (AuraHandledException error) {
      throw error;
    } catch (Exception error) {
      throw new AuraHandledException('Saved views payload is invalid JSON.');
    }
  }

  private static void validateEntryJson(
    String entryJson,
    String entryKey,
    String entryIdFieldName
  ) {
    if (String.isBlank(entryJson)) {
      throw new AuraHandledException('State entry payload is required.');
    }

    try {
      Object parsed = JSON.deserializeUntyped(entryJson);

      if (!(parsed instanceof Map<String, Object>)) {
        throw new AuraHandledException('State entry payload must be a JSON object.');
      }

      if (String.isBlank(entryIdFieldName)) {
        return;
      }

      Map<String, Object> entry = (Map<String, Object>) parsed;
      Object payloadEntryId = entry.get(entryIdFieldName);

      if (
        payloadEntryId != null &&
        normalizeEntryKey(String.valueOf(payloadEntryId)) != normalizeEntryKey(entryKey)
      ) {
        throw new AuraHandledException(
          'State entry ' + entryIdFieldName + ' must match the target entry key.'
        );
      }
    } catch (AuraHandledException error) {
      throw error;
    } catch (Exception error) {
      throw new AuraHandledException('State entry payload is invalid JSON.');
    }
  }

  private static void validateSectionKey(String sectionKey) {
    if (String.isBlank(sectionKey)) {
      throw new AuraHandledException('State section key is required.');
    }
  }

  private static void validateEntryKey(String entryKey) {
    if (String.isBlank(entryKey)) {
      throw new AuraHandledException('State entry key is required.');
    }
  }

  private static String normalizeEntryKey(String entryKey) {
    String normalizedEntryKey = entryKey.trim();

    while (normalizedEntryKey.endsWith('/')) {
      normalizedEntryKey = normalizedEntryKey.substring(
        0,
        normalizedEntryKey.length() - 1
      );
    }

    return normalizedEntryKey;
  }

  private static Map<String, Object> getSectionMap(
    Map<String, Object> stateMap,
    String sectionKey
  ) {
    Object sectionValue = stateMap.get(sectionKey);

    if (sectionValue instanceof Map<String, Object>) {
      return (Map<String, Object>) sectionValue;
    }

    Map<String, Object> section = new Map<String, Object>();
    stateMap.put(sectionKey, section);
    return section;
  }

  private static void validateApplicationName(String applicationName) {
    if (String.isBlank(applicationName)) {
      throw new AuraHandledException('Application name is required.');
    }
  }

  private static void validateStateLength(String serializedState) {
    if (
      serializedState != null &&
      serializedState.length() > UserPreferenceModels.MAX_STATE_LENGTH
    ) {
      throw new AuraHandledException(
        'Preference state exceeds the maximum allowed size. Remove older saved views and try again.'
      );
    }
  }

  private static String resolveContextKey(String recordId) {
    return String.isBlank(recordId)
      ? UserPreferenceModels.GLOBAL_CONTEXT_KEY
      : recordId;
  }

  private static Map<String, Object> createEmptyStateMap() {
    return new Map<String, Object>{
      UserPreferenceModels.VERSION_KEY => UserPreferenceModels.STATE_VERSION,
      UserPreferenceModels.UPDATED_AT_KEY => Datetime.now()
        .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
      UserPreferenceModels.CONTEXTS_SECTION_KEY => new Map<String, Object>()
    };
  }

  private static Map<String, Object> parseStateMap(String stateJson) {
    try {
      Map<String, Object> stateMap = (Map<String, Object>) JSON.deserializeUntyped(
        stateJson
      );

      if (!stateMap.containsKey(UserPreferenceModels.CONTEXTS_SECTION_KEY)) {
        stateMap.put(
          UserPreferenceModels.CONTEXTS_SECTION_KEY,
          new Map<String, Object>()
        );
      }

      if (!stateMap.containsKey(UserPreferenceModels.VERSION_KEY)) {
        stateMap.put(UserPreferenceModels.VERSION_KEY, UserPreferenceModels.STATE_VERSION);
      }

      return stateMap;
    } catch (Exception error) {
      return createEmptyStateMap();
    }
  }

  private static Map<String, Object> getContextsMap(Map<String, Object> stateMap) {
    return getSectionMap(stateMap, UserPreferenceModels.CONTEXTS_SECTION_KEY);
  }

  private static List<Object> extractViewsForContext(
    Map<String, Object> stateMap,
    String contextKey
  ) {
    Map<String, Object> contexts = getContextsMap(stateMap);
    Object contextValue = contexts.get(contextKey);

    if (!(contextValue instanceof Map<String, Object>)) {
      return new List<Object>();
    }

    Map<String, Object> contextEntry = (Map<String, Object>) contextValue;
    Object viewsValue = contextEntry.get('views');

    if (!(viewsValue instanceof List<Object>)) {
      return new List<Object>();
    }

    return (List<Object>) viewsValue;
  }

  private static String extractLastSelectedViewIdForContext(
    Map<String, Object> stateMap,
    String contextKey
  ) {
    Map<String, Object> contexts = getContextsMap(stateMap);
    Object contextValue = contexts.get(contextKey);

    if (!(contextValue instanceof Map<String, Object>)) {
      return '';
    }

    Map<String, Object> contextEntry = (Map<String, Object>) contextValue;
    Object lastSelectedViewIdValue = contextEntry.get('lastSelectedViewId');

    return lastSelectedViewIdValue instanceof String
      ? (String) lastSelectedViewIdValue
      : '';
  }
}