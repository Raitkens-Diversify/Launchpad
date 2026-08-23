/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Chains digest delivery queueable jobs when a batch execute exceeds enqueue limits.
 */
public with sharing class NotificationDigestJobChainQueueable implements Queueable {
  private final List<NotificationDigestModels.DigestDeliveryRequest> pendingRequests;
  private final Integer startIndex;

  public NotificationDigestJobChainQueueable(
    List<NotificationDigestModels.DigestDeliveryRequest> pendingRequests
  ) {
    this(pendingRequests, 0);
  }

  public NotificationDigestJobChainQueueable(
    List<NotificationDigestModels.DigestDeliveryRequest> pendingRequests,
    Integer startIndex
  ) {
    this.pendingRequests = pendingRequests == null
      ? new List<NotificationDigestModels.DigestDeliveryRequest>()
      : pendingRequests;
    this.startIndex = startIndex == null ? 0 : startIndex;
  }

  public void execute(QueueableContext context) {
    NotificationDigestJobDispatcher.chainRemainingJobs(pendingRequests, startIndex);
  }
}