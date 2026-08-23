/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * AuraEnabled facade for the notification center. Delegates to
 * NotificationCenterService so multiple screens and Apex callers share one API.
 */
public with sharing class NotificationCenterController {
  private static final NotificationCenterService SERVICE = new NotificationCenterService();

  @AuraEnabled
  public static NotificationCenterModels.InboxPageResult getInbox(
    String filterName,
    String searchTerm,
    Integer pageSize,
    Id lastSeenId,
    String sortDirection
  ) {
    return SERVICE.getInbox(
      UserInfo.getUserId(),
      filterName,
      searchTerm,
      pageSize,
      lastSeenId,
      sortDirection
    );
  }

  @AuraEnabled
  public static NotificationCenterModels.LogPageResult getNotificationLog(
    String statusFilter,
    String categoryFilter,
    Integer pageSize,
    Id lastSeenId,
    Date startDate,
    Date endDate,
    String searchTerm,
    String sourceTypeFilter,
    List<String> selectedHouseholdIds,
    List<String> selectedBranchNames,
    Boolean presentationMode
  ) {
    return SERVICE.getNotificationLog(
      UserInfo.getUserId(),
      statusFilter,
      categoryFilter,
      pageSize,
      lastSeenId,
      startDate,
      endDate,
      searchTerm,
      sourceTypeFilter,
      selectedHouseholdIds,
      selectedBranchNames,
      presentationMode
    );
  }

  @AuraEnabled
  public static NotificationCenterModels.DashboardResult getDashboard() {
    return SERVICE.getDashboard(UserInfo.getUserId());
  }

  @AuraEnabled
  public static Integer getUnreadCount() {
    return SERVICE.getUnreadCount(UserInfo.getUserId());
  }

  @AuraEnabled
  public static Integer markAsRead(List<Id> notificationIds) {
    return SERVICE.markAsRead(UserInfo.getUserId(), notificationIds);
  }

  @AuraEnabled
  public static Integer markAllAsRead() {
    return SERVICE.markAllAsRead(UserInfo.getUserId());
  }

  @AuraEnabled
  public static List<Notification_Rule__c> getUserDefaultPreferences() {
    return SERVICE.getUserDefaultPreferences(UserInfo.getUserId());
  }

  @AuraEnabled
  public static List<NotificationCenterModels.RuleItem> getNotificationRules(
    Id householdId
  ) {
    return SERVICE.getNotificationRules(UserInfo.getUserId(), householdId);
  }

  @AuraEnabled
  public static List<NotificationCenterModels.RuleItem> getSystemDefaultRules() {
    return SERVICE.getSystemDefaultRules();
  }

  @AuraEnabled
  public static NotificationCenterModels.RuleItem saveNotificationRule(
    NotificationCenterModels.RuleInput input
  ) {
    return SERVICE.saveNotificationRule(UserInfo.getUserId(), input);
  }

  @AuraEnabled
  public static NotificationCenterModels.RuleItem saveSystemDefaultRule(
    NotificationCenterModels.RuleInput input
  ) {
    return SERVICE.saveSystemDefaultRule(input);
  }

  @AuraEnabled
  public static NotificationCenterModels.RuleItem toggleNotificationRule(
    Id ruleId,
    Boolean isActive
  ) {
    return SERVICE.toggleNotificationRule(UserInfo.getUserId(), ruleId, isActive);
  }

  @AuraEnabled
  public static void deleteNotificationRule(Id ruleId) {
    SERVICE.deleteNotificationRule(UserInfo.getUserId(), ruleId);
  }

  @AuraEnabled
  public static void deleteSystemDefaultRule(Id ruleId) {
    SERVICE.deleteSystemDefaultRule(ruleId);
  }

  @AuraEnabled(cacheable=true)
  public static String getDigestTimezoneLabel() {
    return NotificationDigestTimezoneService.getDigestTimezoneLabel();
  }
}