/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Aura-enabled facade for arcRecentlyViewedList.
 * Uses the RecentlyViewed object (matching Salesforce list views), enriches
 * records with household metadata, and falls back to LastViewedDate for ISA.
 */
public with sharing class ArcRecentlyViewedListController {
  private static final Integer RECENTLY_VIEWED_MAX = 200;
  private static final Integer DEFAULT_DISPLAY_LIMIT = 5;

  public static final String LIST_TYPE_CONTACT = 'Contact';
  public static final String LIST_TYPE_ISA = 'ISA';
  /*
   * "ISA" maps to the plain custom object Financial_Account__c — the object
   * the site's own nav routes, CMS detail/list views, and
   * ArcRecordDetailController actually use for viewing/browsing ISAs. The
   * FSC managed-package object FinServ__FinancialAccount__c looked like the
   * natural fit by name, but no page in this site ever renders or navigates
   * to one, so RecentlyViewed/LastViewedDate never had anything to find for
   * it — that was the actual reason this card stayed empty.
   */
  public static final String ISA_OBJECT_API_NAME = 'Financial_Account__c';
  private static final String RECENTLY_VIEWED_TYPE_ACCOUNT = 'Account';
  private static final String RECENTLY_VIEWED_TYPE_ISA = 'Financial_Account__c';

  public class RecentlyViewedItemDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String metadata;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public Datetime lastViewedDate;
  }

  public class RecentlyViewedListResult {
    @AuraEnabled
    public List<RecentlyViewedItemDTO> items;
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String title;
  }

  public class ListTypeConfig {
    public String objectApiName;
    public String title;
  }

  public class RecentlyViewedQueryResult {
    public List<SObject> records;
    public Map<Id, Datetime> lastViewedDateById;
  }

  @AuraEnabled(cacheable=true)
  public static RecentlyViewedListResult getRecentlyViewedItems(
    String listType,
    Integer displayLimit
  ) {
    RecentlyViewedListResult result = new RecentlyViewedListResult();
    result.items = new List<RecentlyViewedItemDTO>();

    ListTypeConfig config = resolveListTypeConfig(listType);
    if (config == null) {
      result.totalCount = 0;
      result.objectApiName = '';
      result.title = '';
      return result;
    }

    result.objectApiName = config.objectApiName;
    result.title = config.title;

    Integer resolvedLimit = resolveDisplayLimit(displayLimit);
    RecentlyViewedQueryResult queryResult = queryRecentlyViewedRecords(
      config.objectApiName
    );
    result.totalCount = queryResult.records.size();

    if (queryResult.records.isEmpty()) {
      return result;
    }

    List<RecentlyViewedItemDTO> allItems = deduplicateItemsById(
      buildItemsFromRecords(
        queryResult.records,
        config.objectApiName,
        queryResult.lastViewedDateById
      )
    );
    result.items = truncateItems(allItems, resolvedLimit);
    return result;
  }

  @TestVisible
  private static String resolveRecentlyViewedType(String objectApiName) {
    if (objectApiName == 'Account') {
      return RECENTLY_VIEWED_TYPE_ACCOUNT;
    }

    if (objectApiName == ISA_OBJECT_API_NAME) {
      return RECENTLY_VIEWED_TYPE_ISA;
    }

    return null;
  }

  @TestVisible
  private static List<RecentlyViewed> queryRecentlyViewedRows(
    String recentlyViewedType
  ) {
    if (String.isBlank(recentlyViewedType)) {
      return new List<RecentlyViewed>();
    }

    return [
      SELECT Id, Name, Type, LastViewedDate
      FROM RecentlyViewed
      WHERE Type = :recentlyViewedType
      WITH USER_MODE
      ORDER BY LastViewedDate DESC
      LIMIT :RECENTLY_VIEWED_MAX
    ];
  }

  @TestVisible
  private static List<RecentlyViewed> deduplicateRecentlyViewedRows(
    List<RecentlyViewed> recentlyViewedRows
  ) {
    List<RecentlyViewed> deduplicatedRows = new List<RecentlyViewed>();

    if (recentlyViewedRows == null || recentlyViewedRows.isEmpty()) {
      return deduplicatedRows;
    }

    Set<Id> seenRecordIds = new Set<Id>();

    for (RecentlyViewed recentlyViewedRow : recentlyViewedRows) {
      if (
        recentlyViewedRow?.Id == null ||
        seenRecordIds.contains(recentlyViewedRow.Id)
      ) {
        continue;
      }

      seenRecordIds.add(recentlyViewedRow.Id);
      deduplicatedRows.add(recentlyViewedRow);
    }

    return deduplicatedRows;
  }

  @TestVisible
  private static List<SObject> enrichAccountRecordsFromRecentlyViewed(
    List<RecentlyViewed> recentlyViewedRows
  ) {
    List<Id> orderedAccountIds = new List<Id>();

    if (recentlyViewedRows == null || recentlyViewedRows.isEmpty()) {
      return new List<SObject>();
    }

    Set<Id> seenAccountIds = new Set<Id>();

    for (RecentlyViewed recentlyViewedRow : recentlyViewedRows) {
      if (
        recentlyViewedRow?.Id == null ||
        seenAccountIds.contains(recentlyViewedRow.Id)
      ) {
        continue;
      }

      seenAccountIds.add(recentlyViewedRow.Id);
      orderedAccountIds.add(recentlyViewedRow.Id);
    }

    return enrichAccountRecordsByIds(orderedAccountIds);
  }

  @TestVisible
  private static List<SObject> enrichAccountRecordsByIds(
    List<Id> orderedAccountIds
  ) {
    List<SObject> orderedRecords = new List<SObject>();

    if (orderedAccountIds == null || orderedAccountIds.isEmpty()) {
      return orderedRecords;
    }

    Set<Id> accountIds = new Set<Id>(orderedAccountIds);
    Map<Id, Account> accountIdToRecord = new Map<Id, Account>(
      [
        SELECT
          Id,
          Name,
          LastViewedDate,
          Household__c,
          Household__r.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE Id IN :accountIds
        WITH USER_MODE
      ]
    );

    for (Id accountId : orderedAccountIds) {
      Account accountRecord = accountIdToRecord.get(accountId);
      if (accountRecord != null) {
        orderedRecords.add(accountRecord);
      }
    }

    return orderedRecords;
  }

  @TestVisible
  private static List<SObject> enrichFinServRecordsFromRecentlyViewed(
    List<RecentlyViewed> recentlyViewedRows
  ) {
    List<SObject> orderedRecords = new List<SObject>();

    if (recentlyViewedRows == null || recentlyViewedRows.isEmpty()) {
      return orderedRecords;
    }

    Set<Id> financialAccountIds = new Set<Id>();

    Set<Id> seenFinancialAccountIds = new Set<Id>();

    for (RecentlyViewed recentlyViewedRow : recentlyViewedRows) {
      if (
        recentlyViewedRow?.Id == null ||
        seenFinancialAccountIds.contains(recentlyViewedRow.Id)
      ) {
        continue;
      }

      seenFinancialAccountIds.add(recentlyViewedRow.Id);
      financialAccountIds.add(recentlyViewedRow.Id);
    }

    Map<Id, Financial_Account__c> financialAccountIdToRecord = new Map<Id, Financial_Account__c>(
      [
        SELECT Id, Name, LastViewedDate, Household__c, Household__r.Name
        FROM Financial_Account__c
        WHERE Id IN :financialAccountIds
        WITH USER_MODE
      ]
    );

    seenFinancialAccountIds.clear();

    for (RecentlyViewed recentlyViewedRow : recentlyViewedRows) {
      if (
        recentlyViewedRow?.Id == null ||
        seenFinancialAccountIds.contains(recentlyViewedRow.Id)
      ) {
        continue;
      }

      seenFinancialAccountIds.add(recentlyViewedRow.Id);

      Financial_Account__c financialAccount = financialAccountIdToRecord.get(
        recentlyViewedRow.Id
      );
      if (financialAccount == null) {
        continue;
      }

      orderedRecords.add(financialAccount);
    }

    return orderedRecords;
  }

  @TestVisible
  private static Map<Id, Datetime> buildLastViewedDateMap(
    List<RecentlyViewed> recentlyViewedRows
  ) {
    Map<Id, Datetime> lastViewedDateById = new Map<Id, Datetime>();

    if (recentlyViewedRows == null || recentlyViewedRows.isEmpty()) {
      return lastViewedDateById;
    }

    for (RecentlyViewed recentlyViewedRow : recentlyViewedRows) {
      if (
        recentlyViewedRow?.Id == null ||
        lastViewedDateById.containsKey(recentlyViewedRow.Id)
      ) {
        continue;
      }

      lastViewedDateById.put(
        recentlyViewedRow.Id,
        recentlyViewedRow.LastViewedDate
      );
    }

    return lastViewedDateById;
  }

  @TestVisible
  private static Map<Id, Datetime> buildLastViewedDateMapFromRecords(
    List<SObject> records
  ) {
    Map<Id, Datetime> lastViewedDateById = new Map<Id, Datetime>();

    if (records == null || records.isEmpty()) {
      return lastViewedDateById;
    }

    for (SObject record : records) {
      if (record?.Id == null) {
        continue;
      }

      lastViewedDateById.put(
        record.Id,
        (Datetime) record.get('LastViewedDate')
      );
    }

    return lastViewedDateById;
  }

  @TestVisible
  private static List<SObject> queryRecordsByLastViewedDate(
    String objectApiName
  ) {
    if (String.isBlank(objectApiName)) {
      return new List<SObject>();
    }

    if (objectApiName == 'Account') {
      return [
        SELECT
          Id,
          Name,
          LastViewedDate,
          Household__c,
          Household__r.Name,
          RecordType.DeveloperName
        FROM Account
        WHERE LastViewedDate != NULL
        WITH USER_MODE
        ORDER BY LastViewedDate DESC
        LIMIT :RECENTLY_VIEWED_MAX
      ];
    }

    if (objectApiName == ISA_OBJECT_API_NAME) {
      return [
        SELECT Id, Name, LastViewedDate, Household__c, Household__r.Name
        FROM Financial_Account__c
        WHERE LastViewedDate != NULL
        WITH USER_MODE
        ORDER BY LastViewedDate DESC
        LIMIT :RECENTLY_VIEWED_MAX
      ];
    }

    return new List<SObject>();
  }

  @TestVisible
  private static ListTypeConfig resolveListTypeConfig(String listType) {
    if (String.isBlank(listType)) {
      return null;
    }

    String normalizedListType = listType.trim();

    if (normalizedListType.equalsIgnoreCase(LIST_TYPE_CONTACT)) {
      ListTypeConfig config = new ListTypeConfig();
      config.objectApiName = 'Account';
      config.title = 'Recently Viewed Contacts';
      return config;
    }

    if (normalizedListType.equalsIgnoreCase(LIST_TYPE_ISA)) {
      ListTypeConfig config = new ListTypeConfig();
      config.objectApiName = ISA_OBJECT_API_NAME;
      config.title = 'Recently Viewed ISAs';
      return config;
    }

    return null;
  }

  @TestVisible
  private static Integer resolveDisplayLimit(Integer displayLimit) {
    if (displayLimit == null || displayLimit < 1) {
      return DEFAULT_DISPLAY_LIMIT;
    }

    return displayLimit;
  }

  @TestVisible
  private static RecentlyViewedQueryResult queryRecentlyViewedRecords(
    String objectApiName
  ) {
    RecentlyViewedQueryResult queryResult = new RecentlyViewedQueryResult();
    queryResult.records = new List<SObject>();
    queryResult.lastViewedDateById = new Map<Id, Datetime>();

    if (String.isBlank(objectApiName)) {
      return queryResult;
    }

    String recentlyViewedType = resolveRecentlyViewedType(objectApiName);
    List<RecentlyViewed> recentlyViewedRows = deduplicateRecentlyViewedRows(
      queryRecentlyViewedRows(recentlyViewedType)
    );

    if (!recentlyViewedRows.isEmpty()) {
      queryResult.lastViewedDateById = buildLastViewedDateMap(
        recentlyViewedRows
      );

      if (objectApiName == 'Account') {
        queryResult.records = enrichAccountRecordsFromRecentlyViewed(
          recentlyViewedRows
        );
        return queryResult;
      }

      if (objectApiName == ISA_OBJECT_API_NAME) {
        queryResult.records = enrichFinServRecordsFromRecentlyViewed(
          recentlyViewedRows
        );
        return queryResult;
      }
    }

    queryResult.records = deduplicateRecordsById(
      queryRecordsByLastViewedDate(objectApiName)
    );
    queryResult.lastViewedDateById = buildLastViewedDateMapFromRecords(
      queryResult.records
    );
    return queryResult;
  }

  @TestVisible
  private static List<SObject> deduplicateRecordsById(List<SObject> records) {
    List<SObject> deduplicatedRecords = new List<SObject>();

    if (records == null || records.isEmpty()) {
      return deduplicatedRecords;
    }

    Set<Id> seenRecordIds = new Set<Id>();

    for (SObject record : records) {
      if (record?.Id == null || seenRecordIds.contains(record.Id)) {
        continue;
      }

      seenRecordIds.add(record.Id);
      deduplicatedRecords.add(record);
    }

    return deduplicatedRecords;
  }

  @TestVisible
  private static List<RecentlyViewedItemDTO> buildItemsFromRecords(
    List<SObject> records,
    String objectApiName
  ) {
    return buildItemsFromRecords(
      records,
      objectApiName,
      buildLastViewedDateMapFromRecords(records)
    );
  }

  @TestVisible
  private static List<RecentlyViewedItemDTO> buildItemsFromRecords(
    List<SObject> records,
    String objectApiName,
    Map<Id, Datetime> lastViewedDateById
  ) {
    List<RecentlyViewedItemDTO> items = new List<RecentlyViewedItemDTO>();

    if (records == null || records.isEmpty()) {
      return items;
    }

    Map<Id, String> householdIdToName = queryHouseholdNamesByRecord(
      records,
      objectApiName
    );

    for (SObject record : records) {
      items.add(
        buildItemFromRecord(
          record,
          objectApiName,
          householdIdToName,
          lastViewedDateById
        )
      );
    }

    return items;
  }

  @TestVisible
  private static Map<Id, String> queryHouseholdNamesByRecord(
    List<SObject> records,
    String objectApiName
  ) {
    Map<Id, String> householdIdToName = new Map<Id, String>();

    if (records == null || records.isEmpty()) {
      return householdIdToName;
    }

    Set<Id> householdIds = new Set<Id>();

    for (SObject record : records) {
      Id householdId = resolveHouseholdId(record, objectApiName);
      if (householdId != null) {
        householdIds.add(householdId);
      }
    }

    if (householdIds.isEmpty()) {
      return householdIdToName;
    }

    for (Account household : [
      SELECT Id, Name
      FROM Account
      WHERE Id IN :householdIds
      WITH USER_MODE
    ]) {
      householdIdToName.put(household.Id, household.Name);
    }

    return householdIdToName;
  }

  @TestVisible
  private static Id resolveHouseholdId(SObject record, String objectApiName) {
    if (record == null) {
      return null;
    }

    if (objectApiName == 'Account') {
      return (Id) record.get('Household__c');
    }

    if (objectApiName == ISA_OBJECT_API_NAME) {
      return ((Financial_Account__c) record).Household__c;
    }

    return null;
  }

  @TestVisible
  private static RecentlyViewedItemDTO buildItemFromRecord(
    SObject record,
    String objectApiName
  ) {
    return buildItemFromRecord(
      record,
      objectApiName,
      queryHouseholdNamesByRecord(new List<SObject>{ record }, objectApiName),
      buildLastViewedDateMapFromRecords(new List<SObject>{ record })
    );
  }

  @TestVisible
  private static RecentlyViewedItemDTO buildItemFromRecord(
    SObject record,
    String objectApiName,
    Map<Id, String> householdIdToName
  ) {
    return buildItemFromRecord(
      record,
      objectApiName,
      householdIdToName,
      buildLastViewedDateMapFromRecords(new List<SObject>{ record })
    );
  }

  @TestVisible
  private static RecentlyViewedItemDTO buildItemFromRecord(
    SObject record,
    String objectApiName,
    Map<Id, String> householdIdToName,
    Map<Id, Datetime> lastViewedDateById
  ) {
    RecentlyViewedItemDTO item = new RecentlyViewedItemDTO();
    item.id = record.Id;
    item.name = (String) record.get('Name');
    item.lastViewedDate = lastViewedDateById?.containsKey(record.Id)
      ? lastViewedDateById.get(record.Id)
      : (Datetime) record.get('LastViewedDate');
    item.metadata = resolveHouseholdMetadata(
      record,
      objectApiName,
      householdIdToName
    );

    if (objectApiName == 'Account') {
      Account accountRecord = (Account) record;
      item.recordTypeDeveloperName = accountRecord.RecordType?.DeveloperName;
    }

    return item;
  }

  @TestVisible
  private static String resolveHouseholdMetadata(
    SObject record,
    String objectApiName
  ) {
    return resolveHouseholdMetadata(
      record,
      objectApiName,
      queryHouseholdNamesByRecord(new List<SObject>{ record }, objectApiName)
    );
  }

  @TestVisible
  private static String resolveHouseholdMetadata(
    SObject record,
    String objectApiName,
    Map<Id, String> householdIdToName
  ) {
    if (record == null) {
      return null;
    }

    if (objectApiName == 'Account') {
      String householdName = null;
      if (record.getPopulatedFieldsAsMap().containsKey('Household__r')) {
        householdName = (String) record.getSObject('Household__r')?.get('Name');
      }

      if (!String.isBlank(householdName)) {
        return householdName;
      }

      return householdIdToName.get((Id) record.get('Household__c'));
    }

    if (objectApiName == ISA_OBJECT_API_NAME) {
      Financial_Account__c financialAccount = (Financial_Account__c) record;
      String householdName = null;
      if (record.getPopulatedFieldsAsMap().containsKey('Household__r')) {
        householdName = financialAccount.Household__r?.Name;
      }
      if (!String.isBlank(householdName)) {
        return householdName;
      }

      return householdIdToName.get(financialAccount.Household__c);
    }

    return null;
  }

  @TestVisible
  private static List<RecentlyViewedItemDTO> deduplicateItemsById(
    List<RecentlyViewedItemDTO> items
  ) {
    List<RecentlyViewedItemDTO> deduplicatedItems = new List<RecentlyViewedItemDTO>();

    if (items == null || items.isEmpty()) {
      return deduplicatedItems;
    }

    Set<Id> seenItemIds = new Set<Id>();

    for (RecentlyViewedItemDTO item : items) {
      if (item?.id == null || seenItemIds.contains(item.id)) {
        continue;
      }

      seenItemIds.add(item.id);
      deduplicatedItems.add(item);
    }

    return deduplicatedItems;
  }

  @TestVisible
  private static List<RecentlyViewedItemDTO> truncateItems(
    List<RecentlyViewedItemDTO> items,
    Integer displayLimit
  ) {
    if (items == null || items.isEmpty()) {
      return new List<RecentlyViewedItemDTO>();
    }

    Integer resolvedLimit = resolveDisplayLimit(displayLimit);
    List<RecentlyViewedItemDTO> truncatedItems = new List<RecentlyViewedItemDTO>();

    for (
      Integer index = 0; index < items.size() && index < resolvedLimit; index++
    ) {
      truncatedItems.add(items[index]);
    }

    return truncatedItems;
  }
}