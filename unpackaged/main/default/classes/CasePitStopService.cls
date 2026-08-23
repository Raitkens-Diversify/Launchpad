/**
 * Branch Pit Stop start/complete: sets Case.Pitstop_Start__c and Case.IsStopped.
 */
public with sharing class CasePitStopService {
    public static final String ERROR_ALREADY_STOPPED =
        'A Branch Pit Stop is already in progress on this Case. Complete the existing Pit Stop before starting another.';

    /**
     * Merges Pit Stop Case field changes into casesToUpdate. Applies addError on Tasks when
     * a Pit Stop is already in progress.
     */
    public static void accumulateCaseUpdates(
        List<Task> tasks,
        Map<Id, Task> oldMap,
        Map<Id, Case> caseMap,
        Map<Id, Case> casesToUpdate
    ) {
        if (tasks == null || tasks.isEmpty() || caseMap == null || casesToUpdate == null) {
            return;
        }

        List<Task> branchPitStopTasks = new List<Task>();
        for (Task taskRecord : tasks) {
            if (!isCaseWhatId(taskRecord.WhatId) || taskRecord.Branch_Pit_Stop__c != true) {
                continue;
            }
            branchPitStopTasks.add(taskRecord);
        }
        if (branchPitStopTasks.isEmpty()) {
            return;
        }

        Set<Id> casesMarkedComplete = new Set<Id>();
        Datetime nowDt = System.now();

        for (Task taskRecord : branchPitStopTasks) {
            Case caseRecord = caseMap.get(taskRecord.WhatId);
            if (caseRecord == null) {
                continue;
            }

            Boolean isCompleted = isTaskCompleted(taskRecord);
            Task oldTask = oldMap == null ? null : oldMap.get(taskRecord.Id);
            Boolean wasCompleted = oldTask != null && isTaskCompleted(oldTask);
            Boolean becameCompleted = isCompleted && (oldMap == null || !wasCompleted);

            if (becameCompleted) {
                Case updateCase = getOrCreate(casesToUpdate, caseRecord.Id);
                updateCase.Pitstop_Start__c = null;
                updateCase.IsStopped = false;
                casesMarkedComplete.add(caseRecord.Id);
            }
        }

        for (Task taskRecord : branchPitStopTasks) {
            Case caseRecord = caseMap.get(taskRecord.WhatId);
            if (caseRecord == null || casesMarkedComplete.contains(caseRecord.Id)) {
                continue;
            }
            if (isTaskCompleted(taskRecord)) {
                continue;
            }

            Boolean shouldStart = false;
            if (oldMap == null) {
                shouldStart = true;
            } else {
                Task oldTask = oldMap.get(taskRecord.Id);
                Boolean branchFlagNewlyTrue =
                    oldTask != null
                    && taskRecord.Branch_Pit_Stop__c == true
                    && oldTask.Branch_Pit_Stop__c != true;
                shouldStart = branchFlagNewlyTrue;
            }

            if (!shouldStart) {
                continue;
            }

            if (caseRecord.Pitstop_Start__c != null) {
                taskRecord.addError(ERROR_ALREADY_STOPPED);
                continue;
            }

            Case updateCase = getOrCreate(casesToUpdate, caseRecord.Id);
            updateCase.Pitstop_Start__c = nowDt;
            updateCase.IsStopped = true;
        }
    }

    private static Case getOrCreate(Map<Id, Case> casesToUpdate, Id caseId) {
        if (!casesToUpdate.containsKey(caseId)) {
            casesToUpdate.put(caseId, new Case(Id = caseId));
        }
        return casesToUpdate.get(caseId);
    }

    private static Boolean isCaseWhatId(Id whatId) {
        return whatId != null && String.valueOf(whatId).startsWith('500');
    }

    private static Boolean isTaskCompleted(Task taskRecord) {
        return taskRecord.Status == 'Completed' || taskRecord.IsClosed == true;
    }
}