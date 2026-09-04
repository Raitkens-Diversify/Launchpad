@IsTest
private class TaskSlaTriggerHandlerTest {
    @IsTest
    static void test_AllTaskTriggerEventsForCoverage() {
        Task coverageTask = new Task(
            Subject = 'Task Trigger Coverage',
            Status = 'Not Started',
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        insert coverageTask;
        coverageTask.Status = 'In Progress';
        update coverageTask;
        delete coverageTask;
        undelete coverageTask;
        Test.stopTest();

        Task restored = [
            SELECT Id, Status
            FROM Task
            WHERE Id = :coverageTask.Id
        ];
        Assert.areEqual(
            'In Progress',
            restored.Status,
            'Task_Trigger should allow insert, update, delete, and undelete'
        );
    }

    @IsTest
    static void test_NullInputsDoNotThrow() {
        TaskSlaTriggerHandler handler = new TaskSlaTriggerHandler();
        Test.startTest();
        handler.isAfterInsert(null);
        handler.isAfterUpdate(null, null);
        Test.stopTest();
        Assert.isTrue(true, 'Null Task SLA handler inputs should be no-ops');
    }

    @IsTest
    static void test_AfterInsertStartsPitStop() {
        Account acc = new Account(Name = 'Task SLA Pit Stop Account', Classification__c = 'Unclassified');
        insert acc;
        Case caseRecord = new Case(
            Subject = 'Task SLA Pit Stop',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id
        );
        insert caseRecord;

        Task pitStopTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Branch Pit Stop',
            Status = 'Not Started',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        insert pitStopTask;
        Test.stopTest();

        Case refreshed = [
            SELECT Pitstop_Start__c, IsStopped
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNotNull(refreshed.Pitstop_Start__c, 'TaskSlaTriggerHandler insert should set Pitstop Start');
        Assert.isTrue(refreshed.IsStopped, 'TaskSlaTriggerHandler insert should stop the Case');

        delete pitStopTask;
        undelete pitStopTask;
    }

    @IsTest
    static void test_AfterUpdateCompletesPitStopAndSetsSubmissionStart() {
        Account acc = new Account(Name = 'Task SLA Update Account', Classification__c = 'Unclassified');
        insert acc;
        Case caseRecord = new Case(
            Subject = 'Task SLA Update',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id
        );
        insert caseRecord;

        Task_Template__c taskTemplate = new Task_Template__c();
        insert taskTemplate;
        Case_Template__c caseTemplate = new Case_Template__c();
        insert caseTemplate;
        Task_Template_Item__c submissionItem = new Task_Template_Item__c(
            Task_Template__c = taskTemplate.Id,
            Case_Template__c = caseTemplate.Id,
            Home_Office_Submission_Milestone__c = true
        );
        insert submissionItem;

        Task pitStopTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Branch Pit Stop',
            Status = 'Not Started',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );
        insert pitStopTask;

        Task submissionTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Submission Milestone Task',
            Status = 'Not Started',
            Task_Template_Item__c = submissionItem.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert submissionTask;

        Test.startTest();
        pitStopTask.Status = 'Completed';
        update pitStopTask;
        submissionTask.Status = 'Completed';
        update submissionTask;
        Test.stopTest();

        Case refreshed = [
            SELECT Pitstop_Start__c, IsStopped, Home_Office_Submission_Milestone_Start__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNull(refreshed.Pitstop_Start__c, 'TaskSlaTriggerHandler update should clear Pitstop Start');
        Assert.isFalse(refreshed.IsStopped, 'TaskSlaTriggerHandler update should resume the Case');
        Assert.isNotNull(
            refreshed.Home_Office_Submission_Milestone_Start__c,
            'TaskSlaTriggerHandler update should set Home Office Submission Start'
        );
    }
}