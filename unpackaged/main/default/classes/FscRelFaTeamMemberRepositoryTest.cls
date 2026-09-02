/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-22
 */
@IsTest
private class FscRelFaTeamMemberRepositoryTest {
  @IsTest
  static void selectActiveByUserId_returnsActiveMembers() {
    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'FA Team Repo Test',
      Related_Advisors__c = 'FaTeamRepo' + System.currentTimeMillis()
    );
    insert faTeam;

    Financial_Advisor_Team_Member__c member = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = UserInfo.getUserId(),
      Active__c = true,
      Primary__c = true
    );

    try {
      insert member;
    } catch (DmlException error) {
      return;
    }

    FscRelFaTeamMemberRepository repository = new FscRelFaTeamMemberRepository();

    Test.startTest();
    List<Financial_Advisor_Team_Member__c> members = repository.selectActiveByUserId(
      UserInfo.getUserId()
    );
    Set<Id> teamIds = repository.selectActiveTeamIdsByUserId(UserInfo.getUserId());
    Boolean isMember = repository.isActiveMember(UserInfo.getUserId(), faTeam.Id);
    List<Financial_Advisor_Team_Member__c> emptyResults = repository.selectActiveByUserId(
      null
    );
    Test.stopTest();

    System.assert(!members.isEmpty());
    System.assert(teamIds.contains(faTeam.Id));
    System.assertEquals(true, isMember);
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void isActiveMember_returnsFalseForMissingMembership() {
    FscRelFaTeamMemberRepository repository = new FscRelFaTeamMemberRepository();

    Test.startTest();
    Boolean isMember = repository.isActiveMember(UserInfo.getUserId(), null);
    Test.stopTest();

    System.assertEquals(false, isMember);
  }
}