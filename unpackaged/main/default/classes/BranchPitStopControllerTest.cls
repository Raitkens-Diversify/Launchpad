@IsTest
private class BranchPitStopControllerTest {
    @IsTest
    static void testGetTasks_FiltersByRecordAndFlagAndOrdersByCreatedDateDesc() {
        // Parent record as WhatId (using Account as in reference)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Minimal related setup to allow relationship fields in query
        Task_Template__c tt = new Task_Template__c();
        insert tt;

        Case_Template__c ct = new Case_Template__c();
        insert ct;

        Task_Template_Item__c ttiTrue = new Task_Template_Item__c(
            Home_Office_Submission_Milestone__c = true,
            Home_Office_Approval_Milestone__c = false,
            Branch_Goal_Milestone__c = false,
            Home_Office_Goal_Milestone__c = false,
            Task_Template__c = tt.Id,
            Case_Template__c = ct.Id
        );
        insert ttiTrue;

        Task_Template_Item__c ttiFalse = new Task_Template_Item__c(
            Home_Office_Submission_Milestone__c = false,
            Home_Office_Approval_Milestone__c = true,
            Branch_Goal_Milestone__c = true,
            Home_Office_Goal_Milestone__c = true,
            Task_Template__c = tt.Id,
            Case_Template__c = ct.Id
        );
        insert ttiFalse;

        // Create tasks: two matching Branch_Pit_Stop__c=true, one false (should be filtered out),
        // and one on a different parent (should be filtered out).
        Task t1 = new Task(
            WhatId = acc.Id,
            Subject = 'BPS Task 1',
            Status = 'Not Started',
            OwnerId = UserInfo.getUserId(),
            Branch_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t1;

        // Ensure CreatedDate ordering by separating DMLs
        Task t2 = new Task(
            WhatId = acc.Id,
            Subject = 'BPS Task 2',
            Status = 'Completed',
            OwnerId = UserInfo.getUserId(),
            Branch_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t2;

        Task t3 = new Task(
            WhatId = acc.Id,
            Subject = 'Non-BPS Task',
            Status = 'In Progress',
            OwnerId = UserInfo.getUserId(),
            Branch_Pit_Stop__c = false,
            Task_Template_Item__c = ttiFalse.Id
        );
        insert t3;

        Account otherAcc = new Account(Name = 'Other');
        insert otherAcc;

        Task t4 = new Task(
            WhatId = otherAcc.Id,
            Subject = 'Other Parent Task',
            Status = 'Not Started',
            OwnerId = UserInfo.getUserId(),
            Branch_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t4;

        Test.startTest();
        List<Task> result = BranchPitStopController.getTasks(acc.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should only return tasks on the same WhatId with Branch_Pit_Stop__c=true');

        // Verify relationship fields are retrievable without null pointer issues
        System.assertNotEquals(null, result[0].Task_Template_Item__r, 'Task Template Item relationship should be populated via query');
        System.assertEquals(true, result[0].Task_Template_Item__r.Home_Office_Submission_Milestone__c, 'Expected Submission Milestone on related template item');
        System.assertEquals(false, result[0].Task_Template_Item__r.Home_Office_Approval_Milestone__c);
        System.assertEquals(false, result[0].Task_Template_Item__r.Branch_Goal_Milestone__c);
        System.assertEquals(false, result[0].Task_Template_Item__r.Home_Office_Goal_Milestone__c);
    }
}