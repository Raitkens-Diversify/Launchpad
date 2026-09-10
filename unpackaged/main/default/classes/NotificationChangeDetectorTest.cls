/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-09
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

  @IsTest
  static void detectUpdatesFormatsDateTimeDisplayForCurrentUser() {
    User currentUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Account household = new Account(Name = 'Detector Date Household');
    NotificationTestDataFactory.insertRecord(household);

    Datetime originalStart = Datetime.newInstance(
      Date.today().addDays(2),
      Time.newInstance(9, 0, 0, 0)
    );
    Datetime originalEnd = originalStart.addHours(1);
    Datetime updatedStart = originalStart.addDays(1);
    Datetime updatedEnd = originalEnd.addDays(1);

    Event eventRecord = new Event(
      Subject = 'Date Display Event',
      WhatId = household.Id,
      OwnerId = currentUser.Id,
      StartDateTime = originalStart,
      EndDateTime = originalEnd,
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Event oldEvent = eventRecord.clone(true, true, true, true);
    eventRecord.StartDateTime = updatedStart;
    eventRecord.EndDateTime = updatedEnd;

    NotificationChangeDetector detector = new NotificationChangeDetector();
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = detector.detectUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ eventRecord.Id => eventRecord },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    System.assertEquals(1, contextByRecordId.size());
    NotificationChangeModels.ChangeContext changeContext = contextByRecordId.get(
      eventRecord.Id
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_UPDATE, changeContext.triggerType);

    NotificationChangeModels.FieldChange startChange = findChangedField(
      changeContext,
      'StartDateTime'
    );
    NotificationChangeModels.FieldChange endChange = findChangedField(
      changeContext,
      'EndDateTime'
    );

    System.assertNotEquals(null, startChange, 'StartDateTime must be detected.');
    System.assertNotEquals(null, endChange, 'EndDateTime must be detected.');
    System.assertEquals(originalStart.format(), startChange.oldDisplay);
    System.assertEquals(updatedStart.format(), startChange.newDisplay);
    System.assertEquals(originalEnd.format(), endChange.oldDisplay);
    System.assertEquals(updatedEnd.format(), endChange.newDisplay);
    System.assertEquals(String.valueOf(originalStart), startChange.oldValue);
    System.assertEquals(String.valueOf(updatedStart), startChange.newValue);
    System.assertEquals(currentUser.Id, eventRecord.OwnerId);
  }

  private static NotificationChangeModels.FieldChange findChangedField(
    NotificationChangeModels.ChangeContext changeContext,
    String fieldApiName
  ) {
    if (changeContext == null || changeContext.changedFields == null) {
      return null;
    }

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      if (fieldChange != null && fieldChange.apiName == fieldApiName) {
        return fieldChange;
      }
    }

    return null;
  }
}