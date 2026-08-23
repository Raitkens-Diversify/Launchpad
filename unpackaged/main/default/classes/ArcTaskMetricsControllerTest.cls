/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcTaskMetricsControllerTest {
  @TestSetup
  static void setupTeammate() {
    createStandardUser('taskmetric');
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

    Account teamAccount = new Account(
      Name = 'Task Metrics Seed Household',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamAccount;

    insertDualFilterTasksForAllMetricTypes(
      currentUserId,
      teamCase.Id,
      teamAccount.Id
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
      WhatId = teamCase.Id,
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
    System.assertEquals(1, teamResult.branchPitStopCount);
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

  private static void insertDualFilterTasksForAllMetricTypes(
    Id ownerId,
    Id caseWhatId,
    Id accountWhatId
  ) {
    insert new List<Task>{
      buildTask('Case Main Track', ownerId, caseWhatId, false, false),
      buildTask('Case HO Pit Stop', ownerId, caseWhatId, true, false),
      buildTask('Case Branch Pit Stop', ownerId, caseWhatId, false, true),
      buildTask('Account Main Track', ownerId, accountWhatId, false, false),
      buildTask('Account HO Pit Stop', ownerId, accountWhatId, true, false),
      buildTask('Account Branch Pit Stop', ownerId, accountWhatId, false, true)
    };
  }

  private static Task buildTask(
    String subject,
    Id ownerId,
    Id whatId,
    Boolean isHoPitStop,
    Boolean isBranchPitStop
  ) {
    return new Task(
      Subject = subject,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = ownerId,
      WhatId = whatId,
      Home_Office_Pit_Stop__c = isHoPitStop,
      Branch_Pit_Stop__c = isBranchPitStop
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