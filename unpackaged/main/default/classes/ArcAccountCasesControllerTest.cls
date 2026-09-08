@IsTest
private class ArcAccountCasesControllerTest {
  @IsTest
  static void getCasesForAccountReturnsCasesLinkedDirectlyByAccountId() {
    Account account = new Account(Name = 'Direct Account', Type = 'Prospect');
    insert account;

    Case directCase = new Case(Subject = 'Direct', Status = 'New', AccountId = account.Id);
    insert directCase;

    Test.startTest();
    ArcAccountCasesController.CasesPage result = ArcAccountCasesController.getCasesForAccount(
      account.Id,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual(directCase.Id, result.rows[0].id);
    Assert.areEqual(false, result.hasMore);
  }

  @IsTest
  static void getCasesForAccountReturnsCasesLinkedThroughHousehold() {
    Account household = new Account(Name = 'Household Only', Type = 'Prospect');
    insert household;

    Case householdCase = new Case(
      Subject = 'Household Case',
      Status = 'New',
      Household__c = household.Id
    );
    insert householdCase;

    Test.startTest();
    ArcAccountCasesController.CasesPage result = ArcAccountCasesController.getCasesForAccount(
      household.Id,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual(householdCase.Id, result.rows[0].id);
  }

  @IsTest
  static void getCasesForAccountPaginatesWithHasMore() {
    Account account = new Account(Name = 'Paginated Account', Type = 'Prospect');
    insert account;

    insert new List<Case>{
      new Case(Subject = 'Case 1', Status = 'New', AccountId = account.Id),
      new Case(Subject = 'Case 2', Status = 'New', AccountId = account.Id),
      new Case(Subject = 'Case 3', Status = 'New', AccountId = account.Id)
    };

    Test.startTest();
    ArcAccountCasesController.CasesPage firstPage = ArcAccountCasesController.getCasesForAccount(
      account.Id,
      0,
      2
    );
    ArcAccountCasesController.CasesPage secondPage = ArcAccountCasesController.getCasesForAccount(
      account.Id,
      2,
      2
    );
    Test.stopTest();

    Assert.areEqual(2, firstPage.rows.size());
    Assert.areEqual(true, firstPage.hasMore);
    Assert.areEqual(1, secondPage.rows.size());
    Assert.areEqual(false, secondPage.hasMore);
  }

  /**
   * Scoped like every ARC list (ArcListScope): another user's case on this
   * account stays out unless one of my active teams is linked to it.
   */
  @IsTest
  static void getCasesForAccountOnlyReturnsCasesOwnedByMeOrLinkedToMyTeams() {
    Account account = new Account(Name = 'Scoped Account', Type = 'Prospect');
    insert account;
    User otherOwner = ArcRelatedTableTestData.createStandardUser('acctcase');
    Financial_Advisor_Team__c myTeam = ArcRelatedTableTestData.createFinancialAdvisorTeam(
      'Account Cases Team'
    );
    ArcRelatedTableTestData.createTeamMembership(myTeam.Id, UserInfo.getUserId());

    Case mine = new Case(Subject = 'Mine', Status = 'New', AccountId = account.Id);
    Case teams = new Case(
      Subject = 'MyTeam',
      Status = 'New',
      AccountId = account.Id,
      Financial_Advisor_Team__c = myTeam.Id
    );
    Case theirs = new Case(
      Subject = 'Theirs',
      Status = 'New',
      AccountId = account.Id,
      OwnerId = otherOwner.Id
    );
    insert new List<Case>{ mine, teams, theirs };
    // Case_TriggerHandler.setProjectManager resets a team-linked case's owner
    // on insert, so the off-team owner is applied with an update.
    teams.OwnerId = otherOwner.Id;
    update teams;

    Test.startTest();
    ArcAccountCasesController.CasesPage result = ArcAccountCasesController.getCasesForAccount(
      account.Id,
      null,
      null
    );
    Test.stopTest();

    Set<Id> ids = new Set<Id>();
    for (ArcAccountCasesController.CaseRow row : result.rows) {
      ids.add(row.id);
    }
    Assert.areEqual(2, result.rows.size(), 'owned by me or linked to my team');
    Assert.isTrue(ids.contains(mine.Id), 'my own case');
    Assert.isTrue(ids.contains(teams.Id), 'my team\'s case, owned off-team');
    Assert.isFalse(ids.contains(theirs.Id), 'someone else\'s unlinked case');
  }

  @IsTest
  static void getCasesForAccountReturnsEmptyForNullAccountId() {
    Test.startTest();
    ArcAccountCasesController.CasesPage result = ArcAccountCasesController.getCasesForAccount(
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.isNotNull(result.rows, 'Rows should be an empty list, not null.');
    Assert.areEqual(0, result.rows.size());
    Assert.areEqual(false, result.hasMore);
  }

  @IsTest
  static void getCasesForAccountShowsUnsubmittedForADraft() {
    Account account = new Account(Name = 'Draft Account', Type = 'Prospect');
    insert account;

    Case draft = new Case(
      Subject = 'Wizard draft',
      Status = 'New',
      AccountId = account.Id,
      Submitted__c = false
    );
    insert draft;

    Test.startTest();
    ArcAccountCasesController.CasesPage result = ArcAccountCasesController.getCasesForAccount(
      account.Id,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Unsubmitted', result.rows[0].overallStatus);
  }
}