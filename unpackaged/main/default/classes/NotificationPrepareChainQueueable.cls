/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Continues chunked notification recipient preparation asynchronously.
 */
public without sharing class NotificationPrepareChainQueueable implements Queueable, System.Finalizer {
  private final NotificationRecipientPrepareModels.ContinuationRequest continuationRequest;

  public NotificationPrepareChainQueueable(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest
  ) {
    this.continuationRequest = continuationRequest;
  }

  public void execute(QueueableContext context) {
    System.attachFinalizer(this);
    NotificationRecipientPrepareDispatcher.continuePreparation(
      continuationRequest
    );
  }

  public void execute(System.FinalizerContext context) {
    handleFinalizerFailure(continuationRequest, context);
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