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

  /**
   * The regression that forced the move off MilestoneStatus. With milestones
   * present the donut has to split by them and only cases that have not
   * reached one may fall into 'Not set'; grouping by the standard
   * MilestoneStatus put every case in 'Not set', because this org creates no
   * CaseMilestone records for that field to derive from.
   *
   * Counts are deliberately lopsided — 'Not set' is the largest bucket — so
   * the assertion also pins the ordering. Sorted by count alone 'Not set'
   * would lead and the stages would come out 3-2-1-1; sorted by milestone
   * progression they read as the pipeline, with 'Not set' last.
   */
  @IsTest
  static void getCaseMetricsGroupsByMilestoneField() {
    Id currentUserId = UserInfo.getUserId();
    List<Case> seeds = new List<Case>();
    Map<String, Integer> seedPlan = new Map<String, Integer>{
      'HO Submission' => 2,
      'HO Approval' => 1,
      'Branch Goal' => 3,
      'HO Goal' => 1
    };

    for (String milestone : seedPlan.keySet()) {
      for (Integer i = 0; i < seedPlan.get(milestone); i++) {
        seeds.add(
          new Case(
            Subject = milestone + ' ' + i,
            Status = 'New',
            OwnerId = currentUserId,
            Milestone__c = milestone
          )
        );
      }
    }
    // Cases that have not completed a milestone task yet -> genuinely 'Not set'.
    for (Integer i = 0; i < 5; i++) {
      seeds.add(
        new Case(
          Subject = 'No milestone ' + i,
          Status = 'New',
          OwnerId = currentUserId
        )
      );
    }
    insert seeds;

    Test.startTest();
    ArcCaseMetricsModels.MetricsResult result = ArcCaseMetricsController.getCaseMetrics(
      'My'
    );
    Test.stopTest();

    System.assertEquals(12, result.totalCount, 'every open owned case counts');
    System.assertEquals(
      5,
      result.segments.size(),
      'four milestones plus Not set'
    );

    List<String> actualOrder = new List<String>();
    Map<String, Integer> countByLabel = new Map<String, Integer>();
    Map<String, String> keyByLabel = new Map<String, String>();
    for (ArcCaseMetricsModels.MilestoneSegment segment : result.segments) {
      actualOrder.add(segment.label);
      countByLabel.put(segment.label, segment.count);
      keyByLabel.put(segment.label, segment.key);
    }

    System.assertEquals(
      new List<String>{
        'HO Submission',
        'HO Approval',
        'Branch Goal',
        'HO Goal',
        'Not set'
      },
      actualOrder,
      'segments follow milestone progression, Not set last'
    );

    System.assertEquals(2, countByLabel.get('HO Submission'));
    System.assertEquals(1, countByLabel.get('HO Approval'));
    System.assertEquals(3, countByLabel.get('Branch Goal'));
    System.assertEquals(1, countByLabel.get('HO Goal'));
    System.assertEquals(5, countByLabel.get('Not set'));

    // Keys are what arcCaseMetrics.MILESTONE_COLORS is keyed on.
    System.assertEquals('ho-submission', keyByLabel.get('HO Submission'));
    System.assertEquals('ho-approval', keyByLabel.get('HO Approval'));
    System.assertEquals('branch-goal', keyByLabel.get('Branch Goal'));
    System.assertEquals('ho-goal', keyByLabel.get('HO Goal'));
    System.assertEquals('not-set', keyByLabel.get('Not set'));
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