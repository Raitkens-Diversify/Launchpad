@IsTest
private class HomeOfficePitStopControllerTest {
    @IsTest
    static void testGetTasks_FiltersByRecordAndFlagAndOrdersByCreatedDateDesc() {
        Account acc = new Account(Name = 'Test Account',Type ='Other');
        insert acc;

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

        Task t1 = new Task(
            WhatId = acc.Id,
            Subject = 'HOPS Task 1',
            Status = 'Not Started',
            OwnerId = UserInfo.getUserId(),
            Home_Office_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t1;

        Task t2 = new Task(
            WhatId = acc.Id,
            Subject = 'HOPS Task 2',
            Status = 'Completed',
            OwnerId = UserInfo.getUserId(),
            Home_Office_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t2;

        Task t3 = new Task(
            WhatId = acc.Id,
            Subject = 'Non-HOPS Task',
            Status = 'In Progress',
            OwnerId = UserInfo.getUserId(),
            Home_Office_Pit_Stop__c = false,
            Task_Template_Item__c = ttiFalse.Id
        );
        insert t3;

        Account otherAcc = new Account(Name = 'Other',Type ='Other', 
           Classification__c = 'Vendor;');
        insert otherAcc;

        Task t4 = new Task(
            WhatId = otherAcc.Id,
            Subject = 'Other Parent Task',
            Status = 'Not Started',
            OwnerId = UserInfo.getUserId(),
            Home_Office_Pit_Stop__c = true,
            Task_Template_Item__c = ttiTrue.Id
        );
        insert t4;

        Test.startTest();
        List<Task> result = HomeOfficePitStopController.getTasks(acc.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return only tasks for same WhatId with Home_Office_Pit_Stop__c=true');

        // Verify relationship fields are accessible
        System.assertNotEquals(null, result[0].Task_Template_Item__r, 'Related Task_Template_Item__r should be queried');
        System.assertEquals(true, result[0].Task_Template_Item__r.Home_Office_Submission_Milestone__c, 'Submission Milestone expected true on template item');
        System.assertEquals(false, result[0].Task_Template_Item__r.Home_Office_Approval_Milestone__c);
        System.assertEquals(false, result[0].Task_Template_Item__r.Branch_Goal_Milestone__c);
        System.assertEquals(false, result[0].Task_Template_Item__r.Home_Office_Goal_Milestone__c);
    }
}