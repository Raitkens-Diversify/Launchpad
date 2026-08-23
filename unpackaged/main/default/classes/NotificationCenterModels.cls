/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * DTOs for notification center reads and writes.
 */
public with sharing class NotificationCenterModels {
  public class ChannelDeliveryStat {
    @AuraEnabled
    public String channelKey { get; private set; }
    @AuraEnabled
    public String label { get; private set; }
    @AuraEnabled
    public Integer count { get; private set; }
    @AuraEnabled
    public Integer percent { get; private set; }

    public ChannelDeliveryStat(
      String channelKey,
      String label,
      Integer count,
      Integer percent
    ) {
      this.channelKey = channelKey;
      this.label = label;
      this.count = count;
      this.percent = percent;
    }

    public ChannelDeliveryStat() {
      this('', '', 0, 0);
    }
  }

  public class DashboardResult {
    @AuraEnabled
    public DashboardStats stats { get; set; }
    @AuraEnabled
    public List<ChannelDeliveryStat> channelDelivery { get; set; }
    @AuraEnabled
    public List<LogItem> recentEvents { get; set; }
    @AuraEnabled
    public List<DigestScheduleItem> upcomingDigests { get; set; }

    public DashboardResult() {
      this.channelDelivery = new List<ChannelDeliveryStat>();
      this.recentEvents = new List<LogItem>();
      this.upcomingDigests = new List<DigestScheduleItem>();
    }
  }

  public class DashboardStats {
    @AuraEnabled
    public Integer deliveredTodayCount { get; private set; }
    @AuraEnabled
    public Integer suppressedTodayCount { get; private set; }
    @AuraEnabled
    public Integer queuedCount { get; private set; }
    @AuraEnabled
    public Integer activeHouseholdCount { get; private set; }
    @AuraEnabled
    public String nextDigestRunLabel { get; set; }
    @AuraEnabled
    public String digestTimezoneLabel { get; set; }
    @AuraEnabled
    public String digestTimezoneAbbreviation { get; set; }

    public DashboardStats(
      Integer deliveredTodayCount,
      Integer suppressedTodayCount,
      Integer queuedCount,
      Integer activeHouseholdCount
    ) {
      this.deliveredTodayCount = deliveredTodayCount;
      this.suppressedTodayCount = suppressedTodayCount;
      this.queuedCount = queuedCount;
      this.activeHouseholdCount = activeHouseholdCount;
    }

    public DashboardStats() {
      this(0, 0, 0, 0);
    }
  }

  public class DigestScheduleItem {
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String timeLabel { get; set; }
    @AuraEnabled
    public Integer queuedCount { get; set; }
    @AuraEnabled
    public List<String> channelTags { get; set; }

    public DigestScheduleItem() {
      this.channelTags = new List<String>();
    }
  }

  public class InboxItem {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String body { get; set; }
    @AuraEnabled
    public String sourceType { get; set; }
    @AuraEnabled
    public String householdName { get; set; }
    @AuraEnabled
    public Datetime deliveredAt { get; set; }
    @AuraEnabled
    public Boolean isRead { get; set; }
    @AuraEnabled
    public String targetRecordId { get; set; }

    public InboxItem() {
      this.isRead = false;
    }
  }

  public class InboxPageResult {
    @AuraEnabled
    public List<InboxItem> items { get; set; }
    @AuraEnabled
    public InboxStats stats { get; set; }
    @AuraEnabled
    public Boolean hasMore { get; set; }

    public InboxPageResult() {
      this.items = new List<InboxItem>();
    }
  }

  public class InboxStats {
    @AuraEnabled
    public Integer totalCount { get; private set; }
    @AuraEnabled
    public Integer unreadCount { get; private set; }
    @AuraEnabled
    public Integer weekCount { get; private set; }

    public InboxStats(
      Integer totalCount,
      Integer unreadCount,
      Integer weekCount
    ) {
      this.totalCount = totalCount;
      this.unreadCount = unreadCount;
      this.weekCount = weekCount;
    }

    public InboxStats() {
      this(0, 0, 0);
    }
  }

  public class LogItem {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String notificationNumber { get; set; }
    @AuraEnabled
    public String householdName { get; set; }
    @AuraEnabled
    public Id householdId { get; set; }
    @AuraEnabled
    public String sourceType { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String recipientName { get; set; }
    @AuraEnabled
    public Id recipientId { get; set; }
    @AuraEnabled
    public String sourceRecordId { get; set; }
    @AuraEnabled
    public String targetRecordId { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public String channel { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String suppressionReason { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
    @AuraEnabled
    public Decimal priority { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public Datetime eventAt { get; set; }
    @AuraEnabled
    public String changeContext { get; set; }
    @AuraEnabled
    public String subject { get; set; }
    @AuraEnabled
    public String changeMade { get; set; }
    @AuraEnabled
    public String assignedTo { get; set; }
    @AuraEnabled
    public Datetime changeDate { get; set; }
    @AuraEnabled
    public String changeDateLabel { get; set; }
    @AuraEnabled
    public String financialAdvisorTeamName { get; set; }
    @AuraEnabled
    public Id financialAdvisorTeamId { get; set; }
    @AuraEnabled
    public String branchName { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String branchAffiliations { get; set; }

    public LogItem() {
    }
  }

  public class LogPresentationFields {
    public String changeMadePlainText { get; set; }
    public String changedAtDisplay { get; set; }
    public Datetime changedAtDatetime { get; set; }

    public LogPresentationFields() {
    }
  }

  public class LogPageResult {
    @AuraEnabled
    public List<LogItem> items { get; set; }
    @AuraEnabled
    public Boolean hasMore { get; set; }
    @AuraEnabled
    public Integer filteredTotalCount { get; set; }
    @AuraEnabled
    public Id nextLastSeenId { get; set; }
    @AuraEnabled
    public List<FilterOption> householdOptions { get; set; }
    @AuraEnabled
    public List<FilterOption> branchOptions { get; set; }

    public LogPageResult() {
      this.items = new List<LogItem>();
      this.householdOptions = new List<FilterOption>();
      this.branchOptions = new List<FilterOption>();
    }
  }

  public class FilterOption {
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public String label { get; set; }

    public FilterOption() {
    }

    public FilterOption(String value, String label) {
      this.value = value;
      this.label = label;
    }
  }

  public class RuleInput {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String ruleName { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public String objectType { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public String digestFrequency { get; set; }
    @AuraEnabled
    public String digestFrequencyHour { get; set; }
    @AuraEnabled
    public List<String> channels { get; set; }
    @AuraEnabled
    public Boolean isActive { get; set; }
    @AuraEnabled
    public Id householdId { get; set; }

    public RuleInput() {
      this.channels = new List<String>();
      this.isActive = false;
    }
  }

  public class RuleItem {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String ruleName { get; set; }
    @AuraEnabled
    public String ruleNumber { get; set; }
    @AuraEnabled
    public String category { get; set; }
    @AuraEnabled
    public String objectType { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public String digestFrequency { get; set; }
    @AuraEnabled
    public String digestFrequencyHour { get; set; }
    @AuraEnabled
    public List<String> channels { get; set; }
    @AuraEnabled
    public Boolean isActive { get; set; }
    @AuraEnabled
    public Boolean householdScoped { get; set; }
    @AuraEnabled
    public Id householdId { get; set; }
    @AuraEnabled
    public String householdName { get; set; }
    @AuraEnabled
    public Boolean respectQuietHours { get; set; }
    @AuraEnabled
    public Decimal priority { get; set; }
    @AuraEnabled
    public Boolean isSystemDefault { get; set; }
    @AuraEnabled
    public Boolean isReadOnly { get; set; }

    public RuleItem() {
      this.channels = new List<String>();
      this.isActive = false;
      this.householdScoped = false;
      this.respectQuietHours = false;
      this.isSystemDefault = false;
      this.isReadOnly = false;
    }
  }
}