@IsTest
private class ArcCaseDetailControllerTest {
  @IsTest
  static void getCaseDetailReturnsFields() {
    Case record = new Case(
      Subject = 'Test Case',
      Status = 'New',
      Priority = 'High'
    );
    insert record;

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    System.assertEquals('Test Case', result.subject);
    System.assertEquals('New', result.status);
  }

  // getCaseDetail's Household-summary branch (formatAddress/formatCurrency/
  // formatPercent) is exercised through a direct DB round trip in
  // getCaseDetailReturnsHouseholdSummaryWhenPopulated below (Household__c,
  // a plain custom lookup, survives a normal test-context insert -- unlike
  // the older FinServ__Household__c managed-package field this code used
  // to read, which some FSC-internal automation cleared specifically in
  // Apex test execution). The formatting helpers are additionally
  // unit-tested directly (below) so each formatting rule has its own
  // focused assertion.
  @IsTest
  static void getCaseDetailReturnsHouseholdSummaryWhenPopulated() {
    Account household = new Account(
      Name = 'Test Household',
      Type = 'Prospect',
      BillingStreet = '1 Main St',
      BillingCity = 'Springfield',
      BillingStateCode = 'IL',
      BillingPostalCode = '62701',
      Liquidity_Needs__c = 'Very Important',
      Approximate_Net_Worth__c = 500000,
      Risk_Tolerance__c = 'Moderate',
      Approximate_Annual_Income_All_Sources__c = 120000,
      Investment_Objective_Ranked__c = 'Growth',
      Approximate_Highest_Tax_Bracket__c = '24%',
      Advisory_Fee__c = 1.25
    );
    insert household;

    Case record = new Case(
      Subject = 'Household Case',
      Status = 'New',
      Household__c = household.Id
    );
    insert record;

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(household.Id, result.householdId);
    Assert.areEqual('Test Household', result.householdName);
    Assert.isNotNull(result.household, 'A populated Household__c should produce a summary.');
    Assert.areEqual('Very Important', result.household.liquidityNeeds);
  }

  @IsTest
  static void formatAddressJoinsStreetCityStateAndZip() {
    Account household = new Account(
      BillingStreet = '1 Main St',
      BillingCity = 'Springfield',
      BillingState = 'IL',
      BillingPostalCode = '62701'
    );

    String address = ArcCaseDetailController.formatAddress(household);

    System.assertEquals('1 Main St, Springfield, IL 62701', address);
  }

  @IsTest
  static void formatAddressReturnsNullWhenNoAddressFieldsSet() {
    Account household = new Account();

    String address = ArcCaseDetailController.formatAddress(household);

    System.assertEquals(null, address);
  }

  @IsTest
  static void formatCurrencyFormatsWithDollarSign() {
    System.assertEquals(
      '$' + ((Decimal) 500000).format(),
      ArcCaseDetailController.formatCurrency(500000)
    );
    System.assertEquals(null, ArcCaseDetailController.formatCurrency(null));
  }

  @IsTest
  static void formatPercentAppendsPercentSign() {
    System.assertEquals(
      ((Decimal) 1.25).format() + '%',
      ArcCaseDetailController.formatPercent(1.25)
    );
    System.assertEquals(null, ArcCaseDetailController.formatPercent(null));
  }

  @IsTest
  static void buildHouseholdSummaryMapsEveryAccountField() {
    Account household = new Account(
      Liquidity_Needs__c = 'Very Important',
      Approximate_Net_Worth__c = 500000,
      Risk_Tolerance__c = 'Moderate',
      Approximate_Annual_Income_All_Sources__c = 120000,
      Investment_Objective_Ranked__c = 'Growth',
      Approximate_Highest_Tax_Bracket__c = '24%',
      Advisory_Fee__c = 1.25
    );

    ArcCaseDetailController.HouseholdSummary summary = ArcCaseDetailController.buildHouseholdSummary(
      household
    );

    System.assertEquals('Very Important', summary.liquidityNeeds);
    System.assertEquals(
      '$' + ((Decimal) 500000).format(),
      summary.approximateNetWorth
    );
    System.assertEquals('Moderate', summary.riskTolerance);
    System.assertEquals(
      '$' + ((Decimal) 120000).format(),
      summary.approximateAnnualIncome
    );
    System.assertEquals('Growth', summary.investmentObjective);
    System.assertEquals('24%', summary.approximateHighestTaxBracket);
    System.assertEquals(((Decimal) 1.25).format() + '%', summary.advisoryFee);
  }

  @IsTest
  static void toRelatedCaseInfoMapsCaseFieldsAndHandlesMissingOwner() {
    Case source = new Case(Subject = 'Related Subject', Status = 'New');

    ArcCaseDetailController.RelatedCaseInfo info = ArcCaseDetailController.toRelatedCaseInfo(
      source
    );

    System.assertEquals('Related Subject', info.subject);
    System.assertEquals('New', info.status);
    System.assertEquals(null, info.ownerName);
  }

