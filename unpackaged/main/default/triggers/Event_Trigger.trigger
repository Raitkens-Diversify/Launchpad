trigger Event_Trigger on Event (after insert, after update) {
  Event_TriggerHandler handler = new Event_TriggerHandler();
  if (Trigger.isAfter && Trigger.isInsert) {
    handler.isAfterInsert(Trigger.newMap);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
  }
}