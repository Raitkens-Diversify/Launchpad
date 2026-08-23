/**
 * Sets Case Home Office milestone timestamps when related Tasks complete
 * with matching Task_Template_Item__c flags.
 * On Submission milestone completion, also assigns Active Account EntitlementId when blank.
 */
public with sharing class CaseMilestoneService {
    /**
     * Merges HO milestone Case field changes into casesToUpdate (idempotent; does not overwrite).
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

        Set<Id> taskIds = new Set<Id>();
        for (Task taskRecord : tasks) {
            if (!isCaseWhatId(taskRecord.WhatId) || !isTaskCompleted(taskRecord)) {
                continue;
            }
            Task oldTask = oldMap == null ? null : oldMap.get(taskRecord.Id);
            if (oldTask != null && isTaskCompleted(oldTask)) {
                continue;
            }
            if (taskRecord.Task_Template_Item__c == null) {
                continue;
            }
            taskIds.add(taskRecord.Id);
        }
        if (taskIds.isEmpty()) {
            return;
        }

        Map<Id, Task> tasksWithTemplate = new Map<Id, Task>([
            SELECT Id, WhatId,
                Task_Template_Item__r.Home_Office_Submission_Milestone__c,
                Task_Template_Item__r.Home_Office_Goal_Milestone__c
            FROM Task
            WHERE Id IN :taskIds
        ]);

        Datetime nowDt = System.now();
        Set<Id> casesNeedingEntitlement = new Set<Id>();

        for (Task taskRecord : tasksWithTemplate.values()) {
            Case caseRecord = caseMap.get(taskRecord.WhatId);
            if (caseRecord == null || taskRecord.Task_Template_Item__r == null) {
                continue;
            }

            Boolean submission =
                taskRecord.Task_Template_Item__r.Home_Office_Submission_Milestone__c == true;
            Boolean goal =
                taskRecord.Task_Template_Item__r.Home_Office_Goal_Milestone__c == true;
            if (!submission && !goal) {
                continue;
            }

            Case existingUpdate = casesToUpdate.get(caseRecord.Id);
            Datetime pendingSubmissionStart = existingUpdate == null
                ? null
                : existingUpdate.Home_Office_Submission_Milestone_Start__c;
            Datetime pendingGoalEnd = existingUpdate == null
                ? null
                : existingUpdate.Home_Office_Goal_Milestone_End__c;
            Id pendingEntitlementId = existingUpdate == null
                ? null
                : existingUpdate.EntitlementId;

            Boolean setSubmission = submission
                && caseRecord.Home_Office_Submission_Milestone_Start__c == null
                && pendingSubmissionStart == null;
            Boolean setGoal = goal
                && caseRecord.Home_Office_Goal_Milestone_End__c == null
                && pendingGoalEnd == null;
            Boolean setEntitlement = submission
                && caseRecord.AccountId != null
                && caseRecord.EntitlementId == null
                && pendingEntitlementId == null;

            if (!setSubmission && !setGoal && !setEntitlement) {
                continue;
            }

            Case updateCase = existingUpdate != null
                ? existingUpdate
                : new Case(Id = caseRecord.Id);
            if (setSubmission) {
                updateCase.Home_Office_Submission_Milestone_Start__c = nowDt;
            }
            if (setGoal) {
                updateCase.Home_Office_Goal_Milestone_End__c = nowDt;
            }
            if (setEntitlement) {
                updateCase.AccountId = caseRecord.AccountId;
                casesNeedingEntitlement.add(caseRecord.Id);
            }
            casesToUpdate.put(caseRecord.Id, updateCase);
        }

        if (!casesNeedingEntitlement.isEmpty()) {
            List<Case> entitlementTargets = new List<Case>();
            for (Id caseId : casesNeedingEntitlement) {
                entitlementTargets.add(casesToUpdate.get(caseId));
            }
            CaseEntitlementService.assignEntitlementIds(entitlementTargets);
        }
    }

    private static Boolean isCaseWhatId(Id whatId) {
        return whatId != null && String.valueOf(whatId).startsWith('500');
    }

    /**
     * Task completed: Status = Completed or IsClosed (Flow "IsCompleted").
     */
    private static Boolean isTaskCompleted(Task taskRecord) {
        return taskRecord.Status == 'Completed' || taskRecord.IsClosed == true;
    }
}