/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Chains notification delivery queueable jobs when enqueue limits are exceeded.
 */
public without sharing class NotificationDeliveryChainQueueable implements Queueable {
  private final List<NotificationDeliveryModels.DeliveryRequest> pendingRequests;
  private final Integer startIndex;

  public NotificationDeliveryChainQueueable(
    List<NotificationDeliveryModels.DeliveryRequest> pendingRequests
  ) {
    this(pendingRequests, 0);
  }

  public NotificationDeliveryChainQueueable(
    List<NotificationDeliveryModels.DeliveryRequest> pendingRequests,
    Integer startIndex
  ) {
    this.pendingRequests = pendingRequests == null
      ? new List<NotificationDeliveryModels.DeliveryRequest>()
      : pendingRequests;
    this.startIndex = startIndex == null ? 0 : startIndex;
  }

  public void execute(QueueableContext context) {
    NotificationGovernorLimitService.enterQueueableExecute();
    NotificationDeliveryDispatcher.chainRemainingJobs(
      pendingRequests,
      startIndex
    );
  }
}