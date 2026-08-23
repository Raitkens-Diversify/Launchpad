public class Task_Comment_TriggerHandler {
    public void isBeforeInsert(List<Task_Comment__c> newList){
        createCaseComment(newList);
    }
    
    public void isBeforeUpdate(Map<Id,Task_Comment__c> newMap, Map<Id,Task_Comment__c> oldMap){
        updateCaseComment(newMap, oldMap);
    }
    
    public void isBeforeDelete(Map<Id,Task_Comment__c> oldMap){
        
    }
    
    public void isAfterInsert(Map<Id,Task_Comment__c> newMap){
        
    }
    
    public void isAfterUpdate(Map<Id,Task_Comment__c> newMap, Map<Id,Task_Comment__c> oldMap){
        
    }
    
    public void isAfterDelete(Map<Id,Task_Comment__c> oldMap){
        
    }
    
    public void isAfterUndelete(Map<Id,Task_Comment__c> newMap){
        
    }
    
    public void createCaseComment(List<Task_Comment__c> newList){
        for(Task_Comment__c t : newList){
            Task task = [SELECT Id, WhatId,what.Type, Subject FROM Task WHERE Id =: t.Task_ID__c LIMIT 1];
            if(task.what != null && task.what.Type == 'Case'){
                CaseComment c = new CaseComment();
                String commentBody = 'Task Comment from ' + task.Subject + ': ' + t.CommentBody__c;
                c.CommentBody = commentBody;
                c.ParentId = task.WhatId;
                insert c;
                t.CaseCommentId__c = c.Id;
            }
        }
    }
    
    public void updateCaseComment(Map<Id,Task_Comment__c> newMap, Map<Id,Task_Comment__c> oldMap){
        Set<Id> caseCommentIds = new Set<Id>();
        Map<Id,Task_Comment__c> changedTaskComments = new Map<Id,Task_Comment__c>();
        List<CaseComment> commentsToUpdate = new List<CaseComment>();
        for(Task_Comment__c newTaskComment : newMap.values()){
            Task_Comment__c oldTaskComment = oldMap.get(newTaskComment.Id);
            if(newTaskComment.CommentBody__c != oldTaskComment.CommentBody__c){
                caseCommentIds.add(newTaskComment.CaseCommentId__c);
                changedTaskComments.put(newTaskComment.Id, newTaskComment);
            }
        }
        if(!caseCommentIds.isEmpty()){
            Map<Id,CaseComment> caseComments = new Map<Id,CaseComment>([SELECT Id, CommentBody FROM CaseComment WHERE Id in: caseCommentIds]);
            for(Task_Comment__c t: changedTaskComments.values()){
                CaseComment c = caseComments.get(t.CaseCommentId__c);
                c.CommentBody = t.CommentBody__c;
                commentsToUpdate.add(c);
            }
        }
        if(!commentsToUpdate.isEmpty()){
            update commentsToUpdate;
        }
    }
}