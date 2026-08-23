/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds Event UI test records on a household for each notification trigger
 * criterion: insert, start/end, assigned to, attendees, location, description,
 * and cancelled.
 */
public without sharing class NotificationEventTriggerUiTestSeeder {
  public static final Id DEFAULT_HOUSEHOLD_ID = SimpsonMapDemoDataSeeder.HOUSEHOLD_ID;

  public class TriggerScenarioResult {
    public String scenarioKey;
    public String scenarioLabel;
    public Id eventId;
    public String subject;
    public String verificationHint;
  }

  public class SeedResult {
    public Id householdId;
    public String householdName;
    public List<TriggerScenarioResult> scenarios = new List<TriggerScenarioResult>();
    public List<Notification_Log__c> notificationLogs = new List<Notification_Log__c>();
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

    User eventOwner = resolveEventOwner();
    User alternateOwner = resolveAlternateOwner(eventOwner);
    Datetime baseStart = Datetime.now().addDays(4);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;

    result.scenarios.add(
      seedStartEndChangeScenario(household, eventOwner, seedMarker, baseStart)
    );
    result.scenarios.add(
      seedAssignedToChangeScenario(
        household,
        eventOwner,
        alternateOwner,
        seedMarker,
        baseStart.addHours(2)
      )
    );
    result.scenarios.add(
      seedAttendeesChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(4))
    );
    result.scenarios.add(
      seedLocationChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(6))
    );
    result.scenarios.add(
      seedDescriptionChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(8))
    );
    TriggerScenarioResult cancelledScenario = seedCancelledEventScenario(
      household,
      eventOwner,
      seedMarker,
      baseStart.addHours(10)
    );
    if (cancelledScenario != null) {
      result.scenarios.add(cancelledScenario);
    }

    Set<String> sourceRecordIds = new Set<String>();
    for (TriggerScenarioResult scenario : result.scenarios) {
      sourceRecordIds.add(String.valueOf(scenario.eventId));
    }
    result.notificationLogs = selectNotificationLogs(sourceRecordIds);
    return result;
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

    User eventOwner = resolveEventOwner();
    User alternateOwner = resolveAlternateOwner(eventOwner);
    Datetime baseStart = Datetime.now().addDays(4);
    String seedMarker = 'UI-' + String.valueOf(System.now().getTime()).right(6);

    SeedResult result = new SeedResult();
    result.householdId = household.Id;
    result.householdName = household.Name;

    result.scenarios.add(seedInsertScenario(household, eventOwner, seedMarker, baseStart));
    result.scenarios.add(
      seedStartEndChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(2))
    );
    result.scenarios.add(
      seedAssignedToChangeScenario(
        household,
        eventOwner,
        alternateOwner,
        seedMarker,
        baseStart.addHours(4)
      )
    );
    result.scenarios.add(
      seedAttendeesChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(6))
    );
    result.scenarios.add(
      seedLocationChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(8))
    );
    result.scenarios.add(
      seedDescriptionChangeScenario(household, eventOwner, seedMarker, baseStart.addHours(10))
    );
    TriggerScenarioResult cancelledScenario = seedCancelledEventScenario(
      household,
      eventOwner,
      seedMarker,
      baseStart.addHours(12)
    );
    if (cancelledScenario != null) {
      result.scenarios.add(cancelledScenario);
    }

    Set<String> sourceRecordIds = new Set<String>();
    for (TriggerScenarioResult scenario : result.scenarios) {
      sourceRecordIds.add(String.valueOf(scenario.eventId));
    }
    result.notificationLogs = selectNotificationLogs(sourceRecordIds);
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Event Trigger UI Test Records ===');
    System.debug('Household: ' + result.householdName + ' (' + result.householdId + ')');

    for (TriggerScenarioResult scenario : result.scenarios) {
      System.debug(
        scenario.scenarioKey +
          ' | Event ' +
          scenario.eventId +
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
          ' | Event ' +
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
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-Insert] Record Created on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for Event insert trigger.'
    );
    insert eventRecord;

    return buildScenarioResult(
      'INSERT',
      'Record Created',
      eventRecord,
      'Confirm notification after insert. Change context should show Event created.'
    );
  }

  private static TriggerScenarioResult seedStartEndChangeScenario(
    Account household,
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-StartEnd] Start/End Date-Time Change on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for Start Date/Time and End Date/Time changes.'
    );
    insert eventRecord;

    eventRecord.StartDateTime = eventRecord.StartDateTime.addHours(2);
    eventRecord.EndDateTime = eventRecord.EndDateTime.addHours(2);
    update eventRecord;

    return buildScenarioResult(
      'START_END',
      'Start/End Date-Time Change',
      eventRecord,
      'Confirm notification after Start/End update. Email should show Start Date/Time and End Date/Time changes.'
    );
  }

  private static TriggerScenarioResult seedAssignedToChangeScenario(
    Account household,
    User eventOwner,
    User alternateOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-AssignedTo] Assigned To Change on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for Assigned To (Owner) change.'
    );
    insert eventRecord;

    eventRecord.OwnerId = alternateOwner.Id;
    update eventRecord;

    return buildScenarioResult(
      'ASSIGNED_TO',
      'Assigned To Change',
      eventRecord,
      'Confirm notification after Assigned To update. Email should show Assigned to change.'
    );
  }

  private static TriggerScenarioResult seedAttendeesChangeScenario(
    Account household,
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-Attendees] Attendees Change on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for attendee changes via NotificationEventAttendeePublisher.'
    );
    insert eventRecord;

    Contact attendeeContact = new Contact(LastName = 'Event Trigger Attendee');
    insert attendeeContact;

    EventRelation attendeeRelation = new EventRelation(
      EventId = eventRecord.Id,
      RelationId = attendeeContact.Id,
      IsInvitee = true
    );
    insert attendeeRelation;

    NotificationEventAttendeePublisher.publishAttendeeChange(
      eventRecord.Id,
      attendeeRelation.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    return buildScenarioResult(
      'ATTENDEES',
      'Attendees Change',
      eventRecord,
      'Confirm notification after attendee add. Change context should include Attendees.'
    );
  }

  private static TriggerScenarioResult seedLocationChangeScenario(
    Account household,
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-Location] Location Change on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for Location change.',
      '742 Evergreen Terrace'
    );
    insert eventRecord;

    eventRecord.Location = 'Springfield Nuclear Power Plant';
    update eventRecord;

    return buildScenarioResult(
      'LOCATION',
      'Location Change',
      eventRecord,
      'Confirm notification after Location update.'
    );
  }

  private static TriggerScenarioResult seedDescriptionChangeScenario(
    Account household,
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-Description] Description Change on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for Description change.'
    );
    insert eventRecord;

    eventRecord.Description = 'Updated description body for notification UI test.';
    update eventRecord;

    return buildScenarioResult(
      'DESCRIPTION',
      'Description Change',
      eventRecord,
      'Confirm notification after Description update.'
    );
  }

  private static TriggerScenarioResult seedCancelledEventScenario(
    Account household,
    User eventOwner,
    String seedMarker,
    Datetime startDateTime
  ) {
    if (!hasEventField('IsArchived')) {
      System.debug(
        'WARN: Event.IsArchived is unavailable. Skipping cancelled-event UI scenario.'
      );
      return null;
    }

    Event eventRecord = buildBaseEvent(
      seedMarker + ' [UI-TRIGGER-Cancelled] Cancelled Event on Simpson Household',
      household.Id,
      eventOwner.Id,
      startDateTime,
      'UI test for cancelled/archived Event.'
    );
    insert eventRecord;

    String verificationHint =
      'Open this Event in Calendar or Activity timeline and click Cancel Event. ' +
      'IsArchived is not editable via Apex in this org, so cancellation must be done in the UI.';

    if (isEventFieldUpdateable('IsArchived')) {
      eventRecord.put('IsArchived', true);
      update eventRecord;
      verificationHint =
        'Confirm notification after Event is archived/cancelled.';
    }

    return buildScenarioResult(
      'CANCELLED',
      'Cancelled Event',
      eventRecord,
      verificationHint
    );
  }

  private static TriggerScenarioResult buildScenarioResult(
    String scenarioKey,
    String scenarioLabel,
    Event eventRecord,
    String verificationHint
  ) {
    TriggerScenarioResult scenario = new TriggerScenarioResult();
    scenario.scenarioKey = scenarioKey;
    scenario.scenarioLabel = scenarioLabel;
    scenario.eventId = eventRecord.Id;
    scenario.subject = eventRecord.Subject;
    scenario.verificationHint = verificationHint;
    return scenario;
  }

  private static Event buildBaseEvent(
    String subject,
    Id householdId,
    Id ownerId,
    Datetime startDateTime,
    String description
  ) {
    return buildBaseEvent(subject, householdId, ownerId, startDateTime, description, null);
  }

  private static Event buildBaseEvent(
    String subject,
    Id householdId,
    Id ownerId,
    Datetime startDateTime,
    String description,
    String location
  ) {
    Datetime endDateTime = startDateTime.addHours(1);

    return new Event(
      Subject = subject,
      WhatId = householdId,
      OwnerId = ownerId,
      StartDateTime = startDateTime,
      EndDateTime = endDateTime,
      DurationInMinutes = 60,
      Location = location,
      Description = description
    );
  }

  private static User resolveEventOwner() {
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

  private static User resolveAlternateOwner(User eventOwner) {
    User homeOfficeUser = selectActiveUserByProfile(
      NotificationConstants.PROFILE_HOME_OFFICE
    );
    if (homeOfficeUser != null && homeOfficeUser.Id != eventOwner.Id) {
      return homeOfficeUser;
    }

    List<User> alternateUsers = [
      SELECT Id
      FROM User
      WHERE Id != :eventOwner.Id AND IsActive = TRUE
      LIMIT 1
    ];
    return alternateUsers.isEmpty() ? eventOwner : alternateUsers[0];
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

  @TestVisible
  private static Boolean hasEventField(String fieldApiName) {
    return Schema.SObjectType.Event.fields.getMap().containsKey(fieldApiName.toLowerCase());
  }

  @TestVisible
  private static Boolean isEventFieldUpdateable(String fieldApiName) {
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
    Schema.SObjectField fieldToken = fieldMap.get(fieldApiName.toLowerCase());
    return fieldToken != null && fieldToken.getDescribe().isUpdateable();
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
        Channel__c,
        Change_Context__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c IN :sourceRecordIds
      ORDER BY Source_Record_Id__c, CreatedDate
    ];
  }
}