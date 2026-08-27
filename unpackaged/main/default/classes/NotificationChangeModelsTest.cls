/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationChangeModelsTest {
  @IsTest
  static void formatChangedAtDisplayUsesIsoValueWhenPresent() {
    Datetime changedAt = Datetime.newInstanceGmt(2026, 7, 27, 18, 30, 0);

    System.assertEquals(
      changedAt.format('MM/dd/yyyy h:mm a'),
      NotificationChangeModels.formatChangedAtDisplay(
        '2026-07-27T18:30:00Z',
        Datetime.newInstance(2026, 1, 1, 0, 0, 0)
      )
    );
  }

  @IsTest
  static void parseChangedAtHandlesMillisecondsAndTimezoneSuffix() {
    Datetime changedAt = Datetime.newInstanceGmt(2026, 8, 6, 15, 45, 0);

    System.assertEquals(
      changedAt,
      NotificationChangeModels.parseChangedAt('2026-08-06T15:45:00.000Z')
    );
    System.assertEquals(
      changedAt,
      NotificationChangeModels.parseChangedAt('2026-08-06T15:45:00+0000')
    );
  }

  @IsTest
  static void formatChangedAtDisplayFallsBackToCreatedDate() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Fallback log'
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    logRecord = [
      SELECT Id, CreatedDate
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
      LIMIT 1
    ];

    System.assertEquals(
      logRecord.CreatedDate.format('MM/dd/yyyy h:mm a'),
      NotificationChangeModels.formatChangedAtDisplay(null, logRecord)
    );
  }

  @IsTest
  static void ensureEnrichedJsonAddsMissingRecordAndActorDetails() {
    Account household = new Account(Name = 'Ensure Household');
    NotificationTestDataFactory.insertRecord(household);

    Event eventRecord = new Event(
      Subject = 'Ensure enriched event',
      WhatId = household.Id,
      StartDateTime = System.now().addDays(1),
      EndDateTime = System.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    String sparseJson = '{"triggerType":"Update","objectType":"Event","changedFields":[{"label":"Attendees","apiName":"Attendees","oldDisplay":"(updated)","newDisplay":"(updated)"}]}';
    String enrichedJson = NotificationChangeModels.ensureEnrichedJson(
      sparseJson,
      NotificationConstants.OBJECT_TYPE_EVENT,
      String.valueOf(eventRecord.Id)
    );
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      enrichedJson
    );

    System.assertEquals(String.valueOf(eventRecord.Id), changeContext.recordId);
    System.assertEquals('Ensure enriched event', changeContext.recordLabel);
    System.assertNotEquals(null, changeContext.changedByUserId);
    System.assertNotEquals(null, changeContext.changedAt);
  }

  @IsTest
  static void enrichChangeContextForDisplayUsesLogAndSourceRecordFallbacks() {
    Account household = new Account(Name = 'Display Household');
    NotificationTestDataFactory.insertRecord(household);

    Event eventRecord = new Event(
      Subject = 'Display fallback event',
      WhatId = household.Id,
      StartDateTime = System.now().addDays(1),
      EndDateTime = System.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Change_Context__c = '{"triggerType":"Update","objectType":"Event","changedFields":[{"label":"Attendees","apiName":"Attendees","oldDisplay":"(updated)","newDisplay":"(updated)"}]}'
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    logRecord = [
      SELECT
        Id,
        Source_Type__c,
        Source_Record_Id__c,
        Change_Context__c,
        CreatedDate
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
      LIMIT 1
    ];

    eventRecord = [
      SELECT Id, Subject, LastModifiedById, LastModifiedBy.Name
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    String displayJson = NotificationChangeModels.enrichChangeContextForDisplay(
      logRecord.Change_Context__c,
      logRecord,
      eventRecord
    );
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      displayJson
    );

    System.assertEquals(String.valueOf(eventRecord.Id), changeContext.recordId);
    System.assertEquals('Display fallback event', changeContext.recordLabel);
    System.assertEquals(
      eventRecord.LastModifiedBy.Name,
      changeContext.changedByUserName
    );
    System.assertNotEquals(null, changeContext.changedAt);
  }

  @IsTest
  static void enrichDmlContextIncludesRecordAndUserDetails() {
    Account household = new Account(Name = 'Context Household');
    NotificationTestDataFactory.insertRecord(household);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Task taskRecord = new Task(
      Subject = 'Context Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    changeContext.enrichDmlContext(taskRecord);
    Test.stopTest();

    System.assertEquals(String.valueOf(taskRecord.Id), changeContext.recordId);
    System.assertEquals('Context Task', changeContext.recordLabel);
    System.assertEquals(UserInfo.getUserId(), changeContext.changedByUserId);
    System.assertEquals(UserInfo.getName(), changeContext.changedByUserName);
    System.assertNotEquals(null, changeContext.changedAt);
  }

  @IsTest
  static void toJsonOmitsChangedFieldsForInsert() {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.CHANGE_TYPE_INSERT
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'Subject',
        'Subject',
        null,
        'Should not serialize',
        null,
        'Should not serialize'
      )
    );
    changeContext.recordLabel = 'New Event';

    String jsonValue = changeContext.toJson();

    System.assert(!jsonValue.contains('changedFields'));
    System.assert(jsonValue.contains('Insert'));
  }

  @IsTest
  static void toJsonSuppressesNullFields() {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.recordLabel = 'Updated Event';

    String jsonValue = changeContext.toJson();

    System.assert(jsonValue.contains('recordLabel'));
    System.assert(!jsonValue.contains('recordId'));
    System.assert(!jsonValue.contains('changedByUserName'));
  }

  @IsTest
  static void mergeAndEnrichJsonBuildsContextWhenMissing() {
    Account household = new Account(Name = 'Merge Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Merge Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    String jsonValue = NotificationChangeModels.mergeAndEnrichJson(
      null,
      taskRecord,
      NotificationConstants.OBJECT_TYPE_TASK
    );

    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      jsonValue
    );

    System.assertEquals(NotificationConstants.OBJECT_TYPE_TASK, changeContext.objectType);
    System.assertEquals('Merge Task', changeContext.recordLabel);
    System.assertEquals(UserInfo.getUserId(), changeContext.changedByUserId);
  }

  @IsTest
  static void formatChangedAtDisplayAndResolveDatetime_useChangeContext() {
    Datetime changedAt = Datetime.newInstanceGmt(2026, 8, 27, 16, 15, 0);
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedAt = '2026-08-27T16:15:00Z';

    System.assertEquals(
      changedAt.format('MM/dd/yyyy h:mm a'),
      NotificationChangeModels.formatChangedAtDisplay(changeContext, null)
    );
    System.assertEquals(
      changedAt,
      NotificationChangeModels.resolveChangedAtDatetime(changeContext, null)
    );
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationChangeModels.formatChangedAtDisplay(
        (NotificationChangeModels.ChangeContext) null,
        (Notification_Log__c) null
      )
    );
    System.assertEquals(
      null,
      NotificationChangeModels.resolveChangedAtDatetime(null, null)
    );
  }

  @IsTest
  static void fieldChangeAndTrackedFieldDefinition_assignProvidedValues() {
    NotificationChangeModels.FieldChange fieldChange = new NotificationChangeModels.FieldChange();
    NotificationChangeModels.FieldChange populatedFieldChange = new NotificationChangeModels.FieldChange(
      'OwnerId',
      'Assigned To',
      '005000000000001',
      '005000000000002',
      'Old Owner',
      'New Owner'
    );
    NotificationChangeModels.TrackedFieldDefinition trackedFieldDefinition = new NotificationChangeModels.TrackedFieldDefinition(
      NotificationConstants.OBJECT_TYPE_TASK,
      'OwnerId',
      'Assigned To',
      1,
      true,
      false
    );

    System.assertEquals(null, fieldChange.apiName);
    System.assertEquals('OwnerId', populatedFieldChange.apiName);
    System.assertEquals('New Owner', populatedFieldChange.newDisplay);
    System.assertEquals(NotificationConstants.OBJECT_TYPE_TASK, trackedFieldDefinition.objectType);
    System.assertEquals(true, trackedFieldDefinition.resolveOwnerDisplay);
    System.assertEquals(false, trackedFieldDefinition.resolveLookupDisplay);
  }
}