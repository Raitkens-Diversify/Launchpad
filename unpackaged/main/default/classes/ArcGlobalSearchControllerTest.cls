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
    insert new Account(Name = 'Acme Test Account', Type = 'Household');
    insert new Case(Subject = 'Test Case Subject', Status = 'New');

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
    Financial_Account__c fa = [
      SELECT Id
      FROM Financial_Account__c
      LIMIT 1
    ];

    // Compliance_Exception__c has Search disabled at the object level, so
    // it's recalled via a plain SOQL LIKE query (which does see this
    // transaction's inserts) rather than mocked SOSL results.
    Test.setFixedSearchResults(new List<Id>{ acc.Id, cs.Id, fa.Id });

    Test.startTest();
    ArcGlobalSearchController.SearchSuggestions result = ArcGlobalSearchController.typeahead(
      'Test'
    );
    Test.stopTest();

    System.assertEquals(
      4,
      result.totalCount,
      'One matching record per category'
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
    System.assertEquals('Household', byKey.get('contacts').items[0].subtitle);
    System.assertEquals(
      'Account',
      byKey.get('contacts').items[0].objectApiName
    );

    System.assertEquals(1, byKey.get('work').totalCount);
    System.assertEquals('Test Case Subject', byKey.get('work').items[0].title);
    System.assert(byKey.get('work').items[0].subtitle.contains('New'));

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
  static void capsPreviewRowsPerCategoryButKeepsFullCount() {
    List<Account> extras = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      extras.add(new Account(Name = 'Extra Test Account ' + i));
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
      extras.add(new Account(Name = 'Extra Test Account ' + i));
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