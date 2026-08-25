/**
 * ArcHomeWelcomeController
 *
 * Backs the first-login welcome banner on the ARC home page. Reads and sets a
 * "seen" flag scoped to the running user only — never another user.
 *
 * Conventions:
 *  - Deliberately not Has_Seen_Welcome__c. That field already belongs to the
 *    Help Center's "Welcome to Nexus/Arc" video flow (ArcWelcomeController /
 *    NexSWelcomeController), which is a different site with a different first
 *    thing to show. Sharing the flag would mean dismissing one welcome silently
 *    dismissed the other, and a user could arrive here already "seen" without
 *    ever having opened this app.
 *  - Storage is reused, not reinvented: this is a small per-user UI flag, the
 *    same shape as the Notifications tab's preferences, so it lives on
 *    User_Preference__c through UserPreferenceRepository rather than adding a
 *    new custom field (and the FLS/profile grants a new field would need
 *    across every profile in this org).
 *  - CRUD is asserted on every entry point; sharing alone is not treated as
 *    sufficient.
 */
public with sharing class ArcHomeWelcomeController {
  @TestVisible
  private static final String APPLICATION_NAME = 'arc.home.welcome';

  @AuraEnabled(cacheable=true)
  public static Boolean getHasSeenWelcome() {
    return hasSeenWelcome();
  }

  /**
   * Same read, not cached. getHasSeenWelcome is cacheable=true, and Lightning
   * Data Service caches that client-side with no invalidation when
   * markWelcomeSeen writes — a @wire on the cacheable version can keep
   * reporting the pre-dismiss false after the flag has already flipped, which
   * is exactly the "shows more than once" failure this feature must not have.
   * The component calls this one imperatively instead, so a remount always
   * asks the server fresh.
   */
  @AuraEnabled
  public static Boolean fetchHasSeenWelcome() {
    return hasSeenWelcome();
  }

  private static Boolean hasSeenWelcome() {
    assertReadable();

    User_Preference__c preference = new UserPreferenceRepository()
      .selectByUserAndApp(UserInfo.getUserId(), APPLICATION_NAME);

    if (preference == null || String.isBlank(preference.State__c)) {
      return false;
    }

    Map<String, Object> state;
    try {
      state = (Map<String, Object>) JSON.deserializeUntyped(
        preference.State__c
      );
    } catch (Exception parseError) {
      return false;
    }

    return state.get('seen') == true;
  }

  @AuraEnabled
  public static void markWelcomeSeen() {
    assertWritable();

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

    preference.State__c = JSON.serialize(
      new Map<String, Object>{ 'seen' => true }
    );
    repository.upsertPreference(preference);
  }

  private static void assertReadable() {
    if (!Schema.sObjectType.User_Preference__c.isAccessible()) {
      throw new AuraHandledException(
        'You do not have access to your welcome state.'
      );
    }
  }

  private static void assertWritable() {
    assertReadable();
    if (
      !Schema.sObjectType.User_Preference__c.isCreateable() ||
      !Schema.sObjectType.User_Preference__c.isUpdateable()
    ) {
      throw new AuraHandledException('You cannot update your welcome state.');
    }
  }
}