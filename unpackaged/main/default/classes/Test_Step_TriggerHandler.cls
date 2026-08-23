/**
 * Test_Step_TriggerHandler — authoring changes the rollup denominator, and
 * step deletion cascades to results across EVERY execution of the case
 * (03 §9). Ordering is the trick: results are captured and deleted in BEFORE
 * delete (the result->step lookup clears once the step dies) with rollups
 * suppressed; AFTER delete recomputes against the now-correct denominator.
 */
public without sharing class Test_Step_TriggerHandler {

    public void isAfterInsert(List<Test_Step__c> steps) {
        UatExecutionService.recomputeForCases(caseIds(steps, null));
    }

    public void isAfterUpdate(Map<Id, Test_Step__c> newMap, Map<Id, Test_Step__c> oldMap) {
        // Only Is_Explore__c flips move the denominator.
        List<Test_Step__c> changed = new List<Test_Step__c>();
        for (Test_Step__c step : newMap.values()) {
            if (step.Is_Explore__c != oldMap.get(step.Id).Is_Explore__c) {
                changed.add(step);
            }
        }
        if (!changed.isEmpty()) {
            UatExecutionService.recomputeForCases(caseIds(changed, null));
        }
    }

    public void isBeforeDelete(List<Test_Step__c> oldSteps) {
        UatExecutionService.cascadeStepDelete(oldSteps);
    }

    public void isAfterDelete() {
        UatExecutionService.afterStepDelete();
    }

    private Set<Id> caseIds(List<Test_Step__c> steps, Set<Id> seed) {
        Set<Id> ids = seed == null ? new Set<Id>() : seed;
        for (Test_Step__c step : steps) {
            ids.add(step.Test_Case__c);
        }
        return ids;
    }
}