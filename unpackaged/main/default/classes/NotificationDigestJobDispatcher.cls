/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * @deprecated Use NotificationDeliveryDispatcher instead.
 * Enqueues digest delivery jobs with governor-limit-safe chunking.
 */
public with sharing class NotificationDigestJobDispatcher {
  public static Integer testEnqueuedJobCount = 0;

  public static Integer testChainExecutionCount = 0;

  public static Integer enqueueChunk(
    List<NotificationDigestModels.DigestDeliveryRequest> requests,
    Integer startIndex,
    List<NotificationDigestModels.DigestDeliveryRequest> overflowOut
  ) {
    if (requests == null || requests.isEmpty()) {
      return startIndex == null ? 0 : startIndex;
    }

    List<NotificationDeliveryModels.DeliveryRequest> deliveryRequests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (NotificationDigestModels.DigestDeliveryRequest request : requests) {
      deliveryRequests.add(NotificationDeliveryRequestBuilder.fromDigest(request));
    }

    List<NotificationDeliveryModels.DeliveryRequest> overflowDeliveryRequests = new List<NotificationDeliveryModels.DeliveryRequest>();
    Integer nextIndex = NotificationDeliveryDispatcher.enqueueChunk(
      deliveryRequests,
      startIndex,
      overflowDeliveryRequests
    );

    if (overflowOut != null && !overflowDeliveryRequests.isEmpty()) {
      for (
        NotificationDeliveryModels.DeliveryRequest overflowRequest : overflowDeliveryRequests
      ) {
        overflowOut.add(toDigestRequest(overflowRequest));
      }
    }

    testEnqueuedJobCount = NotificationDeliveryDispatcher.testEnqueuedJobCount;
    return nextIndex;
  }

  public static void chainRemainingJobs(
    List<NotificationDigestModels.DigestDeliveryRequest> requests,
    Integer startIndex
  ) {
    testChainExecutionCount++;

    if (requests == null || requests.isEmpty()) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> deliveryRequests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (NotificationDigestModels.DigestDeliveryRequest request : requests) {
      deliveryRequests.add(NotificationDeliveryRequestBuilder.fromDigest(request));
    }

    NotificationDeliveryDispatcher.chainRemainingJobs(
      deliveryRequests,
      startIndex
    );
    testEnqueuedJobCount = NotificationDeliveryDispatcher.testEnqueuedJobCount;
  }

  private static NotificationDigestModels.DigestDeliveryRequest toDigestRequest(
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.logIds = request.logIds == null
      ? new List<Id>()
      : new List<Id>(request.logIds);
    digestRequest.recipientId = request.recipientId;
    digestRequest.channel = request.channel;
    digestRequest.sourceType = request.sourceType;
    digestRequest.cadence = request.cadence;
    digestRequest.attemptNumber = request.attemptNumber;
    return digestRequest;
  }
}