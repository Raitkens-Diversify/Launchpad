/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Seeds nexsTaskMetrics UI data: main track, HO pit stop, and branch pit stop
 * tasks that satisfy both My (assigned to running user) and My Team
 * (related Case/Account on a team the user belongs to).
 */
public with sharing class NexsTaskMetricsUiTestSeeder {
  public static final String SEED_MARKER = 'NTM|';
  public static final String OWNED_CASE_SEED_MARKER = 'NTM|OC|';
  public static final Integer DEFAULT_TASKS_PER_TYPE = 3;

  public class SeedResult {
    @AuraEnabled
    public Id teamId;
    @AuraEnabled
    public Id caseId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Integer tasksCreated = 0;
    @AuraEnabled
    public Boolean skippedExisting = false;
  }

  public class OwnedCaseSeedResult {
    @AuraEnabled
    public Integer casesUsed = 0;
    @AuraEnabled
    public Integer tasksCreated = 0;
    @AuraEnabled
    public Integer tasksPerType = 0;
    @AuraEnabled
    public List<Id> caseIds = new List<Id>();
    @AuraEnabled
    public String message;
  }

  public static OwnedCaseSeedResult seedOnOwnedCases() {
    return seedOnOwnedCases(DEFAULT_TASKS_PER_TYPE, false);
  }

  public static OwnedCaseSeedResult seedOnOwnedCases(
    Integer tasksPerType,
    Boolean replaceExisting
  ) {
    Id currentUserId = UserInfo.getUserId();
    OwnedCaseSeedResult result = new OwnedCaseSeedResult();
    Integer resolvedTasksPerType = tasksPerType == null || tasksPerType < 1
      ? DEFAULT_TASKS_PER_TYPE
      : tasksPerType;
    result.tasksPerType = resolvedTasksPerType;

    List<Case> ownedCases = [
      SELECT Id, Subject, CaseNumber
      FROM Case
      WHERE OwnerId = :currentUserId
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT 50
    ];

    if (ownedCases.isEmpty()) {
      result.message = 'No owned Cases found for the running user.';
      return result;
    }

    if (replaceExisting) {
      clearOwnedCaseSeedData(currentUserId);
    }

    Set<Id> usedCaseIds = new Set<Id>();
    List<Task> tasks = new List<Task>();
    Integer caseIndex = 0;

    tasks.addAll(
      buildOwnedCaseTasksForType(
        'Main Track',
        currentUserId,
        ownedCases,
        caseIndex,
        usedCaseIds,
        resolvedTasksPerType,
        false,
        false
      )
    );
    caseIndex = tasks.size();

    tasks.addAll(
      buildOwnedCaseTasksForType(
        'HO Pit Stop',
        currentUserId,
        ownedCases,
        caseIndex,
        usedCaseIds,
        resolvedTasksPerType,
        true,
        false
      )
    );
    caseIndex = tasks.size();

    tasks.addAll(
      buildOwnedCaseTasksForType(
        'Branch Pit Stop',
        currentUserId,
        ownedCases,
        caseIndex,
        usedCaseIds,
        resolvedTasksPerType,
        false,
        true
      )
    );

    insert tasks;

    result.casesUsed = usedCaseIds.size();
    result.caseIds = new List<Id>(usedCaseIds);
    result.tasksCreated = tasks.size();
    result.message = String.format(
      'Created {0} open tasks ({1} per type) on {2} owned Case(s).',
      new List<Object>{
        result.tasksCreated,
        resolvedTasksPerType,
        result.casesUsed
      }
    );
    return result;
  }

  public static void logOwnedCaseSeedResult(OwnedCaseSeedResult result) {
    System.debug('NexsTaskMetrics owned-case seed result: ' + JSON.serialize(result));
  }

  public static SeedResult seedForCurrentUser() {
    return seedForCurrentUser(false);
  }

  public static SeedResult seedForCurrentUser(Boolean replaceExisting) {
    Id currentUserId = UserInfo.getUserId();
    SeedResult result = new SeedResult();

    if (!replaceExisting && hasExistingSeedData(currentUserId)) {
      result.skippedExisting = true;
      return result;
    }

    if (replaceExisting) {
      clearExistingSeedData(currentUserId);
    }

    Financial_Advisor_Team__c team = resolveTeamForUser(currentUserId);
    result.teamId = team.Id;

    Case teamCase = new Case(
      Subject = SEED_MARKER + 'Case',
      Status = 'New',
      Origin = 'Phone',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;
    result.caseId = teamCase.Id;

    Account teamAccount = new Account(
      Name = SEED_MARKER + 'Household',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamAccount;
    result.accountId = teamAccount.Id;

    List<Task> tasks = new List<Task>{
      buildTask('Case Main Track', currentUserId, teamCase.Id, false, false),
      buildTask('Case HO Pit Stop', currentUserId, teamCase.Id, true, false),
      buildTask('Case Branch Pit Stop', currentUserId, teamCase.Id, false, true),
      buildTask('Account Main Track', currentUserId, teamAccount.Id, false, false),
      buildTask('Account HO Pit Stop', currentUserId, teamAccount.Id, true, false),
      buildTask(
        'Account Branch Pit Stop',
        currentUserId,
        teamAccount.Id,
        false,
        true
      )
    };
    insert tasks;
    result.tasksCreated = tasks.size();
    return result;
  }

  public static void logResult(SeedResult result) {
    System.debug('NexsTaskMetrics seed result: ' + JSON.serialize(result));
  }

  private static Financial_Advisor_Team__c resolveTeamForUser(Id userId) {
    List<Financial_Advisor_Team_Member__c> memberships = [
      SELECT Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :userId AND Active__c = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    if (!memberships.isEmpty()) {
      return [
        SELECT Id, Name
        FROM Financial_Advisor_Team__c
        WHERE Id = :memberships[0].Financial_Advisor_Team__c
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
    }

    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = SEED_MARKER + 'Team',
      Related_Advisors__c = 'NTM' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
    insert team;

    insert new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = team.Id,
      User__c = userId,
      Active__c = true
    );

    return team;
  }

  private static List<Task> buildOwnedCaseTasksForType(
    String typeLabel,
    Id ownerId,
    List<Case> ownedCases,
    Integer startingCaseIndex,
    Set<Id> usedCaseIds,
    Integer tasksPerType,
    Boolean isHoPitStop,
    Boolean isBranchPitStop
  ) {
    List<Task> tasks = new List<Task>();
    Integer caseIndex = startingCaseIndex;

    for (Integer taskIndex = 1; taskIndex <= tasksPerType; taskIndex++) {
      Case caseRecord = ownedCases[Math.mod(caseIndex, ownedCases.size())];
      caseIndex++;
      usedCaseIds.add(caseRecord.Id);

      tasks.add(
        buildTask(
          OWNED_CASE_SEED_MARKER + typeLabel + ' ' + taskIndex,
          ownerId,
          caseRecord.Id,
          isHoPitStop,
          isBranchPitStop
        )
      );
    }

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
      Subject = subject.startsWith(SEED_MARKER) || subject.startsWith(OWNED_CASE_SEED_MARKER)
        ? subject
        : SEED_MARKER + subject,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = ownerId,
      WhatId = whatId,
      Home_Office_Pit_Stop__c = isHoPitStop,
      Branch_Pit_Stop__c = isBranchPitStop
    );
  }

  private static void clearOwnedCaseSeedData(Id userId) {
    delete [
      SELECT Id
      FROM Task
      WHERE
        OwnerId = :userId
        AND Subject LIKE :(OWNED_CASE_SEED_MARKER + '%')
      WITH SECURITY_ENFORCED
    ];
  }

  private static Boolean hasExistingSeedData(Id userId) {
    return [
        SELECT COUNT()
        FROM Task
        WHERE OwnerId = :userId AND Subject LIKE :(SEED_MARKER + '%') AND IsClosed = FALSE
        WITH SECURITY_ENFORCED
      ] > 0;
  }

  private static void clearExistingSeedData(Id userId) {
    delete [
      SELECT Id
      FROM Task
      WHERE OwnerId = :userId AND Subject LIKE :(SEED_MARKER + '%')
      WITH SECURITY_ENFORCED
    ];
  }
}