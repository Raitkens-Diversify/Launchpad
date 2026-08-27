/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class NotificationPreferenceControllerTest {
  @IsTest
  static void getChannelOptions_returnsActiveChannels() {
    Test.startTest();
    List<NotificationChannelService.ChannelOption> options =
      NotificationPreferenceController.getChannelOptions();
    Test.stopTest();

    System.assertNotEquals(null, options);
    System.assert(options.size() > 0);
  }

  @IsTest
  static void resolvePreference_returnsGlobalPreference() {
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Test.startTest();
    NotificationPreferenceService.ResolveResult result =
      NotificationPreferenceController.resolvePreference(
        NotificationConstants.OBJECT_TYPE_CASE,
        UserInfo.getUserId(),
        null
      );
    Test.stopTest();

    System.assertEquals(true, result.isAllowed);
    System.assertEquals('ORG_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void savePreference_createsUserPreference() {
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c preference = new Notification_Rule__c(
      Object_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Channel__c = NotificationTestDataFactory.alternateChannel(),
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST,
      Is_Active__c = true,
      Priority__c = 15,
      User__c = context.recipientUser.Id
    );

    Test.startTest();
    Notification_Rule__c savedPreference = NotificationPreferenceController.savePreference(
      preference
    );
    Test.stopTest();

    System.assertNotEquals(null, savedPreference.Id);
    System.assertEquals(context.recipientUser.Id, savedPreference.User__c);
  }

  @IsTest
  static void getAndSaveUserChannelSettings_roundTrip() {
    Test.startTest();
    NotificationUserChannelService.ChannelSettings currentSettings =
      NotificationPreferenceController.getUserChannelSettings();
    NotificationUserChannelService.ChannelSettings echoedSettings =
      NotificationPreferenceController.saveUserChannelSettings(currentSettings);
    NotificationUserChannelService.ChannelSettings fallbackSettings =
      NotificationPreferenceController.saveUserChannelSettings(null);
    Test.stopTest();

    System.assertEquals(true, currentSettings.emailEnabled);
    System.assertEquals(true, echoedSettings.emailEnabled);
    System.assertEquals(true, fallbackSettings.emailEnabled);
    System.assertNotEquals(null, fallbackSettings.userEmail);
  }
}