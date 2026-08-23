/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationChannelUtilsTest {
  @IsTest
  static void splitChannelsParsesMultipicklistValue() {
    List<String> channels = NotificationChannelUtils.splitChannels('Email;In_App');

    System.assertEquals(2, channels.size());
    System.assertEquals(NotificationConstants.CHANNEL_EMAIL, channels[0]);
    System.assertEquals(NotificationConstants.CHANNEL_IN_APP, channels[1]);
  }

  @IsTest
  static void joinChannelsBuildsMultipicklistValue() {
    String channelsValue = NotificationChannelUtils.joinChannels(
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      }
    );

    System.assertEquals('Email;In_App', channelsValue);
  }

  @IsTest
  static void sortChannelsUsesCanonicalOrder() {
    List<String> sortedChannels = NotificationChannelUtils.sortChannels(
      new List<String>{
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.CHANNEL_EMAIL
      }
    );

    System.assertEquals(NotificationConstants.CHANNEL_IN_APP, sortedChannels[0]);
    System.assertEquals(NotificationConstants.CHANNEL_EMAIL, sortedChannels[1]);
  }
}