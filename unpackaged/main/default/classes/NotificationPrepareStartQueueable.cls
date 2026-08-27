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

    if (!NotificationGovernorLimitService.canEnqueueQueueableJob()) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationPrepareStartQueueable.enqueueRequests',
        new NotificationDeliveryService.NotificationDeliveryException(
          NotificationConstants.ERROR_SOQL_QUERY_LIMIT
        )
      );
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
    NotificationEmailDeliveryService.beginBatch();

    try {
      for (
        Integer index = startIndex;
        index < prepareRequests.size();
        index++
      ) {
        if (
          index > startIndex &&
          !NotificationGovernorLimitService.canAffordPrepareSourceRecord()
        ) {
          enqueueRequests(prepareRequests, index);
          return;
        }

        processPrepareRequest(service, prepareRequests[index]);
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

  private void processPrepareRequest(
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

      if (!(Test.isRunningTest() && testSkipDeliveryEnqueue)) {
        NotificationDeliveryEnqueueService.enqueueImmediateDeliveryItems(
          deliveryItems
        );
      }
    } catch (Exception error) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationPrepareStartQueueable.processPrepareRequest',
        error
      );
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