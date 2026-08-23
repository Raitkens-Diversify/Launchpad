trigger Test_Step_Trigger on Test_Step__c (after insert, after update, before delete, after delete) {
    Test_Step_TriggerHandler handler = new Test_Step_TriggerHandler();
    if (Trigger.isAfter && Trigger.isInsert) {
        handler.isAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        handler.isBeforeDelete(Trigger.old);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        handler.isAfterDelete();
    }
}