/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationDigestDeliveryQueueableTest {
  @IsTest
  static void deliverEmailDigestMarksLogsSent() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(
      context,
      NotificationConstants.CHANNEL_EMAIL
    );
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest email item',
      null,
      rule.Id
    );

    NotificationDigestModels.DigestDeliveryRequest request = buildRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ logRecord.Id }
    );

    Test.startTest();
    System.enqueueJob(
      new NotificationDeliveryQueueable(
        NotificationDeliveryRequestBuilder.fromDigest(request)
      )
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Delivered_At__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    System.assertNotEquals(null, updatedLog.Delivered_At__c);
  }

  @IsTest
  static void deliverInAppDigestIsSuppressed() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(
      context,
      NotificationConstants.CHANNEL_IN_APP
    );
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest in-app item',
      null,
      rule.Id
    );

    NotificationDigestModels.DigestDeliveryRequest request = buildRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ logRecord.Id }
    );

    Test.startTest();
    System.enqueueJob(
      new NotificationDeliveryQueueable(
        NotificationDeliveryRequestBuilder.fromDigest(request)
      )
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Suppression_Reason__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SUPPRESSED, updatedLog.Status__c);
    System.assertEquals(
      NotificationConstants.SUPPRESSION_USER_DIGEST_DISABLED,
      updatedLog.Suppression_Reason__c
    );
  }

  @IsTest
  static void deliverInAppDigestIsSuppressedForEventLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Rule__c rule = createDigestRule(
      context,
      NotificationConstants.CHANNEL_IN_APP
    );
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest suppressed item',
      null,
      rule.Id
    );

    NotificationDigestModels.DigestDeliveryRequest request = buildRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<Id>{ logRecord.Id }
    );

    Test.startTest();
    System.enqueueJob(
      new NotificationDeliveryQueueable(
        NotificationDeliveryRequestBuilder.fromDigest(request)
      )
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Suppression_Reason__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SUPPRESSED, updatedLog.Status__c);
    System.assertEquals(
      NotificationConstants.SUPPRESSION_USER_DIGEST_DISABLED,
      updatedLog.Suppression_Reason__c
    );
  }

  @IsTest
  static void failureMarksLogsFailedAfterMaxAttempts() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(
      context,
      NotificationConstants.CHANNEL_EMAIL
    );
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest failure item',
      null,
      rule.Id
    );

    NotificationDigestModels.DigestDeliveryRequest request = buildRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ logRecord.Id }
    );
    request.attemptNumber = NotificationConstants.MAX_DIGEST_DELIVERY_ATTEMPTS - 1;
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    new NotificationDeliveryService().handleFailure(
      NotificationDeliveryRequestBuilder.fromDigest(request),
      new NotificationDeliveryService.NotificationDeliveryException(
        'Simulated delivery failure'
      )
    );

    Notification_Log__c updatedLog = [
      SELECT Status__c, Error_Message__c, Delivery_Attempt_Count__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_FAILED, updatedLog.Status__c);
    System.assert(updatedLog.Error_Message__c.contains('Simulated delivery failure'));
    System.assertEquals(1, updatedLog.Delivery_Attempt_Count__c);
  }

  private static Notification_Rule__c createDigestRule(
    NotificationTestDataFactory.NotificationTestContext context,
    String channel
  ) {
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      channel,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(rule);
    return rule;
  }

  private static NotificationDigestModels.DigestDeliveryRequest buildRequest(
    Id recipientId,
    String channel,
    String sourceType,
    List<Id> logIds
  ) {
    NotificationDigestModels.DigestDeliveryRequest request = new NotificationDigestModels.DigestDeliveryRequest();
    request.recipientId = recipientId;
    request.channel = channel;
    request.sourceType = sourceType;
    request.logIds = logIds;
    request.cadence = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    request.attemptNumber = 0;
    return request;
  }
}