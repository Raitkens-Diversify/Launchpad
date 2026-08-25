/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcTaskMetricsUiTestSeederTest {
  @IsTest
  static void seedForCurrentUserCreatesDualFilterTasksForAllMetricTypes() {
    Test.startTest();
    ArcTaskMetricsUiTestSeeder.SeedResult result = ArcTaskMetricsUiTestSeeder.seedForCurrentUser(
      true
    );
    Test.stopTest();

    System.assertEquals(false, result.skippedExisting);
    System.assertEquals(6, result.tasksCreated);
    System.assertNotEquals(null, result.teamId);
    System.assertNotEquals(null, result.caseId);
    System.assertNotEquals(null, result.accountId);

    ArcTaskMetricsModels.MetricsResult myResult = ArcTaskMetricsController.getTaskMetrics(
      'My'
    );
    ArcTaskMetricsModels.MetricsResult teamResult = ArcTaskMetricsController.getTaskMetrics(
      'Team'
    );

    System.assertEquals(2, myResult.mainTrackCount);
    System.assertEquals(2, myResult.hoPitStopCount);
    System.assertEquals(2, myResult.branchPitStopCount);
    System.assertEquals(2, teamResult.mainTrackCount);
    System.assertEquals(2, teamResult.hoPitStopCount);
    System.assertEquals(2, teamResult.branchPitStopCount);
  }

  @IsTest
  static void seedForCurrentUserSkipsWhenSeedDataExists() {
    ArcTaskMetricsUiTestSeeder.seedForCurrentUser(true);

    Test.startTest();
    ArcTaskMetricsUiTestSeeder.SeedResult result = ArcTaskMetricsUiTestSeeder.seedForCurrentUser(
      false
    );
    Test.stopTest();

    System.assertEquals(true, result.skippedExisting);
    System.assertEquals(0, result.tasksCreated);
  }

  @IsTest
  static void seedOnOwnedCasesCreatesTasksOnOwnedCases() {
    Case ownedCase = new Case(
      Subject = 'Owned Case Seed',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = UserInfo.getUserId()
    );
    insert ownedCase;

    Test.startTest();
    ArcTaskMetricsUiTestSeeder.OwnedCaseSeedResult result = ArcTaskMetricsUiTestSeeder.seedOnOwnedCases(
      3,
      true
    );
    Test.stopTest();

    System.assertEquals(9, result.tasksCreated);
    System.assertEquals(1, result.casesUsed);
    System.assertEquals(true, result.caseIds.contains(ownedCase.Id));

    ArcTaskMetricsModels.MetricsResult myResult = ArcTaskMetricsController.getTaskMetrics(
      'My'
    );

    System.assertEquals(3, myResult.mainTrackCount);
    System.assertEquals(3, myResult.hoPitStopCount);
    System.assertEquals(3, myResult.branchPitStopCount);
  }
}