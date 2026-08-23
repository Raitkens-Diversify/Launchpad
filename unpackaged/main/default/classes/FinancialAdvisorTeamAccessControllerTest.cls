@IsTest
private class FinancialAdvisorTeamAccessControllerTest {
  @IsTest
  static void getMyTeamIdsReturnsEmptyListWithNoMembership() {
    Test.startTest();
    List<Id> teamIds = FinancialAdvisorTeamAccessController.getMyTeamIds();
    Test.stopTest();

    System.assertEquals(0, teamIds.size());
  }

  @IsTest
  static void getMyTeamIdsReturnsMembershipTeamIds() {
    Financial_Advisor_Team__c team = ArcRelatedTableTestData.createFinancialAdvisorTeam(
      'My Team Access Test Team'
    );
    ArcRelatedTableTestData.createTeamMembership(team.Id, UserInfo.getUserId());

    Test.startTest();
    List<Id> teamIds = FinancialAdvisorTeamAccessController.getMyTeamIds();
    Test.stopTest();

    System.assertEquals(1, teamIds.size());
    System.assertEquals(team.Id, teamIds[0]);
  }
}