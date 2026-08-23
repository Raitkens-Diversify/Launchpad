/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationDeliveryEnqueueServiceTest {
  @IsTest
  static void enqueueImmediateLogIdsDedupesAndSkipsDigest() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c immediateRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    Notification_Rule__c digestRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Notification_Log__c immediateLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Immediate enqueue test',
      null,
      immediateRule.Id
    );
    Notification_Log__c digestLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest enqueue test',
      null,
      digestRule.Id
    );

    List<Notification_Log__c> loadedLogs = new NotificationLogRepository().selectLogsByIds(
      new List<Id>{ immediateLog.Id, digestLog.Id }
    );
    System.assertEquals(
      1,
      NotificationDeliveryRequestBuilder.fromLogs(loadedLogs, true).size()
    );

    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;

    Test.startTest();
    NotificationDeliveryEnqueueService.enqueueImmediateLogIdStrings(
      new List<String>{
        String.valueOf(immediateLog.Id),
        String.valueOf(immediateLog.Id),
        String.valueOf(digestLog.Id)
      }
    );
    Test.stopTest();

    System.assertEquals(1, NotificationDeliveryDispatcher.testEnqueuedJobCount);
  }

  @IsTest
  static void enqueueLogIdsIncludesDigestRequests() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c digestRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    digestRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(digestRule);

    Notification_Log__c digestLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest enqueue test',
      null,
      digestRule.Id
    );

    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;

    Test.startTest();
    NotificationDeliveryEnqueueService.enqueueLogIds(new List<Id>{ digestLog.Id });
    Test.stopTest();

    System.assertEquals(1, NotificationDeliveryDispatcher.testEnqueuedJobCount);
  }
}