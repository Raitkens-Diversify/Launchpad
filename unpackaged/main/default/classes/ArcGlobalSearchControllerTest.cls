/**
 * Tests for ArcGlobalSearchController.
 *
 * SOSL can't see records inserted in the same test transaction (the search
 * index isn't updated synchronously), so Test.setFixedSearchResults mocks the
 * multi-object recall deterministically — same pattern as
 * ArcKnowledgeControllerTest's SOSL tests.
 */
@IsTest
private class ArcGlobalSearchControllerTest {
  @TestSetup
  static void setup() {
    insert new Account(Name = 'Acme Test Account', Type = 'Prospect');
    insert new Case(Subject = 'Test Case Subject', Status = 'New');
    insert new Task(Subject = 'Test Task Subject', Status = 'Open');
    // Name is an auto-number (CL-######), so it can't be set here.
    insert new Check_Log__c(Status__c = 'Received');

    // The site's financial-account pages are built on the DFPG custom object,
    // which is what search recalls; see ArcGlobalSearchController.
    insert new Financial_Account__c(Name = 'Test Financial Account');

    insert new Compliance_Exception__c(
      Name = 'Test Compliance Exception',
      Exception_Reason__c = 'Other'
    );
  }

  @IsTest
  static void blankTermReturnsEmpty() {
    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      ''
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.totalCount,
      'Blank term should return no results'
    );
    System.assertEquals(
      4,
      result.categories.size(),
      'All four category groups should still be present, just empty'
    );
    for (ArcGlobalSearchController.CategoryGroup g : result.categories) {
      System.assertEquals(0, g.totalCount);
      System.assertEquals(0, g.items.size());
    }
  }

  @IsTest
  static void tooShortTermReturnsEmpty() {
    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      'a'
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.totalCount,
      'A single-character term should not trigger a search'
    );
  }

  @IsTest
  static void groupsResultsByCategoryWithCorrectTitlesAndSubtitles() {
    Account acc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Acme Test Account'
      LIMIT 1
    ];
    Case cs = [SELECT Id FROM Case LIMIT 1];
    Task tsk = [SELECT Id FROM Task LIMIT 1];
    Check_Log__c checkLog = [SELECT Id, Name FROM Check_Log__c LIMIT 1];
    Financial_Account__c fa = [
      SELECT Id
      FROM Financial_Account__c
      LIMIT 1
    ];

    // Compliance_Exception__c has Search disabled at the object level, so
    // it's recalled via a plain SOQL LIKE query (which does see this
    // transaction's inserts) rather than mocked SOSL results.
    Test.setFixedSearchResults(
      new List<Id>{ acc.Id, cs.Id, tsk.Id, checkLog.Id, fa.Id }
    );

    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      'Test'
    );
    Test.stopTest();

    System.assertEquals(
      6,
      result.totalCount,
      'One account, one financial account, one compliance exception, and three Work rows (case + task + check log)'
    );

    Map<String, ArcGlobalSearchController.CategoryGroup> byKey = new Map<String, ArcGlobalSearchController.CategoryGroup>();
    for (ArcGlobalSearchController.CategoryGroup g : result.categories) {
      byKey.put(g.key, g);
    }

    System.assertEquals(1, byKey.get('contacts').totalCount);
    System.assertEquals(
      'Acme Test Account',
      byKey.get('contacts').items[0].title
    );
    System.assertEquals('Prospect', byKey.get('contacts').items[0].subtitle);
    System.assertEquals(
      'Account',
      byKey.get('contacts').items[0].objectApiName
    );

    // Work merges Case + Task + Check_Log__c, interleaved case-first.
    System.assertEquals(3, byKey.get('work').totalCount);
    System.assertEquals('Test Case Subject', byKey.get('work').items[0].title);
    System.assert(byKey.get('work').items[0].subtitle.contains('New'));
    System.assertEquals('Case', byKey.get('work').items[0].objectApiName);

    System.assertEquals('Test Task Subject', byKey.get('work').items[1].title);
    System.assertEquals('Task • Open', byKey.get('work').items[1].subtitle);
    System.assertEquals('Task', byKey.get('work').items[1].objectApiName);

    System.assertEquals(checkLog.Name, byKey.get('work').items[2].title);
    System.assertEquals(
      'Check Log • Received',
      byKey.get('work').items[2].subtitle
    );
    System.assertEquals(
      'Check_Log__c',
      byKey.get('work').items[2].objectApiName
    );

    System.assertEquals(1, byKey.get('accounts').totalCount);
    System.assertEquals(
      'Test Financial Account',
      byKey.get('accounts').items[0].title
    );

    System.assertEquals(1, byKey.get('compliance').totalCount);
    System.assertEquals(
      'Test Compliance Exception',
      byKey.get('compliance').items[0].title
    );
    System.assertEquals('Other', byKey.get('compliance').items[0].subtitle);
  }

  @IsTest
  static void workPreviewInterleavesSoCasesCannotCrowdOutOtherTypes() {
    List<Case> extras = new List<Case>();
    for (Integer i = 0; i < 4; i++) {
      extras.add(new Case(Subject = 'Extra Test Case ' + i, Status = 'New'));
    }
    insert extras;

    List<Id> ids = new List<Id>();
    for (Case c : [SELECT Id FROM Case]) {
      ids.add(c.Id);
    }
    Task tsk = [SELECT Id FROM Task LIMIT 1];
    ids.add(tsk.Id);
    Test.setFixedSearchResults(ids);

    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      'Test'
    );
    Test.stopTest();

    ArcGlobalSearchController.CategoryGroup work;
    for (ArcGlobalSearchController.CategoryGroup g : result.categories) {
      if (g.key == 'work') {
        work = g;
      }
    }
    System.assertEquals(6, work.totalCount, 'Five cases plus one task');
    System.assertEquals(3, work.items.size(), 'Preview stays capped at 3');
    System.assertEquals(
      'Task',
      work.items[1].objectApiName,
      'The task must appear in the preview even though cases outnumber it'
    );
  }

  @IsTest
  static void capsPreviewRowsPerCategoryButKeepsFullCount() {
    List<Account> extras = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      extras.add(new Account(Name = 'Extra Test Account ' + i, Type = 'Prospect', Classification__c = 'Unclassified'));
    }
    insert extras;

    List<Id> ids = new List<Id>();
    for (Account a : [SELECT Id FROM Account]) {
      ids.add(a.Id);
    }
    Test.setFixedSearchResults(ids);

    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      'Test'
    );
    Test.stopTest();

    ArcGlobalSearchController.CategoryGroup contacts;
    for (ArcGlobalSearchController.CategoryGroup g : result.categories) {
      if (g.key == 'contacts') {
        contacts = g;
      }
    }
    // Counted from the fixture rather than hard-coded: the number of Accounts
    // the setup happens to leave behind is not what this test is about.
    System.assertEquals(
      ids.size(),
      contacts.totalCount,
      'Full recall count should not be capped'
    );
    System.assertEquals(
      3,
      contacts.items.size(),
      'Preview rows should be capped at 3'
    );
  }

  @IsTest
  static void fullSearchReturnsEveryRowNotJustAPreview() {
    List<Account> extras = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      extras.add(new Account(Name = 'Extra Test Account ' + i, Type = 'Prospect', Classification__c = 'Unclassified'));
    }
    insert extras;

    List<Id> ids = new List<Id>();
    for (Account a : [SELECT Id FROM Account]) {
      ids.add(a.Id);
    }
    Test.setFixedSearchResults(ids);

    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.fullSearch(
      'Test'
    );
    Test.stopTest();

    ArcGlobalSearchController.CategoryGroup contacts;
    for (ArcGlobalSearchController.CategoryGroup g : result.categories) {
      if (g.key == 'contacts') {
        contacts = g;
      }
    }
    System.assertEquals(ids.size(), contacts.totalCount);
    System.assertEquals(
      ids.size(),
      contacts.items.size(),
      'fullSearch should not cap rows at the dropdown preview limit'
    );
  }
}