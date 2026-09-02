/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 */
@IsTest
private class NotificationStaleLogCleanupBatchTest {
  @IsTest
  static void batchSuppressesUndeliveredQueuedLogsBeforeCutoff() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Log__c staleQueuedLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Stale queued log',
      null,
      null
    );

    Notification_Log__c attemptedLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Attempted queued log',
      null,
      null
    );
    attemptedLog.Delivery_Attempt_Count__c = 1;
    NotificationTestDataFactory.updateRecord(attemptedLog);

    Test.startTest();
    Database.executeBatch(
      new NotificationStaleLogCleanupBatch(Date.today().addDays(1)),
      200
    );
    Test.stopTest();

    Notification_Log__c updatedStaleLog = [
      SELECT Status__c, Suppression_Reason__c
      FROM Notification_Log__c
      WHERE Id = :staleQueuedLog.Id
    ];
    Notification_Log__c updatedAttemptedLog = [
      SELECT Status__c, Suppression_Reason__c
      FROM Notification_Log__c
      WHERE Id = :attemptedLog.Id
    ];

    System.assertEquals(
      NotificationConstants.STATUS_SUPPRESSED,
      updatedStaleLog.Status__c
    );
    System.assertEquals(
      NotificationConstants.SUPPRESSION_STALE_QUEUED_CLEANUP,
      updatedStaleLog.Suppression_Reason__c
    );
    System.assertEquals(
      NotificationConstants.STATUS_QUEUED,
      updatedAttemptedLog.Status__c
    );
  }

  @IsTest
  static void batchUsesStartOfCurrentMonthByDefault() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.STATUS_PENDING,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Pending digest log',
      null,
      null
    );

    Test.startTest();
    NotificationStaleLogCleanupBatch batch = new NotificationStaleLogCleanupBatch();
    Database.executeBatch(batch, 200);
    Test.stopTest();

    System.assertEquals(0, [
      SELECT COUNT()
      FROM Notification_Log__c
      WHERE
        Status__c IN (
          :NotificationConstants.STATUS_QUEUED,
          :NotificationConstants.STATUS_PENDING
        )
        AND Recipient__c = :context.recipientUser.Id
    ]);
  }
}