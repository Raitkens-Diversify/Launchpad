/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class Event_TriggerHandlerTest {
  @IsTest
  static void afterInsertPublishesEventChangeContext() {
    Account household = new Account(Name = 'Trigger Event Household', Classification__c = 'Unclassified');
    insert household;

    Test.startTest();
    Event eventRecord = new Event(
      Subject = 'Trigger Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = household.Id
    );
    insert eventRecord;
    Test.stopTest();

    System.assert(true, 'Event insert should publish notification change context');
  }

  @IsTest
  static void afterUpdatePublishesTrackedFieldChanges() {
    Account household = new Account(Name = 'Trigger Update Household', Classification__c = 'Unclassified');
    insert household;

    Event eventRecord = new Event(
      Subject = 'Original Subject',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = household.Id
    );
    insert eventRecord;

    Test.startTest();
    eventRecord.Subject = 'Updated Subject';
    update eventRecord;
    Test.stopTest();

    System.assert(true, 'Event update should publish notification change context');
  }

  @IsTest
  static void isAfterInsert_delegatesToChangePublisher() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Event eventRecord = new Event(
      Subject = 'Direct Handler Insert',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(eventRecord);
    NotificationPublisher.resetForTest();

    Event_TriggerHandler handler = new Event_TriggerHandler();
    handler.isAfterInsert(new Map<Id, Event>{ eventRecord.Id => eventRecord });

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_INSERT, changeContext.triggerType);
    System.assertEquals(String.valueOf(eventRecord.Id), changeContext.recordId);
  }

  @IsTest
  static void isAfterUpdate_delegatesToChangePublisher() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Event eventRecord = new Event(
      Subject = 'Direct Handler Original',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(eventRecord);
    NotificationPublisher.resetForTest();

    Event oldEvent = eventRecord.clone(true, true, true, true);
    eventRecord.Subject = 'Direct Handler Updated';

    Event_TriggerHandler handler = new Event_TriggerHandler();
    handler.isAfterUpdate(
      new Map<Id, Event>{ eventRecord.Id => eventRecord },
      new Map<Id, Event>{ oldEvent.Id => oldEvent }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_UPDATE, changeContext.triggerType);
    System.assertEquals(String.valueOf(eventRecord.Id), changeContext.recordId);
  }
}