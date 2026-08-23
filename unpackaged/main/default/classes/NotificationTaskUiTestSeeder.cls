/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds Task UI test records on the Simpson household for notification
 * ownership scenarios AC1 (NexS) and AC2 (Home Office).
 */
public without sharing class NotificationTaskUiTestSeeder {
  public static final Id DEFAULT_HOUSEHOLD_ID = SimpsonMapDemoDataSeeder.HOUSEHOLD_ID;

  public class SeedResult {
    public Id householdId;
    public String householdName;
    public Task ac1NexsTask;
    public Task ac2HomeOfficeTask;
    public Case ac2HomeOfficeCase;
    public Id expectedNexsRecipientId;
    public Id expectedHomeOfficeRecipientId;
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

    User homeOfficeOwner = resolveHomeOfficeOwner();
    User ac1TaskOwner = resolveAc1TaskOwner(homeOfficeOwner);
    User nexsPrimaryAdvisor = selectPrimaryAdvisorForTeam(
      household.Financial_Advisor_Team__c,
      NotificationConstants.PROFILE_NEXS
    );

    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    Task ac1NexsTask = buildUiTestTask(
      seedMarker +
        ' [UI-AC1 NexS] Task Insert on Simpson Household — Primary Advisor FA Team Path',
      household.Id,
      null,
      ac1TaskOwner.Id,
      'AC1 UI test: NexS user should receive notification when Task is on household ' +
        household.Name +
        ', serviced by FA team where user is Primary Advisor. Triggers: Insert, Assigned To change, Status update.'
    );

    Case ac2HomeOfficeCase = buildUiTestCase(
      seedMarker + ' [UI-AC2 Home Office] Supporting Case for Task — Case Owner Path',
      household,
      homeOfficeOwner.Id
    );
    insert ac2HomeOfficeCase;

    Task ac2HomeOfficeTask = buildUiTestTask(
      seedMarker +
        ' [UI-AC2 Home Office] Task Insert on Simpson Case — Case Owner Path',
      null,
      ac2HomeOfficeCase.Id,
      ac1TaskOwner.Id,
      'AC2 UI test: Home Office user should receive notification when they own the related Case or the Task is assigned to them. Triggers: Insert, Assigned To change, Status update.'
    );

    insert new List<Task>{ ac1NexsTask, ac2HomeOfficeTask };

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.ac1NexsTask = ac1NexsTask;
    result.ac2HomeOfficeTask = ac2HomeOfficeTask;
    result.ac2HomeOfficeCase = ac2HomeOfficeCase;
    result.expectedNexsRecipientId = nexsPrimaryAdvisor == null
      ? null
      : nexsPrimaryAdvisor.Id;
    result.expectedHomeOfficeRecipientId = homeOfficeOwner.Id;
    result.notificationLogs = selectNotificationLogs(
      new Set<String>{
        String.valueOf(ac1NexsTask.Id),
        String.valueOf(ac2HomeOfficeTask.Id)
      }
    );
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Task Notification UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug(
      'AC1 NexS task: ' +
        result.ac1NexsTask.Id +
        ' | Subject: ' +
        result.ac1NexsTask.Subject
    );
    System.debug(
      'AC2 Home Office task: ' +
        result.ac2HomeOfficeTask.Id +
        ' | Subject: ' +
        result.ac2HomeOfficeTask.Subject +
        ' | Case: ' +
        result.ac2HomeOfficeCase.Id
    );
    System.debug(
      'Expected AC1 NexS recipient (primary advisor): ' + result.expectedNexsRecipientId
    );
    System.debug(
      'Expected AC2 Home Office recipient (case owner): ' +
        result.expectedHomeOfficeRecipientId
    );
    System.debug(
      'Notification logs created (async flow may add more): ' +
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
      '1. Log in as NexS primary advisor and confirm notification for subject containing "[UI-AC1 NexS]".'
    );
    System.debug(
      '2. Log in as Home Office case owner and confirm notification for subject containing "[UI-AC2 Home Office]".'
    );
    System.debug(
      '3. Update Assigned To or Status on each task and confirm notification follows active Task rule settings.'
    );
  }

  private static Task buildUiTestTask(
    String subject,
    Id householdId,
    Id caseId,
    Id ownerId,
    String description
  ) {
    Task taskRecord = new Task(
      Subject = subject,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = ownerId,
      ActivityDate = Date.today().addDays(7),
      Description = description
    );

    if (caseId != null) {
      taskRecord.WhatId = caseId;
    } else if (householdId != null) {
      taskRecord.WhatId = householdId;
    }

    return taskRecord;
  }

  private static Case buildUiTestCase(
    String subject,
    Account household,
    Id ownerId
  ) {
    Case caseRecord = new Case(
      Subject = subject,
      AccountId = household.Id,
      OwnerId = ownerId,
      Status = 'New',
      Origin = 'Phone',
      Description = 'Supporting case for AC2 Home Office Task UI test.'
    );

    if (household.Financial_Advisor_Team__c != null) {
      caseRecord.Financial_Advisor_Team__c = household.Financial_Advisor_Team__c;
    }

    return caseRecord;
  }

  private static User resolveHomeOfficeOwner() {
    User homeOfficeOwner = selectActiveUserByProfile(
      NotificationConstants.PROFILE_HOME_OFFICE
    );
    if (homeOfficeOwner != null) {
      return homeOfficeOwner;
    }

    homeOfficeOwner = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    System.debug(
      'WARN: No active Home Office user found. AC2 case owner falls back to running user (' +
        homeOfficeOwner.Profile.Name +
        ').'
    );
    return homeOfficeOwner;
  }

  private static User resolveAc1TaskOwner(User homeOfficeOwner) {
    User systemAdminOwner = selectActiveUserByProfile(
      NotificationConstants.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (systemAdminOwner != null && systemAdminOwner.Id != homeOfficeOwner.Id) {
      return systemAdminOwner;
    }

    User runningUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (runningUser.Id != homeOfficeOwner.Id) {
      return runningUser;
    }

    return homeOfficeOwner;
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

  private static User selectPrimaryAdvisorForTeam(Id teamId, String profileName) {
    if (teamId == null) {
      return null;
    }

    List<Financial_Advisor_Team_Member__c> members = [
      SELECT User__c, User__r.Id, User__r.Name, User__r.Profile.Name
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Primary__c = TRUE
        AND Active__c = TRUE
        AND User__c != NULL
        AND User__r.Profile.Name = :profileName
        AND User__r.IsActive = TRUE
      ORDER BY User__r.Name
      LIMIT 1
    ];

    if (members.isEmpty()) {
      System.debug(
        'WARN: No NexS primary advisor on household FA team. AC1 verification may require FA team membership setup.'
      );
      return null;
    }

    return members[0].User__r;
  }

  private static List<Notification_Log__c> selectNotificationLogs(
    Set<String> sourceRecordIds
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
      WHERE Source_Record_Id__c IN :sourceRecordIds
      ORDER BY Source_Record_Id__c, Recipient__r.Name
    ];
  }
}