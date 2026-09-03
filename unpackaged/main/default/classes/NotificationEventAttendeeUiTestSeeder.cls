/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds an Event UI test on a household where the running user is an attendee
 * (not the creator) so attendee-based notification eligibility can be verified.
 */
public without sharing class NotificationEventAttendeeUiTestSeeder {
  public class SeedResult {
    public Id householdId;
    public String householdName;
    public Id attendeeUserId;
    public String attendeeUserName;
    public String attendeeProfileName;
    public Id eventCreatorId;
    public String eventCreatorName;
    public Event attendeeEvent;
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

    User attendeeUser = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    User eventCreator = resolveEventCreator(attendeeUser);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);
    Datetime startDateTime = Datetime.now().addDays(5);

    Event attendeeEvent = new Event(
      Subject =
        seedMarker +
        ' [UI-Attendee] Event on ' +
        household.Name +
        ' — Running User Attendee Path',
      WhatId = household.Id,
      OwnerId = eventCreator.Id,
      StartDateTime = startDateTime,
      EndDateTime = startDateTime.addHours(1),
      DurationInMinutes = 60,
      Location = '742 Evergreen Terrace',
      Description =
        'UI test: running user (' +
        attendeeUser.Name +
        ') is an Event attendee. Assigned To / owner is ' +
        eventCreator.Name +
        '. Attendee-change notification should reach you after publishAttendeeChange.'
    );
    insert attendeeEvent;

    EventRelation attendeeRelation = new EventRelation(
      EventId = attendeeEvent.Id,
      RelationId = attendeeUser.Id,
      IsInvitee = true
    );
    insert attendeeRelation;

    NotificationEventAttendeePublisher.publishAttendeeChange(
      attendeeEvent.Id,
      attendeeRelation.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;
    result.attendeeUserId = attendeeUser.Id;
    result.attendeeUserName = attendeeUser.Name;
    result.attendeeProfileName = attendeeUser.Profile.Name;
    result.eventCreatorId = eventCreator.Id;
    result.eventCreatorName = eventCreator.Name;
    result.attendeeEvent = attendeeEvent;
    result.notificationLogs = selectNotificationLogs(
      new Set<String>{ String.valueOf(attendeeEvent.Id) },
      attendeeUser.Id
    );
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Event Attendee UI Test Record ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');
    System.debug(
      'Event: ' +
        result.attendeeEvent.Id +
        ' | Subject: ' +
        result.attendeeEvent.Subject
    );
    System.debug(
      'Attendee (you): ' +
        result.attendeeUserName +
        ' (' +
        result.attendeeUserId +
        ') | Profile: ' +
        result.attendeeProfileName
    );
    System.debug(
      'Event owner (Assigned To, not you): ' +
        result.eventCreatorName +
        ' (' +
        result.eventCreatorId +
        ')'
    );
    System.debug(
      'Notification logs for attendee immediately (async flow may add more): ' +
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
      '1. Confirm you are listed as an attendee on Event ' + result.attendeeEvent.Id + '.'
    );
    System.debug(
      '2. Open Notification Center / email and confirm a notification for subject containing "[UI-Attendee]".'
    );
    System.debug(
      '3. Recipient should be you (' +
        result.attendeeUserName +
        ') via the attendee change (Attendees field in change context).'
    );
  }

  private static User resolveEventCreator(User attendeeUser) {
    User homeOfficeCreator = selectActiveUserByProfile(
      UserInfoUtils.PROFILE_HOME_OFFICE
    );
    if (homeOfficeCreator != null && homeOfficeCreator.Id != attendeeUser.Id) {
      return homeOfficeCreator;
    }

    User systemAdminCreator = selectActiveUserByProfile(
      UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (systemAdminCreator != null && systemAdminCreator.Id != attendeeUser.Id) {
      return systemAdminCreator;
    }

    User nexsCreator = selectActiveUserByProfile(UserInfoUtils.PROFILE_NEXS);
    if (nexsCreator != null && nexsCreator.Id != attendeeUser.Id) {
      return nexsCreator;
    }

    List<User> alternateCreators = [
      SELECT Id, Name, Profile.Name
      FROM User
      WHERE Id != :attendeeUser.Id AND IsActive = TRUE
      ORDER BY Name
      LIMIT 1
    ];

    if (alternateCreators.isEmpty()) {
      throw new IllegalArgumentException(
        'Could not find another active user to own the Event. Attendee-only test requires a different creator.'
      );
    }

    return alternateCreators[0];
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
    Set<String> sourceRecordIds,
    Id attendeeUserId
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
        AND Recipient__c = :attendeeUserId
      ORDER BY CreatedDate DESC
    ];
  }
}