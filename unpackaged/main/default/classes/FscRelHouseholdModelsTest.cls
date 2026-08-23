/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class FscRelHouseholdModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    FscRelHouseholdModels.TreeMember treeMember = new FscRelHouseholdModels.TreeMember();
    FscRelHouseholdModels.TreeAccount treeAccount = new FscRelHouseholdModels.TreeAccount();
    FscRelHouseholdModels.RelationshipTreeData relationshipTreeData = new FscRelHouseholdModels.RelationshipTreeData();
    FscRelHouseholdModels.TreeAccountResult treeAccountResult = new FscRelHouseholdModels.TreeAccountResult();
    FscRelHouseholdModels.RootAccountResolveResult rootAccountResolveResult = new FscRelHouseholdModels.RootAccountResolveResult();
    FscRelHouseholdModels.DeleteResult deleteResult = new FscRelHouseholdModels.DeleteResult();
    FscRelHouseholdModels.LookupOption lookupOption = new FscRelHouseholdModels.LookupOption();
    FscRelHouseholdModels.RecordTypeInfo recordTypeInfo = new FscRelHouseholdModels.RecordTypeInfo();
    FscRelHouseholdModels.PicklistOption picklistOption = new FscRelHouseholdModels.PicklistOption();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult reciprocalRoleDuplicateCheckResult = new FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult();
    FscRelHouseholdModels.ReciprocalRoleCreateResult reciprocalRoleCreateResult = new FscRelHouseholdModels.ReciprocalRoleCreateResult();
    FscRelHouseholdModels.RecordTypeOption recordTypeOption = new FscRelHouseholdModels.RecordTypeOption();
    FscRelHouseholdModels.TreeMemberAccountRelationship treeMemberAccountRelationship = new FscRelHouseholdModels.TreeMemberAccountRelationship();
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput treeMemberAccountRelationshipInput = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult treeMemberAccountRelationshipRowResult = new FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult();
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult memberAccountRelationshipsSaveResult = new FscRelHouseholdModels.MemberAccountRelationshipsSaveResult();

    System.assertNotEquals(null, treeMember.roles);
    System.assertEquals(false, treeMember.isPrimaryMember);
    System.assertNotEquals(null, treeAccount.roles);
    System.assertNotEquals(null, treeAccount.classifications);
    System.assertNotEquals(null, relationshipTreeData.members);
    System.assertNotEquals(null, relationshipTreeData.leadProspectAccounts);
    System.assertEquals(false, treeAccountResult.success);
    System.assertEquals(false, rootAccountResolveResult.isPersonAccount);
    System.assertEquals(false, deleteResult.success);
    System.assertNotEquals(null, lookupOption);
    System.assertEquals(false, recordTypeInfo.isPersonType);
    System.assertNotEquals(null, picklistOption);
    System.assertEquals(false, reciprocalRoleDuplicateCheckResult.blockSave);
    System.assertEquals(false, reciprocalRoleCreateResult.success);
    System.assertNotEquals(null, recordTypeOption);
    System.assertEquals(false, treeMemberAccountRelationship.isActive);
    System.assertEquals(false, treeMemberAccountRelationshipInput.isActive);
    System.assertEquals(true, treeMemberAccountRelationshipRowResult.success);
    System.assertNotEquals(null, memberAccountRelationshipsSaveResult.rowResults);
  }

  @IsTest
  static void parameterizedConstructors_assignProvidedValues() {
    FscRelHouseholdModels.TreeAccountResult treeAccountResult = new FscRelHouseholdModels.TreeAccountResult(
      true,
      'Saved',
      '001000000000001AAA'
    );
    FscRelHouseholdModels.PicklistOption picklistOption = new FscRelHouseholdModels.PicklistOption(
      'Client',
      'Client'
    );
    FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult rowResult = new FscRelHouseholdModels.TreeMemberAccountRelationshipRowResult(
      'row-1'
    );

    System.assertEquals(true, treeAccountResult.success);
    System.assertEquals('Client', picklistOption.label);
    System.assertEquals('row-1', rowResult.rowKey);
  }
}