/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Manages scoped notification preferences and global POC seed data.
 */
public with sharing class NotificationPreferenceAdminService {
  private final NotificationPreferenceRepository preferenceRepository;

  public NotificationPreferenceAdminService() {
    this(new NotificationPreferenceRepository());
  }

  @TestVisible
  private NotificationPreferenceAdminService(
    NotificationPreferenceRepository preferenceRepository
  ) {
    this.preferenceRepository = preferenceRepository;
  }

  public static Integer seedGlobalDefaults() {
    return new NotificationPreferenceAdminService().insertMissingGlobalDefaults();
  }

  public Notification_Rule__c saveScopedPreference(
    Notification_Rule__c preference
  ) {
    return saveScopedPreference(preference, true);
  }

  public Notification_Rule__c saveScopedPreference(
    Notification_Rule__c preference,
    Boolean reuseExistingScope
  ) {
    validateScope(preference);

    if (reuseExistingScope == true && preference.Id == null) {
      List<Notification_Rule__c> existingPreferences = preferenceRepository.selectExactScope(
        preference.Object_Type__c,
        preference.User__c,
        preference.Household__c
      );

      if (!existingPreferences.isEmpty()) {
        preference.Id = existingPreferences[0].Id;
      }
    }

    return preferenceRepository.upsertPreference(preference);
  }

  public Notification_Rule__c saveSystemDefault(
    Notification_Rule__c preference
  ) {
    return saveSystemDefault(preference, true);
  }

  public Notification_Rule__c saveSystemDefault(
    Notification_Rule__c preference,
    Boolean reuseExistingScope
  ) {
    preference.User__c = null;
    preference.Household__c = null;
    preference.Is_System_Default__c = true;
    validateSystemDefault(preference);

    if (reuseExistingScope == true && preference.Id == null) {
      List<Notification_Rule__c> existingPreferences = preferenceRepository.selectExactScope(
        preference.Object_Type__c,
        null,
        null
      );

      if (!existingPreferences.isEmpty()) {
        preference.Id = existingPreferences[0].Id;
      }
    }

    return preferenceRepository.upsertPreference(preference);
  }

  public Notification_Rule__c saveUserDefault(
    String objectType,
    Id userId,
    String channel,
    String frequency,
    Decimal priority
  ) {
    return saveScopedPreference(
      buildPreference(objectType, userId, null, channel, frequency, priority)
    );
  }

  public Notification_Rule__c saveHouseholdSetting(
    String objectType,
    Id householdId,
    String channel,
    String frequency,
    Decimal priority
  ) {
    return saveScopedPreference(
      buildPreference(objectType, null, householdId, channel, frequency, priority)
    );
  }

  public Notification_Rule__c saveUserHouseholdOverride(
    String objectType,
    Id userId,
    Id householdId,
    String channel,
    String frequency,
    Decimal priority
  ) {
    return saveScopedPreference(
      buildPreference(objectType, userId, householdId, channel, frequency, priority)
    );
  }

  private Notification_Rule__c buildPreference(
    String objectType,
    Id userId,
    Id householdId,
    String channel,
    String frequency,
    Decimal priority
  ) {
    return new Notification_Rule__c(
      Object_Type__c = objectType,
      User__c = userId,
      Household__c = householdId,
      Channel__c = channel,
      Frequency__c = frequency,
      Is_Active__c = true,
      Priority__c = priority
    );
  }

  private Integer insertMissingGlobalDefaults() {
    backfillSystemDefaultFlag();

    List<Notification_Rule__c> existingPreferences = [
      SELECT Id, Object_Type__c
      FROM Notification_Rule__c
      WHERE User__c = NULL AND Household__c = NULL
    ];

    Set<String> existingObjectTypes = new Set<String>();
    for (Notification_Rule__c preference : existingPreferences) {
      existingObjectTypes.add(preference.Object_Type__c);
    }

    List<Notification_Rule__c> preferencesToInsert = new List<Notification_Rule__c>();
    for (String objectType : new List<String>{
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.OBJECT_TYPE_EVENT
    }) {
      if (existingObjectTypes.contains(objectType)) {
        continue;
      }

      preferencesToInsert.add(buildSystemDefaultRule(objectType));
    }

    if (preferencesToInsert.isEmpty()) {
      return 0;
    }

    insert preferencesToInsert;
    return preferencesToInsert.size();
  }

  private static Notification_Rule__c buildSystemDefaultRule(String objectType) {
    return new Notification_Rule__c(
      Object_Type__c = objectType,
      Channel__c = buildSystemDefaultChannels(),
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Is_Active__c = true,
      Is_System_Default__c = true,
      Priority__c = 0
    );
  }

  private static String buildSystemDefaultChannels() {
    return NotificationConstants.CHANNEL_EMAIL +
      ';' +
      NotificationConstants.CHANNEL_IN_APP;
  }

  private void backfillSystemDefaultFlag() {
    List<Notification_Rule__c> orgRules = [
      SELECT Id, Is_System_Default__c
      FROM Notification_Rule__c
      WHERE
        User__c = NULL
        AND Household__c = NULL
        AND Is_System_Default__c = FALSE
    ];

    if (orgRules.isEmpty()) {
      return;
    }

    for (Notification_Rule__c orgRule : orgRules) {
      orgRule.Is_System_Default__c = true;
    }

    update orgRules;
  }

  private void validateScope(Notification_Rule__c preference) {
    if (String.isBlank(preference.Object_Type__c)) {
      throw new NotificationPreferenceException('Object Type is required.');
    }

    NotificationPreferenceService.PreferenceScope scope = NotificationPreferenceService.determineScope(
      preference
    );

    if (
      scope == NotificationPreferenceService.PreferenceScope.ORG_DEFAULT &&
      preference.Is_System_Default__c != true
    ) {
      throw new NotificationPreferenceException(
        'Use saveSystemDefault for system default rules. Scoped preferences require a user default, household setting, or user+household override.'
      );
    }
  }

  private void validateSystemDefault(Notification_Rule__c preference) {
    if (String.isBlank(preference.Object_Type__c)) {
      throw new NotificationPreferenceException('Object Type is required.');
    }

    if (
      preference.User__c != null ||
      preference.Household__c != null ||
      preference.Is_System_Default__c != true
    ) {
      throw new NotificationPreferenceException(
        'System default rules must have User and Household blank with System Default enabled.'
      );
    }
  }

  public class NotificationPreferenceException extends Exception {
  }
}