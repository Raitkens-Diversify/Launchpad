/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 *
 * Shared test data for Significant Event Apex tests.
 */
@IsTest
public class SignificantEventTestDataFactory {
  public static final String DEFAULT_EVENT_NAME = 'Significant Event Test';
  public static final String DEFAULT_OTHER_EVENT_TYPE = 'Custom milestone';
  public static final String DEFAULT_EVENT_TYPE = 'Birthday';
  public static final String OTHER_EVENT_TYPE = 'Other';

  private static Integer scenarioSequence = 0;

  public class ScenarioOptions {
    public Boolean includeFinancialAdvisorTeam = false;
    public Boolean includeSignificantEvent = false;
    public Boolean includeParticipant = false;
    public Boolean useUniqueNames = false;

    public ScenarioOptions withFinancialAdvisorTeam() {
      this.includeFinancialAdvisorTeam = true;
      return this;
    }

    public ScenarioOptions withSignificantEvent() {
      this.includeSignificantEvent = true;
      return this;
    }

    public ScenarioOptions withParticipant() {
      this.includeParticipant = true;
      return this;
    }

    public ScenarioOptions withUniqueNames() {
      this.useUniqueNames = true;
      return this;
    }
  }

  public class SignificantEventOptions {
    public Id householdId;
    public String name = DEFAULT_EVENT_NAME;
    public String eventType = DEFAULT_EVENT_TYPE;
    public String otherEventType;
    public Date startDate = Date.today();
    public Date endDate;
    public Boolean approximateDate = false;
    public String description;
    public Id financialAdvisorTeamId;
    public Id personId;
    public Boolean doInsert = true;
  }

  public class ParticipantOptions {
    public Id significantEventId;
    public Id accountId;
    public Id financialAdvisorTeamId;
    public Boolean doInsert = true;

    public ParticipantOptions forEvent(Id eventId) {
      this.significantEventId = eventId;
      return this;
    }

    public ParticipantOptions forAccount(Id linkedAccountId) {
      this.accountId = linkedAccountId;
      return this;
    }

    public ParticipantOptions withFinancialAdvisorTeam(Id teamId) {
      this.financialAdvisorTeamId = teamId;
      return this;
    }
  }

  public class Scenario {
    public FscDataTestDataFactory.TreeScenario treeScenario;
    public Account household;
    public Financial_Advisor_Team__c financialAdvisorTeam;
    public Group publicGroup;
    public Significant_Event__c significantEvent;
    public List<Significant_Event_Contact__c> participants = new List<Significant_Event_Contact__c>();

    public Scenario reloadTreeScenario() {
      this.treeScenario = FscDataTestDataFactory.loadTreeScenario(
        this.treeScenario.rootAccount.Id
      );
      return this;
    }
  }

  public static Scenario createScenario() {
    return createScenario(new ScenarioOptions());
  }

  public static Scenario createScenario(ScenarioOptions options) {
    ScenarioOptions resolvedOptions = options == null
      ? new ScenarioOptions()
      : options;
    Scenario scenario = new Scenario();
    String scenarioKey = resolvedOptions.useUniqueNames
      ? nextScenarioKey()
      : null;

    scenario.treeScenario = FscDataTestDataFactory.createTreeScenario(
      resolvedOptions.useUniqueNames
        ? new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
        : new FscDataTestDataFactory.TreeScenarioOptions()
    );
    scenario.household = createHouseholdAccount(
      buildScenarioName('Significant Event Household', scenarioKey)
    );

    if (resolvedOptions.includeFinancialAdvisorTeam) {
      scenario.financialAdvisorTeam = createFinancialAdvisorTeamWithPublicGroup(
        buildScenarioName('Significant Event FAT', scenarioKey)
      );
      scenario.publicGroup = [
        SELECT Id
        FROM Group
        WHERE Id = :scenario.financialAdvisorTeam.Public_Group_Id__c
        LIMIT 1
      ];
    }

    if (resolvedOptions.includeSignificantEvent) {
      SignificantEventOptions eventOptions = new SignificantEventOptions();
      eventOptions.householdId = scenario.household.Id;
      eventOptions.financialAdvisorTeamId = scenario.financialAdvisorTeam == null
        ? null
        : scenario.financialAdvisorTeam.Id;
      scenario.significantEvent = createSignificantEvent(eventOptions);
    }

    if (
      resolvedOptions.includeParticipant &&
      scenario.significantEvent != null
    ) {
      scenario.participants.add(
        createParticipant(
          new ParticipantOptions()
            .forEvent(scenario.significantEvent.Id)
            .forAccount(scenario.treeScenario.linkedPersonAccount.Id)
            .withFinancialAdvisorTeam(
              scenario.financialAdvisorTeam == null
                ? null
                : scenario.financialAdvisorTeam.Id
            )
        )
      );
    }

    return scenario;
  }

  public static Scenario loadScenario() {
    Scenario scenario = new Scenario();
    scenario.treeScenario = FscDataTestDataFactory.loadTreeScenario();
    return scenario;
  }

