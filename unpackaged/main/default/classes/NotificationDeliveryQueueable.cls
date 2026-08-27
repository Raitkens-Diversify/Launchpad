/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Delivers notification logs asynchronously with retry support.
 */
public without sharing class NotificationDeliveryQueueable implements Queueable, Database.AllowsCallouts, System.Finalizer {
  private final NotificationDeliveryModels.DeliveryRequest request;
  private final NotificationDeliveryService deliveryService;

  public NotificationDeliveryQueueable(
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    this(request, new NotificationDeliveryService());
  }

  @TestVisible
  private NotificationDeliveryQueueable(
    NotificationDeliveryModels.DeliveryRequest request,
    NotificationDeliveryService deliveryService
  ) {
    this.request = request;
    this.deliveryService = deliveryService;
  }

  public void execute(QueueableContext context) {
    NotificationGovernorLimitService.enterQueueableExecute();
    System.attachFinalizer(this);
    deliveryService.deliver(request);
  }

  public void execute(System.FinalizerContext context) {
    NotificationGovernorLimitService.enterFinalizerExecute();
    if (context.getResult() != System.ParentJobResult.UNHANDLED_EXCEPTION) {
      return;
    }

    deliveryService.handleFailure(request, context.getException());
  }
}