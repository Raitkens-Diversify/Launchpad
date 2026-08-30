/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * Fixture: one check log with two deposits under it, which is enough to prove
 * the parent filter, the dotted-path column and the field allowlist.
 *
 * No org prerequisites: Check_Log__c and Check_Deposit__c are plain custom
 * objects in this org.
 */
@IsTest
private class ArcRelatedListControllerTest {
  private static final List<String> COLUMNS = new List<String>{
    'Name',
    'Amount__c'
  };

  @TestSetup
  static void setup() {
    // Check_Deposit__c.Financial_Account__c is required, and a financial
    // account in turn requires a primary owner, so the fixture starts there.
    Account owner = new Account(Name = 'Related List Owner');
    insert owner;

    FinServ__FinancialAccount__c account = new FinServ__FinancialAccount__c(
      Name = 'Related List Account',
      FinServ__PrimaryOwner__c = owner.Id
    );
    insert account;

    Check_Log__c log = new Check_Log__c();
    insert log;

    insert new List<Check_Deposit__c>{
      new Check_Deposit__c(
        Check__c = log.Id,
        Financial_Account__c = account.Id,
        Amount__c = 100
      ),
      new Check_Deposit__c(
        Check__c = log.Id,
        Financial_Account__c = account.Id,
        Amount__c = 250
      )
    };

    // A second log with nothing under it, so the parent filter has something
    // to exclude rather than an empty table making every query look right.
    insert new Check_Log__c();
  }

  private static Check_Log__c logWithDeposits() {
    return [
      SELECT Id
      FROM Check_Log__c
      WHERE Id IN (SELECT Check__c FROM Check_Deposit__c)
      LIMIT 1
    ];
  }

