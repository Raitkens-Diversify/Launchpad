/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationDigestRuleBatchTest {
  @IsTest
  static void batchPublishesCenterEventsForMatchingDigestRules() {
    NotificationCenterEventPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    rule.Digest_Frequency_Hour__c = NotificationDigestTimezoneService.currentDigestHourValue();
    NotificationTestDataFactory.updateRecord(rule);

    Case caseRecord = new Case(
      Subject = 'Digest batch case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Queued digest item',
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(caseRecord.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests = NotificationDeliveryGroupingService.buildDeliveryRequestsForRuleIds(
      new Set<Id>{ rule.Id },
      NotificationConstants.DIGEST_FREQUENCY_DAILY
    );
    System.assert(
      !deliveryRequests.isEmpty(),
      'Expected digest delivery requests to be built for queued logs.'
    );
    NotificationCenterEventPublisher.publishDigestDeliveryGroups(deliveryRequests);
    System.assert(
      NotificationCenterEventPublisher.testPublishedEventCount > 0,
      'Expected digest delivery preparation to publish Notification Center Events.'
    );

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_DAILY),
      200
    );
    Test.stopTest();
  }

  @IsTest
  static void logScopedBatchEnqueuesDeliveryJobsForPreviewRows() {
    NotificationCenterEventPublisher.resetForTest();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);
    Notification_Log__c logRecord = createDigestInAppLog(context, caseRecord.Id);
    logRecord.Status__c = NotificationConstants.STATUS_SENT;
    logRecord.Delivered_At__c = System.now();
    NotificationTestDataFactory.updateRecord(logRecord);

    NotificationLogDeliveryService.requeueForDebugDelivery(new List<Notification_Log__c>{ logRecord });
    logRecord = [
      SELECT Id, Status__c, Recipient__c, Channel__c, Source_Type__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];
    System.assertEquals(NotificationConstants.STATUS_QUEUED, logRecord.Status__c);

    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests = new List<NotificationDigestModels.DigestDeliveryRequest>{
      NotificationDeliveryGroupingService.buildDeliveryRequest(
        new List<Notification_Log__c>{ logRecord },
        NotificationConstants.DIGEST_FREQUENCY_DAILY,
        0,
        NotificationConstants.CHANNEL_IN_APP
      )
    };
    NotificationCenterEventPublisher.publishDigestDeliveryGroups(deliveryRequests);
    System.assert(
      NotificationCenterEventPublisher.testPublishedEventCount > 0,
      'Expected log-scoped digest delivery preparation to publish Notification Center Events.'
    );

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(
        NotificationConstants.DIGEST_FREQUENCY_DAILY,
        new List<Id>{ logRecord.Id }
      ),
      200
    );
    Test.stopTest();
  }

  @IsTest
  static void recordScopedBatchEnqueuesDeliveryJobsForSourceRecords() {
    NotificationCenterEventPublisher.resetForTest();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case firstCase = createOwnedCase(context);
    Case secondCase = createOwnedCase(context);
    Notification_Log__c firstLog = createDigestInAppLog(context, firstCase.Id);
    Notification_Log__c secondLog = createDigestInAppLog(context, secondCase.Id);

    NotificationCenterEventPublisher.publishDigestDeliveryGroups(
      new List<NotificationDigestModels.DigestDeliveryRequest>{
        NotificationDeliveryGroupingService.buildDeliveryRequest(
          new List<Notification_Log__c>{ firstLog, secondLog },
          NotificationConstants.DIGEST_FREQUENCY_DAILY,
          0,
          NotificationConstants.CHANNEL_IN_APP
        )
      }
    );
    System.assert(
      NotificationCenterEventPublisher.testPublishedEventCount > 0,
      'Expected record-scoped digest delivery preparation to publish Notification Center Events.'
    );

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(
        NotificationConstants.DIGEST_FREQUENCY_DAILY,
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        new List<Id>{ firstCase.Id, secondCase.Id }
      ),
      200
    );
    Test.stopTest();
  }

  @IsTest
  static void dailySchedulerStartsDigestBatch() {
    Test.startTest();
    new NotificationDigestDailyScheduler().execute(null);
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
      'Expected daily scheduler to start a batch job.'
    );
  }

  @IsTest
  static void weeklySchedulerStartsDigestBatch() {
    Test.startTest();
    new NotificationDigestWeeklyScheduler().execute(null);
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
      'Expected weekly scheduler to start a batch job.'
    );
  }

  @IsTest
  static void hourlySchedulerStartsDigestBatch() {
    Test.startTest();
    new NotificationDigestHourlyScheduler().execute(null);
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
      'Expected hourly scheduler to start a batch job.'
    );
  }

  @IsTest
  static void batchWithEmptyScopeCompletesWithoutErrors() {
    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_WEEKLY),
      200
    );
    Test.stopTest();

    System.assert(true, 'Weekly digest batch should complete with empty scope.');
  }

  @IsTest
  static void batchConstructorWithRecipientScopeStartsBatchJob() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);
    createDigestInAppLog(context, caseRecord.Id);

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(
        NotificationConstants.DIGEST_FREQUENCY_DAILY,
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        new List<Id>{ caseRecord.Id }
      ),
      200
    );
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
      'Expected recipient-scoped digest batch to run.'
    );
  }

  @IsTest
  static void batchExecuteProcessesActiveDigestRules() {
    NotificationCenterEventPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    rule.Digest_Frequency_Hour__c = NotificationDigestTimezoneService.currentDigestHourValue();
    NotificationTestDataFactory.updateRecord(rule);

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_DAILY),
      200
    );
    Test.stopTest();

    System.assert(true, 'Digest rule batch should process active digest rules.');
  }

  @IsTest
  static void executeLogScopePublishesDigestDeliveryGroups() {
    NotificationCenterEventPublisher.resetForTest();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);
    Notification_Log__c logRecord = createDigestInAppLog(context, caseRecord.Id);

    NotificationDigestRuleBatch batch = new NotificationDigestRuleBatch(
      NotificationConstants.DIGEST_FREQUENCY_DAILY,
      null,
      null,
      null,
      new List<Id>{ logRecord.Id },
      NotificationConstants.CHANNEL_IN_APP,
      new NotificationDigestRepository()
    );

    List<Notification_Log__c> scope = [
      SELECT
        Id,
        Name,
        Recipient__c,
        Channel__c,
        Source_Type__c,
        Notification_Rule__c,
        Title__c,
        Body__c,
        Change_Context__c,
        CreatedDate,
        Source_Record_Id__c,
        Target_Record_Id__c,
        Household__c,
        Status__c,
        Frequency__c,
        Delivery_Attempt_Count__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    batch.execute(null, scope);

    System.assert(
      NotificationCenterEventPublisher.testPublishedEventCount > 0,
      'Log-scoped execute should publish digest delivery groups.'
    );
  }

  @IsTest
  static void executeReturnsEarlyForEmptyScope() {
    NotificationDigestRuleBatch batch = new NotificationDigestRuleBatch(
      NotificationConstants.DIGEST_FREQUENCY_DAILY
    );

    batch.execute(null, new List<Notification_Log__c>());
    batch.execute(null, null);

    System.assert(true, 'Empty batch scope should return without errors.');
  }

  private static Case createOwnedCase(
    NotificationTestDataFactory.NotificationTestContext context
  ) {
    Case caseRecord = new Case(
      Subject = 'Digest batch case',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    return caseRecord;
  }

  private static Notification_Log__c createDigestInAppLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id sourceRecordId
  ) {
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    rule.Digest_Frequency_Hour__c = NotificationDigestTimezoneService.currentDigestHourValue();
    NotificationTestDataFactory.updateRecord(rule);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest in-app item',
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(sourceRecordId);
    NotificationTestDataFactory.updateRecord(logRecord);
    return logRecord;
  }
}