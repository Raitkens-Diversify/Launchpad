public with sharing class TaskCommentController {

    @AuraEnabled
    public static List<Task_Comment__c> getComments(String recordId){
        List<Task_Comment__c> taskComments = [SELECT Id, OwnerName__c, CreatedDate, CreatedById, CommentBody__c FROM Task_Comment__c WHERE Task_Id__c =: recordId ORDER BY CreatedDate DESC];
        return taskComments;
    }

    /**
     * Adds a comment to a Task, mirroring the Lightning "Add Comment" quick
     * action (the Task_Comment flow): it creates a Task_Comment__c carrying the
     * body and the parent Task's subject. The Task_Comment trigger then mirrors
     * it to a CaseComment when the Task's parent is a Case. Built as Apex here
     * because the flow's final step is an Aura navigation action that does not
     * run in the Experience Cloud (LWR) site.
     */
    @AuraEnabled
    public static Task_Comment__c addComment(Id taskId, String body){
        if (taskId == null || String.isBlank(body)) {
            throw new AuraHandledException('A comment is required.');
        }

        List<Task> tasks = [SELECT Id, Subject FROM Task WHERE Id = :taskId LIMIT 1];
        if (tasks.isEmpty()) {
            throw new AuraHandledException('This task could not be found.');
        }

        Task_Comment__c comment = new Task_Comment__c(
            Task_ID__c = taskId,
            CommentBody__c = body,
            Task_Subject__c = tasks[0].Subject
        );
        insert comment;

        return [SELECT Id, OwnerName__c, CreatedDate, CreatedById, CommentBody__c
                FROM Task_Comment__c WHERE Id = :comment.Id];
    }
}