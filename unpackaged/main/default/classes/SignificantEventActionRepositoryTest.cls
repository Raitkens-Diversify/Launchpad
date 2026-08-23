/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class SignificantEventActionRepositoryTest {
  @TestSetup
  static void setup() {
    SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions()
        .withFinancialAdvisorTeam()
        .withSignificantEvent()
        .withParticipant()
    );
  }

  @IsTest
  static void selectContextAccount_returnsNullForBlankId() {
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    System.assertEquals(null, repository.selectContextAccount(null));
  }

  @IsTest
  static void selectContextAccount_returnsAccountWhenFound() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    Account account = repository.selectContextAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, account);
    System.assertEquals(
      scenario.treeScenario.linkedPersonAccount.Id,
      account.Id
    );
  }

  @IsTest
  static void searchNonHouseholdAccounts_returnsEmptyForInvalidInput() {
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    System.assertEquals(0, repository.searchNonHouseholdAccounts('', 8).size());
    System.assertEquals(0, repository.searchNonHouseholdAccounts('a', 8).size());
    System.assertEquals(0, repository.searchNonHouseholdAccounts(null, 8).size());
    Test.stopTest();
  }

  @IsTest
  static void searchNonHouseholdAccounts_excludesHouseholdRecordType() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    List<Account> results = repository.searchNonHouseholdAccounts(
      scenario.treeScenario.linkedPersonAccount.Name.left(4),
      8
    );
    Test.stopTest();

    System.assert(results.size() > 0, 'Expected search results.');

    for (Account account : results) {
      System.assertEquals(
        false,
        FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
          account.RecordType.DeveloperName
        )
      );
    }
  }

  @IsTest
  static void selectSignificantEventById_returnsEventWhenFound() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];

    Test.startTest();
    Significant_Event__c eventRecord = repository.selectSignificantEventById(
      seededEvent.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, eventRecord);
    System.assertEquals(seededEvent.Id, eventRecord.Id);
  }

  @IsTest
  static void selectParticipantsByEventId_returnsParticipantsForEvent() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];

    Test.startTest();
    List<Significant_Event_Contact__c> participants = repository.selectParticipantsByEventId(
      seededEvent.Id
    );
    Test.stopTest();

    System.assertEquals(1, participants.size());
    System.assertEquals(
      scenario.treeScenario.linkedPersonAccount.Id,
      participants[0].Account__c
    );
  }

  @IsTest
  static void selectParticipantsByAccountIds_returnsMatchingParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    List<Significant_Event_Contact__c> participants = repository.selectParticipantsByAccountIds(
      new Set<Id>{ scenario.treeScenario.linkedPersonAccount.Id }
    );
    Test.stopTest();

    System.assertEquals(1, participants.size());
    System.assertNotEquals(null, participants[0].Significant_Event__c);
  }

  @IsTest
  static void selectParticipantsByDirectEventAccountId_returnsHouseholdEvents() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    List<Significant_Event_Contact__c> participants = repository.selectParticipantsByDirectEventAccountId(
      scenario.household.Id
    );
    Test.stopTest();

    System.assertEquals(1, participants.size());
    System.assertEquals(
      SignificantEventTestDataFactory.DEFAULT_EVENT_NAME,
      participants[0].Significant_Event__r.Name
    );
  }

  @IsTest
  static void nullGuardMethods_returnEarlyWithoutQuery() {
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    System.assertEquals(null, repository.selectSignificantEventById(null));
    System.assertEquals(0, repository.selectParticipantsByEventId(null).size());
    System.assertEquals(0, repository.selectParticipantsByAccountIds(null).size());
    System.assertEquals(0, repository.selectParticipantsByAccountIds(new Set<Id>()).size());
    System.assertEquals(
      0,
      repository.selectParticipantsByDirectEventAccountId(null).size()
    );
    repository.insertParticipants(null);
    repository.insertParticipants(new List<Significant_Event_Contact__c>());
    repository.updateParticipants(null);
    repository.deleteParticipants(null);
    repository.deleteSignificantEvent(null);
    Test.stopTest();
  }

  @IsTest
  static void searchNonHouseholdAccounts_usesDefaultLimitWhenInvalid() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();

    Test.startTest();
    List<Account> results = repository.searchNonHouseholdAccounts(
      scenario.treeScenario.linkedPersonAccount.Name.left(4),
      null
    );
    Test.stopTest();

    System.assert(results.size() > 0, 'Expected default-limit search results.');
  }

  @IsTest
  static void dmlMethods_insertUpdateAndDeleteRecords() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionRepository repository = new SignificantEventActionRepository();
    SignificantEventTestDataFactory.SignificantEventOptions eventOptions = new SignificantEventTestDataFactory.SignificantEventOptions();
    eventOptions.householdId = scenario.household.Id;
    Significant_Event__c eventRecord = SignificantEventTestDataFactory.createSignificantEvent(
      eventOptions
    );
    eventRecord.Name = 'Updated Repository Event';
    eventRecord = repository.updateSignificantEvent(eventRecord);

    Significant_Event_Contact__c participant = SignificantEventTestDataFactory.createParticipant(
      new SignificantEventTestDataFactory.ParticipantOptions()
        .forEvent(eventRecord.Id)
        .forAccount(scenario.treeScenario.secondPersonAccount.Id)
    );
    participant.Financial_Advisor_Team__c = null;
    repository.updateParticipants(new List<Significant_Event_Contact__c>{ participant });

    Test.startTest();
    repository.deleteParticipants(new List<Significant_Event_Contact__c>{ participant });
    repository.deleteSignificantEvent(eventRecord);
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM Significant_Event__c WHERE Id = :eventRecord.Id]
    );
  }
}