/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationCenterEventPublisherTest {
  @IsTest
  static void publishDigestDeliveryGroupsEnqueuesOneJobPerDeliveryGroup() {
    NotificationCenterEventPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest item one',
      null,
      null
    );
    Notification_Log__c secondLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest item two',
      null,
      null
    );

    NotificationDigestModels.DigestDeliveryRequest inAppRequest = NotificationDeliveryGroupingService.buildDeliveryRequest(
      new List<Notification_Log__c>{ firstLog },
      NotificationConstants.DIGEST_FREQUENCY_DAILY,
      0
    );
    NotificationDigestModels.DigestDeliveryRequest emailRequest = NotificationDeliveryGroupingService.buildDeliveryRequest(
      new List<Notification_Log__c>{ secondLog },
      NotificationConstants.DIGEST_FREQUENCY_DAILY,
      0
    );

    Test.startTest();
    NotificationCenterEventPublisher.publishDigestDeliveryGroups(
      new List<NotificationDigestModels.DigestDeliveryRequest>{
        inAppRequest,
        emailRequest
      }
    );
    Test.stopTest();

    System.assertEquals(
      2,
      NotificationCenterEventPublisher.testPublishedEventCount,
      'Expected one delivery job per recipient/channel group.'
    );
  }
}