trigger Test_Execution_Trigger on Test_Execution__c (before insert, before update) {
    Test_Execution_TriggerHandler handler = new Test_Execution_TriggerHandler();
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        handler.stampIdentity(Trigger.new);
    }
}