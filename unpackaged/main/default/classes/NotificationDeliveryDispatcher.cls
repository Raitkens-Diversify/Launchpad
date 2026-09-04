/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 *
 * Enqueues unified notification delivery jobs with governor-limit-safe chunking.
 */
public without sharing class NotificationDeliveryDispatcher {
  public static Integer testEnqueuedJobCount = 0;

  @TestVisible
  public static Integer testChainExecutionCount = 0;

  @TestVisible
  private static Boolean testAllowChainInlineEnqueueContinuation = false;

  public static void enqueueLogIdStrings(List<String> logIdStrings) {
    NotificationDeliveryEnqueueService.enqueueLogIdStrings(logIdStrings);
  }

  public static void enqueueLogIds(List<Id> logIds) {
    NotificationDeliveryEnqueueService.enqueueLogIds(logIds);
  }

  public static void enqueueDigestRequests(
    List<NotificationDigestModels.DigestDeliveryRequest> digestRequests
  ) {
    if (digestRequests == null || digestRequests.isEmpty()) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (NotificationDigestModels.DigestDeliveryRequest digestRequest : digestRequests) {
      requests.add(NotificationDeliveryRequestBuilder.fromDigest(digestRequest));
    }

    enqueueRequests(requests);
  }

  public static void enqueueAsSingleFollowUp(
    List<NotificationDeliveryModels.DeliveryRequest> requests
  ) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    enqueueViaChain(requests);
  }

  public static void enqueueRequests(
    List<NotificationDeliveryModels.DeliveryRequest> requests
  ) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    if (requiresSingleEnqueueChain()) {
      enqueueViaChain(requests);
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> overflowRequests = new List<NotificationDeliveryModels.DeliveryRequest>();
    Integer nextIndex = enqueueChunk(requests, 0, overflowRequests);

    if (
      !overflowRequests.isEmpty() &&
      NotificationGovernorLimitService.enqueueQueueable(
        new NotificationDeliveryChainQueueable(overflowRequests, 0)
      )
    ) {
      testEnqueuedJobCount++;
    } else if (
      !overflowRequests.isEmpty() &&
      NotificationGovernorLimitService.canProcessImmediateDelivery()
    ) {
      deliverOverflowInline(overflowRequests);
    }
  }

  public static Integer enqueueChunk(
    List<NotificationDeliveryModels.DeliveryRequest> requests,
    Integer startIndex,
    List<NotificationDeliveryModels.DeliveryRequest> overflowOut
  ) {
    if (requests == null || requests.isEmpty()) {
      return startIndex == null ? 0 : startIndex;
    }

    Integer safeStartIndex = startIndex == null ? 0 : startIndex;
    Integer jobsEnqueuedThisTransaction = 0;
    Integer index = safeStartIndex;
    Integer maxJobsPerTransaction = resolveMaxEnqueueJobsPerTransaction();

    while (
      index < requests.size() &&
      jobsEnqueuedThisTransaction < maxJobsPerTransaction &&
      NotificationGovernorLimitService.canEnqueueQueueableJob()
    ) {
      if (
        !NotificationGovernorLimitService.enqueueQueueable(
          new NotificationDeliveryQueueable(requests[index])
        )
      ) {
        break;
      }
      jobsEnqueuedThisTransaction++;
      testEnqueuedJobCount++;
      index++;
    }

    if (overflowOut != null) {
      for (
        Integer overflowIndex = index;
        overflowIndex < requests.size();
        overflowIndex++
      ) {
        overflowOut.add(requests[overflowIndex]);
      }
    }

    return index;
  }

  public static void chainRemainingJobs(
    List<NotificationDeliveryModels.DeliveryRequest> requests,
    Integer startIndex
  ) {
    testChainExecutionCount++;

    if (requests == null || requests.isEmpty()) {
      return;
    }

    Integer safeStartIndex = startIndex == null ? 0 : startIndex;

    if (safeStartIndex >= requests.size()) {
      return;
    }

    if (requiresSingleEnqueueChain()) {
      chainDeliverInline(requests, safeStartIndex);
      return;
    }

    Integer nextIndex = enqueueChunk(requests, safeStartIndex, null);

    if (nextIndex < requests.size()) {
      List<NotificationDeliveryModels.DeliveryRequest> overflowRequests = new List<NotificationDeliveryModels.DeliveryRequest>();

      for (
        Integer overflowIndex = nextIndex;
        overflowIndex < requests.size();
        overflowIndex++
      ) {
        overflowRequests.add(requests[overflowIndex]);
      }

      if (
        !overflowRequests.isEmpty() &&
        NotificationGovernorLimitService.enqueueQueueable(
          new NotificationDeliveryChainQueueable(overflowRequests, 0)
        )
      ) {
        testEnqueuedJobCount++;
      } else if (
        !overflowRequests.isEmpty() &&
        NotificationGovernorLimitService.canProcessImmediateDelivery()
      ) {
        deliverOverflowInline(overflowRequests);
      }
    }
  }

  @TestVisible
  private static Boolean requiresSingleEnqueueChain() {
    return NotificationGovernorLimitService.requiresSingleEnqueueChain();
  }

  @TestVisible
  private static Integer resolveMaxEnqueueJobsPerTransaction() {
    return NotificationGovernorLimitService.resolveMaxDeliveryEnqueueJobs();
  }

  @TestVisible
  private static void enqueueViaChain(
    List<NotificationDeliveryModels.DeliveryRequest> requests
  ) {
    Queueable followUpJob;
    if (requests.size() == 1) {
      followUpJob = new NotificationDeliveryQueueable(requests[0]);
    } else {
      followUpJob = new NotificationDeliveryChainQueueable(requests, 0);
    }

    if (NotificationGovernorLimitService.enqueueQueueable(followUpJob)) {
      testEnqueuedJobCount++;
      return;
    }

    if (NotificationGovernorLimitService.canProcessImmediateDelivery()) {
      deliverOverflowInline(requests);
    }
  }

  @TestVisible
  private static void deliverOverflowInline(
    List<NotificationDeliveryModels.DeliveryRequest> requests
  ) {
    NotificationDeliveryService deliveryService = new NotificationDeliveryService();
    NotificationEmailDeliveryService.beginBatch();

    try {
      for (NotificationDeliveryModels.DeliveryRequest request : requests) {
        if (!NotificationGovernorLimitService.canProcessImmediateDelivery()) {
          break;
        }

        try {
          deliveryService.deliver(request);
        } catch (Exception error) {
          deliveryService.handleFailure(request, error);
        }
      }
    } finally {
      try {
        NotificationEmailDeliveryService.endBatch();
      } catch (Exception flushError) {
        NotificationGovernorLimitService.logLimitException(
          'NotificationDeliveryDispatcher.deliverOverflowInline.flush',
          flushError
        );
      }
    }
  }

  @TestVisible
  private static void chainDeliverInline(
    List<NotificationDeliveryModels.DeliveryRequest> requests,
    Integer startIndex
  ) {
    NotificationDeliveryService deliveryService = new NotificationDeliveryService();
    Integer index = startIndex;
    NotificationEmailDeliveryService.beginBatch();

    try {
      while (index < requests.size()) {
        if (!NotificationGovernorLimitService.canProcessImmediateDelivery()) {
          break;
        }

        try {
          deliveryService.deliver(requests[index]);
        } catch (Exception error) {
          deliveryService.handleFailure(requests[index], error);
        }

        index++;

        if (index >= requests.size()) {
          break;
        }

        if (Test.isRunningTest() && !testAllowChainInlineEnqueueContinuation) {
          continue;
        }

        if (
          NotificationGovernorLimitService.enqueueQueueable(
            new NotificationDeliveryChainQueueable(requests, index)
          )
        ) {
          testEnqueuedJobCount++;
          return;
        }
      }
    } finally {
      try {
        NotificationEmailDeliveryService.endBatch();
      } catch (Exception flushError) {
        NotificationGovernorLimitService.logLimitException(
          'NotificationDeliveryDispatcher.chainDeliverInline.flush',
          flushError
        );
      }
    }
  }
}