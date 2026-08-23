/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-25
 */
@IsTest
private class FscRelMemberAarExpansionTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void getMemberAccountRelationshipsForAccount_includesIncomingRelationship() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = FscDataTestDataFactory.resolveMemberRelationshipRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c siblingRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Sibling',
      'Sibling'
    );
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    insert new Account_Account_Relationship__c(
      Account__c = scenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.unlinkedPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = siblingRole.Id,
      Inverse_Reciprocal_Role__c = siblingRole.Id,
      Active__c = true
    );

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = FscRelHouseholdController.getMemberAccountRelationshipsForAccount(
      scenario.unlinkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(
      String.valueOf(scenario.linkedPersonAccount.Id),
      results[0].relatedAccountId
    );
    System.assertEquals('Sibling', results[0].role);
  }
}