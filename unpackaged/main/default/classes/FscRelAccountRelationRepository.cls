/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 *
 * Repository for Account_Account_Relationship__c reads and writes.
 */
public with sharing class FscRelAccountRelationRepository {
  private static final String MEMBER_RELATION_FIELDS =
    'Id, Account__c, Account__r.Name, Account__r.IsPersonAccount, Related_Account__c, Related_Account__r.Name, Related_Account__r.IsPersonAccount, ' +
    'Reciprocal_Role__c, Reciprocal_Role__r.Role__c, Reciprocal_Role__r.Name, ' +
    'Inverse_Reciprocal_Role__c, Inverse_Reciprocal_Role__r.Role__c, Inverse_Reciprocal_Role__r.Name, ' +
    'RecordTypeId, RecordType.DeveloperName, Active__c';

  private static final String HOUSEHOLD_MEMBERSHIP_FIELDS =
    'Id, Account__c, Account__r.Name, Account__r.IsPersonAccount, Account__r.RecordType.DeveloperName, Account__r.RecordType.Name, ' +
    'Related_Account__c, Related_Account__r.Name, Related_Account__r.Type, Related_Account__r.IsPersonAccount, Related_Account__r.PersonContactId, ' +
    'Related_Account__r.RecordType.DeveloperName, Related_Account__r.RecordType.Name, Related_Account__r.Classification__c, ' +
    'Roles__c, Association_Type__c, RecordTypeId, RecordType.DeveloperName, Active__c';

  public List<Account_Account_Relationship__c> selectByRootAccount(Id rootAccountId) {
    if (rootAccountId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    return [
      SELECT
        Id,
        Roles__c,
        Association_Type__c,
        Related_Account__c,
        Related_Account__r.Name,
        Related_Account__r.IsPersonAccount,
        Related_Account__r.RecordType.DeveloperName,
        Related_Account__r.RecordType.Name,
        Related_Account__r.Type
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :rootAccountId
        AND (RecordType.DeveloperName != :FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE OR RecordTypeId = NULL)
      ORDER BY Related_Account__r.Name
    ];
  }

  public List<Account_Account_Relationship__c> selectHouseholdMembershipByHouseholdId(
    Id householdId
  ) {
    if (householdId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    String householdRecordTypeDeveloperName = FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE;

    return Database.query(
      'SELECT ' +
        HOUSEHOLD_MEMBERSHIP_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c = :householdId AND RecordType.DeveloperName = :householdRecordTypeDeveloperName AND Active__c = TRUE AND Related_Account__c != NULL ORDER BY Related_Account__r.Name'
    );
  }

  public List<Account_Account_Relationship__c> selectHouseholdMembershipByMemberAccountId(
    Id memberAccountId
  ) {
    if (memberAccountId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    String householdRecordTypeDeveloperName = FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE;

    return Database.query(
      'SELECT ' +
        HOUSEHOLD_MEMBERSHIP_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Related_Account__c = :memberAccountId AND RecordType.DeveloperName = :householdRecordTypeDeveloperName AND Active__c = TRUE AND Account__c != NULL ORDER BY Account__r.Name'
    );
  }

  public List<Account_Account_Relationship__c> selectByAccountAndRecordType(
    Id memberAccountId,
    Id recordTypeId
  ) {
    if (memberAccountId == null || recordTypeId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    return Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c = :memberAccountId AND RecordTypeId = :recordTypeId ORDER BY Related_Account__r.Name'
    );
  }

  public List<Account_Account_Relationship__c> selectByAccountIds(Set<Id> accountIds) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    return Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c IN :accountIds ORDER BY Related_Account__r.Name'
    );
  }

  public Account_Account_Relationship__c selectByAccountRelatedAccountAndRecordType(
    Id accountId,
    Id relatedAccountId,
    Id recordTypeId
  ) {
    if (accountId == null || relatedAccountId == null || recordTypeId == null) {
      return null;
    }

    List<Account_Account_Relationship__c> relations = Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c = :accountId AND Related_Account__c = :relatedAccountId AND RecordTypeId = :recordTypeId LIMIT 1'
    );

    return relations.isEmpty() ? null : relations[0];
  }

  public Account_Account_Relationship__c selectByRootAccountAndRelatedAccount(
    Id rootAccountId,
    Id relatedAccountId
  ) {
    if (rootAccountId == null || relatedAccountId == null) {
      return null;
    }

    List<Account_Account_Relationship__c> relations = [
      SELECT Id, Roles__c, Association_Type__c, Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE Account__c = :rootAccountId AND Related_Account__c = :relatedAccountId
      LIMIT 1
    ];

    return relations.isEmpty() ? null : relations[0];
  }

  public List<Account_Account_Relationship__c> selectByRelatedAccountAndRecordType(
    Id relatedAccountId,
    Id recordTypeId
  ) {
    if (relatedAccountId == null || recordTypeId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    return Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Related_Account__c = :relatedAccountId AND RecordTypeId = :recordTypeId AND Active__c = TRUE ORDER BY Account__r.Name'
    );
  }

  public Set<Id> selectRelatedAccountIdsByMemberAccountIds(Set<Id> memberAccountIds) {
    Set<Id> relatedAccountIds = new Set<Id>();

    if (memberAccountIds == null || memberAccountIds.isEmpty()) {
      return relatedAccountIds;
    }

    for (Account_Account_Relationship__c relation : [
      SELECT Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE Account__c IN :memberAccountIds AND Related_Account__c != NULL
    ]) {
      relatedAccountIds.add(relation.Related_Account__c);
    }

    return relatedAccountIds;
  }

  public List<Account_Account_Relationship__c> selectByRelatedAccountIds(
    Set<Id> relatedAccountIds
  ) {
    if (relatedAccountIds == null || relatedAccountIds.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    return Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Related_Account__c IN :relatedAccountIds AND Active__c = TRUE ORDER BY Account__r.Name'
    );
  }

  public Map<String, Integer> selectActiveExpansionCountsByAccountIds(Set<Id> accountIds) {
    Map<String, Integer> accountIdToCount = new Map<String, Integer>();

    if (accountIds == null || accountIds.isEmpty()) {
      return accountIdToCount;
    }

    Map<Id, Set<String>> accountIdToRelatedAccountKeys = new Map<Id, Set<String>>();

    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c, RecordTypeId
      FROM Account_Account_Relationship__c
      WHERE
        (Account__c IN :accountIds OR Related_Account__c IN :accountIds)
        AND Active__c = TRUE
    ]) {
      if (relation.Account__c != null && accountIds.contains(relation.Account__c)) {
        addExpansionCountKey(
          accountIdToRelatedAccountKeys,
          relation.Account__c,
          relation.Related_Account__c,
          relation.RecordTypeId
        );
      }

      if (
        relation.Related_Account__c != null &&
        accountIds.contains(relation.Related_Account__c)
      ) {
        addExpansionCountKey(
          accountIdToRelatedAccountKeys,
          relation.Related_Account__c,
          relation.Account__c,
          relation.RecordTypeId
        );
      }
    }

    for (Id accountId : accountIdToRelatedAccountKeys.keySet()) {
      accountIdToCount.put(
        String.valueOf(accountId),
        accountIdToRelatedAccountKeys.get(accountId).size()
      );
    }

    return accountIdToCount;
  }

  private static void addExpansionCountKey(
    Map<Id, Set<String>> accountIdToRelatedAccountKeys,
    Id viewerAccountId,
    Id otherAccountId,
    Id recordTypeId
  ) {
    if (viewerAccountId == null || otherAccountId == null) {
      return;
    }

    if (!accountIdToRelatedAccountKeys.containsKey(viewerAccountId)) {
      accountIdToRelatedAccountKeys.put(viewerAccountId, new Set<String>());
    }

    accountIdToRelatedAccountKeys.get(viewerAccountId)
      .add(buildExpansionCountKey(otherAccountId, recordTypeId));
  }

  private static String buildExpansionCountKey(Id otherAccountId, Id recordTypeId) {
    return String.valueOf(otherAccountId) + ':' + String.valueOf(recordTypeId);
  }

  public Integer selectDistinctFamilyContactCountByMemberAccountIds(Set<Id> memberAccountIds) {
    if (memberAccountIds == null || memberAccountIds.isEmpty()) {
      return 0;
    }

    Set<Id> familyRecordTypeIds = selectFamilyAccountRelationRecordTypeIds();
    if (familyRecordTypeIds.isEmpty()) {
      return 0;
    }

    Set<Id> familyContactIds = new Set<Id>();

    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE
        Active__c = TRUE
        AND RecordTypeId IN :familyRecordTypeIds
        AND (
          Account__c IN :memberAccountIds
          OR Related_Account__c IN :memberAccountIds
        )
    ]) {
      if (
        relation.Account__c != null &&
        memberAccountIds.contains(relation.Account__c) &&
        relation.Related_Account__c != null
      ) {
        familyContactIds.add(relation.Related_Account__c);
      }

      if (
        relation.Related_Account__c != null &&
        memberAccountIds.contains(relation.Related_Account__c) &&
        relation.Account__c != null
      ) {
        familyContactIds.add(relation.Account__c);
      }
    }

    return familyContactIds.size();
  }

  public Integer selectDistinctNetworkContactCountByMemberAccountIds(
    Set<Id> memberAccountIds
  ) {
    if (memberAccountIds == null || memberAccountIds.isEmpty()) {
      return 0;
    }

    Set<Id> networkRecordTypeIds = selectNetworkAccountRelationRecordTypeIds();
    if (networkRecordTypeIds.isEmpty()) {
      return 0;
    }

    Set<Id> networkContactIds = new Set<Id>();

    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE
        Active__c = TRUE
        AND RecordTypeId IN :networkRecordTypeIds
        AND (
          Account__c IN :memberAccountIds
          OR Related_Account__c IN :memberAccountIds
        )
    ]) {
      if (
        relation.Account__c != null &&
        memberAccountIds.contains(relation.Account__c) &&
        relation.Related_Account__c != null
      ) {
        networkContactIds.add(relation.Related_Account__c);
      }

      if (
        relation.Related_Account__c != null &&
        memberAccountIds.contains(relation.Related_Account__c) &&
        relation.Account__c != null
      ) {
        networkContactIds.add(relation.Account__c);
      }
    }

    return networkContactIds.size();
  }

  private Set<Id> selectNetworkAccountRelationRecordTypeIds() {
    Set<Id> recordTypeIds = new Set<Id>();
    Set<String> developerNames = new Set<String>{
      FscRelRecordTypeUtils.COI_REFERRAL_RECORD_TYPE,
      FscRelRecordTypeUtils.SERVICE_PROVIDER_RECORD_TYPE,
      FscRelRecordTypeUtils.BUSINESS_RECORD_TYPE
    };

    for (RecordType recordType : [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account_Account_Relationship__c'
        AND DeveloperName IN :developerNames
        AND IsActive = TRUE
    ]) {
      recordTypeIds.add(recordType.Id);
    }

    return recordTypeIds;
  }

  private Set<Id> selectFamilyAccountRelationRecordTypeIds() {
    Set<Id> recordTypeIds = new Set<Id>();
    Set<String> developerNames = new Set<String>{
      FscRelRecordTypeUtils.PERSONAL_AND_FAMILY_RECORD_TYPE
    };

    for (RecordType recordType : [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account_Account_Relationship__c'
        AND DeveloperName IN :developerNames
        AND IsActive = TRUE
    ]) {
      recordTypeIds.add(recordType.Id);
    }

    return recordTypeIds;
  }

  public Map<String, Integer> selectActiveCountsByAccountIds(Set<Id> accountIds) {
    Map<String, Integer> accountIdToCount = new Map<String, Integer>();

    if (accountIds == null || accountIds.isEmpty()) {
      return accountIdToCount;
    }

    for (AggregateResult aggregateResult : [
      SELECT Account__c accountId, COUNT(Id) rowCount
      FROM Account_Account_Relationship__c
      WHERE Account__c IN :accountIds AND Active__c = TRUE
      GROUP BY Account__c
    ]) {
      accountIdToCount.put(
        String.valueOf(aggregateResult.get('accountId')),
        (Integer) aggregateResult.get('rowCount')
      );
    }

    return accountIdToCount;
  }

  public List<Account_Account_Relationship__c> selectByIds(List<Id> relationIds) {
    if (relationIds == null || relationIds.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    return Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Id IN :relationIds'
    );
  }

  public Account_Account_Relationship__c insertRelation(
    Account_Account_Relationship__c relation
  ) {
    insert relation;
    return relation;
  }

  public Account_Account_Relationship__c updateRelation(
    Account_Account_Relationship__c relation
  ) {
    update relation;
    return relation;
  }

  public Integer deleteRelations(List<Account_Account_Relationship__c> relations) {
    if (relations == null || relations.isEmpty()) {
      return 0;
    }

    delete relations;
    return relations.size();
  }
}