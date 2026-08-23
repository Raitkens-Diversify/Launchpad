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

  public User_Preference__c upsertPreference(User_Preference__c preference) {
    if (preference == null) {
      throw new AuraHandledException('Preference record is required.');
    }

    upsert preference;
    return preference;
  }
}