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

    /**
     * The task behind each given CaseComment, for the Case page's Case Comments
     * card to link a mirrored comment back to the task it was left on. A
     * CaseComment that did not come from a task simply has no entry.
     */
    @AuraEnabled(cacheable=true)
    public static List<TaskCommentLink> getTaskLinksForCaseComments(List<Id> caseCommentIds) {
        List<TaskCommentLink> links = new List<TaskCommentLink>();
        if (caseCommentIds == null || caseCommentIds.isEmpty()) {
            return links;
        }
        Set<String> keys = new Set<String>();
        for (Id caseCommentId : caseCommentIds) {
            keys.add(String.valueOf(caseCommentId));
        }
        for (Task_Comment__c c : [
            SELECT CaseCommentId__c, Task_ID__c, Task_Subject__c
            FROM Task_Comment__c
            WHERE CaseCommentId__c IN :keys
        ]) {
            TaskCommentLink link = new TaskCommentLink();
            link.caseCommentId = c.CaseCommentId__c;
            link.taskId = c.Task_ID__c;
            link.taskSubject = c.Task_Subject__c;
            links.add(link);
        }
        return links;
    }

    public class TaskCommentLink {
        @AuraEnabled public String caseCommentId;
        @AuraEnabled public String taskId;
        @AuraEnabled public String taskSubject;
    }
}