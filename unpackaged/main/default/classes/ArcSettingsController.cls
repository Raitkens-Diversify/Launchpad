/**
 * Author: Claude
 *
 * Reads and writes the running user's notification choices for
 * Settings / Notifications (Figma 758:116730). The blob is a JSON map of
 * notification key to channel, stored on User_Preference__c alongside the other
 * per-user widget state.
 *
 * Conventions:
 * - The running user is the only subject. The user id is never taken from the
 *   client, so one user can never read or write another's preferences.
 * - CRUD is asserted on every entry point; sharing alone is not treated as
 *   sufficient.
 * - The blob is validated against the known channel allowlist before it is
 *   stored, so a crafted payload cannot put arbitrary text on the record.
 * - Storage is reused, not reinvented: UserPreferenceRepository already owns
 *   the query and the upsert for this object.
 */
public with sharing class ArcSettingsController {
  /** Namespaced so it cannot collide with the saved-view blobs on the object. */
  private static final String APPLICATION_NAME = 'arcSettings.notifications';

  /** The four segments the frame draws, and the only values accepted. */
  private static final Set<String> ALLOWED_CHANNELS = new Set<String>{
    'all',
    'email',
    'in-app',
    'none'
  };

  /** Guards a runaway payload; the frame draws eight rows. */
  private static final Integer MAX_PREFERENCES = 50;

  @AuraEnabled(cacheable=true)
  public static String loadNotificationPreferences() {
    assertReadable();

    User_Preference__c preference = new UserPreferenceRepository()
      .selectByUserAndApp(UserInfo.getUserId(), APPLICATION_NAME);

    return preference == null || String.isBlank(preference.State__c)
      ? '{}'
      : preference.State__c;
  }

  @AuraEnabled
  public static String saveNotificationPreferences(String state) {
    assertWritable();

    String cleaned = sanitize(state);

    UserPreferenceRepository repository = new UserPreferenceRepository();
    User_Preference__c preference = repository.selectByUserAndApp(
      UserInfo.getUserId(),
      APPLICATION_NAME
    );

    if (preference == null) {
      preference = new User_Preference__c(
        User__c = UserInfo.getUserId(),
        Application_Name__c = APPLICATION_NAME
      );
    }

    preference.State__c = cleaned;
    repository.upsertPreference(preference);

    return cleaned;
  }

  // ---- Internals ---------------------------------------------------------

  /**
   * Keeps only string-to-string entries whose channel is in the allowlist, so
   * what lands on the record is always a map this screen can read back.
   */
  private static String sanitize(String state) {
    if (String.isBlank(state)) {
      return '{}';
    }

    Map<String, Object> parsed;
    try {
      parsed = (Map<String, Object>) JSON.deserializeUntyped(state);
    } catch (Exception parseError) {
      throw new AuraHandledException(
        'Notification preferences must be a JSON object.'
      );
    }

    if (parsed.size() > MAX_PREFERENCES) {
      throw new AuraHandledException(
        'Too many notification preferences: ' + parsed.size() + '.'
      );
    }

    Map<String, String> cleaned = new Map<String, String>();
    for (String key : parsed.keySet()) {
      Object value = parsed.get(key);
      if (!(value instanceof String)) {
        continue;
      }
      String channel = ((String) value).toLowerCase();
      if (ALLOWED_CHANNELS.contains(channel)) {
        cleaned.put(key, channel);
      }
    }

    return JSON.serialize(cleaned);
  }

  private static void assertReadable() {
    if (!Schema.sObjectType.User_Preference__c.isAccessible()) {
      throw new AuraHandledException(
        'You do not have access to notification preferences.'
      );
    }
  }

  private static void assertWritable() {
    assertReadable();
    if (
      !Schema.sObjectType.User_Preference__c.isCreateable() ||
      !Schema.sObjectType.User_Preference__c.isUpdateable()
    ) {
      throw new AuraHandledException(
        'You cannot change notification preferences.'
      );
    }
  }
}