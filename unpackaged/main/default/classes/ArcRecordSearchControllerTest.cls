@IsTest
private class ArcRecordSearchControllerTest {
  @IsTest
  static void searchRecordsFiltersByRecordTypeLabel() {
    Id businessRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Business')
      .getRecordTypeId();
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();

    insert new List<Account>{
      new Account(Name = 'Acme Business', RecordTypeId = businessRecordTypeId),
      new Account(Name = 'Acme Household', RecordTypeId = householdRecordTypeId)
    };

    List<ArcRecordSearchController.SearchFilter> filters = new List<ArcRecordSearchController.SearchFilter>();
    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'RecordType.Name';
    filter.operator = 'Equals';
    filter.operandValue = 'Business';
    filters.add(filter);

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      filters,
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size(), 'only the Business-record-type account should match');
    Assert.areEqual('Acme Business', result.rows[0].cells[0]);
  }

  /**
   * This org has two record-type pairs sharing an identical label (Household
   * of both a plain "Household" and a "FinServ__IndustriesHousehold" record
   * type, likewise for "Business"), which is exactly the scenario
   * resolveRecordTypeIds iterating a plain list (not a Name-keyed map) exists
   * to preserve. The FinServ__Industries* half of each pair isn't insertable
   * from this org's Apex test context ("this ID value isn't valid for the
   * user", the same record-type-not-available-to-the-running-user's-profile
   * limitation documented elsewhere in this codebase's tests) -- so the
   * label-collision behavior itself isn't independently re-provable by
   * insert here. searchRecordsFiltersByRecordTypeLabel already exercises the
   * describe-based resolution this method now uses for a real record type
   * and label.
   */
  @IsTest
  static void searchRecordsDropsRecordTypeFilterWithNoMatchingLabelAndReturnsEverythingElseInstead() {
    insert new Account(Name = 'Unfiltered by anything');

    List<ArcRecordSearchController.SearchFilter> filters = new List<ArcRecordSearchController.SearchFilter>();
    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'RecordType.Name';
    filter.operator = 'Equals';
    filter.operandValue = 'No Such Record Type Label';
    filters.add(filter);

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      filters,
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    // Documented, pre-existing behavior (not something this fix changes): a
    // label matching no record type drops the whole clause rather than
    // failing the search, so the account comes back same as an unfiltered
    // query would return it.
    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Unfiltered by anything', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsReturnsEmptyForInaccessibleObject() {
    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'NoSuchObject__c',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    Assert.isTrue(result.rows.isEmpty());
    Assert.isNull(result.fieldApiNames);
  }

  @IsTest
  static void searchRecordsPaginatesByIdAndReportsHasMore() {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 3; i++) {
      accounts.add(new Account(Name = 'Paged ' + i));
    }
    insert accounts;

    Test.startTest();
    ArcRecordSearchController.SearchResult firstPage = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      null,
      2
    );
    ArcRecordSearchController.SearchResult secondPage = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      firstPage.rows[1].id,
      2
    );
    Test.stopTest();

    Assert.areEqual(2, firstPage.rows.size());
    Assert.isTrue(firstPage.hasMore, 'a third row exists past this page size');
    Assert.areEqual(1, secondPage.rows.size(), 'only the remaining row comes back after the last seen id');
    Assert.isFalse(secondPage.hasMore);
  }

  @IsTest
  static void searchRecordsFallsBackToLikeSearchForATermTooShortForSosl() {
    insert new List<Account>{
      new Account(Name = 'Zebra Holdings'),
      new Account(Name = 'Other Company')
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      'Z',
      new List<String>{ 'Name' },
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Zebra Holdings', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsAppliesNumericComparisonOperators() {
    insert new List<Account>{
      new Account(Name = 'Small Fund', AnnualRevenue = 5000),
      new Account(Name = 'Large Fund', AnnualRevenue = 5000000)
    };

    List<ArcRecordSearchController.SearchFilter> filters = new List<ArcRecordSearchController.SearchFilter>();
    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'AnnualRevenue';
    filter.operator = 'GreaterThan';
    filter.operandValue = '100000';
    filters.add(filter);

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      filters,
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Large Fund', result.rows[0].cells[0]);
  }
}