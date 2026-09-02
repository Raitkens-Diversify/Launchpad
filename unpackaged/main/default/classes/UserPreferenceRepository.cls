/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * SOQL access for User_Preference__c records.
 */
public with sharing class UserPreferenceRepository {
  public User_Preference__c selectByUserAndApp(Id userId, String applicationName) {
    if (userId == null || String.isBlank(applicationName)) {
      return null;
    }

    List<User_Preference__c> preferences = [
      SELECT Id, User__c, Application_Name__c, State__c
      FROM User_Preference__c
      WHERE User__c = :userId AND Application_Name__c = :applicationName
      LIMIT 1
    ];

    return preferences.isEmpty() ? null : preferences[0];
  }

  /**
   * Same row, but locked for the rest of this transaction -- used only by
   * writers. All state for a given (user, applicationName) lives in one
   * row's State__c JSON blob, and a save is read-modify-write: read the
   * blob, merge in one section/entry, write the whole thing back. Two
   * concurrent saves (e.g. saving a new view's list-view preference and its
   * created-views manifest entry, fired back to back from the same client
   * action) each do that cycle independently; without a lock, whichever
   * read happened first can still write last, silently discarding
   * whatever the other one just committed. FOR UPDATE makes the second
   * transaction block until the first commits, so it always merges on top
   * of the latest data instead of a stale snapshot.
   */
  public User_Preference__c selectByUserAndAppForUpdate(Id userId, String applicationName) {
    if (userId == null || String.isBlank(applicationName)) {
      return null;
    }

    List<User_Preference__c> preferences = [
      SELECT Id, User__c, Application_Name__c, State__c
      FROM User_Preference__c
      WHERE User__c = :userId AND Application_Name__c = :applicationName
      LIMIT 1
      FOR UPDATE
    ];

    return preferences.isEmpty() ? null : preferences[0];
  }

  public User_Preference__c upsertPreference(User_Preference__c preference) {
    if (preference == null) {
      throw new AuraHandledException('Preference record is required.');
    }

    try {
      upsert preference;
    } catch (Exception e) {
      // Apex masks an unhandled exception's real message from the client as
      // a generic "Script-thrown exception" -- wrapping it in an
      // AuraHandledException carrying the real message is the only way the
      // browser console/network response ever sees what actually failed
      // (insufficient access, a validation rule, FLS, etc.) instead of that
      // generic placeholder.
      AuraHandledException wrapped = new AuraHandledException(
        'upsertPreference failed: ' + e.getTypeName() + ': ' + e.getMessage()
      );
      wrapped.setMessage(
        'upsertPreference failed: ' + e.getTypeName() + ': ' + e.getMessage()
      );
      throw wrapped;
    }

    return preference;
  }
}