/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class NotificationUserChannelServiceTest {
  @IsTest
  static void loadsActiveChannelDefaultsForCurrentUser() {
    NotificationUserChannelService service = new NotificationUserChannelService();

    Test.startTest();
    NotificationUserChannelService.ChannelSettings settings = service.getForCurrentUser();
    Test.stopTest();

    System.assertEquals(true, settings.emailEnabled);
    System.assertEquals(true, settings.emailImmediate);
    System.assertEquals(true, settings.emailDigest);
    System.assertEquals(true, settings.inAppImmediate);
    System.assertEquals(true, settings.inAppDigest);
    System.assertNotEquals(null, settings.userEmail);
  }

  @IsTest
  static void emailAndInAppChannelsAreAlwaysEnabledForDelivery() {
    NotificationUserChannelService.ChannelSettings settings = new NotificationUserChannelService.ChannelSettings();
    settings.emailEnabled = false;
    settings.emailImmediate = false;
    settings.emailDigest = false;
    settings.inAppImmediate = false;
    settings.inAppDigest = false;

    System.assertEquals(
      true,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_IMMEDIATE
      )
    );
    System.assertEquals(
      true,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
    System.assertEquals(
      true,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_IMMEDIATE
      )
    );
    System.assertEquals(
      true,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
    System.assertEquals(
      false,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_ZOOM,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
  }
}