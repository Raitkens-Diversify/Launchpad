/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class NotificationDigestModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationDigestModels.DigestDeliveryRequest digestDeliveryRequest = new NotificationDigestModels.DigestDeliveryRequest();
    NotificationDigestModels.ConsolidatedMessage consolidatedMessage = new NotificationDigestModels.ConsolidatedMessage();
    NotificationDigestModels.DigestDeliveryContext digestDeliveryContext = new NotificationDigestModels.DigestDeliveryContext();
    NotificationDigestModels.DeliveryResult deliveryResult = new NotificationDigestModels.DeliveryResult();

    System.assertNotEquals(null, digestDeliveryRequest.logIds);
    System.assertEquals(0, digestDeliveryRequest.attemptNumber);
    System.assertEquals(0, consolidatedMessage.itemCount);
    System.assertNotEquals(null, digestDeliveryContext.request);
    System.assertNotEquals(null, digestDeliveryContext.logs);
    System.assertEquals(null, digestDeliveryContext.channelSettings);
    System.assertEquals(false, deliveryResult.success);
    System.assertEquals(false, deliveryResult.suppressed);
  }

  @IsTest
  static void withAttemptNumber_createsRetryRequest() {
    NotificationDigestModels.DigestDeliveryRequest digestDeliveryRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestDeliveryRequest.recipientId = UserInfo.getUserId();
    digestDeliveryRequest.channel = 'in_app';
    digestDeliveryRequest.logIds.add(UserInfo.getUserId());

    NotificationDigestModels.DigestDeliveryRequest retryRequest = digestDeliveryRequest.withAttemptNumber(
      3
    );
    NotificationDigestModels.DigestDeliveryRequest nullAttemptRequest = digestDeliveryRequest.withAttemptNumber(
      null
    );

    System.assertEquals(3, retryRequest.attemptNumber);
    System.assertEquals(0, nullAttemptRequest.attemptNumber);
    System.assertEquals(1, retryRequest.logIds.size());
  }
}