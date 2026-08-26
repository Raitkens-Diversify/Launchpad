/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 */
@IsTest
private class NotificationDeliveryDispatcherTest {
  @IsTest
  static void syncEnqueueStillProcessesMultipleRequestsDirectly() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);
    Notification_Log__c firstLog = createQueuedDigestLog(context, rule);
    Notification_Log__c secondLog = createQueuedDigestLog(context, rule);

    NotificationDeliveryDispatcher.enqueueRequests(
      new List<NotificationDeliveryModels.DeliveryRequest>{
        buildDigestRequest(context.recipientUser.Id, firstLog.Id),
        buildDigestRequest(context.recipientUser.Id, secondLog.Id)
      }
    );

    System.assertEquals(
      2,
      NotificationDeliveryDispatcher.testEnqueuedJobCount,
      'Expected synchronous enqueue to start one delivery job per request.'
    );

    Test.startTest();
    Test.stopTest();
  }

  @IsTest
  static void batchDigestEnqueueUsesSingleChainForMultipleDeliveryGroups() {
    NotificationCenterEventPublisher.resetForTest();
    NotificationCustomNotificationService.testSkipSend = true;

    NotificationTestDataFactory.NotificationTestContext firstContext = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.NotificationTestContext secondContext = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Rule__c firstRule = createDigestRule(
      firstContext,
      NotificationConstants.CHANNEL_EMAIL
    );
    Notification_Rule__c secondRule = createDigestRule(
      secondContext,
      NotificationConstants.CHANNEL_EMAIL
    );

    Case firstCase = createOwnedCase(firstContext);
    Case secondCase = createOwnedCase(secondContext);
    Notification_Log__c firstLog = createQueuedDigestLog(
      firstContext,
      firstRule,
      firstCase.Id
    );
    Notification_Log__c secondLog = createQueuedDigestLog(
      secondContext,
      secondRule,
      secondCase.Id
    );

    Test.startTest();
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_DAILY),
      200
    );
    Test.stopTest();

    List<AsyncApexJob> batchJobs = [
      SELECT Status, NumberOfErrors, ExtendedStatus
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'NotificationDigestRuleBatch'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    System.assertEquals(1, batchJobs.size(), 'Expected digest batch to run.');
    System.assertEquals(
      0,
      batchJobs[0].NumberOfErrors,
      'Batch should complete without queueable limit errors: ' +
        batchJobs[0].ExtendedStatus
    );

    firstLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :firstLog.Id
    ];
    secondLog = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :secondLog.Id
    ];

    System.assertEquals(
      NotificationConstants.STATUS_SENT,
      firstLog.Status__c,
      'Expected first digest log to be delivered after batch processing.'
    );
    System.assertEquals(
      NotificationConstants.STATUS_SENT,
      secondLog.Status__c,
      'Expected second digest log to be delivered after batch processing.'
    );
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
    rule.Digest_Frequency_Hour__c = NotificationDigestTimezoneService.currentDigestHourValue();
    NotificationTestDataFactory.updateRecord(rule);
    return rule;
  }

  private static Notification_Log__c createQueuedDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Notification_Rule__c rule
  ) {
    Case caseRecord = createOwnedCase(context);
    return createQueuedDigestLog(context, rule, caseRecord.Id);
  }

  private static Notification_Log__c createQueuedDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Notification_Rule__c rule,
    Id sourceRecordId
  ) {
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      rule.Channel__c,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest batch item',
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(sourceRecordId);
    NotificationTestDataFactory.updateRecord(logRecord);
    return logRecord;
  }

  private static Case createOwnedCase(
    NotificationTestDataFactory.NotificationTestContext context
  ) {
    Case caseRecord = new Case(
      Subject = 'Digest dispatcher case',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    return caseRecord;
  }

  private static NotificationDeliveryModels.DeliveryRequest buildDigestRequest(
    Id recipientId,
    Id logId
  ) {
    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = recipientId;
    digestRequest.channel = NotificationConstants.CHANNEL_EMAIL;
    digestRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    digestRequest.logIds = new List<Id>{ logId };
    digestRequest.cadence = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    digestRequest.attemptNumber = 0;
    return NotificationDeliveryRequestBuilder.fromDigest(digestRequest);
  }

  @IsTest
  static void enqueueDigestRequests_convertsDigestRequestsAndEnqueues() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);
    Notification_Log__c logRecord = createQueuedDigestLog(context, rule);

    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = context.recipientUser.Id;
    digestRequest.channel = NotificationConstants.CHANNEL_EMAIL;
    digestRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    digestRequest.logIds = new List<Id>{ logRecord.Id };
    digestRequest.cadence = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    digestRequest.attemptNumber = 0;

    NotificationDeliveryDispatcher.enqueueDigestRequests(
      new List<NotificationDigestModels.DigestDeliveryRequest>{ digestRequest }
    );

    System.assertEquals(1, NotificationDeliveryDispatcher.testEnqueuedJobCount);
  }

  @IsTest
  static void enqueueRequests_noopsForNullOrEmptyLists() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;

    NotificationDeliveryDispatcher.enqueueRequests(null);
    NotificationDeliveryDispatcher.enqueueRequests(
      new List<NotificationDeliveryModels.DeliveryRequest>()
    );
    NotificationDeliveryDispatcher.enqueueDigestRequests(null);
    NotificationDeliveryDispatcher.enqueueDigestRequests(
      new List<NotificationDigestModels.DigestDeliveryRequest>()
    );

    System.assertEquals(0, NotificationDeliveryDispatcher.testEnqueuedJobCount);
  }

  @IsTest
  static void chainRemainingJobs_processesRemainingDeliveryRequests() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationDeliveryDispatcher.testChainExecutionCount = 0;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);

    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();
    for (Integer index = 0; index < 3; index++) {
      Notification_Log__c logRecord = createQueuedDigestLog(context, rule);
      requests.add(
        buildDigestRequest(context.recipientUser.Id, logRecord.Id)
      );
    }

    NotificationDeliveryDispatcher.chainRemainingJobs(requests, 1);

    System.assertEquals(1, NotificationDeliveryDispatcher.testChainExecutionCount);
  }

  @IsTest
  static void enqueueChunk_overflowEnqueuesChainWhenExceedingJobLimit() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);
    Notification_Log__c logRecord = createQueuedDigestLog(context, rule);

    Integer requestCount =
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION + 5;
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (Integer index = 0; index < requestCount; index++) {
      requests.add(
        buildDigestRequest(context.recipientUser.Id, logRecord.Id)
      );
    }

    List<NotificationDeliveryModels.DeliveryRequest> overflowRequests = new List<NotificationDeliveryModels.DeliveryRequest>();

    Test.startTest();
    NotificationDeliveryDispatcher.enqueueChunk(requests, 0, overflowRequests);

    System.assertEquals(
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION,
      NotificationDeliveryDispatcher.testEnqueuedJobCount
    );
    System.assertEquals(5, overflowRequests.size());

    System.enqueueJob(
      new NotificationDeliveryChainQueueable(overflowRequests, 0)
    );
    Test.stopTest();
  }

  @IsTest
  static void enqueueRequests_neverExceedsQueueableGovernorLimit() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_IN_APP);
    Notification_Log__c logRecord = createQueuedDigestLog(context, rule);

    Integer requestCount =
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION + 7;
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();

    for (Integer index = 0; index < requestCount; index++) {
      requests.add(
        buildDigestRequest(context.recipientUser.Id, logRecord.Id)
      );
    }

    Test.startTest();
    NotificationDeliveryDispatcher.enqueueRequests(requests);
    Integer queueableJobsAdded = Limits.getQueueableJobs();
    Test.stopTest();

    System.assert(
      queueableJobsAdded <= Limits.getLimitQueueableJobs(),
      'Expected enqueueRequests to stay within the queueable governor limit, but added ' +
        queueableJobsAdded +
        ' jobs.'
    );
    System.assert(
      NotificationDeliveryDispatcher.testEnqueuedJobCount <=
        Limits.getLimitQueueableJobs(),
      'Expected tracked enqueue count to remain within the queueable governor limit.'
    );
    System.assertEquals(
      0,
      NotificationGovernorLimitService.loggedLimitMessages.size(),
      'Unexpected governor limit exceptions: ' +
        String.join(NotificationGovernorLimitService.loggedLimitMessages, '; ')
    );
  }

  @IsTest
  static void enqueueRequests_deliversOverflowInlineWhenQueueableBudgetIsExhausted() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testRemainingQueueableBudgetOverride = 0;
    NotificationCustomNotificationService.testSkipSend = true;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_IN_APP);
    Notification_Log__c logRecord = createQueuedDigestLog(context, rule);

    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>{
      buildDigestRequest(context.recipientUser.Id, logRecord.Id)
    };

    Test.startTest();
    NotificationDeliveryDispatcher.enqueueRequests(requests);
    Test.stopTest();

    logRecord = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    System.assertEquals(
      NotificationConstants.STATUS_SENT,
      logRecord.Status__c,
      'Expected overflow inline delivery to mark the digest log as sent.'
    );
    System.assertEquals(
      0,
      NotificationDeliveryDispatcher.testEnqueuedJobCount,
      'Expected inline overflow delivery to avoid queueable enqueue when budget is exhausted.'
    );
  }

  @IsTest
  static void enqueueRequests_batchesOverflowEmailsWithinInvocationLimit() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testRemainingQueueableBudgetOverride = 0;
    NotificationEmailDeliveryService.resetTestState();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Integer emailCount =
      NotificationConstants.MAX_EMAIL_INVOCATIONS_PER_TRANSACTION + 1;
    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>();
    List<Id> logIds = new List<Id>();

    for (Integer index = 0; index < emailCount; index++) {
      Case caseRecord = new Case(
        Subject = 'Overflow email ' + index,
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
        Notification_Rule__c = rule.Id,
        Title__c = 'Overflow ' + index,
        Body__c = 'Body ' + index
      );
      NotificationTestDataFactory.insertRecord(logRecord);
      logIds.add(logRecord.Id);
      requests.add(NotificationDeliveryRequestBuilder.fromLogId(logRecord.Id));
    }

    Test.startTest();
    NotificationDeliveryDispatcher.enqueueRequests(requests);
    Test.stopTest();

    System.assert(
      NotificationEmailDeliveryService.testSendEmailInvocationCount <=
        NotificationConstants.MAX_EMAIL_INVOCATIONS_PER_TRANSACTION,
      'Overflow email delivery must batch sendEmail calls within the 10-invocation limit.'
    );

    List<Notification_Log__c> deliveredLogs = [
      SELECT Status__c, Error_Message__c
      FROM Notification_Log__c
      WHERE Id IN :logIds
    ];

    for (Notification_Log__c logRecord : deliveredLogs) {
      System.assertEquals(
        false,
        NotificationGovernorLimitService.isEmailInvocationLimitMessage(
          logRecord.Error_Message__c
        ),
        'Overflow delivery must not fail logs with Too many Email Invocations.'
      );
    }
  }

  @IsTest
  static void configuredDeliveryChunkPlusChainReserveStaysWithinQueueableLimit() {
    System.assert(
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION +
        NotificationConstants.QUEUEABLE_CHAIN_RESERVE_SLOTS <=
      Limits.getLimitQueueableJobs(),
      'Pre-fix configurations that set MAX_DIGEST_JOBS_PER_TRANSACTION to 50 could enqueue 51 jobs (50 delivery + 1 chain).'
    );
  }

  @IsTest
  static void deliveryChainQueueableExecutesRemainingJobs() {
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;
    NotificationDeliveryDispatcher.testChainExecutionCount = 0;
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = createDigestRule(context, NotificationConstants.CHANNEL_EMAIL);
    Notification_Log__c logRecord = createQueuedDigestLog(context, rule);

    List<NotificationDeliveryModels.DeliveryRequest> requests = new List<NotificationDeliveryModels.DeliveryRequest>{
      buildDigestRequest(context.recipientUser.Id, logRecord.Id)
    };

    NotificationDeliveryDispatcher.chainRemainingJobs(requests, 0);
    System.assert(
      NotificationDeliveryDispatcher.testChainExecutionCount > 0,
      'Expected chainRemainingJobs to execute at least once.'
    );

    new NotificationDeliveryChainQueueable(requests, 0).execute((QueueableContext) null);
    new NotificationDeliveryChainQueueable(requests).execute((QueueableContext) null);
    new NotificationDeliveryChainQueueable(null, null).execute((QueueableContext) null);
  }
}