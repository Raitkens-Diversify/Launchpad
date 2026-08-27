/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class NotificationDigestJobDispatcherTest {
  @IsTest
  static void enqueueChunk_mapsOverflowDeliveryRequestsBackToDigest() {
    List<NotificationDigestModels.DigestDeliveryRequest> requests =
      new List<NotificationDigestModels.DigestDeliveryRequest>();

    Integer requestCount =
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION + 3;
    for (Integer index = 0; index < requestCount; index++) {
      NotificationDigestModels.DigestDeliveryRequest request =
        new NotificationDigestModels.DigestDeliveryRequest();
      request.recipientId = UserInfo.getUserId();
      request.channel = NotificationConstants.CHANNEL_EMAIL;
      request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
      request.logIds.add(UserInfo.getUserId());
      requests.add(request);
    }

    List<NotificationDigestModels.DigestDeliveryRequest> overflowRequests =
      new List<NotificationDigestModels.DigestDeliveryRequest>();

    Test.startTest();
    Integer nextIndex = NotificationDigestJobDispatcher.enqueueChunk(
      requests,
      0,
      overflowRequests
    );
    Test.stopTest();

    System.assert(
      nextIndex < requests.size(),
      'Expected enqueueChunk to stop before the last digest request.'
    );
    System.assert(
      !overflowRequests.isEmpty(),
      'Expected overflow digest requests to be converted from delivery requests.'
    );
    System.assertEquals(
      UserInfo.getUserId(),
      overflowRequests[0].recipientId
    );
  }
}