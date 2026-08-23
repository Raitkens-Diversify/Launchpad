/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventTriggerUiTestSeederTest {
  @IsTest
  static void seedForHouseholdCreatesTriggerScenarioEvents() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Event Trigger UI Household'
    );

    Test.startTest();
    NotificationEventTriggerUiTestSeeder.SeedResult result = NotificationEventTriggerUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assert(result.scenarios.size() >= 6, 'Expected at least six trigger scenarios.');

    Map<String, NotificationEventTriggerUiTestSeeder.TriggerScenarioResult> scenarioByKey = new Map<String, NotificationEventTriggerUiTestSeeder.TriggerScenarioResult>();
    for (
      NotificationEventTriggerUiTestSeeder.TriggerScenarioResult scenario : result.scenarios
    ) {
      scenarioByKey.put(scenario.scenarioKey, scenario);
    }

    System.assert(scenarioByKey.containsKey('INSERT'));
    System.assert(scenarioByKey.containsKey('START_END'));
    System.assert(scenarioByKey.containsKey('ASSIGNED_TO'));
    System.assert(scenarioByKey.containsKey('ATTENDEES'));
    System.assert(scenarioByKey.containsKey('LOCATION'));
    System.assert(scenarioByKey.containsKey('DESCRIPTION'));

    System.assert(
      scenarioByKey.get('INSERT').subject.contains('[UI-TRIGGER-Insert]')
    );
    System.assert(
      scenarioByKey.get('START_END').subject.contains('[UI-TRIGGER-StartEnd]')
    );
    System.assert(
      scenarioByKey.get('ASSIGNED_TO').subject.contains('[UI-TRIGGER-AssignedTo]')
    );
    System.assert(
      scenarioByKey.get('ATTENDEES').subject.contains('[UI-TRIGGER-Attendees]')
    );
    System.assert(
      scenarioByKey.get('LOCATION').subject.contains('[UI-TRIGGER-Location]')
    );
    System.assert(
      scenarioByKey.get('DESCRIPTION').subject.contains('[UI-TRIGGER-Description]')
    );
  }
}