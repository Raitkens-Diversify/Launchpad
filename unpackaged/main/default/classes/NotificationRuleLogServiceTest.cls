/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationRuleLogServiceTest {
  @IsTest
  static void processRecipientCreatesImmediateLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Immediate Rule Log',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationPreferenceService.ResolveResult preferenceResult = new NotificationPreferenceService()
      .resolve(
        NotificationConstants.OBJECT_TYPE_CASE,
        context.recipientUser.Id,
        context.household.Id
      );

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = String.valueOf(caseRecord.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = String.valueOf(caseRecord.Id) + '-test';
    request.preferenceResult = preferenceResult;

    Test.startTest();
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().processRecipient(
      request
    );
    Test.stopTest();

    System.assertEquals(1, result.logs.size());
    System.assertEquals(1, result.immediateLogs.size());
    System.assertEquals(NotificationConstants.STATUS_QUEUED, result.logs[0].Status__c);
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      result.logs[0].Frequency__c
    );
    System.assertEquals(rule.Id, result.logs[0].Notification_Rule__c);
  }

  @IsTest
  static void processRecipientQueuesDigestLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Task taskRecord = new Task(
      Subject = 'Digest Rule Log',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationPreferenceService.ResolveResult preferenceResult = new NotificationPreferenceService()
      .resolve(
        NotificationConstants.OBJECT_TYPE_TASK,
        context.recipientUser.Id,
        context.household.Id
      );

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    request.sourceId = String.valueOf(taskRecord.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = String.valueOf(taskRecord.Id) + '-test';
    request.preferenceResult = preferenceResult;

    Test.startTest();
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().processRecipient(
      request
    );
    Test.stopTest();

    System.assertEquals(1, result.logs.size());
    System.assertEquals(0, result.immediateLogs.size());
    System.assertEquals(NotificationConstants.STATUS_QUEUED, result.logs[0].Status__c);
    System.assertEquals(
      NotificationConstants.FREQUENCY_DIGEST,
      result.logs[0].Frequency__c
    );
  }

  @IsTest
  static void processRecipientSuppressesWhenNoMatchingRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_EVENT;
    request.sourceId = String.valueOf(context.household.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = 'missing-rule';
    request.preferenceResult = new NotificationPreferenceService().resolve(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      context.household.Id
    );

    Test.startTest();
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().processRecipient(
      request
    );
    Test.stopTest();

    System.assertEquals(1, result.logs.size());
    System.assertEquals(0, result.immediateLogs.size());
    System.assertEquals(
      NotificationConstants.STATUS_SUPPRESSED,
      result.logs[0].Status__c
    );
    System.assertEquals(
      NotificationConstants.SUPPRESSION_NO_PREFERENCE,
      result.logs[0].Suppression_Reason__c
    );
  }

  @IsTest
  static void processRecipientCreatesLogsForMultipleChannels() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Multi-channel Rule Log',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationPreferenceService.ResolveResult preferenceResult = new NotificationPreferenceService()
      .resolve(
        NotificationConstants.OBJECT_TYPE_CASE,
        context.recipientUser.Id,
        context.household.Id
      );

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = String.valueOf(caseRecord.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = String.valueOf(caseRecord.Id) + '-multi';
    request.preferenceResult = preferenceResult;

    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().processRecipient(
      request
    );

    System.assertEquals(2, result.logs.size());
    System.assertEquals(2, result.immediateLogs.size());
  }

  @IsTest
  static void buildRecipientLogsFailsWhenNoChannelsConfigured() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    rule.Channel__c = null;
    NotificationTestDataFactory.updateRecord(rule);

    NotificationPreferenceService.ResolveResult preferenceResult = new NotificationPreferenceService()
      .resolve(
        NotificationConstants.OBJECT_TYPE_TASK,
        context.recipientUser.Id,
        context.household.Id
      );
    preferenceResult.preference.Channel__c = null;

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    request.sourceId = String.valueOf(context.household.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = 'missing-channel';
    request.preferenceResult = preferenceResult;

    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().buildRecipientLogs(
      request
    );

    System.assertEquals(1, result.logs.size());
    System.assertEquals(
      NotificationConstants.STATUS_FAILED,
      result.logs[0].Status__c
    );
  }

  @IsTest
  static void buildRecipientLogsReturnsEmptyForNullRequest() {
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().buildRecipientLogs(
      null
    );
    System.assertEquals(0, result.logs.size());
  }

  @IsTest
  static void buildRecipientLogsUsesPerChannelPreferences() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    Notification_Rule__c householdRule = NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Task taskRecord = new Task(
      Subject = 'Per-channel Rule Log',
      WhatId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Map<String, NotificationPreferenceService.ResolveResult> channelPreferenceResults = new NotificationPreferenceService()
      .resolveForRecipientsByChannel(
        NotificationConstants.OBJECT_TYPE_TASK,
        new List<Id>{ context.recipientUser.Id },
        context.household.Id
      )
      .get(context.recipientUser.Id);

    NotificationRuleLogModels.ProcessRecipientRequest request = new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    request.sourceId = String.valueOf(taskRecord.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = String.valueOf(taskRecord.Id) + '-per-channel';
    request.channelPreferenceResults = channelPreferenceResults;

    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService().buildRecipientLogs(
      request
    );

    System.assertEquals(1, result.logs.size());
    System.assertEquals(0, result.immediateLogs.size());
    System.assertEquals(
      householdRule.Id,
      result.logs[0].Notification_Rule__c
    );
    System.assertEquals(
      NotificationConstants.CHANNEL_EMAIL,
      result.logs[0].Channel__c
    );
  }
}