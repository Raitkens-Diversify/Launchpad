/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationTaskUiTestSeederTest {
  @IsTest
  static void seedForHouseholdCreatesAc1AndAc2TasksWithScenarioSubjects() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'UI Test Task Household'
    );

    Test.startTest();
    NotificationTaskUiTestSeeder.SeedResult result = NotificationTaskUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assertNotEquals(null, result.ac1NexsTask.Id);
    System.assertNotEquals(null, result.ac2HomeOfficeTask.Id);
    System.assertNotEquals(null, result.ac2HomeOfficeCase.Id);
    System.assert(result.ac1NexsTask.Subject.contains('[UI-AC1 NexS]'));
    System.assert(result.ac2HomeOfficeTask.Subject.contains('[UI-AC2 Home Office]'));
    System.assertEquals(household.Id, result.ac1NexsTask.WhatId);
    System.assertEquals(result.ac2HomeOfficeCase.Id, result.ac2HomeOfficeTask.WhatId);
    System.assertEquals(
      result.ac2HomeOfficeCase.OwnerId,
      result.expectedHomeOfficeRecipientId
    );
  }
}