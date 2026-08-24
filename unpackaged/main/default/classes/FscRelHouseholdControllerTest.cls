/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
@IsTest
private class FscRelHouseholdControllerTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void getAccountName_returnsAccountName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    String accountName = FscRelHouseholdController.getAccountName(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(scenario.linkedPersonAccount.Name, accountName);
  }

  @IsTest
  static void searchAccounts_returnsMatchingPersonAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchAccounts(
      'FscData',
      true
    );
    Test.stopTest();

    System.assert(!results.isEmpty(), 'Expected person account search results.');
    System.assertEquals(
      scenario.linkedPersonAccount.Id,
      results[0].id,
      'Expected the linked person account in search results.'
    );
    System.assertEquals('standard:account', results[0].iconName);
  }

  @IsTest
  static void searchAccountsInScope_returnsOnlyAllowedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> scopedResults = FscRelHouseholdController.searchAccountsInScope(
      FscDataTestDataFactory.LINKED_PERSON_LAST_NAME,
      null,
      new List<String>{ scenario.linkedPersonAccount.Id }
    );
    List<FscRelHouseholdModels.LookupOption> excludedResults = FscRelHouseholdController.searchAccountsInScope(
      FscDataTestDataFactory.LINKED_PERSON_LAST_NAME,
      null,
      new List<String>{ scenario.rootAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, scopedResults.size());
    System.assertEquals(scenario.linkedPersonAccount.Id, scopedResults[0].id);
    System.assertEquals(true, excludedResults.isEmpty());
  }

  @IsTest
  static void getAccountsByIds_returnsPersonAccountsInOrder() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.getAccountsByIds(
      new List<String>{ scenario.linkedPersonAccount.Id },
      true
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(scenario.linkedPersonAccount.Id, results[0].id);
    System.assertEquals(scenario.linkedPersonAccount.Name, results[0].label);
  }

  @IsTest
  static void getCreateableRecordTypes_returnsAccountOptions() {
    Test.startTest();
    List<FscRelHouseholdModels.CreateRecordTypeOption> options = FscRelHouseholdController.getCreateableRecordTypes(
      'Account'
    );
    Test.stopTest();

    System.assert(!options.isEmpty(), 'Expected creatable Account record types.');
  }

  @IsTest
  static void getRecordTypeByDeveloperName_returnsPersonAccountRecordType() {
    List<RecordType> personRecordTypes = [
      SELECT DeveloperName
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];

    System.assert(!personRecordTypes.isEmpty(), 'Person account record type required.');

    Test.startTest();
    FscRelHouseholdModels.RecordTypeInfo recordTypeInfo = FscRelHouseholdController.getRecordTypeByDeveloperName(
      'Account',
      personRecordTypes[0].DeveloperName
    );
    Test.stopTest();

    System.assertNotEquals(null, recordTypeInfo.recordTypeId);
    System.assertEquals(true, recordTypeInfo.isPersonType);
  }

  @IsTest
  static void searchContacts_returnsMatchingContacts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchContacts(
      scenario.linkedPersonAccount.Name.left(4)
    );
    Test.stopTest();

    System.assert(!results.isEmpty(), 'Expected contact search results.');
    System.assertEquals('standard:contact', results[0].iconName);
  }

  @IsTest
  static void searchReciprocalRoles_returnsDefaultLookupWhenSearchTermBlank() {
    FscDataTestDataFactory.createReciprocalRole('Alpha Default');
    FscDataTestDataFactory.createReciprocalRole('Beta Default');

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchReciprocalRoles(
      '',
      null
    );
    Test.stopTest();

    System.assert(results.size() >= 2, 'Expected default reciprocal role lookup results.');
    System.assertEquals('Alpha Default', results[0].label);
  }

  @IsTest
  static void searchReciprocalRoles_returnsMatchingRoles() {
    FscDataTestDataFactory.createReciprocalRole('Spouse');

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchReciprocalRoles(
      'Spou',
      null
    );
    Test.stopTest();

    System.assert(!results.isEmpty(), 'Expected reciprocal role search results.');
    System.assertEquals('Spouse', results[0].label);
    System.assertEquals(true, String.isBlank(results[0].subtitle));
  }

  @IsTest
  static void validateReciprocalRoleForCreate_warnsOnDuplicateRole() {
    FscDataTestDataFactory.createReciprocalRole('Spouse');

    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult result = FscRelHouseholdController.validateReciprocalRoleForCreate(
      'Spouse'
    );
    Test.stopTest();

    System.assertEquals(true, result.blockSave);
    System.assertEquals(false, result.requiresConfirmation);
    System.assertEquals('Spouse', result.existingRole);
  }

  @IsTest
  static void validateReciprocalRoleForCreate_blocksExactDuplicate() {
    FscDataTestDataFactory.createReciprocalRole('Parent');

    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult result = FscRelHouseholdController.validateReciprocalRoleForCreate(
      'Parent'
    );
    Test.stopTest();

    System.assertEquals(true, result.blockSave);
    System.assertEquals(false, result.requiresConfirmation);
  }

  @IsTest
  static void validateReciprocalRoleForCreate_warnsOnSimilarRoleName() {
    FscDataTestDataFactory.createReciprocalRole('Child');

    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult result = FscRelHouseholdController.validateReciprocalRoleForCreate(
      'Beneficiary Child'
    );
    Test.stopTest();

    System.assertEquals(true, result.requiresConfirmation);
    System.assertEquals(false, result.blockSave);
    System.assertEquals('Child', result.existingRole);
  }

  @IsTest
  static void validateReciprocalRoleForCreate_allowsNewRoleName() {
    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult result = FscRelHouseholdController.validateReciprocalRoleForCreate(
      'Parent'
    );
    Test.stopTest();

    System.assertEquals(false, result.blockSave);
    System.assertEquals(false, result.requiresConfirmation);
  }

  @IsTest
  static void createReciprocalRole_createsContactRecordTypeRole() {
    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleCreateResult result = FscRelHouseholdController.createReciprocalRole(
      'Sibling',
      true,
      null
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertNotEquals(null, result.reciprocalRoleId);

    Reciprocal_Role__c createdRole = [
      SELECT Id, Role__c, RecordType.DeveloperName
      FROM Reciprocal_Role__c
      WHERE Id = :result.reciprocalRoleId
      LIMIT 1
    ];
    System.assertEquals('Sibling', createdRole.Role__c);
    System.assertNotEquals(null, createdRole.RecordType.DeveloperName);
  }

  @IsTest
  static void deleteMemberAccountRelationships_removesPrimaryAndMirrorRows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c childRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Delete Child',
      'Delete Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Delete Parent'
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

    Account_Account_Relationship__c primaryRow = [
      SELECT Id
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :scenario.linkedPersonAccount.Id
        AND Related_Account__c = :scenario.secondPersonAccount.Id
      LIMIT 1
    ];

    Test.startTest();
    FscRelHouseholdModels.DeleteResult deleteResult = FscRelHouseholdController.deleteMemberAccountRelationships(
      new List<String>{ String.valueOf(primaryRow.Id) }
    );
    Test.stopTest();

    System.assertEquals(true, deleteResult.success);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE
          Account__c = :scenario.linkedPersonAccount.Id
          OR Account__c = :scenario.secondPersonAccount.Id
      ]
    );
  }

  private static String resolveFirstAccountRelationRecordTypeDeveloperName() {
    return FscDataTestDataFactory.resolveMemberRelationshipRecordTypeDeveloperName();
  }

  @IsTest
  static void getAccountRecordTypeId_returnsDefaultRecordType() {
    Test.startTest();
    String personRecordTypeId = FscRelHouseholdController.getAccountRecordTypeId(true);
    String businessRecordTypeId = FscRelHouseholdController.getAccountRecordTypeId(false);
    Test.stopTest();

    System.assertNotEquals(null, personRecordTypeId);
    System.assertNotEquals(null, businessRecordTypeId);
  }

  @IsTest
  static void getContactName_returnsContactName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    String contactName = FscRelHouseholdController.getContactName(
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assert(String.isNotBlank(contactName), 'Expected a contact name.');
  }

  @IsTest
  static void getAccountMemberCounts_returnsActiveMembershipCounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    Map<String, Integer> counts = FscRelHouseholdController.getAccountMemberCounts(
      new List<Id>{ scenario.rootAccount.Id, scenario.secondRootAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(2, counts.get(String.valueOf(scenario.rootAccount.Id)));
    System.assertEquals(0, counts.get(String.valueOf(scenario.secondRootAccount.Id)));
  }
}