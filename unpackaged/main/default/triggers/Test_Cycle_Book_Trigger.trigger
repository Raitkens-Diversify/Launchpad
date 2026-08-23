trigger Test_Cycle_Book_Trigger on Test_Cycle_Book__c (after insert, after delete) {
    Test_Cycle_Book_TriggerHandler handler = new Test_Cycle_Book_TriggerHandler();
    if (Trigger.isAfter && Trigger.isInsert) {
        handler.isAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        handler.isAfterDelete(Trigger.old);
    }
}