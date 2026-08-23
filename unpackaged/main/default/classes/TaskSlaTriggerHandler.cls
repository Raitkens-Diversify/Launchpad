/**
 * Task trigger entry for Standard SLA automation.
 * After insert/update: Branch Pit Stop Case fields, HO milestone timestamps, EntitlementId.
 */
public with sharing class TaskSlaTriggerHandler {
    public void isAfterInsert(Map<Id, Task> newMap) {
        CaseTaskAutomationService.processAfterInsert(newMap);
    }

    public void isAfterUpdate(Map<Id, Task> newMap, Map<Id, Task> oldMap) {
        CaseTaskAutomationService.processAfterUpdate(newMap, oldMap);
    }
}