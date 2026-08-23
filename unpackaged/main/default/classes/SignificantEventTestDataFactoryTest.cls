/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class SignificantEventTestDataFactoryTest {
  @IsTest
  static void createScenario_buildsHouseholdEventAndParticipant() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions()
        .withFinancialAdvisorTeam()
        .withSignificantEvent()
        .withParticipant()
    );

    System.assertNotEquals(null, scenario.treeScenario.rootAccount.Id);
    System.assertNotEquals(null, scenario.household.Id);
    System.assertNotEquals(null, scenario.financialAdvisorTeam.Id);
    System.assertNotEquals(null, scenario.significantEvent.Id);
    System.assertEquals(1, scenario.participants.size());
  }

  @IsTest
  static void createScenario_withUniqueNames_createsIsolatedHouseholds() {
    SignificantEventTestDataFactory.Scenario firstScenario = SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions().withUniqueNames()
    );
    SignificantEventTestDataFactory.Scenario secondScenario = SignificantEventTestDataFactory.createScenario(
      new SignificantEventTestDataFactory.ScenarioOptions().withUniqueNames()
    );

    System.assertNotEquals(firstScenario.household.Id, secondScenario.household.Id);
    System.assertNotEquals(
      firstScenario.treeScenario.rootAccount.Id,
      secondScenario.treeScenario.rootAccount.Id
    );
  }

  @IsTest
  static void buildSaveRequest_returnsPopulatedRequest() {
    SignificantEventTestDataFactory.Scenario scenario = SignificantEventTestDataFactory.createScenario();

    SignificantEventActionModels.SaveRequest request = SignificantEventTestDataFactory.buildSaveRequest(
      scenario.treeScenario.linkedPersonAccount.Id,
      scenario.household.Id,
      new List<String>{
        String.valueOf(scenario.treeScenario.linkedPersonAccount.Id)
      }
    );

    System.assertEquals('Graduation Party', request.eventName);
    System.assertEquals(
      SignificantEventTestDataFactory.OTHER_EVENT_TYPE,
      request.eventType
    );
    System.assertEquals(1, request.linkedAccountIds.size());
  }
}