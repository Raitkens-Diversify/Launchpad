/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Models for chunked notification recipient preparation.
 */
public class NotificationRecipientPrepareModels {
  public class SourcePrepareContext {
    public String sourceType;
    public String sourceId;
    public Id householdId;
    public String correlationKey;
    public String changeContextJson;
    public String enrichedChangeContextJson;
    public List<Id> recipientIds;
    public Set<Id> pitStopBypassRecipientIds = new Set<Id>();
  }

  public class ContinuationRequest {
    public String sourceType;
    public String sourceId;
    public String correlationKey;
    public String changeContextJson;
    public Integer startIndex;
    public Integer chunkSize;
    public Integer attemptNumber;
  }

  public class ProcessChunkResult {
    public Integer nextStartIndex;
    public List<NotificationCenterDeliveryItem> deliveryItems = new List<NotificationCenterDeliveryItem>();
    public Boolean limitReached = false;
    public Exception caughtException;
  }
}