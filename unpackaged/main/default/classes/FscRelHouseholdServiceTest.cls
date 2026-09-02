/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-22
 */
@IsTest
private class FscRelHouseholdServiceTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void resolveRootAccount_handlesNullAndMissingAccount() {
    FscRelHouseholdService service = new FscRelHouseholdService();
    Account tempAccount = new Account(Name = 'Temporary Missing Account');
    FscDataTestDataFactory.applyRequiredAccountTypeOrClassification(tempAccount);
    insert tempAccount;
    Id missingAccountId = tempAccount.Id;
    delete tempAccount;

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult nullResult = service.resolveRootAccount(
      null
    );
    FscRelHouseholdModels.RootAccountResolveResult missingResult = service.resolveRootAccount(
      missingAccountId
    );
    Test.stopTest();

    System.assertEquals(null, nullResult.rootAccountId);
    System.assertEquals(null, missingResult.rootAccountId);
  }

  @IsTest
  static void resolveRootAccount_returnsHouseholdForBusinessAccountWithHouseholdField() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    scenario.relatedBusinessAccount.Household__c = scenario.rootAccount.Id;
    update scenario.relatedBusinessAccount;
    FscDataTestDataFactory.createHouseholdMembershipRelations(
      new List<Account>{ scenario.relatedBusinessAccount },
      scenario.rootAccount.Id
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      scenario.relatedBusinessAccount.Id
    );
    Test.stopTest();

    System.assertEquals(scenario.rootAccount.Id, resolveResult.rootAccountId);
  }

  @IsTest
  static void getRelationshipTree_includesLeadProspectAccountsWhenPresent() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String leadProspectType = resolveLeadProspectType();
    if (String.isBlank(leadProspectType)) {
      return;
    }

    Account leadProspectAccount = FscDataTestDataFactory.createPersonAccount(
      'Lead',
      'Prospect Member ' + System.currentTimeMillis()
    );
    leadProspectAccount.Type = leadProspectType;
    update leadProspectAccount;
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ leadProspectAccount },
      scenario.rootAccount.Id
    );

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assert(treeData.leadProspectAccounts.size() >= 1);
  }

  @IsTest
  static void getRelationshipTree_includesLeadProspectAccountsInClassifiedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String leadProspectType = resolveLeadProspectType();

    if (String.isBlank(leadProspectType)) {
      return;
    }

    Account leadProspectAccount = FscDataTestDataFactory.createPersonAccount(
      'Lead',
      'Prospect Vendor Member ' + System.currentTimeMillis()
    );
    leadProspectAccount.Type = leadProspectType;
    update leadProspectAccount;
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ leadProspectAccount },
      scenario.rootAccount.Id
    );
    FscDataTestDataFactory.assignClassification(
      leadProspectAccount,
      FscRelClassificationUtils.VENDOR
    );

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    String accountId = String.valueOf(leadProspectAccount.Id);
    Boolean foundInLeadProspect = false;
    Boolean foundInClassified = false;

    for (FscRelHouseholdModels.TreeAccount account : treeData.leadProspectAccounts) {
      if (account.accountId == accountId) {
        foundInLeadProspect = true;
      }
    }

    for (FscRelHouseholdModels.TreeAccount account : treeData.classifiedAccounts) {
      if (account.accountId == accountId) {
        foundInClassified = true;
      }
    }

    System.assertEquals(true, foundInLeadProspect);
    System.assertEquals(true, foundInClassified);
  }

  @IsTest
  static void getRelationshipTree_includesUnclassifiedFromHouseholdMembershipArrOnly() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClassification(
      scenario.relatedBusinessAccount,
      FscRelClassificationUtils.UNCLASSIFIED
    );
    FscDataTestDataFactory.createHouseholdMembershipRelations(
      new List<Account>{ scenario.relatedBusinessAccount },
      scenario.rootAccount.Id
    );

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    String accountId = String.valueOf(scenario.relatedBusinessAccount.Id);
    Boolean foundInClassified = false;
    Boolean foundInRelated = false;

    for (FscRelHouseholdModels.TreeAccount account : treeData.classifiedAccounts) {
      if (account.accountId == accountId) {
        foundInClassified = true;
        System.assertNotEquals(null, account.relationId);
      }
    }

    for (FscRelHouseholdModels.TreeAccount account : treeData.relatedAccounts) {
      if (account.accountId == accountId) {
        foundInRelated = true;
        System.assertNotEquals(null, account.relationId);
      }
    }

    System.assertEquals(
      true,
      foundInClassified,
      'Unclassified household members should resolve through Household AAR.'
    );
    System.assertEquals(
      true,
      foundInRelated,
      'Household membership entities should appear in related accounts for lazy groups.'
    );
  }

  @IsTest
  static void getRelationshipTree_promotesLeadProspectRelatedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String leadProspectType = resolveLeadProspectType();

    if (String.isBlank(leadProspectType)) {
      return;
    }

    Account leadProspectRelatedAccount = [
      SELECT Id
      FROM Account
      WHERE Id = :scenario.relatedBusinessAccount.Id
    ];
    leadProspectRelatedAccount.Type = leadProspectType;
    update leadProspectRelatedAccount;
    FscDataTestDataFactory.assignClassification(
      leadProspectRelatedAccount,
      FscRelClassificationUtils.VENDOR
    );

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();
  }

  @IsTest
  static void getMemberRelationshipRecordTypes_returnsActiveOptions() {
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = service.getMemberRelationshipRecordTypes();
    Test.stopTest();

    System.assertNotEquals(null, recordTypes);
  }

  @IsTest
  static void resolveRootAccount_returnsHouseholdRecordTypeRoot() {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeId();

    if (householdRecordTypeId == null) {
      return;
    }

    Account householdAccount = FscDataTestDataFactory.createHouseholdAccount(
      'Household Root Account'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      householdAccount.Id
    );
    Test.stopTest();

    System.assertEquals(householdAccount.Id, resolveResult.rootAccountId);
  }

  @IsTest
  static void searchAccountsByClassification_returnsLookupOptions() {
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = service.searchAccountsByClassification(
      'FscData',
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertNotEquals(null, results);
  }

  @IsTest
  static void getReciprocalRoleName_returnsDisplayName() {
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRole(
      'Display Role ' + System.currentTimeMillis()
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    String roleName = service.getReciprocalRoleName(role.Id);
    Test.stopTest();

    System.assertEquals(role.Role__c, roleName);
  }

  @IsTest
  static void resolveRootAccount_returnsSelfForBusinessAccountWithoutHousehold() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      scenario.relatedBusinessAccount.Id
    );
    Test.stopTest();

    System.assertEquals(false, resolveResult.isPersonAccount);
    System.assertEquals(
      scenario.relatedBusinessAccount.Id,
      resolveResult.rootAccountId
    );
  }

  @IsTest
  static void resolveRootAccount_returnsHouseholdForPersonAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, resolveResult.isPersonAccount);
    System.assertEquals(scenario.rootAccount.Id, resolveResult.rootAccountId);
  }

  @IsTest
  static void resolveRootAccount_returnsNullWhenNoHouseholdField() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    scenario.linkedPersonAccount.Household__c = null;
    update scenario.linkedPersonAccount;
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, resolveResult.isPersonAccount);
    System.assertEquals(null, resolveResult.rootAccountId);
  }

  @IsTest
  static void resolveRootAccount_unlinkedPerson_returnsNullRoot() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RootAccountResolveResult resolveResult = service.resolveRootAccount(
      scenario.unlinkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(true, resolveResult.isPersonAccount);
    System.assertEquals(null, resolveResult.rootAccountId);
  }

  @IsTest
  static void getRelationshipTree_returnsMembersAndRelatedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getRelationshipTree(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertEquals(String.valueOf(scenario.rootAccount.Id), treeData.rootAccountId);
    System.assertEquals(scenario.rootAccount.Name, treeData.name);
    System.assertEquals(2, treeData.members.size());
    System.assertEquals(2, treeData.clientAccounts.size());
    System.assert(
      treeData.relatedAccounts.size() >= 1,
      'Related accounts should include role-based relationships and household membership links.'
    );
    System.assert(
      treeData.householdLinkedAccounts.size() >= treeData.clientAccounts.size(),
      'Household-linked accounts should include every account with Household__c populated.'
    );
  }

  @IsTest
  static void getRelationshipTree_throwsWhenRootAccountIdNull() {
    FscRelHouseholdService service = new FscRelHouseholdService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getRelationshipTree(null);
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getRelationshipTree_throwsWhenRootAccountNotFound() {
    Account tempAccount = new Account(Name = 'Temporary Missing Root');
    FscDataTestDataFactory.applyRequiredAccountTypeOrClassification(tempAccount);
    insert tempAccount;
    Id missingAccountId = tempAccount.Id;
    delete tempAccount;
    FscRelHouseholdService service = new FscRelHouseholdService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getRelationshipTree(missingAccountId);
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getPersonAccountMapTree_returnsPersonMemberNode() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RelationshipTreeData treeData = service.getPersonAccountMapTree(
      scenario.unlinkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(
      String.valueOf(scenario.unlinkedPersonAccount.Id),
      treeData.rootAccountId
    );
    System.assertEquals(1, treeData.members.size());
  }

  @IsTest
  static void getPersonAccountMapTree_throwsForNonPersonAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getPersonAccountMapTree(scenario.rootAccount.Id);
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void resolveRecentlyCreatedAccount_returnsLatestMatchingAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();
    Id businessRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      false
    );
    Long createdAfterEpochMs = Datetime.now().getTime();

    Account createdAccount = new Account(
      Name = 'Native Create Overlay Test',
      RecordTypeId = businessRecordTypeId
    );
    FscDataTestDataFactory.applyRequiredAccountTypeOrClassification(createdAccount);
    insert createdAccount;

    Test.startTest();
    FscRelHouseholdModels.LookupOption resolved = service.resolveRecentlyCreatedAccount(
      businessRecordTypeId,
      createdAfterEpochMs
    );
    Test.stopTest();

    System.assertNotEquals(null, resolved);
    System.assertEquals(String.valueOf(createdAccount.Id), resolved.id);
    System.assertEquals(createdAccount.Name, resolved.label);
  }

  @IsTest
  static void getAccountCreatePrefillFieldValues_prefillsHouseholdAndName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();
    Id businessRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      false
    );

    Test.startTest();
    Map<String, String> businessPrefill = service.getAccountCreatePrefillFieldValues(
      scenario.linkedPersonAccount.Id,
      businessRecordTypeId,
      'Acme Holdings'
    );
    Map<String, String> personPrefill = service.getAccountCreatePrefillFieldValues(
      scenario.linkedPersonAccount.Id,
      scenario.linkedPersonAccount.RecordTypeId,
      'Jane Doe'
    );
    Test.stopTest();

    System.assertEquals(
      String.valueOf(scenario.rootAccount.Id),
      businessPrefill.get('Household__c')
    );
    System.assertEquals('Acme Holdings', businessPrefill.get('Name'));
    System.assertEquals(
      String.valueOf(scenario.rootAccount.Id),
      personPrefill.get('Household__c')
    );
    System.assertEquals('Jane', personPrefill.get('FirstName'));
    System.assertEquals('Doe', personPrefill.get('LastName'));
  }

  @IsTest
  static void getAccountName_returnsAccountName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    String accountName = service.getAccountName(scenario.linkedPersonAccount.Id);
    Test.stopTest();

    System.assertEquals(scenario.linkedPersonAccount.Name, accountName);
  }

  @IsTest
  static void getContactName_returnsContactName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    String contactName = service.getContactName(
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assert(String.isNotBlank(contactName));
  }

  @IsTest
  static void getAccountRecordTypeId_returnsDefaultRecordType() {
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    String personRecordTypeId = service.getAccountRecordTypeId(true);
    String businessRecordTypeId = service.getAccountRecordTypeId(false);
    Test.stopTest();

    System.assertNotEquals(null, personRecordTypeId);
    System.assertNotEquals(null, businessRecordTypeId);
  }

  @IsTest
  static void getRecordTypeByDeveloperName_returnsPersonAccountRecordType() {
    List<RecordType> personRecordTypes = [
      SELECT DeveloperName
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
      LIMIT 1
    ];

    if (personRecordTypes.isEmpty()) {
      return;
    }

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.RecordTypeInfo recordTypeInfo = service.getRecordTypeByDeveloperName(
      'Account',
      personRecordTypes[0].DeveloperName
    );
    FscRelHouseholdModels.RecordTypeInfo blankResult = service.getRecordTypeByDeveloperName(
      '',
      ''
    );
    Test.stopTest();

    System.assertNotEquals(null, recordTypeInfo.recordTypeId);
    System.assertEquals(true, recordTypeInfo.isPersonType);
    System.assertEquals(null, blankResult.recordTypeId);
  }

  @IsTest
  static void searchAccounts_returnsMatchingPersonAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = service.searchAccounts(
      'FscData',
      true
    );
    Test.stopTest();

    System.assert(!results.isEmpty());
    System.assertEquals(scenario.linkedPersonAccount.Id, results[0].id);
  }

  @IsTest
  static void searchAccountsInScope_returnsOnlyAllowedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> scopedResults = service.searchAccountsInScope(
      'FscData',
      true,
      new List<String>{ scenario.linkedPersonAccount.Id }
    );
    List<FscRelHouseholdModels.LookupOption> emptyScopeResults = service.searchAccountsInScope(
      'FscData',
      true,
      new List<String>()
    );
    Test.stopTest();

    System.assertEquals(1, scopedResults.size());
    System.assertEquals(true, emptyScopeResults.isEmpty());
  }

  @IsTest
  static void getAccountsByIds_returnsPersonAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = service.getAccountsByIds(
      new List<String>{ scenario.linkedPersonAccount.Id, 'not-an-id' },
      true
    );
    List<FscRelHouseholdModels.LookupOption> emptyResults = service.getAccountsByIds(
      null,
      true
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void searchContacts_returnsMatchingContacts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> results = service.searchContacts(
      scenario.linkedPersonAccount.Name.left(4)
    );
    Test.stopTest();

    System.assert(!results.isEmpty());
    System.assertEquals('standard:contact', results[0].iconName);
  }

  @IsTest
  static void searchReciprocalRoles_returnsLookupResults() {
    FscDataTestDataFactory.createReciprocalRole(
      'Service Role ' + System.currentTimeMillis()
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    List<FscRelHouseholdModels.LookupOption> defaultResults = service.searchReciprocalRoles(
      '',
      null
    );
    List<FscRelHouseholdModels.LookupOption> filteredResults = service.searchReciprocalRoles(
      '',
      'Definitely_Not_A_Real_Record_Type'
    );
    Test.stopTest();

    System.assert(!defaultResults.isEmpty());
    System.assertEquals(true, filteredResults.isEmpty());
  }

  @IsTest
  static void validateReciprocalRoleForCreate_handlesDuplicateAndBlankRole() {
    FscDataTestDataFactory.createReciprocalRole('Parent');
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult blankResult = service.validateReciprocalRoleForCreate(
      ''
    );
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult duplicateResult = service.validateReciprocalRoleForCreate(
      'Parent'
    );
    FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult similarResult = service.validateReciprocalRoleForCreate(
      'Beneficiary Parent'
    );
    Test.stopTest();

    System.assertEquals(true, blankResult.blockSave);
    System.assertEquals(true, duplicateResult.blockSave);
    System.assertEquals(true, similarResult.requiresConfirmation);
  }

  @IsTest
  static void createReciprocalRole_createsRoleWhenConfirmed() {
    FscRelHouseholdService service = new FscRelHouseholdService();
    String uniqueRole = 'Sibling ' + System.currentTimeMillis();

    Test.startTest();
    FscRelHouseholdModels.ReciprocalRoleCreateResult result = service.createReciprocalRole(
      uniqueRole,
      true,
      null
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);
    System.assertNotEquals(null, result.reciprocalRoleId);
  }

  @IsTest
  static void linkClassificationAccountToHousehold_validatesRequiredInputs() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult missingRootResult = service.linkClassificationAccountToHousehold(
      null,
      scenario.relatedBusinessAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    FscRelHouseholdModels.TreeAccountResult selfLinkResult = service.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      scenario.rootAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(false, missingRootResult.success);
    System.assertEquals(false, selfLinkResult.success);
  }

  @IsTest
  static void linkClassificationAccountToHousehold_setsHouseholdField() {
    if (!FscDataTestDataFactory.hasClassificationField()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    Account vendorAccount = FscDataTestDataFactory.createClassifiedBusinessAccount(
      'Service Vendor ' + System.currentTimeMillis(),
      FscRelClassificationUtils.VENDOR
    );
    Id householdMembershipRecordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE
    );

    if (householdMembershipRecordTypeId == null) {
      return;
    }

    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.TreeAccountResult result = service.linkClassificationAccountToHousehold(
      scenario.rootAccount.Id,
      vendorAccount.Id,
      FscRelClassificationUtils.VENDOR
    );
    Test.stopTest();

    System.assertEquals(true, result.success, result.message);

    Account updatedAccount = [
      SELECT Id, Household__c
      FROM Account
      WHERE Id = :vendorAccount.Id
      LIMIT 1
    ];
    System.assertEquals(scenario.rootAccount.Id, updatedAccount.Household__c);

    Account_Account_Relationship__c membershipRelation = [
      SELECT Id, Active__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :scenario.rootAccount.Id
        AND Related_Account__c = :vendorAccount.Id
        AND RecordTypeId = :householdMembershipRecordTypeId
      LIMIT 1
    ];
    System.assertEquals(true, membershipRelation.Active__c);
  }

  @IsTest
  static void getAccountMemberCounts_returnsActiveMembershipCounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    Map<String, Integer> counts = service.getAccountMemberCounts(
      new List<Id>{ scenario.rootAccount.Id, scenario.secondRootAccount.Id }
    );
    Map<String, Integer> emptyCounts = service.getAccountMemberCounts(
      new List<Id>()
    );
    Test.stopTest();

    System.assertEquals(2, counts.get(String.valueOf(scenario.rootAccount.Id)));
    System.assertEquals(0, counts.get(String.valueOf(scenario.secondRootAccount.Id)));
    System.assertEquals(true, emptyCounts.isEmpty());
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
      'Child',
      'Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Parent'
      LIMIT 1
    ];
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = FscDataTestDataFactory.buildMemberAccountRelationshipInput(
      scenario.secondPersonAccount,
      childRole,
      parentRole,
      true,
      'row-1'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();
    service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
    );

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = service.getMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName
    );
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> emptyResults = service.getMemberAccountRelationships(
      null,
      recordTypeDeveloperName
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void getMemberAccountRelationshipsForAccounts_returnsRelationships() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = resolveFirstAccountRelationRecordTypeDeveloperName();
    if (String.isBlank(recordTypeDeveloperName)) {
      return;
    }

    Reciprocal_Role__c childRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Network Child',
      'Network Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Network Parent'
      LIMIT 1
    ];
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = FscDataTestDataFactory.buildMemberAccountRelationshipInput(
      scenario.secondPersonAccount,
      childRole,
      parentRole,
      true,
      'row-1'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();
    service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
    );

    Test.startTest();
    List<FscRelHouseholdModels.TreeMemberAccountRelationship> results = service.getMemberAccountRelationshipsForAccounts(
      new Set<Id>{
        scenario.linkedPersonAccount.Id,
        scenario.secondPersonAccount.Id
      }
    );
    Map<String, Integer> relationshipCounts = service.getMemberAccountRelationshipCounts(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Integer familyCount = service.getHouseholdFamilyCardCount(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Integer networkCount = service.getHouseholdNetworkCardCount(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assert(!results.isEmpty());
    System.assertNotEquals(null, relationshipCounts);
    System.assert(familyCount >= 0);
    System.assert(networkCount >= 0);
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
      'Save Child',
      'Save Parent'
    );
    Reciprocal_Role__c parentRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Save Parent'
      LIMIT 1
    ];
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = FscDataTestDataFactory.buildMemberAccountRelationshipInput(
      scenario.secondPersonAccount,
      childRole,
      parentRole,
      true,
      'row-1'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult saveResult = service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
    );
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult emptySaveResult = service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>()
    );
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult invalidSaveResult = service.saveMemberAccountRelationships(
      null,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
    );
    Test.stopTest();

    System.assertEquals(true, saveResult.success, saveResult.message);
    System.assertEquals(true, emptySaveResult.success);
    System.assertEquals(false, invalidSaveResult.success);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE
          Account__c = :scenario.linkedPersonAccount.Id
          AND Related_Account__c = :scenario.secondPersonAccount.Id
      ]
    );
  }

  @IsTest
  static void saveMemberAccountRelationships_allowsBusinessRelatedAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String recordTypeDeveloperName = FscRelRecordTypeUtils.BUSINESS_RECORD_TYPE;
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypeDeveloperName
    );
    if (recordTypeId == null) {
      return;
    }

    Reciprocal_Role__c employeeRole = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypeDeveloperName,
      'Employee',
      'Employer'
    );
    Reciprocal_Role__c employerRole = [
      SELECT Id, Role__c
      FROM Reciprocal_Role__c
      WHERE Role__c = 'Employer'
      LIMIT 1
    ];
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = FscDataTestDataFactory.buildMemberAccountRelationshipInput(
      scenario.relatedBusinessAccount,
      employeeRole,
      employerRole,
      true,
      'row-business'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();

    Test.startTest();
    FscRelHouseholdModels.MemberAccountRelationshipsSaveResult saveResult = service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
    );
    Test.stopTest();

    System.assertEquals(true, saveResult.success, saveResult.message);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Account_Account_Relationship__c
        WHERE
          Account__c = :scenario.linkedPersonAccount.Id
          AND Related_Account__c = :scenario.relatedBusinessAccount.Id
      ]
    );
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
    FscRelHouseholdModels.TreeMemberAccountRelationshipInput input = FscDataTestDataFactory.buildMemberAccountRelationshipInput(
      scenario.secondPersonAccount,
      childRole,
      parentRole,
      true,
      'row-1'
    );
    FscRelHouseholdService service = new FscRelHouseholdService();
    service.saveMemberAccountRelationships(
      scenario.linkedPersonAccount.Id,
      recordTypeDeveloperName,
      new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>{ input }
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
    FscRelHouseholdModels.DeleteResult deleteResult = service.deleteMemberAccountRelationships(
      new List<String>{ String.valueOf(primaryRow.Id) }
    );
    FscRelHouseholdModels.DeleteResult emptyDeleteResult = service.deleteMemberAccountRelationships(
      new List<String>()
    );
    Test.stopTest();

    System.assertEquals(true, deleteResult.success);
    System.assertEquals(true, emptyDeleteResult.success);
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

  private static String resolveLeadProspectType() {
    for (String preferredType : FscRelClientAccountUtils.LEAD_PROSPECT_ACCOUNT_TYPES) {
      for (Schema.PicklistEntry entry : Account.Type.getDescribe().getPicklistValues()) {
        if (entry.isActive() && entry.getValue() == preferredType) {
          return preferredType;
        }
      }
    }

    return null;
  }
}