  @IsTest
  static void getRelatedRecordsReturnsOnlyThisParentsChildren() {
    Check_Log__c log = logWithDeposits();

    Test.startTest();
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      COLUMNS,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      result.rows.size(),
      'Only the deposits under this check log belong on its page.'
    );
    Assert.isFalse(
      result.hasMore,
      'Two rows is under the display limit, so there is no overflow.'
    );
    Assert.areEqual(
      COLUMNS.size(),
      result.rows[0].cells.size(),
      'One cell per requested column, in order.'
    );
  }

  /** A dotted path is walked hop by hop against the object it belongs to. */
  @IsTest
  static void getRelatedRecordsResolvesRelationshipColumns() {
    Check_Log__c log = logWithDeposits();

    Test.startTest();
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      new List<String>{ 'Name', 'Financial_Account__r.Name' },
      null
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      result.rows[0].cells.size(),
      'A relationship column survives validation and is selected.'
    );
  }

  /**
   * Object and field names cannot be bind variables, so they are checked
   * against the describe and dropped rather than escaped. A path that survived
   * would reach the query and fail the whole card.
   */
  @IsTest
  static void getRelatedRecordsDropsUnknownColumns() {
    Check_Log__c log = logWithDeposits();

    Test.startTest();
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      new List<String>{ 'Name', 'No_Such_Field__c', 'No_Such__r.Name' },
      null
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      result.rows[0].cells.size(),
      'Only the real column is queried; the invented ones are dropped.'
    );
  }

  /**
   * A row can point somewhere other than itself. Files come back as
   * ContentDocumentLink rows whose own Id is the join record, which opens
   * nothing — that list navigates by ContentDocumentId instead.
   */
  @IsTest
  static void getRelatedRecordsLinksThroughTheGivenField() {
    Check_Log__c log = logWithDeposits();

    Test.startTest();
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      COLUMNS,
      'Financial_Account__c'
    );
    Test.stopTest();

    Id financialAccountId = [
      SELECT Id
      FROM FinServ__FinancialAccount__c
      WHERE Name = 'Related List Account'
      LIMIT 1
    ]
    .Id;

    Assert.areEqual(
      String.valueOf(financialAccountId),
      result.rows[0].linkId,
      'The row opens the record named by the link field, not itself.'
    );
    Assert.areEqual(
      COLUMNS.size(),
      result.rows[0].cells.size(),
      'The link field is selected for navigation, not shown as a column.'
    );
  }

  /** An unknown link field falls back to the row rather than failing. */
  @IsTest
  static void getRelatedRecordsFallsBackToTheRowsOwnId() {
    Check_Log__c log = logWithDeposits();

    Test.startTest();
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      COLUMNS,
      'Not_A_Field__c'
    );
    Test.stopTest();

    Assert.areEqual(
      String.valueOf(result.rows[0].id),
      result.rows[0].linkId,
      'A link field that does not exist leaves the row pointing at itself.'
    );
  }

  @IsTest
  static void getRelatedRecordsPadsNullValuesSoColumnsStayAligned() {
    Check_Log__c log = logWithDeposits();
    // Employee_Deferral_Amount__c is unset on the fixture deposits, so it
    // sits null between two populated columns. The LWR endpoint drops null
    // list elements from the serialized response, which would shift every
    // later cell one column left — the controller must emit '' instead.
    ArcRelatedListController.RelatedRecords result = ArcRelatedListController.getRelatedRecords(
      log.Id,
      'Check_Deposit__c',
      'Check__c',
      new List<String>{ 'Name', 'Employee_Deferral_Amount__c', 'Amount__c' },
      null
    );

    System.assertEquals(2, result.rows.size());
    for (ArcRelatedListController.RelatedRow row : result.rows) {
      System.assertEquals(3, row.cells.size(), 'One cell per column');
      System.assertEquals('', row.cells[1], 'Null value pads as empty string');
      System.assertNotEquals('', row.cells[2], 'Later columns keep their values');
    }
  }

  @IsTest
  static void getRelatedRecordsRejectsAnUnknownObject() {
    Check_Log__c log = logWithDeposits();

    Boolean threw = false;
    try {
      ArcRelatedListController.getRelatedRecords(
        log.Id,
        'Not_An_Object__c',
        'Check__c',
        COLUMNS,
        null
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(threw, 'An object that does not exist is refused.');
  }

  @IsTest
  static void getRelatedRecordsRejectsAnUnknownParentField() {
    Check_Log__c log = logWithDeposits();

    Boolean threw = false;
    try {
      ArcRelatedListController.getRelatedRecords(
        log.Id,
        'Check_Deposit__c',
        'Not_A_Field__c',
        COLUMNS,
        null
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(
      threw,
      'The parent field is concatenated into the query, so it must be known.'
    );
  }

  @IsTest
  static void getRelatedRecordsRejectsNullRecordId() {
    Boolean threw = false;
    try {
      ArcRelatedListController.getRelatedRecords(
        null,
        'Check_Deposit__c',
        'Check__c',
        COLUMNS,
        null
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(threw, 'A null record id is refused, not queried.');
  }

  /**
   * The batch takes its requests as a JSON string (a typed list nulls out on
   * the LWR endpoint — see the method's doc comment). One good request and one
   * pointing at an unknown object: the good one comes back keyed, the bad one
   * is skipped rather than blanking the batch.
   */
  @IsTest
  static void getRelatedRecordsBatchAnswersEachRequestByKey() {
    Check_Log__c log = logWithDeposits();

    String requestsJson =
      '[{"key":"deposits","objectApiName":"Check_Deposit__c",' +
      '"parentFieldApiName":"Check__c","fieldApiNames":["Name","Amount__c"]},' +
      '{"key":"broken","objectApiName":"Not_An_Object__c",' +
      '"parentFieldApiName":"Check__c","fieldApiNames":["Name"]}]';

    Test.startTest();
    Map<String, ArcRelatedListController.RelatedRecords> results = ArcRelatedListController.getRelatedRecordsBatch(
      log.Id,
      requestsJson
    );
    Test.stopTest();

    Assert.isTrue(
      results.containsKey('deposits'),
      'The valid request is answered under the key the caller chose.'
    );
    Assert.areEqual(
      2,
      results.get('deposits').rows.size(),
      'The batch runs the same query the single-card path runs.'
    );
    Assert.isFalse(
      results.containsKey('broken'),
      'A request that fails validation is skipped, not fatal to the batch.'
    );
  }

  @IsTest
  static void getRelatedRecordsBatchRefusesUnreadableJson() {
    Check_Log__c log = logWithDeposits();

    Map<String, ArcRelatedListController.RelatedRecords> emptyResults = ArcRelatedListController.getRelatedRecordsBatch(
      log.Id,
      ' '
    );
    Assert.areEqual(
      0,
      emptyResults.size(),
      'A blank request list yields an empty map, not an error.'
    );

    Boolean threw = false;
    try {
      ArcRelatedListController.getRelatedRecordsBatch(log.Id, 'not json');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(
      threw,
      'JSON that cannot be read is a caller bug worth surfacing, not an empty page.'
    );
  }
}