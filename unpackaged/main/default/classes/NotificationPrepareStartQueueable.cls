/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 *
 * Runs notification prepare work in a fresh transaction when the caller
 * has insufficient remaining SOQL budget.
 */
public without sharing class NotificationPrepareStartQueueable implements Queueable, System.Finalizer {
  @TestVisible
  public static Integer testEnqueuedJobCount = 0;

  @TestVisible
  public static Boolean testForceAsyncEnqueue = false;

  @TestVisible
  public static Boolean testSkipDeliveryEnqueue = false;

  private final String sourceType;
  private final String sourceId;
  private final String changeContextJson;
  private final Boolean prepareNotificationLog;

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
    this.sourceType = sourceType;
    this.sourceId = sourceId;
    this.changeContextJson = changeContextJson;
    this.prepareNotificationLog = prepareNotificationLog == true;
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
    NotificationPrepareStartQueueable job = new NotificationPrepareStartQueueable(
      sourceType,
      sourceId,
      changeContextJson,
      prepareNotificationLog
    );

    if (Test.isRunningTest() && !testForceAsyncEnqueue) {
      job.runPrepare();
      testEnqueuedJobCount++;
      return;
    }

    if (!NotificationGovernorLimitService.canEnqueueQueueableJob()) {
      job.runPrepare();
      testEnqueuedJobCount++;
      return;
    }

    System.enqueueJob(job);
    testEnqueuedJobCount++;
  }

  public void execute(QueueableContext context) {
    System.attachFinalizer(this);
    runPrepare();
  }

  @TestVisible
  private void runPrepare() {
    NotificationCenterEventService service = new NotificationCenterEventService();
    List<NotificationCenterDeliveryItem> deliveryItems;
    NotificationEmailDeliveryService.beginBatch();

    try {
      if (prepareNotificationLog) {
        deliveryItems = service.prepareNotificationLog(sourceId);
      } else {
        deliveryItems = service.prepareSourceRecord(
          sourceType,
          sourceId,
          changeContextJson
        );
      }

      if (!(Test.isRunningTest() && testSkipDeliveryEnqueue)) {
        NotificationDeliveryEnqueueService.enqueueImmediateDeliveryItems(
          deliveryItems
        );
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

  public void execute(System.FinalizerContext context) {
    handleFinalizerFailure(context);
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