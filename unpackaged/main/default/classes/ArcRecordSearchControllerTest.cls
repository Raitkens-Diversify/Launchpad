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

    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'RecordType.Name';
    filter.operator = 'Equals';
    filter.operandValue = 'Business';

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      JSON.serialize(new List<ArcRecordSearchController.SearchFilter>{ filter }),
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

    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'RecordType.Name';
    filter.operator = 'Equals';
    filter.operandValue = 'No Such Record Type Label';

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      JSON.serialize(new List<ArcRecordSearchController.SearchFilter>{ filter }),
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

    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = 'AnnualRevenue';
    filter.operator = 'GreaterThan';
    filter.operandValue = '100000';

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      JSON.serialize(new List<ArcRecordSearchController.SearchFilter>{ filter }),
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Large Fund', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsAppliesTextComparisonOperators() {
    insert new List<Account>{
      new Account(Name = 'Zebra Holdings'),
      new Account(Name = 'Other Company')
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult containsResult = searchWithFilter('Name', 'Contains', 'Zebra');
    ArcRecordSearchController.SearchResult startsWithResult = searchWithFilter('Name', 'StartsWith', 'Zebra');
    ArcRecordSearchController.SearchResult notContainResult = searchWithFilter('Name', 'NotContain', 'Zebra');
    Test.stopTest();

    Assert.areEqual('Zebra Holdings', containsResult.rows[0].cells[0]);
    Assert.areEqual('Zebra Holdings', startsWithResult.rows[0].cells[0]);
    Assert.areEqual('Other Company', notContainResult.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsAppliesRemainingNumericComparisonOperators() {
    insert new List<Account>{
      new Account(Name = 'Small Fund', AnnualRevenue = 5000),
      new Account(Name = 'Large Fund', AnnualRevenue = 5000000)
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult equalsResult = searchWithFilter('AnnualRevenue', 'Equals', '5000');
    ArcRecordSearchController.SearchResult notEqualResult = searchWithFilter('AnnualRevenue', 'NotEqual', '5000');
    ArcRecordSearchController.SearchResult greaterOrEqualResult = searchWithFilter('AnnualRevenue', 'GreaterOrEqual', '5000000');
    ArcRecordSearchController.SearchResult lessThanResult = searchWithFilter('AnnualRevenue', 'LessThan', '100000');
    ArcRecordSearchController.SearchResult lessOrEqualResult = searchWithFilter('AnnualRevenue', 'LessOrEqual', '5000');
    Test.stopTest();

    Assert.areEqual('Small Fund', equalsResult.rows[0].cells[0]);
    Assert.areEqual('Large Fund', notEqualResult.rows[0].cells[0]);
    Assert.areEqual('Large Fund', greaterOrEqualResult.rows[0].cells[0]);
    Assert.areEqual('Small Fund', lessThanResult.rows[0].cells[0]);
    Assert.areEqual('Small Fund', lessOrEqualResult.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsDropsFilterOnUnknownFieldAndDropsUnknownColumnSelection() {
    insert new Account(Name = 'Untouched By Bad Filter');

    Test.startTest();
    ArcRecordSearchController.SearchResult unknownFieldFilterResult = searchWithFilter(
      'No_Such_Field__x',
      'Equals',
      'anything'
    );
    ArcRecordSearchController.SearchResult emptySelectionResult = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'No_Such_Field__x' },
      null,
      null,
      null,
      null,
      25
    );
    Test.stopTest();

    // An unrecognised filter field is dropped rather than failing the whole
    // search, same documented behavior as an unresolvable RecordType label.
    Assert.areEqual(1, unknownFieldFilterResult.rows.size());
    // No requested column survives validation, so no query is even attempted.
    Assert.isTrue(emptySelectionResult.rows.isEmpty());
  }

  private static ArcRecordSearchController.SearchResult searchWithFilter(
    String fieldApiName,
    String operator,
    String operandValue
  ) {
    ArcRecordSearchController.SearchFilter filter = new ArcRecordSearchController.SearchFilter();
    filter.fieldApiName = fieldApiName;
    filter.operator = operator;
    filter.operandValue = operandValue;
    return ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      JSON.serialize(new List<ArcRecordSearchController.SearchFilter>{ filter }),
      null,
      null,
      null,
      25
    );
  }
}