/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventUiTestSeederTest {
  @IsTest
  static void seedForHouseholdCreatesAc1AndAc2EventsWithScenarioSubjects() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'UI Test Event Household'
    );

    Test.startTest();
    NotificationEventUiTestSeeder.SeedResult result = NotificationEventUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assertNotEquals(null, result.ac1NexsEvent.Id);
    System.assertNotEquals(null, result.ac2HomeOfficeEvent.Id);
    System.assert(result.ac1NexsEvent.Subject.contains('[UI-AC1 NexS]'));
    System.assert(result.ac2HomeOfficeEvent.Subject.contains('[UI-AC2 Home Office]'));
    System.assertEquals(household.Id, result.ac1NexsEvent.WhatId);
    System.assertEquals(household.Id, result.ac2HomeOfficeEvent.WhatId);
  }
}