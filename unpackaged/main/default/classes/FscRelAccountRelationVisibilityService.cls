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

  private static final String HOUSEHOLD_MEMBERSHIP_FIELDS =
    'Id, Account__c, Account__r.Name, Account__r.IsPersonAccount, Account__r.RecordType.DeveloperName, Account__r.RecordType.Name, ' +
    'Related_Account__c, Related_Account__r.Name, Related_Account__r.Type, Related_Account__r.IsPersonAccount, Related_Account__r.PersonContactId, ' +
    'Related_Account__r.RecordType.DeveloperName, Related_Account__r.RecordType.Name, Related_Account__r.Classification__c, ' +
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
      SELECT Id, Account__c, Related_Account__c, RecordTypeId, Active__c, Reciprocal_Role__c
      FROM Account_Account_Relationship__c
      WHERE
        (Account__c IN :accountIds OR Related_Account__c IN :accountIds)
        AND Active__c = TRUE
        AND Reciprocal_Role__c != NULL
    ];

    Map<Id, Set<Id>> accountIdToRelatedAccountIds = new Map<Id, Set<Id>>();
    Map<Id, Set<String>> accountIdToOutgoingPairKeys = new Map<Id, Set<String>>();

    for (
      Account_Account_Relationship__c relation : filterByRelatedAccountAccess(
        relations
      )
    ) {
      if (
        relation.Account__c != null &&
        accountIds.contains(relation.Account__c)
      ) {
        addExpansionRelatedAccountId(
          accountIdToRelatedAccountIds,
          relation.Account__c,
          relation.Related_Account__c
        );
        addExpansionOutgoingPairKey(
          accountIdToOutgoingPairKeys,
          relation.Account__c,
          relation.Related_Account__c,
          relation.RecordTypeId
        );
      }
    }

    for (
      Account_Account_Relationship__c relation : filterByRelatedAccountAccess(
        relations
      )
    ) {
      if (
        relation.Related_Account__c == null ||
        !accountIds.contains(relation.Related_Account__c)
      ) {
        continue;
      }

      String pairKey = buildExpansionPairKey(
        relation.Related_Account__c,
        relation.Account__c,
        relation.RecordTypeId
      );
      Set<String> outgoingPairKeys = accountIdToOutgoingPairKeys.get(
        relation.Related_Account__c
      );

      if (outgoingPairKeys != null && outgoingPairKeys.contains(pairKey)) {
        continue;
      }

      addExpansionRelatedAccountId(
        accountIdToRelatedAccountIds,
        relation.Related_Account__c,
        relation.Account__c
      );
    }

    for (Id accountId : accountIdToRelatedAccountIds.keySet()) {
      accountIdToCount.put(
        String.valueOf(accountId),
        accountIdToRelatedAccountIds.get(accountId).size()
      );
    }

    return accountIdToCount;
  }

  public static List<Account_Account_Relationship__c> selectReadableHouseholdMembershipByHouseholdId(
    Id householdId
  ) {
    if (householdId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = new FscRelAccountRelationRepository()
      .selectHouseholdMembershipByHouseholdId(householdId);

    return filterByRelatedAccountAccess(relations);
  }

  public static List<Account_Account_Relationship__c> selectReadableHouseholdMembershipByMemberAccountId(
    Id memberAccountId
  ) {
    if (memberAccountId == null) {
      return new List<Account_Account_Relationship__c>();
    }

    List<Account_Account_Relationship__c> relations = new FscRelAccountRelationRepository()
      .selectHouseholdMembershipByMemberAccountId(memberAccountId);

    return filterByAccountAccess(relations);
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

  public static List<Account_Account_Relationship__c> filterByAccountAccess(
    List<Account_Account_Relationship__c> relations
  ) {
    if (relations == null || relations.isEmpty()) {
      return new List<Account_Account_Relationship__c>();
    }

    Set<Id> accountIds = new Set<Id>();

    for (Account_Account_Relationship__c relation : relations) {
      if (relation?.Account__c != null) {
        accountIds.add(relation.Account__c);
      }
    }

    Set<Id> readableAccountIds = loadReadableAccountIds(accountIds);
    List<Account_Account_Relationship__c> visibleRelations = new List<Account_Account_Relationship__c>();

    for (Account_Account_Relationship__c relation : relations) {
      if (
        relation.Active__c == true &&
        relation.Account__c != null &&
        readableAccountIds.contains(relation.Account__c)
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

  private static void addExpansionRelatedAccountId(
    Map<Id, Set<Id>> accountIdToRelatedAccountIds,
    Id viewerAccountId,
    Id relatedAccountId
  ) {
    if (viewerAccountId == null || relatedAccountId == null) {
      return;
    }

    if (!accountIdToRelatedAccountIds.containsKey(viewerAccountId)) {
      accountIdToRelatedAccountIds.put(viewerAccountId, new Set<Id>());
    }

    accountIdToRelatedAccountIds.get(viewerAccountId).add(relatedAccountId);
  }

  private static void addExpansionOutgoingPairKey(
    Map<Id, Set<String>> accountIdToOutgoingPairKeys,
    Id viewerAccountId,
    Id otherAccountId,
    Id recordTypeId
  ) {
    if (viewerAccountId == null || otherAccountId == null) {
      return;
    }

    if (!accountIdToOutgoingPairKeys.containsKey(viewerAccountId)) {
      accountIdToOutgoingPairKeys.put(viewerAccountId, new Set<String>());
    }

    accountIdToOutgoingPairKeys.get(viewerAccountId)
      .add(buildExpansionPairKey(viewerAccountId, otherAccountId, recordTypeId));
  }

  private static String buildExpansionPairKey(
    Id viewerAccountId,
    Id otherAccountId,
    Id recordTypeId
  ) {
    return String.valueOf(viewerAccountId) +
      ':' +
      String.valueOf(otherAccountId) +
      ':' +
      String.valueOf(recordTypeId);
  }
}