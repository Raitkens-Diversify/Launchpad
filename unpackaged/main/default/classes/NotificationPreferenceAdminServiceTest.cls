/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationPreferenceAdminServiceTest {
  @IsTest
  static void seedGlobalDefaultsInsertsMissingPreferences() {
    Test.startTest();
    Integer insertedCount = NotificationPreferenceAdminService.seedGlobalDefaults();
    Test.stopTest();

    System.assertEquals(3, insertedCount);

    List<Notification_Rule__c> preferences = [
      SELECT Object_Type__c, Is_System_Default__c
      FROM Notification_Rule__c
      WHERE User__c = NULL AND Household__c = NULL
    ];

    System.assertEquals(3, preferences.size());

    for (Notification_Rule__c preference : preferences) {
      System.assertEquals(true, preference.Is_System_Default__c);
    }
  }

  @IsTest
  static void seedGlobalDefaultsIsIdempotent() {
    NotificationPreferenceAdminService.seedGlobalDefaults();

    Test.startTest();
    Integer insertedCount = NotificationPreferenceAdminService.seedGlobalDefaults();
    Test.stopTest();

    System.assertEquals(0, insertedCount);
  }

  @IsTest
  static void saveScopedPreferenceCreatesUserPreference() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Rule__c preference = new Notification_Rule__c(
      Object_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Channel__c = NotificationTestDataFactory.alternateChannel(),
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST,
      Is_Active__c = true,
      Priority__c = 15,
      User__c = context.recipientUser.Id
    );

    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();
    Notification_Rule__c savedPreference = adminService.saveScopedPreference(
      preference
    );

    System.assertNotEquals(null, savedPreference.Id);
    System.assertEquals(context.recipientUser.Id, savedPreference.User__c);
  }

  @IsTest
  static void saveScopedPreferenceUpdatesExistingHouseholdPreference() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.household.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Notification_Rule__c preference = new Notification_Rule__c(
      Object_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Channel__c = NotificationTestDataFactory.alternateChannel(),
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST,
      Is_Active__c = true,
      Priority__c = 25,
      Household__c = context.household.Id
    );

    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();
    Notification_Rule__c savedPreference = adminService.saveScopedPreference(
      preference
    );

    List<Notification_Rule__c> householdPreferences = [
      SELECT Id, Channel__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :NotificationConstants.OBJECT_TYPE_TASK
        AND Household__c = :context.household.Id
        AND User__c = NULL
    ];

    System.assertEquals(1, householdPreferences.size());
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      savedPreference.Channel__c
    );
  }

  @IsTest
  static void saveScopedPreferenceRejectsGlobalScope() {
    Notification_Rule__c preference = new Notification_Rule__c(
      Object_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Channel__c = NotificationTestDataFactory.defaultChannel(),
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Is_Active__c = true
    );

    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();
    Boolean exceptionThrown = false;

    try {
      adminService.saveScopedPreference(preference);
    } catch (NotificationPreferenceAdminService.NotificationPreferenceException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void saveUserDefaultCreatesUserDefaultPreference() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();

    Notification_Rule__c savedPreference = adminService.saveUserDefault(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST,
      15
    );

    System.assertNotEquals(null, savedPreference.Id);
    System.assertEquals(context.recipientUser.Id, savedPreference.User__c);
    System.assertEquals(null, savedPreference.Household__c);
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.USER_DEFAULT,
      NotificationPreferenceService.determineScope(savedPreference)
    );
  }

  @IsTest
  static void saveHouseholdSettingCreatesHouseholdPreference() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();

    Notification_Rule__c savedPreference = adminService.saveHouseholdSetting(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.household.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST,
      20
    );

    System.assertNotEquals(null, savedPreference.Id);
    System.assertEquals(context.household.Id, savedPreference.Household__c);
    System.assertEquals(null, savedPreference.User__c);
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.HOUSEHOLD_SETTING,
      NotificationPreferenceService.determineScope(savedPreference)
    );
  }

  @IsTest
  static void saveUserHouseholdOverrideUpsertsByExactScope() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationPreferenceAdminService adminService = new NotificationPreferenceAdminService();

    Notification_Rule__c savedPreference = adminService.saveUserHouseholdOverride(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      context.household.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE,
      25
    );

    Notification_Rule__c updatedPreference = adminService.saveUserHouseholdOverride(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      context.household.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST,
      30
    );

    List<Notification_Rule__c> scopedPreferences = [
      SELECT Id, Channel__c, Frequency__c
      FROM Notification_Rule__c
      WHERE
        Object_Type__c = :NotificationConstants.OBJECT_TYPE_EVENT
        AND User__c = :context.recipientUser.Id
        AND Household__c = :context.household.Id
    ];

    System.assertEquals(1, scopedPreferences.size());
    System.assertEquals(savedPreference.Id, updatedPreference.Id);
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      updatedPreference.Channel__c
    );
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, updatedPreference.Frequency__c);
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.USER_HOUSEHOLD_OVERRIDE,
      NotificationPreferenceService.determineScope(updatedPreference)
    );
  }
}