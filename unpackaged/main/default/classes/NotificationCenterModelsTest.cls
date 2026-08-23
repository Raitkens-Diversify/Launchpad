/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class NotificationCenterModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationCenterModels.DashboardResult dashboardResult = new NotificationCenterModels.DashboardResult();
    NotificationCenterModels.ChannelDeliveryStat channelDeliveryStat = new NotificationCenterModels.ChannelDeliveryStat();
    NotificationCenterModels.DashboardStats dashboardStats = new NotificationCenterModels.DashboardStats();
    NotificationCenterModels.DigestScheduleItem digestScheduleItem = new NotificationCenterModels.DigestScheduleItem();
    NotificationCenterModels.InboxItem inboxItem = new NotificationCenterModels.InboxItem();
    NotificationCenterModels.InboxPageResult inboxPageResult = new NotificationCenterModels.InboxPageResult();
    NotificationCenterModels.InboxStats inboxStats = new NotificationCenterModels.InboxStats();
    NotificationCenterModels.LogItem logItem = new NotificationCenterModels.LogItem();
    NotificationCenterModels.LogPageResult logPageResult = new NotificationCenterModels.LogPageResult();
    NotificationCenterModels.RuleInput ruleInput = new NotificationCenterModels.RuleInput();
    NotificationCenterModels.RuleItem ruleItem = new NotificationCenterModels.RuleItem();

    System.assertNotEquals(null, dashboardResult.channelDelivery);
    System.assertNotEquals(null, dashboardResult.recentEvents);
    System.assertNotEquals(null, dashboardResult.upcomingDigests);
    System.assertEquals('', channelDeliveryStat.channelKey);
    System.assertEquals(0, dashboardStats.deliveredTodayCount);
    System.assertNotEquals(null, digestScheduleItem.channelTags);
    System.assertEquals(false, inboxItem.isRead);
    System.assertNotEquals(null, inboxPageResult.items);
    System.assertEquals(0, inboxStats.totalCount);
    System.assertNotEquals(null, logItem);
    System.assertNotEquals(null, logPageResult.items);
    System.assertNotEquals(null, ruleInput.channels);
    System.assertEquals(false, ruleInput.isActive);
    System.assertNotEquals(null, ruleItem.channels);
    System.assertEquals(false, ruleItem.isActive);
  }

  @IsTest
  static void parameterizedConstructors_assignProvidedValues() {
    NotificationCenterModels.ChannelDeliveryStat channelDeliveryStat = new NotificationCenterModels.ChannelDeliveryStat(
      'in_app',
      'In App',
      5,
      50
    );
    NotificationCenterModels.DashboardStats dashboardStats = new NotificationCenterModels.DashboardStats(
      1,
      2,
      3,
      4
    );
    NotificationCenterModels.InboxStats inboxStats = new NotificationCenterModels.InboxStats(10, 4, 6);

    System.assertEquals('in_app', channelDeliveryStat.channelKey);
    System.assertEquals(1, dashboardStats.deliveredTodayCount);
    System.assertEquals(10, inboxStats.totalCount);
  }
}