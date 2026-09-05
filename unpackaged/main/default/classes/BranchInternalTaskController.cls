public class BranchInternalTaskController {

	  @AuraEnabled
    public static List<Task> getTasks(Id recordId) {
        return [
            SELECT Id, Subject, Status, Owner.Name, Completed_Date__c, Branch_Internal_Task__C, WhatId
            FROM Task
            WHERE WhatId = :recordId
            AND Branch_Internal_task__c = true
            ORDER BY CreatedDate DESC
        ];
    }

}