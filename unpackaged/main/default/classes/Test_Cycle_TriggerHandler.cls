/**
 * Test_Cycle_TriggerHandler — 03 §6: when a cycle's team changes, retarget
 * ONLY the unclaimed executions in its scope. Claimed executions are never
 * silently affected by a later reassignment. Delegates to UatExecutionService.
 */
public without sharing class Test_Cycle_TriggerHandler {

    public void isAfterUpdate(Map<Id, Test_Cycle__c> newMap, Map<Id, Test_Cycle__c> oldMap) {
        Map<Id, Id> newTeamByCycle = new Map<Id, Id>();
        for (Test_Cycle__c cycle : newMap.values()) {
            if (cycle.Assigned_Team__c != oldMap.get(cycle.Id).Assigned_Team__c) {
                newTeamByCycle.put(cycle.Id, cycle.Assigned_Team__c);
            }
        }
        UatExecutionService.retargetUnclaimed(newTeamByCycle);
    }
}