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

  @IsTest
  static void getMemberAccountRelationshipsForAccount_returnsMultipleRolesForSameAccountPair() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = FscRelRecordTypeUtils.FIDUCIARY_LEGAL_RECORD_TYPE;
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );

    if (recordTypeId == null) {
      return;
    }

    Reciprocal_Role__c grantorRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Grantor',
      'Trustee'
    );
    Reciprocal_Role__c principalRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Principal',
      'Power of Attorney'
    );
    Reciprocal_Role__c trusteeRole = [
      SELECT Id
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Trustee'
      LIMIT 1
    ];
    Reciprocal_Role__c powerOfAttorneyRole = [
      SELECT Id
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Power of Attorney'
      LIMIT 1
    ];

    insert new List<Account_Account_Relationship__c>{
      new Account_Account_Relationship__c(
        Account__c = scenario.rootAccount.Id,
        Related_Account__c = scenario.linkedPersonAccount.Id,
        RecordTypeId = recordTypeId,
        Reciprocal_Role__c = grantorRole.Id,
        Inverse_Reciprocal_Role__c = trusteeRole.Id,
        Active__c = true
      ),
      new Account_Account_Relationship__c(
        Account__c = scenario.rootAccount.Id,
        Related_Account__c = scenario.linkedPersonAccount.Id,
        RecordTypeId = recordTypeId,
        Reciprocal_Role__c = principalRole.Id,
        Inverse_Reciprocal_Role__c = powerOfAttorneyRole.Id,
        Active__c = true
      )
    };

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = FscRelHouseholdController.getMemberAccountRelationshipsForAccount(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(2, results.size());

    Set<String> roleLabels = new Set<String>();

    for (FscRelHouseholdModels.TreeMemberAccountRelationship relationship : results) {
      System.assertEquals(
        String.valueOf(scenario.rootAccount.Id),
        relationship.relatedAccountId
      );
      roleLabels.add(relationship.role);
    }

    System.assert(roleLabels.contains('Trustee'));
    System.assert(roleLabels.contains('Power of Attorney'));
  }
}