/**
 * Orchestrates Case updates driven by Task insert/update (Pit Stop + HO milestones)
 * into a single Case DML where possible.
 */
public with sharing class CaseTaskAutomationService {
    private static Set<Id> casesBeingUpdated = new Set<Id>();

    public static void processAfterInsert(Map<Id, Task> newMap) {
        if (newMap == null || newMap.isEmpty()) {
            return;
        }
        apply(newMap.values(), null);
    }

    public static void processAfterUpdate(Map<Id, Task> newMap, Map<Id, Task> oldMap) {
        if (newMap == null || newMap.isEmpty()) {
            return;
        }
        apply(newMap.values(), oldMap);
    }

    private static void apply(List<Task> tasks, Map<Id, Task> oldMap) {
        Set<Id> candidateCaseIds = new Set<Id>();
        for (Task taskRecord : tasks) {
            if (isCaseWhatId(taskRecord.WhatId) && !casesBeingUpdated.contains(taskRecord.WhatId)) {
                candidateCaseIds.add(taskRecord.WhatId);
            }
        }
        if (candidateCaseIds.isEmpty()) {
            return;
        }

        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, AccountId, EntitlementId, Pitstop_Start__c, IsStopped, Pitstop_Total_Minutes__c,
                Home_Office_Submission_Milestone_Start__c, Home_Office_Goal_Milestone_End__c
            FROM Case
            WHERE Id IN :candidateCaseIds
        ]);

        Map<Id, Case> casesToUpdate = new Map<Id, Case>();
        CasePitStopService.accumulateCaseUpdates(tasks, oldMap, caseMap, casesToUpdate);
        CaseMilestoneService.accumulateCaseUpdates(tasks, oldMap, caseMap, casesToUpdate);

        if (casesToUpdate.isEmpty()) {
            return;
        }

        casesBeingUpdated.addAll(casesToUpdate.keySet());
        try {
            update casesToUpdate.values();
        } finally {
            casesBeingUpdated.removeAll(casesToUpdate.keySet());
        }
    }

    private static Boolean isCaseWhatId(Id whatId) {
        return whatId != null && String.valueOf(whatId).startsWith('500');
    }
}