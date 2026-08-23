/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 *
 * Repository for AccountContactRelation reads and writes.
 */
public with sharing class FscRelRelationRepository {
  public List<AccountContactRelation> selectByRootAccount(Id rootAccountId) {
    if (rootAccountId == null) {
      return new List<AccountContactRelation>();
    }

    return [
      SELECT
        Id,
        Roles,
        IsActive,
        ContactId,
        Contact.Name,
        Contact.AccountId,
        Contact.Account.Id,
        Contact.Account.RecordType.DeveloperName,
        Contact.Account.RecordType.Name,
        Contact.Account.Type
      FROM AccountContactRelation
      WHERE AccountId = :rootAccountId
      ORDER BY Contact.Name
    ];
  }

  public AccountContactRelation selectPrimaryGroupByContact(Id contactId) {
    if (contactId == null) {
      return null;
    }

    List<AccountContactRelation> relations = [
      SELECT AccountId
      FROM AccountContactRelation
      WHERE ContactId = :contactId AND IsActive = TRUE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];

    return relations.isEmpty() ? null : relations[0];
  }

  public List<AccountContactRelation> selectActiveGroupsByContact(Id contactId) {
    if (contactId == null) {
      return new List<AccountContactRelation>();
    }

    return [
      SELECT Id, AccountId, Account.Name
      FROM AccountContactRelation
      WHERE ContactId = :contactId AND IsActive = TRUE
      ORDER BY Account.Name
    ];
  }

  public AccountContactRelation selectPrimaryGroupConflict(
    Id contactId,
    Id rootAccountId
  ) {
    return null;
  }

  public AccountContactRelation selectByRootAccountAndContact(
    Id rootAccountId,
    Id contactId
  ) {
    if (rootAccountId == null || contactId == null) {
      return null;
    }

    List<AccountContactRelation> relations = [
      SELECT Id, Roles, IsActive
      FROM AccountContactRelation
      WHERE AccountId = :rootAccountId AND ContactId = :contactId
      LIMIT 1
    ];

    return relations.isEmpty() ? null : relations[0];
  }

  public List<AccountContactRelation> selectOtherPrimaryMembers(
    Id rootAccountId,
    Id keepRelationId
  ) {
    return new List<AccountContactRelation>();
  }

  public List<AccountContactRelation> selectByIds(List<Id> relationIds) {
    if (relationIds == null || relationIds.isEmpty()) {
      return new List<AccountContactRelation>();
    }

    return [
      SELECT Id, AccountId
      FROM AccountContactRelation
      WHERE Id IN :relationIds
    ];
  }

  public List<AccountContactRelation> selectActiveByRootAccounts(Set<Id> rootAccountIds) {
    if (rootAccountIds == null || rootAccountIds.isEmpty()) {
      return new List<AccountContactRelation>();
    }

    return [
      SELECT Id, AccountId
      FROM AccountContactRelation
      WHERE AccountId IN :rootAccountIds AND IsActive = TRUE
    ];
  }

  public Map<Id, Integer> selectActiveMemberCountsByRootAccountIds(Set<Id> rootAccountIds) {
    Map<Id, Integer> rootAccountIdToMemberCount = new Map<Id, Integer>();

    if (rootAccountIds == null || rootAccountIds.isEmpty()) {
      return rootAccountIdToMemberCount;
    }

    for (Id rootAccountId : rootAccountIds) {
      rootAccountIdToMemberCount.put(rootAccountId, 0);
    }

    for (AggregateResult aggregateResult : [
      SELECT AccountId rootAccountId, COUNT(Id) memberCount
      FROM AccountContactRelation
      WHERE AccountId IN :rootAccountIds AND IsActive = TRUE
      GROUP BY AccountId
    ]) {
      rootAccountIdToMemberCount.put(
        (Id) aggregateResult.get('rootAccountId'),
        (Integer) aggregateResult.get('memberCount')
      );
    }

    return rootAccountIdToMemberCount;
  }

  public AccountContactRelation insertRelation(AccountContactRelation relation) {
    insert relation;
    return relation;
  }

  public AccountContactRelation updateRelation(AccountContactRelation relation) {
    update relation;
    return relation;
  }

  public void updateRelations(List<AccountContactRelation> relations) {
    if (relations == null || relations.isEmpty()) {
      return;
    }

    update relations;
  }

  public Integer deleteRelations(List<AccountContactRelation> relations) {
    if (relations == null || relations.isEmpty()) {
      return 0;
    }

    delete relations;
    return relations.size();
  }
}