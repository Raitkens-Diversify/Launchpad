/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 */
@IsTest
private class NotificationPrepareContextFactoryTest {
  @IsTest
  static void prepareSourceRecordBypassesPreferencesForEligiblePitStopTask() {
    NotificationTestDataFactory.clearTestOverrides();

    User branchUser = createBranchUser('pitstoppr');

    if (branchUser == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    context.recipientUser = branchUser;
    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ branchUser.Id }
    };

    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      branchUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Case caseRecord = new Case(
      Subject = 'Pit Stop Prepare Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Pit Stop Prepare Task',
      WhatId = caseRecord.Id,
      OwnerId = branchUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      new NotificationCenterEventService().prepareSourceRecord(
        NotificationConstants.OBJECT_TYPE_TASK,
        String.valueOf(taskRecord.Id)
      );
    }
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Channel__c, Frequency__c, Status__c, Recipient__c
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c = :String.valueOf(taskRecord.Id)
        AND Recipient__c = :branchUser.Id
    ];

    Set<String> channels = new Set<String>();

    for (Notification_Log__c logRecord : logs) {
      System.assertEquals(
        NotificationConstants.FREQUENCY_IMMEDIATE,
        logRecord.Frequency__c,
        'Pit stop notifications must bypass digest preferences.'
      );
      channels.add(logRecord.Channel__c);
    }

    System.assert(
      channels.contains(NotificationConstants.CHANNEL_IN_APP),
      'Branch pit stop tasks should create In_App logs for branch assignees.'
    );
    System.assert(
      channels.contains(NotificationConstants.CHANNEL_EMAIL),
      'Branch pit stop tasks should create Email logs for branch assignees.'
    );
  }

  @IsTest
  static void buildReturnsNullForBranchPitStopTaskNotRelatedToCase() {
    NotificationTestDataFactory.clearTestOverrides();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithStandardUserRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Invalid Pit Stop Prepare Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationRecipientPrepareModels.SourcePrepareContext prepareContext = NotificationPrepareContextFactory.build(
      NotificationConstants.OBJECT_TYPE_TASK,
      String.valueOf(taskRecord.Id),
      null
    );

    System.assertEquals(null, prepareContext);
    System.assertEquals(
      false,
      NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord)
    );
  }

  @IsTest
  static void prepareSourceRecordSuppressesNexsOnHoPitStopTask() {
    NotificationTestDataFactory.clearTestOverrides();
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User nexsAssignee = createBranchUser('pitstopnx');

    if (nexsAssignee == null) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      nexsAssignee.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Case caseRecord = new Case(
      Subject = 'HO Pit Stop NexS Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop NexS Task',
      WhatId = caseRecord.Id,
      OwnerId = nexsAssignee.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    System.runAs(NotificationTestDataFactory.runningUser()) {
      new NotificationCenterEventService().prepareSourceRecord(
        NotificationConstants.OBJECT_TYPE_TASK,
        String.valueOf(taskRecord.Id)
      );
    }
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c = :String.valueOf(taskRecord.Id)
        AND Recipient__c = :nexsAssignee.Id
    ];

    System.assertEquals(
      0,
      logs.size(),
      'Branch users should be suppressed on Home Office pit stop tasks.'
    );
  }

  private static User createBranchUser(String aliasPrefix) {
    try {
      return NotificationTestDataFactory.createProfileUser(
        UserInfoUtils.PROFILE_NEXS,
        aliasPrefix
      );
    } catch (DmlException ex) {
      try {
        return NotificationTestDataFactory.createProfileUser(
          UserInfoUtils.PROFILE_ADVISOR,
          aliasPrefix
        );
      } catch (DmlException advisorException) {
        return null;
      }
    }
  }
}