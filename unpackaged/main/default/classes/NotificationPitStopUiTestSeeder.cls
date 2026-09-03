/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 *
 * Seeds pit stop Task UI test records on a household for notification scenarios:
 *   PS1 — Branch pit stop, branch assignee → immediate In_App + Email (preferences bypassed)
 *   PS2 — HO pit stop, Home Office assignee → immediate In_App + Email (preferences bypassed)
 *   PS3 — HO pit stop, branch assignee on Case → branch user suppressed (no NC logs)
 *   PS4 — Branch pit stop task update → immediate notification on modify
 */
public without sharing class NotificationPitStopUiTestSeeder {
  public class SeedResult {
    public Id householdId;
    public String householdName;
    public String seedMarker;
    public Case ps1BranchCase;
    public Task ps1BranchTask;
    public Case ps2HoCase;
    public Task ps2HoTask;
    public Case ps3SuppressCase;
    public Task ps3SuppressTask;
    public User branchAssignee;
    public User homeOfficeAssignee;
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

    User branchAssignee = resolveBranchAssignee(household.Financial_Advisor_Team__c);
    User homeOfficeAssignee = resolveHomeOfficeAssigneeOptional();
    User systemAdminOwner = resolveSystemAdminOwner(
      branchAssignee.Id,
      homeOfficeAssignee == null ? branchAssignee.Id : homeOfficeAssignee.Id
    );

    String seedMarker = 'PS-' + String.valueOf(System.now().getTime()).right(6);

    Case ps1BranchCase = buildUiTestCase(
      seedMarker +
        ' [PS1 Branch Pit Stop] Case for branch assignee immediate notification',
      household,
      systemAdminOwner.Id,
      'PS1: Branch pit stop task owned by branch user — expect immediate email + in-app.'
    );

    Case ps2HoCase = buildUiTestCase(
      seedMarker +
        ' [PS2 HO Pit Stop] Case for Home Office assignee immediate notification',
      household,
      systemAdminOwner.Id,
      'PS2: HO pit stop task owned by HO user — expect immediate email + in-app.'
    );

    Case ps3SuppressCase = buildUiTestCase(
      seedMarker +
        ' [PS3 HO Pit Stop Suppress] Branch assignee should be suppressed',
      household,
      homeOfficeAssignee != null ? homeOfficeAssignee.Id : systemAdminOwner.Id,
      'PS3: HO pit stop with branch assignee — branch user should NOT receive NC notifications.'
    );

    List<Case> casesToInsert = new List<Case>{ ps1BranchCase, ps3SuppressCase };
    if (homeOfficeAssignee != null) {
      casesToInsert.add(ps2HoCase);
    }
    insert casesToInsert;

    Task ps1BranchTask = buildPitStopTask(
      seedMarker + ' [PS1] Branch Pit Stop Task',
      ps1BranchCase.Id,
      branchAssignee.Id,
      true,
      false
    );

    List<Task> tasksToInsert = new List<Task>{ ps1BranchTask };

    Task ps2HoTask = null;
    if (homeOfficeAssignee != null) {
      ps2HoTask = buildPitStopTask(
        seedMarker + ' [PS2] Home Office Pit Stop Task',
        ps2HoCase.Id,
        homeOfficeAssignee.Id,
        false,
        true
      );
      tasksToInsert.add(ps2HoTask);
    } else {
      System.debug(
        'WARN: No active Home Office user — PS2 skipped. Activate a Home Office user to test HO pit stop exception path.'
      );
    }

    Task ps3SuppressTask = buildPitStopTask(
      seedMarker + ' [PS3] HO Pit Stop — Branch Assignee (suppressed)',
      ps3SuppressCase.Id,
      branchAssignee.Id,
      false,
      true
    );

    tasksToInsert.add(ps3SuppressTask);
    insert tasksToInsert;

    ps1BranchTask.Status = 'In Progress';
    update ps1BranchTask;

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.seedMarker = seedMarker;
    result.ps1BranchCase = ps1BranchCase;
    result.ps1BranchTask = ps1BranchTask;
    result.ps2HoCase = ps2HoCase;
    result.ps2HoTask = ps2HoTask;
    result.ps3SuppressCase = ps3SuppressCase;
    result.ps3SuppressTask = ps3SuppressTask;
    result.branchAssignee = branchAssignee;
    result.homeOfficeAssignee = homeOfficeAssignee;
    Set<String> sourceRecordIds = new Set<String>{
      String.valueOf(ps1BranchTask.Id),
      String.valueOf(ps3SuppressTask.Id)
    };
    if (ps2HoTask != null) {
      sourceRecordIds.add(String.valueOf(ps2HoTask.Id));
    }

    result.notificationLogs = selectNotificationLogs(sourceRecordIds);
    return result;
  }

  public static void enqueuePendingImmediateEmails(SeedResult result) {
    List<Id> immediateEmailLogIds = new List<Id>();

    for (Notification_Log__c logRecord : result.notificationLogs) {
      if (
        logRecord.Channel__c == NotificationConstants.CHANNEL_EMAIL &&
        logRecord.Frequency__c == NotificationConstants.FREQUENCY_IMMEDIATE &&
        logRecord.Status__c != NotificationConstants.STATUS_SENT
      ) {
        immediateEmailLogIds.add(logRecord.Id);
      }
    }

    if (!immediateEmailLogIds.isEmpty()) {
      NotificationDeliveryEnqueueService.enqueueImmediateLogIds(immediateEmailLogIds);
      System.debug(
        'Enqueued immediate email delivery for ' + immediateEmailLogIds.size() + ' log(s).'
      );
    }
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Pit Stop Notification UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug('Seed marker: ' + result.seedMarker);
    System.debug(
      'Branch assignee: ' +
        result.branchAssignee.Name +
        ' (' +
        result.branchAssignee.Profile.Name +
        ')'
    );
    System.debug(
      'HO assignee: ' +
        (result.homeOfficeAssignee == null
          ? '(none — PS2 skipped)'
          : result.homeOfficeAssignee.Name +
            ' (' +
            result.homeOfficeAssignee.Profile.Name +
            ')')
    );
    System.debug('PS1 Task: ' + result.ps1BranchTask.Id);
    if (result.ps2HoTask != null) {
      System.debug('PS2 Task: ' + result.ps2HoTask.Id);
    } else {
      System.debug('PS2 Task: skipped (no Home Office user)');
    }
    System.debug('PS3 Task: ' + result.ps3SuppressTask.Id);
    System.debug('=== PS4: Updated PS1 Branch Pit Stop task status to In Progress ===');

    System.debug(
      'Notification logs found (may be incomplete — async prepare): ' +
        result.notificationLogs.size()
    );

    for (Notification_Log__c logRecord : result.notificationLogs) {
      System.debug(
        '  ' +
          logRecord.Name +
          ' | Task ' +
          logRecord.Source_Record_Id__c +
          ' | ' +
          logRecord.Status__c +
          ' | ' +
          logRecord.Channel__c +
          ' | ' +
          logRecord.Frequency__c +
          ' | ' +
          logRecord.Recipient__r.Name +
          ' (' +
          logRecord.Recipient__r.Profile.Name +
          ')'
      );
    }

    Integer branchPs1Logs = countLogsForRecipientAndTask(
      result.notificationLogs,
      result.branchAssignee.Id,
      result.ps1BranchTask.Id
    );
    Integer hoPs2Logs = result.ps2HoTask == null ||
      result.homeOfficeAssignee == null
      ? 0
      : countLogsForRecipientAndTask(
          result.notificationLogs,
          result.homeOfficeAssignee.Id,
          result.ps2HoTask.Id
        );
    Integer branchPs3Logs = countLogsForRecipientAndTask(
      result.notificationLogs,
      result.branchAssignee.Id,
      result.ps3SuppressTask.Id
    );

    System.debug('=== Expected outcomes (after async prepare completes) ===');
    System.debug(
      'PS1 Branch assignee logs (expect 4: In_App+Email insert+update): ' +
        branchPs1Logs +
        ' so far'
    );
    System.debug(
      'PS2 HO assignee logs (expect 2 when PS2 runs): ' + hoPs2Logs + ' so far'
    );
    System.debug(
      'PS3 Branch assignee on HO pit stop (expect 0 — suppressed): ' +
        branchPs3Logs +
        ' so far'
    );

    System.debug('=== UI Verification Checklist ===');
    System.debug(
      '1. Log in as ' +
        result.branchAssignee.Name +
        ' — confirm immediate NC entries for [PS1 Branch Pit Stop] task (insert + update).'
    );
    if (result.homeOfficeAssignee != null && result.ps2HoTask != null) {
      System.debug(
        '2. Log in as ' +
          result.homeOfficeAssignee.Name +
          ' — confirm immediate NC entries for [PS2 HO Pit Stop] task.'
      );
    } else {
      System.debug(
        '2. PS2 skipped — activate a Home Office user and re-run to test HO pit stop exception.'
      );
    }
    System.debug(
      '3. Log in as ' +
        result.branchAssignee.Name +
        ' — confirm NO NC entries for [PS3 HO Pit Stop Suppress] task.'
    );
    System.debug(
      '4. Verify emails from ' +
        NotificationConstants.ORG_WIDE_NOTIFICATION_EMAIL +
        ' are Immediate (not Digest).'
    );
    System.debug(
      'PS1 Task URL: /lightning/r/Task/' + result.ps1BranchTask.Id + '/view'
    );
    if (result.ps2HoTask != null) {
      System.debug('PS2 Task URL: /lightning/r/Task/' + result.ps2HoTask.Id + '/view');
    }
    System.debug(
      'PS3 Task URL: /lightning/r/Task/' + result.ps3SuppressTask.Id + '/view'
    );
    System.debug(
      'PS1 Case URL: /lightning/r/Case/' + result.ps1BranchCase.Id + '/view'
    );
    if (result.ps2HoCase != null && result.ps2HoTask != null) {
      System.debug('PS2 Case URL: /lightning/r/Case/' + result.ps2HoCase.Id + '/view');
    }
    System.debug(
      'PS3 Case URL: /lightning/r/Case/' + result.ps3SuppressCase.Id + '/view'
    );
  }

  private static Integer countLogsForRecipientAndTask(
    List<Notification_Log__c> notificationLogs,
    Id recipientId,
    Id taskId
  ) {
    Integer count = 0;
    String taskSourceId = String.valueOf(taskId);

    for (Notification_Log__c logRecord : notificationLogs) {
      if (
        logRecord.Source_Record_Id__c == taskSourceId &&
        logRecord.Recipient__c == recipientId
      ) {
        count++;
      }
    }

    return count;
  }

  private static Case buildUiTestCase(
    String subject,
    Account household,
    Id ownerId,
    String description
  ) {
    Case caseRecord = new Case(
      Subject = subject,
      AccountId = household.Id,
      OwnerId = ownerId,
      Status = 'New',
      Origin = 'Phone',
      Description = description
    );

    if (household.Financial_Advisor_Team__c != null) {
      caseRecord.Financial_Advisor_Team__c = household.Financial_Advisor_Team__c;
    }

    return caseRecord;
  }

  private static Task buildPitStopTask(
    String subject,
    Id caseId,
    Id ownerId,
    Boolean isBranchPitStop,
    Boolean isHoPitStop
  ) {
    return new Task(
      Subject = subject,
      WhatId = caseId,
      OwnerId = ownerId,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = isBranchPitStop,
      Home_Office_Pit_Stop__c = isHoPitStop
    );
  }

  private static User resolveBranchAssignee(Id teamId) {
    User nexsAdvisor = selectPrimaryAdvisorForTeam(
      teamId,
      UserInfoUtils.PROFILE_NEXS
    );
    if (nexsAdvisor != null) {
      return nexsAdvisor;
    }

    User advisor = selectActiveUserByProfile(UserInfoUtils.PROFILE_ADVISOR);
    if (advisor != null) {
      return advisor;
    }

    throw new IllegalArgumentException(
      'No active NexS or Advisor user found for branch pit stop UI test.'
    );
  }

  private static User resolveHomeOfficeAssigneeOptional() {
    User homeOfficeUser = selectActiveUserByProfile(
      UserInfoUtils.PROFILE_HOME_OFFICE
    );
    if (homeOfficeUser != null) {
      return homeOfficeUser;
    }

    System.debug(
      'WARN: No active Home Office user found. PS2 will be skipped.'
    );
    return null;
  }

  private static User resolveSystemAdminOwner(Id branchAssigneeId, Id hoAssigneeId) {
    User systemAdmin = selectActiveUserByProfile(
      UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
    );

    if (
      systemAdmin != null &&
      systemAdmin.Id != branchAssigneeId &&
      systemAdmin.Id != hoAssigneeId
    ) {
      return systemAdmin;
    }

    List<User> admins = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE
        Profile.Name = :UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
        AND IsActive = TRUE
        AND Id NOT IN (:branchAssigneeId, :hoAssigneeId)
      ORDER BY Name
      LIMIT 1
    ];

    if (!admins.isEmpty()) {
      return admins[0];
    }

    return [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
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

    return members.isEmpty() ? null : members[0].User__r;
  }

  private static List<Notification_Log__c> selectNotificationLogs(
    Set<String> sourceRecordIds
  ) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Channel__c,
        Frequency__c,
        Recipient__c,
        Recipient__r.Name,
        Recipient__r.Profile.Name,
        Source_Record_Id__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c IN :sourceRecordIds
      ORDER BY CreatedDate
    ];
  }
}