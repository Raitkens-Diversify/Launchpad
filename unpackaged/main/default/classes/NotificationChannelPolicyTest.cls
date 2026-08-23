/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class NotificationChannelPolicyTest {
  @IsTest
  static void emailSupportsImmediateAndDigestWhileInAppIsImmediateOnly() {
    System.assertEquals(
      true,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_IMMEDIATE
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.isImmediateEnabledForChannel(
        NotificationConstants.CHANNEL_IN_APP
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
  }
}