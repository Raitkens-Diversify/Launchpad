/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * DTOs for notification center debug tooling.
 */
public with sharing class NotificationCenterDebugModels {
  public class DebugDigestItem {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String body { get; set; }
    @AuraEnabled
    public String channel { get; set; }
    @AuraEnabled
    public String sourceRecordId { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Datetime createdAt { get; set; }
    @AuraEnabled
    public Datetime deliveredAt { get; set; }

    public DebugDigestItem() {
    }
  }

  public class DigestTriggerResult {
    @AuraEnabled
    public String objectType { get; set; }
    @AuraEnabled
    public Integer deliveredCount { get; set; }
    @AuraEnabled
    public Integer previewCount { get; set; }
    @AuraEnabled
    public Integer customNotificationCount { get; set; }
    @AuraEnabled
    public Integer sourceRecordCount { get; set; }
    @AuraEnabled
    public Integer publishedEventCount { get; set; }
    @AuraEnabled
    public Id batchJobId { get; set; }
    @AuraEnabled
    public List<DebugDigestItem> items { get; set; }

    public DigestTriggerResult() {
      this.items = new List<DebugDigestItem>();
    }
  }
}