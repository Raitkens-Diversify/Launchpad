/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 *
 * Continues chunked notification recipient preparation asynchronously.
 * A Queueable may enqueue only one follow-up job, so remaining recipient
 * work uses that slot and delivery hops through the Finalizer.
 */
public without sharing class NotificationPrepareChainQueueable implements Queueable, System.Finalizer {
  private final NotificationRecipientPrepareModels.ContinuationRequest continuationRequest;
  private List<NotificationCenterDeliveryItem> pendingDeliveryItems = new List<NotificationCenterDeliveryItem>();
  private Boolean deliveryEnqueued = false;

  public NotificationPrepareChainQueueable(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest
  ) {
    this.continuationRequest = continuationRequest;
  }

  public void execute(QueueableContext context) {
    NotificationGovernorLimitService.enterQueueableExecute();
    System.attachFinalizer(this);
    NotificationRecipientPrepareDispatcher.continuePreparation(
      continuationRequest
    );
    pendingDeliveryItems.addAll(
      NotificationRecipientPrepareDispatcher.consumeDeferredDeliveryItems()
    );

    NotificationRecipientPrepareModels.ContinuationRequest nextContinuation =
      NotificationRecipientPrepareDispatcher.consumeDeferredContinuation();
    if (
      nextContinuation != null &&
      NotificationGovernorLimitService.enqueueQueueable(
        new NotificationPrepareChainQueueable(nextContinuation)
      )
    ) {
      return;
    }

    enqueuePendingDelivery();
  }

  public void execute(System.FinalizerContext context) {
    NotificationGovernorLimitService.enterFinalizerExecute();
    handleFinalizerFailure(continuationRequest, context);
    if (
      context != null &&
      context.getResult() == System.ParentJobResult.UNHANDLED_EXCEPTION
    ) {
      return;
    }

    if (!deliveryEnqueued) {
      enqueuePendingDelivery();
    }
  }

  private void enqueuePendingDelivery() {
    if (pendingDeliveryItems.isEmpty() || deliveryEnqueued) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromDeliveryItems(
      pendingDeliveryItems
    );
    if (requests == null || requests.isEmpty()) {
      deliveryEnqueued = true;
      return;
    }

    NotificationDeliveryDispatcher.enqueueAsSingleFollowUp(requests);
    deliveryEnqueued = true;
  }

  @TestVisible
  private static void handleFinalizerFailure(
    NotificationRecipientPrepareModels.ContinuationRequest request,
    System.FinalizerContext context
  ) {
    if (context == null) {
      return;
    }

    handleFinalizerFailure(
      request,
      context.getResult(),
      context.getException()
    );
  }

  @TestVisible
  private static void handleFinalizerFailure(
    NotificationRecipientPrepareModels.ContinuationRequest request,
    System.ParentJobResult result,
    Exception error
  ) {
    if (result != System.ParentJobResult.UNHANDLED_EXCEPTION) {
      return;
    }

    NotificationRecipientPrepareDispatcher.handleContinuationFailure(
      request,
      error
    );
  }
}