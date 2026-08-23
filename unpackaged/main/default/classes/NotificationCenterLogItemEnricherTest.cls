/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 */
@IsTest
private class NotificationCenterLogItemEnricherTest {
  @IsTest
  static void enrichItemsUsesEmailChangeMadeSummaryForQueuedTaskUpdates() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User assigneeUser = NotificationTestDataFactory.createStandardUser('logassignee');

    Task taskRecord = new Task(
      Subject = 'Queued assignment task',
      WhatId = context.household.Id,
      OwnerId = assigneeUser.Id,
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
    User resolvedAssigneeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :assigneeUser.Id
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
        String.valueOf(resolvedAssigneeUser.Id),
        String.valueOf(recipientUser.Id),
        String.valueOf(resolvedAssigneeUser.Id)
      )
    );

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Queued task assignment',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    logRecord.Change_Context__c = changeContext.toJson();
    NotificationTestDataFactory.updateRecord(logRecord);

    Map<Id, String> changeContextByLogId = NotificationChangeModels.enrichChangeContextsForDisplay(
      new List<Notification_Log__c>{ logRecord }
    );
    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.id = logRecord.Id;
    item.sourceType = logRecord.Source_Type__c;
    item.sourceRecordId = logRecord.Source_Record_Id__c;
    item.changeContext = changeContextByLogId.get(logRecord.Id);

    NotificationCenterLogItemEnricher.enrichItems(
      new List<NotificationCenterModels.LogItem>{ item },
      new List<Notification_Log__c>{ logRecord }
    );

    String expectedChangeMade = NotificationTaskEmailContentService.buildChangeMadePlainText(
      logRecord
    );
    NotificationCenterModels.LogPresentationFields expectedPresentation = NotificationTaskEmailContentService.loadPresentationFieldsForLogs(
      new List<Notification_Log__c>{ logRecord }
    )
    .get(logRecord.Id);

    System.assertEquals(
      expectedChangeMade,
      item.changeMade,
      'Log Change Made should match email body summary for queued notifications'
    );
    System.assertEquals(
      expectedPresentation.changedAtDisplay,
      item.changeDateLabel,
      'Log Change Date should match email body display for queued notifications'
    );
    System.assertEquals(
      expectedPresentation.changedAtDatetime,
      item.changeDate,
      'Log Change Date value should match email sort datetime'
    );
    System.assert(
      item.changeMade.contains('Assigned To'),
      'Change Made should include the email field label'
    );
    System.assert(
      item.changeMade.contains('Old: ' + recipientUser.Name),
      'Change Made should resolve old owner display name'
    );
    System.assert(
      item.changeMade.contains('New: ' + resolvedAssigneeUser.Name),
      'Change Made should resolve new owner display name'
    );
  }

  @IsTest
  static void applyContextFiltersMatchesSubjectOnly() {
    NotificationCenterModels.LogItem matchingItem = new NotificationCenterModels.LogItem();
    matchingItem.subject = 'Portfolio review meeting';
    matchingItem.title = 'Ignored title';
    matchingItem.changeDate = System.now();

    NotificationCenterModels.LogItem nonMatchingItem = new NotificationCenterModels.LogItem();
    nonMatchingItem.subject = 'Tax planning follow up';
    nonMatchingItem.title = 'Annual review summary';
    nonMatchingItem.changeDate = System.now();

    List<NotificationCenterModels.LogItem> filteredItems = NotificationCenterLogItemEnricher.applyContextFilters(
      new List<NotificationCenterModels.LogItem>{ matchingItem, nonMatchingItem },
      Date.today(),
      Date.today(),
      'portfolio review'
    );

    System.assertEquals(1, filteredItems.size());
    System.assertEquals(matchingItem.subject, filteredItems[0].subject);
  }

  @IsTest
  static void applyFacetFiltersMatchesSelectedHouseholdAndBranch() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Id householdId = context.household.Id;

    NotificationCenterModels.LogItem matchingItem = new NotificationCenterModels.LogItem();
    matchingItem.householdId = householdId;
    matchingItem.branchName = 'DAS Branch';

    NotificationCenterModels.LogItem wrongHousehold = new NotificationCenterModels.LogItem();
    wrongHousehold.householdId = UserInfo.getUserId();
    wrongHousehold.branchName = 'DAS Branch';

    NotificationCenterModels.LogItem wrongBranch = new NotificationCenterModels.LogItem();
    wrongBranch.householdId = householdId;
    wrongBranch.branchName = 'DWM Branch';

    List<NotificationCenterModels.LogItem> filteredItems = NotificationCenterLogItemEnricher.applyFacetFilters(
      new List<NotificationCenterModels.LogItem>{
        matchingItem,
        wrongHousehold,
        wrongBranch
      },
      new List<String>{ String.valueOf(householdId) },
      new List<String>{ 'DAS Branch' }
    );

    System.assertEquals(1, filteredItems.size());
    System.assertEquals(matchingItem.householdId, filteredItems[0].householdId);
    System.assertEquals(matchingItem.branchName, filteredItems[0].branchName);
  }

  @IsTest
  static void collectFilterOptionsReturnsDistinctHouseholdAndBranchValues() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    String householdKey = String.valueOf(context.household.Id);

    NotificationCenterModels.LogItem firstItem = new NotificationCenterModels.LogItem();
    firstItem.householdId = context.household.Id;
    firstItem.householdName = context.household.Name;
    firstItem.branchName = 'DAS Branch';

    NotificationCenterModels.LogItem secondItem = new NotificationCenterModels.LogItem();
    secondItem.householdId = context.household.Id;
    secondItem.householdName = context.household.Name;
    secondItem.branchName = 'DWM Branch';

    Map<String, NotificationCenterModels.FilterOption> householdOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();
    Map<String, NotificationCenterModels.FilterOption> branchOptionsByValue = new Map<String, NotificationCenterModels.FilterOption>();

    NotificationCenterLogItemEnricher.collectFilterOptions(
      new List<NotificationCenterModels.LogItem>{ firstItem, secondItem },
      householdOptionsByValue,
      branchOptionsByValue
    );

    System.assertEquals(1, householdOptionsByValue.size());
    System.assertEquals(2, branchOptionsByValue.size());
    System.assertEquals(
      context.household.Name,
      householdOptionsByValue.get(householdKey).label
    );
  }

  @IsTest
  static void filterLogsByChangeDateRange_excludesOutOfRangeLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Datetime todayChangedAt = System.now();
    Datetime oldChangedAt = todayChangedAt.addDays(-30);

    NotificationChangeModels.ChangeContext todayChangeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    todayChangeContext.changedAt = todayChangedAt.formatGmt(
      'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
    );

    NotificationChangeModels.ChangeContext oldChangeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    oldChangeContext.changedAt = oldChangedAt.formatGmt(
      'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
    );

    Notification_Log__c todayLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Today change',
      null,
      null
    );
    todayLog.Change_Context__c = todayChangeContext.toJson();
    NotificationTestDataFactory.updateRecord(todayLog);

    Notification_Log__c oldLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Old change',
      null,
      null
    );
    oldLog.Change_Context__c = oldChangeContext.toJson();
    NotificationTestDataFactory.updateRecord(oldLog);

    List<Notification_Log__c> filteredLogs = NotificationCenterLogItemEnricher.filterLogsByChangeDateRange(
      new List<Notification_Log__c>{ todayLog, oldLog },
      Date.today(),
      Date.today()
    );

    System.assertEquals(1, filteredLogs.size());
    System.assertEquals(todayLog.Id, filteredLogs[0].Id);
  }

  @IsTest
  static void applyPresentationFilters_appliesBranchAndSearchTogether() {
    NotificationCenterModels.LogItem matchingItem = new NotificationCenterModels.LogItem();
    matchingItem.subject = 'Portfolio review meeting';
    matchingItem.title = 'Portfolio review meeting';
    matchingItem.branchName = 'DAS Branch';
    matchingItem.changeDate = System.now();

    NotificationCenterModels.LogItem wrongBranch = new NotificationCenterModels.LogItem();
    wrongBranch.subject = 'Portfolio review follow up';
    wrongBranch.title = 'Portfolio review follow up';
    wrongBranch.branchName = 'DWM Branch';
    wrongBranch.changeDate = System.now();

    NotificationCenterModels.LogItem wrongSearch = new NotificationCenterModels.LogItem();
    wrongSearch.subject = 'Tax planning follow up';
    wrongSearch.title = 'Tax planning follow up';
    wrongSearch.branchName = 'DAS Branch';
    wrongSearch.changeDate = System.now();

    List<NotificationCenterModels.LogItem> filteredItems = NotificationCenterLogItemEnricher.applyPresentationFilters(
      new List<NotificationCenterModels.LogItem>{
        matchingItem,
        wrongBranch,
        wrongSearch
      },
      Date.today(),
      Date.today(),
      'DAS Branch',
      'portfolio review'
    );

    System.assertEquals(1, filteredItems.size());
    System.assertEquals(matchingItem.subject, filteredItems[0].subject);
  }

  @IsTest
  static void buildPresentationDedupKey_stripsChannelSuffixFromCorrelationKey() {
    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.recipientId = UserInfo.getUserId();
    item.sourceRecordId = '00T000000000001';
    item.sourceType = NotificationConstants.OBJECT_TYPE_TASK;

    Notification_Log__c notification = new Notification_Log__c(
      Correlation_Key__c = 'task-change-key-' + NotificationConstants.CHANNEL_EMAIL
    );

    String dedupKey = NotificationCenterLogItemEnricher.buildPresentationDedupKey(
      item,
      notification
    );

    System.assertEquals(
      String.valueOf(item.recipientId) + '|task-change-key',
      dedupKey
    );
  }

  @IsTest
  static void sortBatchItemsByChannelPreference_prefersInAppOverEmail() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Log__c emailLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Email channel item',
      null,
      null
    );
    Notification_Log__c inAppLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'In-app channel item',
      null,
      null
    );

    NotificationCenterModels.LogItem emailItem = new NotificationCenterModels.LogItem();
    emailItem.id = emailLog.Id;

    NotificationCenterModels.LogItem inAppItem = new NotificationCenterModels.LogItem();
    inAppItem.id = inAppLog.Id;

    List<NotificationCenterModels.LogItem> items = new List<NotificationCenterModels.LogItem>{
      emailItem,
      inAppItem
    };
    Map<Id, Notification_Log__c> notificationById = new Map<Id, Notification_Log__c>{
      emailLog.Id => emailLog,
      inAppLog.Id => inAppLog
    };

    NotificationCenterLogItemEnricher.sortBatchItemsByChannelPreference(
      items,
      notificationById
    );

    System.assertEquals(inAppLog.Id, items[0].id);
    System.assertEquals(emailLog.Id, items[1].id);
  }

  @IsTest
  static void enrichItems_populatesCaseSubjectFromSourceRecord() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Case caseRecord = new Case(
      Subject = 'Enriched case subject',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Case update notification',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(caseRecord.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.id = logRecord.Id;
    item.sourceType = logRecord.Source_Type__c;
    item.sourceRecordId = logRecord.Source_Record_Id__c;
    item.title = logRecord.Title__c;

    NotificationCenterLogItemEnricher.enrichItems(
      new List<NotificationCenterModels.LogItem>{ item },
      new List<Notification_Log__c>{ logRecord }
    );

    System.assertEquals('Enriched case subject', item.subject);
  }

  @IsTest
  static void enrichItemsUsesFallbackPresentationWhenNoSpecializedFields() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Fallback title',
      'Fallback body',
      null
    );

    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.id = logRecord.Id;
    item.title = logRecord.Title__c;
    item.sourceType = logRecord.Source_Type__c;
    item.sourceRecordId = null;

    NotificationCenterLogItemEnricher.enrichItems(
      new List<NotificationCenterModels.LogItem>{ item },
      new List<Notification_Log__c>{ logRecord }
    );

    System.assertEquals('Fallback title', item.subject);
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      item.assignedTo
    );
  }

  @IsTest
  static void applyContextFiltersReturnsAllWhenSearchBlank() {
    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.subject = 'Any subject';
    item.changeDate = System.now();

    List<NotificationCenterModels.LogItem> filteredItems = NotificationCenterLogItemEnricher.applyContextFilters(
      new List<NotificationCenterModels.LogItem>{ item },
      null,
      null,
      null
    );

    System.assertEquals(1, filteredItems.size());
  }

  @IsTest
  static void applyFacetFiltersReturnsAllWhenNoFacetsSelected() {
    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.householdId = UserInfo.getUserId();
    item.branchName = 'Any Branch';

    List<NotificationCenterModels.LogItem> filteredItems = NotificationCenterLogItemEnricher.applyFacetFilters(
      new List<NotificationCenterModels.LogItem>{ item },
      new List<String>(),
      new List<String>()
    );

    System.assertEquals(1, filteredItems.size());
  }

  @IsTest
  static void filterLogsByChangeDateRangeReturnsAllWhenDatesNull() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'No date filter',
      null,
      null
    );

    List<Notification_Log__c> filteredLogs = NotificationCenterLogItemEnricher.filterLogsByChangeDateRange(
      new List<Notification_Log__c>{ logRecord },
      null,
      null
    );

    System.assertEquals(1, filteredLogs.size());
  }

  @IsTest
  static void enrichItems_populatesEventSubjectFromSourceRecord() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Event eventRecord = new Event(
      Subject = 'Enriched event subject',
      WhatId = context.household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Event update notification',
      null,
      null
    );
    logRecord.Source_Record_Id__c = String.valueOf(eventRecord.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    NotificationCenterModels.LogItem item = new NotificationCenterModels.LogItem();
    item.id = logRecord.Id;
    item.sourceType = logRecord.Source_Type__c;
    item.sourceRecordId = logRecord.Source_Record_Id__c;
    item.title = logRecord.Title__c;

    NotificationCenterLogItemEnricher.enrichItems(
      new List<NotificationCenterModels.LogItem>{ item },
      new List<Notification_Log__c>{ logRecord }
    );

    System.assertEquals('Enriched event subject', item.subject);
  }
}