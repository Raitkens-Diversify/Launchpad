/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventChangePublisherTest {
  @IsTest
  static void publishInsertsPublishesRecordCreatedContext() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Insert Event');

    NotificationChangePublisher.publishInserts(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<SObject>{ eventRecord }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_INSERT,
      NotificationChangeModels.fromJson(
          NotificationPublisher.testPublishedEvents[0].Change_Context__c
        )
        .triggerType
    );
  }

  @IsTest
  static void publishUpdatesPublishesStartAndEndDateTimeChanges() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Start End Event');
    Event oldEvent = eventRecord.clone(true, true, true, true);

    eventRecord.StartDateTime = eventRecord.StartDateTime.addHours(1);
    eventRecord.EndDateTime = eventRecord.EndDateTime.addHours(1);

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ eventRecord.Id => eventRecord },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    Set<String> changedFieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      changedFieldApiNames.add(fieldChange.apiName);
    }
    System.assert(changedFieldApiNames.contains('StartDateTime'));
    System.assert(changedFieldApiNames.contains('EndDateTime'));
  }

  @IsTest
  static void publishUpdatesPublishesAssignedToChange() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Assigned To Event');
    User alternateOwner = selectAlternateOwner(eventRecord.OwnerId);
    Event oldEvent = eventRecord.clone(true, true, true, true);

    eventRecord.OwnerId = alternateOwner.Id;

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ eventRecord.Id => eventRecord },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    assertPublishedFieldChange('OwnerId');
  }

  @IsTest
  static void publishUpdatesPublishesLocationChange() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Location Event');
    eventRecord.Location = '742 Evergreen Terrace';
    NotificationTestDataFactory.updateRecord(eventRecord);
    NotificationPublisher.resetForTest();

    Event oldEvent = eventRecord.clone(true, true, true, true);
    eventRecord.Location = 'Springfield Town Hall';

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ eventRecord.Id => eventRecord },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    assertPublishedFieldChange('Location');
  }

  @IsTest
  static void publishUpdatesPublishesDescriptionChange() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Description Event');
    Event oldEvent = eventRecord.clone(true, true, true, true);

    eventRecord.Description = 'Updated event description body.';

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ eventRecord.Id => eventRecord },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    assertPublishedFieldChange('Description');
  }

  @IsTest
  static void publishUpdatesPublishesCancelledChangeWhenFieldExists() {
    if (
      !hasEventField('IsArchived') ||
      !isEventFieldUpdateable('IsArchived')
    ) {
      System.assert(
        true,
        'Event.IsArchived is unavailable or not updateable in this org.'
      );
      return;
    }

    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Cancelled Event');
    Event oldEvent = eventRecord.clone(true, true, true, true);
    Event newEvent = buildEventWithFieldValue(oldEvent, 'IsArchived', true);

    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new Map<Id, SObject>{ newEvent.Id => newEvent },
      new Map<Id, SObject>{ oldEvent.Id => oldEvent }
    );

    assertPublishedFieldChange('IsArchived');
  }

  @IsTest
  static void publishAttendeeChangesPublishesAttendeesContext() {
    NotificationPublisher.resetForTest();
    Event eventRecord = insertHouseholdEvent('Publisher Attendees Event');
    User attendeeUser = NotificationTestDataFactory.createStandardUser('evtchg');
    attendeeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :attendeeUser.Id
      LIMIT 1
    ];

    EventRelation attendeeRelation = new EventRelation(
      EventId = eventRecord.Id,
      RelationId = attendeeUser.Id,
      IsInvitee = true
    );
    NotificationTestDataFactory.insertRecord(attendeeRelation);

    NotificationEventAttendeePublisher.publishAttendeeChange(
      eventRecord.Id,
      attendeeRelation.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_UPDATE, changeContext.triggerType);
    System.assertEquals(1, changeContext.changedFields.size());
    System.assertEquals('Attendees', changeContext.changedFields[0].apiName);
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      changeContext.changedFields[0].oldDisplay
    );
    System.assertEquals(attendeeUser.Name, changeContext.changedFields[0].newDisplay);
  }

  private static Event insertHouseholdEvent(String subject) {
    Account household = new Account(Name = 'Event Publisher Household');
    NotificationTestDataFactory.insertRecord(household);

    Event eventRecord = new Event(
      Subject = subject,
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    return [
      SELECT
        Id,
        Subject,
        OwnerId,
        WhatId,
        WhoId,
        StartDateTime,
        EndDateTime,
        Location,
        Description,
        IsArchived
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];
  }

  private static User selectAlternateOwner(Id currentOwnerId) {
    List<User> alternateOwners = [
      SELECT Id
      FROM User
      WHERE Id != :currentOwnerId AND IsActive = TRUE
      LIMIT 1
    ];
    System.assert(!alternateOwners.isEmpty(), 'Expected an alternate active user.');
    return alternateOwners[0];
  }

  private static Event buildEventWithFieldValue(
    Event sourceEvent,
    String fieldApiName,
    Object fieldValue
  ) {
    Map<String, Object> fieldValues = sourceEvent.getPopulatedFieldsAsMap();
    fieldValues.put(fieldApiName, fieldValue);
    return (Event) JSON.deserialize(JSON.serialize(fieldValues), Event.class);
  }

  private static void assertPublishedFieldChange(String fieldApiName) {
    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(NotificationConstants.CHANGE_TYPE_UPDATE, changeContext.triggerType);

    Set<String> changedFieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      changedFieldApiNames.add(fieldChange.apiName);
    }

    System.assert(
      changedFieldApiNames.contains(fieldApiName),
      'Expected changed field ' + fieldApiName + ' but got ' + changedFieldApiNames
    );
  }

  private static Boolean hasEventField(String fieldApiName) {
    return Schema.SObjectType.Event.fields.getMap().containsKey(fieldApiName.toLowerCase());
  }

  private static Boolean isEventFieldUpdateable(String fieldApiName) {
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Event.fields.getMap();
    Schema.SObjectField fieldToken = fieldMap.get(fieldApiName.toLowerCase());
    return fieldToken != null && fieldToken.getDescribe().isUpdateable();
  }
}