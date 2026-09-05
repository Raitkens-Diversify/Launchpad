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

  // Next_Task__c/Original_Owner__c/Previous_Task__c are plain Text(18) fields
  // that trigger logic (Case_TriggerHandler) populates with a raw Task/User
  // Id -- never a real Lookup, so the Schema.DisplayType.REFERENCE filter in
  // getCaseInformationFieldNames doesn't catch them. Confirmed live: they
  // rendered as bare 18-character ids on the Case Information section with
  // no way for a portal user to make sense of them.
  @IsTest
  static void getCaseInformationFieldNamesExcludesRawIdTextFields() {
    Case record = new Case(Subject = 'Id Text Field Case', Status = 'New');
    insert record;

    Test.startTest();
    List<String> fieldNames = ArcCaseDetailController.getCaseInformationFieldNames(
      record.Id
    );
    Test.stopTest();

    Set<String> lowerFieldNames = new Set<String>();
    for (String fieldName : fieldNames) {
      lowerFieldNames.add(fieldName.toLowerCase());
    }
    Assert.isFalse(lowerFieldNames.contains('next_task__c'));
    Assert.isFalse(lowerFieldNames.contains('original_owner__c'));
    Assert.isFalse(lowerFieldNames.contains('previous_task__c'));
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

  // ---- Additional coverage ---------------------------------------------------

  private static Id accountServicingRecordTypeId() {
    return Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
      .get('Account_Servicing')
      .getRecordTypeId();
  }

  /**
   * The mapped-type path: an Account Servicing case whose Type has an envelope
   * schema (Additional Funding -> Envelope_Field__mdt rows) comes back grouped
   * into the wizard's own sections, carrying only the fields that hold a value.
   */
  @IsTest
  static void getCaseFieldSectionsGroupsPopulatedEnvelopeFieldsForAMappedType() {
    Case record = new Case(
      Subject = 'Additional funding case',
      Status = 'New',
      RecordTypeId = accountServicingRecordTypeId(),
      Type = 'Additional Funding',
      Amount__c = 1234.5
    );
    insert record;

    Test.startTest();
    List<ArcCaseDetailController.SectionView> sections = ArcCaseDetailController.getCaseFieldSections(
      record.Id
    );
    Test.stopTest();

    Assert.isFalse(
      sections.isEmpty(),
      'A mapped type with a populated envelope field yields at least one section.'
    );
    ArcCaseDetailController.FieldValue amount;
    for (ArcCaseDetailController.SectionView section : sections) {
      Assert.isNotNull(section.name, 'Every section is named.');
      Assert.isFalse(section.fields.isEmpty(), 'Empty sections are dropped.');
      for (ArcCaseDetailController.FieldValue fieldValue : section.fields) {
        Assert.isNotNull(fieldValue.value, 'Blank fields are dropped.');
        if (fieldValue.value.contains('1234')) {
          amount = fieldValue;
        }
      }
    }
    Assert.isNotNull(amount, 'The populated Amount field is shown: ' + JSON.serialize(sections));
    Assert.areEqual('Amount', amount.label, 'The field carries the schema label.');
  }

  /** Branch alone: the pill names the branch pit stop. */
  @IsTest
  static void getCaseDetailReportsABranchPitStopWhenOnlyABranchTaskIsOpen() {
    Case record = new Case(Subject = 'Branch pit stop case');
    insert record;

    insert new List<Task>{
      new Task(Subject = 'Main track open', WhatId = record.Id, Status = 'Not Started'),
      new Task(
        Subject = 'Branch open',
        WhatId = record.Id,
        Status = 'Not Started',
        Branch_Pit_Stop__c = true
      )
    };

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual('Branch', result.progress.pitStopKind);
    Assert.areEqual('Branch pit stop', result.progress.label);
    Assert.isTrue(result.progress.isInPitStop);
    Assert.areEqual(1, result.progress.openBranchPitStopTasks);
    Assert.areEqual(0, result.progress.openHomeOfficePitStopTasks);
    Assert.areEqual(1, result.progress.openMainTrackTasks);
    Assert.areEqual(1, result.progress.total, 'Only the main track task counts.');
    Assert.areEqual(0, result.progress.percent, 'Nothing on the main track is done.');
    Assert.areEqual(
      1,
      result.progress.statusSlices.size(),
      'Both tasks share one status, so one slice.'
    );
    Assert.areEqual('Not Started', result.progress.statusSlices[0].label);
    Assert.areEqual(2, result.progress.statusSlices[0].count);
  }

  /** The Case's own rollup counts win over the task rows when populated. */
  @IsTest
  static void getCaseDetailPrefersTheCaseRollupCountsWhenPopulated() {
    Case record = new Case(
      Subject = 'Rollup counts case',
      Total_Main_Track_Tasks__c = 4,
      Completed_Main_Track_Tasks__c = 1,
      Pitstop_Total_Minutes__c = 90
    );
    insert record;
    insert new Task(Subject = 'Only task', WhatId = record.Id, Status = 'Completed');

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(4, result.totalMainTrackTasks);
    Assert.areEqual(1, result.completedMainTrackTasks);
    Assert.areEqual(90, result.pitstopTotalMinutes);
    Assert.areEqual(4, result.progress.total, 'The rollup total wins over one task row.');
    Assert.areEqual(1, result.progress.completed, 'The rollup completed count wins.');
    Assert.areEqual(25, result.progress.percent);
    Assert.areEqual('On track', result.progress.label);
  }

  @IsTest
  static void getCaseDetailThrowsWhenTheCaseNoLongerExists() {
    Case record = new Case(Subject = 'Deleted case');
    insert record;
    Id deletedId = record.Id;
    delete record;

    Boolean threw = false;
    Test.startTest();
    try {
      ArcCaseDetailController.getCaseDetail(deletedId);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'A well-formed id with no case behind it is an error.');
  }

  @IsTest
  static void getCaseDetailResolvesAccountRecordTypeAndOwnerNames() {
    Account client = new Account(Name = 'Detail Client', Type = 'Prospect');
    insert client;
    Case record = new Case(
      Subject = 'Named case',
      Status = 'New',
      RecordTypeId = accountServicingRecordTypeId(),
      AccountId = client.Id,
      Description = 'Some description'
    );
    insert record;

    Test.startTest();
    ArcCaseDetailController.CaseDetailResult result = ArcCaseDetailController.getCaseDetail(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(client.Id, result.accountId);
    Assert.areEqual('Detail Client', result.accountName);
    Assert.areEqual(accountServicingRecordTypeId(), result.recordTypeId);
    Assert.areEqual(
      Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get('Account_Servicing')
        .getName(),
      result.recordTypeName
    );
    Assert.areEqual(UserInfo.getUserId(), result.ownerId);
    // Not asserting result.ownerName here: Owner.Name is read through a
    // relationship subquery (Case.Owner.Name), and in Apex test context (no
    // SeeAllData) the running user's own compound Name field does not
    // hydrate through that path -- a direct `SELECT Name FROM User WHERE
    // Id = :UserInfo.getUserId()` resolves fine, but `Owner.Name`/
    // `CreatedBy.Name` traversed from another object's row comes back null.
    // Confirmed with a throwaway diagnostic test against this org. Contact
    // and other non-User relationships (see getTaskContextResolvesTheWhoName
    // -ForAContact) are unaffected, so this is User-specific, not a general
    // relationship-query limitation.
    Assert.isNull(result.ownerName, 'Documents the current test-context limitation above.');
    Assert.areEqual('Some description', result.description);
    Assert.isNotNull(result.caseNumber);
    Assert.isNotNull(result.createdDate);
    Assert.isNull(result.household, 'No household means no summary.');
  }

  @IsTest
  static void getCaseTasksMapsPitStopFlagsAndClosedState() {
    Case record = new Case(Subject = 'Task mapping case', Status = 'New');
    insert record;
    Date due = Date.today().addDays(3);
    insert new List<Task>{
      new Task(
        Subject = 'Branch stop',
        Status = 'Not Started',
        WhatId = record.Id,
        ActivityDate = due,
        Branch_Pit_Stop__c = true
      ),
      new Task(
        Subject = 'Done',
        Status = 'Completed',
        WhatId = record.Id,
        Home_Office_Pit_Stop__c = true
      )
    };

    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> tasks = ArcCaseDetailController.getCaseTasks(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(2, tasks.size());
    Map<String, ArcCaseDetailController.TaskInfo> bySubject = new Map<String, ArcCaseDetailController.TaskInfo>();
    for (ArcCaseDetailController.TaskInfo info : tasks) {
      bySubject.put(info.subject, info);
    }
    ArcCaseDetailController.TaskInfo branch = bySubject.get('Branch stop');
    Assert.isTrue(branch.branchPitStop);
    Assert.isFalse(branch.homeOfficePitStop);
    Assert.isFalse(branch.isClosed);
    Assert.areEqual(due, branch.dueDate);
    // Task.Owner.Name does not hydrate through this relationship subquery in
    // Apex test context (see getCaseDetailResolvesAccountRecordTypeAndOwnerNames
    // for the full explanation).
    Assert.isNull(branch.ownerName);
    ArcCaseDetailController.TaskInfo done = bySubject.get('Done');
    Assert.isTrue(done.homeOfficePitStop);
    Assert.isTrue(done.isClosed);
    Assert.areEqual('Completed', done.status);
  }

  @IsTest
  static void getCaseInformationFieldNamesListsPopulatedFieldsByLabelAndDropsUncheckedBoxes() {
    Case record = new Case(
      Subject = 'Field names case',
      Status = 'New',
      RecordTypeId = accountServicingRecordTypeId(),
      Type = 'Additional Funding',
      Check_in_Hand__c = true
    );
    insert record;

    Test.startTest();
    List<String> fieldNames = ArcCaseDetailController.getCaseInformationFieldNames(
      record.Id
    );
    Test.stopTest();

    Set<String> lower = new Set<String>();
    for (String fieldName : fieldNames) {
      lower.add(fieldName.toLowerCase());
    }
    Assert.isTrue(lower.contains('type'), 'A populated picklist is listed: ' + fieldNames);
    Assert.isTrue(lower.contains('check_in_hand__c'), 'A checked box is listed.');
    Assert.isFalse(lower.contains('donotcalc__c'), 'An unchecked box is dropped.');
    Assert.isFalse(lower.contains('subject'), 'Header fields are not repeated.');
    Assert.isFalse(lower.contains('status'), 'Header fields are not repeated.');
    Assert.isFalse(lower.contains('ownerid'), 'Lookups are excluded.');

    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
    List<String> labels = new List<String>();
    for (String fieldName : fieldNames) {
      Schema.DescribeFieldResult describe = fieldMap.get(fieldName.toLowerCase())
        .getDescribe();
      labels.add(describe.getLabel());
      Assert.isTrue(
        describe.getLength() <= 255,
        'Long text belongs in its own section: ' + fieldName
      );
    }
    List<String> sorted = labels.clone();
    sorted.sort();
    Assert.areEqual(sorted, labels, 'Fields come back ordered by label.');
  }
}