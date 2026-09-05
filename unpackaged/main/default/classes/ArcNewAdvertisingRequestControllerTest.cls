@IsTest
private class ArcNewAdvertisingRequestControllerTest {
  @IsTest
  static void searchAccountsReturnsEmptyListForShortTerm() {
    List<ArcNewAdvertisingRequestController.AccountOption> results = ArcNewAdvertisingRequestController.searchAccounts(
      'a'
    );
    System.assertEquals(0, results.size());
  }

  @IsTest
  static void searchAccountsReturnsMatchingAccountsByName() {
    insert new Account(Name = 'ARCQA Advertising Household', Type = 'Prospect', Classification__c = 'Unclassified');

    Test.startTest();
    List<ArcNewAdvertisingRequestController.AccountOption> results = ArcNewAdvertisingRequestController.searchAccounts(
      'Advertising Household'
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals('ARCQA Advertising Household', results[0].name);
  }

  @IsTest
  static void createAdvertisingRequestThrowsWhenAccountMissing() {
    try {
      ArcNewAdvertisingRequestController.createAdvertisingRequest(
        null,
        'Test Subject',
        'Test Description',
        'High',
        'New'
      );
      System.assert(false, 'Expected an exception for a missing account');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @IsTest
  static void createAdvertisingRequestCreatesCaseFromAccount() {
    Account household = new Account(Name = 'ARCQA Advertising Household 2', Type = 'Prospect', Classification__c = 'Unclassified');
    insert household;

    Test.startTest();
    Id caseId = ArcNewAdvertisingRequestController.createAdvertisingRequest(
      household.Id,
      'Test Subject',
      'Test Description',
      'High',
      'New'
    );
    Test.stopTest();

    Case created = [
      SELECT Subject, Description, Priority, Status, Origin, AccountId, OwnerId
      FROM Case
      WHERE Id = :caseId
    ];
    System.assertEquals('Test Subject', created.Subject);
    System.assertEquals('High', created.Priority);
    System.assertEquals('New', created.Status);
    System.assertEquals('Ad Hoc', created.Origin);
    System.assertEquals(household.Id, created.AccountId);
    System.assertEquals(UserInfo.getUserId(), created.OwnerId);
  }
}