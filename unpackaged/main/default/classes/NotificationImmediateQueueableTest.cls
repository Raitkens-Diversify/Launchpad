/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationImmediateQueueableTest {
  @IsTest
  static void deliverEmailImmediateMarksLogSent() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Immediate email retry test',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Notification_Rule__c = rule.Id
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );

    Test.startTest();
    System.enqueueJob(new NotificationDeliveryQueueable(request));
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
  static void deliverInAppImmediateMarksLogSentWhenCustomNotificationSkipped() {
    NotificationCustomNotificationService.testSkipSend = true;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Task taskRecord = new Task(
      Subject = 'Immediate in-app retry test',
      WhatId = context.household.Id,
      Status = 'Not Started',
      ActivityDate = Date.today()
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_IN_APP,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Notification_Rule__c = rule.Id,
      Title__c = 'Immediate in-app retry test',
      Body__c = 'Open the notification to view details.'
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );

    Test.startTest();
    System.enqueueJob(new NotificationDeliveryQueueable(request));
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
  }

  @IsTest
  static void failureMarksLogsFailedAfterMaxAttempts() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(context.household.Id),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Notification_Rule__c = rule.Id,
      Delivery_Attempt_Count__c = NotificationConstants.MAX_IMMEDIATE_DELIVERY_ATTEMPTS -
        1
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    new NotificationDeliveryService().handleFailure(
      request,
      new NotificationDeliveryService.NotificationDeliveryException(
        'Simulated immediate delivery failure'
      )
    );

    Notification_Log__c updatedLog = [
      SELECT Status__c, Error_Message__c, Delivery_Attempt_Count__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_FAILED, updatedLog.Status__c);
    System.assert(
      updatedLog.Error_Message__c.contains('Simulated immediate delivery failure')
    );
    System.assertEquals(
      NotificationConstants.MAX_IMMEDIATE_DELIVERY_ATTEMPTS,
      updatedLog.Delivery_Attempt_Count__c
    );
  }

  @IsTest
  static void scheduleImmediateRetryEnqueuesAnotherAttempt() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Retry invocable test',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Notification_Rule__c = rule.Id
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    Test.startTest();
    NotificationDeliveryService.scheduleRetryOrFail(
      new List<Notification_Log__c>{ logRecord },
      'Flow delivery failed'
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Delivery_Attempt_Count__c, Error_Message__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    System.assertEquals(1, updatedLog.Delivery_Attempt_Count__c);
  }
}