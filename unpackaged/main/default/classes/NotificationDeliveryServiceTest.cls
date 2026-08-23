/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Tests for unified notification delivery.
 */
@IsTest
private class NotificationDeliveryServiceTest {
  @IsTest
  static void deliverImmediateEmailMarksLogSent() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Unified delivery email test',
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
  static void deliverImmediateTaskEmailEnrichesHtmlBody() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Task taskRecord = new Task(
      Subject = 'HTML email task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Notification_Rule__c = rule.Id
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    Test.startTest();
    System.enqueueJob(
      new NotificationDeliveryQueueable(
        NotificationDeliveryRequestBuilder.fromLogId(logRecord.Id)
      )
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Body__c, Title__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    System.assertEquals('New task', updatedLog.Title__c);
    System.assert(updatedLog.Body__c.contains('<table'));
    System.assert(updatedLog.Body__c.contains('HTML email task'));
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

    Test.startTest();
    System.enqueueJob(
      new NotificationDeliveryQueueable(
        NotificationDeliveryRequestBuilder.fromLogId(logRecord.Id)
      )
    );
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
  }

  @IsTest
  static void immediateFailureMarksLogsFailedAfterMaxAttempts() {
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

    NotificationDeliveryService.simulateFailureForTest(
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
  static void scheduleRetryEnqueuesAnotherAttempt() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Retry delivery test',
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
      'Delivery failed'
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

  @IsTest
  static void deliverDefersImmediateDeliveryWhenSoqlBudgetInsufficient() {
    NotificationGovernorLimitService.resetTestState();
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
      Notification_Rule__c = rule.Id
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );
    NotificationGovernorLimitService.testForceInsufficientDeliveryBudget = true;
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    Test.startTest();
    new NotificationDeliveryService().deliver(request);
    Test.stopTest();

    Notification_Log__c updatedLog = [
      SELECT Status__c, Delivery_Attempt_Count__c, Error_Message__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    System.assertEquals(NotificationConstants.STATUS_PENDING, updatedLog.Status__c);
    System.assert(
      updatedLog.Delivery_Attempt_Count__c == null ||
        updatedLog.Delivery_Attempt_Count__c == 0,
      'Governor-limit deferral should not consume delivery attempts.'
    );
  }

  @IsTest
  static void scheduleRetryUsesDispatcherChunking() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
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
      Notification_Rule__c = rule.Id
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDeliveryService.skipRetryEnqueueForTest = false;

    Test.startTest();
    NotificationDeliveryService.scheduleRetryOrFail(
      new List<Notification_Log__c>{ logRecord },
      'Delivery failed'
    );
    Test.stopTest();

    System.assert(
      NotificationDeliveryDispatcher.testEnqueuedJobCount >= 1,
      'Expected immediate delivery retries to enqueue through the dispatcher.'
    );
  }

  @IsTest
  static void deliverConsolidatedEmailDigestUsesHtmlTableBody() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);

    Case firstCase = new Case(
      Subject = 'Consolidated digest case one',
      AccountId = context.household.Id
    );
    Case secondCase = new Case(
      Subject = 'Consolidated digest case two',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecords(new List<Case>{ firstCase, secondCase });

    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      null,
      null,
      rule.Id
    );
    firstLog.Source_Record_Id__c = String.valueOf(firstCase.Id);
    firstLog.Change_Context__c = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.CHANGE_TYPE_INSERT
      )
      .toJson();

