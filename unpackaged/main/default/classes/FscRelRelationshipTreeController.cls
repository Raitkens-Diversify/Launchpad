/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 *
 * Aura-enabled facade for shared household relationship tree reads.
 */
public with sharing class FscRelRelationshipTreeController {
  private static final FscRelRelationshipTreeService SERVICE = new FscRelRelationshipTreeService();

  @AuraEnabled
  public static Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> getMemberRelationshipsByMemberAccountIds(
    List<Id> memberAccountIds
  ) {
    return SERVICE.getMemberRelationshipsByMemberAccountIds(
      memberAccountIds == null ? new Set<Id>() : new Set<Id>(memberAccountIds)
    );
  }
}