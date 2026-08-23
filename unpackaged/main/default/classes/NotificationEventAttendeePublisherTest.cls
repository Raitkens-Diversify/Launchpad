/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventAttendeePublisherTest {
  @IsTest
  static void publishAttendeeChangesFindsEventAndInvokesPublisher() {
    NotificationPublisher.resetForTest();

    Event eventRecord = new Event(
      Subject = 'Attendee Publisher Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChange(eventRecord.Id);

    System.assertEquals(
      1,
      NotificationPublisher.testPublishedEventCount,
      'Attendee publisher should publish one notification event.'
    );
  }

  @IsTest
  static void publishAttendeeChangeIncludesAttendeeNames() {
    NotificationPublisher.resetForTest();
    User attendeeUser = NotificationTestDataFactory.createStandardUser('evtatt');
    attendeeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :attendeeUser.Id
      LIMIT 1
    ];

    Event eventRecord = new Event(
      Subject = 'Attendee Names Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    EventRelation attendeeRelation = new EventRelation(
      EventId = eventRecord.Id,
      RelationId = attendeeUser.Id,
      IsInvitee = true
    );
    NotificationTestDataFactory.insertRecord(attendeeRelation);

    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChange(
      eventRecord.Id,
      attendeeRelation.Id,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    NotificationChangeModels.FieldChange attendeeChange = changeContext.changedFields[0];

    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      attendeeChange.oldDisplay
    );
    System.assertEquals(attendeeUser.Name, attendeeChange.newDisplay);
  }

  @IsTest
  static void publishAttendeeChangesInvocableProcessesRequests() {
    NotificationPublisher.resetForTest();

    Event eventRecord = new Event(
      Subject = 'Invocable Attendee Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationEventAttendeePublisher.AttendeeChangeRequest request = new NotificationEventAttendeePublisher.AttendeeChangeRequest();
    request.eventId = eventRecord.Id;
    request.dmlOperation = NotificationConstants.CHANGE_TYPE_UPDATE;

    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChangesInvocable(
      new List<NotificationEventAttendeePublisher.AttendeeChangeRequest>{ request }
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
  }

  @IsTest
  static void publishAttendeeChangesByEventIdSkipsNullIds() {
    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChangesByEventId(null);
    NotificationEventAttendeePublisher.publishAttendeeChangesByEventId(
      new List<Id>{ null }
    );
    System.assertEquals(0, NotificationPublisher.testPublishedEventCount);
  }

  @IsTest
  static void publishAttendeeChangeHandlesDeleteOperation() {
    NotificationPublisher.resetForTest();
    User attendeeUser = NotificationTestDataFactory.createStandardUser('evtattdel');

    Event eventRecord = new Event(
      Subject = 'Delete Attendee Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    EventRelation attendeeRelation = new EventRelation(
      EventId = eventRecord.Id,
      RelationId = attendeeUser.Id,
      IsInvitee = true
    );
    NotificationTestDataFactory.insertRecord(attendeeRelation);

    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChange(
      eventRecord.Id,
      attendeeRelation.Id,
      'Delete'
    );

    System.assertEquals(1, NotificationPublisher.testPublishedEventCount);
  }

  @IsTest
  static void publishAttendeeChangeNoopsForNullEventId() {
    NotificationPublisher.resetForTest();
    NotificationEventAttendeePublisher.publishAttendeeChange(null);
    System.assertEquals(0, NotificationPublisher.testPublishedEventCount);
  }
}