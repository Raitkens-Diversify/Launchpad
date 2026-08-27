/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 *
 * Runs notification prepare work in a fresh transaction when the caller
 * (typically the Notification Center Event Flow) has already consumed SOQL.
 * SOQL 101 is uncatchable, so this job never continues once remaining queries
 * drop below the prepare reserve.
 */
public without sharing class NotificationPrepareStartQueueable implements Queueable, System.Finalizer {
  @TestVisible
  public static Integer testEnqueuedJobCount = 0;

  @TestVisible
  public static Boolean testForceAsyncEnqueue = false;

  @TestVisible
  public static Boolean testSkipDeliveryEnqueue = false;

  public class PrepareRequest {
    public String sourceType;
    public String sourceId;
    public String changeContextJson;
    public Boolean prepareNotificationLog;

    public PrepareRequest(
      String sourceType,
      String sourceId,
      String changeContextJson,
      Boolean prepareNotificationLog
    ) {
      this.sourceType = sourceType;
      this.sourceId = sourceId;
      this.changeContextJson = changeContextJson;
      this.prepareNotificationLog = prepareNotificationLog == true;
    }
  }

  private final List<PrepareRequest> prepareRequests;
  private final Integer startIndex;
  private final List<NotificationCenterDeliveryItem> pendingDeliveryItems = new List<NotificationCenterDeliveryItem>();
  private Integer remainingStartIndex;
  private Boolean deliveryEnqueued = false;

  public NotificationPrepareStartQueueable(
    String sourceType,
    String sourceId,
    String changeContextJson
  ) {
    this(sourceType, sourceId, changeContextJson, false);
  }

  @TestVisible
  private NotificationPrepareStartQueueable(
    String sourceType,
    String sourceId,
    String changeContextJson,
    Boolean prepareNotificationLog
  ) {
    this(
      new List<PrepareRequest>{
        new PrepareRequest(
          sourceType,
          sourceId,
          changeContextJson,
          prepareNotificationLog
        )
      },
      0
    );
  }

  @TestVisible
  private NotificationPrepareStartQueueable(
    List<PrepareRequest> prepareRequests,
    Integer startIndex
  ) {
    this.prepareRequests = prepareRequests == null
      ? new List<PrepareRequest>()
      : prepareRequests;
    this.startIndex = startIndex == null ? 0 : startIndex;
  }

  public static void enqueue(
    String sourceType,
    String sourceId,
    String changeContextJson
  ) {
    enqueue(sourceType, sourceId, changeContextJson, false);
  }

  public static void enqueue(
    String sourceType,
    String sourceId,
    String changeContextJson,
    Boolean prepareNotificationLog
  ) {
    enqueueRequests(
      new List<PrepareRequest>{
        new PrepareRequest(
          sourceType,
          sourceId,
          changeContextJson,
          prepareNotificationLog
        )
      },
      0
    );
  }

  public static void enqueueRequests(List<PrepareRequest> prepareRequests) {
    enqueueRequests(prepareRequests, 0);
  }

  public static void enqueueRequests(
    List<PrepareRequest> prepareRequests,
    Integer startIndex
  ) {
    if (prepareRequests == null || prepareRequests.isEmpty()) {
      return;
    }

    Integer safeStartIndex = startIndex == null ? 0 : startIndex;
    if (safeStartIndex >= prepareRequests.size()) {
      return;
    }

    NotificationPrepareStartQueueable job = new NotificationPrepareStartQueueable(
      prepareRequests,
      safeStartIndex
    );

    if (Test.isRunningTest() && !testForceAsyncEnqueue) {
      job.runPrepare();
      testEnqueuedJobCount++;
      return;
    }

    if (!NotificationGovernorLimitService.enqueueQueueable(job)) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationPrepareStartQueueable.enqueueRequests',
        new NotificationDeliveryService.NotificationDeliveryException(
          NotificationConstants.ERROR_QUEUEABLE_JOB_LIMIT
        )
      );
      return;
    }

    testEnqueuedJobCount++;
  }

  public void execute(QueueableContext context) {
    NotificationGovernorLimitService.enterQueueableExecute();
    System.attachFinalizer(this);
    runPrepare();
    enqueueFollowUpWork();
  }

  @TestVisible
  private void runPrepare() {
    NotificationCenterEventService service = new NotificationCenterEventService();
    NotificationEmailDeliveryService.beginBatch();
    Boolean processOneSource = System.isQueueable();

    try {
      for (
        Integer index = startIndex;
        index < prepareRequests.size();
        index++
      ) {
        if (processOneSource && index > startIndex) {
          remainingStartIndex = index;
          break;
        }

        if (
          index > startIndex &&
          !NotificationGovernorLimitService.canAffordPrepareSourceRecord()
        ) {
          remainingStartIndex = index;
          if (!processOneSource) {
            enqueueRequests(prepareRequests, index);
          }
          break;
        }

        collectPrepareRequest(service, prepareRequests[index]);
      }

      pendingDeliveryItems.addAll(
        NotificationRecipientPrepareDispatcher.consumeDeferredDeliveryItems()
      );

      if (!processOneSource) {
        enqueuePendingDelivery();
      }
    } finally {
      try {
        NotificationEmailDeliveryService.endBatch();
      } catch (Exception flushError) {
        NotificationGovernorLimitService.logLimitException(
          'NotificationPrepareStartQueueable.flush',
          flushError
        );
      }
    }
  }

  private void collectPrepareRequest(
    NotificationCenterEventService service,
    PrepareRequest prepareRequest
  ) {
    if (prepareRequest == null) {
      return;
    }

    try {
      List<NotificationCenterDeliveryItem> deliveryItems;
      if (prepareRequest.prepareNotificationLog) {
        deliveryItems = service.prepareNotificationLog(prepareRequest.sourceId);
      } else {
        deliveryItems = service.prepareSourceRecord(
          prepareRequest.sourceType,
          prepareRequest.sourceId,
          prepareRequest.changeContextJson
        );
      }

      if (deliveryItems != null && !deliveryItems.isEmpty()) {
        pendingDeliveryItems.addAll(deliveryItems);
      }
    } catch (Exception error) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationPrepareStartQueueable.processPrepareRequest',
        error
      );
    }
  }

  private void enqueueFollowUpWork() {
    NotificationRecipientPrepareModels.ContinuationRequest continuation =
      NotificationRecipientPrepareDispatcher.consumeDeferredContinuation();

    if (
      continuation != null &&
      NotificationGovernorLimitService.enqueueQueueable(
        new NotificationPrepareChainQueueable(continuation)
      )
    ) {
      testEnqueuedJobCount++;
      return;
    }

    if (
      remainingStartIndex != null &&
      remainingStartIndex < prepareRequests.size() &&
      NotificationGovernorLimitService.enqueueQueueable(
        new NotificationPrepareStartQueueable(
          prepareRequests,
          remainingStartIndex
        )
      )
    ) {
      testEnqueuedJobCount++;
      return;
    }

    enqueuePendingDelivery();
  }

  private void enqueuePendingDelivery() {
    if (Test.isRunningTest() && testSkipDeliveryEnqueue) {
      deliveryEnqueued = true;
      return;
    }

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

  public void execute(System.FinalizerContext context) {
    NotificationGovernorLimitService.enterFinalizerExecute();
    handleFinalizerFailure(context);
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

  @TestVisible
  private static void handleFinalizerFailure(
    System.ParentJobResult result,
    Exception error
  ) {
    if (result != System.ParentJobResult.UNHANDLED_EXCEPTION) {
      return;
    }

    NotificationGovernorLimitService.logLimitException(
      'NotificationPrepareStartQueueable.execute',
      error
    );
  }

  @TestVisible
  private static void handleFinalizerFailure(
    System.FinalizerContext context
  ) {
    if (context == null) {
      return;
    }

    handleFinalizerFailure(context.getResult(), context.getException());
  }

  @TestVisible
  public static void resetTestState() {
    testEnqueuedJobCount = 0;
    testForceAsyncEnqueue = false;
    testSkipDeliveryEnqueue = false;
  }
}