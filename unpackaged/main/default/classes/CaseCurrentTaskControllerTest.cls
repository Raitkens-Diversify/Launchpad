@isTest
private class CaseCurrentTaskControllerTest {

    @testSetup
    static void setup() {
        // Create a Task
        Task t = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            ActivityDate = Date.today().addDays(7)
        );
        insert t;

        // Create a Case linked to that Task
        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Current_Task_Id__c = t.Id
        );
        insert c;
    }

    @isTest
    static void testGetCurrentTask() {
        Case c = [SELECT Id, Current_Task_Id__c FROM Case LIMIT 1];
        
        Test.startTest();
        Task result = CaseCurrentTaskController.getCurrentTask(c.Id);
        Test.stopTest();

        Assert.areNotEqual(null, result, 'Task should be returned');
        Assert.areEqual(c.Current_Task_Id__c, result.Id, 'Should return the linked task');
    }

    @isTest
    static void testGetCurrentTaskNull() {
        Case c = new Case(Subject = 'No Task Case');
        insert c;

        Test.startTest();
        Task result = CaseCurrentTaskController.getCurrentTask(c.Id);
        Test.stopTest();

        Assert.areEqual(null, result, 'Should return null if no task ID is present on case');
    }

    @isTest
    static void testMarkComplete() {
        Task t = [SELECT Id, Status FROM Task LIMIT 1];
        
        Test.startTest();
        CaseCurrentTaskController.markComplete(t.Id);
        Test.stopTest();

        Task updatedTask = [SELECT Status FROM Task WHERE Id = :t.Id];
        Assert.areEqual('Completed', updatedTask.Status);
    }

    @isTest
    static void testUpdateTask() {
        Task t = [SELECT Id FROM Task LIMIT 1];
        Id currentUserId = UserInfo.getUserId();
        Date newDate = Date.today().addDays(10);

        Test.startTest();
        CaseCurrentTaskController.updateTask(t.Id, currentUserId, newDate);
        Test.stopTest();

        Task updatedTask = [SELECT OwnerId, ActivityDate FROM Task WHERE Id = :t.Id];
        Assert.areEqual(currentUserId, updatedTask.OwnerId);
        Assert.areEqual(newDate, updatedTask.ActivityDate);
    }

    @isTest
    static void testMarkCompletePitStopReassignsByFaTeamPermission() {
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'Test FAT');
        insert fat;

        insert new Financial_Advisor_Team_Member__c(
            Financial_Advisor_Team__c = fat.Id,
            User__c = UserInfo.getUserId(),
            Primary__c = true
        );

        Task_Template__c tmpl = new Task_Template__c(
            Assigned_To__c = 'FA Team Permission',
            FA_Team_Permission__c = 'Advisor'
        );
        insert tmpl;

        Case c = new Case(Subject = 'Pit Stop Case', Financial_Advisor_Team__c = fat.Id);
        insert c;

        Task blocked = new Task(
            Subject = 'Blocked Main Track Task',
            Status = 'Blocked',
            WhatId = c.Id,
            Full_Template_Order__c = 2,
            Task_Template__c = tmpl.Id
        );
        Task pitStop = new Task(
            Subject = 'Branch Pit Stop',
            Status = 'Not Started',
            WhatId = c.Id,
            Branch_Pit_Stop__c = true
        );
        insert new List<Task>{ blocked, pitStop };

        Test.startTest();
        CaseCurrentTaskController.markComplete(pitStop.Id);
        Test.stopTest();

        Task updated = [SELECT Status, OwnerId FROM Task WHERE Id = :blocked.Id];
        Assert.areEqual('Not Started', updated.Status, 'Blocked task should be reactivated');
        Assert.areEqual(UserInfo.getUserId(), updated.OwnerId, 'Should reassign to the FAT primary member');

        Case updatedCase = [SELECT Current_Task_Id__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual(blocked.Id, updatedCase.Current_Task_Id__c, 'Case current task should point to the reactivated task');
    }

    @isTest
    static void testMarkCompletePitStopReassignsByQueue() {
        Map<String, Id> queues = createQueues(new List<String>{ 'Operations' });

        Task_Template__c tmpl = new Task_Template__c(
            Assigned_To__c = 'Queue',
            Queue__c = 'Back Office Operations'
        );
        insert tmpl;

        Case c = new Case(Subject = 'Pit Stop Queue Case');
        insert c;

        Task blocked = new Task(
            Subject = 'Blocked Queue Task',
            Status = 'Blocked',
            WhatId = c.Id,
            Full_Template_Order__c = 3,
            Task_Template__c = tmpl.Id
        );
        Task pitStop = new Task(
            Subject = 'Home Office Pit Stop',
            Status = 'Not Started',
            WhatId = c.Id,
            Home_Office_Pit_Stop__c = true
        );
        insert new List<Task>{ blocked, pitStop };

        Test.startTest();
        CaseCurrentTaskController.markComplete(pitStop.Id);
        Test.stopTest();

        Task updated = [SELECT Status, OwnerId FROM Task WHERE Id = :blocked.Id];
        Assert.areEqual('Not Started', updated.Status, 'Blocked task should be reactivated');
        Assert.areEqual(queues.get('Operations'), updated.OwnerId, 'Should reassign to the Operations queue');
    }

    @isTest
    static void testMarkCompletePitStopNoBlockedTask() {
        Case c = new Case(Subject = 'Pit Stop No Blocked');
        insert c;

        Task pitStop = new Task(
            Subject = 'Branch Pit Stop',
            Status = 'Not Started',
            WhatId = c.Id,
            Branch_Pit_Stop__c = true
        );
        insert pitStop;

        Test.startTest();
        CaseCurrentTaskController.markComplete(pitStop.Id);
        Test.stopTest();

        Task updated = [SELECT Status FROM Task WHERE Id = :pitStop.Id];
        Assert.areEqual('Completed', updated.Status, 'Pit stop task should still complete with no next task');
    }

    private static Map<String, Id> createQueues(List<String> names) {
        Map<String, Id> result = new Map<String, Id>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Group> groups = new List<Group>();
            for (String name : names) {
                groups.add(new Group(Name = name, Type = 'Queue'));
            }
            insert groups;

            List<QueueSObject> queueSobjects = new List<QueueSObject>();
            for (Group g : groups) {
                queueSobjects.add(new QueueSObject(QueueId = g.Id, SObjectType = 'Task'));
            }
            insert queueSobjects;

            for (Group g : groups) {
                result.put(g.Name, g.Id);
            }
        }
        return result;
    }

    @isTest
    static void testSearchUsersAndQueues() {
        // Search for the current user's name
        String searchKey = UserInfo.getName().substring(0, 3);

        Test.startTest();
        List<Map<String, String>> results = CaseCurrentTaskController.searchUsers(searchKey);
        List<Map<String, String>> emptyResults = CaseCurrentTaskController.searchUsers('');
        Test.stopTest();

        Assert.isTrue(results.size() > 0, 'Should return at least the current user');
        Assert.areEqual(0, emptyResults.size(), 'Empty search key should return empty list');
        
        // Verify structure
        Map<String, String> firstResult = results[0];
        Assert.isTrue(firstResult.containsKey('label'));
        Assert.isTrue(firstResult.containsKey('value'));
        Assert.isTrue(firstResult.containsKey('icon'));
    }
}