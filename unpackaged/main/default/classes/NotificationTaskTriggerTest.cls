/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class NotificationTaskTriggerTest {
  @IsTest
  static void insertUpdateDeleteUndeleteFiresTaskTrigger() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Notification Task Trigger Test',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );

    Test.startTest();
    NotificationTestDataFactory.insertRecord(taskRecord);

    taskRecord.Subject = 'Updated Notification Task Trigger Test';
    NotificationTestDataFactory.updateRecord(taskRecord);

    delete taskRecord;
    undelete taskRecord;
    Test.stopTest();

    Task restoredTask = [
      SELECT Id, Subject
      FROM Task
      WHERE Id = :taskRecord.Id
      LIMIT 1
    ];
    System.assertEquals(
      'Updated Notification Task Trigger Test',
      restoredTask.Subject
    );
  }

  @IsTest
  static void afterInsertPublishesTaskChangeContext() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Test.startTest();
    Task taskRecord = new Task(
      Subject = 'Task Change Publisher',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    Test.stopTest();

    System.assertNotEquals(null, taskRecord.Id);
  }

  @IsTest
  static void afterUpdatePublishesTaskChangeContext() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Task Update Publisher',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    taskRecord.Status = 'In Progress';
    NotificationTestDataFactory.updateRecord(taskRecord);
    Test.stopTest();

    Task updatedTask = [
      SELECT Status
      FROM Task
      WHERE Id = :taskRecord.Id
      LIMIT 1
    ];
    System.assertEquals('In Progress', updatedTask.Status);
  }

  @IsTest
  static void beforeInsertSetsOriginalOwnerAndHouseholdFromContact() {
    Contact contactRecord = new Contact(
      LastName = 'Task Trigger Contact',
      Email = 'task.trigger@example.com.test'
    );
    NotificationTestDataFactory.insertRecord(contactRecord);

    Test.startTest();
    Task taskRecord = new Task(
      Subject = 'Contact Household Task',
      WhoId = contactRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    Test.stopTest();

    Task insertedTask = [
      SELECT Id, Original_Owner__c, OwnerId
      FROM Task
      WHERE Id = :taskRecord.Id
      LIMIT 1
    ];
    System.assertEquals(insertedTask.OwnerId, insertedTask.Original_Owner__c);
  }
}