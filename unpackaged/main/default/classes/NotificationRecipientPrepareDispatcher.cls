/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Chunks notification recipient preparation and chains overflow work asynchronously.
 */
public without sharing class NotificationRecipientPrepareDispatcher {
  @TestVisible
  public static Integer testEnqueuedContinuationCount = 0;

  @TestVisible
  private static Integer testMaxSyncChunks;

  @TestVisible
  private static Integer syncChunksProcessed = 0;

  private static NotificationRecipientPrepareModels.ContinuationRequest deferredContinuation;
  private static List<NotificationCenterDeliveryItem> deferredDeliveryItems = new List<NotificationCenterDeliveryItem>();

  public static List<NotificationCenterDeliveryItem> processRecipients(
    NotificationRecipientPrepareModels.SourcePrepareContext context
  ) {
    List<NotificationCenterDeliveryItem> deliveryItems = new List<NotificationCenterDeliveryItem>();

    if (
      context == null ||
      context.recipientIds == null ||
      context.recipientIds.isEmpty()
    ) {
      return deliveryItems;
    }

    NotificationRecipientPrepareService prepareService = new NotificationRecipientPrepareService();
    Integer startIndex = 0;

    while (startIndex < context.recipientIds.size()) {
      if (
        shouldStopSyncProcessing() ||
        !NotificationGovernorLimitService.canProcessAnotherRecipientChunk()
      ) {
        enqueueContinuation(buildContinuationRequest(context, startIndex, null, 1));
        break;
      }

      NotificationRecipientPrepareModels.ProcessChunkResult chunkResult = prepareService.processChunk(
        context,
        startIndex,
        null
      );
      deliveryItems.addAll(chunkResult.deliveryItems);
      syncChunksProcessed++;

      if (chunkResult.limitReached) {
        Integer retryChunkSize = NotificationGovernorLimitService.shrinkRecipientChunkSize(
          NotificationGovernorLimitService.resolveRecipientChunkSize(
            context.recipientIds.size() - chunkResult.nextStartIndex
          )
        );
        enqueueContinuation(
          buildContinuationRequest(
            context,
            chunkResult.nextStartIndex,
            retryChunkSize,
            1
          )
        );
        break;
      }

      startIndex = chunkResult.nextStartIndex;
    }

    return deliveryItems;
  }

  public static void continuePreparation(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest
  ) {
    if (continuationRequest == null) {
      return;
    }

    NotificationRecipientPrepareModels.SourcePrepareContext context = NotificationPrepareContextFactory.buildFromContinuation(
      continuationRequest
    );

    if (context == null || context.recipientIds == null || context.recipientIds.isEmpty()) {
      return;
    }

    Integer safeStartIndex = continuationRequest.startIndex == null
      ? 0
      : continuationRequest.startIndex;

    if (safeStartIndex >= context.recipientIds.size()) {
      return;
    }

    NotificationRecipientPrepareService prepareService = new NotificationRecipientPrepareService();
    NotificationRecipientPrepareModels.ProcessChunkResult chunkResult = prepareService.processChunk(
      context,
      safeStartIndex,
      continuationRequest.chunkSize
    );

    enqueueImmediateDelivery(chunkResult.deliveryItems);

    if (chunkResult.limitReached) {
      handleContinuationFailure(continuationRequest, chunkResult.caughtException);
      return;
    }

    if (
      chunkResult.nextStartIndex < context.recipientIds.size() &&
      chunkResult.nextStartIndex > safeStartIndex
    ) {
      enqueueContinuation(
        buildContinuationRequest(
          context,
          chunkResult.nextStartIndex,
          continuationRequest.chunkSize,
          1
        )
      );
    }
  }

  public static void handleContinuationFailure(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest,
    Exception error
  ) {
    if (continuationRequest == null) {
      return;
    }

    Integer attemptNumber = continuationRequest.attemptNumber == null
      ? 1
      : continuationRequest.attemptNumber;

    if (attemptNumber >= NotificationConstants.MAX_RECIPIENT_PREPARE_CHAIN_ATTEMPTS) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationRecipientPrepareDispatcher.handleContinuationFailure',
        error
      );
      return;
    }

    Integer retryChunkSize = NotificationGovernorLimitService.shrinkRecipientChunkSize(
      continuationRequest.chunkSize == null
        ? NotificationGovernorLimitService.resolveRecipientChunkSize(
            NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK
          )
        : continuationRequest.chunkSize
    );

    NotificationRecipientPrepareModels.ContinuationRequest retryRequest = buildContinuationRequest(
      continuationRequest.sourceType,
      continuationRequest.sourceId,
      continuationRequest.correlationKey,
      continuationRequest.changeContextJson,
      continuationRequest.startIndex,
      retryChunkSize,
      attemptNumber + 1
    );
    enqueueContinuation(retryRequest);
  }

  private static void enqueueContinuation(
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest
  ) {
    if (continuationRequest == null || continuationRequest.startIndex == null) {
      return;
    }

    if (System.isQueueable()) {
      deferredContinuation = continuationRequest;
      testEnqueuedContinuationCount++;
      return;
    }

    if (
      NotificationGovernorLimitService.isInFinalizerContext() ||
      System.isBatch()
    ) {
      if (
        NotificationGovernorLimitService.enqueueQueueable(
          new NotificationPrepareChainQueueable(continuationRequest)
        )
      ) {
        testEnqueuedContinuationCount++;
        return;
      }

      NotificationGovernorLimitService.logLimitException(
        'NotificationRecipientPrepareDispatcher.enqueueContinuation',
        new NotificationDeliveryService.NotificationDeliveryException(
          NotificationConstants.ERROR_QUEUEABLE_JOB_LIMIT
        )
      );
      return;
    }

    if (
      !Test.isRunningTest() &&
      NotificationGovernorLimitService.enqueueQueueable(
        new NotificationPrepareChainQueueable(continuationRequest)
      )
    ) {
      testEnqueuedContinuationCount++;
      return;
    }

    continuePreparation(continuationRequest);
    testEnqueuedContinuationCount++;
  }

  public static NotificationRecipientPrepareModels.ContinuationRequest consumeDeferredContinuation() {
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest = deferredContinuation;
    deferredContinuation = null;
    return continuationRequest;
  }

  public static List<NotificationCenterDeliveryItem> consumeDeferredDeliveryItems() {
    List<NotificationCenterDeliveryItem> deliveryItems = deferredDeliveryItems;
    deferredDeliveryItems = new List<NotificationCenterDeliveryItem>();
    return deliveryItems;
  }

  private static void enqueueImmediateDelivery(
    List<NotificationCenterDeliveryItem> deliveryItems
  ) {
    if (deliveryItems == null || deliveryItems.isEmpty()) {
      return;
    }

    if (System.isQueueable()) {
      deferredDeliveryItems.addAll(deliveryItems);
      return;
    }

    NotificationDeliveryEnqueueService.enqueueImmediateDeliveryItems(
      deliveryItems
    );
  }

  private static NotificationRecipientPrepareModels.ContinuationRequest buildContinuationRequest(
    NotificationRecipientPrepareModels.SourcePrepareContext context,
    Integer startIndex,
    Integer chunkSize,
    Integer attemptNumber
  ) {
    return buildContinuationRequest(
      context.sourceType,
      context.sourceId,
      context.correlationKey,
      context.changeContextJson,
      startIndex,
      chunkSize,
      attemptNumber
    );
  }

  private static NotificationRecipientPrepareModels.ContinuationRequest buildContinuationRequest(
    String sourceType,
    String sourceId,
    String correlationKey,
    String changeContextJson,
    Integer startIndex,
    Integer chunkSize,
    Integer attemptNumber
  ) {
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest = new NotificationRecipientPrepareModels.ContinuationRequest();
    continuationRequest.sourceType = sourceType;
    continuationRequest.sourceId = sourceId;
    continuationRequest.correlationKey = correlationKey;
    continuationRequest.changeContextJson = changeContextJson;
    continuationRequest.startIndex = startIndex;
    continuationRequest.chunkSize = chunkSize;
    continuationRequest.attemptNumber = attemptNumber;
    return continuationRequest;
  }

  @TestVisible
  public static void resetTestState() {
    testEnqueuedContinuationCount = 0;
    testMaxSyncChunks = null;
    syncChunksProcessed = 0;
    deferredContinuation = null;
    deferredDeliveryItems = new List<NotificationCenterDeliveryItem>();
  }

  private static Boolean shouldStopSyncProcessing() {
    return Test.isRunningTest() &&
      testMaxSyncChunks != null &&
      syncChunksProcessed >= testMaxSyncChunks;
  }
}