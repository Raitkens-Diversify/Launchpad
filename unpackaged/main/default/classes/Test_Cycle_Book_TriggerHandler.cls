/**
 * Test_Cycle_Book_TriggerHandler — attaching a book to a cycle eagerly
 * materializes unclaimed execution slots for every newly-in-scope case
 * (03 §3); detaching cleans up pristine out-of-scope slots only.
 */
public without sharing class Test_Cycle_Book_TriggerHandler {

    public void isAfterInsert(List<Test_Cycle_Book__c> rows) {
        UatExecutionService.materializeSlots(cycleIds(rows));
    }

    public void isAfterDelete(List<Test_Cycle_Book__c> rows) {
        UatExecutionService.cleanupPristineSlots(cycleIds(rows));
    }

    private Set<Id> cycleIds(List<Test_Cycle_Book__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (Test_Cycle_Book__c row : rows) {
            ids.add(row.Test_Cycle__c);
        }
        return ids;
    }
}