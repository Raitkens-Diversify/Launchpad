/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcRelatedWorkTableRepositoryTest {
  @IsTest
  static void selectRowsMineReturnsOwnedCaseAndTask() {
    Case ownedCase = new Case(
      Subject = 'Mine Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = UserInfo.getUserId(),
      Total_Main_Track_Tasks__c = 5,
      Completed_Main_Track_Tasks__c = 2
    );
    insert ownedCase;

    Task ownedTask = new Task(
      Subject = 'Mine Work Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId()
    );
    insert ownedTask;

    ArcRelatedWorkTableRepository repository = new ArcRelatedWorkTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.MINE
    );
    Test.stopTest();

    Set<String> ids = new Set<String>();
    ArcRelatedTableModels.TableRow ownedCaseRow;
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      ids.add(row.id);
      if (row.id == String.valueOf(ownedCase.Id)) {
        ownedCaseRow = row;
      }
    }

    System.assertEquals(true, ids.contains(String.valueOf(ownedCase.Id)));
    System.assertEquals(true, ids.contains(String.valueOf(ownedTask.Id)));
    System.assertNotEquals(null, ownedCaseRow);
    System.assertEquals('2 / 5', ownedCaseRow.mainTrackTasks);
    System.assertEquals(2, ownedCaseRow.completedMainTrack);
    System.assertEquals(5, ownedCaseRow.totalMainTrack);
  }

  @IsTest
  static void selectRowsTeamReturnsTeamCaseAndMemberTask() {
    User teammate = ArcRelatedTableTestData.createStandardUser('teammate');
    Financial_Advisor_Team__c team = ArcRelatedTableTestData.createFinancialAdvisorTeam(
      'Work Team'
    );
    ArcRelatedTableTestData.createTeamMembership(team.Id, UserInfo.getUserId());
    ArcRelatedTableTestData.createTeamMembership(team.Id, teammate.Id);

    Case teamCase = new Case(
      Subject = 'Team Case',
      Status = 'New',
      Origin = 'Phone',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;

    Task teammateTask = new Task(
      Subject = 'Team Member Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = teammate.Id
    );
    insert teammateTask;

    ArcRelatedWorkTableRepository repository = new ArcRelatedWorkTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.TEAM
    );
    Test.stopTest();

    Set<String> ids = new Set<String>();
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      ids.add(row.id);
    }

    System.assertEquals(true, ids.contains(String.valueOf(teamCase.Id)));
    System.assertEquals(true, ids.contains(String.valueOf(teammateTask.Id)));
  }

  /**
   * Team scope with no team at all returns no Cases (selectCaseRows short
   * circuits on an empty teamIds), but FinancialAdvisorTeamAccessService
   * always seeds teamMemberUserIds with the running user regardless of team
   * membership, so selectTaskRows still returns that user's own open tasks --
   * "my team" degrades to "just me" rather than to nothing.
   */
  @IsTest
  static void selectRowsTeamReturnsOnlyOwnTasksWhenUserHasNoTeam() {
    Case unrelatedCase = new Case(
      Subject = 'Unrelated Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = UserInfo.getUserId()
    );
    insert unrelatedCase;
    Task ownTask = new Task(
      Subject = 'Unrelated Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId()
    );
    insert ownTask;

    ArcRelatedWorkTableRepository repository = new ArcRelatedWorkTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.TEAM
    );
    Test.stopTest();

    System.assertEquals(1, result.totalCount);
    Set<String> ids = new Set<String>();
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      ids.add(row.id);
    }
    System.assertEquals(
      false,
      ids.contains(String.valueOf(unrelatedCase.Id)),
      'No team means selectCaseRows returns nothing.'
    );
    System.assertEquals(
      true,
      ids.contains(String.valueOf(ownTask.Id)),
      'selectTaskRows still includes the running user\'s own tasks.'
    );
  }

  /**
   * A task's "Related To" label is resolved from whichever object WhatId
   * points at -- a Case (by CaseNumber) or an Account (by Name) -- and a task
   * with an explicit ActivityDate is dated from that field rather than
   * falling back to LastModifiedDate.
   */
  @IsTest
  static void selectRowsMineResolvesRelatedToLabelForCaseAndAccountTasks() {
    Case relatedCase = new Case(
      Subject = 'Related Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = UserInfo.getUserId()
    );
    insert relatedCase;
    relatedCase = [SELECT Id, CaseNumber FROM Case WHERE Id = :relatedCase.Id];

    Account relatedAccount = new Account(Name = 'Related Account', Type = 'Prospect');
    insert relatedAccount;

    Task caseTask = new Task(
      Subject = 'Case Related Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      WhatId = relatedCase.Id,
      ActivityDate = Date.today()
    );
    Task accountTask = new Task(
      Subject = 'Account Related Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      WhatId = relatedAccount.Id
    );
    insert new List<Task>{ caseTask, accountTask };

    ArcRelatedWorkTableRepository repository = new ArcRelatedWorkTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.MINE
    );
    Test.stopTest();

    Map<String, ArcRelatedTableModels.TableRow> rowsById = new Map<String, ArcRelatedTableModels.TableRow>();
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      rowsById.put(row.id, row);
    }

    System.assertEquals(
      relatedCase.CaseNumber,
      rowsById.get(String.valueOf(caseTask.Id)).relatedTo,
      'A task on a Case shows the case number.'
    );
    System.assertEquals(
      'Related Account',
      rowsById.get(String.valueOf(accountTask.Id)).relatedTo,
      'A task on an Account shows the account name.'
    );
    System.assertNotEquals(
      null,
      rowsById.get(String.valueOf(caseTask.Id)).activityDate,
      'An explicit ActivityDate is formatted rather than left blank.'
    );
  }
}