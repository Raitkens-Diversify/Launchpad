/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class NotificationLogRepositoryTest {
  @IsTest
  static void selectLogsReturnsInAppSentNotificationsForRecipient() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c unreadNotification = NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Unread Case Alert',
      'Case 00001001 - Portfolio Review',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Read Task Alert',
      'Follow up call',
      true
    );

    NotificationLogRepository.NotificationLogQuery query = new NotificationLogRepository.NotificationLogQuery();
    query.recipientId = context.recipientUser.Id;
    query.channels = new Set<String>{ NotificationConstants.CHANNEL_IN_APP };
    query.statuses = new Set<String>{ NotificationConstants.STATUS_SENT };
    query.pageSize = 25;
    query.fieldSet = NotificationLogRepository.FieldSet.INBOX;

    List<Notification_Log__c> notifications = new NotificationLogRepository().selectLogs(query);

    System.assertEquals(2, notifications.size());

    Set<Id> returnedIds = new Set<Id>();
    for (Notification_Log__c notification : notifications) {
      returnedIds.add(notification.Id);
    }
    System.assert(returnedIds.contains(unreadNotification.Id));
  }

  @IsTest
  static void countLogsMatchesFilteredLogResults() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Delivered notification',
      null,
      null
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_SUPPRESSED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Suppressed notification',
      'Info category disabled for this recipient',
      null
    );

    NotificationLogRepository repository = new NotificationLogRepository();
    NotificationLogRepository.NotificationLogQuery query = new NotificationLogRepository.NotificationLogQuery();
    query.recipientId = context.recipientUser.Id;
    query.statuses = new Set<String>{ NotificationConstants.STATUS_SUPPRESSED };
    query.categoryFilter = NotificationConstants.LOG_CATEGORY_ALL;
    query.fieldSet = NotificationLogRepository.FieldSet.LOG;

    System.assertEquals(1, repository.countLogs(query));
    System.assertEquals(1, repository.selectLogs(query).size());
  }

  @IsTest
  static void selectLogsRequiresRecipientId() {
    Boolean didThrow = false;

    try {
      new NotificationLogRepository().selectLogs(new NotificationLogRepository.NotificationLogQuery());
    } catch (IllegalArgumentException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void selectLogsFiltersByDateRange() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationLogRepository repository = new NotificationLogRepository();

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Delivered today',
      null,
      null
    );
    Notification_Log__c deliveredYesterday = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Delivered yesterday',
      null,
      null
    );
    deliveredYesterday.Delivered_At__c = Datetime.newInstance(
      Date.today().addDays(-1),
      Time.newInstance(12, 0, 0, 0)
    );
    NotificationTestDataFactory.updateRecord(deliveredYesterday);

    NotificationLogRepository.NotificationLogQuery query = new NotificationLogRepository.NotificationLogQuery();
    query.recipientId = context.recipientUser.Id;
    query.statuses = new Set<String>{ NotificationConstants.STATUS_SENT };
    query.categoryFilter = NotificationConstants.LOG_CATEGORY_ALL;
    query.startDate = Date.today();
    query.endDate = Date.today();
    query.fieldSet = NotificationLogRepository.FieldSet.LOG;

    System.assertEquals(1, repository.countLogs(query));
    System.assertEquals(1, repository.selectLogs(query).size());
  }

  @IsTest
  static void promoteAndSelectPendingImmediateLogsByIdsPromotesQueuedLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationLogRepository repository = new NotificationLogRepository();

    Notification_Log__c queuedLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Immediate queued log',
      null,
      null
    );

    List<Notification_Log__c> deliverableLogs = repository.promoteAndSelectPendingImmediateLogsByIds(
      new List<Id>{ queuedLog.Id }
    );

    System.assertEquals(1, deliverableLogs.size());
    System.assertEquals(queuedLog.Id, deliverableLogs[0].Id);
    System.assertEquals(
      NotificationConstants.STATUS_PENDING,
      [
        SELECT Status__c
        FROM Notification_Log__c
        WHERE Id = :queuedLog.Id
      ].Status__c
    );
  }
}