  @IsTest
  static void getCaseDetailThrowsWhenCaseIdMissing() {
    Boolean threw = false;

    Test.startTest();
    try {
      ArcCaseDetailController.getCaseDetail(null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getCaseTasksReturnsTasksLinkedToTheCase() {
    Case record = new Case(Subject = 'Case With Tasks', Status = 'New');
    insert record;

    insert new List<Task>{
      new Task(
        Subject = 'First Task',
        Status = 'Not Started',
        WhatId = record.Id
      ),
      new Task(
        Subject = 'Second Task',
        Status = 'Completed',
        WhatId = record.Id
      )
    };

    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> tasks = ArcCaseDetailController.getCaseTasks(
      record.Id
    );
    Test.stopTest();

    System.assertEquals(2, tasks.size());
  }

  @IsTest
  static void getCaseTasksReturnsEmptyListWhenCaseIdMissing() {
    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> tasks = ArcCaseDetailController.getCaseTasks(
      null
    );
    Test.stopTest();

    System.assertEquals(0, tasks.size());
  }

  @IsTest
  static void getCaseFieldSectionsReturnsEmptyListForUnmappedType() {
    Case record = new Case(
      Subject = 'Unmapped Type Case',
      Status = 'New',
      Type = 'General'
    );
    insert record;

    Test.startTest();
    List<ArcCaseDetailController.SectionView> sections = ArcCaseDetailController.getCaseFieldSections(
      record.Id
    );
    Test.stopTest();

    System.assertEquals(0, sections.size());
  }

  @IsTest
  static void getCaseFieldSectionsReturnsEmptyListWhenCaseIdMissing() {
    Test.startTest();
    List<ArcCaseDetailController.SectionView> sections = ArcCaseDetailController.getCaseFieldSections(
      null
    );
    Test.stopTest();

    System.assertEquals(0, sections.size());
  }

  @IsTest
  static void getRelatedHouseholdCasesReturnsEmptyWhenNoHousehold() {
    Case record = new Case(Subject = 'No Household Case', Status = 'New');
    insert record;

    Test.startTest();
    ArcCaseDetailController.HouseholdCasesResult result = ArcCaseDetailController.getRelatedHouseholdCases(
      record.Id
    );
    Test.stopTest();

    System.assertEquals(0, result.openCases.size());
    System.assertEquals(0, result.closedCases.size());
  }

  @IsTest
  static void getRelatedHouseholdCasesSplitsSiblingsIntoOpenAndClosed() {
    Account household = new Account(Name = 'Sibling Household', Type = 'Prospect');
    insert household;

    Case current = new Case(
      Subject = 'Current Case',
      Status = 'New',
      Household__c = household.Id
    );
    insert current;

    insert new List<Case>{
      new Case(
        Subject = 'Open Sibling',
        Status = 'New',
        Household__c = household.Id
      ),
      new Case(
        Subject = 'Closed Sibling',
        Status = 'Closed',
        Household__c = household.Id
      )
    };

    Test.startTest();
    ArcCaseDetailController.HouseholdCasesResult result = ArcCaseDetailController.getRelatedHouseholdCases(
      current.Id
    );
    Test.stopTest();

    Assert.areEqual(1, result.openCases.size());
    Assert.areEqual('Open Sibling', result.openCases[0].subject);
    Assert.areEqual(1, result.closedCases.size());
    Assert.areEqual('Closed Sibling', result.closedCases[0].subject);
  }

  /**
   * A case parked in a pit stop is waiting on someone else, so it is not on
   * track however many of its main-track tasks are finished. This asserts the
   * two halves are independent: 100% complete and still not on track.
   */
  @IsTest
  static void getCaseDetailReportsPitStopSeparatelyFromCompletion() {
    Case record = new Case(Subject = 'Pit stop progress case');
    insert record;

    insert new List<Task>{
      new Task(Subject = 'Main track done', WhatId = record.Id, Status = 'Completed'),
      new Task(
        Subject = 'HO pit stop open',
        WhatId = record.Id,
        Status = 'Not Started',
        Home_Office_Pit_Stop__c = true
      )
    };

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      result.progress.total,
      'A pit stop task is not a main track task and must not swell the total.'
    );
    Assert.areEqual(100, result.progress.percent, 'The one main track task is done.');
    Assert.isTrue(result.progress.isInPitStop, 'An open pit stop task parks the case.');
    Assert.areEqual(
      'Home office pit stop',
      result.progress.label,
      'The pill names which pit stop, not just that there is one.'
    );
    Assert.areEqual(
      1,
      result.progress.openHomeOfficePitStopTasks,
      'The breakdown counts the open home office task.'
    );
  }

  /** Home office outranks branch: it is the one the advisor cannot clear. */
  @IsTest
  static void getCaseDetailPrefersHomeOfficeOverBranchPitStop() {
    Case record = new Case(Subject = 'Both pit stops case');
    insert record;

    insert new List<Task>{
      new Task(
        Subject = 'Branch open',
        WhatId = record.Id,
        Status = 'Not Started',
        Branch_Pit_Stop__c = true
      ),
      new Task(
        Subject = 'Home office open',
        WhatId = record.Id,
        Status = 'Not Started',
        Home_Office_Pit_Stop__c = true
      )
    };

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(
      'Home office pit stop',
      result.progress.label,
      'With both open, the home office one is the blocker worth naming.'
    );
  }

  /** No tasks at all means no progress to draw, not a division by zero. */
  @IsTest
  static void getCaseDetailHandlesACaseWithNoTasks() {
    Case record = new Case(Subject = 'No tasks case');
    insert record;

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(0, result.progress.total, 'No tasks, no total.');
    Assert.areEqual(0, result.progress.percent, 'Percent is 0, not an error.');
    Assert.isFalse(result.progress.isInPitStop, 'Nothing is blocking it.');
  }
}