public with sharing class MainTrackTasksController {
    
    @AuraEnabled(cacheable = false)
    public static List<Task> getTasks(Id recordId) {
        return [
            SELECT Id, Subject, Status, Owner.Name, Completed_Date__c, Order__c, Full_Template_Order__c,
                   Task_Template_Item__r.Home_Office_Submission_Milestone__c,
                   Task_Template_Item__r.Home_Office_Approval_Milestone__c,
                   Task_Template_Item__r.Branch_Goal_Milestone__c,
                   Task_Template_Item__r.Home_Office_Goal_Milestone__c,
            	   Task_Template__r.Assigned_To__c,
                   Task_Template__r.Queue__c
            FROM Task
            WHERE WhatId = :recordId
            AND Full_Template_Order__c != null
            ORDER BY Full_Template_Order__c ASC
        ];
    }
    
}