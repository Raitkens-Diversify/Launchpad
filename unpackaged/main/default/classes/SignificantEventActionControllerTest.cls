/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class SignificantEventActionControllerTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void getCreateContext_householdLaunch_hasNoDefaultSelection() {
    Boolean hasHouseholdRecordType = FscRelAccountRepository.selectHouseholdRecordTypeId() != null;
    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Household');
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    FscDataTestDataFactory.createMembership(
      household,
      scenario.treeScenario.linkedPersonAccount,
      true,
      true,
      FscDataTestDataFactory.resolveDefaultRoleValue()
    );

    Test.startTest();
    SignificantEventActionModels.CreateContext context = SignificantEventActionController.getCreateContext(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(false, context.isEditMode);
    System.assertEquals(hasHouseholdRecordType, context.isHouseholdLaunch);
    System.assertEquals(0, context.defaultSelectedAccounts.size());
    System.assertEquals(String.valueOf(household.Id), context.householdId);
  }

  @IsTest
  static void getCreateContext_nonHouseholdLaunch_doesNotPreselectSourceAccount() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();

    Test.startTest();
    SignificantEventActionModels.CreateContext context = SignificantEventActionController.getCreateContext(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(false, context.isHouseholdLaunch);
    System.assertEquals(0, context.defaultSelectedAccounts.size());
  }

  private static void linkHouseholdMembersForSuggestions(
    Account household,
    SignificantEventTestDataFactory.Scenario scenario
  ) {
    String clientType = FscRelClientAccountUtils.resolveAssignableClientAccountType();
    if (String.isBlank(clientType)) {
      return;
    }

    FscDataTestDataFactory.createMembership(
      household,
      scenario.treeScenario.linkedPersonAccount,
      true,
      true,
      FscDataTestDataFactory.resolveDefaultRoleValue()
    );
    FscDataTestDataFactory.createMembership(
      household,
      scenario.treeScenario.secondPersonAccount,
      false,
      false,
      FscDataTestDataFactory.resolveDefaultRoleValue()
    );

    update new List<Account>{
      new Account(
        Id = scenario.treeScenario.linkedPersonAccount.Id,
        Household__c = household.Id,
        Type = clientType
      ),
      new Account(
        Id = scenario.treeScenario.secondPersonAccount.Id,
        Household__c = household.Id,
        Type = clientType
      )
    };
  }

  @IsTest
  static void getSuggestedLinkedContacts_returnsClientsFamilyAndNetwork() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    String clientType = FscRelClientAccountUtils.resolveAssignableClientAccountType();
    if (String.isBlank(clientType)) {
      return;
    }

    Account household = SignificantEventTestDataFactory.createHouseholdAccount(
      'SE Suggestions Household'
    );
    linkHouseholdMembersForSuggestions(household, scenario);

    Test.startTest();
    List<SignificantEventActionModels.SuggestedContactGroup> groups = SignificantEventActionController.getSuggestedLinkedContacts(
      household.Id,
      null,
      new List<String>(),
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
  static void getSuggestedLinkedContacts_includesAarFromHouseholdMembers() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }
    if (String.isBlank(FscRelClientAccountUtils.resolveAssignableClientAccountType())) {
      return;
    }

    Account household = SignificantEventTestDataFactory.createHouseholdAccount(
      'SE Suggestions AAR Household'
    );
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Family Role',
      'Family Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.treeScenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    linkHouseholdMembersForSuggestions(household, scenario);

    Test.startTest();
    List<SignificantEventActionModels.SuggestedContactGroup> groups = SignificantEventActionController.getSuggestedLinkedContacts(
      household.Id,
      null,
      new List<String>(),
      true
    );
    Test.stopTest();

    Set<String> suggestedAccountIds = new Set<String>();
    for (
      SignificantEventActionModels.SuggestedContactGroup suggestionGroup : groups
    ) {
      for (
        SignificantEventActionModels.LinkedAccountOption contact : suggestionGroup.contacts
      ) {
        suggestedAccountIds.add(contact.accountId);
      }
    }

    System.assert(
      suggestedAccountIds.contains(String.valueOf(scenario.treeScenario.secondPersonAccount.Id)),
      'Expected member AAR related account in suggestions.'
    );
  }

  @IsTest
  static void searchNonHouseholdAccounts_excludesHouseholdRecordType() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Search Household');

    Test.startTest();
    List<SignificantEventActionModels.LinkedAccountOption> results = SignificantEventActionController.searchNonHouseholdAccounts(
      scenario.treeScenario.linkedPersonAccount.Name.left(4)
    );
    Test.stopTest();

    System.assert(results.size() > 0, 'Expected search results.');

    Set<Id> resultIds = new Set<Id>();
    for (SignificantEventActionModels.LinkedAccountOption result : results) {
      resultIds.add(Id.valueOf(result.accountId));
    }

    System.assert(!resultIds.contains(household.Id));

    for (Account account : [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :resultIds
    ]) {
      System.assertEquals(
        false,
        FscRelAccountRepository.isHouseholdRecordTypeDeveloperName(
          account.RecordType.DeveloperName
        )
      );
    }
  }

  @IsTest
  static void getActionContext_routesSignificantEventToEditContext() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Routed Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    Test.startTest();
    SignificantEventActionModels.CreateContext context = SignificantEventActionController.getActionContext(
      eventRecord.Id
    );
    Test.stopTest();

    System.assertEquals(true, context.isEditMode);
    System.assertEquals('Routed Event', context.eventData.eventName);
  }

  @IsTest
  static void getActionContext_routesAccountToCreateContext() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();

    Test.startTest();
    SignificantEventActionModels.CreateContext context = SignificantEventActionController.getActionContext(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(false, context.isEditMode);
    System.assertEquals(0, context.defaultSelectedAccounts.size());
  }

  @IsTest
  static void getActionContext_rejectsUnsupportedRecord() {
    User currentUser = [
      SELECT Id
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.getActionContext(currentUser.Id);
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getEditContext_returnsExistingEventData() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Existing Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    SignificantEventActionModels.CreateContext context = SignificantEventActionController.getEditContext(
      eventRecord.Id
    );
    Test.stopTest();

    System.assertEquals(true, context.isEditMode);
    System.assertEquals(
      String.valueOf(scenario.treeScenario.rootAccount.Id),
      context.contextAccountId
    );
    System.assertEquals('Existing Event', context.eventData.eventName);
    System.assertEquals(1, context.eventData.selectedAccounts.size());
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      context.eventData.selectedAccounts[0].accountId
    );
  }

  @IsTest
  static void createSignificantEvent_stampsFatOnParentAndParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'SE FAT');
    insert fat;

    scenario.treeScenario.rootAccount.Financial_Advisor_Team__c = fat.Id;
    update scenario.treeScenario.rootAccount;

    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.treeScenario.rootAccount.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );

    Test.startTest();
    SignificantEventActionModels.SaveResult result = SignificantEventActionController.createSignificantEvent(
      JSON.serialize(request)
    );
    Test.stopTest();

    System.assertEquals(true, result.success);

    Significant_Event__c createdEvent = [
      SELECT Id, Financial_Advisor_Team__c, Household__c, Other_Event_Type__c
      FROM Significant_Event__c
      WHERE Id = :result.significantEventId
      LIMIT 1
    ];
    System.assertEquals(fat.Id, createdEvent.Financial_Advisor_Team__c);
    System.assertEquals(scenario.treeScenario.rootAccount.Id, createdEvent.Household__c);
    System.assertEquals('Custom milestone', createdEvent.Other_Event_Type__c);

    Significant_Event_Contact__c participant = [
      SELECT Financial_Advisor_Team__c, Account__c
      FROM Significant_Event_Contact__c
      WHERE Significant_Event__c = :createdEvent.Id
      LIMIT 1
    ];
    System.assertEquals(fat.Id, participant.Financial_Advisor_Team__c);
    System.assertEquals(
      scenario.treeScenario.linkedPersonAccount.Id,
      participant.Account__c
    );
  }

  @IsTest
  static void updateSignificantEvent_syncsParticipantsAndFat() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'SE FAT Update');
    insert fat;

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Existing Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id,
      Financial_Advisor_Team__c = fat.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Financial_Advisor_Team__c = fat.Id
    );

    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.treeScenario.rootAccount.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.secondPersonAccount.Id)
      }
    );
    request.significantEventId = String.valueOf(eventRecord.Id);
    request.eventType = 'Marriage';
    request.otherEventType = null;

    Test.startTest();
    SignificantEventActionModels.SaveResult result = SignificantEventActionController.updateSignificantEvent(
      JSON.serialize(request)
    );
    Test.stopTest();

    System.assertEquals(true, result.success);

    List<Significant_Event_Contact__c> participants = [
      SELECT Account__c, Financial_Advisor_Team__c
      FROM Significant_Event_Contact__c
      WHERE Significant_Event__c = :eventRecord.Id
    ];
    System.assertEquals(1, participants.size());
    System.assertEquals(
      scenario.treeScenario.secondPersonAccount.Id,
      participants[0].Account__c
    );
    System.assertEquals(fat.Id, participants[0].Financial_Advisor_Team__c);
  }

  @IsTest
  static void updateSignificantEvent_deletesEventWhenAllContactsRemoved() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Event To Delete',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.treeScenario.rootAccount.Id,
      new List<String>()
    );
    request.significantEventId = String.valueOf(eventRecord.Id);

    Test.startTest();
    SignificantEventActionModels.SaveResult result = SignificantEventActionController.updateSignificantEvent(
      JSON.serialize(request)
    );
    Test.stopTest();

    System.assertEquals(true, result.success);
    System.assertEquals('Significant Event deleted.', result.message);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Significant_Event__c
        WHERE Id = :eventRecord.Id
      ]
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Significant_Event_Contact__c
        WHERE Significant_Event__c = :eventRecord.Id
      ]
    );
  }

  @IsTest
  static void createSignificantEvent_requiresOtherEventType() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.treeScenario.rootAccount.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.otherEventType = null;

    Boolean threw = false;
    String errorMessage = '';

    Test.startTest();
    try {
      SignificantEventActionController.createSignificantEvent(
        JSON.serialize(request)
      );
    } catch (Exception error) {
      threw = true;
      errorMessage = error.getMessage();
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected validation failure.');
  }

  @IsTest
  static void createSignificantEvent_rejectsEndDateBeforeStartDate() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.rootAccount.Id,
      scenario.treeScenario.rootAccount.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );
    request.startDate = String.valueOf(Date.today());
    request.endDate = String.valueOf(Date.today().addDays(-1));
    request.eventType = 'Birthday';
    request.otherEventType = null;

    Boolean threw = false;
    String errorMessage = '';

    Test.startTest();
    try {
      SignificantEventActionController.createSignificantEvent(
        JSON.serialize(request)
      );
    } catch (Exception error) {
      threw = true;
      errorMessage = error.getMessage();
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected validation failure.');
  }

  @IsTest
  static void createSignificantEvent_rejectsBlankRequest() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.createSignificantEvent('');
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getLinkedContactsForAccount_householdLaunch_returnsMemberParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Linked Contacts Household');
    scenario.treeScenario.linkedPersonAccount.Household__c = household.Id;
    scenario.treeScenario.secondPersonAccount.Household__c = household.Id;
    update new List<Account>{
      scenario.treeScenario.linkedPersonAccount,
      scenario.treeScenario.secondPersonAccount
    };

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Household Linked Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = household.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      rows[0].accountId
    );
    System.assertEquals('Household Linked Event', rows[0].eventName);
    System.assertEquals('Birthday', rows[0].eventType);
  }

  @IsTest
  static void getLinkedContactsForAccount_householdLaunch_includesAarParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Linked Contacts AAR Household');
    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Family Role',
      'Family Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.treeScenario.relatedBusinessAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );
    scenario.treeScenario.linkedPersonAccount.Household__c = household.Id;
    scenario.treeScenario.secondPersonAccount.Household__c = household.Id;
    update new List<Account>{
      scenario.treeScenario.linkedPersonAccount,
      scenario.treeScenario.secondPersonAccount
    };

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'AAR Linked Event',
      Event_Type__c = 'Marriage',
      Start_Date__c = Date.today(),
      Household__c = household.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.relatedBusinessAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      household.Id
    );
    Test.stopTest();

    Set<String> accountIds = new Set<String>();
    for (SignificantEventActionModels.LinkedContactRow row : rows) {
      accountIds.add(row.accountId);
    }

    System.assert(
      accountIds.contains(String.valueOf(scenario.treeScenario.relatedBusinessAccount.Id)),
      'Expected AAR related account participant.'
    );
  }

  @IsTest
  static void getLinkedContactsForAccount_nonHouseholdLaunch_usesAarOnly() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Family Role',
      'Family Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.treeScenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Non-Household AAR Event',
      Event_Type__c = 'Retirement',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.secondPersonAccount.Id
    );
    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(2, rows.size());

    Set<String> accountIds = new Set<String>();
    for (SignificantEventActionModels.LinkedContactRow row : rows) {
      accountIds.add(row.accountId);
    }

    System.assert(
      accountIds.contains(String.valueOf(scenario.treeScenario.secondPersonAccount.Id)),
      'Expected AAR related account participant.'
    );
    System.assert(
      accountIds.contains(String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)),
      'Expected direct account participant.'
    );
  }

  @IsTest
  static void getLinkedContactsForAccount_includesDirectAccountParticipants() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Direct Account Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      rows[0].accountId
    );
    System.assertEquals('Direct Account Event', rows[0].eventName);
  }

  @IsTest
  static void getLinkedContactsForAccount_includesDirectHouseholdEventParticipants() {
    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Direct Household Event');

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Household Direct Event',
      Event_Type__c = 'Marriage',
      Start_Date__c = Date.today(),
      Household__c = household.Id
    );
    insert eventRecord;

    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals('Household Direct Event', rows[0].eventName);
    System.assertEquals(
      String.valueOf(scenario.treeScenario.linkedPersonAccount.Id),
      rows[0].accountId
    );
  }

  @IsTest
  static void getLinkedContactsForAccount_emptyScope_returnsEmptyList() {
    Account standaloneAccount = new Account(Name = 'Standalone Account');
    insert standaloneAccount;

    Test.startTest();
    List<SignificantEventActionModels.LinkedContactRow> rows = SignificantEventActionController.getLinkedContactsForAccount(
      standaloneAccount.Id
    );
    Test.stopTest();

    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void getLinkedContactsForAccount_nullId_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.getLinkedContactsForAccount(null);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getSignificantEventsForAccount_multipleContacts_returnsOneRowPerEvent() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Family Role',
      'Family Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.treeScenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Deduped Event',
      Event_Type__c = 'Other',
      Other_Event_Type__c = 'Custom milestone',
      Start_Date__c = Date.today(),
      End_Date_Optional__c = Date.today().addDays(1),
      Approximate_Date__c = true,
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert eventRecord;

    insert new List<Significant_Event_Contact__c>{
      new Significant_Event_Contact__c(
        Significant_Event__c = eventRecord.Id,
        Account__c = scenario.treeScenario.linkedPersonAccount.Id
      ),
      new Significant_Event_Contact__c(
        Significant_Event__c = eventRecord.Id,
        Account__c = scenario.treeScenario.secondPersonAccount.Id
      )
    };

    Test.startTest();
    List<SignificantEventActionModels.SignificantEventRow> rows = SignificantEventActionController.getSignificantEventsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals(
      String.valueOf(eventRecord.Id),
      rows[0].significantEventId
    );
    System.assertEquals('Deduped Event', rows[0].eventName);
    System.assertEquals('Other', rows[0].eventType);
    System.assertEquals('Custom milestone', rows[0].otherEventType);
    System.assertEquals(String.valueOf(Date.today()), rows[0].startDate);
    System.assertEquals(
      String.valueOf(Date.today().addDays(1)),
      rows[0].endDate
    );
    System.assertEquals(true, rows[0].approximateDate);
  }

  @IsTest
  static void getSignificantEventsForAccount_householdLaunch_returnsDirectParticipantEvents() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Account household = SignificantEventTestDataFactory.createHouseholdAccount('SE Events Household');
    scenario.treeScenario.linkedPersonAccount.Household__c = household.Id;
    scenario.treeScenario.secondPersonAccount.Household__c = household.Id;
    update new List<Account>{
      scenario.treeScenario.linkedPersonAccount,
      scenario.treeScenario.secondPersonAccount
    };

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Household Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = household.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = scenario.treeScenario.linkedPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.SignificantEventRow> rows = SignificantEventActionController.getSignificantEventsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(1, rows.size());
    System.assertEquals('Household Event', rows[0].eventName);
  }

  @IsTest
  static void getSignificantEventsForAccount_personAccount_excludesAarRelatedEvents() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    List<FscRelHouseholdModels.RecordTypeOption> recordTypes = FscRelRecordTypeUtils.selectActiveAccountRelationRecordTypes();
    if (recordTypes.isEmpty()) {
      return;
    }

    Id recordTypeId = FscRelRecordTypeUtils.selectAccountRelationRecordTypeId(
      recordTypes[0].developerName
    );
    Reciprocal_Role__c role = FscDataTestDataFactory.createReciprocalRoleForMemberRelationship(
      recordTypes[0].developerName,
      'Family Role',
      'Family Role'
    );
    insert new Account_Account_Relationship__c(
      Account__c = scenario.treeScenario.linkedPersonAccount.Id,
      Related_Account__c = scenario.treeScenario.secondPersonAccount.Id,
      RecordTypeId = recordTypeId,
      Reciprocal_Role__c = role.Id,
      Inverse_Reciprocal_Role__c = role.Id,
      Active__c = true
    );

    Significant_Event__c relatedPersonEvent = new Significant_Event__c(
      Name = 'Related Person Only Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Household__c = scenario.treeScenario.rootAccount.Id
    );
    insert relatedPersonEvent;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = relatedPersonEvent.Id,
      Account__c = scenario.treeScenario.secondPersonAccount.Id
    );

    Test.startTest();
    List<SignificantEventActionModels.SignificantEventRow> rows = SignificantEventActionController.getSignificantEventsForAccount(
      scenario.treeScenario.linkedPersonAccount.Id
    );
    Test.stopTest();

    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void getSignificantEventsForAccount_emptyScope_returnsEmptyList() {
    Account standaloneAccount = new Account(Name = 'Standalone Events Account');
    insert standaloneAccount;

    Test.startTest();
    List<SignificantEventActionModels.SignificantEventRow> rows = SignificantEventActionController.getSignificantEventsForAccount(
      standaloneAccount.Id
    );
    Test.stopTest();

    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void getSignificantEventsForAccount_nullId_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.getSignificantEventsForAccount(null);
    } catch (AuraHandledException error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getCreateContext_missingAccount_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.getCreateContext(
        SignificantEventTestDataFactory.generateFakeId(Account.SObjectType)
      );
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getEditContext_missingEvent_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.getEditContext(
        SignificantEventTestDataFactory.generateFakeId(Significant_Event__c.SObjectType)
      );
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void getSuggestedLinkedContacts_returnsGroupedResults() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.loadScenario();
    Account household = SignificantEventTestDataFactory.createHouseholdAccount(
      'SE Controller Suggestions Household'
    );

    Test.startTest();
    List<SignificantEventActionModels.SuggestedContactGroup> groups = SignificantEventActionController.getSuggestedLinkedContacts(
      household.Id,
      scenario.treeScenario.linkedPersonAccount.Id,
      new List<String>(),
      false
    );
    Test.stopTest();

    System.assertNotEquals(null, groups);
  }

  @IsTest
  static void createSignificantEvent_invalidJson_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.createSignificantEvent('{invalid-json');
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }

  @IsTest
  static void updateSignificantEvent_invalidJson_throwsHandledException() {
    Boolean threw = false;

    Test.startTest();
    try {
      SignificantEventActionController.updateSignificantEvent('{invalid-json');
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw);
  }
}