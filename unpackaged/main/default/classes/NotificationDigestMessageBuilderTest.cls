/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-08
 */
@IsTest
private class NotificationDigestMessageBuilderTest {
  @IsTest
  static void buildCreatesConsolidatedTitleAndBody() {
    List<Notification_Log__c> logs = new List<Notification_Log__c>{
      buildLog('First item'),
      buildLog('Second item')
    };

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      logs,
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assertEquals('Case digest — 2 updates', message.title);
    System.assert(message.body.contains('1. First item'));
    System.assert(message.body.contains('2. Second item'));
    System.assertEquals(2, message.itemCount);
  }

  @IsTest
  static void buildTruncatesLongBodiesWithOverflowSuffix() {
    List<Notification_Log__c> logs = new List<Notification_Log__c>();
    for (Integer index = 0; index < 20; index++) {
      logs.add(buildLog('Line ' + index + ' with extra detail text'));
    }

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_TASK,
      logs,
      120
    );

    System.assert(message.body.length() <= 120);
    System.assert(message.body.contains('+ 20 more'));
  }

  @IsTest
  static void buildForChannelUsesPlainTextForInApp() {
    List<Notification_Log__c> logs = new List<Notification_Log__c>{
      buildLog('In-app digest item')
    };

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.buildForChannel(
      NotificationConstants.OBJECT_TYPE_TASK,
      logs,
      NotificationConstants.CHANNEL_IN_APP
    );

    System.assert(message.body.contains('1. In-app digest item'));
    System.assert(!message.body.contains('<table'));
  }

  @IsTest
  static void buildForChannelUsesHtmlTableForEmail() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Email digest builder case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_CASE,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Status__c = NotificationConstants.STATUS_QUEUED,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.buildForChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ logRecord },
      NotificationConstants.CHANNEL_EMAIL
    );

    System.assert(message.body.contains('<table'));
    System.assert(message.body.contains('Email digest builder case'));
    System.assertEquals(
      NotificationDigestMessageBuilder.buildEmailSubject(
        NotificationConstants.OBJECT_TYPE_CASE,
        new List<Notification_Log__c>{ logRecord }
      ),
      message.title
    );
    System.assert(message.title.contains('My Case Digest'));
    System.assert(message.title.contains(context.household.Name));
  }

  @IsTest
  static void buildEmailSubjectUsesSourceTypeAndDate() {
    System.assertEquals(
      'My Notification Digest - ' + Date.today().format(),
      NotificationDigestMessageBuilder.buildEmailSubject()
    );
    System.assertEquals(
      'My Task Digest - ' + Date.today().format(),
      NotificationDigestMessageBuilder.buildEmailSubject(
        NotificationConstants.OBJECT_TYPE_TASK
      )
    );
    System.assertEquals(
      'My Case Digest - ' + Date.today().format(),
      NotificationDigestMessageBuilder.buildEmailSubject(
        NotificationConstants.OBJECT_TYPE_CASE
      )
    );
    System.assertEquals(
      'My Event Digest - ' + Date.today().format(),
      NotificationDigestMessageBuilder.buildEmailSubject(
        NotificationConstants.OBJECT_TYPE_EVENT
      )
    );
  }

  @IsTest
  static void buildEmailSubjectLabelUsesMyObjectDigest() {
    System.assertEquals(
      'My Task Digest',
      NotificationDigestMessageBuilder.buildEmailSubjectLabel(
        NotificationConstants.OBJECT_TYPE_TASK
      )
    );
    System.assertEquals(
      'My Case Digest',
      NotificationDigestMessageBuilder.buildEmailSubjectLabel(
        NotificationConstants.OBJECT_TYPE_CASE
      )
    );
    System.assertEquals(
      'My Event Digest',
      NotificationDigestMessageBuilder.buildEmailSubjectLabel(
        NotificationConstants.OBJECT_TYPE_EVENT
      )
    );
  }

  @IsTest
  static void buildEmailSubjectIncludesHouseholdWhenLogsShareOneHousehold() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = new Notification_Log__c(
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      'My Task Digest — ' +
        context.household.Name +
        ' - ' +
        Date.today().format(),
      NotificationDigestMessageBuilder.buildEmailSubject(
        NotificationConstants.OBJECT_TYPE_TASK,
        new List<Notification_Log__c>{ logRecord }
      )
    );
  }

  @IsTest
  static void buildEmailSubjectOmitsHouseholdWhenLogsSpanMultipleHouseholds() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account otherHousehold = FscDataTestDataFactory.createHouseholdAccount(
      'Other Digest Household'
    );

    String subject = NotificationDigestMessageBuilder.buildEmailSubject(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{
        new Notification_Log__c(Household__c = context.household.Id),
        new Notification_Log__c(Household__c = otherHousehold.Id)
      }
    );

    System.assertEquals(
      'My Case Digest - ' + Date.today().format(),
      subject
    );
    System.assert(!subject.contains(context.household.Name));
    System.assert(!subject.contains(otherHousehold.Name));
  }

  @IsTest
  static void buildEmailSubjectOmitsHouseholdWhenAnyLogHasNoHousehold() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    String subject = NotificationDigestMessageBuilder.buildEmailSubject(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Notification_Log__c>{
        new Notification_Log__c(Household__c = context.household.Id),
        new Notification_Log__c(Household__c = null)
      }
    );

    System.assertEquals('My Task Digest - ' + Date.today().format(), subject);
    System.assert(!subject.contains(context.household.Name));
  }

  @IsTest
  static void buildImmediateEmailSubjectUsesNewAndUpdatedFormats() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Portfolio review case',
      AccountId = context.household.Id
    );
    Task taskRecord = new Task(
      Subject = 'Follow up paperwork',
      WhatId = context.household.Id,
      Status = 'Not Started'
    );
    Event eventRecord = new Event(
      Subject = 'Advisor check-in',
      WhatId = context.household.Id,
      StartDateTime = System.now().addDays(1),
      EndDateTime = System.now().addDays(1).addHours(1)
    );
    NotificationTestDataFactory.insertRecords(
      new List<SObject>{ caseRecord, taskRecord, eventRecord }
    );

    Case insertedCase = [
      SELECT Subject, Case_Branch_Name_DisplayName__c
      FROM Case
      WHERE Id = :caseRecord.Id
    ];
    String expectedCaseSummary = String.isBlank(
        insertedCase.Case_Branch_Name_DisplayName__c
      )
      ? insertedCase.Subject
      : insertedCase.Case_Branch_Name_DisplayName__c;

    System.assertEquals(
      'New Case Created: ' + expectedCaseSummary,
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
          Source_Record_Id__c = String.valueOf(caseRecord.Id),
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_CASE,
              NotificationConstants.CHANGE_TYPE_INSERT
            )
            .toJson()
        )
      )
    );
    System.assertEquals(
      'Case Updated',
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
          Source_Record_Id__c = String.valueOf(caseRecord.Id),
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_CASE,
              NotificationConstants.CHANGE_TYPE_UPDATE
            )
            .toJson()
        )
      )
    );
    System.assertEquals(
      'New Task: Follow up paperwork',
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
          Source_Record_Id__c = String.valueOf(taskRecord.Id),
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_TASK,
              NotificationConstants.CHANGE_TYPE_INSERT
            )
            .toJson()
        )
      )
    );
    System.assertEquals(
      'Task Updated',
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_TASK,
              NotificationConstants.CHANGE_TYPE_UPDATE
            )
            .toJson()
        )
      )
    );
    System.assertEquals(
      'New Event: Advisor check-in',
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
          Source_Record_Id__c = String.valueOf(eventRecord.Id),
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_EVENT,
              NotificationConstants.CHANGE_TYPE_INSERT
            )
            .toJson()
        )
      )
    );
    System.assertEquals(
      'Event Updated',
      NotificationDigestMessageBuilder.buildImmediateEmailSubject(
        new Notification_Log__c(
          Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
          Change_Context__c = new NotificationChangeModels.ChangeContext(
              NotificationConstants.OBJECT_TYPE_EVENT,
              NotificationConstants.CHANGE_TYPE_UPDATE
            )
            .toJson()
        )
      )
    );
  }

  @IsTest
  static void buildPlainTextResolvesSourceDetailWhenBodyMissing() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Resolved digest case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Household__c = context.household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_CASE,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson()
    );

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(message.body.contains('Resolved digest case'));
  }

  @IsTest
  static void buildPlainTextSkipsHtmlBodyValues() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Title fallback',
      Body__c = '<table><tr><td>html body</td></tr></table>',
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = null
    );

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(
      !message.body.contains('html body'),
      'HTML bodies should not be used as plain digest lines'
    );
    System.assert(message.body.contains('Title fallback'));
  }

  @IsTest
  static void buildUsesNotificationLabelWhenSourceTypeBlank() {
    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      null,
      new List<Notification_Log__c>{ buildLog('Blank source type item') },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assertEquals('Notification digest — 1 update', message.title);
  }

  @IsTest
  static void buildReturnsEmptyMessageForEmptyLogs() {
    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>(),
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assertEquals(0, message.itemCount);
    System.assertEquals('', message.body);
  }

  @IsTest
  static void buildForChannelUsesInAppPlainTextPath() {
    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.buildForChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ buildLog('In-app digest item') },
      NotificationConstants.CHANNEL_IN_APP
    );

    System.assert(message.body.contains('In-app digest item'));
  }

  @IsTest
  static void buildUsesTitleFallbackWhenBodyBlank() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Title only item',
      Body__c = null,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK
    );

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(message.title.contains('Task digest'));
    System.assert(message.body.contains('1.'));
  }

  @IsTest
  static void buildUsesEmailTableForEmailBodyLimit() {
    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ buildLog('Email digest row') },
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(message.title.contains('My Case Digest'));
    System.assert(!String.isBlank(message.body));
  }

  @IsTest
  static void buildPlainTextTruncatesWhenBodyExceedsLimit() {
    List<Notification_Log__c> logs = new List<Notification_Log__c>();
    for (Integer index = 0; index < 20; index++) {
      logs.add(buildLog('Digest overflow line ' + index));
    }

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      logs,
      80
    );

    System.assert(message.body.length() <= 80);
    System.assert(message.body.contains('more'));
  }

  @IsTest
  static void buildPlainTextTruncatesWhenAllowedLengthIsZero() {
    List<Notification_Log__c> logs = new List<Notification_Log__c>{
      buildLog('Overflow with zero allowed length')
    };

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      logs,
      3
    );

    System.assert(message.body.length() <= 3);
  }

  @IsTest
  static void buildPlainTextResolvesLineTextWithoutEnrichment() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Unavailable source title',
      Body__c = null,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = null
    );

    String body = NotificationDigestMessageBuilder.buildPlainTextBody(
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(body.contains('Unavailable source title'));
  }

  @IsTest
  static void buildPlainTextUsesNotificationItemWhenNoFallbackText() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = null,
      Body__c = null,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = null
    );

    String body = NotificationDigestMessageBuilder.buildPlainTextBody(
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(body.contains('Notification item'));
  }

  @IsTest
  static void buildPlainTextUsesContextBodyWhenSourceDetailUnavailable() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = null,
      Body__c = null,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = '500000000000001AAA',
      Household__c = null
    );

    String body = NotificationDigestMessageBuilder.buildPlainTextBody(
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.CUSTOM_NOTIFICATION_BODY_LIMIT
    );

    System.assert(body.contains('New case created for this household'));
  }

  private static Notification_Log__c buildLog(String body) {
    return new Notification_Log__c(
      Title__c = body,
      Body__c = body,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE
    );
  }
}