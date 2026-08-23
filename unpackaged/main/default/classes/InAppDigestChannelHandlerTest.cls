/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class InAppDigestChannelHandlerTest {
  @IsTest
  static void deliverSendsIndividualPreferenceNotifications() {
    NotificationCustomNotificationService.testSkipSend = true;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    List<Notification_Log__c> logs = new List<Notification_Log__c>{
      buildLog('First task update'),
      buildLog('Second task update')
    };

    NotificationDigestModels.DigestDeliveryRequest request = new NotificationDigestModels.DigestDeliveryRequest();
    request.recipientId = context.recipientUser.Id;
    request.channel = NotificationConstants.CHANNEL_IN_APP;
    request.sourceType = NotificationConstants.OBJECT_TYPE_TASK;

    NotificationDigestModels.DigestDeliveryContext deliveryContext = new NotificationDigestModels.DigestDeliveryContext();
    deliveryContext.request = request;
    deliveryContext.logs = logs;

    Test.startTest();
    NotificationDigestModels.DeliveryResult result = new InAppDigestChannelHandler().deliver(
      deliveryContext
    );
    Test.stopTest();

    System.assertEquals(true, result.success);
  }

  private static Notification_Log__c buildLog(String body) {
    return new Notification_Log__c(
      Title__c = body,
      Body__c = body,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK
    );
  }
}