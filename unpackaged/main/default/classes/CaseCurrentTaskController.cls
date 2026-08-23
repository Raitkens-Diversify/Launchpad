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
        system.System.debug(taskId);
        update new Task(Id = taskId, Status = 'Completed');
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