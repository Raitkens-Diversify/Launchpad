trigger Test_Book_Item_Trigger on Test_Book_Item__c (after insert, after delete) {
    Test_Book_Item_TriggerHandler handler = new Test_Book_Item_TriggerHandler();
    if (Trigger.isAfter && Trigger.isInsert) {
        handler.isAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        handler.isAfterDelete(Trigger.old);
    }
}