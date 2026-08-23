/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationDigestEmailTableBuilderTest {
  @IsTest
  static void buildCaseDigestTableUsesSingleHeaderWithMultipleRows() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Digest row one',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Due_Date_of_Current_Task__c = Date.today().addDays(3)
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Case secondCase = new Case(
      Subject = 'Digest row two',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Due_Date_of_Current_Task__c = Date.today().addDays(5)
    );
    NotificationTestDataFactory.insertRecord(secondCase);

    insert new CaseComment(
      ParentId = caseRecord.Id,
      CommentBody = 'First digest comment',
      IsPublished = true
    );

    Notification_Log__c firstLog = buildDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );
    Notification_Log__c secondLog = buildDigestLog(
      context,
      secondCase.Id,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    NotificationTestDataFactory.insertRecords(
      new List<Notification_Log__c>{ firstLog, secondLog }
    );

    String htmlBody = NotificationDigestEmailTableBuilder.build(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ firstLog, secondLog },
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(htmlBody.contains('Change Date'));
    System.assert(htmlBody.contains('Financial Advisor Team'));
    System.assert(htmlBody.contains('Digest row one'));
    System.assert(htmlBody.contains('Digest row two'));
    System.assertEquals(1, htmlBody.countMatches('<thead>'));
    System.assertEquals(2, htmlBody.countMatches('<tr><td>'));
  }

  @IsTest
  static void buildEmailDigestMessageUsesHtmlTableBody() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Digest email case',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = buildDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );
    NotificationTestDataFactory.insertRecord(logRecord);

    NotificationDigestModels.ConsolidatedMessage message = NotificationDigestMessageBuilder.buildForChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Notification_Log__c>{ logRecord },
      NotificationConstants.CHANNEL_EMAIL
    );

    System.assertEquals(
      NotificationDigestMessageBuilder.buildEmailSubject(),
      message.title
    );
    System.assert(message.body.contains('<table'));
    System.assert(message.body.contains('Change Date'));
    System.assert(message.body.contains('Digest email case'));
    System.assert(!message.body.contains('1. '));
  }

  @IsTest
  static void buildTaskDigestTableUsesSingleHeaderWithMultipleRows() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Linked digest case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task firstTask = new Task(
      Subject = 'Digest task one',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    Task secondTask = new Task(
      Subject = 'Digest task two',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecords(
      new List<Task>{ firstTask, secondTask }
    );

    Notification_Log__c firstLog = buildTaskDigestLog(context, firstTask.Id);
    Notification_Log__c secondLog = buildTaskDigestLog(context, secondTask.Id);
    NotificationTestDataFactory.insertRecords(
      new List<Notification_Log__c>{ firstLog, secondLog }
    );

    String htmlBody = NotificationDigestEmailTableBuilder.build(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Notification_Log__c>{ firstLog, secondLog },
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(htmlBody.contains('Digest task one'));
    System.assert(htmlBody.contains('Digest task two'));
    System.assertEquals(1, htmlBody.countMatches('<thead>'));
    System.assertEquals(2, htmlBody.countMatches('<tr><td>'));
  }

  @IsTest
  static void buildEventDigestTableUsesSingleHeaderWithMultipleRows() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Event firstEvent = new Event(
      Subject = 'Digest event one',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = context.household.Id
    );
    Event secondEvent = new Event(
      Subject = 'Digest event two',
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60,
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecords(
      new List<Event>{ firstEvent, secondEvent }
    );

    Notification_Log__c firstLog = buildEventDigestLog(context, firstEvent.Id);
    Notification_Log__c secondLog = buildEventDigestLog(context, secondEvent.Id);
    NotificationTestDataFactory.insertRecords(
      new List<Notification_Log__c>{ firstLog, secondLog }
    );

    String htmlBody = NotificationDigestEmailTableBuilder.build(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<Notification_Log__c>{ firstLog, secondLog },
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(htmlBody.contains('Digest event one'));
    System.assert(htmlBody.contains('Digest event two'));
    System.assert(htmlBody.contains('Change Date'));
    System.assertEquals(1, htmlBody.countMatches('<thead>'));
    System.assertEquals(2, htmlBody.countMatches('<tr><td>'));
  }

  @IsTest
  static void buildCaseDigestTableAppliesAc1AndAc2GroupingRules() {
    assertDigestTableAppliesAc1AndAc2GroupingRules(
      NotificationConstants.OBJECT_TYPE_CASE,
      buildCaseDigestScenario()
    );
  }

  @IsTest
  static void buildTaskDigestTableAppliesAc1AndAc2GroupingRules() {
    assertDigestTableAppliesAc1AndAc2GroupingRules(
      NotificationConstants.OBJECT_TYPE_TASK,
      buildTaskDigestScenario()
    );
  }

  @IsTest
  static void buildEventDigestTableAppliesAc1AndAc2GroupingRules() {
    assertDigestTableAppliesAc1AndAc2GroupingRules(
      NotificationConstants.OBJECT_TYPE_EVENT,
      buildEventDigestScenario()
    );
  }

  @IsTest
  static void buildFallsBackToPlainTextForUnknownSourceType() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Fallback item',
      Body__c = 'Fallback body',
      Source_Type__c = 'CustomObject'
    );

    String body = NotificationDigestEmailTableBuilder.build(
      'CustomObject',
      new List<Notification_Log__c>{ logRecord },
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(body.contains('1. Fallback body'));
  }

  private class DigestAcScenario {
    public List<Notification_Log__c> logs;
    public String alphaHouseholdName;
    public String betaHouseholdName;
    public String alphaEarlierSubject;
    public String alphaLaterSubject;
    public String otherNotificationsSubject;
  }

  private static void assertDigestTableAppliesAc1AndAc2GroupingRules(
    String sourceType,
    DigestAcScenario scenario
  ) {
    NotificationTestDataFactory.insertRecords(scenario.logs);

    String htmlBody = NotificationDigestEmailTableBuilder.build(
      sourceType,
      scenario.logs,
      NotificationDigestMessageBuilder.EMAIL_BODY_LIMIT
    );

    System.assert(htmlBody.contains('Subject'), 'Expected Subject column header');
    System.assert(htmlBody.contains('Change Made'), 'Expected Change Made column header');
    System.assert(htmlBody.contains('Assigned To'), 'Expected Assigned To column header');
    System.assert(
      htmlBody.contains('Change Date'),
      'Expected Change Date column header'
    );
    System.assert(htmlBody.contains('Household'), 'Expected Household column header');
    System.assert(
      htmlBody.contains('Financial Advisor Team'),
      'Expected Financial Advisor Team column header'
    );
    System.assertEquals(1, htmlBody.countMatches('<thead>'), 'Expected one table header');

    Integer alphaSectionIndex = htmlBody.indexOf(scenario.alphaHouseholdName);
    Integer betaSectionIndex = htmlBody.indexOf(scenario.betaHouseholdName);
    Integer otherSectionIndex = htmlBody.indexOf(
      NotificationDigestEmailGroupingService.OTHER_NOTIFICATIONS_SECTION
    );
    Integer alphaEarlierIndex = htmlBody.indexOf(scenario.alphaEarlierSubject);
    Integer alphaLaterIndex = htmlBody.indexOf(scenario.alphaLaterSubject);
    Integer otherSubjectIndex = htmlBody.indexOf(scenario.otherNotificationsSubject);

    System.assert(alphaSectionIndex >= 0, 'Expected Alpha household section header');
    System.assert(betaSectionIndex > alphaSectionIndex, 'Expected Beta section after Alpha');
    System.assert(
      otherSectionIndex > betaSectionIndex,
      'Expected Other Notifications section after household sections'
    );
    System.assert(
      alphaEarlierIndex > alphaSectionIndex,
      'Expected earlier Alpha row after Alpha section header'
    );
    System.assert(
      alphaLaterIndex > alphaEarlierIndex,
      'Expected Alpha rows sorted by Change Date ascending'
    );
    System.assert(
      otherSubjectIndex > otherSectionIndex,
      'Expected AC2 row after Other Notifications section header'
    );
  }

  private static DigestAcScenario buildCaseDigestScenario() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account alphaHousehold;
    Account betaHousehold;

    System.runAs(NotificationTestDataFactory.runningUser()) {
      alphaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Alpha Digest Household'
      );
      betaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Beta Digest Household'
      );
    }

    Case alphaEarlierCase = new Case(
      Subject = 'Alpha earlier case',
      AccountId = alphaHousehold.Id,
      Status = 'New'
    );
    Case alphaLaterCase = new Case(
      Subject = 'Alpha later case',
      AccountId = alphaHousehold.Id,
      Status = 'New'
    );
    Case betaCase = new Case(
      Subject = 'Beta digest case',
      AccountId = betaHousehold.Id,
      Status = 'New'
    );
    Case otherCase = new Case(
      Subject = 'Other notifications case',
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecords(
      new List<Case>{ alphaEarlierCase, alphaLaterCase, betaCase, otherCase }
    );

    DigestAcScenario scenario = new DigestAcScenario();
    scenario.alphaHouseholdName = alphaHousehold.Name;
    scenario.betaHouseholdName = betaHousehold.Name;
    scenario.alphaEarlierSubject = alphaEarlierCase.Subject;
    scenario.alphaLaterSubject = alphaLaterCase.Subject;
    scenario.otherNotificationsSubject = otherCase.Subject;
    scenario.logs = new List<Notification_Log__c>{
      buildDigestLogWithChangedAt(
        context,
        alphaLaterCase.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        alphaHousehold.Id,
        '2026-07-29T15:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        alphaEarlierCase.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        alphaHousehold.Id,
        '2026-07-29T10:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        betaCase.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        betaHousehold.Id,
        '2026-07-29T12:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        otherCase.Id,
        NotificationConstants.OBJECT_TYPE_CASE,
        null,
        '2026-07-29T09:00:00Z'
      )
    };
    return scenario;
  }

  private static DigestAcScenario buildTaskDigestScenario() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account alphaHousehold;
    Account betaHousehold;

    System.runAs(NotificationTestDataFactory.runningUser()) {
      alphaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Alpha Digest Household'
      );
      betaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Beta Digest Household'
      );
    }

    Task alphaEarlierTask = new Task(
      Subject = 'Alpha earlier task',
      WhatId = alphaHousehold.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    Task alphaLaterTask = new Task(
      Subject = 'Alpha later task',
      WhatId = alphaHousehold.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    Task betaTask = new Task(
      Subject = 'Beta digest task',
      WhatId = betaHousehold.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    Task otherTask = new Task(
      Subject = 'Other notifications task',
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecords(
      new List<Task>{ alphaEarlierTask, alphaLaterTask, betaTask, otherTask }
    );

    DigestAcScenario scenario = new DigestAcScenario();
    scenario.alphaHouseholdName = alphaHousehold.Name;
    scenario.betaHouseholdName = betaHousehold.Name;
    scenario.alphaEarlierSubject = alphaEarlierTask.Subject;
    scenario.alphaLaterSubject = alphaLaterTask.Subject;
    scenario.otherNotificationsSubject = otherTask.Subject;
    scenario.logs = new List<Notification_Log__c>{
      buildDigestLogWithChangedAt(
        context,
        alphaLaterTask.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        alphaHousehold.Id,
        '2026-07-29T15:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        alphaEarlierTask.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        alphaHousehold.Id,
        '2026-07-29T10:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        betaTask.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        betaHousehold.Id,
        '2026-07-29T12:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        otherTask.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        null,
        '2026-07-29T09:00:00Z'
      )
    };
    return scenario;
  }

  private static DigestAcScenario buildEventDigestScenario() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account alphaHousehold;
    Account betaHousehold;

    System.runAs(NotificationTestDataFactory.runningUser()) {
      alphaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Alpha Digest Household'
      );
      betaHousehold = FscDataTestDataFactory.createHouseholdAccount(
        'Beta Digest Household'
      );
    }

    Event alphaEarlierEvent = buildDigestEvent('Alpha earlier event', alphaHousehold.Id);
    Event alphaLaterEvent = buildDigestEvent('Alpha later event', alphaHousehold.Id);
    Event betaEvent = buildDigestEvent('Beta digest event', betaHousehold.Id);
    Event otherEvent = buildDigestEvent('Other notifications event', null);
    NotificationTestDataFactory.insertRecords(
      new List<Event>{ alphaEarlierEvent, alphaLaterEvent, betaEvent, otherEvent }
    );

    DigestAcScenario scenario = new DigestAcScenario();
    scenario.alphaHouseholdName = alphaHousehold.Name;
    scenario.betaHouseholdName = betaHousehold.Name;
    scenario.alphaEarlierSubject = alphaEarlierEvent.Subject;
    scenario.alphaLaterSubject = alphaLaterEvent.Subject;
    scenario.otherNotificationsSubject = otherEvent.Subject;
    scenario.logs = new List<Notification_Log__c>{
      buildDigestLogWithChangedAt(
        context,
        alphaLaterEvent.Id,
        NotificationConstants.OBJECT_TYPE_EVENT,
        alphaHousehold.Id,
        '2026-07-29T15:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        alphaEarlierEvent.Id,
        NotificationConstants.OBJECT_TYPE_EVENT,
        alphaHousehold.Id,
        '2026-07-29T10:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        betaEvent.Id,
        NotificationConstants.OBJECT_TYPE_EVENT,
        betaHousehold.Id,
        '2026-07-29T12:00:00Z'
      ),
      buildDigestLogWithChangedAt(
        context,
        otherEvent.Id,
        NotificationConstants.OBJECT_TYPE_EVENT,
        null,
        '2026-07-29T09:00:00Z'
      )
    };
    return scenario;
  }

  private static Event buildDigestEvent(String subject, Id householdId) {
    return new Event(
      Subject = subject,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = householdId
    );
  }

  private static Notification_Log__c buildDigestLogWithChangedAt(
    NotificationTestDataFactory.NotificationTestContext context,
    Id sourceRecordId,
    String sourceType,
    Id householdId,
    String changedAtIso
  ) {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      sourceType,
      NotificationConstants.CHANGE_TYPE_INSERT
    );
    changeContext.changedAt = changedAtIso;

    return new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = householdId,
      Source_Type__c = sourceType,
      Source_Record_Id__c = String.valueOf(sourceRecordId),
      Change_Context__c = changeContext.toJson(),
      Status__c = NotificationConstants.STATUS_QUEUED,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
  }

  private static Notification_Log__c buildTaskDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id taskId
  ) {
    return new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = String.valueOf(taskId),
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Status__c = NotificationConstants.STATUS_QUEUED,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
  }

  private static Notification_Log__c buildEventDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id eventId
  ) {
    return new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventId),
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_EVENT,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Status__c = NotificationConstants.STATUS_QUEUED,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
  }

  private static Notification_Log__c buildDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id caseId,
    String changeType
  ) {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      changeType
    );

    if (changeType == NotificationConstants.CHANGE_TYPE_UPDATE) {
      changeContext.changedFields.add(
        new NotificationChangeModels.FieldChange(
          'Status',
          'Status',
          'New',
          'In Progress',
          'New',
          'In Progress'
        )
      );
    }

    return new Notification_Log__c(
      Recipient__c = context.recipientUser.Id,
      Household__c = context.household.Id,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseId),
      Change_Context__c = changeContext.toJson(),
      Status__c = NotificationConstants.STATUS_QUEUED,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST
    );
  }
}