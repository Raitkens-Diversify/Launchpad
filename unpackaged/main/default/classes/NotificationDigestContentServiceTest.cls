/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationDigestContentServiceTest {
  @IsTest
  static void resolveTargetIdUsesSourceRecordWhenTargetFieldNotQueried() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Event eventRecord = new Event(
      Subject = 'Target id fallback event',
      WhatId = context.household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_QUEUED,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    Notification_Log__c partialLog = [
      SELECT Id, Source_Record_Id__c, Household__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
      LIMIT 1
    ];

    Id resolvedTargetId = NotificationDigestContentService.resolveTargetId(
      partialLog
    );

    System.assertEquals(eventRecord.Id, resolvedTargetId);
  }

  @IsTest
  static void buildDigestMessageDoesNotRequireTargetFieldOnPartialQuery() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Event eventRecord = new Event(
      Subject = 'Digest builder partial query event',
      WhatId = context.household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_EVENT,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_QUEUED,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    Notification_Log__c partialLog = [
      SELECT
        Id,
        Source_Type__c,
        Source_Record_Id__c,
        Change_Context__c,
        Household__c,
        Channel__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
      LIMIT 1
    ];

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.buildForChannel(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<Notification_Log__c>{ partialLog },
      NotificationConstants.CHANNEL_EMAIL
    );

    System.assertEquals(eventRecord.Id, message.targetId);
    System.assert(message.body.contains('<table'));
    System.assert(message.body.contains('Digest builder partial query event'));
  }
}