/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * DTOs for scheduled digest batch processing and delivery.
 */
public with sharing class NotificationDigestModels {
  public class DigestDeliveryRequest {
    public Id recipientId { get; set; }
    public String channel { get; set; }
    public String sourceType { get; set; }
    public List<Id> logIds { get; set; }
    public String cadence { get; set; }
    public Integer attemptNumber { get; set; }

    public DigestDeliveryRequest() {
      this.logIds = new List<Id>();
      this.attemptNumber = 0;
    }

    public DigestDeliveryRequest withAttemptNumber(Integer nextAttempt) {
      DigestDeliveryRequest retryRequest = new DigestDeliveryRequest();
      retryRequest.recipientId = recipientId;
      retryRequest.channel = channel;
      retryRequest.sourceType = sourceType;
      retryRequest.logIds = new List<Id>(logIds);
      retryRequest.cadence = cadence;
      retryRequest.attemptNumber = nextAttempt == null ? 0 : nextAttempt;
      return retryRequest;
    }
  }

  public class ConsolidatedMessage {
    public String title { get; set; }
    public String body { get; set; }
    public Id targetId { get; set; }
    public Integer itemCount { get; set; }

    public ConsolidatedMessage() {
      this.itemCount = 0;
    }
  }

  public class DigestDeliveryContext {
    public DigestDeliveryRequest request { get; set; }
    public List<Notification_Log__c> logs { get; set; }
    public NotificationUserChannelService.ChannelSettings channelSettings { get; set; }
    public ConsolidatedMessage message { get; set; }

    public DigestDeliveryContext() {
      this.request = new DigestDeliveryRequest();
      this.logs = new List<Notification_Log__c>();
    }
  }

  public class DeliveryResult {
    public Boolean success { get; set; }
    public String errorMessage { get; set; }
    public Boolean suppressed { get; set; }
    public String suppressionReason { get; set; }

    public DeliveryResult() {
      this.success = false;
      this.suppressed = false;
    }
  }
}