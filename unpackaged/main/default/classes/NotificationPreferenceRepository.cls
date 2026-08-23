/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * SOQL access for Notification_Rule__c records.
 */
public with sharing class NotificationPreferenceRepository {
  public List<Notification_Rule__c> selectActiveScopedPreferencesForRecipients(
    String objectType,
    Set<Id> recipientIds,
    Id householdId
  ) {
    if (recipientIds == null || recipientIds.isEmpty()) {
      return new List<Notification_Rule__c>();
    }

    if (householdId == null) {
      return [
        SELECT
          Id,
          Object_Type__c,
          Channel__c,
          Frequency__c,
          Digest_Cadence__c,
          Digest_Frequency_Hour__c,
          Is_Active__c,
          Is_System_Default__c,
          User__c,
          Household__c,
          Priority__c
        FROM Notification_Rule__c
        WHERE
          Object_Type__c = :objectType
          AND Is_Active__c = TRUE
          AND (User__c IN :recipientIds OR User__c = NULL)
          AND Household__c = NULL
          AND (User__c != NULL OR Household__c != NULL)
        ORDER BY Priority__c DESC
      ];
    }

    return [
      SELECT
        Id,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        User__c,
        Household__c,
        Priority__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :objectType
        AND Is_Active__c = TRUE
        AND (User__c IN :recipientIds OR User__c = NULL)
        AND (Household__c = :householdId OR Household__c = NULL)
        AND (User__c != NULL OR Household__c != NULL)
      ORDER BY Priority__c DESC
    ];
  }

  public List<Notification_Rule__c> selectActiveScopedPreferences(
    String objectType,
    Id recipientId,
    Id householdId
  ) {
    return [
      SELECT
        Id,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        User__c,
        Household__c,
        Priority__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :objectType
        AND Is_Active__c = TRUE
        AND (User__c != NULL OR Household__c != NULL)
        AND (User__c = :recipientId OR User__c = NULL)
        AND (Household__c = :householdId OR Household__c = NULL)
      ORDER BY Priority__c DESC
    ];
  }

  public List<Notification_Rule__c> selectActiveSystemDefaults(String objectType) {
    return [
      SELECT
        Id,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        User__c,
        Household__c,
        Priority__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :objectType
        AND Is_Active__c = TRUE
        AND Is_System_Default__c = TRUE
        AND User__c = NULL
        AND Household__c = NULL
      ORDER BY Priority__c DESC
    ];
  }

  public List<Notification_Rule__c> selectMatchingPreferences(
    String objectType,
    Id recipientId,
    Id householdId
  ) {
    return [
      SELECT
        Id,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        User__c,
        Household__c,
        Priority__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :objectType
        AND Is_Active__c = TRUE
        AND (User__c = :recipientId OR User__c = NULL)
        AND (Household__c = :householdId OR Household__c = NULL)
      ORDER BY Priority__c DESC
    ];
  }

  public List<Notification_Rule__c> selectExactScope(
    String objectType,
    Id userId,
    Id householdId
  ) {
    return [
      SELECT
        Id,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        User__c,
        Household__c,
        Priority__c,
        Rule_Name__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :objectType
        AND User__c = :userId
        AND Household__c = :householdId
      LIMIT 1
    ];
  }

  public Notification_Rule__c upsertPreference(
    Notification_Rule__c preference
  ) {
    upsert preference;
    return preference;
  }

  public List<Notification_Rule__c> selectUserDefaultPreferences(Id userId) {
    return [
      SELECT Id, Object_Type__c, Channel__c, Frequency__c, Is_Active__c, Priority__c
      FROM Notification_Rule__c
      WHERE User__c = :userId AND Household__c = NULL AND Is_Active__c = TRUE
      ORDER BY Object_Type__c
    ];
  }

  public List<Notification_Rule__c> selectRulesForUser(Id userId) {
    return [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE User__c = :userId
      ORDER BY Priority__c DESC, Object_Type__c ASC, CreatedDate DESC
    ];
  }

  public List<Notification_Rule__c> selectRulesForUserAndHousehold(
    Id userId,
    Id householdId
  ) {
    return [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE User__c = :userId AND Household__c = :householdId
      ORDER BY Priority__c DESC, Object_Type__c ASC, CreatedDate DESC
    ];
  }

  public List<Notification_Rule__c> selectSystemDefaultRules() {
    return [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE
        Is_System_Default__c = TRUE
        AND User__c = NULL
        AND Household__c = NULL
      ORDER BY Priority__c DESC, Object_Type__c ASC, CreatedDate DESC
    ];
  }

  public Notification_Rule__c selectSystemDefaultRule(Id ruleId) {
    List<Notification_Rule__c> rules = [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE
        Id = :ruleId
        AND Is_System_Default__c = TRUE
        AND User__c = NULL
        AND Household__c = NULL
      LIMIT 1
    ];

    return rules.isEmpty() ? null : rules[0];
  }

  public Notification_Rule__c selectUserDefaultRuleForObjectType(
    Id userId,
    String objectType
  ) {
    List<Notification_Rule__c> rules = [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE
        User__c = :userId
        AND Household__c = NULL
        AND Object_Type__c = :objectType
      LIMIT 1
    ];

    return rules.isEmpty() ? null : rules[0];
  }

  public Notification_Rule__c selectRuleById(Id ruleId) {
    List<Notification_Rule__c> rules = [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE Id = :ruleId
      LIMIT 1
    ];

    return rules.isEmpty() ? null : rules[0];
  }

  public Notification_Rule__c selectRuleForUser(Id ruleId, Id userId) {
    List<Notification_Rule__c> rules = [
      SELECT
        Id,
        Name,
        Rule_Name__c,
        Object_Type__c,
        Channel__c,
        Frequency__c,
        Digest_Cadence__c,
        Digest_Frequency_Hour__c,
        Is_Active__c,
        Is_System_Default__c,
        Priority__c,
        User__c,
        Household__c,
        Household__r.Name
      FROM Notification_Rule__c
      WHERE Id = :ruleId AND User__c = :userId
      LIMIT 1
    ];

    return rules.isEmpty() ? null : rules[0];
  }
}