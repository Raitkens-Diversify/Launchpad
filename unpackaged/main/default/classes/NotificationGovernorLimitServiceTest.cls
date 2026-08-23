/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationGovernorLimitServiceTest {
  @IsTest
  static void resolveRecipientChunkSizeUsesConfiguredMaximum() {
    NotificationGovernorLimitService.resetTestState();

    Integer chunkSizeForLargeSet = NotificationGovernorLimitService.resolveRecipientChunkSize(
      100
    );
    System.assert(
      chunkSizeForLargeSet <= NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK,
      'Chunk size should not exceed the configured maximum.'
    );
    System.assert(
      chunkSizeForLargeSet >= NotificationConstants.MIN_RECIPIENTS_PER_PREPARE_CHUNK,
      'Chunk size should respect the SOQL budget floor.'
    );
    System.assertEquals(
      12,
      NotificationGovernorLimitService.resolveRecipientChunkSize(12)
    );
  }

  @IsTest
  static void sliceIdsReturnsRequestedRange() {
    List<Id> recipientIds = new List<Id>{
      UserInfo.getUserId(),
      UserInfo.getUserId(),
      UserInfo.getUserId()
    };

    List<Id> sliceValues = NotificationGovernorLimitService.sliceIds(
      recipientIds,
      1,
      3
    );

    System.assertEquals(2, sliceValues.size());
  }

  @IsTest
  static void shrinkRecipientChunkSizeNeverFallsBelowMinimum() {
    System.assertEquals(
      5,
      NotificationGovernorLimitService.shrinkRecipientChunkSize(5)
    );
    System.assertEquals(
      5,
      NotificationGovernorLimitService.shrinkRecipientChunkSize(6)
    );
    System.assertEquals(
      25,
      NotificationGovernorLimitService.shrinkRecipientChunkSize(50)
    );
  }

  @IsTest
  static void insertInChunksPersistsAllRecords() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    List<Notification_Log__c> logs = new List<Notification_Log__c>();

    for (Integer index = 0; index < 3; index++) {
      logs.add(
        new Notification_Log__c(
          Recipient__c = context.recipientUser.Id,
          Household__c = context.household.Id,
          Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
          Status__c = NotificationConstants.STATUS_PENDING,
          Channel__c = NotificationConstants.CHANNEL_IN_APP,
          Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
          Title__c = 'Chunk ' + index,
          Body__c = 'Chunk ' + index
        )
      );
    }

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      NotificationGovernorLimitService.insertInChunks(logs);
    }
    Test.stopTest();

    System.assertEquals(3, [SELECT COUNT() FROM Notification_Log__c]);
  }

  @IsTest
  static void canProcessAnotherRecipientChunkReflectsRemainingBudget() {
    NotificationGovernorLimitService.resetTestState();
    System.assertEquals(
      true,
      NotificationGovernorLimitService.canProcessAnotherRecipientChunk()
    );
  }

  @IsTest
  static void canProcessImmediateDeliveryHonorsTestOverride() {
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testForceInsufficientDeliveryBudget = true;

    System.assertEquals(
      false,
      NotificationGovernorLimitService.canProcessImmediateDelivery()
    );
  }

  @IsTest
  static void getRemainingSoqlBudgetNeverReturnsNegative() {
    System.assert(
      NotificationGovernorLimitService.getRemainingSoqlBudget() >= 0
    );
    System.assert(
      NotificationGovernorLimitService.getSoqlLimit() > 0
    );
  }

  @IsTest
  static void sliceIdsReturnsEmptyForInvalidInput() {
    System.assertEquals(
      0,
      NotificationGovernorLimitService.sliceIds(null, 0, 1).size()
    );
    System.assertEquals(
      0,
      NotificationGovernorLimitService.sliceIds(new List<Id>(), 0, 1).size()
    );
  }

  @IsTest
  static void isLimitExceptionDetectsLimitExceptionType() {
    System.assertEquals(
      true,
      NotificationGovernorLimitService.isLimitException(new LimitException())
    );
    System.assertEquals(
      false,
      NotificationGovernorLimitService.isLimitException(
        new NotificationDeliveryService.NotificationDeliveryException('x')
      )
    );
  }

  @IsTest
  static void logLimitExceptionCapturesMessage() {
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.logLimitException(
      'NotificationGovernorLimitServiceTest',
      new LimitException()
    );

    System.assertEquals(
      1,
      NotificationGovernorLimitService.loggedLimitMessages.size()
    );
  }

  @IsTest
  static void resolveRecipientChunkSizeRespectsRemainingSoqlBudget() {
    NotificationGovernorLimitService.resetTestState();

    Integer budgetChunkSize = NotificationGovernorLimitService.resolveRecipientChunkSize(
      100
    );

    System.assert(
      budgetChunkSize <= NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK,
      'Chunk size should never exceed the configured maximum.'
    );
    System.assert(
      budgetChunkSize >= NotificationConstants.MIN_RECIPIENTS_PER_PREPARE_CHUNK,
      'Chunk size should never fall below the configured minimum.'
    );
  }

  @IsTest
  static void resolveMaxDeliveryEnqueueJobsReservesChainSlot() {
    NotificationGovernorLimitService.resetTestState();

    Integer maxJobs = NotificationGovernorLimitService.resolveMaxDeliveryEnqueueJobs();

    System.assert(
      maxJobs <= NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION,
      'Configured max should cap delivery enqueue jobs.'
    );
    System.assert(
      maxJobs <= NotificationGovernorLimitService.getRemainingQueueableBudget() -
        NotificationConstants.QUEUEABLE_CHAIN_RESERVE_SLOTS,
      'Delivery enqueue max should reserve one slot for overflow chaining.'
    );
  }

  @IsTest
  static void resolveMaxDeliveryEnqueueJobsAccountsForRemainingBudget() {
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testRemainingQueueableBudgetOverride = 10;

    System.assertEquals(
      9,
      NotificationGovernorLimitService.resolveMaxDeliveryEnqueueJobs(),
      'Expected one queueable slot to remain reserved for overflow chaining.'
    );
  }

  @IsTest
  static void shouldDeferPrepareToAsyncWhenQueueableBudgetIsBelowMinimum() {
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testRemainingQueueableBudgetOverride =
      NotificationConstants.MIN_QUEUEABLE_BUDGET_FOR_SYNC_PREPARE - 1;

    System.assertEquals(
      true,
      NotificationGovernorLimitService.shouldDeferPrepareToAsync(),
      'Expected prepare work to defer when queueable budget is too low.'
    );
  }

  @IsTest
  static void getRemainingQueueableBudgetNeverReturnsNegative() {
    System.assert(
      NotificationGovernorLimitService.getRemainingQueueableBudget() >= 0
    );
    System.assert(NotificationGovernorLimitService.getQueueableLimit() > 0);
  }

  @IsTest
  static void shouldDeferPrepareToAsyncHonorsTestOverride() {
    NotificationGovernorLimitService.resetTestState();

    System.assertEquals(
      false,
      NotificationGovernorLimitService.shouldDeferPrepareToAsync()
    );

    NotificationGovernorLimitService.testForceDeferPrepareToAsync = true;

    System.assertEquals(
      true,
      NotificationGovernorLimitService.shouldDeferPrepareToAsync()
    );
  }

  @IsTest
  static void resolveRecipientChunkSizeReturnsZeroForInvalidInput() {
    System.assertEquals(
      0,
      NotificationGovernorLimitService.resolveRecipientChunkSize(0)
    );
    System.assertEquals(
      0,
      NotificationGovernorLimitService.resolveRecipientChunkSize(null)
    );
  }
}