    Notification_Log__c secondLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      null,
      null,
      rule.Id
    );
    secondLog.Source_Record_Id__c = String.valueOf(secondCase.Id);
    secondLog.Change_Context__c = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.CHANGE_TYPE_UPDATE
      )
      .toJson();
    update new List<Notification_Log__c>{ firstLog, secondLog };

    NotificationDeliveryModels.DeliveryRequest request = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ firstLog.Id, secondLog.Id }
    );

    Test.startTest();
    System.enqueueJob(new NotificationDeliveryQueueable(request));
    Test.stopTest();

    List<Notification_Log__c> updatedLogs = [
      SELECT Status__c, Delivered_At__c
      FROM Notification_Log__c
      WHERE Id IN :new Set<Id>{ firstLog.Id, secondLog.Id }
    ];

    for (Notification_Log__c updatedLog : updatedLogs) {
      System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
      System.assertNotEquals(null, updatedLog.Delivered_At__c);
    }
  }

  @IsTest
  static void deliverEmailDigestMarksLogsSent() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);
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

    NotificationDeliveryModels.DeliveryRequest request = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ logRecord.Id }
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
  static void deliverDigestIndividuallyUsesPerLogMessage() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);

    Task firstTask = new Task(
      Subject = 'First individual digest task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      ActivityDate = Date.today()
    );
    Task secondTask = new Task(
      Subject = 'Second individual digest task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      ActivityDate = Date.today()
    );
    NotificationTestDataFactory.insertRecords(new List<SObject>{ firstTask, secondTask });

    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'First individual digest item',
      'First body',
      rule.Id
    );
    firstLog.Source_Record_Id__c = String.valueOf(firstTask.Id);
    Notification_Log__c secondLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Second individual digest item',
      'Second body',
      rule.Id
    );
    secondLog.Source_Record_Id__c = String.valueOf(secondTask.Id);
    update new List<Notification_Log__c>{ firstLog, secondLog };

    NotificationDeliveryModels.DeliveryRequest firstRequest = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ firstLog.Id }
    );
    firstRequest.deliverIndividually = true;

    NotificationDeliveryModels.DeliveryRequest secondRequest = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ secondLog.Id }
    );
    secondRequest.deliverIndividually = true;

    Test.startTest();
    System.enqueueJob(new NotificationDeliveryQueueable(firstRequest));
    System.enqueueJob(new NotificationDeliveryQueueable(secondRequest));
    Test.stopTest();

    List<Notification_Log__c> updatedLogs = [
      SELECT Status__c, Delivered_At__c
      FROM Notification_Log__c
      WHERE Id IN :new Set<Id>{ firstLog.Id, secondLog.Id }
    ];
    System.assertEquals(2, updatedLogs.size());

    for (Notification_Log__c updatedLog : updatedLogs) {
      System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
      System.assertNotEquals(null, updatedLog.Delivered_At__c);
    }
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

    NotificationDeliveryModels.DeliveryRequest request = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ logRecord.Id }
    );

    Test.startTest();
    System.enqueueJob(new NotificationDeliveryQueueable(request));
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
  static void digestFailureMarksLogsFailedAfterMaxAttempts() {
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

    NotificationDeliveryModels.DeliveryRequest request = buildDigestRequest(
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ logRecord.Id }
    );
    request.attemptNumber = NotificationConstants.MAX_DIGEST_DELIVERY_ATTEMPTS - 1;
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    NotificationDeliveryService.simulateFailureForTest(
      request,
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

  @IsTest
  static void dispatcherGroupsDigestLogsByRecipientAndChannel() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(rule);

    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest item one',
      null,
      rule.Id
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
      rule.Id
    );

    Test.startTest();
    NotificationDeliveryDispatcher.enqueueLogIds(
      new List<Id>{ firstLog.Id, secondLog.Id }
    );
    Test.stopTest();

    List<Notification_Log__c> updatedLogs = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id IN :new Set<Id>{ firstLog.Id, secondLog.Id }
    ];
    System.assertEquals(2, updatedLogs.size());

    for (Notification_Log__c updatedLog : updatedLogs) {
      System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    }

    System.assertEquals(1, NotificationDeliveryDispatcher.testEnqueuedJobCount);
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

  private static NotificationDeliveryModels.DeliveryRequest buildDigestRequest(
    Id recipientId,
    String channel,
    String sourceType,
    List<Id> logIds
  ) {
    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = recipientId;
    digestRequest.channel = channel;
    digestRequest.sourceType = sourceType;
    digestRequest.logIds = logIds;
    digestRequest.cadence = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    digestRequest.attemptNumber = 0;
    return NotificationDeliveryRequestBuilder.fromDigest(digestRequest);
  }

  @IsTest
  static void logDeliveryServiceMarksSentSuppressedFailedAndRequeues() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Log delivery service item',
      null,
      null
    );

    System.assertEquals(
      true,
      NotificationLogDeliveryService.isDeliverableStatus(
        NotificationConstants.STATUS_QUEUED
      )
    );
    System.assertEquals(
      false,
      NotificationLogDeliveryService.isDeliverableStatus(
        NotificationConstants.STATUS_SENT
      )
    );

    System.assertEquals(
      1,
      NotificationLogDeliveryService.markSent(new List<Notification_Log__c>{ logRecord })
    );

    logRecord = [
      SELECT Id, Status__c, Delivered_At__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SENT, logRecord.Status__c);
    System.assertNotEquals(null, logRecord.Delivered_At__c);

    NotificationLogDeliveryService.markSuppressed(
      new List<Notification_Log__c>{ logRecord },
      NotificationConstants.SUPPRESSION_USER_IMMEDIATE_DISABLED
    );

    logRecord = [
      SELECT Id, Status__c, Suppression_Reason__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_SUPPRESSED, logRecord.Status__c);

    logRecord = [
      SELECT Id, Status__c, Delivery_Attempt_Count__c, Error_Message__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    NotificationLogDeliveryService.markFailed(
      new List<Notification_Log__c>{ logRecord },
      'Simulated failure'
    );
    NotificationLogDeliveryService.incrementAttemptCounts(
      new List<Notification_Log__c>{ logRecord }
    );

    logRecord = [
      SELECT Id, Status__c, Delivery_Attempt_Count__c, Error_Message__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_FAILED, logRecord.Status__c);
    System.assertEquals(1, logRecord.Delivery_Attempt_Count__c);

    System.assertEquals(
      1,
      NotificationLogDeliveryService.requeueForDebugDelivery(
        new List<Notification_Log__c>{ logRecord }
      )
    );
  }

  @IsTest
  static void deliverImmediateWithMultipleChannelsDeliversIndividually() {
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Case caseRecord = new Case(
      Subject = 'Multi-channel immediate case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c emailLog = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Title__c = 'Email item',
      Body__c = 'Email body'
    );
    Notification_Log__c inAppLog = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_IN_APP,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Title__c = 'In-app item',
      Body__c = 'In-app body'
    );
    NotificationTestDataFactory.insertRecords(new List<SObject>{ emailLog, inAppLog });

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogs(
      new List<Notification_Log__c>{ emailLog, inAppLog },
      true
    )[0];

    Test.startTest();
    new NotificationDeliveryService().deliver(request);
    Test.stopTest();

    List<Notification_Log__c> updatedLogs = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id IN :new Set<Id>{ emailLog.Id, inAppLog.Id }
    ];

    for (Notification_Log__c updatedLog : updatedLogs) {
      System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    }
  }

  @IsTest
  static void handleFailureDefersWhenGovernorLimitFailure() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_PENDING,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Governor limit failure',
      null,
      null
    );

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    NotificationDeliveryService.simulateFailureForTest(
      request,
      new LimitException()
    );

    Notification_Log__c updatedLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_PENDING, updatedLog.Status__c);
  }

  @IsTest
  static void deliverDigestDoesNotExpandWeeklyLogsIntoHourlyDelivery() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Rule__c hourlyRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    hourlyRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_HOURLY;
    NotificationTestDataFactory.updateRecord(hourlyRule);

    Notification_Rule__c weeklyRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    weeklyRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_WEEKLY;
    NotificationTestDataFactory.updateRecord(weeklyRule);

    Task taskRecord = new Task(
      Subject = 'Cadence isolation task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c hourlyLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Hourly digest item',
      null,
      hourlyRule.Id
    );
    hourlyLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    NotificationTestDataFactory.updateRecord(hourlyLog);

    Notification_Log__c weeklyLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Weekly digest item',
      null,
      weeklyRule.Id
    );
    weeklyLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    NotificationTestDataFactory.updateRecord(weeklyLog);

    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = context.recipientUser.Id;
    digestRequest.channel = NotificationConstants.CHANNEL_EMAIL;
    digestRequest.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    digestRequest.logIds = new List<Id>{ hourlyLog.Id };
    digestRequest.cadence = NotificationConstants.DIGEST_FREQUENCY_HOURLY;
    digestRequest.attemptNumber = 0;

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromDigest(
      digestRequest
    );

    Test.startTest();
    new NotificationDeliveryService().deliver(request);
    Test.stopTest();

    Notification_Log__c updatedHourlyLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :hourlyLog.Id
    ];
    Notification_Log__c updatedWeeklyLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :weeklyLog.Id
    ];

    System.assertEquals(NotificationConstants.STATUS_SENT, updatedHourlyLog.Status__c);
    System.assertEquals(
      NotificationConstants.STATUS_QUEUED,
      updatedWeeklyLog.Status__c,
      'Weekly digest logs must not be delivered by hourly digest runs.'
    );
  }

  @IsTest
  static void deliverNoopsForNullOrEmptyRequest() {
    new NotificationDeliveryService().deliver(null);

    NotificationDeliveryModels.DeliveryRequest emptyRequest = new NotificationDeliveryModels.DeliveryRequest();
    emptyRequest.logIds = new List<Id>();
    new NotificationDeliveryService().deliver(emptyRequest);

    System.assert(true, 'Null or empty delivery requests should no-op safely.');
  }
}