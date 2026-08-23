/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventAttendeeSeederTest {
  @IsTest
  static void seedForHouseholdAddsRunningUserAsAttendee() {
    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Event Attendee UI Household'
    );

    Test.startTest();
    NotificationEventAttendeeUiTestSeeder.SeedResult result = NotificationEventAttendeeUiTestSeeder.seedForHousehold(
      household.Id
    );
    Test.stopTest();

    System.assertEquals(household.Id, result.householdId);
    System.assertEquals(UserInfo.getUserId(), result.attendeeUserId);
    System.assertNotEquals(result.attendeeUserId, result.eventCreatorId);
    System.assert(result.attendeeEvent.Subject.contains('[UI-Attendee]'));

    List<EventRelation> attendeeRelations = [
      SELECT Id, RelationId
      FROM EventRelation
      WHERE EventId = :result.attendeeEvent.Id AND IsInvitee = TRUE
    ];

    System.assertEquals(1, attendeeRelations.size());
    System.assertEquals(UserInfo.getUserId(), attendeeRelations[0].RelationId);
  }
}