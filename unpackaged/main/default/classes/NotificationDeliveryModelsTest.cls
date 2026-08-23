/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class NotificationDeliveryModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationDeliveryModels.DeliveryRequest deliveryRequest = new NotificationDeliveryModels.DeliveryRequest();
    NotificationDeliveryModels.DeliveryContext deliveryContext = new NotificationDeliveryModels.DeliveryContext();

    System.assertNotEquals(null, deliveryRequest.logIds);
    System.assertEquals(0, deliveryRequest.attemptNumber);
    System.assertEquals(false, deliveryRequest.deliverIndividually);
    System.assertNotEquals(null, deliveryContext.request);
    System.assertNotEquals(null, deliveryContext.logs);
  }

  @IsTest
  static void withAttemptNumber_createsRetryRequest() {
    NotificationDeliveryModels.DeliveryRequest deliveryRequest = new NotificationDeliveryModels.DeliveryRequest();
    deliveryRequest.logIds.add(UserInfo.getUserId());
    deliveryRequest.recipientId = UserInfo.getUserId();
    deliveryRequest.channel = 'in_app';
    deliveryRequest.deliverIndividually = true;

    NotificationDeliveryModels.DeliveryRequest retryRequest = deliveryRequest.withAttemptNumber(2);

    System.assertEquals(2, retryRequest.attemptNumber);
    System.assertEquals(true, retryRequest.deliverIndividually);
    System.assertEquals(1, retryRequest.logIds.size());
  }
}