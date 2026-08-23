/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * AuraEnabled API for notification preference UI.
 */
public with sharing class NotificationPreferenceController {
  @AuraEnabled(cacheable=true)
  public static List<NotificationChannelService.ChannelOption> getChannelOptions() {
    return NotificationChannelService.getChannelOptions();
  }

  @AuraEnabled
  public static Notification_Rule__c savePreference(
    Notification_Rule__c preference
  ) {
    return new NotificationPreferenceAdminService().saveScopedPreference(preference);
  }

  @AuraEnabled
  public static NotificationPreferenceService.ResolveResult resolvePreference(
    String objectType,
    Id recipientId,
    Id householdId
  ) {
    return new NotificationPreferenceService().resolve(
      objectType,
      recipientId,
      householdId
    );
  }
}