/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class NotificationCenterDeliveryItemTest {
  @IsTest
  static void fromLog_populatesAllInvocableFields() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Delivery item test',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(context.household.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    NotificationCenterDeliveryItem item = NotificationCenterDeliveryItem.fromLog(
      logRecord
    );

    System.assertEquals(logRecord.Id, item.logId);
    System.assertEquals(context.recipientUser.Id, item.recipientId);
    System.assertEquals(NotificationConstants.CHANNEL_EMAIL, item.channel);
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, item.frequency);
    System.assertEquals(NotificationConstants.OBJECT_TYPE_CASE, item.sourceType);
    System.assertEquals(String.valueOf(context.household.Id), item.sourceRecordId);
  }

  @IsTest
  static void fromLogs_buildsCsvForMultipleLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'First digest item',
      null,
      null
    );
    Notification_Log__c secondLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Second digest item',
      null,
      null
    );

    NotificationCenterDeliveryItem item = NotificationCenterDeliveryItem.fromLogs(
      new List<Notification_Log__c>{ firstLog, secondLog }
    );

    System.assertEquals(firstLog.Id, item.logId);
    System.assert(item.logIdsCsv.contains(String.valueOf(firstLog.Id)));
    System.assert(item.logIdsCsv.contains(String.valueOf(secondLog.Id)));
  }

  @IsTest
  static void fromLog_returnsNullForNullInput() {
    System.assertEquals(null, NotificationCenterDeliveryItem.fromLog(null));
    System.assertEquals(null, NotificationCenterDeliveryItem.fromLogs(null));
    System.assertEquals(null, NotificationCenterDeliveryItem.fromLogs(new List<Notification_Log__c>()));
  }
}