/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationChangePublisherTest {
  @IsTest
  static void publishInsertsIncludesChangeContextJson() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Publisher Insert Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    NotificationChangePublisher.publishInserts(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<SObject>{ taskRecord }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_INSERT, changeContext.triggerType);
    System.assertEquals(String.valueOf(taskRecord.Id), changeContext.recordId);
    System.assertEquals('Publisher Insert Task', changeContext.recordLabel);
    System.assertEquals(UserInfo.getUserId(), changeContext.changedByUserId);
  }

  @IsTest
  static void publishUpdatesWhenOwnerChanges() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('triggerowner');

    Task taskRecord = new Task(
      Subject = 'Publisher Update Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    Task oldTask = taskRecord.clone(true, true, true, true);
    taskRecord.OwnerId = otherUser.Id;

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, SObject>{ taskRecord.Id => taskRecord },
      new Map<Id, SObject>{ oldTask.Id => oldTask }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_UPDATE, changeContext.triggerType);
    System.assertEquals(1, changeContext.changedFields.size());
  }

  @IsTest
  static void publishUpdatesSkipsUntrackedFieldChanges() {
    NotificationPublisher.resetForTest();
    Account household = new Account(Name = 'Skip Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Skip Update Task',
      Description = 'Before',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    Task oldTask = taskRecord.clone(true, true, true, true);
    taskRecord.Description = 'After';

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, SObject>{ taskRecord.Id => taskRecord },
      new Map<Id, SObject>{ oldTask.Id => oldTask }
    );

    System.assertEquals(0, NotificationPublisher.testPublishedEventCount);
  }

  @IsTest
  static void publishInsertsSkipsBranchPitStopTasks() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Branch Pit Stop Publisher Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    NotificationChangePublisher.publishInserts(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<SObject>{ taskRecord }
    );

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'Branch pit stop tasks use standard task notification paths.'
    );
  }

  @IsTest
  static void publishUpdatesSkipsBranchPitStopTasks() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Branch Pit Stop Update Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    Task oldTask = taskRecord.clone(true, true, true, true);
    taskRecord.Status = 'In Progress';

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, SObject>{ taskRecord.Id => taskRecord },
      new Map<Id, SObject>{ oldTask.Id => oldTask }
    );

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'Branch pit stop task updates use standard task notification paths.'
    );
  }

  @IsTest
  static void publishInsertsIncludesHomeOfficePitStopTasks() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop Publisher Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    NotificationPublisher.resetForTest();

    NotificationChangePublisher.publishInserts(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<SObject>{ taskRecord }
    );

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'HO pit stop tasks still publish for non-Home Office Notification Center recipients.'
    );
  }
}