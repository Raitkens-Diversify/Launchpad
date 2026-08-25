/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcRelatedEnvelopeTableRepositoryTest {
  @IsTest
  static void selectRowsMineReturnsOwnedEnvelopesOnly() {
    User otherUser = ArcRelatedTableTestData.createStandardUser('otherenv');
    Envelope__c mineEnvelope = new Envelope__c(
      Name = 'Owned Envelope',
      Status__c = 'In Progress'
    );
    insert mineEnvelope;

    Envelope__c otherEnvelope = new Envelope__c(
      Name = 'Other Envelope',
      Status__c = 'In Progress',
      OwnerId = otherUser.Id
    );
    insert otherEnvelope;

    ArcRelatedEnvelopeTableRepository repository = new ArcRelatedEnvelopeTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.MINE
    );
    Test.stopTest();

    Set<String> ids = new Set<String>();
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      ids.add(row.id);
    }

    System.assertEquals(true, ids.contains(String.valueOf(mineEnvelope.Id)));
    System.assertEquals(false, ids.contains(String.valueOf(otherEnvelope.Id)));
  }

  @IsTest
  static void selectRowsTeamReturnsFinancialAdvisorTeamEnvelopes() {
    Financial_Advisor_Team__c team = ArcRelatedTableTestData.createFinancialAdvisorTeam(
      'Envelope Team'
    );
    ArcRelatedTableTestData.createTeamMembership(team.Id, UserInfo.getUserId());

    Envelope__c teamEnvelope = new Envelope__c(
      Name = 'Team Envelope',
      Status__c = 'In Progress',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamEnvelope;

    Envelope__c otherEnvelope = new Envelope__c(
      Name = 'Unassigned Envelope',
      Status__c = 'In Progress'
    );
    insert otherEnvelope;

    ArcRelatedEnvelopeTableRepository repository = new ArcRelatedEnvelopeTableRepository();

    Test.startTest();
    ArcRelatedTableModels.TableData result = repository.selectRows(
      ArcRelatedTableScope.Value.TEAM
    );
    Test.stopTest();

    Set<String> ids = new Set<String>();
    for (ArcRelatedTableModels.TableRow row : result.rows) {
      ids.add(row.id);
    }

    System.assertEquals(true, ids.contains(String.valueOf(teamEnvelope.Id)));
    System.assertEquals(false, ids.contains(String.valueOf(otherEnvelope.Id)));
  }
}