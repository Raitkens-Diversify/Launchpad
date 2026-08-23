/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Enqueues digest delivery groups via the unified delivery dispatcher.
 */
public without sharing class NotificationCenterEventPublisher {
  @TestVisible
  private static Integer testPublishedEventCount = 0;

  @TestVisible
  static void resetForTest() {
    testPublishedEventCount = 0;
  }

  public static void publishDigestDeliveryGroups(
    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests
  ) {
    if (deliveryRequests == null || deliveryRequests.isEmpty()) {
      return;
    }

    testPublishedEventCount += deliveryRequests.size();
    NotificationDeliveryDispatcher.enqueueDigestRequests(deliveryRequests);
  }
}