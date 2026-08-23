/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 *
 * Mirrors Account sharing on Related_Account__c onto Account_Account_Relationship__c
 * so relationship map reads respect account access without bypassing AAR OWD.
 */
public without sharing class FscRelAccountRelationShareService {
  private static final Set<String> ACCOUNT_ACCESS_LEVELS_WITH_READ = new Set<String>{
    'Read',
    'Edit',
    'All'
  };

  public static void syncSharesForRelatedAccounts(Set<Id> relatedAccountIds) {
    if (relatedAccountIds == null || relatedAccountIds.isEmpty()) {
      return;
    }

    Set<Id> safeRelatedAccountIds = new Set<Id>();

    for (Id relatedAccountId : relatedAccountIds) {
      if (relatedAccountId != null) {
        safeRelatedAccountIds.add(relatedAccountId);
      }
    }

    if (safeRelatedAccountIds.isEmpty()) {
      return;
    }

    List<Account_Account_Relationship__c> relations = [
      SELECT Id, Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE Related_Account__c IN :safeRelatedAccountIds
    ];

    syncSharesForRelations(relations);
  }

  public static void syncSharesForRelations(
    List<Account_Account_Relationship__c> relations
  ) {
    if (relations == null || relations.isEmpty()) {
      return;
    }

    Set<Id> relatedAccountIds = new Set<Id>();
    Set<Id> relationIds = new Set<Id>();
    List<Account_Account_Relationship__c> scopedRelations = new List<Account_Account_Relationship__c>();

    for (Account_Account_Relationship__c relation : relations) {
      if (relation == null || relation.Id == null || relation.Related_Account__c == null) {
        continue;
      }

      relatedAccountIds.add(relation.Related_Account__c);
      relationIds.add(relation.Id);
      scopedRelations.add(relation);
    }

    if (scopedRelations.isEmpty()) {
      return;
    }

    Map<Id, Set<Id>> relatedAccountIdToRecipients = loadAccountShareRecipients(
      relatedAccountIds
    );

    deleteManualShares(relationIds);

    List<Account_Account_Relationship__Share> sharesToInsert = new List<Account_Account_Relationship__Share>();

    for (Account_Account_Relationship__c relation : scopedRelations) {
      Set<Id> recipients = relatedAccountIdToRecipients.get(
        relation.Related_Account__c
      );

      if (recipients == null || recipients.isEmpty()) {
        continue;
      }

      for (Id userOrGroupId : recipients) {
        Account_Account_Relationship__Share shareRow = new Account_Account_Relationship__Share();
        shareRow.ParentId = relation.Id;
        shareRow.UserOrGroupId = userOrGroupId;
        shareRow.AccessLevel = 'Read';
        shareRow.RowCause = Schema.Account_Account_Relationship__Share.RowCause.Manual;
        sharesToInsert.add(shareRow);
      }
    }

    if (!sharesToInsert.isEmpty()) {
      Database.insert(sharesToInsert, false);
    }
  }

  private static Map<Id, Set<Id>> loadAccountShareRecipients(Set<Id> accountIds) {
    Map<Id, Set<Id>> accountIdToRecipients = new Map<Id, Set<Id>>();

    for (Id accountId : accountIds) {
      accountIdToRecipients.put(accountId, new Set<Id>());
    }

    for (AccountShare accountShare : [
      SELECT AccountId, UserOrGroupId, AccountAccessLevel
      FROM AccountShare
      WHERE AccountId IN :accountIds
    ]) {
      if (
        accountShare.UserOrGroupId == null ||
        !ACCOUNT_ACCESS_LEVELS_WITH_READ.contains(accountShare.AccountAccessLevel)
      ) {
        continue;
      }

      accountIdToRecipients.get(accountShare.AccountId)
        .add(accountShare.UserOrGroupId);
    }

    return accountIdToRecipients;
  }

  private static void deleteManualShares(Set<Id> relationIds) {
    if (relationIds == null || relationIds.isEmpty()) {
      return;
    }

    List<Account_Account_Relationship__Share> manualShares = [
      SELECT Id
      FROM Account_Account_Relationship__Share
      WHERE
        ParentId IN :relationIds
        AND RowCause = :Schema.Account_Account_Relationship__Share.RowCause.Manual
    ];

    if (!manualShares.isEmpty()) {
      Database.delete(manualShares, false);
    }
  }
}