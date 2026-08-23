/**
 * Case trigger entry for Standard SLA automation.
 * Pit Stop minutes accumulate in before update; EntitlementId is cleared before delete.
 */
public with sharing class CaseSlaTriggerHandler {
    public void isBeforeUpdate(Map<Id, Case> newMap, Map<Id, Case> oldMap) {
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            newMap == null ? null : newMap.values(),
            oldMap
        );
    }

    public void isBeforeDelete(Map<Id, Case> oldMap) {
        CaseEntitlementService.clearEntitlementIdsBeforeDelete(
            oldMap == null ? null : oldMap.values()
        );
    }
}