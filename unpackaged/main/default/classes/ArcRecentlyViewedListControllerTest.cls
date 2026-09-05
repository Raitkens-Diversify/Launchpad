/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class ArcRecentlyViewedListControllerTest {
  @IsTest
  static void resolveRecentlyViewedType_mapsAccountAndIsaTypes() {
    System.assertEquals(
      'Account',
      ArcRecentlyViewedListController.resolveRecentlyViewedType('Account')
    );
    System.assertEquals(
      'Financial_Account__c',
      ArcRecentlyViewedListController.resolveRecentlyViewedType(
        ArcRecentlyViewedListController.ISA_OBJECT_API_NAME
      )
    );
    System.assertEquals(
      null,
      ArcRecentlyViewedListController.resolveRecentlyViewedType('Unknown')
    );
  }

  @IsTest
  static void enrichAccountRecordsByIds_preservesOrder() {
    Account firstAccount = createPersonAccount(
      'First',
      'Account'
    );
    Account secondAccount = createPersonAccount(
      'Second',
      'Account'
    );

    List<SObject> enrichedRecords = ArcRecentlyViewedListController.enrichAccountRecordsByIds(
      new List<Id>{ secondAccount.Id, firstAccount.Id }
    );

    System.assertEquals(2, enrichedRecords.size());
    System.assertEquals(secondAccount.Id, enrichedRecords[0].Id);
    System.assertEquals(firstAccount.Id, enrichedRecords[1].Id);
  }

  @IsTest
  static void deduplicateRecentlyViewedRows_returnsEmptyListForNullOrEmptyInput() {
    System.assertEquals(
      0,
      ArcRecentlyViewedListController.deduplicateRecentlyViewedRows(null).size()
    );
    System.assertEquals(
      0,
      ArcRecentlyViewedListController.deduplicateRecentlyViewedRows(
          new List<RecentlyViewed>()
        )
        .size()
    );
  }

  @IsTest
  static void resolveListTypeConfig_mapsContactAndIsaModes() {
    ArcRecentlyViewedListController.ListTypeConfig contactConfig = ArcRecentlyViewedListController.resolveListTypeConfig(
      ArcRecentlyViewedListController.LIST_TYPE_CONTACT
    );
    ArcRecentlyViewedListController.ListTypeConfig isaConfig = ArcRecentlyViewedListController.resolveListTypeConfig(
      ArcRecentlyViewedListController.LIST_TYPE_ISA
    );

    System.assertEquals('Account', contactConfig.objectApiName);
    System.assertEquals('Recently Viewed Contacts', contactConfig.title);

    System.assertEquals(
      ArcRecentlyViewedListController.ISA_OBJECT_API_NAME,
      isaConfig.objectApiName
    );
    System.assertEquals('Recently Viewed Investments & Services', isaConfig.title);
  }

  @IsTest
  static void resolveListTypeConfig_returnsNullForUnknownType() {
    System.assertEquals(
      null,
      ArcRecentlyViewedListController.resolveListTypeConfig('Unknown')
    );
    System.assertEquals(
      null,
      ArcRecentlyViewedListController.resolveListTypeConfig(null)
    );
  }

  @IsTest
  static void resolveDisplayLimit_defaultsToFiveWhenInvalid() {
    System.assertEquals(
      5,
      ArcRecentlyViewedListController.resolveDisplayLimit(null)
    );
    System.assertEquals(
      5,
      ArcRecentlyViewedListController.resolveDisplayLimit(0)
    );
    System.assertEquals(
      3,
      ArcRecentlyViewedListController.resolveDisplayLimit(3)
    );
  }

  @IsTest
  static void deduplicateRecordsById_returnsEmptyListForNullOrEmptyInput() {
    System.assertEquals(
      0,
      ArcRecentlyViewedListController.deduplicateRecordsById(null).size()
    );
    System.assertEquals(
      0,
      ArcRecentlyViewedListController.deduplicateRecordsById(
          new List<SObject>()
        )
        .size()
    );
  }

  @IsTest
  static void buildItemFromRecord_includesHouseholdMetadataForAccounts() {
    Account household = createIsaHouseholdAccount(
      'Recently Viewed Household'
    );
    Account memberAccount = createPersonAccount(
      'Sarah',
      'Harrison'
    );
    memberAccount.Household__c = household.Id;
    update memberAccount;

    memberAccount = [
      SELECT
        Id,
        Name,
        LastViewedDate,
        Household__c,
        Household__r.Name,
        RecordType.DeveloperName
      FROM Account
      WHERE Id = :memberAccount.Id
    ];

    ArcRecentlyViewedListController.RecentlyViewedItemDTO item = ArcRecentlyViewedListController.buildItemFromRecord(
      memberAccount,
      'Account'
    );

    System.assertEquals(memberAccount.Id, item.id);
    System.assertEquals(memberAccount.Name, item.name);
    System.assertEquals(household.Name, item.metadata);
    System.assertEquals(
      memberAccount.RecordType.DeveloperName,
      item.recordTypeDeveloperName
    );
  }

  @IsTest
  static void buildItemFromRecord_includesHouseholdMetadataForFinancialAccounts() {
    Account household = createIsaHouseholdAccount('ISA Household');
    Financial_Account__c financialAccount = createIsaFinancialAccount(
      'Harrison Dental 401(k) Plan',
      household.Id
    );

    ArcRecentlyViewedListController.RecentlyViewedItemDTO item = ArcRecentlyViewedListController.buildItemFromRecord(
      financialAccount,
      ArcRecentlyViewedListController.ISA_OBJECT_API_NAME,
      new Map<Id, String>{ household.Id => household.Name }
    );

    System.assertEquals(financialAccount.Id, item.id);
    System.assertEquals(household.Name, item.metadata);
    System.assertEquals(null, item.recordTypeDeveloperName);
  }

  @IsTest
  static void truncateItems_limitsDisplayedRows() {
    List<ArcRecentlyViewedListController.RecentlyViewedItemDTO> items = new List<ArcRecentlyViewedListController.RecentlyViewedItemDTO>();

    for (Integer index = 0; index < 6; index++) {
      ArcRecentlyViewedListController.RecentlyViewedItemDTO item = new ArcRecentlyViewedListController.RecentlyViewedItemDTO();
      item.id = UserInfo.getUserId();
      item.name = 'Item ' + index;
      items.add(item);
    }

    List<ArcRecentlyViewedListController.RecentlyViewedItemDTO> truncatedItems = ArcRecentlyViewedListController.truncateItems(
      items,
      5
    );

    System.assertEquals(5, truncatedItems.size());
    System.assertEquals('Item 0', truncatedItems[0].name);
    System.assertEquals('Item 4', truncatedItems[4].name);
  }

  @IsTest
  static void resolveHouseholdMetadata_returnsIsaHouseholdName() {
    Account household = createIsaHouseholdAccount('Resolver Household');
    Financial_Account__c financialAccount = createIsaFinancialAccount(
      'Resolver ISA',
      household.Id
    );

    System.assertEquals(
      household.Name,
      ArcRecentlyViewedListController.resolveHouseholdMetadata(
        financialAccount,
        ArcRecentlyViewedListController.ISA_OBJECT_API_NAME,
        new Map<Id, String>{ household.Id => household.Name }
      )
    );
  }

  @IsTest
  static void queryRecentlyViewedRecords_returnsAccountRowsFromFallbackQuery() {
    ArcRecentlyViewedListController.RecentlyViewedQueryResult queryResult = ArcRecentlyViewedListController.queryRecentlyViewedRecords(
      'Account'
    );

    System.assertNotEquals(null, queryResult.records);
    System.assertNotEquals(null, queryResult.lastViewedDateById);
  }

  @IsTest
  static void buildItemsFromRecords_appliesLastViewedDateOverride() {
    Account memberAccount = createPersonAccount(
      'Override',
      'Account'
    );
    Datetime viewedDate = Datetime.newInstance(2026, 8, 12, 3, 23, 50);
    Map<Id, Datetime> lastViewedDateById = new Map<Id, Datetime>{
      memberAccount.Id => viewedDate
    };

    memberAccount = [
      SELECT Id, Name, LastViewedDate, Household__c, RecordType.DeveloperName
      FROM Account
      WHERE Id = :memberAccount.Id
    ];

    List<ArcRecentlyViewedListController.RecentlyViewedItemDTO> items = ArcRecentlyViewedListController.buildItemsFromRecords(
      new List<SObject>{ memberAccount },
      'Account',
      lastViewedDateById
    );

    System.assertEquals(1, items.size());
    System.assertEquals(viewedDate, items[0].lastViewedDate);
  }

  @IsTest
  static void enrichFinServRecordsFromRecentlyViewed_returnsEmptyListForNullInput() {
    System.assertEquals(
      0,
      ArcRecentlyViewedListController.enrichFinServRecordsFromRecentlyViewed(
          null
        )
        .size()
    );
  }

  @IsTest
  static void buildLastViewedDateMapFromRecords_mapsRecordIdsToDates() {
    Account memberAccount = createPersonAccount(
      'Date',
      'Map'
    );
    memberAccount = [
      SELECT Id, LastViewedDate
      FROM Account
      WHERE Id = :memberAccount.Id
    ];

    Map<Id, Datetime> lastViewedDateById = ArcRecentlyViewedListController.buildLastViewedDateMapFromRecords(
      new List<SObject>{ memberAccount }
    );

    System.assertEquals(1, lastViewedDateById.size());
    System.assertEquals(
      memberAccount.LastViewedDate,
      lastViewedDateById.get(memberAccount.Id)
    );
  }

  @IsTest
  static void queryRecentlyViewedRecords_returnsFinancialAccountRows() {
    Account household = createIsaHouseholdAccount('Query Household');
    createIsaFinancialAccount('Query Test ISA', household.Id);

    List<SObject> records = ArcRecentlyViewedListController.queryRecentlyViewedRecords(
        ArcRecentlyViewedListController.ISA_OBJECT_API_NAME
      )
      .records;

    System.assertNotEquals(null, records);
  }

  @IsTest
  static void getRecentlyViewedItems_returnsEmptyResultForUnknownListType() {
    ArcRecentlyViewedListController.RecentlyViewedListResult result = ArcRecentlyViewedListController.getRecentlyViewedItems(
      'Unsupported',
      5
    );

    System.assertEquals(0, result.totalCount);
    System.assertEquals(true, result.items.isEmpty());
    System.assertEquals('', result.objectApiName);
    System.assertEquals('', result.title);
  }

  @IsTest
  static void getRecentlyViewedItems_returnsConfiguredResultForContactMode() {
    ArcRecentlyViewedListController.RecentlyViewedListResult result = ArcRecentlyViewedListController.getRecentlyViewedItems(
      ArcRecentlyViewedListController.LIST_TYPE_CONTACT,
      5
    );

    System.assertEquals('Account', result.objectApiName);
    System.assertEquals('Recently Viewed Contacts', result.title);
    System.assertNotEquals(null, result.items);
    System.assert(result.totalCount >= 0);
    System.assert(result.items.size() <= 5);
  }

  @IsTest
  static void getRecentlyViewedItems_returnsConfiguredResultForIsaMode() {
    ArcRecentlyViewedListController.RecentlyViewedListResult result = ArcRecentlyViewedListController.getRecentlyViewedItems(
      ArcRecentlyViewedListController.LIST_TYPE_ISA,
      5
    );

    System.assertEquals(
      ArcRecentlyViewedListController.ISA_OBJECT_API_NAME,
      result.objectApiName
    );
    System.assertEquals('Recently Viewed Investments & Services', result.title);
    System.assertNotEquals(null, result.items);
    System.assert(result.totalCount >= 0);
    System.assert(result.items.size() <= 5);
  }

  private static RecentlyViewed buildRecentlyViewedRow(
    Id recordId,
    Datetime lastViewedDate
  ) {
    RecentlyViewed recentlyViewedRow = new RecentlyViewed();
    recentlyViewedRow.put('Id', recordId);
    recentlyViewedRow.put('LastViewedDate', lastViewedDate);
    return recentlyViewedRow;
  }

  @IsTest
  static void deduplicateRecentlyViewedRows_removesDuplicateRecordIds() {
    Account account = createPersonAccount(
      'Duplicate',
      'Account'
    );
    Datetime mostRecentView = Datetime.newInstance(2026, 8, 12, 16, 0, 0);
    Datetime olderView = Datetime.newInstance(2026, 8, 11, 16, 0, 0);

    List<RecentlyViewed> recentlyViewedRows = new List<RecentlyViewed>{
      buildRecentlyViewedRow(account.Id, mostRecentView),
      buildRecentlyViewedRow(account.Id, olderView)
    };

    List<RecentlyViewed> deduplicatedRows = ArcRecentlyViewedListController.deduplicateRecentlyViewedRows(
      recentlyViewedRows
    );

    System.assertEquals(1, deduplicatedRows.size());
    System.assertEquals(account.Id, deduplicatedRows[0].Id);
    System.assertEquals(mostRecentView, deduplicatedRows[0].LastViewedDate);
  }

  @IsTest
  static void deduplicateRecordsById_removesDuplicateRecords() {
    Account account = createPersonAccount(
      'Duplicate',
      'Record'
    );
    account = [
      SELECT Id, Name, LastViewedDate
      FROM Account
      WHERE Id = :account.Id
    ];

    List<SObject> deduplicatedRecords = ArcRecentlyViewedListController.deduplicateRecordsById(
      new List<SObject>{ account, account }
    );

    System.assertEquals(1, deduplicatedRecords.size());
    System.assertEquals(account.Id, deduplicatedRecords[0].Id);
  }

  @IsTest
  static void deduplicateItemsById_removesDuplicateItems() {
    Account account = createPersonAccount(
      'Duplicate',
      'Item'
    );
    ArcRecentlyViewedListController.RecentlyViewedItemDTO firstItem = new ArcRecentlyViewedListController.RecentlyViewedItemDTO();
    firstItem.id = account.Id;
    firstItem.name = 'First';

    ArcRecentlyViewedListController.RecentlyViewedItemDTO duplicateItem = new ArcRecentlyViewedListController.RecentlyViewedItemDTO();
    duplicateItem.id = account.Id;
    duplicateItem.name = 'Duplicate';

    List<ArcRecentlyViewedListController.RecentlyViewedItemDTO> deduplicatedItems = ArcRecentlyViewedListController.deduplicateItemsById(
      new List<ArcRecentlyViewedListController.RecentlyViewedItemDTO>{
        firstItem,
        duplicateItem
      }
    );

    System.assertEquals(1, deduplicatedItems.size());
    System.assertEquals('First', deduplicatedItems[0].name);
  }

  @IsTest
  static void getRecentlyViewedItems_returnsUniqueItemIdsForContactMode() {
    ArcRecentlyViewedListController.RecentlyViewedListResult result = ArcRecentlyViewedListController.getRecentlyViewedItems(
      ArcRecentlyViewedListController.LIST_TYPE_CONTACT,
      200
    );

    Set<Id> seenItemIds = new Set<Id>();

    for (
      ArcRecentlyViewedListController.RecentlyViewedItemDTO item : result.items
    ) {
      System.assert(
        !seenItemIds.contains(item.id),
        'Duplicate recently viewed contact id returned: ' + item.id
      );
      seenItemIds.add(item.id);
    }
  }

  @IsTest
  static void getRecentlyViewedItems_returnsUniqueItemIdsForIsaMode() {
    ArcRecentlyViewedListController.RecentlyViewedListResult result = ArcRecentlyViewedListController.getRecentlyViewedItems(
      ArcRecentlyViewedListController.LIST_TYPE_ISA,
      200
    );

    Set<Id> seenItemIds = new Set<Id>();

    for (
      ArcRecentlyViewedListController.RecentlyViewedItemDTO item : result.items
    ) {
      System.assert(
        !seenItemIds.contains(item.id),
        'Duplicate recently viewed ISA id returned: ' + item.id
      );
      seenItemIds.add(item.id);
    }
  }

  @IsTest
  static void enrichAccountRecordsFromRecentlyViewed_skipsDuplicateRecentlyViewedRows() {
    Account account = createPersonAccount(
      'Duplicate',
      'Enrich'
    );
    List<RecentlyViewed> recentlyViewedRows = new List<RecentlyViewed>{
      buildRecentlyViewedRow(account.Id, Datetime.now()),
      buildRecentlyViewedRow(account.Id, Datetime.now().addDays(-1))
    };

    List<SObject> enrichedRecords = ArcRecentlyViewedListController.enrichAccountRecordsFromRecentlyViewed(
      recentlyViewedRows
    );

    System.assertEquals(1, enrichedRecords.size());
    System.assertEquals(account.Id, enrichedRecords[0].Id);
  }

  /**
   * Local stand-in for FscDataTestDataFactory.createPersonAccount. The Account
   * validation rule Type_OR_Classification_Required (active since 2026-08-20)
   * rejects a person account that carries neither Type nor Classification__c,
   * and the git copy of the shared factory predates that rule. Building the
   * account here keeps this test passing whichever factory version is deployed.
   */
  private static Account createPersonAccount(String firstName, String lastName) {
    List<RecordType> personRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];
    System.assert(
      !personRecordTypes.isEmpty(),
      'A person account record type is required to run this test.'
    );
    Account personAccount = new Account(
      FirstName = firstName,
      LastName = lastName,
      RecordTypeId = personRecordTypes[0].Id,
      Type = 'Prospect'
    );
    insert personAccount;
    return [
      SELECT Id, Name, IsPersonAccount, PersonContactId, Classification__c
      FROM Account
      WHERE Id = :personAccount.Id
      LIMIT 1
    ];
  }

  private static Account createIsaHouseholdAccount(String name) {
    Id householdRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName()
      .get('Household')
      .getRecordTypeId();
    Account household = new Account(
      Name = name,
      RecordTypeId = householdRecordTypeId
    );
    insert household;
    return household;
  }

  private static Financial_Account__c createIsaFinancialAccount(
    String name,
    Id householdId
  ) {
    Financial_Account__c financialAccount = new Financial_Account__c(
      Name = name,
      Household__c = householdId
    );
    insert financialAccount;

    return [
      SELECT Id, Name, LastViewedDate, Household__c, Household__r.Name
      FROM Financial_Account__c
      WHERE Id = :financialAccount.Id
    ];
  }
}