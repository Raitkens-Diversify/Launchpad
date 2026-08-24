/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-20
 *
 * Integration tests for classification-aware relationship map Apex.
 */
@IsTest
private class FscRelClassificationFeatureTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withClassifications()
    );
  }

  @IsTest
  static void searchAccountsByClassification_returnsMatchingVendorAccounts() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchAccountsByClassification(
      'FscData Vendor',
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(FscDataTestDataFactory.VENDOR_ACCOUNT_NAME, results[0].label);
  }

  @IsTest
  static void searchAccountsByClassification_returnsEmptyForBlankInputs() {
    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> blankClassificationResults = FscRelHouseholdController.searchAccountsByClassification(
      'Vendor',
      ''
    );
    List<FscRelHouseholdModels.LookupOption> shortSearchTermResults = FscRelHouseholdController.searchAccountsByClassification(
      'V',
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(true, blankClassificationResults.isEmpty());
    System.assertEquals(true, shortSearchTermResults.isEmpty());
  }

  @IsTest
  static void repositorySearchAndSelectSupportClassifications() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    List<Account> searchResults = new FscRelAccountRepository().searchAccountsByClassification(
      'FscData Vendor',
      FscRelClassificationUtils.VENDOR,
      8
    );
    List<Account> selectedAccounts = new FscRelAccountRepository().selectAccountsByIdsWithClassifications(
      new Set<Id>{ scenario.vendorAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, searchResults.size());
    System.assertEquals(scenario.vendorAccount.Id, searchResults[0].Id);
    System.assertEquals(1, selectedAccounts.size());
    System.assert(
      FscRelClassificationUtils.includesClassification(
        selectedAccounts[0],
        FscRelClassificationUtils.VENDOR
      )
    );
  }

  @IsTest
  static void linkClassificationAccountToHousehold_setsHouseholdField() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    Id householdMembershipRecordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE
    );

    if (householdMembershipRecordTypeId == null) {
      return;
    }

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult result = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.vendorAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertEquals(
      String.valueOf(scenario.vendorAccount.Id),
      result.accountId
    );

    Account updatedAccount = [
      SELECT Id, Household__c
      FROM Account
      WHERE Id = :scenario.vendorAccount.Id
      LIMIT 1
    ];
    System.assertEquals(scenario.rootAccount.Id, updatedAccount.Household__c);

    Account_Account_Relationship__c membershipRelation = [
      SELECT Id, Active__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :scenario.rootAccount.Id
        AND Related_Account__c = :scenario.vendorAccount.Id
        AND RecordTypeId = :householdMembershipRecordTypeId
      LIMIT 1
    ];
    System.assertEquals(true, membershipRelation.Active__c);
  }

  @IsTest
  static void linkClassificationAccountToHousehold_reusesExistingHouseholdLink() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.vendorAccount },
      scenario.rootAccount.Id
    );

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult result = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.vendorAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertEquals(
      String.valueOf(scenario.vendorAccount.Id),
      result.accountId
    );
  }

  @IsTest
  static void linkClassificationAccountToHousehold_validatesRequiredInputs() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult missingRootResult = FscRelHouseholdController.linkClassificationAccountToHousehold(
      null,
      scenario.relatedBusinessAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    FscRelHouseholdModels.TreeAccountResult missingAccountResult = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      null,
      FscRelClassificationUtils.VENDOR
    );
    FscRelHouseholdModels.TreeAccountResult missingClassificationResult = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.relatedBusinessAccount.Id,
      ''
    );
    FscRelHouseholdModels.TreeAccountResult selfLinkResult = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.rootAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(false, missingRootResult.success);
    System.assertEquals(false, missingAccountResult.success);
    System.assertEquals(false, missingClassificationResult.success);
    System.assertEquals(false, selfLinkResult.success);
  }

  @IsTest
  static void linkClassificationAccountToHousehold_rejectsMissingClassification() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult result = FscRelHouseholdController.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.relatedBusinessAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assert(
      result.message.contains('required classification')
    );
  }

  @IsTest
  static void getRelationshipTree_returnsClassifiedAccounts() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClassification(
      scenario.relatedBusinessAccount,
      FscRelClassificationUtils.VENDOR
    );
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.relatedBusinessAccount },
      scenario.rootAccount.Id
    );

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, treeData.classifiedAccounts);
    System.assert(treeData.classifiedAccounts.size() >= 1);

    Boolean foundVendorAccount = false;
    for (FscRelHouseholdModels.TreeAccount classifiedAccount : treeData.classifiedAccounts) {
      if (
        classifiedAccount.accountId ==
        String.valueOf(scenario.relatedBusinessAccount.Id)
      ) {
        foundVendorAccount = true;
        System.assert(
          classifiedAccount.classifications.contains(
            FscRelClassificationUtils.VENDOR
          )
        );
      }
    }

    System.assertEquals(true, foundVendorAccount);
  }

  @IsTest
  static void getRelationshipTree_includesDirectHouseholdAarClassifications() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClassification(
      scenario.relatedBusinessAccount,
      FscRelClassificationUtils.COI
    );

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = FscRelTreeController.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    Boolean foundCoiAccount = false;
    for (FscRelHouseholdModels.TreeAccount classifiedAccount : treeData.classifiedAccounts) {
      if (
        classifiedAccount.accountId ==
        String.valueOf(scenario.relatedBusinessAccount.Id)
      ) {
        foundCoiAccount = true;
        System.assertNotEquals(null, classifiedAccount.relationId);
        System.assert(
          classifiedAccount.classifications.contains(FscRelClassificationUtils.COI)
        );
      }
    }

    System.assertEquals(true, foundCoiAccount);
  }

  @IsTest
  static void searchAccountsByClassification_excludesHouseholdLinkedAccounts() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.vendorAccount },
      scenario.rootAccount.Id
    );

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = FscRelHouseholdController.searchAccountsByClassification(
      'FscData Vendor',
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(true, results.isEmpty());
  }
}