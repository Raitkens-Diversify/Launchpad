/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-25
 */
@IsTest
private class FscRelMemberAccountRelationshipTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void saveMemberAccountRelationships_createsMirrorRows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c childRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Child',
      'Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Parent'
      LIMIT 1
    ];

    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    input.rowKey = 'row-1';
    input.relatedAccountId = String.valueOf(scenario.secondPersonAccount.Id);
    input.reciprocalRoleId = String.valueOf(childRole.Id);
    input.inverseReciprocalRoleId = String.valueOf(parentRole.Id);
    input.role = childRole.Role__c;
    input.inverseRole = parentRole.Role__c;
    input.isActive = true;

    Test.startTest();
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult saveResult = FscRelHouseholdController.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      JSON.serialize(
        new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
      )
    );
    Test.stopTest();

    System.assertEquals(true, saveResult.success, saveResult.message);

    List<Account_Account_Relationship__c> primaryRows = [
      SELECT
        Id,
        Account__c,
        Related_Account__c,
        Reciprocal_Role__c,
        Inverse_Reciprocal_Role__c,
        RecordType.DeveloperName
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :scenario.linkedPersonAccount.Id
        AND Related_Account__c = :scenario.secondPersonAccount.Id
    ];
    System.assertEquals(1, primaryRows.size());
    System.assertEquals(childRole.Id, primaryRows[0].Reciprocal_Role__c);
    System.assertEquals(parentRole.Id, primaryRows[0].Inverse_Reciprocal_Role__c);

    List<Account_Account_Relationship__c> mirrorRows = [
      SELECT Id, Reciprocal_Role__c, Inverse_Reciprocal_Role__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :scenario.secondPersonAccount.Id
        AND Related_Account__c = :scenario.linkedPersonAccount.Id
    ];
    System.assertEquals(1, mirrorRows.size());
    System.assertEquals(parentRole.Id, mirrorRows[0].Reciprocal_Role__c);
    System.assertEquals(childRole.Id, mirrorRows[0].Inverse_Reciprocal_Role__c);
  }

  @IsTest
  static void getMemberAccountRelationships_filtersByRecordType() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c childRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Sibling',
      'Sibling'
    );
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    input.rowKey = 'row-1';
    input.relatedAccountId = String.valueOf(scenario.secondPersonAccount.Id);
    input.reciprocalRoleId = String.valueOf(childRole.Id);
    input.inverseReciprocalRoleId = String.valueOf(childRole.Id);
    input.role = childRole.Role__c;
    input.inverseRole = childRole.Role__c;
    input.isActive = true;

    FscRelHouseholdController.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      JSON.serialize(
        new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
      )
    );

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = FscRelHouseholdController.getMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals('Sibling', results[0].role);
  }

  @IsTest
  static void searchReciprocalRoles_filtersByServiceProviderRecordTypeDeveloperName() {
    String recordTypeDeveloperName = FscRelRecordTypeUtils.SERVICE_PROVIDER_RECORD_TYPE;
    Id reciprocalRoleRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      recordTypeDeveloperName
    );
    if (reciprocalRoleRecordTypeId == null) {
      return;
    }

    FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Physician',
      'Patient (Physician)'
    );

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchReciprocalRoles(
      'Physician',
      recordTypeDeveloperName
    );
    Test.stopTest();

    System.assert(!results.isEmpty(), 'Expected service provider reciprocal role search results.');
    System.assert(
      results[0].label.contains('Physician'),
      'Expected a service provider role label containing Physician.'
    );
  }

  @IsTest
  static void searchReciprocalRoles_filtersByRecordTypeDeveloperName() {
    String recordTypeDeveloperName = FscRelRecordTypeUtils.PERSONAL_AND_FAMILY_RECORD_TYPE;
    Id reciprocalRoleRecordTypeId = FscRelRecordTypeUtils.selectReciprocalRoleRecordTypeId(
      recordTypeDeveloperName
    );
    if (reciprocalRoleRecordTypeId == null) {
      return;
    }

    FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Child',
      'Parent'
    );

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchReciprocalRoles(
      'Child',
      recordTypeDeveloperName
    );
    Test.stopTest();

    System.assert(!results.isEmpty(), 'Expected filtered reciprocal role search results.');
    System.assertEquals('Child', results[0].label);
  }

  @IsTest
  static void searchReciprocalRoles_returnsEmptyWhenRecordTypeCannotResolve() {
    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchReciprocalRoles(
      '',
      'Definitely_Not_A_Real_Record_Type'
    );
    Test.stopTest();

    System.assertEquals(
      0,
      results.size(),
      'Expected no reciprocal roles when record type cannot be resolved.'
    );
  }

  @IsTest
  static void getHouseholdFamilyCardCount_returnsDistinctFamilyContacts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c childRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Child',
      'Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Parent'
      LIMIT 1
    ];

    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    input.rowKey = 'row-1';
    input.relatedAccountId = String.valueOf(scenario.secondPersonAccount.Id);
    input.reciprocalRoleId = String.valueOf(childRole.Id);
    input.inverseReciprocalRoleId = String.valueOf(parentRole.Id);
    input.role = childRole.Role__c;
    input.inverseRole = parentRole.Role__c;
    input.isActive = true;

    FscRelHouseholdController.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      JSON.serialize(
        new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
      )
    );

    Test.startTest();
    Integer count = FscRelHouseholdController.getHouseholdFamilyCardCount(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, count);
  }

  @IsTest
  static void getHouseholdNetworkCardCount_returnsDistinctNetworkContacts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    Id coiRecordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.COI_REFERRAL_RECORD_TYPE
    );
    if (coiRecordTypeId == null) {
      return;
    }

    Reciprocal_Role__c referrerRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      FscRelRecordTypeUtils.COI_REFERRAL_RECORD_TYPE,
      'Referrer',
      'Referred'
    );
    Reciprocal_Role__c referredRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Referred'
      LIMIT 1
    ];

    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = new FscRelHouseholdModels.TreeMemberAccountRelationshipInput();
    input.rowKey = 'row-network-1';
    input.relatedAccountId = String.valueOf(scenario.secondPersonAccount.Id);
    input.reciprocalRoleId = String.valueOf(referrerRole.Id);
    input.inverseReciprocalRoleId = String.valueOf(referredRole.Id);
    input.role = referrerRole.Role__c;
    input.inverseRole = referredRole.Role__c;
    input.isActive = true;

    FscRelHouseholdController.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      FscRelRecordTypeUtils.COI_REFERRAL_RECORD_TYPE,
      JSON.serialize(
        new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
      )
    );

    Test.startTest();
    Integer count = FscRelHouseholdController.getHouseholdNetworkCardCount(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, count);
  }

  private static String resolveFirstAccountRelationRecordTypeDeveloperName() {
    return FscDataTestDataFactory.resolveMemberRelationshipRecordTypeDeveloperName();
  }
}