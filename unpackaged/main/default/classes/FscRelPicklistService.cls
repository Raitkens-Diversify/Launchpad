/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 *
 * Exposes canonical reciprocal role names for FSC relationship flows.
 * Role selection uses Reciprocal_Role__c lookups on AAR, not AAR picklists.
 */
public without sharing class FscRelPicklistService {
  public static List<String> getAccountRelationRoleNamesForRecordType(
    String recordTypeDeveloperName
  ) {
    Set<String> roleNames = FscRelReciprocalRoleCatalog.selectAllowedRoleNamesForAarRecordType(
      recordTypeDeveloperName
    );
    List<String> sortedRoleNames = new List<String>(roleNames);
    sortedRoleNames.sort();
    return sortedRoleNames;
  }
}