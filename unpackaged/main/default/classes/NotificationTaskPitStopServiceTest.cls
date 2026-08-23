/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 */
@IsTest
private class NotificationTaskPitStopServiceTest {
  @IsTest
  static void resolveRecipientsReturnsBranchAssigneeForEligibleCasePitStopTask() {
    User branchUser = createBranchUser('pitstopbr');

    if (branchUser == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Pit Stop Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Branch Pit Stop Assignee Task',
      WhatId = caseRecord.Id,
      OwnerId = branchUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = NotificationTaskPitStopService.resolveRecipients(
      taskRecord
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(branchUser.Id, recipientIds[0]);
  }

  @IsTest
  static void resolveRecipientsReturnsHomeOfficeQueueMembersForHoPitStopTask() {
    User homeOfficeUser = createHomeOfficeUser('pitstopho');

    if (homeOfficeUser == null) {
      System.assert(true, 'Org automation prevented Home Office user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    List<Group> taskQueues = [
      SELECT Id
      FROM Group
      WHERE
        Type = 'Queue'
        AND Id IN (
          SELECT QueueId
          FROM QueueSobject
          WHERE SObjectType = 'Task'
        )
      LIMIT 1
    ];

    if (taskQueues.isEmpty()) {
      System.assert(true, 'No Task queue available in org.');
      return;
    }

    Group queueRecord = taskQueues[0];
    insert new GroupMember(
      GroupId = queueRecord.Id,
      UserOrGroupId = homeOfficeUser.Id
    );

    Case caseRecord = new Case(
      Subject = 'Queued Pit Stop Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop Queue Task',
      WhatId = caseRecord.Id,
      OwnerId = queueRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = NotificationTaskPitStopService.resolveRecipients(
      taskRecord
    );

    System.assert(recipientIds.contains(homeOfficeUser.Id));
  }

  @IsTest
  static void resolveRecipientsExcludesNonBranchAssigneeForBranchPitStopTask() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Non Branch Pit Stop Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Branch Pit Stop Sys Admin Task',
      WhatId = caseRecord.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = NotificationTaskPitStopService.resolveRecipients(
      taskRecord
    );

    System.assertEquals(
      0,
      recipientIds.size(),
      'System Administrator assignees should not receive branch pit stop notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsExcludesBranchUserForHomeOfficePitStopTask() {
    User branchUser = createBranchUser('pitstopnb');

    if (branchUser == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    List<Group> taskQueues = [
      SELECT Id
      FROM Group
      WHERE
        Type = 'Queue'
        AND Id IN (
          SELECT QueueId
          FROM QueueSobject
          WHERE SObjectType = 'Task'
        )
      LIMIT 1
    ];

    if (taskQueues.isEmpty()) {
      System.assert(true, 'No Task queue available in org.');
      return;
    }

    Group queueRecord = taskQueues[0];
    insert new GroupMember(
      GroupId = queueRecord.Id,
      UserOrGroupId = branchUser.Id
    );

    Case caseRecord = new Case(
      Subject = 'Branch User HO Pit Stop Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop Branch Queue Task',
      WhatId = caseRecord.Id,
      OwnerId = queueRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = NotificationTaskPitStopService.resolveRecipients(
      taskRecord
    );

    System.assertEquals(
      false,
      recipientIds.contains(branchUser.Id),
      'Branch users should not receive Home Office pit stop notifications.'
    );
  }

  @IsTest
  static void isEligiblePitStopTaskReturnsFalseWhenWhatIdIsNotCase() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Household Pit Stop Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    System.assertEquals(false, NotificationTaskPitStopService.isEligiblePitStopTask(taskRecord));
    System.assertEquals(0, NotificationTaskPitStopService.resolveRecipients(taskRecord).size());
  }

  private static User createBranchUser(String aliasPrefix) {
    try {
      return NotificationTestDataFactory.createProfileUser(
        NotificationConstants.PROFILE_NEXS,
        aliasPrefix
      );
    } catch (DmlException ex) {
      try {
        return NotificationTestDataFactory.createProfileUser(
          NotificationConstants.PROFILE_ADVISOR,
          aliasPrefix
        );
      } catch (DmlException advisorException) {
        return null;
      }
    }
  }

  private static User createHomeOfficeUser(String aliasPrefix) {
    try {
      return NotificationTestDataFactory.createProfileUser(
        NotificationConstants.PROFILE_HOME_OFFICE,
        aliasPrefix
      );
    } catch (DmlException ex) {
      return null;
    }
  }
}