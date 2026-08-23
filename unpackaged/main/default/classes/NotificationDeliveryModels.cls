/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * DTOs for unified notification delivery (immediate and digest).
 */
public with sharing class NotificationDeliveryModels {
  public class DeliveryRequest {
    public List<Id> logIds { get; set; }
    public Id recipientId { get; set; }
    public String channel { get; set; }
    public String sourceType { get; set; }
    public String frequency { get; set; }
    public String cadence { get; set; }
    public Integer attemptNumber { get; set; }
    public Boolean deliverIndividually { get; set; }

    public DeliveryRequest() {
      this.logIds = new List<Id>();
      this.attemptNumber = 0;
      this.deliverIndividually = false;
    }

    public DeliveryRequest withAttemptNumber(Integer nextAttempt) {
      DeliveryRequest retryRequest = new DeliveryRequest();
      retryRequest.logIds = new List<Id>(logIds);
      retryRequest.recipientId = recipientId;
      retryRequest.channel = channel;
      retryRequest.sourceType = sourceType;
      retryRequest.frequency = frequency;
      retryRequest.cadence = cadence;
      retryRequest.attemptNumber = nextAttempt == null ? 0 : nextAttempt;
      retryRequest.deliverIndividually = deliverIndividually;
      return retryRequest;
    }
  }

  public class DeliveryContext {
    public DeliveryRequest request { get; set; }
    public List<Notification_Log__c> logs { get; set; }
    public NotificationDigestModels.ConsolidatedMessage message { get; set; }

    public DeliveryContext() {
      this.request = new DeliveryRequest();
      this.logs = new List<Notification_Log__c>();
    }
  }
}