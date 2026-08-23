trigger Test_Cycle_Trigger on Test_Cycle__c (after update) {
    Test_Cycle_TriggerHandler handler = new Test_Cycle_TriggerHandler();
    if (Trigger.isAfter && Trigger.isUpdate) {
        handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
    }
}