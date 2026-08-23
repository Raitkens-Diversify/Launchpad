/**
 * Test_Cycle_Case_TriggerHandler — adding a case directly to a cycle eagerly
 * materializes its unclaimed slot (03 §3); removal cleans up pristine
 * out-of-scope slots only.
 */
public without sharing class Test_Cycle_Case_TriggerHandler {

    public void isAfterInsert(List<Test_Cycle_Case__c> rows) {
        UatExecutionService.materializeSlots(cycleIds(rows));
    }

    public void isAfterDelete(List<Test_Cycle_Case__c> rows) {
        UatExecutionService.cleanupPristineSlots(cycleIds(rows));
    }

    private Set<Id> cycleIds(List<Test_Cycle_Case__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (Test_Cycle_Case__c row : rows) {
            ids.add(row.Test_Cycle__c);
        }
        return ids;
    }
}