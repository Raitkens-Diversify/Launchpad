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
}