  public static Scenario loadSeededScenario() {
    Scenario scenario = loadScenario();

    List<Account> households = [
      SELECT Id, Name
      FROM Account
      WHERE Name LIKE 'Significant Event Household%'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!households.isEmpty()) {
      scenario.household = households[0];
    }

    List<Financial_Advisor_Team__c> teams = [
      SELECT Id, Public_Group_Id__c, Name
      FROM Financial_Advisor_Team__c
      WHERE Name LIKE 'Significant Event FAT%'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!teams.isEmpty()) {
      scenario.financialAdvisorTeam = teams[0];
    }

    List<Significant_Event__c> events = [
      SELECT Id, Name, Household__c, Financial_Advisor_Team__c
      FROM Significant_Event__c
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!events.isEmpty()) {
      scenario.significantEvent = events[0];
    }

    scenario.participants = [
      SELECT Id, Account__c, Significant_Event__c, Financial_Advisor_Team__c
      FROM Significant_Event_Contact__c
      ORDER BY CreatedDate DESC
    ];

    return scenario;
  }

  public static Account createHouseholdAccount(String name) {
    return FscDataTestDataFactory.createHouseholdAccount(name);
  }

  public static Financial_Advisor_Team__c createFinancialAdvisorTeamWithPublicGroup(
    String name
  ) {
    String uniqueSuffix = nextScenarioKey();
    Group publicGroup = new Group(
      Name = truncateName('SE Grp ' + uniqueSuffix, 40),
      Type = 'Regular'
    );
    insert publicGroup;

    Financial_Advisor_Team__c financialAdvisorTeam = new Financial_Advisor_Team__c(
      Name = truncateName(name, 80),
      Public_Group_Id__c = publicGroup.Id
    );
    insert financialAdvisorTeam;
    return financialAdvisorTeam;
  }

  public static Significant_Event__c createSignificantEvent(
    SignificantEventOptions options
  ) {
    SignificantEventOptions resolvedOptions = options == null
      ? new SignificantEventOptions()
      : options;

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = resolvedOptions.name,
      Event_Type__c = resolvedOptions.eventType,
      Other_Event_Type__c = resolvedOptions.otherEventType,
      Start_Date__c = resolvedOptions.startDate,
      End_Date_Optional__c = resolvedOptions.endDate,
      Approximate_Date__c = resolvedOptions.approximateDate == true,
      Description__c = resolvedOptions.description,
      Household__c = resolvedOptions.householdId,
      Financial_Advisor_Team__c = resolvedOptions.financialAdvisorTeamId,
      Person__c = resolvedOptions.personId
    );

    if (resolvedOptions.doInsert) {
      insert eventRecord;
    }

    return eventRecord;
  }

  public static Significant_Event_Contact__c createParticipant(
    ParticipantOptions options
  ) {
    ParticipantOptions resolvedOptions = options == null
      ? new ParticipantOptions()
      : options;

    Significant_Event_Contact__c participant = new Significant_Event_Contact__c(
      Significant_Event__c = resolvedOptions.significantEventId,
      Account__c = resolvedOptions.accountId,
      Financial_Advisor_Team__c = resolvedOptions.financialAdvisorTeamId
    );

    if (resolvedOptions.doInsert) {
      insert participant;
    }

    return participant;
  }

  public static SignificantEventActionModels.SaveRequest buildSaveRequest(
    Id contextAccountId,
    Id householdId,
    List<String> linkedAccountIds
  ) {
    SignificantEventActionModels.SaveRequest request = new SignificantEventActionModels.SaveRequest();
    request.contextAccountId = String.valueOf(contextAccountId);
    request.householdId = String.valueOf(householdId);
    request.eventName = 'Graduation Party';
    request.eventType = OTHER_EVENT_TYPE;
    request.otherEventType = DEFAULT_OTHER_EVENT_TYPE;
    request.startDate = String.valueOf(Date.today());
    request.approximateDate = true;
    request.description = 'Test description';
    request.linkedAccountIds = linkedAccountIds;
    return request;
  }

  public static void assignHouseholdMembers(
    Account household,
    List<Account> memberAccounts
  ) {
    if (household == null || memberAccounts == null || memberAccounts.isEmpty()) {
      return;
    }

    for (Account memberAccount : memberAccounts) {
      memberAccount.Household__c = household.Id;
    }

    update memberAccounts;
  }

  public static Id generateFakeId(Schema.SObjectType sobjectType) {
    String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
    String fakeId = keyPrefix;

    for (Integer index = 0; index < 12; index++) {
      fakeId += '0';
    }

    return (Id) fakeId;
  }

  private static String nextScenarioKey() {
    scenarioSequence++;
    return String.valueOf(scenarioSequence);
  }

  private static String buildScenarioName(String baseName, String scenarioKey) {
    return String.isBlank(scenarioKey) ? baseName : baseName + ' ' + scenarioKey;
  }

  private static String truncateName(String value, Integer maxLength) {
    String normalizedValue = String.valueOf(value == null ? '' : value).trim();
    return normalizedValue.length() <= maxLength
      ? normalizedValue
      : normalizedValue.substring(0, maxLength);
  }
}