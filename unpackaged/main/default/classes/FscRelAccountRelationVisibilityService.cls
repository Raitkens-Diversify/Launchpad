/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 *
 * Loads member account relationships without AAR sharing enforcement, then filters
 * to rows the running user can read based on Related_Account__c access.
 *
 * Only relationships created through the relationship-map modals (Reciprocal_Role__c
 * populated) are exposed. Structural household-membership links from envelope
 * provisioning carry Association_Type__c = Member and no reciprocal role.
 */
public without sharing class FscRelAccountRelationVisibilityService {
  private static final String MEMBER_RELATION_FIELDS =
    'Id, Account__c, Account__r.Name, Account__r.IsPersonAccount, Related_Account__c, Related_Account__r.Name, Related_Account__r.IsPersonAccount, ' +
    'Reciprocal_Role__c, Reciprocal_Role__r.Role__c, Reciprocal_Role__r.Name, ' +
    'Inverse_Reciprocal_Role__c, Inverse_Reciprocal_Role__r.Role__c, Inverse_Reciprocal_Role__r.Name, ' +
    'RecordTypeId, RecordType.DeveloperName, Active__c';

  public static List<Account_Account_Relationship__c> selectVisibleByAccountIds(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c IN :accountIds ORDER BY Related_Account__r.Name'
    );

    return filterToRelationshipMapManagedRelations(
      filterByRelatedAccountAccess(relations)
    );
  }

  public static List<Account_Account_Relationship__c> selectVisibleByRelatedAccountIds(
    Set<Id> relatedAccountIds
  ) {
    if (relatedAccountIds == null || relatedAccountIds.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Related_Account__c IN :relatedAccountIds AND Active__c = TRUE ORDER BY Account__r.Name'
    );

    return filterToRelationshipMapManagedRelations(
      filterByRelatedAccountAccess(relations)
    );
  }

  public static List<Account_Account_Relationship__c> selectVisibleByAccountAndRecordType(
    Id memberAccountId,
    Id recordTypeId
  ) {
    if (memberAccountId == null || recordTypeId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Account__c = :memberAccountId AND RecordTypeId = :recordTypeId ORDER BY Related_Account__r.Name'
    );

    return filterToRelationshipMapManagedRelations(
      filterByRelatedAccountAccess(relations)
    );
  }

  public static List<Account_Account_Relationship__c> selectVisibleByRelatedAccountAndRecordType(
    Id relatedAccountId,
    Id recordTypeId
  ) {
    if (relatedAccountId == null || recordTypeId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = Database.query(
      'SELECT ' +
        MEMBER_RELATION_FIELDS +
        ' FROM Account_Account_Relationship__c WHERE Related_Account__c = :relatedAccountId AND RecordTypeId = :recordTypeId AND Active__c = TRUE ORDER BY Account__r.Name'
    );

    return filterToRelationshipMapManagedRelations(
      filterByRelatedAccountAccess(relations)
    );
  }

  public static Map<String, Integer> selectVisibleExpansionCountsByAccountIds(
    Set<Id> accountIds
  ) {
    Map<String, Integer> accountIdToCount = new Map<String, Integer>();

    if (accountIds == null || accountIds.isEmpty()) {
      return accountIdToCount;
    }

    List<Account_Account_Relationship__c> relations = [
      SELECT Account__c, Related_Account__c, RecordTypeId, Active__c, Reciprocal_Role__c
      FROM Account_Account_Relationship__c
      WHERE
        (Account__c IN :accountIds OR Related_Account__c IN :accountIds)
        AND Active__c = TRUE
        AND Reciprocal_Role__c != NULL
    ];

    Map<Id, Set<String>> accountIdToRelatedAccountKeys = new Map<Id, Set<String>>();

    for (
      Account_Account_Relationship__c relation : filterByRelatedAccountAccess(
        relations
      )
    ) {
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

  public static Boolean isRelationshipMapManagedRelation(
    Account_Account_Relationship__c relation
  ) {
    return relation != null && relation.Reciprocal_Role__c != null;
  }

  public static List<Account_Account_Relationship__c> filterToRelationshipMapManagedRelations(
    List<Account_Account_Relationship__c> relations
  ) {
    List<Account_Account_Relationship__c> managedRelations = new List<Account_Account_Relationship__c>();

    if (relations == null || relations.isEmpty()) {
      return managedRelations;
    }

    for (Account_Account_Relationship__c relation : relations) {
      if (isRelationshipMapManagedRelation(relation)) {
        managedRelations.add(relation);
      }
    }

    return managedRelations;
  }

  public static List<Account_Account_Relationship__c> filterByRelatedAccountAccess(
    List<Account_Account_Relationship__c> relations
  ) {
    if (relations == null || relations.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    Set<Id> relatedAccountIds = new Set<Id>();

    for (Account_Account_Relationship__c relation : relations) {
      if (relation?.Related_Account__c != null) {
        relatedAccountIds.add(relation.Related_Account__c);
      }
    }

    Set<Id> readableRelatedAccountIds = loadReadableAccountIds(relatedAccountIds);
    List<Account_Account_Relationship__c> visibleRelations = new List<Account_Account_Relationship__c>();

    for (Account_Account_Relationship__c relation : relations) {
      if (
        relation.Active__c == true &&
        relation.Related_Account__c != null &&
        readableRelatedAccountIds.contains(relation.Related_Account__c)
      ) {
        visibleRelations.add(relation);
      }
    }

    return visibleRelations;
  }

  private static Set<Id> loadReadableAccountIds(Set<Id> accountIds) {
    Set<Id> readableAccountIds = new Set<Id>();

    if (accountIds == null || accountIds.isEmpty()) {
      return readableAccountIds;
    }

    for (UserRecordAccess recordAccess : [
      SELECT RecordId
      FROM UserRecordAccess
      WHERE
        UserId = :UserInfo.getUserId()
        AND RecordId IN :accountIds
        AND HasReadAccess = TRUE
    ]) {
      readableAccountIds.add(recordAccess.RecordId);
    }

    return readableAccountIds;
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
      .add(
        String.valueOf(otherAccountId) + ':' + String.valueOf(recordTypeId)
      );
  }
}