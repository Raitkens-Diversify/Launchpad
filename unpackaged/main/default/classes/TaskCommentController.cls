public class TaskCommentController {

    @AuraEnabled
    public static List<Task_Comment__c> getComments(String recordId){
        List<Task_Comment__c> taskComments = [SELECT Id, OwnerName__c, CreatedDate, CreatedById, CommentBody__c FROM Task_Comment__c WHERE Task_Id__c =: recordId];
        return taskComments;
    }
}