/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Shared test helpers for arcRelatedTable Apex tests.
 */
@IsTest
public class ArcRelatedTableTestData {
  public static User createStandardUser(String aliasSeed) {
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

  public static Financial_Advisor_Team__c createFinancialAdvisorTeam(String name) {
    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = name,
      Related_Advisors__c = 'RT' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
    insert team;
    return team;
  }

  public static Financial_Advisor_Team_Member__c createTeamMembership(
    Id teamId,
    Id userId
  ) {
    Financial_Advisor_Team_Member__c membership = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = teamId,
      User__c = userId,
      Active__c = true
    );
    insert membership;
    return membership;
  }

  public class TaskMetricsSeedContext {
    public Financial_Advisor_Team__c team { get; set; }
    public Case teamCase { get; set; }
    public Account teamAccount { get; set; }
  }

  public static TaskMetricsSeedContext createTaskMetricsTeamContext(Id userId) {
    Financial_Advisor_Team__c team = createFinancialAdvisorTeam('Task Metrics Seed Team');
    createTeamMembership(team.Id, userId);

    Case teamCase = new Case(
      Subject = 'Task Metrics Seed Case',
      Status = 'New',
      Origin = 'Phone',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;

    // Type satisfies Type_OR_Classification_Required (activated 2026-09-02),
    // which rejects an Account of several record types -- including whichever
    // one is the running user's default -- that has neither a Type nor a
    // Classification.
    Account teamAccount = new Account(
      Name = 'Task Metrics Seed Household',
      Type = 'Prospect',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamAccount;

    TaskMetricsSeedContext context = new TaskMetricsSeedContext();
    context.team = team;
    context.teamCase = teamCase;
    context.teamAccount = teamAccount;
    return context;
  }

  public static List<Task> createDualFilterTasksForAllMetricTypes(
    Id ownerId,
    Id caseWhatId,
    Id accountWhatId
  ) {
    List<Task> tasks = new List<Task>{
      buildTask(
        'Case Main Track',
        ownerId,
        caseWhatId,
        false,
        false
      ),
      buildTask(
        'Case HO Pit Stop',
        ownerId,
        caseWhatId,
        true,
        false
      ),
      buildTask(
        'Case Branch Pit Stop',
        ownerId,
        caseWhatId,
        false,
        true
      ),
      buildTask(
        'Account Main Track',
        ownerId,
        accountWhatId,
        false,
        false
      ),
      buildTask(
        'Account HO Pit Stop',
        ownerId,
        accountWhatId,
        true,
        false
      ),
      buildTask(
        'Account Branch Pit Stop',
        ownerId,
        accountWhatId,
        false,
        true
      )
    };
    insert tasks;
    return tasks;
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