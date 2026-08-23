/**
 * Test_Step_Result_TriggerHandler — 03 §10: the execution's status/result
 * rolls up on EVERY result change, from any write path, so queue badges stay
 * live. UatExecutionService.suppressRollup guards the step-delete-cascade
 * window and bulk result seeding.
 */
public without sharing class Test_Step_Result_TriggerHandler {

    public void recompute(List<Test_Step_Result__c> rows) {
        Set<Id> executionIds = new Set<Id>();
        for (Test_Step_Result__c row : rows) {
            executionIds.add(row.Test_Execution__c);
        }
        UatExecutionService.recomputeRollups(executionIds);
    }
}