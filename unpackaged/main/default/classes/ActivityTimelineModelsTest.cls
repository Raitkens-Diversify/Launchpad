/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class ActivityTimelineModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    ActivityTimelineModels.ActivityItem activityItem = new ActivityTimelineModels.ActivityItem();
    ActivityTimelineModels.ActivityTimelineData activityTimelineData = new ActivityTimelineModels.ActivityTimelineData();

    System.assertNotEquals(null, activityItem.participants);
    System.assertNotEquals(null, activityTimelineData.activities);
    System.assertNotEquals(null, activityTimelineData.categoryCounts);
    System.assertEquals(0, activityItem.participants.size());
    System.assertEquals(0, activityTimelineData.activities.size());
  }

  @IsTest
  static void participantConstructor_setsLinkFields() {
    ActivityTimelineModels.Participant participant = new ActivityTimelineModels.Participant(
      '005XXXXXXXXXXXX',
      'Test User',
      'User'
    );

    System.assertEquals('005XXXXXXXXXXXX', participant.id);
    System.assertEquals('Test User', participant.name);
    System.assertEquals('User', participant.objectApiName);
  }
}