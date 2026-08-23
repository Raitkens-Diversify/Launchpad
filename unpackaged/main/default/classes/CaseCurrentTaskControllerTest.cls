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