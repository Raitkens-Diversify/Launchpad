@IsTest
private class ArcHomeMetricsControllerTest {
  @IsTest
  static void getHomeMetricsWithNoDataReturnsAllZeros() {
    Test.startTest();
    ArcHomeMetricsModels.MetricsResult result = ArcHomeMetricsController.getHomeMetrics();
    Test.stopTest();

    System.assertEquals(0, result.casesAssignedToMe);
    System.assertEquals(0, result.tasksAssignedToMe);
    System.assertEquals(0, result.casesAssignedToMyTeams);
    System.assertEquals(0, result.tasksAssignedToMyTeams);
    System.assertEquals(0, result.casesAwaitingHomeOffice);
  }

  @IsTest
  static void getHomeMetricsCountsMineCasesAndTasks() {
    Id currentUserId = UserInfo.getUserId();

    Case awaitingHoCase = new Case(
      Subject = 'Awaiting HO Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = currentUserId
    );
    Case plainCase = new Case(
      Subject = 'Plain Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = currentUserId
    );
    insert new List<Case>{ awaitingHoCase, plainCase };

    insert new Task(
      Subject = 'Open HO Pit Stop Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUserId,
      WhatId = awaitingHoCase.Id,
      Home_Office_Pit_Stop__c = true
    );
    insert new Task(
      Subject = 'Unrelated Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUserId
    );

    Test.startTest();
    ArcHomeMetricsModels.MetricsResult result = ArcHomeMetricsController.getHomeMetrics();
    Test.stopTest();

    System.assertEquals(2, result.casesAssignedToMe);
    System.assertEquals(2, result.tasksAssignedToMe);
    System.assertEquals(1, result.casesAwaitingHomeOffice);
  }

  @IsTest
  static void getHomeMetricsCountsTeamCasesAndTasks() {
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
    ArcHomeMetricsModels.MetricsResult result = ArcHomeMetricsController.getHomeMetrics();
    Test.stopTest();

    System.assertEquals(1, result.casesAssignedToMyTeams);
    System.assertEquals(6, result.tasksAssignedToMyTeams);
  }
}