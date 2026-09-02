@isTest
private class TaskCommentControllerTest {

    @isTest
    static void addCommentCreatesTaskAndCaseComment() {
        Case parentCase = new Case(Origin = 'Web', Status = 'New');
        insert parentCase;
        Task task = new Task(WhatId = parentCase.Id, Subject = 'Follow up', Status = 'New');
        insert task;

        Test.startTest();
        Task_Comment__c created = TaskCommentController.addComment(task.Id, 'Called the client back.');
        Test.stopTest();

        Assert.isNotNull(created, 'addComment should return the new comment.');
        Assert.areEqual('Called the client back.', created.CommentBody__c);

        List<Task_Comment__c> comments = TaskCommentController.getComments(task.Id);
        Assert.areEqual(1, comments.size(), 'The comment should be readable back by task.');

        List<CaseComment> caseComments = [SELECT Id FROM CaseComment WHERE ParentId = :parentCase.Id];
        Assert.areEqual(1, caseComments.size(), 'A Case parent gets a mirrored CaseComment.');
    }

    @isTest
    static void addCommentRejectsBlankBody() {
        Task task = new Task(Subject = 'No parent', Status = 'New');
        insert task;

        Test.startTest();
        Boolean threw = false;
        try {
            TaskCommentController.addComment(task.Id, '   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A blank comment body should be rejected.');
    }
}