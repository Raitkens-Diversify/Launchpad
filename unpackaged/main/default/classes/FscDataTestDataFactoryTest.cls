/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 */
@IsTest
private class FscDataTestDataFactoryTest {
  @IsTest
  static void createTreeScenario_buildsDefaultHouseholdData() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario();

    System.assertNotEquals(null, scenario.rootAccount.Id);
    System.assertNotEquals(null, scenario.primaryMembership.Id);
    System.assertNotEquals(null, scenario.primaryAccountRelationship.Id);
  }

  @IsTest
  static void createTreeScenario_withUniqueNames_createsIsolatedAccounts() {
    FscDataTestDataFactory.TreeScenario firstScenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );
    FscDataTestDataFactory.TreeScenario secondScenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    System.assertNotEquals(firstScenario.rootAccount.Id, secondScenario.rootAccount.Id);
    System.assertNotEquals(firstScenario.rootAccount.Name, secondScenario.rootAccount.Name);
  }

  @IsTest
  static void loadTreeScenario_reloadsCreatedScenario() {
    FscDataTestDataFactory.TreeScenario createdScenario = FscDataTestDataFactory.createTreeScenario();
    FscDataTestDataFactory.TreeScenario loadedScenario = createdScenario.reload();

    System.assertEquals(createdScenario.rootAccount.Id, loadedScenario.rootAccount.Id);
    System.assertEquals(
      createdScenario.linkedPersonAccount.Id,
      loadedScenario.linkedPersonAccount.Id
    );
  }

  @IsTest
  static void createTreeScenario_withClassifications_createsVendorAndUnclassifiedAccounts() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withClassifications()
    );

    System.assertNotEquals(null, scenario.vendorAccount);
    System.assertNotEquals(null, scenario.unclassifiedAccount);
    System.assert(
      FscRelClassificationUtils.includesClassification(
        scenario.vendorAccount,
        FscRelClassificationUtils.VENDOR
      )
    );
  }

  @IsTest
  static void createRootAccount_doesNotAssignHouseholdRecordType() {
    Account rootAccount = FscDataTestDataFactory.createRootAccount(
      'Generic Root Account'
    );

    rootAccount = [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id = :rootAccount.Id
      LIMIT 1
    ];

    System.assertEquals(
      false,
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
        rootAccount.RecordType == null ? null : rootAccount.RecordType.DeveloperName
      )
    );
  }

  @IsTest
  static void createHouseholdAccount_assignsHouseholdRecordTypeWhenAvailable() {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeId();

    if (householdRecordTypeId == null) {
      return;
    }

    Account householdAccount = FscDataTestDataFactory.createHouseholdAccount(
      'Explicit Household Account'
    );

    householdAccount = [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id = :householdAccount.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordType(householdAccount)
    );
  }

  @IsTest
  static void createHouseholdAccountForClientLink_assignsHouseholdRecordTypeWhenAvailable() {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeIdForClientHouseholdLink();

    if (householdRecordTypeId == null) {
      return;
    }

    Account householdAccount = FscDataTestDataFactory.createHouseholdAccountForClientLink(
      'Client Link Household Account'
    );

    householdAccount = [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id = :householdAccount.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordType(householdAccount)
    );
  }

  @IsTest
  static void createTreeScenario_assignsHouseholdRecordTypeToRootAccountsWhenAvailable() {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeId();

    if (householdRecordTypeId == null) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario();
    Account rootAccount = [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id = :scenario.rootAccount.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordType(rootAccount)
    );
  }

  @IsTest
  static void createTreeScenario_assignsClientHouseholdWhenLookupAllows() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario();
    Account linkedPersonAccount = [
      SELECT Id, Household__c, RecordType.DeveloperName
      FROM Account
      WHERE Id = :scenario.linkedPersonAccount.Id
      LIMIT 1
    ];

    if (linkedPersonAccount.Household__c == null) {
      return;
    }

    System.assertEquals(scenario.rootAccount.Id, linkedPersonAccount.Household__c);
  }
}