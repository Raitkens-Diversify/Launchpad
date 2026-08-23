/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationTaskTriggerUiTestSeederTest {
  @IsTest
  static void seedForHouseholdCreatesTriggerScenarioTasks() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Task Trigger UI Household'
    );

    Test.startTest();
    NotificationTaskTriggerUiTestSeeder.SeedResult result = NotificationTaskTriggerUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assertEquals(3, result.scenarios.size());

    Map<String, NotificationTaskTriggerUiTestSeeder.TriggerScenarioResult> scenarioByKey = new Map<String, NotificationTaskTriggerUiTestSeeder.TriggerScenarioResult>();
    for (
      NotificationTaskTriggerUiTestSeeder.TriggerScenarioResult scenario : result.scenarios
    ) {
      scenarioByKey.put(scenario.scenarioKey, scenario);
    }

    System.assert(scenarioByKey.containsKey('INSERT'));
    System.assert(scenarioByKey.containsKey('ASSIGNED_TO'));
    System.assert(scenarioByKey.containsKey('STATUS'));
    System.assert(scenarioByKey.get('INSERT').subject.contains('[UI-TRIGGER-Insert]'));
    System.assert(
      scenarioByKey.get('ASSIGNED_TO').subject.contains('[UI-TRIGGER-AssignedTo]')
    );
    System.assert(scenarioByKey.get('STATUS').subject.contains('[UI-TRIGGER-Status]'));
  }

  @IsTest
  static void seedUpdatesForHouseholdCreatesUpdateScenarioTasksOnly() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Task Trigger Update UI Household'
    );

    Test.startTest();
    NotificationTaskTriggerUiTestSeeder.SeedResult result = NotificationTaskTriggerUiTestSeeder.seedUpdatesForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(2, result.scenarios.size());

    Set<String> scenarioKeys = new Set<String>();
    for (
      NotificationTaskTriggerUiTestSeeder.TriggerScenarioResult scenario : result.scenarios
    ) {
      scenarioKeys.add(scenario.scenarioKey);
    }

    System.assert(scenarioKeys.contains('ASSIGNED_TO'));
    System.assert(scenarioKeys.contains('STATUS'));
    System.assert(!scenarioKeys.contains('INSERT'));
  }
}