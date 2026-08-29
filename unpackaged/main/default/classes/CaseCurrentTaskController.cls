public with sharing class CaseCurrentTaskController {

    @AuraEnabled(cacheable=true)
    public static Task getCurrentTask(Id caseId) {
        Case c = [
            SELECT Current_Task_Id__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (c.Current_Task_Id__c == null) return null;

        return [
            SELECT Id, Subject, Description, OwnerId, Owner.Name,
                   Status, ActivityDate
            FROM Task
            WHERE Id = :c.Current_Task_Id__c
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static void markComplete(Id taskId) {
        Task completedTask = [
            SELECT Id, Status, WhatId, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];

        completedTask.Status = 'Completed';
        update completedTask;

        reactivateNextTaskAfterPitStop(completedTask);
    }

    /**
     * When a Branch or Home Office Pit Stop task is completed, re-activate the
     * next task on the same Case: the first incomplete task (by
     * Full_Template_Order__c) that the Pit Stop had left in 'Blocked' status is
     * set back to 'Not Started' and reassigned from its Task Template.
     */
    private static void reactivateNextTaskAfterPitStop(Task completedTask) {
        Boolean isPitStop =
            completedTask.Branch_Pit_Stop__c == true
            || completedTask.Home_Office_Pit_Stop__c == true;

        Boolean isCaseWhatId =
            completedTask.WhatId != null && String.valueOf(completedTask.WhatId).startsWith('500');

        if (!isPitStop || !isCaseWhatId) {
            return;
        }

        List<Task> nextTasks = [
            SELECT Id, WhatId, Full_Template_Order__c,
                   Task_Template__r.Assigned_To__c,
                   Task_Template__r.Queue__c,
                   Task_Template__r.FA_Team_Permission__c
            FROM Task
            WHERE WhatId = :completedTask.WhatId
            AND IsClosed = false
            AND Status = 'Blocked'
            ORDER BY Full_Template_Order__c ASC NULLS LAST
            LIMIT 1
        ];

        if (nextTasks.isEmpty()) {
            return;
        }

        Task nextTask = nextTasks[0];
        nextTask.Status = 'Not Started';
        TaskTemplateAssignmentService.assignOwners(nextTasks);
        update nextTask;

        update new Case(
            Id = completedTask.WhatId,
            Current_Task_Id__c = nextTask.Id
        );
    }

    @AuraEnabled
    public static void updateTask(Id taskId, Id ownerId, Date dueDate) {
        update new Task(
            Id = taskId,
            OwnerId = ownerId,
            ActivityDate = dueDate
        );
    }

    @AuraEnabled
    public static List<Map<String, String>> searchUsers(String searchKey) {
        if (String.isBlank(searchKey)) {
            return new List<Map<String, String>>();
        }
        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            AND Name LIKE :('%' + searchKey + '%')
            ORDER BY Name
            LIMIT 10
        ];
        List<Group> queues = [
            SELECT Id, Name 
            FROM Group 
            WHERE Type = 'Queue'
            AND Name LIKE :('%' + searchKey + '%')
            ORDER BY Name
            LIMIT 10
        ];
        List<Map<String, String>> results = new List<Map<String, String>>();
        for (User u : users) {
            results.add(new Map<String, String>{
                'label' => u.Name,
                'value' => u.Id,
                'icon' => 'standard:user'
            });
        }
        for (Group q : queues) {
            results.add(new Map<String, String>{
                'label' => q.Name,
                'value' => q.Id,
                'icon' => 'standard:queue'
            });
        }
        return results;
    }
    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserMemberOfQueue(Id ownerId) {

        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Id = :ownerId
            AND Type = 'Queue'
            LIMIT 1
        ];

        if(queues.isEmpty()) {
            return false;
        }

        Integer memberCount = [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :ownerId
            AND UserOrGroupId = :UserInfo.getUserId()
        ];

        return memberCount > 0;
    }
}