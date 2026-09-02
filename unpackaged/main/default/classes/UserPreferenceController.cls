/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Aura-enabled facade for app-level user preference state.
 */
public with sharing class UserPreferenceController {
  private static final UserPreferenceService SERVICE = new UserPreferenceService();

  @AuraEnabled(cacheable=true)
  public static UserPreferenceModels.PreferenceResult getSavedViews(
    String applicationName,
    String recordId
  ) {
    return SERVICE.getSavedViews(
      UserInfo.getUserId(),
      applicationName,
      recordId
    );
  }

  @AuraEnabled
  public static UserPreferenceModels.PreferenceResult saveSavedViews(
    String applicationName,
    String recordId,
    String viewsJson,
    String lastSelectedViewId
  ) {
    return SERVICE.saveSavedViews(
      UserInfo.getUserId(),
      applicationName,
      recordId,
      viewsJson,
      lastSelectedViewId
    );
  }

  @AuraEnabled(cacheable=true)
  public static UserPreferenceModels.StateEntryResult getStateEntry(
    String applicationName,
    String sectionKey,
    String entryKey
  ) {
    return SERVICE.getStateEntry(
      UserInfo.getUserId(),
      applicationName,
      sectionKey,
      entryKey
    );
  }

  @AuraEnabled
  public static UserPreferenceModels.StateEntryResult saveStateEntry(
    String applicationName,
    String sectionKey,
    String entryKey,
    String entryJson
  ) {
    return SERVICE.saveStateEntry(
      UserInfo.getUserId(),
      applicationName,
      sectionKey,
      entryKey,
      entryJson
    );
  }

  @AuraEnabled(cacheable=true)
  public static UserPreferenceModels.StateEntryResult getListViewPreference(
    String applicationName,
    String tableId
  ) {
    return SERVICE.getListViewPreference(
      UserInfo.getUserId(),
      applicationName,
      tableId
    );
  }

  @AuraEnabled
  public static UserPreferenceModels.StateEntryResult saveListViewPreference(
    String applicationName,
    String tableId,
    String preferenceJson
  ) {
    return SERVICE.saveListViewPreference(
      UserInfo.getUserId(),
      applicationName,
      tableId,
      preferenceJson
    );
  }
}