/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Request/response models for NotificationRuleLogService.
 */
public with sharing class NotificationRuleLogModels {
  public class ProcessRecipientRequest {
    public String sourceType;
    public String sourceId;
    public Id recipientId;
    public Id householdId;
    public String correlationKey;
    public String changeContextJson;
    public NotificationPreferenceService.ResolveResult preferenceResult;
    public Map<String, NotificationPreferenceService.ResolveResult> channelPreferenceResults;

    public ProcessRecipientRequest() {
    }
  }

  public class ProcessRecipientResult {
    public List<Notification_Log__c> logs = new List<Notification_Log__c>();
    public List<Notification_Log__c> immediateLogs = new List<Notification_Log__c>();

    public ProcessRecipientResult() {
      this.logs = new List<Notification_Log__c>();
      this.immediateLogs = new List<Notification_Log__c>();
    }
  }
}