/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationTaskEmailContentServiceTest {
  @IsTest
  static void buildIncludesLinkedTaskCaseAndHouseholdForCaseWhatId() {
    Account household = new Account(Name = 'Case Comment Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Portfolio Review',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationTestDataFactory.insertRecord(new CaseComment(
      ParentId = caseRecord.Id,
      CommentBody = 'Initial portfolio review note.',
      IsPublished = true
    ));
    NotificationTestDataFactory.insertRecord(new CaseComment(
      ParentId = caseRecord.Id,
      CommentBody = 'Latest case comment for email body.',
      IsPublished = true
    ));
    Task taskRecord = new Task(
      Subject = 'Review paperwork',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationTaskEmailContentService.ContentResult result = NotificationTaskEmailContentService.build(
      logRecord
    );

    System.assertEquals('New task', result.title);
    System.assert(result.htmlBody.contains('/lightning/r/Task/'));
    System.assert(result.htmlBody.contains('Change Made'));
    System.assert(result.htmlBody.contains('Case Summary Name'));
    System.assert(result.htmlBody.contains('Case Comments'));
    System.assert(result.htmlBody.contains('Review paperwork'));
    System.assert(result.htmlBody.contains('Latest case comment for email body.'));
    System.assert(
      !result.htmlBody.contains('Initial portfolio review note.'),
      'Email should include only the latest case comment'
    );
    System.assert(result.htmlBody.contains(household.Name));
    System.assertEquals(String.valueOf(taskRecord.Id), result.targetRecordId);
  }

  @IsTest
  static void buildIncludesHouseholdLinkForAccountWhatId() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Household follow up',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationTaskEmailContentService.ContentResult result = NotificationTaskEmailContentService.build(
      logRecord
    );

    System.assert(result.htmlBody.contains('Household follow up'));
    System.assert(
      result.htmlBody.contains(NotificationConstants.DISPLAY_NOT_APPLICABLE),
      'Case row should be unavailable'
    );
    System.assert(result.htmlBody.contains(context.household.Name));
  }

  @IsTest
  static void buildIncludesChangeSummaryForAssignmentUpdate() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('assignee');

    Task taskRecord = new Task(
      Subject = 'Assignment Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

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

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned To',
        String.valueOf(recipientUser.Id),
        String.valueOf(assigneeUser.Id),
        recipientUser.Name,
        assigneeUser.Name
      )
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationTaskEmailContentService.ContentResult result = NotificationTaskEmailContentService.build(
      logRecord
    );

    System.assertEquals('Task assignment changed', result.title);
    System.assert(result.htmlBody.contains('Assigned To'));
    System.assert(result.htmlBody.contains(recipientUser.Name));
    System.assert(result.htmlBody.contains(assigneeUser.Name));
  }

  @IsTest
  static void buildResolvesUserNamesWhenChangeContextContainsIds() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('assigneeids');

    Task taskRecord = new Task(
      Subject = 'Assignment Task IDs',
      WhatId = context.household.Id,
      OwnerId = otherUser.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

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

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned To',
        String.valueOf(recipientUser.Id),
        String.valueOf(assigneeUser.Id),
        String.valueOf(recipientUser.Id),
        String.valueOf(assigneeUser.Id)
      )
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationTaskEmailContentService.ContentResult result = NotificationTaskEmailContentService.build(
      logRecord
    );

    System.assert(
      result.htmlBody.contains(
        '<strong>Assigned To</strong><br/>Old: ' + recipientUser.Name + '<br/>New: ' + assigneeUser.Name
      ),
      'Change Made should show field label with Old and New lines'
    );
    System.assert(
      result.plainBody.contains(
        'Assigned To\nOld: ' + recipientUser.Name + '\nNew: ' + assigneeUser.Name
      )
    );
    System.assertEquals(
      'Assigned To\nOld: ' +
        recipientUser.Name +
        '\nNew: ' +
        assigneeUser.Name,
      NotificationTaskEmailContentService.buildChangeMadePlainText(logRecord)
    );
  }

  @IsTest
  static void enrichLogUsesPlainBodyForInAppChannel() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'In-app task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_IN_APP
    );

    NotificationDigestContentService.enrichLog(logRecord);

    System.assertEquals('New task', logRecord.Title__c);
    System.assert(!logRecord.Body__c.contains('<table'), 'In-app body should be plain text');
    System.assert(logRecord.Body__c.contains('In-app task'));
  }

  @IsTest
  static void buildUsesEmailContentCacheForRepeatedSourceRecord() {
    NotificationEmailContentCache.clear();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Cached email task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationTaskEmailContentService.ContentResult firstResult = NotificationTaskEmailContentService.build(
      logRecord
    );
    NotificationTaskEmailContentService.ContentResult secondResult = NotificationTaskEmailContentService.build(
      logRecord
    );

    String cacheKey = NotificationEmailContentCache.buildSourceKey(
      NotificationConstants.OBJECT_TYPE_TASK,
      String.valueOf(taskRecord.Id)
    );

    System.assertNotEquals(null, NotificationEmailContentCache.get(cacheKey));
    System.assertEquals(firstResult.title, secondResult.title);
    NotificationEmailContentCache.clear();
  }

  @IsTest
  static void emailContentCacheIgnoresBlankKeysAndNullContent() {
    NotificationEmailContentCache.clear();
    NotificationEmailContentCache.put(null, 'ignored');
    NotificationEmailContentCache.put('valid:key', null);
    System.assertEquals(null, NotificationEmailContentCache.get('valid:key'));
    NotificationEmailContentCache.clear();
    System.assertEquals(null, NotificationEmailContentCache.get('valid:key'));
  }

  @IsTest
  static void buildDigestTableRendersTableForDigestLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Task taskRecord = new Task(
      Subject = 'Digest table task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest table item',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    String digestTable = NotificationTaskEmailContentService.buildDigestTable(
      new List<Notification_Log__c>{ logRecord },
      32000
    );

    System.assert(!String.isBlank(digestTable));
    System.assert(digestTable.contains('Digest table task') || digestTable.contains('table'));
  }

  @IsTest
  static void loadPresentationFieldsForLogsReturnsFieldsByLogId() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Task taskRecord = new Task(
      Subject = 'Presentation task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Presentation item',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    logRecord.Change_Context__c = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_TASK,
        NotificationConstants.CHANGE_TYPE_INSERT
      )
      .toJson();
    NotificationTestDataFactory.updateRecord(logRecord);

    Map<Id, NotificationCenterModels.LogPresentationFields> fieldsByLogId = NotificationTaskEmailContentService.loadPresentationFieldsForLogs(
      new List<Notification_Log__c>{ logRecord }
    );

    System.assertEquals(1, fieldsByLogId.size());
    System.assertNotEquals(null, fieldsByLogId.get(logRecord.Id).changeMadePlainText);
  }

  @IsTest
  static void buildChangeMadePlainTextReturnsNaForMissingSourceRecord() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationTaskEmailContentService.buildChangeMadePlainText(logRecord)
    );
    System.assertNotEquals(
      null,
      NotificationTaskEmailContentService.buildChangedAtDisplay(logRecord)
    );
  }
}