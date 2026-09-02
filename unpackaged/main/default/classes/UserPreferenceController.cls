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
    System.debug(
      '[UserPreferenceController][diag] getListViewPreference ENTRY applicationName=' + applicationName +
      ' tableId=' + tableId +
      ' runningUserId=' + UserInfo.getUserId() +
      ' runningUserType=' + UserInfo.getUserType()
    );
    UserPreferenceModels.StateEntryResult result = SERVICE.getListViewPreference(
      UserInfo.getUserId(),
      applicationName,
      tableId
    );
    System.debug(
      '[UserPreferenceController][diag] getListViewPreference RESULT entryJson=' + result.entryJson
    );
    return result;
  }

  @AuraEnabled
  public static UserPreferenceModels.StateEntryResult saveListViewPreference(
    String applicationName,
    String tableId,
    String preferenceJson
  ) {
    System.debug(
      '[UserPreferenceController][diag] saveListViewPreference ENTRY applicationName=' + applicationName +
      ' tableId=' + tableId +
      ' preferenceJson=' + preferenceJson +
      ' runningUserId=' + UserInfo.getUserId() +
      ' runningUserType=' + UserInfo.getUserType()
    );
    UserPreferenceModels.StateEntryResult result = SERVICE.saveListViewPreference(
      UserInfo.getUserId(),
      applicationName,
      tableId,
      preferenceJson
    );
    System.debug(
      '[UserPreferenceController][diag] saveListViewPreference RESULT preferenceId=' + result.preferenceId
    );
    return result;
  }
}