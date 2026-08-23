/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Publishes Notification_Center_Event__e platform events after eligible record changes.
 */
public with sharing class NotificationPublisher {
  @TestVisible
  private static Boolean isPublishing = false;

  @TestVisible
  private static Integer testPublishedEventCount = 0;

  @TestVisible
  private static List<Notification_Center_Event__e> testPublishedEvents;

  @TestVisible
  static void resetForTest() {
    isPublishing = false;
    testPublishedEventCount = 0;
    testPublishedEvents = null;
  }

  public static void publishFromRecords(List<SObject> records, String sourceType) {
    new NotificationPublisher().publish(records, sourceType);
  }

  public static void publishWithContext(
    List<SObject> records,
    String sourceType,
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    new NotificationPublisher().publishWithContextInternal(
      records,
      sourceType,
      contextByRecordId
    );
  }

  public void publish(List<SObject> records, String sourceType) {
    publishWithContextInternal(records, sourceType, null);
  }

  public void publishWithContextInternal(
    List<SObject> records,
    String sourceType,
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    if (records == null || records.isEmpty() || isPublishing) {
      return;
    }

    isPublishing = true;
    testPublishedEventCount = 0;
    testPublishedEvents = new List<Notification_Center_Event__e>();
    try {
      List<Notification_Center_Event__e> events = buildEvents(
        records,
        sourceType,
        contextByRecordId
      );
      if (events.isEmpty()) {
        return;
      }

      testPublishedEventCount = events.size();
      testPublishedEvents = events;
      EventBus.publish(events);
    } finally {
      isPublishing = false;
    }
  }

  private List<Notification_Center_Event__e> buildEvents(
    List<SObject> records,
    String sourceType,
    Map<Id, NotificationChangeModels.ChangeContext> contextByRecordId
  ) {
    List<Notification_Center_Event__e> events = new List<Notification_Center_Event__e>();

    for (SObject record : records) {
      if (record.Id == null) {
        continue;
      }

      Notification_Center_Event__e centerEvent = new Notification_Center_Event__e();
      centerEvent.Source_Type__c = sourceType;
      centerEvent.Source_Id__c = String.valueOf(record.Id);

      if (contextByRecordId != null && contextByRecordId.containsKey(record.Id)) {
        NotificationChangeModels.ChangeContext changeContext = contextByRecordId.get(
          record.Id
        );
        if (changeContext != null) {
          centerEvent.Change_Context__c = changeContext.toJson();
        }
      }

      events.add(centerEvent);
    }

    return events;
  }
}