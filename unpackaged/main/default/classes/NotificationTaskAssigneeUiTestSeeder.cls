/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds a Task UI test on a household where the running user is the assignee
 * so Task notification eligibility is guaranteed without FA-team fan-out.
 */
public without sharing class NotificationTaskAssigneeUiTestSeeder {
  public class SeedResult {
    public Id householdId;
    public String householdName;
    public Id assigneeUserId;
    public String assigneeUserName;
    public String assigneeProfileName;
    public Task assigneeTask;
    public Id taskNotificationRuleId;
    public List<Notification_Log__c> notificationLogs = new List<Notification_Log__c>();
  }

  public static SeedResult seedForHousehold(Id householdId) {
    if (householdId == null) {
      throw new IllegalArgumentException('householdId is required.');
    }

    Account household = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    User assigneeUser = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Notification_Rule__c taskRule = ensureTaskRuleForUser(assigneeUser.Id);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    Task assigneeTask = new Task(
      Subject =
        seedMarker +
        ' [UI-Assignee] Task Insert on ' +
        household.Name +
        ' — Running User Assigned To Path',
      WhatId = household.Id,
      OwnerId = assigneeUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Description =
        'UI test: running user (' +
        assigneeUser.Name +
        ') is Assigned To. You should receive an In App / Email notification for this Task insert.'
    );
    insert assigneeTask;

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.assigneeUserId = assigneeUser.Id;
    result.assigneeUserName = assigneeUser.Name;
    result.assigneeProfileName = assigneeUser.Profile.Name;
    result.assigneeTask = assigneeTask;
    result.taskNotificationRuleId = taskRule.Id;
    result.notificationLogs = selectNotificationLogs(
      new Set<String>{ String.valueOf(assigneeTask.Id) },
      assigneeUser.Id
    );
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Task Assignee UI Test Record ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug(
      'Task: ' +
        result.assigneeTask.Id +
        ' | Subject: ' +
        result.assigneeTask.Subject
    );
    System.debug(
      'Assignee (you): ' +
        result.assigneeUserName +
        ' (' +
        result.assigneeUserId +
        ') | Profile: ' +
        result.assigneeProfileName
    );
    System.debug(
      'Task Notification_Rule__c for you: ' + result.taskNotificationRuleId
    );
    System.debug(
      'Notification logs for assignee immediately (async flow may add more): ' +
        result.notificationLogs.size()
    );

    for (Notification_Log__c logRecord : result.notificationLogs) {
      System.debug(
        '  ' +
          logRecord.Name +
          ' | ' +
          logRecord.Recipient__r.Name +
          ' (' +
          logRecord.Recipient__r.Profile.Name +
          ') | ' +
          logRecord.Status__c +
          ' | ' +
          logRecord.Channel__c
      );
    }

    System.debug('=== UI Verification Checklist ===');
    System.debug(
      '1. Confirm Task ' +
        result.assigneeTask.Id +
        ' is assigned to you (' +
        result.assigneeUserName +
        ').'
    );
    System.debug(
      '2. Open Notification Center and confirm a notification for subject containing "[UI-Assignee]".'
    );
    System.debug(
      '3. Recipient should be you via the Assigned To / assignee path on Task insert.'
    );
  }

  private static Notification_Rule__c ensureTaskRuleForUser(Id userId) {
    List<Notification_Rule__c> existingRules = [
      SELECT Id, Channel__c, Frequency__c, Is_Active__c
      FROM Notification_Rule__c
      WHERE
        User__c = :userId
        AND Household__c = NULL
        AND Object_Type__c = :NotificationConstants.OBJECT_TYPE_TASK
      LIMIT 1
    ];

    if (!existingRules.isEmpty()) {
      Notification_Rule__c existingRule = existingRules[0];
      if (!existingRule.Is_Active__c) {
        existingRule.Is_Active__c = true;
        update existingRule;
      }
      return existingRule;
    }

    Notification_Rule__c taskRule = new Notification_Rule__c(
      Object_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Channel__c =
        NotificationConstants.CHANNEL_IN_APP +
        ';' +
        NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Is_Active__c = true,
      Is_System_Default__c = false,
      Priority__c = 10,
      Rule_Name__c = 'UI Task Assignee Test Rule',
      User__c = userId
    );
    insert taskRule;
    return taskRule;
  }

  private static List<Notification_Log__c> selectNotificationLogs(
    Set<String> sourceRecordIds,
    Id assigneeUserId
  ) {
    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Recipient__r.Name,
        Recipient__r.Profile.Name,
        Source_Record_Id__c,
        Status__c,
        Channel__c,
        Frequency__c,
        Notification_Rule__r.Rule_Name__c
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c IN :sourceRecordIds
        AND Recipient__c = :assigneeUserId
      ORDER BY CreatedDate DESC
    ];
  }
}