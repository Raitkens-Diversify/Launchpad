/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationPublisherTest {
  @IsTest
  static void publishFromRecordsAlwaysPublishesCenterEvent() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Case caseRecord = new Case(
      Subject = 'Publisher Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationPublisher.publishFromRecords(
      new List<SObject>{ caseRecord },
      NotificationConstants.OBJECT_TYPE_CASE
    );

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'Publisher should emit one Notification Center Event per record'
    );
  }

  @IsTest
  static void publishFromRecordsPublishesEvenWhenNoHousehold() {
    NotificationPublisher.resetForTest();

    Task taskRecord = new Task(
      Subject = 'No Household Task',
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationPublisher.publishFromRecords(
      new List<SObject>{ taskRecord },
      NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'Publisher should always emit an event per record'
    );
  }

  @IsTest
  static void publishTasksIncludesChangeContextJson() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Publisher Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    NotificationPublisher.publishWithContext(
      new List<SObject>{ taskRecord },
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, NotificationChangeModels.ChangeContext>{
        taskRecord.Id => changeContext
      }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    System.assertEquals(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationPublisher.testPublishedEvents[0].Source_Type__c
    );
    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_INSERT,
      NotificationChangeModels.fromJson(
          NotificationPublisher.testPublishedEvents[0].Change_Context__c
        )
        .triggerType
    );
  }
}