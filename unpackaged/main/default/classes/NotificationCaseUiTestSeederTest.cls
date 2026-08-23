/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationCaseUiTestSeederTest {
  @IsTest
  static void seedForHouseholdCreatesAc1AndAc2CasesWithScenarioSubjects() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'UI Test Notification Household'
    );

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Test.startTest();
    NotificationCaseUiTestSeeder.SeedResult result = NotificationCaseUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assertNotEquals(null, result.ac1NexsCase.Id);
    System.assertNotEquals(null, result.ac2HomeOfficeCase.Id);
    System.assert(
      result.ac1NexsCase.Subject.contains('[UI-AC1 NexS]'),
      'AC1 subject should describe the NexS scenario.'
    );
    System.assert(
      result.ac2HomeOfficeCase.Subject.contains('[UI-AC2 Home Office]'),
      'AC2 subject should describe the Home Office scenario.'
    );
    System.assertEquals(household.Id, result.ac1NexsCase.AccountId);
    System.assertEquals(household.Id, result.ac2HomeOfficeCase.AccountId);
    System.assertEquals(
      result.ac2HomeOfficeCase.OwnerId,
      result.expectedHomeOfficeRecipientId
    );

    List<CaseComment> comments = [
      SELECT Id, ParentId, IsPublished
      FROM CaseComment
      WHERE ParentId IN :new Set<Id>{ result.ac1NexsCase.Id, result.ac2HomeOfficeCase.Id }
    ];
    System.assertEquals(2, comments.size());
  }
}