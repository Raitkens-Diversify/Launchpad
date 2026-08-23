trigger Test_Step_Result_Trigger on Test_Step_Result__c (after insert, after update, after delete, after undelete) {
    Test_Step_Result_TriggerHandler handler = new Test_Step_Result_TriggerHandler();
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete)) {
        handler.recompute(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        handler.recompute(Trigger.old);
    }
}