/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 *
 * Thin trigger handler for Event notification publishing.
 */
public class Event_TriggerHandler {
  public void isAfterInsert(Map<Id, Event> newMap) {
    NotificationChangePublisher.publishInserts(
      NotificationConstants.OBJECT_TYPE_EVENT,
      newMap.values()
    );
  }

  public void isAfterUpdate(Map<Id, Event> newMap, Map<Id, Event> oldMap) {
    NotificationChangePublisher.publishUpdates(
      NotificationConstants.OBJECT_TYPE_EVENT,
      newMap,
      oldMap
    );
  }
}