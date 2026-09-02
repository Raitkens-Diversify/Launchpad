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
      // Type='Prospect' satisfies Type_OR_Classification_Required, which
      // fires for the Business record type (among others) -- pre-existing
      // validation, unrelated to this test's own subject.
      new Account(Name = 'Acme Business', RecordTypeId = businessRecordTypeId, Type = 'Prospect'),
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
      null,
      25,
      null
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
    insert new Account(Name = 'Unfiltered by anything', Type = 'Prospect');

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
      null,
      25,
      null
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
      null,
      25,
      null
    );
    Test.stopTest();

    Assert.isTrue(result.rows.isEmpty());
    Assert.isNull(result.fieldApiNames);
  }

  @IsTest
  static void searchRecordsSortsByCreatedDateDescendingAndPaginatesByCompoundCursor() {
    Account oldest = new Account(Name = 'Oldest', Type = 'Prospect');
    Account middle = new Account(Name = 'Middle', Type = 'Prospect');
    Account newest = new Account(Name = 'Newest', Type = 'Prospect');
    insert new List<Account>{ oldest, middle, newest };

    // Forced, deterministic CreatedDate spread -- this test exists to prove
    // latest-CreatedDate-first ordering specifically, not whatever ordering
    // a single-transaction bulk insert happens to produce on its own.
    Test.setCreatedDate(oldest.Id, DateTime.newInstance(2026, 1, 1));
    Test.setCreatedDate(middle.Id, DateTime.newInstance(2026, 1, 2));
    Test.setCreatedDate(newest.Id, DateTime.newInstance(2026, 1, 3));

    Test.startTest();
    ArcRecordSearchController.SearchResult firstPage = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      null,
      null,
      2,
      null
    );
    ArcRecordSearchController.SearchResult secondPage = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      firstPage.rows[1].id,
      firstPage.rows[1].createdDate,
      2,
      null
    );
    Test.stopTest();

    Assert.areEqual(2, firstPage.rows.size());
    Assert.isTrue(firstPage.hasMore, 'a third row exists past this page size');
    Assert.areEqual('Newest', firstPage.rows[0].cells[0], 'the most recently created row leads');
    Assert.areEqual('Middle', firstPage.rows[1].cells[0]);
    Assert.areEqual(1, secondPage.rows.size(), 'only the remaining row comes back after the last seen (CreatedDate, Id)');
    Assert.isFalse(secondPage.hasMore);
    Assert.areEqual('Oldest', secondPage.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsBreaksCreatedDateTiesByIdDescending() {
    Account first = new Account(Name = 'Tied First', Type = 'Prospect');
    Account second = new Account(Name = 'Tied Second', Type = 'Prospect');
    insert new List<Account>{ first, second };

    // Same forced CreatedDate for both -- exactly the case the Id
    // tie-breaker exists for (routine for bulk inserts/API loads in
    // production, which is why Id alone was never a safe sole cursor key).
    Datetime sameInstant = DateTime.newInstance(2026, 1, 1);
    Test.setCreatedDate(first.Id, sameInstant);
    Test.setCreatedDate(second.Id, sameInstant);

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      null,
      null,
      null,
      null,
      25,
      null
    );
    Test.stopTest();

    // Identical CreatedDate for both -- Id DESC decides the order. `second`
    // was inserted after `first` in the same bulk DML, so it holds the
    // higher Id and leads.
    Assert.areEqual(2, result.rows.size());
    Assert.areEqual('Tied Second', result.rows[0].cells[0]);
    Assert.areEqual('Tied First', result.rows[1].cells[0]);
  }

  @IsTest
  static void searchRecordsFallsBackToLikeSearchForATermTooShortForSosl() {
    insert new List<Account>{
      new Account(Name = 'Zebra Holdings', Type = 'Prospect'),
      new Account(Name = 'Other Company', Type = 'Prospect')
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Account',
      new List<String>{ 'Name' },
      null,
      'Z',
      new List<String>{ 'Name' },
      null,
      null,
      25,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Zebra Holdings', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsAppliesNumericComparisonOperators() {
    insert new List<Account>{
      new Account(Name = 'Small Fund', AnnualRevenue = 5000, Type = 'Prospect'),
      new Account(Name = 'Large Fund', AnnualRevenue = 5000000, Type = 'Prospect')
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
      null,
      25,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Large Fund', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsAppliesTextComparisonOperators() {
    insert new List<Account>{
      new Account(Name = 'Zebra Holdings', Type = 'Prospect'),
      new Account(Name = 'Other Company', Type = 'Prospect')
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
      new Account(Name = 'Small Fund', AnnualRevenue = 5000, Type = 'Prospect'),
      new Account(Name = 'Large Fund', AnnualRevenue = 5000000, Type = 'Prospect')
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
    insert new Account(Name = 'Untouched By Bad Filter', Type = 'Prospect');

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
      null,
      25,
      null
    );
    Test.stopTest();

    // An unrecognised filter field is dropped rather than failing the whole
    // search, same documented behavior as an unresolvable RecordType label.
    Assert.areEqual(1, unknownFieldFilterResult.rows.size());
    // No requested column survives validation, so no query is even attempted.
    Assert.isTrue(emptySelectionResult.rows.isEmpty());
  }

  // ---- Per-tab mandatory filters (appendMandatoryFilter) ------------------

  @IsTest
  static void searchRecordsMyOpenCasesOnlyReturnsCasesOwnedByTheRunningUser() {
    User otherOwner = createTestUser('CaseOtherOwner');

    Case mine = new Case(Subject = 'Owned by me', Status = 'New');
    Case theirs = new Case(
      Subject = 'Owned by someone else',
      Status = 'New',
      OwnerId = otherOwner.Id
    );
    insert new List<Case>{ mine, theirs };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Case',
      new List<String>{ 'Subject' },
      null,
      null,
      null,
      null,
      null,
      25,
      'MyOpenCases'
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Owned by me', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsMyTeamsOpenCasesReturnsCasesOwnedByActiveTeammatesOnly() {
    User teammate = createTestUser('CaseTeammate');
    User outsider = createTestUser('CaseOutsider');
    User inactiveTeammate = createTestUser('CaseInactiveTeammate');

    // Financial_Advisor_Team_TriggerHandler.updateRepCode (unrelated,
    // pre-existing automation that fires on a Related_Advisors__c change
    // cascaded from inserting team members below) hardcodes a lookup for a
    // team literally named 'Default Team' and throws "List has no rows"
    // without one -- mirrors FATMember_TriggerHandler_Test's own seed data
    // for the exact same reason.
    insert new Financial_Advisor_Team__c(Name = 'Default Team');

    Financial_Advisor_Team__c myTeam = new Financial_Advisor_Team__c(Name = 'My Team');
    Financial_Advisor_Team__c otherTeam = new Financial_Advisor_Team__c(Name = 'Other Team');
    insert new List<Financial_Advisor_Team__c>{ myTeam, otherTeam };

    insert new List<Financial_Advisor_Team_Member__c>{
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = myTeam.Id,
        User__c = UserInfo.getUserId(),
        Role__c = 'Financial Advisor',
        Active__c = true
      ),
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = myTeam.Id,
        User__c = teammate.Id,
        Role__c = 'Financial Advisor',
        Active__c = true
      ),
      // Inactive membership on my own team -- their cases should NOT count
      // as "my team's", proving Active__c is actually checked and not just
      // team membership on its own.
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = myTeam.Id,
        User__c = inactiveTeammate.Id,
        Role__c = 'Financial Advisor',
        Active__c = false
      ),
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = otherTeam.Id,
        User__c = outsider.Id,
        Role__c = 'Financial Advisor',
        Active__c = true
      )
    };

    Case mine = new Case(Subject = 'Mine', Status = 'New');
    Case teammatesCase = new Case(
      Subject = 'Teammates',
      Status = 'New',
      OwnerId = teammate.Id
    );
    Case inactiveTeammatesCase = new Case(
      Subject = 'InactiveTeammates',
      Status = 'New',
      OwnerId = inactiveTeammate.Id
    );
    Case outsidersCase = new Case(
      Subject = 'Outsiders',
      Status = 'New',
      OwnerId = outsider.Id
    );
    insert new List<Case>{ mine, teammatesCase, inactiveTeammatesCase, outsidersCase };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Case',
      new List<String>{ 'Subject' },
      null,
      null,
      null,
      null,
      null,
      25,
      'My_teams_open_cases'
    );
    Test.stopTest();

    Set<String> subjects = new Set<String>();
    for (ArcRecordSearchController.SearchRow row : result.rows) {
      subjects.add(row.cells[0]);
    }
    Assert.areEqual(2, result.rows.size());
    Assert.isTrue(subjects.contains('Mine'));
    Assert.isTrue(subjects.contains('Teammates'));
    Assert.isFalse(subjects.contains('InactiveTeammates'));
    Assert.isFalse(subjects.contains('Outsiders'));
  }

  @IsTest
  static void searchRecordsMyOpenTasksOnlyReturnsOpenTasksOwnedByTheRunningUser() {
    User otherOwner = createTestUser('TaskOtherOwner');

    Task openMine = new Task(Subject = 'Open, mine', Status = 'Not Started');
    Task closedMine = new Task(
      Subject = 'Closed, mine',
      Status = 'Completed'
    );
    Task openTheirs = new Task(
      Subject = 'Open, someone else',
      Status = 'Not Started',
      OwnerId = otherOwner.Id
    );
    insert new List<Task>{ openMine, closedMine, openTheirs };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Task',
      new List<String>{ 'Subject' },
      null,
      null,
      null,
      null,
      null,
      25,
      'My_Open_Tasks'
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Open, mine', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsMyTeamsOpenTasksExcludesClosedAndSystemOwnedTasks() {
    User normalOwner = createTestUser('TaskNormalOwner');
    User unassignedOwner = createTestUser('Unassigned');
    User maestroOwner = createTestUser('Maestro');
    User dmsOwner = createTestUser('DMS');
    User systemsOwner = createTestUser('Systems Bot');

    List<Task> tasks = new List<Task>{
      new Task(Subject = 'Open, normal owner', Status = 'Not Started', OwnerId = normalOwner.Id),
      new Task(Subject = 'Closed, normal owner', Status = 'Completed', OwnerId = normalOwner.Id),
      new Task(Subject = 'Open, Unassigned', Status = 'Not Started', OwnerId = unassignedOwner.Id),
      new Task(Subject = 'Open, Maestro', Status = 'Not Started', OwnerId = maestroOwner.Id),
      new Task(Subject = 'Open, DMS', Status = 'Not Started', OwnerId = dmsOwner.Id),
      new Task(Subject = 'Open, Systems Bot', Status = 'Not Started', OwnerId = systemsOwner.Id)
    };
    insert tasks;

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Task',
      new List<String>{ 'Subject' },
      null,
      null,
      null,
      null,
      null,
      25,
      'My_Team_s_Open_Tasks'
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual('Open, normal owner', result.rows[0].cells[0]);
  }

  @IsTest
  static void searchRecordsCheckingInOpsOnlyReturnsNeedsReviewLogs() {
    insert new List<Check_Log__c>{
      new Check_Log__c(Status__c = 'Received', Review_Status__c = 'Needs Review'),
      new Check_Log__c(Status__c = 'Received', Review_Status__c = 'Review Complete'),
      new Check_Log__c(Status__c = 'Received')
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Check_Log__c',
      new List<String>{ 'Status__c' },
      null,
      null,
      null,
      null,
      null,
      25,
      'checking_in_ops'
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
  }

  @IsTest
  static void searchRecordsSentAndReceivedExcludesDeliveredLogs() {
    insert new List<Check_Log__c>{
      new Check_Log__c(Status__c = 'Delivered'),
      new Check_Log__c(Status__c = 'Received'),
      new Check_Log__c(Status__c = 'Sent')
    };

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Check_Log__c',
      new List<String>{ 'Status__c' },
      null,
      null,
      null,
      null,
      null,
      25,
      'Sent_and_Received_Check_Logs'
    );
    Test.stopTest();

    Assert.areEqual(2, result.rows.size());
    for (ArcRecordSearchController.SearchRow row : result.rows) {
      Assert.areNotEqual('Delivered', row.cells[0]);
    }
  }

  @IsTest
  static void searchRecordsSoslMatchStillWorksAlongsideTheRelationshipLikeSupplement() {
    Case matched = new Case(Subject = 'Matched', Status = 'New');
    Case unmatched = new Case(Subject = 'Unmatched', Status = 'New');
    insert new List<Case>{ matched, unmatched };

    // Simulates a real SOSL index hit on `matched` only -- Test methods don't
    // get a live search index, so this is the standard way to control what
    // "useSosl" sees without depending on actual index timing.
    Test.setFixedSearchResults(new List<Id>{ matched.Id });

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Case',
      new List<String>{ 'CaseNumber' },
      null,
      'anything',
      null,
      null,
      null,
      25,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual(matched.Id, result.rows[0].id);
  }

  @IsTest
  static void searchRecordsFallsBackToLikeOnARelationshipColumnSoslCannotSee() {
    // Financial_Advisor_Team_TriggerHandler.updateRepCode (unrelated,
    // pre-existing automation described on the My Team's Open Cases test
    // above) needs a team literally named 'Default Team' to exist.
    insert new Financial_Advisor_Team__c(Name = 'Default Team');

    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = 'Zenith Advisors'
    );
    insert team;

    Case teamCase = new Case(
      Subject = 'Team Case',
      Status = 'New',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;

    // SOSL only indexes fields that live on Case itself --
    // Financial_Advisor_Team__r.Name lives on the related team record, so a
    // real SOSL search would never match "Zenith" here. An authoritative,
    // empty fixed result simulates exactly that, so a match below can only
    // come from the supplemental LIKE clause, not SOSL.
    Test.setFixedSearchResults(new List<Id>());

    Test.startTest();
    ArcRecordSearchController.SearchResult result = ArcRecordSearchController.searchRecords(
      'Case',
      new List<String>{ 'CaseNumber', 'Financial_Advisor_Team__r.Name' },
      null,
      'Zenith',
      new List<String>{ 'Financial_Advisor_Team__r.Name' },
      null,
      null,
      25,
      null
    );
    Test.stopTest();

    Assert.areEqual(1, result.rows.size());
    Assert.areEqual(teamCase.Id, result.rows[0].id);
    Assert.areEqual('Zenith Advisors', result.rows[0].cells[1]);
  }

  private static Integer testUserCounter = 0;

  /** Mirrors FATMember_TriggerHandler_Test's own working pattern for a
   *  minimal, insertable test User. lastName drives Name (and so
   *  Owner.Name) exactly, since FirstName is left blank. */
  private static User createTestUser(String lastName) {
    testUserCounter++;
    User user = new User(
      // Matches FATMember_TriggerHandler_Test's own proven-working profile
      // choice -- confirmed to exist in this org.
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id,
      LastName = lastName,
      Username = 'arc.search.test' + testUserCounter + '@example.com.test',
      Email = 'arc.search.test' + testUserCounter + '@example.com',
      Alias = 'ast' + testUserCounter,
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      IsActive = true
    );
    insert user;
    return user;
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
      null,
      25,
      null
    );
  }
}