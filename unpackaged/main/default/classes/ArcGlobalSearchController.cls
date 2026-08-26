/**
 * ArcGlobalSearchController
 *
 * Live-typeahead backing for the global header search box (arcHeaderSearch).
 * One multi-object SOSL pass returns a category-grouped, capped preview
 * matching the Figma "Autosuggest" spec: tabs with per-category counts,
 * grouped result rows (title + subtitle), and a total count for the
 * "Showing X of Y results" footer.
 *
 * Conventions mirror ArcKnowledgeController.typeahead: `with sharing` +
 * explicit isAccessible() guards, cacheable Apex, lightweight DTOs capped to
 * a small per-category preview so the dropdown stays fast while the user
 * types.
 */
public with sharing class ArcGlobalSearchController {
  private static final Integer MAX_PER_CATEGORY = 3; // dropdown preview rows per category
  private static final Integer SOSL_LIMIT = 50; // per-object SOSL cap (drives the count badge)
  private static final Integer MIN_TERM_LENGTH = 2;

  public class SearchResultItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public String objectApiName;
  }

  public class CategoryGroup {
    @AuraEnabled
    public String key; // stable id for the tab, e.g. 'work'
    @AuraEnabled
    public String label; // tab/section label, e.g. 'Work'
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public List<SearchResultItem> items;
    public CategoryGroup(String key, String label) {
      this.key = key;
      this.label = label;
      this.items = new List<SearchResultItem>();
      this.totalCount = 0;
    }
  }

  public class SearchSuggestions {
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public List<CategoryGroup> categories;
    @AuraEnabled
    public String normalizedTerm; // sanitized term, for client-side match highlighting
    public SearchSuggestions() {
      this.totalCount = 0;
      this.categories = new List<CategoryGroup>();
    }
  }

  /**
   * Category definitions, in tab display order. Each maps 1:1 to an SObject
   * currently searched; add an entry here (and a RETURNING clause below) to
   * extend to another object/tab later.
   */
  private static final String KEY_CONTACTS = 'contacts';
  private static final String KEY_WORK = 'work';
  private static final String KEY_ACCOUNTS = 'accounts';
  private static final String KEY_COMPLIANCE = 'compliance';

  /** Dropdown preview: capped to MAX_PER_CATEGORY rows per category. */
  @AuraEnabled(cacheable=true)
  public static SearchSuggestions typeahead(String term) {
    return recall(term, MAX_PER_CATEGORY);
  }

  /** Full results page: every recalled row per category (up to SOSL_LIMIT), not just a preview. */
  @AuraEnabled(cacheable=true)
  public static SearchSuggestions fullSearch(String term) {
    return recall(term, SOSL_LIMIT);
  }

  /** Shared recall: one federated SOSL pass (+ a SOQL pass for the one
   * object that doesn't support SOSL), grouped by category and capped to
   * maxPerCategory rows each. */
  private static SearchSuggestions recall(String term, Integer maxPerCategory) {
    SearchSuggestions result = new SearchSuggestions();

    result.categories.add(new CategoryGroup(KEY_WORK, 'Work'));
    result.categories.add(new CategoryGroup(KEY_CONTACTS, 'Contacts'));
    result.categories.add(new CategoryGroup(KEY_ACCOUNTS, 'Accounts'));
    result.categories.add(new CategoryGroup(KEY_COMPLIANCE, 'Compliance'));

    String cleanTerm = sanitizeSearch(term);
    result.normalizedTerm = cleanTerm;
    if (cleanTerm.length() < MIN_TERM_LENGTH) {
      return result;
    }

    // Compliance_Exception__c and Financial_Account__c both have Search
    // disabled at the object level (enableSearch=false) in this org — an
    // object-wide setting we shouldn't flip just for this feature, so both
    // are recalled via a plain SOQL LIKE query instead of SOSL. A SOSL
    // FIND...RETURNING clause naming a non-searchable object throws
    // "entity type X does not support search" and aborts the whole
    // federated pass, which is why Financial_Account__c must be excluded
    // from it entirely, not just guarded by object accessibility.
    // Everything else supports SOSL and shares one federated recall pass.
    //
    // Leading + trailing wildcard so a term matches anywhere in the field
    // (contains), not just at the start of a word — e.g. "cme" still finds
    // "Acme Test Account".
    String findExpr = '*' + cleanTerm + '*';
    String sosl =
      'FIND \'' +
      findExpr +
      '\' IN ALL FIELDS RETURNING ' +
      'Account(Id, Name, Type LIMIT ' +
      SOSL_LIMIT +
      '), ' +
      'Case(Id, CaseNumber, Subject, Status LIMIT ' +
      SOSL_LIMIT +
      ')';

    List<List<SObject>> searchResults;
    try {
      searchResults = Search.query(sosl);
    } catch (QueryException e) {
      AuraHandledException ahe = new AuraHandledException(
        'Search failed: ' + e.getMessage()
      );
      ahe.setMessage('Search failed: ' + e.getMessage());
      throw ahe;
    }

    populateGroup(
      result.categories[0],
      casesAccessible() ? searchResults[1] : new List<SObject>(),
      'Case',
      maxPerCategory
    );
    populateGroup(
      result.categories[1],
      accountsAccessible() ? searchResults[0] : new List<SObject>(),
      'Account',
      maxPerCategory
    );
    if (financialAccountsAccessible()) {
      populateGroup(
        result.categories[2],
        queryFinancialAccounts(cleanTerm),
        'Financial_Account__c',
        maxPerCategory
      );
    }
    if (complianceAccessible()) {
      populateGroup(
        result.categories[3],
        queryComplianceExceptions(cleanTerm),
        'Compliance_Exception__c',
        maxPerCategory
      );
    }

    for (CategoryGroup g : result.categories) {
      result.totalCount += g.totalCount;
    }
    return result;
  }

  /** Fill in a category's capped rows, plus the full recalled count for its tab/section badge. */
  private static void populateGroup(
    CategoryGroup grp,
    List<SObject> rows,
    String objectApiName,
    Integer maxPerCategory
  ) {
    grp.totalCount = rows.size();
    for (Integer i = 0; i < rows.size() && i < maxPerCategory; i++) {
      grp.items.add(toItem(rows[i], objectApiName));
    }
  }

  private static SearchResultItem toItem(SObject row, String objectApiName) {
    SearchResultItem item = new SearchResultItem();
    item.id = (Id) row.get('Id');
    item.objectApiName = objectApiName;
    if (objectApiName == 'Account') {
      item.title = (String) row.get('Name');
      item.subtitle = (String) row.get('Type');
    } else if (objectApiName == 'Case') {
      item.title = (String) row.get('Subject');
      String caseNumber = (String) row.get('CaseNumber');
      String status = (String) row.get('Status');
      item.subtitle = String.isNotBlank(caseNumber)
        ? caseNumber + (String.isNotBlank(status) ? ' • ' + status : '')
        : status;
    } else if (objectApiName == 'Financial_Account__c') {
      item.title = (String) row.get('Name');
      item.subtitle = (String) row.get('Financial_Account_Type__c');
    } else if (objectApiName == 'Compliance_Exception__c') {
      item.title = (String) row.get('Name');
      item.subtitle = (String) row.get('Exception_Reason__c');
    }
    return item;
  }

  private static Boolean accountsAccessible() {
    return Schema.sObjectType.Account.isAccessible();
  }

  private static Boolean casesAccessible() {
    return Schema.sObjectType.Case.isAccessible();
  }

  private static Boolean financialAccountsAccessible() {
    return Schema.sObjectType.Financial_Account__c.isAccessible();
  }

  private static Boolean complianceAccessible() {
    return Schema.sObjectType.Compliance_Exception__c.isAccessible();
  }

  /**
   * Name-prefix/contains recall for Compliance_Exception__c, which doesn't
   * support SOSL (enableSearch=false on the object). cleanTerm is already
   * stripped to [a-zA-Z0-9 ], so there are no LIKE wildcards/quotes to
   * escape in it.
   */
  private static List<SObject> queryComplianceExceptions(String cleanTerm) {
    String likeTerm = '%' + cleanTerm + '%';
    return [
      SELECT Id, Name, Exception_Reason__c
      FROM Compliance_Exception__c
      WHERE Name LIKE :likeTerm
      LIMIT :SOSL_LIMIT
    ];
  }

  /**
   * Name-contains recall for Financial_Account__c, which doesn't support
   * SOSL in this org (enableSearch=false on the object). Same pattern as
   * queryComplianceExceptions.
   */
  private static List<SObject> queryFinancialAccounts(String cleanTerm) {
    String likeTerm = '%' + cleanTerm + '%';
    return [
      SELECT Id, Name, Financial_Account_Type__c
      FROM Financial_Account__c
      WHERE Name LIKE :likeTerm
      LIMIT :SOSL_LIMIT
    ];
  }

  /**
   * Make a user term safe to inline into a SOSL FIND clause by stripping
   * everything except alphanumerics and spaces — removes SOSL reserved
   * characters and quotes entirely, so there's nothing to inject with.
   * Mirrors ArcKnowledgeController.sanitizeSearch.
   */
  private static String sanitizeSearch(String input) {
    if (input == null) {
      return '';
    }
    return input.replaceAll('[^a-zA-Z0-9 ]', ' ').trim();
  }
}