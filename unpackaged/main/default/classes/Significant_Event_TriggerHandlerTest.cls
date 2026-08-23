/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class Significant_Event_TriggerHandlerTest {
  @IsTest
  static void isAfterInsert_createsManualShareForFinancialAdvisorTeam() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions().withFinancialAdvisorTeam()
    );
    scenario.financialAdvisorTeam = [
      SELECT Id, Public_Group_Id__c
      FROM Financial_Advisor_Team__c
      WHERE Id = :scenario.financialAdvisorTeam.Id
      LIMIT 1
    ];
    SignificantEventTestDataFactory.SignificantEventOptions eventOptions = new SignificantEventTestDataFactory.SignificantEventOptions();
    eventOptions.householdId = scenario.household.Id;
    eventOptions.financialAdvisorTeamId = scenario.financialAdvisorTeam.Id;
    eventOptions.doInsert = false;

    Test.startTest();
    Significant_Event__c eventRecord = SignificantEventTestDataFactory.createSignificantEvent(
      eventOptions
    );
    insert eventRecord;
    Test.stopTest();

    List<Significant_Event__Share> shareRecords = [
      SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
      FROM Significant_Event__Share
      WHERE
        ParentId = :eventRecord.Id
        AND RowCause = :Schema.Significant_Event__Share.RowCause.Manual
    ];

    System.assertEquals(1, shareRecords.size());
    System.assertEquals(
      scenario.financialAdvisorTeam.Public_Group_Id__c,
      shareRecords[0].UserOrGroupId
    );
    System.assertEquals('Edit', shareRecords[0].AccessLevel);
    System.assertEquals(
      Schema.Significant_Event__Share.RowCause.Manual,
      shareRecords[0].RowCause
    );
  }

  @IsTest
  static void isAfterUpdate_replacesShareWhenFinancialAdvisorTeamChanges() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions().withFinancialAdvisorTeam()
    );
    scenario.financialAdvisorTeam = [
      SELECT Id, Public_Group_Id__c
      FROM Financial_Advisor_Team__c
      WHERE Id = :scenario.financialAdvisorTeam.Id
      LIMIT 1
    ];
    Financial_Advisor_Team__c replacementTeam = SignificantEventTestDataFactory.createFinancialAdvisorTeamWithPublicGroup(
      'Replacement FAT'
    );
    replacementTeam = [
      SELECT Id, Public_Group_Id__c
      FROM Financial_Advisor_Team__c
      WHERE Id = :replacementTeam.Id
      LIMIT 1
    ];
    SignificantEventTestDataFactory.SignificantEventOptions eventOptions = new SignificantEventTestDataFactory.SignificantEventOptions();
    eventOptions.householdId = scenario.household.Id;
    eventOptions.financialAdvisorTeamId = scenario.financialAdvisorTeam.Id;
    eventOptions.doInsert = false;
    Significant_Event__c eventRecord = SignificantEventTestDataFactory.createSignificantEvent(
      eventOptions
    );
    insert eventRecord;

    Test.startTest();
    eventRecord.Financial_Advisor_Team__c = replacementTeam.Id;
    update eventRecord;
    Test.stopTest();

    List<Significant_Event__Share> shareRecords = [
      SELECT Id, UserOrGroupId
      FROM Significant_Event__Share
      WHERE
        ParentId = :eventRecord.Id
        AND RowCause = :Schema.Significant_Event__Share.RowCause.Manual
    ];

    System.assertEquals(1, shareRecords.size());
    System.assertEquals(
      replacementTeam.Public_Group_Id__c,
      shareRecords[0].UserOrGroupId
    );
  }

  @IsTest
  static void isAfterInsert_withoutFinancialAdvisorTeam_doesNotCreateShare() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.createScenario();
    SignificantEventTestDataFactory.SignificantEventOptions eventOptions = new SignificantEventTestDataFactory.SignificantEventOptions();
    eventOptions.householdId = scenario.household.Id;
    eventOptions.doInsert = false;

    Test.startTest();
    Significant_Event__c eventRecord = SignificantEventTestDataFactory.createSignificantEvent(
      eventOptions
    );
    insert eventRecord;
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Significant_Event__Share
        WHERE
          ParentId = :eventRecord.Id
          AND RowCause = :Schema.Significant_Event__Share.RowCause.Manual
      ]
    );
  }
}