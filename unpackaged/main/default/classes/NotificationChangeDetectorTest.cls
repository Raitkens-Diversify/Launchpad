/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationChangeDetectorTest {
  @IsTest
  static void detectInsertsReturnsInsertContextForEachRecord() {
    Account household = new Account(Name = 'Detector Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Insert Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeDetector detector = new NotificationChangeDetector();
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = detector.detectInserts(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<SObject>{ taskRecord }
    );

    System.assertEquals(1, contextByRecordId.size());
    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_INSERT,
      contextByRecordId.get(taskRecord.Id).triggerType
    );
    System.assertEquals(0, contextByRecordId.get(taskRecord.Id).changedFields.size());
  }

  @IsTest
  static void detectUpdatesReturnsContextWhenOwnerChanges() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('taskowner');

    Task taskRecord = new Task(
      Subject = 'Assigned Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Task oldTask = taskRecord.clone(true, true, true, true);
    taskRecord.OwnerId = otherUser.Id;
    NotificationTestDataFactory.updateRecord(taskRecord);

    NotificationChangeDetector detector = new NotificationChangeDetector();
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = detector.detectUpdates(
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, SObject>{ taskRecord.Id => taskRecord },
      new Map<Id, SObject>{ oldTask.Id => oldTask }
    );

    System.assertEquals(1, contextByRecordId.size());
    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_UPDATE,
      contextByRecordId.get(taskRecord.Id).triggerType
    );
    System.assertEquals(1, contextByRecordId.get(taskRecord.Id).changedFields.size());
    System.assertEquals(
      'OwnerId',
      contextByRecordId.get(taskRecord.Id).changedFields[0].apiName
    );

    User recipientUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :context.recipientUser.Id
      LIMIT 1
    ];
    User assigneeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :otherUser.Id
      LIMIT 1
    ];

    System.assertEquals(
      recipientUser.Name,
      contextByRecordId.get(taskRecord.Id).changedFields[0].oldDisplay
    );
    System.assertEquals(
      assigneeUser.Name,
      contextByRecordId.get(taskRecord.Id).changedFields[0].newDisplay
    );
  }

  @IsTest
  static void detectUpdatesReturnsEmptyWhenUntrackedFieldChanges() {
    Account household = new Account(Name = 'Untracked Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Original Subject',
      Description = 'Original Description',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Task oldTask = taskRecord.clone(true, true, true, true);
    taskRecord.Description = 'Updated Description';
    NotificationTestDataFactory.updateRecord(taskRecord);

    NotificationChangeDetector detector = new NotificationChangeDetector();
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = detector.detectUpdates(
      NotificationConstants.OBJECT_TYPE_TASK,
      new Map<Id, SObject>{ taskRecord.Id => taskRecord },
      new Map<Id, SObject>{ oldTask.Id => oldTask }
    );

    System.assertEquals(0, contextByRecordId.size());
  }
}