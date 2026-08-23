/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 */
public with sharing class AccountAccountRelationshipTriggerHandler {
  public void isAfterInsert(List<Account_Account_Relationship__c> newList) {
    FscRelAccountRelationShareService.syncSharesForRelations(newList);
  }

  public void isAfterUpdate(
    List<Account_Account_Relationship__c> newList,
    Map<Id, Account_Account_Relationship__c> oldMap
  ) {
    List<Account_Account_Relationship__c> relationsToSync = new List<Account_Account_Relationship__c>();
    Set<Id> relatedAccountIds = new Set<Id>();

    for (Account_Account_Relationship__c relation : newList) {
      Account_Account_Relationship__c oldRelation = oldMap.get(relation.Id);

      if (oldRelation == null) {
        relationsToSync.add(relation);
        continue;
      }

      if (relation.Related_Account__c != oldRelation.Related_Account__c) {
        relationsToSync.add(relation);

        if (oldRelation.Related_Account__c != null) {
          relatedAccountIds.add(oldRelation.Related_Account__c);
        }
      }
    }

    FscRelAccountRelationShareService.syncSharesForRelations(relationsToSync);

    if (!relatedAccountIds.isEmpty()) {
      FscRelAccountRelationShareService.syncSharesForRelatedAccounts(
        relatedAccountIds
      );
    }
  }
}