/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 */
@IsTest(IsParallel=false)
private class NotificationPrepareStartQueueableTest {
  @IsTest
  static void enqueuePreparesSourceRecordInFreshTransaction() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Deferred Prepare Task',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      NotificationPrepareStartQueueable.enqueue(
        NotificationConstants.OBJECT_TYPE_TASK,
        String.valueOf(taskRecord.Id),
        null
      );
    }
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
    ];

    System.assert(
      !logs.isEmpty(),
      'Expected notification logs to be created during deferred prepare.'
    );
  }

  @IsTest
  static void executeQueueableCreatesLogs() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationPrepareStartQueueable.testSkipDeliveryEnqueue = true;
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Queueable Execute Task',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      System.enqueueJob(
        new NotificationPrepareStartQueueable(
          NotificationConstants.OBJECT_TYPE_TASK,
          String.valueOf(taskRecord.Id),
          null
        )
      );
    }
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
    ];

    System.assert(!logs.isEmpty());
  }

  @IsTest
  static void executeQueueable_staysWithinSingleChainedJobLimit() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationRecipientPrepareDispatcher.resetTestState();
    NotificationRecipientPrepareDispatcher.testMaxSyncChunks = 1;
    NotificationGovernorLimitService.testRecipientChunkSizeOverride = 1;
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationDeliveryService.skipRetryEnqueueForTest = true;
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    User secondRecipient = NotificationTestDataFactory.createStandardUser(
      'prepq2'
    );
    NotificationTaskRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{
        context.recipientUser.Id,
        secondRecipient.Id
      }
    };

    Task taskRecord = new Task(
      Subject = 'Single Chain Limit Task',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    try {
      Test.startTest();
      System.runAs(NotificationTestDataFactory.runningUser()) {
        System.enqueueJob(
          new NotificationPrepareStartQueueable(
            NotificationConstants.OBJECT_TYPE_TASK,
            String.valueOf(taskRecord.Id),
            null
          )
        );
      }
      Test.stopTest();

      List<Notification_Log__c> logs = [
        SELECT Id
        FROM Notification_Log__c
        WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
      ];

      System.assert(
        !logs.isEmpty(),
        'Expected prepare queueable to create logs without exceeding the chained queueable limit.'
      );
    } finally {
      NotificationTaskRecipientService.testRecipientOverrides = null;
      NotificationDeliveryService.skipRetryEnqueueForTest = false;
    }
  }

  @IsTest
  static void enqueueUsesAsyncPathWhenForced() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationPrepareStartQueueable.testForceAsyncEnqueue = true;
    NotificationPrepareStartQueueable.testSkipDeliveryEnqueue = true;
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Forced Async Enqueue Task',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      NotificationPrepareStartQueueable.enqueue(
        NotificationConstants.OBJECT_TYPE_TASK,
        String.valueOf(taskRecord.Id),
        null
      );
    }
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
    ];

    System.assert(!logs.isEmpty());
  }

  @IsTest
  static void prepareDeliveryDefersWhenSoqlBudgetIsLow() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationGovernorLimitService.testForceDeferPrepareToAsync = true;
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Invocable Deferred Task',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationCenterPrepareInvocable.EventInput input = new NotificationCenterPrepareInvocable.EventInput();
    input.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    input.sourceId = String.valueOf(taskRecord.Id);

    Test.startTest();
    List<NotificationCenterPrepareInvocable.PrepareOutput> outputs;
    System.runAs(NotificationTestDataFactory.runningUser()) {
      outputs = NotificationCenterPrepareInvocable.prepareDelivery(
        new List<NotificationCenterPrepareInvocable.EventInput>{ input }
      );
    }
    Test.stopTest();

    System.assertEquals(1, outputs.size());
    System.assertEquals(0, outputs[0].deliveryLogIds.size());

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
    ];

    System.assert(
      !logs.isEmpty(),
      'Expected notification logs to be created during deferred prepare.'
    );
  }

  @IsTest
  static void enqueueRequests_chainsRemainingWorkWhenSoqlBudgetIsLow() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();
    NotificationPrepareStartQueueable.testSkipDeliveryEnqueue = true;
    NotificationDeliveryService.skipRetryEnqueueForTest = true;

    String dummySourceId = String.valueOf(UserInfo.getUserId());
    List<NotificationPrepareStartQueueable.PrepareRequest> prepareRequests = new List<NotificationPrepareStartQueueable.PrepareRequest>{
      new NotificationPrepareStartQueueable.PrepareRequest(
        NotificationConstants.OBJECT_TYPE_TASK,
        dummySourceId,
        null,
        false
      ),
      new NotificationPrepareStartQueueable.PrepareRequest(
        NotificationConstants.OBJECT_TYPE_TASK,
        dummySourceId,
        null,
        false
      )
    };

    Test.startTest();
    NotificationGovernorLimitService.testRemainingSoqlBudgetOverride = 0;
    NotificationPrepareStartQueueable.enqueueRequests(prepareRequests);
    Test.stopTest();

    System.assertEquals(
      2,
      NotificationPrepareStartQueueable.testEnqueuedJobCount,
      'Expected remaining prepare work to chain when SOQL budget is low.'
    );

    NotificationDeliveryService.skipRetryEnqueueForTest = false;
  }

  @IsTest
  static void prepareInvocable_batchesMultipleInputsIntoSingleEnqueueJob() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.resetTestState();

    NotificationCenterPrepareInvocable.EventInput firstInput =
      new NotificationCenterPrepareInvocable.EventInput();
    firstInput.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    firstInput.sourceId = String.valueOf(UserInfo.getUserId());

    NotificationCenterPrepareInvocable.EventInput secondInput =
      new NotificationCenterPrepareInvocable.EventInput();
    secondInput.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    secondInput.sourceId = String.valueOf(UserInfo.getUserId());

    Test.startTest();
    NotificationCenterPrepareInvocable.prepareDelivery(
      new List<NotificationCenterPrepareInvocable.EventInput>{
        firstInput,
        secondInput
      }
    );
    Test.stopTest();

    System.assertEquals(
      1,
      NotificationPrepareStartQueueable.testEnqueuedJobCount,
      'Multiple Flow inputs should share one prepare queueable job.'
    );
  }

  @IsTest
  static void finalizerLogsUnhandledExceptions() {
    NotificationGovernorLimitService.resetTestState();
    NotificationPrepareStartQueueable.handleFinalizerFailure(
      System.ParentJobResult.UNHANDLED_EXCEPTION,
      new LimitException()
    );

    System.assertEquals(
      1,
      NotificationGovernorLimitService.loggedLimitMessages.size()
    );
  }

  @IsTest
  static void finalizerExecuteDelegatesToHandler() {
    NotificationGovernorLimitService.resetTestState();

    NotificationPrepareStartQueueable.handleFinalizerFailure(
      System.ParentJobResult.SUCCESS,
      null
    );

    System.assertEquals(
      0,
      NotificationGovernorLimitService.loggedLimitMessages.size()
    );
  }
}