/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
@IsTest
private class FscRelRelationshipTreeServiceTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  private static void assignHouseholdMembers(
    FscDataTestDataFactory.TreeScenario scenario
  ) {
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{
        scenario.linkedPersonAccount,
        scenario.secondPersonAccount
      },
      scenario.rootAccount.Id
    );
  }

  private static void removeHouseholdMembership(
    Id householdId,
    Id memberAccountId
  ) {
    Id householdRecordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      FscRelRecordTypeUtils.HOUSEHOLD_AAR_RECORD_TYPE
    );

    if (householdRecordTypeId == null) {
      return;
    }

    delete [
      SELECT Id
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :householdId
        AND Related_Account__c = :memberAccountId
        AND RecordTypeId = :householdRecordTypeId
    ];
  }

  @IsTest
  static void buildMemberAccountIds_householdLaunch_usesHouseholdFieldOnly() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    assignHouseholdMembers(scenario);
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Set<Id> memberAccountIds = service.buildMemberAccountIds(
      scenario.rootAccount.Id,
      null,
      true
    );
    Test.stopTest();

    System.assert(
      memberAccountIds.contains(scenario.linkedPersonAccount.Id),
      'Expected linked person account from Household__c.'
    );
    System.assert(
      memberAccountIds.contains(scenario.secondPersonAccount.Id),
      'Expected second person account from Household__c.'
    );
  }

  @IsTest
  static void buildMemberAccountIds_householdLaunch_ignoresAcrOnlyMembers() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    assignHouseholdMembers(scenario);
    removeHouseholdMembership(
      scenario.rootAccount.Id,
      scenario.secondPersonAccount.Id
    );
    scenario.secondPersonAccount.Household__c = null;
    update scenario.secondPersonAccount;
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Set<Id> memberAccountIds = service.buildMemberAccountIds(
      scenario.rootAccount.Id,
      null,
      true
    );
    Test.stopTest();

    System.assert(
      memberAccountIds.contains(scenario.linkedPersonAccount.Id),
      'Expected household field member.'
    );
    System.assert(
      !memberAccountIds.contains(scenario.secondPersonAccount.Id),
      'ACR-only members should not be included for household launch.'
    );
  }

  @IsTest
  static void buildMemberAccountIds_nonHouseholdLaunch_includesHouseholdFieldMembers() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.linkedPersonAccount },
      scenario.rootAccount.Id
    );
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Set<Id> memberAccountIds = service.buildMemberAccountIds(
      scenario.rootAccount.Id,
      scenario.unlinkedPersonAccount.Id,
      false
    );
    Test.stopTest();

    System.assert(
      memberAccountIds.contains(scenario.linkedPersonAccount.Id),
      'Expected household field member on non-household context.'
    );
    System.assert(
      !memberAccountIds.contains(scenario.rootAccount.Id),
      'Household root accounts should not be included in client scope.'
    );
  }

  @IsTest
  static void getGroupedContactSuggestions_nonHouseholdLaunch_excludesContextAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.linkedPersonAccount },
      scenario.rootAccount.Id
    );
    Account vendorContextAccount = FscDataTestDataFactory.createClassifiedBusinessAccount(
      'Tree Vendor Context ' + System.currentTimeMillis(),
      FscRelClassificationUtils.VENDOR
    );
    for (
      Schema.PicklistEntry entry : Account.Type.getDescribe().getPicklistValues()
    ) {
      if (
        entry.isActive() &&
        !FscRelClientAccountUtils.CLIENT_ACCOUNT_TYPES.contains(
          entry.getValue()
        )
      ) {
        vendorContextAccount.Type = entry.getValue();
        update vendorContextAccount;
        break;
      }
    }
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    List<FscRelRelationshipTreeModels.GroupedAccountContacts> groups = service.getGroupedContactSuggestions(
      scenario.rootAccount.Id,
      vendorContextAccount.Id,
      new Set<Id>(),
      false
    );
    Test.stopTest();

    Set<String> suggestedAccountIds = new Set<String>();
    for (FscRelRelationshipTreeModels.GroupedAccountContacts contactGroup : groups) {
      for (
        FscRelRelationshipTreeModels.ScopedAccountSummary contact : contactGroup.contacts
      ) {
        suggestedAccountIds.add(contact.accountId);
      }
    }

    System.assert(
      suggestedAccountIds.contains(String.valueOf(scenario.linkedPersonAccount.Id)),
      'Expected household field member in suggestions.'
    );
    System.assert(
      !suggestedAccountIds.contains(String.valueOf(vendorContextAccount.Id)),
      'Non-client context accounts should not appear in suggestions.'
    );
  }

  @IsTest
  static void buildMemberAccountIds_nonHouseholdLaunch_usesContextAccountOnly() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    assignHouseholdMembers(scenario);
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Set<Id> memberAccountIds = service.buildMemberAccountIds(
      scenario.rootAccount.Id,
      scenario.linkedPersonAccount.Id,
      false
    );
    Test.stopTest();

    System.assert(memberAccountIds.contains(scenario.linkedPersonAccount.Id));
  }

  @IsTest
  static void getGroupedContactSuggestions_returnsClientsFamilyAndNetwork() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    assignHouseholdMembers(scenario);
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    List<FscRelRelationshipTreeModels.GroupedAccountContacts> groups = service.getGroupedContactSuggestions(
      scenario.rootAccount.Id,
      null,
      new Set<Id>(),
      true
    );
    Test.stopTest();

    System.assertEquals(3, groups.size());
    System.assertEquals('Clients', groups[0].category);
    System.assert(groups[0].contacts.size() > 0, 'Expected client suggestions.');
    System.assertEquals('Family and Friends', groups[1].category);
    System.assertEquals('Network', groups[2].category);
  }

  @IsTest
  static void getMemberRelationshipsByMemberAccountIds_groupsByMemberAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (!recordTypes.isEmpty()) {
      Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
        recordTypes[0].developerName
      );
      Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
        recordTypes[0].developerName,
        'Tree Family Role',
        'Tree Family Role'
      );
      insert new Account_Account_Relationship__c(
        Account__c = scenario.linkedPersonAccount.Id,
        Related_Account__c = scenario.secondPersonAccount.Id,
        RecordTypeId = recordTypeId,
        Reciprocal_Role__c = role.Id,
        Inverse_Reciprocal_Role__c = role.Id,
        Active__c = true
      );
    }

    Test.startTest();
    Map<String, List<FscRelHouseholdModels.TreeMemberAccountRelationship>> relationshipsByAccountId = FscRelRelationshipTreeController.getMemberRelationshipsByMemberAccountIds(
      new List<Id>{ scenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertNotEquals(null, relationshipsByAccountId);
    System.assert(
      relationshipsByAccountId.containsKey(
        String.valueOf(scenario.linkedPersonAccount.Id)
      ),
      'Expected member account key in relationship map.'
    );
  }

  @IsTest
  static void resolveHouseholdId_usesHouseholdFieldWhenPresent() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscDataTestDataFactory.assignClientHousehold(
      new List<Account>{ scenario.linkedPersonAccount },
      scenario.rootAccount.Id
    );
    scenario = scenario.reload();
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Id resolvedHouseholdId = service.resolveHouseholdId(
      scenario.linkedPersonAccount.Id
    );
    Id nullAccountHouseholdId = service.resolveHouseholdId((Account) null);
    Test.stopTest();

    System.assertEquals(scenario.rootAccount.Id, resolvedHouseholdId);
    System.assertEquals(null, nullAccountHouseholdId);
  }

  @IsTest
  static void resolveHouseholdId_returnsHouseholdAccountId() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Tree Service Household'
    );
    FscRelRelationshipTreeService service = new FscRelRelationshipTreeService();

    Test.startTest();
    Id resolvedHouseholdId = service.resolveHouseholdId(household.Id);
    Id nullHouseholdId = service.resolveHouseholdId((Id) null);
    Id resolvedFromAccount = service.resolveHouseholdId(household);
    Test.stopTest();

    System.assertEquals(household.Id, resolvedHouseholdId);
    System.assertEquals(null, nullHouseholdId);
    System.assertEquals(household.Id, resolvedFromAccount);
  }
}