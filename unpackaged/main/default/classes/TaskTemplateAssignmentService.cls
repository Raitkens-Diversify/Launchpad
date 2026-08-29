/**
 * Resolves the Owner (and, for approval queues, the RecordType) of a Task from
 * its Task Template configuration.
 *
 * This mirrors the assignment rules used by Task_TriggerHandler when it activates
 * the next task in a case's template sequence (Queue vs. FA Team Permission), so
 * that other entry points -- e.g. re-activating a task after a Pit Stop is
 * completed -- reassign the same way instead of duplicating the rules ad hoc.
 */
public with sharing class TaskTemplateAssignmentService {

    /**
     * Reassigns each task in place using its Task_Template__r configuration.
     *
     * Every task must already have these fields loaded:
     *   WhatId, Task_Template__r.Assigned_To__c, Task_Template__r.Queue__c,
     *   Task_Template__r.FA_Team_Permission__c
     * The caller is responsible for the DML -- this method only mutates OwnerId
     * and RecordTypeId on the supplied records.
     */
    public static void assignOwners(List<Task> tasksToAssign) {
        if (tasksToAssign == null || tasksToAssign.isEmpty()) {
            return;
        }

        Set<Id> caseIds = new Set<Id>();
        Set<String> queueNames = new Set<String>();

        for (Task taskRecord : tasksToAssign) {
            if (taskRecord.WhatId != null && String.valueOf(taskRecord.WhatId).startsWith('500')) {
                caseIds.add(taskRecord.WhatId);
            }
            if (taskRecord.Task_Template__r != null && !String.isEmpty(taskRecord.Task_Template__r.Queue__c)) {
                queueNames.add(taskRecord.Task_Template__r.Queue__c);
            }
        }
        // Back Office Operations maps onto the 'Operations' queue.
        queueNames.add('Operations');

        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, OwnerId, Financial_Advisor_Team__c
            FROM Case
            WHERE Id IN :caseIds
        ]);

        Set<Id> fatIds = new Set<Id>();
        for (Case caseRecord : caseMap.values()) {
            if (!String.isEmpty(caseRecord.Financial_Advisor_Team__c)) {
                fatIds.add(caseRecord.Financial_Advisor_Team__c);
            }
        }

        Map<Id, Financial_Advisor_Team__c> fatMap = new Map<Id, Financial_Advisor_Team__c>([
            SELECT Id, (SELECT Id, Associate_Advisor__c, CSA__c, Send_Notifications__c,
                               Review_Paperwork__c, Draft_Paperwork__c, Trading__c,
                               User__c, Operations__c, Primary__c
                        FROM Financial_Advisor_Team_Members__r)
            FROM Financial_Advisor_Team__c
            WHERE Id IN :fatIds
        ]);

        Map<Id, Id> operationsUserByFat = new Map<Id, Id>();
        Map<Id, Id> primaryUserByFat = new Map<Id, Id>();
        for (Financial_Advisor_Team__c fat : fatMap.values()) {
            for (Financial_Advisor_Team_Member__c fatm : fat.Financial_Advisor_Team_Members__r) {
                if (fatm.Operations__c) {
                    operationsUserByFat.put(fat.Id, fatm.User__c);
                }
                if (fatm.Primary__c) {
                    primaryUserByFat.put(fat.Id, fatm.User__c);
                }
            }
        }

        Map<String, Id> queueIdByName = new Map<String, Id>();
        for (Group groupRecord : [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name IN :queueNames]) {
            queueIdByName.put(groupRecord.Name, groupRecord.Id);
        }

        Id approvalTaskRecordTypeId =
            Schema.SObjectType.Task.getRecordTypeInfosByName().get('Approval Task').getRecordTypeId();

        for (Task taskRecord : tasksToAssign) {
            Case relatedCase = caseMap.get(taskRecord.WhatId);
            if (relatedCase == null || taskRecord.Task_Template__r == null) {
                continue;
            }

            String assignedTo = taskRecord.Task_Template__r.Assigned_To__c;

            if (assignedTo == 'Queue') {
                String queueName = taskRecord.Task_Template__r.Queue__c;
                if (String.isEmpty(queueName)) {
                    continue;
                }
                if (queueName == 'Compliance' || queueName == 'Principal Review') {
                    taskRecord.RecordTypeId = approvalTaskRecordTypeId;
                    taskRecord.OwnerId = queueIdByName.get(queueName);
                } else if (queueName == 'Back Office Operations') {
                    taskRecord.OwnerId = queueIdByName.get('Operations');
                } else if (queueName == 'Financial Advisor Team Operations') {
                    if (operationsUserByFat.containsKey(relatedCase.Financial_Advisor_Team__c)) {
                        taskRecord.OwnerId = operationsUserByFat.get(relatedCase.Financial_Advisor_Team__c);
                    } else if (primaryUserByFat.containsKey(relatedCase.Financial_Advisor_Team__c)) {
                        taskRecord.OwnerId = primaryUserByFat.get(relatedCase.Financial_Advisor_Team__c);
                    }
                } else if (queueIdByName.containsKey(queueName)) {
                    taskRecord.OwnerId = queueIdByName.get(queueName);
                }
            } else if (assignedTo == 'FA Team Permission') {
                if (String.isEmpty(relatedCase.Financial_Advisor_Team__c)
                    || !fatMap.containsKey(relatedCase.Financial_Advisor_Team__c)) {
                    continue;
                }
                String fieldName = fatMemberFieldFor(taskRecord.Task_Template__r.FA_Team_Permission__c);
                if (fieldName == null) {
                    continue;
                }
                List<Financial_Advisor_Team_Member__c> members =
                    fatMap.get(relatedCase.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
                for (Financial_Advisor_Team_Member__c fatm : members) {
                    if ((Boolean) fatm.get(fieldName)) {
                        taskRecord.OwnerId = fatm.User__c;
                        break;
                    } else {
                        taskRecord.OwnerId = relatedCase.OwnerId;
                    }
                }
            }
        }
    }

    private static String fatMemberFieldFor(String permission) {
        switch on permission {
            when 'Trading'            { return 'Trading__c'; }
            when 'Draft Paperwork'    { return 'Draft_Paperwork__c'; }
            when 'Review Paperwork'   { return 'Review_Paperwork__c'; }
            when 'Send Notifications' { return 'Send_Notifications__c'; }
            when 'CSA'                { return 'CSA__c'; }
            when 'Associate Advisor'  { return 'Associate_Advisor__c'; }
            when 'Advisor'            { return 'Primary__c'; }
            when 'Operation'          { return 'Operations__c'; }
            when else                 { return null; }
        }
    }
}