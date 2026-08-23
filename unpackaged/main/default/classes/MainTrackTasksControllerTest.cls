@isTest
private class MainTrackTasksControllerTest {
    
    @isTest
    static void testGetTasks() {
        // Create parent record (e.g., Account)
        Account acc = new Account(Name = 'Test Account');
        insert acc;
		
        //Create Task Template
        Task_Template__c tt = new Task_Template__c(
        );
        insert tt;
        
        //Create Task Template
        Case_Template__c ct = new Case_Template__c(
        );
        insert ct;
        
        // Create a Task Template Item
        Task_Template_Item__c tti = new Task_Template_Item__c(
			Order__c = 3,
            Home_Office_Submission_Milestone__c = true,
            Home_Office_Approval_Milestone__c = false,
            Branch_Goal_Milestone__c = false,
            Home_Office_Goal_Milestone__c = false,
            Task_Template__c = tt.Id,
            Case_Template__c = ct.Id
        );
        insert tti;

        // Create tasks
        List<Task> taskList = new List<Task>{
            new Task(
                WhatId = acc.Id,
                Subject = 'Test Task 1',
                Status = 'Not Started',
                OwnerId = UserInfo.getUserId(),
                Task_Template_Item__c = tti.Id
            ),
            new Task(
                WhatId = acc.Id,
                Subject = 'Test Task 2',
                Status = 'Completed',
                OwnerId = UserInfo.getUserId()
            )
        };
        insert taskList;

        Test.startTest();
        List<Task> result = MainTrackTasksController.getTasks(acc.Id);
        Test.stopTest();
		System.debug(result);
        System.assertEquals(1, result.size(), 'Only one Task will be fetched because another wont be getting its order populated');
        System.assertEquals('Test Task 1', result[0].Subject);
        System.assertNotEquals(null, result[0].Order__c, 'Order will get populate through task template items');
        System.assertEquals(result[0].Task_Template_Item__r.Home_Office_Submission_Milestone__c, true, 'Home Office Submission Milestone must be true');
    }
}