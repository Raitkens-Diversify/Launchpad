/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationChannelServiceTest {
  @IsTest
  static void getChannelOptionsReturnsActivePicklistValues() {
    List<NotificationChannelService.ChannelOption> options = NotificationChannelService.getChannelOptions();

    System.assert(!options.isEmpty(), 'Expected at least one channel option.');

    for (NotificationChannelService.ChannelOption option : options) {
      System.assertNotEquals(null, option.label);
      System.assertNotEquals(null, option.value);
    }
  }

  @IsTest
  static void getChannelOptionsUsesCanonicalOrder() {
    List<NotificationChannelService.ChannelOption> options = NotificationChannelService.getChannelOptions();
    List<String> optionValues = new List<String>();

    for (NotificationChannelService.ChannelOption option : options) {
      optionValues.add(option.value);
    }

    System.assertEquals(
      NotificationChannelUtils.sortChannels(optionValues),
      optionValues
    );
  }

  @IsTest
  static void getDefaultChannelApiNameReturnsPicklistDefault() {
    String defaultChannel = NotificationChannelService.getDefaultChannelApiName();
    Set<String> activeChannels = NotificationChannelService.getActiveChannelApiNames();

    System.assertNotEquals(null, defaultChannel);
    System.assert(activeChannels.contains(defaultChannel));

    Boolean hasDefaultOption = false;
    for (NotificationChannelService.ChannelOption option : NotificationChannelService.getChannelOptions()) {
      if (option.isDefault) {
        hasDefaultOption = true;
        System.assertEquals(option.value, defaultChannel);
      }
    }

    System.assertEquals(true, hasDefaultOption);
  }

  @IsTest
  static void getActiveChannelApiNamesMatchesOptions() {
    Set<String> activeChannels = NotificationChannelService.getActiveChannelApiNames();
    List<NotificationChannelService.ChannelOption> options = NotificationChannelService.getChannelOptions();

    System.assertEquals(options.size(), activeChannels.size());

    for (NotificationChannelService.ChannelOption option : options) {
      System.assert(activeChannels.contains(option.value));
    }
  }
}