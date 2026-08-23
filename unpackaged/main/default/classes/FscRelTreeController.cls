/**
 * Author: Hoang Long Vu To
 * Date: 2026-05-20
 *
 * Aura-enabled facade for FSC Relationship Tree reads.
 * Delegates to FscRelHouseholdService.
 */
public with sharing class FscRelTreeController {
  private static final FscRelHouseholdService SERVICE = new FscRelHouseholdService();

  /**
   * Resolves the root Account id for the supplied Account.
   * Person Accounts: returns Account.Household__c when populated, otherwise
   * the AccountId from the most recently modified active AccountContactRelation.
   * Non-person Accounts: returns the same Account id.
   */
  @AuraEnabled(cacheable=true)
  public static FscRelHouseholdModels.RootAccountResolveResult resolveRootAccountId(
    Id accountId
  ) {
    return SERVICE.resolveRootAccount(accountId);
  }

  @AuraEnabled(cacheable=true)
  public static FscRelHouseholdModels.RelationshipTreeData getPersonAccountMapTree(
    Id personAccountId
  ) {
    return SERVICE.getPersonAccountMapTree(personAccountId);
  }

  @AuraEnabled(cacheable=true)
  public static FscRelHouseholdModels.RelationshipTreeData getRelationshipTree(
    Id rootAccountId
  ) {
    return SERVICE.getRelationshipTree(rootAccountId);
  }

  /**
   * Non-cacheable read used after DML so the UI reloads committed data.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.RelationshipTreeData refreshRelationshipTree(
    Id rootAccountId
  ) {
    return SERVICE.getRelationshipTree(rootAccountId);
  }

  @AuraEnabled
  public static FscRelHouseholdModels.RelationshipTreeData refreshPersonAccountMapTree(
    Id personAccountId
  ) {
    return SERVICE.getPersonAccountMapTree(personAccountId);
  }
}