/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class SignificantEventActionServiceTest {
  @TestSetup
  static void setup() {
    SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions()
        .withFinancialAdvisorTeam()
        .withSignificantEvent()
        .withParticipant()
    );
  }

  private static SignificantEventActionService newService() {
    return new SignificantEventActionService(new SignificantEventActionRepository());
  }

  @IsTest
  static void getCreateContext_nullAccountId_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getCreateContext(null);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getCreateContext_missingAccount_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getCreateContext(SignificantEventTestDataFactory.generateFakeId(Account.SObjectType));
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getEditContext_missingEvent_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getEditContext(
        SignificantEventTestDataFactory.generateFakeId(Significant_Event__c.SObjectType)
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getActionContext_unsupportedRecord_throwsHandledException() {
    SignificantEventActionService service = newService();
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    Boolean threw = false;

    Test.startTest();
    try {
      service.getActionContext(currentUser.Id);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getLinkedContactsForAccount_missingAccount_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getLinkedContactsForAccount(
        SignificantEventTestDataFactory.generateFakeId(Account.SObjectType)
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getSignificantEventsForAccount_missingAccount_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getSignificantEventsForAccount(
        SignificantEventTestDataFactory.generateFakeId(Account.SObjectType)
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void createSignificantEvent_requiresLinkedContacts() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>()
    );
    Boolean threw = false;

    Test.startTest();
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void createSignificantEvent_requiresEventName() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.eventName = '   ';
    Boolean threw = false;

    Test.startTest();
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getEditContext_returnsSelectedAccounts() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];

    Test.startTest();
    SignificantEventActionModels.CreateContext context = service.getEditContext(
      seededEvent.Id
    );
    Test.stopTest();

    System.assertEquals(true, context.isEditMode);
    System.assertEquals(1, context.eventData.selectedAccounts.size());
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      context.eventData.selectedAccounts[0].accountId
    );
  }

  @IsTest
  static void getSignificantEventsForAccount_returnsDirectParticipantEvents() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();

    Test.startTest();
    List<SignificantEventActionModels.SignificantEventRow> rows = service.getSignificantEventsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      SignificantEventTestDataFactory.DEFAULT_EVENT_NAME,
      rows[0].eventName
    );
  }

  @IsTest
  static void getLinkedContactsForAccount_returnsParticipantRows() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = service.getLinkedContactsForAccount(
      scenario.household.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      rows[0].accountId
    );
  }

  @IsTest
  static void getLinkedContactsForSignificantEvent_returnsParticipantRows() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Account household = SignificantEventTestDataFactory.createHouseholdAccount(
      'SE Service Event Participants Household'
    );
    SignificantEventActionService service = newService();

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = SignificantEventTestDataFactory.DEFAULT_EVENT_NAME,
      Event_Type__c = SignificantEventTestDataFactory.DEFAULT_EVENT_TYPE,
      Start_Date__c = Date.today(),
      Household__c = household.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = service.getLinkedContactsForSignificantEvent(
      eventRecord.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      SignificantEventTestDataFactory.DEFAULT_EVENT_NAME,
      rows[0].eventName
    );
  }

  @IsTest
  static void getLinkedContactsForSignificantEvent_missingEvent_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getLinkedContactsForSignificantEvent(
        SignificantEventTestDataFactory.generateFakeId(Significant_Event__c.SObjectType)
      );
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void testVisibleConstructor_usesInjectedDependencies() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = new SignificantEventActionService(
      new SignificantEventActionRepository(),
      new FscRelRelationshipTreeService()
    );

    Test.startTest();
    SignificantEventActionModels.CreateContext context = service.getCreateContext(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, context.contextAccountId);
  }

  @IsTest
  static void getActionContext_nullRecordId_throwsHandledException() {
    SignificantEventActionService service = newService();
    Boolean threw = false;

    Test.startTest();
    try {
      service.getActionContext(null);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getActionContext_routesAccountAndEventContexts() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];

    Test.startTest();
    SignificantEventActionModels.CreateContext createContext = service.getActionContext(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    SignificantEventActionModels.CreateContext editContext = service.getActionContext(
      seededEvent.Id
    );
    Test.stopTest();

    System.assertEquals(false, createContext.isEditMode);
    System.assertEquals(true, editContext.isEditMode);
  }

  @IsTest
  static void getCreateContext_returnsResolvedHouseholdContext() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();

    Test.startTest();
    SignificantEventActionModels.CreateContext context = service.getCreateContext(
      scenario.household.Id
    );
    Test.stopTest();

    System.assertEquals(false, context.isEditMode);
    System.assertEquals(String.valueOf(scenario.household.Id), context.contextAccountId);
    System.assertEquals(String.valueOf(scenario.household.Id), context.householdId);
  }

  @IsTest
  static void getSuggestedLinkedContacts_returnsGroupedSuggestions() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();

    Test.startTest();
    List<SignificantEventActionModels.SuggestedContactGroup> groups = service.getSuggestedLinkedContacts(
      scenario.household.Id,
      scenario.treeScenario.linkedPersonAccount.Id,
      new List<String>(),
      false
    );
    Test.stopTest();

    System.assertNotEquals(null, groups);
  }

  @IsTest
  static void searchNonHouseholdAccounts_returnsLinkedAccountOptions() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();

    Test.startTest();
    List<SignificantEventActionModels.LinkedAccountOption> options = service.searchNonHouseholdAccounts(
      scenario.treeScenario.linkedPersonAccount.Name.left(4)
    );
    Test.stopTest();

    System.assert(options.size() > 0, 'Expected account search options.');
  }

  @IsTest
  static void createSignificantEvent_persistsEventAndParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.eventType = 'Birthday';
    request.otherEventType = null;

    Test.startTest();
    SignificantEventActionModels.SaveResult result = service.createSignificantEvent(request);
    Test.stopTest();

    System.assertEquals(true, result.success);

    Significant_Event__c createdEvent = [
      SELECT Id, Name, Household__c
      FROM Significant_Event__c
      WHERE Id = :result.significantEventId
      LIMIT 1
    ];
    System.assertEquals('Graduation Party', createdEvent.Name);
    System.assertEquals(scenario.household.Id, createdEvent.Household__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Significant_Event_Contact__c
        WHERE Significant_Event__c = :createdEvent.Id
      ]
    );
  }

  @IsTest
  static void createSignificantEvent_validatesRequiredFields() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.eventType = '';
    Boolean threwEventType = false;

    Test.startTest();
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threwEventType = true;
    }

    request.eventType = SignificantEventTestDataFactory.OTHER_EVENT_TYPE;
    request.otherEventType = null;
    Boolean threwOtherType = false;
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threwOtherType = true;
    }

    request.otherEventType = SignificantEventTestDataFactory.DEFAULT_OTHER_EVENT_TYPE;
    request.startDate = '';
    Boolean threwStartDate = false;
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threwStartDate = true;
    }

    request.startDate = String.valueOf(Date.today());
    request.endDate = String.valueOf(Date.today().addDays(-2));
    request.eventType = 'Birthday';
    request.otherEventType = null;
    Boolean threwEndDate = false;
    try {
      service.createSignificantEvent(request);
    } catch (AuraHandledException error) {
      threwEndDate = true;
    }
    Test.stopTest();

    System.assertEquals(true, threwEventType);
    System.assertEquals(true, threwOtherType);
    System.assertEquals(true, threwStartDate);
    System.assertEquals(true, threwEndDate);
  }

  @IsTest
  static void updateSignificantEvent_updatesFieldsAndParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.secondPersonAccount.Id)
      }
    );
    request.significantEventId = String.valueOf(seededEvent.Id);
    request.eventType = 'Marriage';
    request.otherEventType = null;
    request.householdId = String.valueOf(scenario.household.Id);

    Test.startTest();
    SignificantEventActionModels.SaveResult result = service.updateSignificantEvent(
      request
    );
    Test.stopTest();

    System.assertEquals(true, result.success);

    Significant_Event__c updatedEvent = [
      SELECT Name, Event_Type__c
      FROM Significant_Event__c
      WHERE Id = :seededEvent.Id
      LIMIT 1
    ];
    System.assertEquals('Graduation Party', updatedEvent.Name);
    System.assertEquals('Marriage', updatedEvent.Event_Type__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Significant_Event_Contact__c
        WHERE
          Significant_Event__c = :seededEvent.Id
          AND Account__c = :scenario.treeScenario.secondPersonAccount.Id
      ]
    );
  }

  @IsTest
  static void updateSignificantEvent_syncsParticipantFinancialAdvisorTeam() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    Significant_Event__c seededEvent = [
      SELECT Id, Financial_Advisor_Team__c
      FROM Significant_Event__c
      LIMIT 1
    ];
    Significant_Event_Contact__c participant = [
      SELECT Id, Account__c, Financial_Advisor_Team__c
      FROM Significant_Event_Contact__c
      WHERE Significant_Event__c = :seededEvent.Id
      LIMIT 1
    ];
    participant.Financial_Advisor_Team__c = null;
    update participant;

    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{ String.valueOf(participant.Account__c) }
    );
    request.significantEventId = String.valueOf(seededEvent.Id);
    request.eventType = 'Birthday';
    request.otherEventType = null;

    Test.startTest();
    service.updateSignificantEvent(request);
    Test.stopTest();

    Significant_Event_Contact__c updatedParticipant = [
      SELECT Financial_Advisor_Team__c
      FROM Significant_Event_Contact__c
      WHERE Id = :participant.Id
      LIMIT 1
    ];
    System.assertEquals(
      seededEvent.Financial_Advisor_Team__c,
      updatedParticipant.Financial_Advisor_Team__c
    );
  }

  @IsTest
  static void updateSignificantEvent_deletesEventWhenContactsRemoved() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionService service = newService();
    Significant_Event__c seededEvent = [
      SELECT Id
      FROM Significant_Event__c
      LIMIT 1
    ];
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>()
    );
    request.significantEventId = String.valueOf(seededEvent.Id);

    Test.startTest();
    SignificantEventActionModels.SaveResult result = service.updateSignificantEvent(
      request
    );
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assertEquals('Significant Event deleted.', result.message);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Significant_Event__c WHERE Id = :seededEvent.Id]
    );
  }

  @IsTest
  static void updateSignificantEvent_nullRequestAndMissingEvent_throwHandledExceptions() {
    SignificantEventActionService service = newService();
    Boolean threwNullRequest = false;
    Boolean threwMissingEvent = false;

    Test.startTest();
    try {
      service.updateSignificantEvent(null);
    } catch (AuraHandledException error) {
      threwNullRequest = true;
    }

    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadSeededScenario();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.significantEventId = String.valueOf(
      SignificantEventTestDataFactory.generateFakeId(Significant_Event__c.SObjectType)
    );
    request.eventType = 'Birthday';
    request.otherEventType = null;
    try {
      service.updateSignificantEvent(request);
    } catch (AuraHandledException error) {
      threwMissingEvent = true;
    }
    Test.stopTest();

    System.assertEquals(true, threwNullRequest);
    System.assertEquals(true, threwMissingEvent);
  }
}