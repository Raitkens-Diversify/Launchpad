/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
@IsTest
private class ArcCaseMetricsControllerTest {
  @TestSetup
  static void setupTeammate() {
    ArcRelatedTableTestData.createStandardUser('casemetric');
  }

  private static User getTeammateUser() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'casemetric%@relatedtable.example.com'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  @IsTest
  static void getCaseMetricsMineReturnsOwnedOpenCases() {
    insert new List<Case>{
      new Case(
        Subject = 'Owned Case A',
        Status = 'New',
        OwnerId = UserInfo.getUserId()
      ),
      new Case(
        Subject = 'Owned Case B',
        Status = 'New',
        OwnerId = UserInfo.getUserId()
      )
    };

    Test.startTest();
    ArcCaseMetricsModels.MetricsResult result = ArcCaseMetricsController.getCaseMetrics(
      'My'
    );
    Test.stopTest();

    System.assertEquals(2, result.totalCount);
    System.assertEquals(1, result.segments.size());
    System.assertEquals('Not set', result.segments[0].label);
    System.assertEquals(2, result.segments[0].count);
  }

  @IsTest
  static void getCaseMetricsTeamReturnsAdvisorTeamCases() {
    Id currentUserId = UserInfo.getUserId();
    User teammate = getTeammateUser();
    ArcRelatedTableTestData.TaskMetricsSeedContext context = ArcRelatedTableTestData.createTaskMetricsTeamContext(
      currentUserId
    );

    insert new Case(
      Subject = 'My Only Case',
      Status = 'New',
      OwnerId = currentUserId
    );

    context.teamCase.OwnerId = teammate.Id;
    update context.teamCase;

    Test.startTest();
    ArcCaseMetricsModels.MetricsResult myResult = ArcCaseMetricsController.getCaseMetrics(
      'My'
    );
    ArcCaseMetricsModels.MetricsResult teamResult = ArcCaseMetricsController.getCaseMetrics(
      'Team'
    );
    Test.stopTest();

    System.assertEquals(1, myResult.totalCount);
    System.assertEquals(1, teamResult.totalCount);
  }

  @IsTest
  static void getCaseMetricsTeamReturnsEmptyWhenUserHasNoTeam() {
    insert new Case(
      Subject = 'Unassigned Team Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );

    Test.startTest();
    ArcCaseMetricsModels.MetricsResult result = ArcCaseMetricsController.getCaseMetrics(
      'Team'
    );
    Test.stopTest();

    System.assertEquals(0, result.totalCount);
    System.assertEquals(0, result.segments.size());
  }
}