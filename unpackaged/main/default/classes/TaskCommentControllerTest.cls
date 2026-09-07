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

        List<TaskCommentController.TaskCommentLink> links =
            TaskCommentController.getTaskLinksForCaseComments(new List<Id>{ caseComments[0].Id });
        Assert.areEqual(1, links.size(), 'The mirrored CaseComment links back to its task.');
        Assert.areEqual(caseComments[0].Id, links[0].caseCommentId);
        Assert.areEqual(String.valueOf(task.Id), links[0].taskId);
        Assert.areEqual('Follow up', links[0].taskSubject);

        Assert.areEqual(0, TaskCommentController.getTaskLinksForCaseComments(new List<Id>()).size(),
            'No ids, no links.');
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