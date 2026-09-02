/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * SOQL access for User_Preference__c records.
 */
public with sharing class UserPreferenceRepository {
  public User_Preference__c selectByUserAndApp(Id userId, String applicationName) {
    System.debug(
      '[UserPreferenceRepository][diag] selectByUserAndApp userId=' + userId +
      ' applicationName=' + applicationName +
      ' runningUser=' + UserInfo.getUserId() +
      ' runningUserType=' + UserInfo.getUserType()
    );
    if (userId == null || String.isBlank(applicationName)) {
      System.debug('[UserPreferenceRepository][diag] selectByUserAndApp: short-circuited, missing userId or applicationName');
      return null;
    }

    List<User_Preference__c> preferences = [
      SELECT Id, User__c, Application_Name__c, State__c
      FROM User_Preference__c
      WHERE User__c = :userId AND Application_Name__c = :applicationName
      LIMIT 1
    ];

    System.debug('[UserPreferenceRepository][diag] selectByUserAndApp: found ' + preferences.size() + ' row(s)');
    return preferences.isEmpty() ? null : preferences[0];
  }

  public User_Preference__c upsertPreference(User_Preference__c preference) {
    if (preference == null) {
      throw new AuraHandledException('Preference record is required.');
    }

    System.debug(
      '[UserPreferenceRepository][diag] upsertPreference: Id=' + preference.Id +
      ' User__c=' + preference.User__c +
      ' Application_Name__c=' + preference.Application_Name__c +
      ' stateLength=' + (preference.State__c == null ? 0 : preference.State__c.length()) +
      ' runningUser=' + UserInfo.getUserId() +
      ' runningUserType=' + UserInfo.getUserType()
    );

    try {
      upsert preference;
    } catch (Exception e) {
      // Apex masks an unhandled exception's real message from the client as
      // a generic "Script-thrown exception" -- wrapping it in an
      // AuraHandledException carrying the real message is the only way the
      // browser console/network response ever sees what actually failed
      // (insufficient access, a validation rule, FLS, etc.) instead of that
      // generic placeholder.
      System.debug('[UserPreferenceRepository][diag] upsertPreference FAILED: ' + e.getTypeName() + ': ' + e.getMessage());
      AuraHandledException wrapped = new AuraHandledException(
        'upsertPreference failed: ' + e.getTypeName() + ': ' + e.getMessage()
      );
      wrapped.setMessage(
        'upsertPreference failed: ' + e.getTypeName() + ': ' + e.getMessage()
      );
      throw wrapped;
    }

    System.debug('[UserPreferenceRepository][diag] upsertPreference SUCCESS: Id=' + preference.Id);
    return preference;
  }
}