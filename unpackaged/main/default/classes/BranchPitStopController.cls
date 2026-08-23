public with sharing class BranchPitStopController {
    
    @AuraEnabled
    public static List<Task> getTasks(Id recordId) {
        return [
            SELECT Id, Subject, Status, Owner.Name, Completed_Date__c,
                   Task_Template_Item__r.Home_Office_Submission_Milestone__c,
                   Task_Template_Item__r.Home_Office_Approval_Milestone__c,
                   Task_Template_Item__r.Branch_Goal_Milestone__c,
                   Task_Template_Item__r.Home_Office_Goal_Milestone__c
            FROM Task
            WHERE WhatId = :recordId
            AND Branch_Pit_Stop__c = true
            ORDER BY CreatedDate DESC
        ];
    }
}