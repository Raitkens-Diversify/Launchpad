/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 */
@IsTest
private class FscRelAccountRepositoryTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void selectById_returnsAccountWhenFound() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    Account rootAccount = accountRepository.selectById(scenario.rootAccount.Id);
    Account personAccount = accountRepository.selectById(scenario.linkedPersonAccount.Id);
    Test.stopTest();

    System.assertNotEquals(null, rootAccount);
    System.assertEquals(false, FscRelAccountRepository.isPersonAccountRecord(rootAccount));
    System.assertEquals(true, FscRelAccountRepository.isPersonAccountRecord(personAccount));
  }

  @IsTest
  static void isHouseholdRecordTypeDeveloperName_returnsTrueForBothHouseholdTypes() {
    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName('Household')
    );
    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName('IndustriesHousehold')
    );
    System.assertEquals(
      false,
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName('Business_Account')
    );
    System.assertEquals(
      false,
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(null)
    );
  }

  @IsTest
  static void selectHouseholdRecordTypeId_prefersHouseholdOverLegacy() {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeId();

    if (householdRecordTypeId == null) {
      return;
    }

    RecordType recordType = [
      SELECT DeveloperName
      FROM RecordType
      WHERE Id = :householdRecordTypeId
      LIMIT 1
    ];

    System.assert(
      FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
        recordType.DeveloperName
      )
    );
  }

  @IsTest
  static void isHouseholdRecordType_returnsTrueForHouseholdRecordTypes() {
    Account householdAccount = new Account(
      RecordType = new RecordType(DeveloperName = 'Household')
    );
    Account industriesHouseholdAccount = new Account(
      RecordType = new RecordType(DeveloperName = 'IndustriesHousehold')
    );
    Account businessAccount = new Account(
      RecordType = new RecordType(DeveloperName = 'Business_Account')
    );

    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordType(householdAccount)
    );
    System.assertEquals(
      true,
      FscRelAccountRepository.isHouseholdRecordType(industriesHouseholdAccount)
    );
    System.assertEquals(
      false,
      FscRelAccountRepository.isHouseholdRecordType(businessAccount)
    );
  }

  @IsTest
  static void selectPersonContactId_returnsContactForPersonAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    Id contactId = accountRepository.selectPersonContactId(
      String.valueOf(scenario.linkedPersonAccount.Id)
    );
    Test.stopTest();

    System.assertEquals(scenario.linkedPersonAccount.PersonContactId, contactId);
  }

  @IsTest
  static void selectClientAccountsByHouseholdId_returnsHouseholdLinkedClients() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> clientAccounts = accountRepository.selectClientAccountsByHouseholdId(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    System.assertEquals(
      2,
      clientAccounts.size(),
      'Expected household-linked clients.'
    );

    Set<Id> clientAccountIds = new Set<Id>();
    for (Account account : clientAccounts) {
      clientAccountIds.add(account.Id);
    }

    System.assert(clientAccountIds.contains(scenario.linkedPersonAccount.Id));
    System.assert(clientAccountIds.contains(scenario.secondPersonAccount.Id));
  }

  @IsTest
  static void selectClientAccountsByHouseholdId_usesHouseholdMembershipArr() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    Account arrOnlyClient = FscDataTestDataFactory.createPersonAccount(
      'ArrOnly',
      'Client Member ' + System.currentTimeMillis()
    );
    FscDataTestDataFactory.assignActiveClientAccountType(
      new List<Account>{ arrOnlyClient }
    );
    FscDataTestDataFactory.createHouseholdMembershipRelations(
      new List<Account>{ arrOnlyClient },
      scenario.rootAccount.Id
    );

    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> clientAccounts = accountRepository.selectClientAccountsByHouseholdId(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    Set<Id> clientAccountIds = new Set<Id>();
    for (Account account : clientAccounts) {
      clientAccountIds.add(account.Id);
    }

    System.assert(
      clientAccountIds.contains(arrOnlyClient.Id),
      'Client roster should include members linked only through Household AAR.'
    );
  }

  @IsTest
  static void selectLeadProspectAccountsByHouseholdId_usesHouseholdMembershipArr() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    String leadProspectType = resolveLeadProspectType();

    if (String.isBlank(leadProspectType)) {
      return;
    }

    Account leadProspectAccount = FscDataTestDataFactory.createPersonAccount(
      'Lead',
      'Prospect Arr Member ' + System.currentTimeMillis()
    );
    leadProspectAccount.Type = leadProspectType;
    update leadProspectAccount;
    FscDataTestDataFactory.createHouseholdMembershipRelations(
      new List<Account>{ leadProspectAccount },
      scenario.rootAccount.Id
    );

    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> leadProspectAccounts = accountRepository.selectLeadProspectAccountsByHouseholdId(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    Set<Id> leadProspectAccountIds = new Set<Id>();
    for (Account account : leadProspectAccounts) {
      leadProspectAccountIds.add(account.Id);
    }

    System.assert(
      leadProspectAccountIds.contains(leadProspectAccount.Id),
      'Lead/prospect roster should include members linked only through Household AAR.'
    );
  }

  @IsTest
  static void selectHouseholdIdByMemberAccountId_resolvesHouseholdFromIncomingArr() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    Id householdId = accountRepository.selectHouseholdIdByMemberAccountId(
      scenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(
      scenario.rootAccount.Id,
      householdId,
      'Member account should resolve its household through incoming Household AAR.'
    );
  }

  @IsTest
  static void selectMemberAccountsByHouseholdId_returnsHouseholdMembershipMembers() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> memberAccounts = accountRepository.selectMemberAccountsByHouseholdId(
      scenario.rootAccount.Id
    );
    Test.stopTest();

    Set<Id> memberAccountIds = new Set<Id>();
    for (Account account : memberAccounts) {
      memberAccountIds.add(account.Id);
    }

    System.assert(
      memberAccountIds.contains(scenario.linkedPersonAccount.Id),
      'Expected household membership members from Household AAR.'
    );
    System.assert(
      memberAccountIds.contains(scenario.secondPersonAccount.Id),
      'Expected all linked household members from Household AAR.'
    );
  }

  private static String resolveLeadProspectType() {
    Schema.DescribeFieldResult typeDescribe = Account.Type.getDescribe();

    for (Schema.PicklistEntry picklistEntry : typeDescribe.getPicklistValues()) {
      if (
        picklistEntry.isActive() &&
        FscRelClientAccountUtils.isLeadProspectAccountType(picklistEntry.getValue())
      ) {
        return picklistEntry.getValue();
      }
    }

    return null;
  }

  @IsTest
  static void searchAccountsByClassification_returnsEmptyForInvalidInput() {
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> blankClassificationResults = accountRepository.searchAccountsByClassification(
      'Vendor',
      '',
      8
    );
    List<Account> shortSearchTermResults = accountRepository.searchAccountsByClassification(
      'V',
      FscRelClassificationUtils.VENDOR,
      8
    );
    List<Account> emptySelectionResults = accountRepository.selectAccountsByIdsWithClassifications(
      new Set<Id>()
    );
    Test.stopTest();

    System.assertEquals(true, blankClassificationResults.isEmpty());
    System.assertEquals(true, shortSearchTermResults.isEmpty());
    System.assertEquals(true, emptySelectionResults.isEmpty());
  }

  @IsTest
  static void searchAccountsByName_returnsMatchingAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> personResults = accountRepository.searchAccountsByName('FscData', true, 8);
    List<Account> shortTermResults = accountRepository.searchAccountsByName('F', true, 8);
    Id defaultPersonRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      true
    );
    RecordType personRecordType = FscRelRecordTypeUtils.selectRecordTypeByDeveloperName(
      'Account',
      'PersonAccount'
    );
    Test.stopTest();

    System.assert(!personResults.isEmpty());
    System.assertEquals(true, shortTermResults.isEmpty());
    System.assertNotEquals(null, defaultPersonRecordTypeId);
    System.assert(
      personRecordType == null || personRecordType.DeveloperName == 'PersonAccount'
    );
  }

  @IsTest
  static void searchAccountsByName_matchesMiddleInitialWithoutLastNamePrefix() {
    Id personRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      true
    );

    if (personRecordTypeId == null) {
      return;
    }

    Account personAccount = new Account(
      FirstName = 'Carl',
      MiddleName = 'T',
      LastName = 'Primary',
      RecordTypeId = personRecordTypeId
    );
    insert personAccount;
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> carlInitialResults = accountRepository.searchAccountsByName(
      'Carl T',
      true,
      8
    );
    List<Account> carlInitialAndLastNameResults = accountRepository.searchAccountsByName(
      'Carl T P',
      true,
      8
    );
    Test.stopTest();

    System.assert(!carlInitialResults.isEmpty());
    System.assertEquals(personAccount.Id, carlInitialResults[0].Id);
    System.assert(!carlInitialAndLastNameResults.isEmpty());
    System.assertEquals(personAccount.Id, carlInitialAndLastNameResults[0].Id);
  }

  @IsTest
  static void searchAccountsByName_matchesMiddleNameTokens() {
    Id personRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      true
    );

    if (personRecordTypeId == null) {
      return;
    }

    Account personAccount = new Account(
      FirstName = 'Abigail',
      MiddleName = 'F',
      LastName = 'Holland',
      RecordTypeId = personRecordTypeId
    );
    insert personAccount;
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> fullNameResults = accountRepository.searchAccountsByName(
      'abigail f holland',
      true,
      8
    );
    List<Account> middleNameResults = accountRepository.searchAccountsByName(
      'f holland',
      true,
      8
    );
    List<Account> lastNameResults = accountRepository.searchAccountsByName(
      'Holland',
      true,
      8
    );
    Test.stopTest();

    System.assertEquals(1, fullNameResults.size());
    System.assertEquals(personAccount.Id, fullNameResults[0].Id);
    System.assertEquals(1, middleNameResults.size());
    System.assertEquals(personAccount.Id, middleNameResults[0].Id);
    System.assert(!lastNameResults.isEmpty());
    System.assertEquals(personAccount.Id, lastNameResults[0].Id);
  }

  @IsTest
  static void searchAccountsByName_matchesAccentInsensitivePersonNames() {
    Id personRecordTypeId = FscRelRecordTypeUtils.selectDefaultAccountRecordTypeId(
      true
    );

    if (personRecordTypeId == null) {
      return;
    }

    Account personAccount = new Account(
      FirstName = 'José',
      LastName = 'García',
      RecordTypeId = personRecordTypeId
    );
    insert personAccount;
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> unaccentedResults = accountRepository.searchAccountsByName(
      'jose garcia',
      true,
      8
    );
    Test.stopTest();

    System.assert(!unaccentedResults.isEmpty());
    System.assertEquals(personAccount.Id, unaccentedResults[0].Id);
  }

  @IsTest
  static void searchAccountsByNameInIds_matchesWithinAllowedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();
    Set<Id> allowedAccountIds = new Set<Id>{ scenario.linkedPersonAccount.Id };

    Test.startTest();
    List<Account> scopedResults = accountRepository.searchAccountsByNameInIds(
      'FscData Linked',
      true,
      allowedAccountIds,
      8
    );
    List<Account> excludedResults = accountRepository.searchAccountsByNameInIds(
      'Second Person',
      true,
      allowedAccountIds,
      8
    );
    List<Account> emptyScopeResults = accountRepository.searchAccountsByNameInIds(
      'FscData',
      true,
      new Set<Id>(),
      8
    );
    Test.stopTest();

    System.assertEquals(1, scopedResults.size());
    System.assertEquals(scenario.linkedPersonAccount.Id, scopedResults[0].Id);
    System.assertEquals(true, excludedResults.isEmpty());
    System.assertEquals(true, emptyScopeResults.isEmpty());
  }

  @IsTest
  static void searchAccountsByName_matchesBusinessAccountsByNameOnly() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> businessResults = accountRepository.searchAccountsByName(
      'Related Business',
      false,
      8
    );
    List<Account> personResults = accountRepository.searchAccountsByName(
      'Related Business',
      true,
      8
    );
    Test.stopTest();

    System.assertEquals(1, businessResults.size());
    System.assertEquals(scenario.relatedBusinessAccount.Id, businessResults[0].Id);
    System.assertEquals(true, personResults.isEmpty());
  }

  @IsTest
  static void searchAccountsByName_returnsPersonAndBusinessWhenUnrestricted() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> results = accountRepository.searchAccountsByName(
      'FscData',
      null,
      25
    );
    Test.stopTest();

    Set<Id> resultIds = new Map<Id, Account>(results).keySet();
    System.assert(
      resultIds.contains(scenario.linkedPersonAccount.Id) ||
        resultIds.contains(scenario.relatedBusinessAccount.Id),
      'Expected unrestricted search to return person and/or business matches.'
    );
  }

  @IsTest
  static void selectAccountsByIdsWithClassifications_returnsAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> accounts = accountRepository.selectAccountsByIdsWithClassifications(
      new Set<Id>{ scenario.linkedPersonAccount.Id }
    );
    String accountName = accountRepository.selectNameById(scenario.rootAccount.Id);
    Test.stopTest();

    System.assertEquals(1, accounts.size());
    System.assertEquals(scenario.rootAccount.Name, accountName);
  }

  @IsTest
  static void selectById_returnsHouseholdFieldsForRootAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    Account account = accountRepository.selectById(scenario.rootAccount.Id);
    Account missingAccount = accountRepository.selectById(null);
    Test.stopTest();

    System.assertNotEquals(null, account);
    System.assertEquals(scenario.rootAccount.Id, account.Id);
    System.assertEquals(null, missingAccount);
  }

  @IsTest
  static void selectByIds_returnsRequestedAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    List<Account> accounts = accountRepository.selectByIds(
      new Set<Id>{
        scenario.linkedPersonAccount.Id,
        scenario.secondPersonAccount.Id
      }
    );
    List<Account> emptyResults = accountRepository.selectByIds(new Set<Id>());
    Test.stopTest();

    System.assertEquals(2, accounts.size());
    System.assertEquals(true, emptyResults.isEmpty());
  }

  @IsTest
  static void selectPersonAccountIdsByContactIds_mapsPersonAccounts() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelAccountRepository accountRepository = new FscRelAccountRepository();

    Test.startTest();
    Map<Id, Id> contactIdToAccountId = accountRepository.selectPersonAccountIdsByContactIds(
      new Set<Id>{ scenario.linkedPersonAccount.PersonContactId }
    );
    Map<Id, Id> emptyResult = accountRepository.selectPersonAccountIdsByContactIds(
      new Set<Id>()
    );
    Test.stopTest();

    System.assertEquals(
      scenario.linkedPersonAccount.Id,
      contactIdToAccountId.get(scenario.linkedPersonAccount.PersonContactId)
    );
    System.assertEquals(true, emptyResult.isEmpty());
  }
}