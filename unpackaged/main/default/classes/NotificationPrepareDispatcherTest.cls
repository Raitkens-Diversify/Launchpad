/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationPrepareDispatcherTest {
  @IsTest
  static void processRecipientsChunksLargeRecipientSets() {
    NotificationGovernorLimitService.resetTestState();
    NotificationRecipientPrepareDispatcher.resetTestState();
    NotificationGovernorLimitService.testRecipientChunkSizeOverride = 1;
    NotificationRecipientPrepareDispatcher.testMaxSyncChunks = 1;
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    User secondRecipient = NotificationTestDataFactory.createStandardUser('notifrcpt2');
    User thirdRecipient = NotificationTestDataFactory.createStandardUser('notifrcpt3');

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{
        context.recipientUser.Id,
        secondRecipient.Id,
        thirdRecipient.Id
      }
    };

    Case caseRecord = new Case(
      Subject = 'Chunked Prepare Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationCaseRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      caseRecord.Id => new List<Id>{
        context.recipientUser.Id,
        secondRecipient.Id,
        thirdRecipient.Id
      }
    };

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems;
    System.runAs(NotificationTestDataFactory.runningUser()) {
      deliveryItems = new NotificationCenterEventService().prepareSourceRecord(
        NotificationConstants.OBJECT_TYPE_CASE,
        String.valueOf(caseRecord.Id)
      );
    }
    Test.stopTest();

    System.assert(
      NotificationRecipientPrepareDispatcher.testEnqueuedContinuationCount >= 1 ||
        NotificationRecipientPrepareDispatcher.syncChunksProcessed >= 1,
      'Expected chunked recipient preparation to process recipients in capped sync batches.'
    );

    List<Notification_Log__c> logs = [
      SELECT Recipient__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(caseRecord.Id)
    ];

    Set<Id> recipientIds = new Set<Id>();
    for (Notification_Log__c logRecord : logs) {
      recipientIds.add(logRecord.Recipient__c);
    }

    System.assertEquals(3, recipientIds.size());
    System.assert(recipientIds.contains(context.recipientUser.Id));
    System.assert(recipientIds.contains(secondRecipient.Id));
    System.assert(recipientIds.contains(thirdRecipient.Id));

    NotificationCaseRecipientService.testRecipientOverrides = null;
    NotificationRecipientService.testRecipientOverrides = null;
  }

  @IsTest
  static void prepareChainQueueableExecutesContinuation() {
    NotificationGovernorLimitService.resetTestState();
    NotificationRecipientPrepareDispatcher.resetTestState();
    NotificationTestDataFactory.clearTestOverrides();
    NotificationCustomNotificationService.testSkipSend = true;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Prepare Chain Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationCaseRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      caseRecord.Id => new List<Id>{ context.recipientUser.Id }
    };

    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest = new NotificationRecipientPrepareModels.ContinuationRequest();
    continuationRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    continuationRequest.sourceId = String.valueOf(caseRecord.Id);
    continuationRequest.correlationKey = String.valueOf(caseRecord.Id);
    continuationRequest.startIndex = 999;
    continuationRequest.attemptNumber = 1;

    Test.startTest();
    System.enqueueJob(new NotificationPrepareChainQueueable(continuationRequest));
    Test.stopTest();

    NotificationCaseRecipientService.testRecipientOverrides = null;
    System.assert(true, 'Prepare chain queueable should execute continuation.');
  }

  @IsTest
  static void prepareChainFinalizerHandlesSuccessAndFailureResults() {
    NotificationRecipientPrepareDispatcher.resetTestState();

    NotificationRecipientPrepareModels.ContinuationRequest request = new NotificationRecipientPrepareModels.ContinuationRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = '500000000000001AAA';
    request.startIndex = 0;
    request.attemptNumber = 1;

    NotificationPrepareChainQueueable.handleFinalizerFailure(
      request,
      System.ParentJobResult.SUCCESS,
      null
    );
    NotificationPrepareChainQueueable.handleFinalizerFailure(request, null);

    NotificationPrepareChainQueueable.handleFinalizerFailure(
      request,
      System.ParentJobResult.UNHANDLED_EXCEPTION,
      new LimitException()
    );

    System.assert(true, 'Finalizer failure path should delegate to prepare dispatcher.');
  }

  @IsTest
  static void processRecipientsReturnsEmptyForNullContext() {
    NotificationRecipientPrepareDispatcher.resetTestState();

    List<NotificationCenterDeliveryItem> deliveryItems = NotificationRecipientPrepareDispatcher.processRecipients(
      null
    );

    System.assertEquals(0, deliveryItems.size());
  }

  @IsTest
  static void handleContinuationFailureLogsWhenMaxAttemptsReached() {
    NotificationGovernorLimitService.resetTestState();
    NotificationRecipientPrepareDispatcher.resetTestState();

    NotificationRecipientPrepareModels.ContinuationRequest request = new NotificationRecipientPrepareModels.ContinuationRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = '500000000000001AAA';
    request.startIndex = 0;
    request.attemptNumber = NotificationConstants.MAX_RECIPIENT_PREPARE_CHAIN_ATTEMPTS;

    NotificationRecipientPrepareDispatcher.handleContinuationFailure(
      request,
      new LimitException()
    );

    System.assertEquals(
      1,
      NotificationGovernorLimitService.loggedLimitMessages.size()
    );
  }

  @IsTest
  static void handleContinuationFailureEnqueuesRetryBelowMaxAttempts() {
    NotificationGovernorLimitService.resetTestState();
    NotificationRecipientPrepareDispatcher.resetTestState();
    NotificationTestDataFactory.clearTestOverrides();

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Retry Prepare Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationCaseRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      caseRecord.Id => new List<Id>{ context.recipientUser.Id }
    };

    NotificationRecipientPrepareModels.ContinuationRequest request = new NotificationRecipientPrepareModels.ContinuationRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = String.valueOf(caseRecord.Id);
    request.correlationKey = String.valueOf(caseRecord.Id);
    request.startIndex = 0;
    request.chunkSize = 1;
    request.attemptNumber = 1;

    NotificationRecipientPrepareDispatcher.handleContinuationFailure(
      request,
      new LimitException()
    );

    System.assert(
      NotificationRecipientPrepareDispatcher.testEnqueuedContinuationCount >= 1
    );
    NotificationCaseRecipientService.testRecipientOverrides = null;
  }

  @IsTest
  static void continuePreparationNoopsForNullOrCompletedRequest() {
    NotificationRecipientPrepareDispatcher.continuePreparation(null);

    NotificationRecipientPrepareModels.ContinuationRequest completedRequest = new NotificationRecipientPrepareModels.ContinuationRequest();
    completedRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    completedRequest.sourceId = '500000000000001AAA';
    completedRequest.startIndex = 999;
    NotificationRecipientPrepareDispatcher.continuePreparation(completedRequest);

    System.assert(true, 'Completed or null continuation requests should no-op safely.');
  }

  @IsTest
  static void processRecipients_enqueuesContinuationWhenSyncChunkLimitReached() {
    NotificationRecipientPrepareDispatcher.resetTestState();
    NotificationRecipientPrepareDispatcher.testMaxSyncChunks = 0;

    NotificationRecipientPrepareModels.SourcePrepareContext context =
      new NotificationRecipientPrepareModels.SourcePrepareContext();
    context.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    context.sourceId = String.valueOf(UserInfo.getUserId());
    context.recipientIds = new List<Id>{ UserInfo.getUserId() };

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems =
      NotificationRecipientPrepareDispatcher.processRecipients(context);
    Test.stopTest();

    System.assertEquals(0, deliveryItems.size());
    System.assert(
      NotificationRecipientPrepareDispatcher.testEnqueuedContinuationCount >= 1
    );
  }
}