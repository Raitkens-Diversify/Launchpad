/*@IsTest
public class CaseStatusSummaryControllerTest {

    @TestSetup
    static void setup() {
        // Create User for Owner
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser234@unique.com.test',
            Alias = 'tusr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        Task_Template__c ttmp = new Task_Template__c(
        );
        insert ttmp;
        Case_Template__c ctmp = new Case_Template__c(
        );
		insert ctmp;
        // Create Case Template
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType='Case' LIMIT 1];
        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            RecordTypeId = rt.Id,
            Case_Template__c = ctmp.Id,
            Total_Main_Track_Tasks__c = 5,
            Completed_Main_Track_Tasks__c = 2
        );
        insert c;

        // Create Task Template Item + Activity
        Task_Template_Item__c tti = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Branch_Goal_Milestone__c = true
        );
        insert tti;

        Task act = new Task(
            Task_Template_Item__c = tti.Id,
            Status = 'Completed'
        );
        insert act;

        // Create a Task for Case
        Task t = new Task(
            Subject = 'Review documents',
            OwnerId = u.Id,
            WhatId = c.Id,
            Branch_Pit_Stop__c = true,
            Status = 'Completed'
        );
        insert t;

        // Update Case with Task Id
        c.Current_Task_Id__c = t.Id;
        update c;
    }

    @IsTest
    static void testGetCaseStatusSummary() {
        User u = [SELECT Id FROM User LIMIT 1];
        Case c = [SELECT Id, Current_Task_Id__c FROM Case LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(c.Current_Task_Id__c, result.currentTaskId);
        System.assert(result.statusMessage.contains('Branch Pit Stop'), 'Status message should reflect pit stop');
        System.assertEquals(5, result.totalTasks);
        System.assertEquals(2, result.completedTasks);
        System.assertNotEquals(null, result.wrappedMilestones);
    }

    @IsTest
    static void testNullCaseId() {
        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary(null, null);
        Test.stopTest();

        System.assertEquals('', result.statusMessage, 'Should return blank wrapper on null input');
    }

    @IsTest
    static void testCaseStatus() {
        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary([SELECT Id FROM Case limit 1].Id, null);
        Test.stopTest();

        System.assertEquals(true, result.statusMessage.contains('Branch Pit Stop'));
    }
}*/

@IsTest
public class CaseStatusSummaryControllerTest {

    @TestSetup
    static void setup() {
        // Create User for Owner
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser234@unique.com.test',
            Alias = 'tusr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        // Isolate setup-object DML (User / PermissionSetAssignment) from the
        // non-setup DML below, otherwise the transaction hits MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }

        Task_Template__c ttmp = new Task_Template__c();
        insert ttmp;

        Case_Template__c ctmp = new Case_Template__c();
        insert ctmp;

        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType='Case' LIMIT 1];

        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            RecordTypeId = rt.Id,
            Case_Template__c = ctmp.Id,
            Total_Main_Track_Tasks__c = 5,
            Completed_Main_Track_Tasks__c = 2
        );
        insert c;

        Task_Template_Item__c tti = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Branch_Goal_Milestone__c = true,
          	Home_Office_Submission_Milestone__c = true,
            Home_Office_Approval_Milestone__c = true,
            Home_Office_Goal_Milestone__c = true
        );
        insert tti;

        Task milestoneTask = new Task(
            Task_Template_Item__c = tti.Id,
            WhatId = c.Id,
            Status = 'Completed'
        );
        insert milestoneTask;

        Task currentTask = new Task(
            Subject = 'Review documents',
            OwnerId = u.Id,
            WhatId = c.Id,
            Branch_Pit_Stop__c = true,
            Status = 'Not Started'
        );
        insert currentTask;

        c.Current_Task_Id__c = currentTask.Id;
        update c;
    }

    @IsTest
    static void testGetCaseStatusSummary_BranchUser() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap, 'Wrapper should not be null');
        System.assertEquals(5, wrap.totalTasks, 'Total tasks mismatch');
        System.assertEquals(2, wrap.completedTasks, 'Completed tasks mismatch');
        System.assertEquals('Branch Pit Stop Task', wrap.statusMessage);
        System.assertEquals('Review documents', wrap.nextAction);
        System.assertNotEquals('', wrap.formattedOwnerDetail);
        System.assertNotEquals('', wrap.timeInStage);
        System.assertEquals(true, wrap.wrappedMilestones.size() > 0);
        System.assertEquals('HO Submission', wrap.wrappedMilestones[0].label);
        System.assertEquals(true, wrap.wrappedMilestones[0].isCompleted);
    }

    @IsTest
    static void testGetCaseStatusSummary_HomeOfficeSubmission() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];
        Task_Template_Item__c tti = [SELECT Id, Home_Office_Submission_Milestone__c, Home_Office_Approval_Milestone__c, Home_Office_Goal_Milestone__c FROM Task_Template_Item__c];
        tti.Home_Office_Submission_Milestone__c = true;
        tti.Home_Office_Approval_Milestone__c = true;
        tti.Home_Office_Goal_Milestone__c = true;

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap, 'Wrapper should not be null');
        System.assertEquals(5, wrap.totalTasks, 'Total tasks mismatch');
        System.assertEquals(2, wrap.completedTasks, 'Completed tasks mismatch');
        System.assertEquals('Branch Pit Stop Task', wrap.statusMessage);
        System.assertEquals('Review documents', wrap.nextAction);
        System.assertNotEquals('', wrap.formattedOwnerDetail);
        System.assertNotEquals('', wrap.timeInStage);
        System.assertEquals(true, wrap.wrappedMilestones.size() > 0);
        System.assertEquals('HO Submission', wrap.wrappedMilestones[0].label);
        System.assertEquals(true, wrap.wrappedMilestones[0].isCompleted);
    }

    @IsTest
    static void testGetCaseStatusSummary_NullCaseId() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(null, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap);
        System.assertEquals(0, wrap.totalTasks);
        System.assertEquals('', wrap.statusMessage);
    }

    @IsTest
    static void testGetCaseStatusSummary_NoCurrentTask() {
        Case c = [SELECT Id, Current_Task_Id__c FROM Case LIMIT 1];
        c.Current_Task_Id__c = null;
        update c;

        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertEquals('No current Task set.', wrap.statusMessage);
    }

}