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
}