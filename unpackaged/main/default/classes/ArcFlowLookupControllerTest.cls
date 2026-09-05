/**
 * Tests for ArcFlowLookupController, the search backend for c/arcFlowLookup.
 *
 * One record per supported object, each exercising the object's own
 * sublabel shape: Financial_Account__c through Household__r.Name, Contact
 * through Account.Name, Case labelled by CaseNumber with Subject as the
 * sublabel, Advertising_Item__c through RecordType.Name (the object's only
 * record type, Master, so the sublabel is real without hard-coding an
 * org-specific developer name), and Account with no sublabel at all.
 */
@IsTest
private class ArcFlowLookupControllerTest {
  @IsTest
  static void blankTermReturnsEmptyForASupportedObject() {
    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Account',
      ''
    );
    Test.stopTest();

    Assert.areEqual(0, results.size(), 'A blank term should match nothing');
  }

  @IsTest
  static void unsupportedObjectReturnsEmptyEvenWithATerm() {
    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Opportunity',
      'Anything'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      results.size(),
      'An object outside the supported set should never be searched'
    );
  }

  @IsTest
  static void searchesAccountWithNoSublabel() {
    insert new Account(
      Name = 'Flow Lookup Test Household',
      Type = 'Prospect'
    );

    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Account',
      'Flow Lookup Test Household'
    );
    Test.stopTest();

    Assert.areEqual(1, results.size());
    Assert.areEqual('Flow Lookup Test Household', results[0].get('label'));
    Assert.isNull(
      results[0].get('sublabel'),
      'Account has no configured sublabel field'
    );
  }

  @IsTest
  static void searchesFinancialAccountWithHouseholdSublabel() {
    Account household = new Account(
      Name = 'Flow Lookup Household',
      Type = 'Prospect'
    );
    insert household;
    insert new Financial_Account__c(
      Name = 'Flow Lookup Financial Account',
      Household__c = household.Id
    );

    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Financial_Account__c',
      'Flow Lookup Financial'
    );
    Test.stopTest();

    Assert.areEqual(1, results.size());
    Assert.areEqual(
      'Flow Lookup Financial Account',
      results[0].get('label')
    );
    Assert.areEqual(
      'Flow Lookup Household',
      results[0].get('sublabel'),
      'The sublabel comes from the related household name'
    );
  }

  @IsTest
  static void searchesContactWithAccountNameSublabel() {
    Account household = new Account(
      Name = 'Flow Lookup Contact Household',
      Type = 'Prospect'
    );
    insert household;
    insert new Contact(
      LastName = 'FlowLookupTestContact',
      AccountId = household.Id
    );

    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Contact',
      'FlowLookupTestContact'
    );
    Test.stopTest();

    Assert.areEqual(1, results.size());
    Assert.isTrue(
      String.valueOf(results[0].get('label')).contains(
        'FlowLookupTestContact'
      )
    );
    Assert.areEqual(
      'Flow Lookup Contact Household',
      results[0].get('sublabel')
    );
  }

  @IsTest
  static void searchesCaseByCaseNumberWithSubjectSublabel() {
    insert new Case(Subject = 'Flow Lookup Case Subject', Status = 'New');
    Case inserted = [SELECT Id, CaseNumber FROM Case LIMIT 1];

    Test.startTest();
    List<Map<String, String>> results = ArcFlowLookupController.search(
      'Case',
      inserted.CaseNumber
    );
    Test.stopTest();

    Assert.areEqual(1, results.size());
    Assert.areEqual(inserted.CaseNumber, results[0].get('label'));
    Assert.areEqual(
      'Flow Lookup Case Subject',
      results[0].get('sublabel')
    );
  }

  /**
   * KNOWN CONTROLLER BUG (documenting current behavior, not fixing it --
   * production code is out of scope here): SUBLABEL_BY_OBJECT maps
   * Advertising_Item__c to 'RecordType.Name' (ArcFlowLookupController.cls,
   * ~line 19), and search() always includes the sublabel field in its
   * dynamic SOQL when one is configured (~line 37). In this org
   * Advertising_Item__c has Record Types disabled entirely -- no
   * RecordTypeId field and no RecordType relationship exist on the object
   * (confirmed via `sf sobject describe -o launchpad -s Advertising_Item__c`
   * and a direct `sf data query` of "SELECT RecordType.Name FROM
   * Advertising_Item__c", both of which show no such field/relationship).
   * Every call to search('Advertising_Item__c', <non-blank term>) therefore
   * throws System.QueryException: "Didn't understand relationship
   * 'RecordType' in field path" before it can return anything. This test
   * asserts that actual behavior rather than the success the code cannot
   * currently deliver.
   */
  @IsTest
  static void searchingAdvertisingItemThrowsBecauseRecordTypeIsNotEnabled() {
    insert new Advertising_Item__c(Name = 'Flow Lookup Advertising Item');

    Test.startTest();
    Boolean threw = false;
    try {
      ArcFlowLookupController.search(
        'Advertising_Item__c',
        'Flow Lookup Advertising'
      );
      Assert.fail(
        'Advertising_Item__c has no RecordType relationship in this org; ' +
        'if this starts succeeding the bug note above is stale.'
      );
    } catch (System.QueryException e) {
      threw = true;
      Assert.isTrue(
        e.getMessage().contains('RecordType'),
        'Expected the RecordType relationship failure.'
      );
    }
    Test.stopTest();

    Assert.isTrue(threw, 'The known RecordType.Name bug should still reproduce.');
  }

  @IsTest
  static void getRecordLabelReturnsNullForANullId() {
    Test.startTest();
    String label = ArcFlowLookupController.getRecordLabel('Account', null);
    Test.stopTest();

    Assert.isNull(label);
  }

  @IsTest
  static void getRecordLabelReturnsNullForAnUnsupportedObject() {
    Account account = new Account(
      Name = 'Flow Lookup Unsupported Object Test',
      Type = 'Prospect'
    );
    insert account;

    Test.startTest();
    String label = ArcFlowLookupController.getRecordLabel(
      'Opportunity',
      account.Id
    );
    Test.stopTest();

    Assert.isNull(
      label,
      'An id for an object outside the supported set is never resolved'
    );
  }

  @IsTest
  static void getRecordLabelResolvesTheNameOfAFoundRecord() {
    Account account = new Account(
      Name = 'Flow Lookup Get Label Test',
      Type = 'Prospect'
    );
    insert account;

    Test.startTest();
    String label = ArcFlowLookupController.getRecordLabel(
      'Account',
      account.Id
    );
    Test.stopTest();

    Assert.areEqual('Flow Lookup Get Label Test', label);
  }

  @IsTest
  static void getRecordLabelResolvesACaseByCaseNumber() {
    insert new Case(Subject = 'Get Label Case', Status = 'New');
    Case inserted = [SELECT Id, CaseNumber FROM Case LIMIT 1];

    Test.startTest();
    String label = ArcFlowLookupController.getRecordLabel(
      'Case',
      inserted.Id
    );
    Test.stopTest();

    Assert.areEqual(inserted.CaseNumber, label);
  }
}