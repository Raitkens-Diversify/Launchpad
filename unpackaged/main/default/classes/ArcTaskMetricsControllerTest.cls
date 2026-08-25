/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcTaskMetricsControllerTest {
  @TestSetup
  static void setupTeammate() {
    ArcRelatedTableTestData.createStandardUser('taskmetric');
  }

  private static User getTeammateUser() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'taskmetric%@relatedtable.example.com'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  @IsTest
  static void getTaskMetricsMineReturnsCategoryCounts() {
    Task mainTrackTask = new Task(
      Subject = 'Main Track Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      Branch_Pit_Stop__c = false,
      Home_Office_Pit_Stop__c = false
    );
    Task hoPitStopTask = new Task(
      Subject = 'HO Pit Stop Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      Home_Office_Pit_Stop__c = true
    );
    Task branchPitStopTask = new Task(
      Subject = 'Branch Pit Stop Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      Branch_Pit_Stop__c = true
    );
    insert new List<Task>{ mainTrackTask, hoPitStopTask, branchPitStopTask };

    Test.startTest();
    ArcTaskMetricsModels.MetricsResult result = ArcTaskMetricsController.getTaskMetrics(
      'My'
    );
    Test.stopTest();

    System.assertEquals(1, result.mainTrackCount);
    System.assertEquals(1, result.hoPitStopCount);
    System.assertEquals(1, result.branchPitStopCount);
  }

  @IsTest
  static void getTaskMetricsDualFilterReturnsAllCategoriesForBothScopes() {
    Id currentUserId = UserInfo.getUserId();
    ArcRelatedTableTestData.TaskMetricsSeedContext context = ArcRelatedTableTestData.createTaskMetricsTeamContext(
      currentUserId
    );
    ArcRelatedTableTestData.createDualFilterTasksForAllMetricTypes(
      currentUserId,
      context.teamCase.Id,
      context.teamAccount.Id
    );

    Test.startTest();
    ArcTaskMetricsModels.MetricsResult myResult = ArcTaskMetricsController.getTaskMetrics(
      'My'
    );
    ArcTaskMetricsModels.MetricsResult teamResult = ArcTaskMetricsController.getTaskMetrics(
      'Team'
    );
    Test.stopTest();

    System.assertEquals(2, myResult.mainTrackCount);
    System.assertEquals(2, myResult.hoPitStopCount);
    System.assertEquals(2, myResult.branchPitStopCount);
    System.assertEquals(2, teamResult.mainTrackCount);
    System.assertEquals(2, teamResult.hoPitStopCount);
    System.assertEquals(2, teamResult.branchPitStopCount);
  }

  @IsTest
  static void getTaskMetricsScopesExcludeSingleFilterTasks() {
    Id currentUserId = UserInfo.getUserId();
    User teammate = getTeammateUser();
    ArcRelatedTableTestData.TaskMetricsSeedContext context = ArcRelatedTableTestData.createTaskMetricsTeamContext(
      currentUserId
    );

    insert new Task(
      Subject = 'My Only Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUserId,
      Branch_Pit_Stop__c = true
    );

    insert new Task(
      Subject = 'Team Only Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = teammate.Id,
      WhatId = context.teamCase.Id,
      Home_Office_Pit_Stop__c = true
    );

    Test.startTest();
    ArcTaskMetricsModels.MetricsResult myResult = ArcTaskMetricsController.getTaskMetrics(
      'My'
    );
    ArcTaskMetricsModels.MetricsResult teamResult = ArcTaskMetricsController.getTaskMetrics(
      'Team'
    );
    Test.stopTest();

    System.assertEquals(1, myResult.branchPitStopCount);
    System.assertEquals(0, myResult.hoPitStopCount);
    System.assertEquals(1, teamResult.hoPitStopCount);
    System.assertEquals(0, teamResult.branchPitStopCount);
  }
}