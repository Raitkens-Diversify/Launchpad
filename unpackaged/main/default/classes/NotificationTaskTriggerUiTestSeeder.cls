/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds Task UI test records on a household for each notification trigger
 * criterion: insert, assigned to, and status update.
 */
public without sharing class NotificationTaskTriggerUiTestSeeder {
  public static final Id DEFAULT_HOUSEHOLD_ID = SimpsonMapDemoDataSeeder.HOUSEHOLD_ID;

  public class TriggerScenarioResult {
    public String scenarioKey;
    public String scenarioLabel;
    public Id taskId;
    public String subject;
    public String verificationHint;
  }

  public class SeedResult {
    public Id householdId;
    public String householdName;
    public List<TriggerScenarioResult> scenarios = new List<TriggerScenarioResult>();
    public List<Notification_Log__c> notificationLogs = new List<Notification_Log__c>();
  }

  public static SeedResult seedForHousehold(Id householdId) {
    if (householdId == null) {
      throw new IllegalArgumentException('householdId is required.');
    }

    Account household = [
      SELECT Id, Name, Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    User taskOwner = resolveTaskOwner();
    User alternateOwner = resolveAlternateOwner(taskOwner);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;

    result.scenarios.add(seedInsertScenario(household, taskOwner, seedMarker));
    result.scenarios.add(
      seedAssignedToChangeScenario(household, taskOwner, alternateOwner, seedMarker)
    );
    result.scenarios.add(seedStatusChangeScenario(household, taskOwner, seedMarker));

    Set<String> sourceRecordIds = new Set<String>();
    for (TriggerScenarioResult scenario : result.scenarios) {
      sourceRecordIds.add(String.valueOf(scenario.taskId));
    }
    result.notificationLogs = selectNotificationLogs(sourceRecordIds);
    return result;
  }

  public static SeedResult seedUpdatesForHousehold(Id householdId) {
    if (householdId == null) {
      throw new IllegalArgumentException('householdId is required.');
    }

    Account household = [
      SELECT Id, Name, Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    User taskOwner = resolveTaskOwner();
    User alternateOwner = resolveAlternateOwner(taskOwner);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;

    result.scenarios.add(
      seedAssignedToChangeScenario(household, taskOwner, alternateOwner, seedMarker)
    );
    result.scenarios.add(seedStatusChangeScenario(household, taskOwner, seedMarker));

    Set<String> sourceRecordIds = new Set<String>();
    for (TriggerScenarioResult scenario : result.scenarios) {
      sourceRecordIds.add(String.valueOf(scenario.taskId));
    }
    result.notificationLogs = selectNotificationLogs(sourceRecordIds);
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Task Trigger UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');

    for (TriggerScenarioResult scenario : result.scenarios) {
      System.debug(
        scenario.scenarioKey +
          ' | Task ' +
          scenario.taskId +
          ' | ' +
          scenario.subject
      );
      System.debug('  Hint: ' + scenario.verificationHint);
    }

    System.debug(
      'Notification logs found immediately (async flow may add more): ' +
        result.notificationLogs.size()
    );

    for (Notification_Log__c logRecord : result.notificationLogs) {
      System.debug(
        '  ' +
          logRecord.Name +
          ' | Task ' +
          logRecord.Source_Record_Id__c +
          ' | ' +
          logRecord.Recipient__r.Name +
          ' | ' +
          logRecord.Status__c +
          ' | ' +
          logRecord.Channel__c
      );
    }
  }

  private static TriggerScenarioResult seedInsertScenario(
    Account household,
    User taskOwner,
    String seedMarker
  ) {
    Task taskRecord = buildBaseTask(
      seedMarker + ' [UI-TRIGGER-Insert] Record Created on Simpson Household',
      household.Id,
      taskOwner.Id,
      'UI test for Task insert trigger.'
    );
    insert taskRecord;

    return buildScenarioResult(
      'INSERT',
      'Record Created',
      taskRecord,
      'Confirm notification after insert. Change context should show Task created.'
    );
  }

  private static TriggerScenarioResult seedAssignedToChangeScenario(
    Account household,
    User taskOwner,
    User alternateOwner,
    String seedMarker
  ) {
    Task taskRecord = buildBaseTask(
      seedMarker + ' [UI-TRIGGER-AssignedTo] Assigned To Change on Simpson Household',
      household.Id,
      taskOwner.Id,
      'UI test for Assigned To (Owner) change.'
    );
    insert taskRecord;

    taskRecord.OwnerId = alternateOwner.Id;
    update taskRecord;

    return buildScenarioResult(
      'ASSIGNED_TO',
      'Assigned To Change',
      taskRecord,
      'Confirm notification after Assigned To update.'
    );
  }

  private static TriggerScenarioResult seedStatusChangeScenario(
    Account household,
    User taskOwner,
    String seedMarker
  ) {
    Task taskRecord = buildBaseTask(
      seedMarker + ' [UI-TRIGGER-Status] Status Update on Simpson Household',
      household.Id,
      taskOwner.Id,
      'UI test for Status update.'
    );
    insert taskRecord;

    taskRecord.Status = 'In Progress';
    update taskRecord;

    return buildScenarioResult(
      'STATUS',
      'Status Update',
      taskRecord,
      'Confirm notification after Status update.'
    );
  }

  private static TriggerScenarioResult buildScenarioResult(
    String scenarioKey,
    String scenarioLabel,
    Task taskRecord,
    String verificationHint
  ) {
    TriggerScenarioResult scenario = new TriggerScenarioResult();
    scenario.scenarioKey = scenarioKey;
    scenario.scenarioLabel = scenarioLabel;
    scenario.taskId = taskRecord.Id;
    scenario.subject = taskRecord.Subject;
    scenario.verificationHint = verificationHint;
    return scenario;
  }

  private static Task buildBaseTask(
    String subject,
    Id householdId,
    Id ownerId,
    String description
  ) {
    return new Task(
      Subject = subject,
      WhatId = householdId,
      OwnerId = ownerId,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today().addDays(5),
      Description = description
    );
  }

  private static User resolveTaskOwner() {
    User systemAdminUser = selectActiveUserByProfile(
      NotificationConstants.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (systemAdminUser != null) {
      return systemAdminUser;
    }

    return [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
  }

  private static User resolveAlternateOwner(User taskOwner) {
    User homeOfficeUser = selectActiveUserByProfile(
      NotificationConstants.PROFILE_HOME_OFFICE
    );
    if (homeOfficeUser != null && homeOfficeUser.Id != taskOwner.Id) {
      return homeOfficeUser;
    }

    List<User> alternateUsers = [
      SELECT Id
      FROM User
      WHERE Id != :taskOwner.Id AND IsActive = TRUE
      LIMIT 1
    ];
    return alternateUsers.isEmpty() ? taskOwner : alternateUsers[0];
  }

  private static User selectActiveUserByProfile(String profileName) {
    List<User> users = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Profile.Name = :profileName AND IsActive = TRUE
      ORDER BY Name
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static List<Notification_Log__c> selectNotificationLogs(
    Set<String> sourceRecordIds
  ) {
    if (sourceRecordIds.isEmpty()) {
      return new List<Notification_Log__c>();
    }

    return [
      SELECT
        Id,
        Name,
        Recipient__c,
        Recipient__r.Name,
        Source_Record_Id__c,
        Status__c,
        Channel__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c IN :sourceRecordIds
      ORDER BY Source_Record_Id__c, CreatedDate
    ];
  }
}