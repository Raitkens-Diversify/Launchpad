/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Publishes notification events when Event attendee relations change.
 * EventRelation does not support Apex triggers, so this class is exposed
 * to record-triggered Flow on EventRelation insert/update/delete.
 */
public without sharing class NotificationEventAttendeePublisher {
  private static final String ATTENDEES_FIELD_API_NAME = 'Attendees';
  private static final String ATTENDEES_FIELD_LABEL = 'Attendees';

  public class AttendeeChangeRequest {
    @InvocableVariable(label='Event Id' required=true)
    public Id eventId;

    @InvocableVariable(label='Event Relation Id')
    public Id eventRelationId;

    @InvocableVariable(label='DML Operation')
    public String dmlOperation;
  }

  @InvocableMethod(
    label='Publish Event Attendee Notification'
    description='Publishes notification center events when Event attendees change.'
  )
  public static void publishAttendeeChangesInvocable(
    List<AttendeeChangeRequest> requests
  ) {
    publishAttendeeChanges(requests);
  }

  public static void publishAttendeeChangesByEventId(List<Id> eventIds) {
    if (eventIds == null || eventIds.isEmpty()) {
      return;
    }

    List<AttendeeChangeRequest> requests = new List<AttendeeChangeRequest>();
    for (Id eventId : eventIds) {
      if (eventId == null) {
        continue;
      }

      AttendeeChangeRequest request = new AttendeeChangeRequest();
      request.eventId = eventId;
      requests.add(request);
    }

    publishAttendeeChanges(requests);
  }

  public static void publishAttendeeChange(Id eventId) {
    publishAttendeeChange(eventId, null, null);
  }

  public static void publishAttendeeChange(
    Id eventId,
    Id eventRelationId,
    String dmlOperation
  ) {
    if (eventId == null) {
      return;
    }

    AttendeeChangeRequest request = new AttendeeChangeRequest();
    request.eventId = eventId;
    request.eventRelationId = eventRelationId;
    request.dmlOperation = dmlOperation;
    publishAttendeeChanges(new List<AttendeeChangeRequest>{ request });
  }

  private static void publishAttendeeChanges(List<AttendeeChangeRequest> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    Set<Id> eventIds = new Set<Id>();
    for (AttendeeChangeRequest request : requests) {
      if (request?.eventId != null) {
        eventIds.add(request.eventId);
      }
    }

    if (eventIds.isEmpty()) {
      return;
    }

    Map<Id, Event> eventById = queryEvents(eventIds);
    Map<Id, List<EventRelation>> relationsByEventId = queryInviteeRelationsByEventId(eventIds);
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId = new Map<Id, NotificationChangeModels.ChangeContext>();
    List<Event> eventsToPublish = new List<Event>();

    for (AttendeeChangeRequest request : requests) {
      if (request?.eventId == null || !eventById.containsKey(request.eventId)) {
        continue;
      }

      Event eventRecord = eventById.get(request.eventId);
      List<EventRelation> currentRelations = relationsByEventId.containsKey(request.eventId)
        ? relationsByEventId.get(request.eventId)
        : new List<EventRelation>();

      NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
        NotificationConstants.OBJECT_TYPE_EVENT,
        NotificationConstants.CHANGE_TYPE_UPDATE
      );
      changeContext.changedFields.add(buildAttendeeFieldChange(request, currentRelations));
      changeContext.enrichDmlContext(eventRecord);
      contextByRecordId.put(eventRecord.Id, changeContext);
      eventsToPublish.add(eventRecord);
    }

    if (eventsToPublish.isEmpty()) {
      return;
    }

    NotificationPublisher.publishWithContext(
      eventsToPublish,
      NotificationConstants.OBJECT_TYPE_EVENT,
      contextByRecordId
    );
  }

  private static NotificationChangeModels.FieldChange buildAttendeeFieldChange(
    AttendeeChangeRequest request,
    List<EventRelation> currentRelations
  ) {
    String newSummary = summarizeRelations(currentRelations);
    String oldSummary = resolvePriorAttendeeSummary(request, currentRelations);

    return new NotificationChangeModels.FieldChange(
      ATTENDEES_FIELD_API_NAME,
      ATTENDEES_FIELD_LABEL,
      oldSummary,
      newSummary,
      oldSummary,
      newSummary
    );
  }

  private static String resolvePriorAttendeeSummary(
    AttendeeChangeRequest request,
    List<EventRelation> currentRelations
  ) {
    String operation = normalizeDmlOperation(request.dmlOperation);

    if (operation == 'Delete' && request.eventRelationId != null) {
      EventRelation deletedRelation = queryEventRelation(request.eventRelationId, true);
      if (deletedRelation != null) {
        List<EventRelation> priorRelations = new List<EventRelation>(currentRelations);
        priorRelations.add(deletedRelation);
        return summarizeRelations(priorRelations);
      }
    }

    if (request.eventRelationId != null) {
      List<EventRelation> priorRelations = excludeRelation(
        currentRelations,
        request.eventRelationId
      );
      if (priorRelations.size() != currentRelations.size()) {
        return summarizeRelations(priorRelations);
      }

      EventRelation deletedRelation = queryEventRelation(request.eventRelationId, true);
      if (deletedRelation != null) {
        List<EventRelation> restoredRelations = new List<EventRelation>(currentRelations);
        restoredRelations.add(deletedRelation);
        return summarizeRelations(restoredRelations);
      }
    }

    if (currentRelations.isEmpty()) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (currentRelations.size() == 1) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    return NotificationConstants.DISPLAY_NOT_APPLICABLE;
  }

  private static Map<Id, Event> queryEvents(Set<Id> eventIds) {
    Map<Id, Event> eventById = new Map<Id, Event>(
      [
        SELECT Id, Subject
        FROM Event
        WHERE Id IN :eventIds
      ]
    );

    return eventById;
  }

  private static Map<Id, List<EventRelation>> queryInviteeRelationsByEventId(
    Set<Id> eventIds
  ) {
    Map<Id, List<EventRelation>> relationsByEventId = new Map<Id, List<EventRelation>>();

    for (EventRelation attendeeRelation : [
      SELECT Id, EventId, RelationId, Relation.Name
      FROM EventRelation
      WHERE EventId IN :eventIds AND IsInvitee = TRUE
      ORDER BY Relation.Name ASC NULLS LAST
    ]) {
      if (!relationsByEventId.containsKey(attendeeRelation.EventId)) {
        relationsByEventId.put(
          attendeeRelation.EventId,
          new List<EventRelation>()
        );
      }

      relationsByEventId.get(attendeeRelation.EventId).add(attendeeRelation);
    }

    return relationsByEventId;
  }

  private static EventRelation queryEventRelation(Id eventRelationId, Boolean includeDeleted) {
    if (eventRelationId == null) {
      return null;
    }

    List<EventRelation> relations = includeDeleted
      ? (List<EventRelation>) Database.query(
          'SELECT Id, EventId, RelationId, Relation.Name ' +
            'FROM EventRelation ' +
            'WHERE Id = :eventRelationId ' +
            'ALL ROWS'
        )
      : [
          SELECT Id, EventId, RelationId, Relation.Name
          FROM EventRelation
          WHERE Id = :eventRelationId
          LIMIT 1
        ];

    return relations.isEmpty() ? null : relations[0];
  }

  private static List<EventRelation> excludeRelation(
    List<EventRelation> relations,
    Id eventRelationId
  ) {
    List<EventRelation> filteredRelations = new List<EventRelation>();

    for (EventRelation relation : relations) {
      if (relation.Id != eventRelationId) {
        filteredRelations.add(relation);
      }
    }

    return filteredRelations;
  }

  private static String summarizeRelations(List<EventRelation> relations) {
    if (relations == null || relations.isEmpty()) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    Set<Id> unresolvedRelationIds = new Set<Id>();
    List<String> attendeeNames = new List<String>();

    for (EventRelation relation : relations) {
      String relationName = relation.Relation == null ? null : relation.Relation.Name;

      if (!String.isBlank(relationName)) {
        attendeeNames.add(relationName.trim());
        continue;
      }

      if (relation.RelationId != null) {
        unresolvedRelationIds.add(relation.RelationId);
      }
    }

    if (!unresolvedRelationIds.isEmpty()) {
      Map<Id, String> idToDisplay = NotificationChangeDisplayResolver.resolveRecordDisplays(
        unresolvedRelationIds
      );

      for (Id relationId : unresolvedRelationIds) {
        if (idToDisplay.containsKey(relationId)) {
          attendeeNames.add(idToDisplay.get(relationId));
        }
      }
    }

    attendeeNames.sort();
    return attendeeNames.isEmpty()
      ? NotificationConstants.DISPLAY_NOT_APPLICABLE
      : String.join(attendeeNames, ', ');
  }

  private static String normalizeDmlOperation(String dmlOperation) {
    if (String.isBlank(dmlOperation)) {
      return null;
    }

    String normalizedOperation = dmlOperation.trim();

    if (normalizedOperation.equalsIgnoreCase(NotificationConstants.CHANGE_TYPE_INSERT)) {
      return NotificationConstants.CHANGE_TYPE_INSERT;
    }

    if (normalizedOperation.equalsIgnoreCase(NotificationConstants.CHANGE_TYPE_UPDATE)) {
      return NotificationConstants.CHANGE_TYPE_UPDATE;
    }

    if (normalizedOperation.equalsIgnoreCase('Delete')) {
      return 'Delete';
    }

    return normalizedOperation;
  }
}