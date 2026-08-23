/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds Event UI test records on the Simpson household for notification
 * ownership scenarios AC1 (NexS) and AC2 (Home Office).
 */
public without sharing class NotificationEventUiTestSeeder {
  public class SeedResult {
    public Id householdId;
    public String householdName;
    public Event ac1NexsEvent;
    public Event ac2HomeOfficeEvent;
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

    User homeOfficeCreator = resolveHomeOfficeUser();
    User ac1Creator = resolveAc1Creator(homeOfficeCreator);
    User nexsPrimaryAdvisor = selectPrimaryAdvisorForTeam(
      household.Financial_Advisor_Team__c,
      NotificationConstants.PROFILE_NEXS
    );

    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);
    Datetime startDateTime = Datetime.now().addDays(3);
    Datetime endDateTime = startDateTime.addHours(1);

    Event ac1NexsEvent = buildUiTestEvent(
      seedMarker +
        ' [UI-AC1 NexS] Event Insert on Simpson Household — Primary Advisor FA Team Path',
      household.Id,
      ac1Creator.Id,
      startDateTime,
      endDateTime,
      'AC1 UI test: NexS user should receive notification when Event relates to household/contact on FA team where user is Primary Advisor, or when creator/attendee.'
    );

    Event ac2HomeOfficeEvent = buildUiTestEvent(
      seedMarker +
        ' [UI-AC2 Home Office] Event Insert on Simpson Household — Event Creator Path',
      household.Id,
      homeOfficeCreator.Id,
      startDateTime.addHours(2),
      endDateTime.addHours(2),
      'AC2 UI test: Home Office user should receive notification when they created the Event or are an attendee.'
    );

    insert new List<Event>{ ac1NexsEvent, ac2HomeOfficeEvent };

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.ac1NexsEvent = ac1NexsEvent;
    result.ac2HomeOfficeEvent = ac2HomeOfficeEvent;
    result.expectedNexsRecipientId = nexsPrimaryAdvisor == null
      ? null
      : nexsPrimaryAdvisor.Id;
    result.expectedHomeOfficeRecipientId = homeOfficeCreator.Id;
    result.notificationLogs = selectNotificationLogs(
      new Set<String>{
        String.valueOf(ac1NexsEvent.Id),
        String.valueOf(ac2HomeOfficeEvent.Id)
      }
    );
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Event Notification UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug(
      'AC1 NexS event: ' +
        result.ac1NexsEvent.Id +
        ' | Subject: ' +
        result.ac1NexsEvent.Subject
    );
    System.debug(
      'AC2 Home Office event: ' +
        result.ac2HomeOfficeEvent.Id +
        ' | Subject: ' +
        result.ac2HomeOfficeEvent.Subject
    );
    System.debug(
      'Expected AC1 NexS recipient (primary advisor): ' + result.expectedNexsRecipientId
    );
    System.debug(
      'Expected AC2 Home Office recipient (creator): ' +
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
          ' | Event ' +
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
      '2. Log in as Home Office event creator and confirm notification for subject containing "[UI-AC2 Home Office]".'
    );
    System.debug(
      '3. Update Start/End, Assigned To, Location, Description, attendees, or cancel the event and confirm notification follows active Event rule settings.'
    );
  }

  private static Event buildUiTestEvent(
    String subject,
    Id householdId,
    Id ownerId,
    Datetime startDateTime,
    Datetime endDateTime,
    String description
  ) {
    return new Event(
      Subject = subject,
      WhatId = householdId,
      OwnerId = ownerId,
      StartDateTime = startDateTime,
      EndDateTime = endDateTime,
      DurationInMinutes = 60,
      Location = '742 Evergreen Terrace',
      Description = description
    );
  }

  private static User resolveHomeOfficeUser() {
    User homeOfficeUser = selectActiveUserByProfile(
      NotificationConstants.PROFILE_HOME_OFFICE
    );
    if (homeOfficeUser != null) {
      return homeOfficeUser;
    }

    homeOfficeUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    System.debug(
      'WARN: No active Home Office user found. AC2 event creator falls back to running user (' +
        homeOfficeUser.Profile.Name +
        ').'
    );
    return homeOfficeUser;
  }

  private static User resolveAc1Creator(User homeOfficeCreator) {
    User systemAdminCreator = selectActiveUserByProfile(
      NotificationConstants.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (systemAdminCreator != null && systemAdminCreator.Id != homeOfficeCreator.Id) {
      return systemAdminCreator;
    }

    User runningUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (runningUser.Id != homeOfficeCreator.Id) {
      return runningUser;
    }

    return homeOfficeCreator;
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