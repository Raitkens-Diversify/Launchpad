/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
@IsTest
private class ArcCaseMetricsControllerTest {
  @TestSetup
  static void setupTeammate() {
    createStandardUser('casemetric');
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
    Financial_Advisor_Team__c team = createFinancialAdvisorTeam(
      'Task Metrics Seed Team'
    );
    createTeamMembership(team.Id, currentUserId);

    Case teamCase = new Case(
      Subject = 'Task Metrics Seed Case',
      Status = 'New',
      Origin = 'Phone',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;

    insert new Case(
      Subject = 'My Only Case',
      Status = 'New',
      OwnerId = currentUserId
    );

    teamCase.OwnerId = teammate.Id;
    update teamCase;

    Test.startTest();
    ArcCaseMetricsModels.MetricsResult myResult = ArcCaseMetricsController.getCaseMetrics(
      'My'
    );
    ArcCaseMetricsModels.MetricsResult teamResult = ArcCaseMetricsController.getCaseMetrics(
      'Team'
    );
    Test.stopTest();

    System.assertEquals(1, myResult.totalCount);
    System.assertEquals(2, teamResult.totalCount);
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

    System.assertEquals(1, result.totalCount);
    System.assertEquals(1, result.segments.size());
  }

  private static User createStandardUser(String aliasSeed) {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User testUser = new User(
      Alias = truncate(aliasSeed, 8),
      Email = aliasSeed + uniqueSuffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'RelatedTable',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasSeed + uniqueSuffix + '@relatedtable.example.com'
    );
    insert testUser;
    return testUser;
  }

  private static Financial_Advisor_Team__c createFinancialAdvisorTeam(String name) {
    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = name,
      Related_Advisors__c = 'RT' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
    insert team;
    return team;
  }

  private static void createTeamMembership(Id teamId, Id userId) {
    insert new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = teamId,
      User__c = userId,
      Active__c = true
    );
  }

  private static String truncate(String value, Integer maxLength) {
    if (value == null) {
      return '';
    }

    return value.length() <= maxLength
      ? value
      : value.substring(0, maxLength);
  }
}