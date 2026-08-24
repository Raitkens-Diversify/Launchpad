/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 *
 * Repository for Account reads used by the FSC Relationship Tree.
 */
public with sharing class FscRelAccountRepository {
  private static final String ACCOUNT_LOOKUP_SELECT =
    'SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, ' +
    'PersonMailingStreet, PersonMailingCity, PersonMailingState, PersonMailingPostalCode, ' +
    'IsPersonAccount FROM Account ';

  public Account selectById(Id accountId) {
    if (accountId == null) {
      return null;
    }

    List<Account> accounts = [
      SELECT
        Id,
        Name,
        IsPersonAccount,
        PersonContactId,
        Household__c,
        RecordType.DeveloperName,
        RecordType.Name,
        Type,
        Classification__c
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    return accounts.isEmpty() ? null : accounts[0];
  }

  public String selectNameById(Id accountId) {
    Account account = selectById(accountId);
    return account == null ? null : account.Name;
  }

  public Id selectPersonContactId(String accountId) {
    if (String.isBlank(accountId)) {
      return null;
    }

    List<Account> accounts = [
      SELECT Id, PersonContactId
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    return accounts.isEmpty() ? null : accounts[0].PersonContactId;
  }

  public static Boolean isPersonAccountRecord(Account account) {
    return account != null &&
      (account.IsPersonAccount == true ||
      account.PersonContactId != null);
  }

  public static final String HOUSEHOLD_RECORD_TYPE = 'Household';
  public static final String LEGACY_HOUSEHOLD_RECORD_TYPE = 'IndustriesHousehold';

  public static Set<String> selectHouseholdRecordTypeDeveloperNames() {
    return new Set<String>{
      HOUSEHOLD_RECORD_TYPE,
      LEGACY_HOUSEHOLD_RECORD_TYPE
    };
  }

  public static Boolean isHouseholdRecordTypeDeveloperName(
    String recordTypeDeveloperName
  ) {
    if (String.isBlank(recordTypeDeveloperName)) {
      return false;
    }

    return selectHouseholdRecordTypeDeveloperNames()
      .contains(recordTypeDeveloperName.trim());
  }

  public static Id selectHouseholdRecordTypeId() {
    return selectFirstAvailableHouseholdRecordTypeId(
      new List<String>{
        HOUSEHOLD_RECORD_TYPE,
        LEGACY_HOUSEHOLD_RECORD_TYPE
      }
    );
  }

  public static Id selectHouseholdRecordTypeIdForClientHouseholdLink() {
    return selectFirstAvailableHouseholdRecordTypeId(
      new List<String>{
        LEGACY_HOUSEHOLD_RECORD_TYPE,
        HOUSEHOLD_RECORD_TYPE
      }
    );
  }

  private static Id selectFirstAvailableHouseholdRecordTypeId(
    List<String> developerNamesInPriorityOrder
  ) {
    if (developerNamesInPriorityOrder == null) {
      return null;
    }

    for (String developerName : developerNamesInPriorityOrder) {
      RecordType recordType = FscRelRecordTypeUtils.selectRecordTypeByDeveloperName(
        'Account',
        developerName
      );

      if (recordType != null) {
        return recordType.Id;
      }
    }

    return null;
  }

  public static Boolean isHouseholdRecordType(Account account) {
    if (account == null || account.RecordType == null) {
      return false;
    }

    return isHouseholdRecordTypeDeveloperName(account.RecordType.DeveloperName);
  }

  public Map<Id, Id> selectPersonAccountIdsByContactIds(Set<Id> contactIds) {
    Map<Id, Id> contactIdToAccountId = new Map<Id, Id>();

    if (contactIds == null || contactIds.isEmpty()) {
      return contactIdToAccountId;
    }

    for (Account account : [
      SELECT Id, PersonContactId
      FROM Account
      WHERE PersonContactId IN :contactIds AND IsPersonAccount = TRUE
    ]) {
      contactIdToAccountId.put(account.PersonContactId, account.Id);
    }

    return contactIdToAccountId;
  }

  public List<Account> selectByIds(Set<Id> accountIds) {
    return selectAccountsByIdsWithClassifications(accountIds);
  }

  public List<Account> searchAccountsByName(
    String searchTerm,
    Boolean personAccountsOnly,
    Integer limitSize
  ) {
    return queryAccountsByNameSearch(
      searchTerm,
      personAccountsOnly,
      null,
      limitSize
    );
  }

  public List<Account> searchAccountsByNameInIds(
    String searchTerm,
    Boolean personAccountsOnly,
    Set<Id> allowedAccountIds,
    Integer limitSize
  ) {
    if (allowedAccountIds == null || allowedAccountIds.isEmpty()) {
      return new List<Account>();
    }

    return queryAccountsByNameSearch(
      searchTerm,
      personAccountsOnly,
      allowedAccountIds,
      limitSize
    );
  }

  public List<Account> selectPersonAccountsByIds(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account>();
    }

    return [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        PersonMailingStreet,
        PersonMailingCity,
        PersonMailingState,
        PersonMailingPostalCode,
        IsPersonAccount
      FROM Account
      WHERE Id IN :accountIds AND IsPersonAccount = TRUE
      ORDER BY Name
    ];
  }

  public List<Account> selectAccountsByHouseholdId(Id householdId) {
    if (householdId == null) {
      return new List<Account>();
    }

    return [
      SELECT
        Id,
        Name,
        Type,
        IsPersonAccount,
        PersonContactId,
        RecordType.DeveloperName,
        RecordType.Name,
        Classification__c
      FROM Account
      WHERE Household__c = :householdId
      ORDER BY Name
    ];
  }

  public List<Account> searchAccountsByClassification(
    String searchTerm,
    String classificationValue,
    Integer limitSize
  ) {
    if (String.isBlank(classificationValue)) {
      return new List<Account>();
    }

    if (String.isBlank(searchTerm)) {
      return new List<Account>();
    }

    String trimmedTerm = searchTerm.trim();
    if (trimmedTerm.length() < 2) {
      return new List<Account>();
    }

    Integer safeLimit = limitSize == null ||
      limitSize < 1
      ? 8
      : Math.min(limitSize, 25);
    List<String> tokens = FscRelNameSearchUtils.tokenizeSearchTerm(trimmedTerm);

    if (tokens.isEmpty()) {
      return new List<Account>();
    }

    Integer queryLimit = FscRelNameSearchUtils.resolveSearchQueryLimit(
      tokens,
      safeLimit
    );
    String nameWhereClause = FscRelNameSearchUtils.buildPersonNameTokenWhereClause(
      tokens
    );
    String safeClassification = String.escapeSingleQuotes(classificationValue);
    List<Account> accounts = Database.query(
      'SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, ' +
        'PersonMailingStreet, PersonMailingCity, PersonMailingState, PersonMailingPostalCode, ' +
        'IsPersonAccount, Classification__c ' +
        'FROM Account ' +
        'WHERE (' +
        nameWhereClause +
        ') AND Household__c = NULL AND Classification__c INCLUDES (\'' +
        safeClassification +
        '\') ' +
        'ORDER BY Name ' +
        'LIMIT ' +
        queryLimit
    );

    if (queryLimit > safeLimit) {
      accounts = FscRelNameSearchUtils.rankAccountsByNameTokens(
        accounts,
        tokens,
        safeLimit
      );
    }

    return accounts;
  }

  private List<Account> queryAccountsByNameSearch(
    String searchTerm,
    Boolean personAccountsOnly,
    Set<Id> allowedAccountIds,
    Integer limitSize
  ) {
    if (String.isBlank(searchTerm)) {
      return new List<Account>();
    }

    String trimmedTerm = searchTerm.trim();
    if (trimmedTerm.length() < 2) {
      return new List<Account>();
    }

    Integer safeLimit = limitSize == null ||
      limitSize < 1
      ? 8
      : Math.min(limitSize, 25);
    List<String> tokens = FscRelNameSearchUtils.tokenizeSearchTerm(trimmedTerm);

    if (tokens.isEmpty()) {
      return new List<Account>();
    }

    Integer queryLimit = FscRelNameSearchUtils.resolveSearchQueryLimit(
      tokens,
      safeLimit
    );
    Boolean resolvedPersonAccountsOnly = personAccountsOnly == true;
    String nameWhereClause = resolvedPersonAccountsOnly
      ? FscRelNameSearchUtils.buildPersonNameTokenWhereClause(tokens)
      : FscRelNameSearchUtils.buildNameTokenWhereClause(tokens);
    String whereClause =
      'IsPersonAccount = ' +
      (resolvedPersonAccountsOnly ? 'true' : 'false') +
      ' AND (' +
      nameWhereClause +
      ')';
    List<Account> accounts;

    if (allowedAccountIds != null && !allowedAccountIds.isEmpty()) {
      whereClause = 'Id IN :allowedAccountIds AND ' + whereClause;
      accounts = Database.query(
        ACCOUNT_LOOKUP_SELECT +
          'WHERE ' +
          whereClause +
          ' ORDER BY Name LIMIT :queryLimit'
      );
    } else {
      accounts = Database.query(
        ACCOUNT_LOOKUP_SELECT +
          'WHERE ' +
          whereClause +
          ' ORDER BY Name LIMIT ' +
          queryLimit
      );
    }

    if (queryLimit > safeLimit) {
      accounts = FscRelNameSearchUtils.rankAccountsByNameTokens(
        accounts,
        tokens,
        safeLimit
      );
    }

    return accounts;
  }

  public void updateHouseholdLink(Id accountId, Id householdId) {
    if (accountId == null || householdId == null) {
      return;
    }

    update new Account(Id = accountId, Household__c = householdId);
  }

  public List<Account> selectAccountsByIdsWithClassifications(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account>();
    }

    return [
      SELECT
        Id,
        Name,
        Type,
        IsPersonAccount,
        PersonContactId,
        RecordType.DeveloperName,
        RecordType.Name,
        Classification__c
      FROM Account
      WHERE Id IN :accountIds
      ORDER BY Name
    ];
  }

  public List<Account> selectClientAccountsByHouseholdId(Id householdId) {
    List<Account> clientAccounts = new List<Account>();

    for (Account account : selectMemberAccountsFromHouseholdMembership(householdId)) {
      if (FscRelClientAccountUtils.isClientAccount(account)) {
        clientAccounts.add(account);
      }
    }

    return clientAccounts;
  }

  public List<Account> selectLeadProspectAccountsByHouseholdId(Id householdId) {
    List<Account> leadProspectAccounts = new List<Account>();

    for (Account account : selectMemberAccountsFromHouseholdMembership(householdId)) {
      if (FscRelClientAccountUtils.isLeadProspectAccount(account)) {
        leadProspectAccounts.add(account);
      }
    }

    return leadProspectAccounts;
  }

  public Id selectHouseholdIdByMemberAccountId(Id memberAccountId) {
    if (memberAccountId == null) {
      return null;
    }

    for (
      Account_Account_Relationship__c relation : FscRelAccountRelationVisibilityService.selectReadableHouseholdMembershipByMemberAccountId(
        memberAccountId
      )
    ) {
      if (
        relation.Account__r != null &&
        isHouseholdRecordType(relation.Account__r)
      ) {
        return relation.Account__c;
      }
    }

    return null;
  }

  public List<Account> selectMemberAccountsByHouseholdId(Id householdId) {
    return selectMemberAccountsFromHouseholdMembership(householdId);
  }

  private List<Account> selectMemberAccountsFromHouseholdMembership(Id householdId) {
    return mapHouseholdMembershipRelationsToAccounts(
      FscRelAccountRelationVisibilityService.selectReadableHouseholdMembershipByHouseholdId(
        householdId
      )
    );
  }

  private List<Account> mapHouseholdMembershipRelationsToAccounts(
    List<Account_Account_Relationship__c> relations
  ) {
    Map<Id, Account> accountIdToAccount = new Map<Id, Account>();

    if (relations == null || relations.isEmpty()) {
      return new List<Account>();
    }

    for (Account_Account_Relationship__c relation : relations) {
      if (
        relation.Related_Account__c != null &&
        relation.Related_Account__r != null &&
        !accountIdToAccount.containsKey(relation.Related_Account__c)
      ) {
        accountIdToAccount.put(
          relation.Related_Account__c,
          relation.Related_Account__r
        );
      }
    }

    List<Account> memberAccounts = accountIdToAccount.values();
    memberAccounts.sort();

    return memberAccounts;
  }

  public Map<Id, Integer> selectClientAccountCountsByHouseholdIds(
    Set<Id> householdIds
  ) {
    Map<Id, Integer> householdIdToCount = new Map<Id, Integer>();

    if (householdIds == null || householdIds.isEmpty()) {
      return householdIdToCount;
    }

    for (Id householdId : householdIds) {
      householdIdToCount.put(householdId, 0);
    }

    for (Id householdId : householdIds) {
      for (Account account : selectMemberAccountsFromHouseholdMembership(householdId)) {
        if (!FscRelClientAccountUtils.isClientAccount(account)) {
          continue;
        }

        householdIdToCount.put(
          householdId,
          householdIdToCount.get(householdId) + 1
        );
      }
    }

    return householdIdToCount;
  }
}