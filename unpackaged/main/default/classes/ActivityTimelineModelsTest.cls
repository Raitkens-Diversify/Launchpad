/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class ActivityTimelineModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    ActivityTimelineModels.Participant emptyParticipant = new ActivityTimelineModels.Participant();
    ActivityTimelineModels.ActivityItem activityItem = new ActivityTimelineModels.ActivityItem();
    ActivityTimelineModels.ActivityTimelineData activityTimelineData = new ActivityTimelineModels.ActivityTimelineData();

    emptyParticipant.id = '003000000000001';
    emptyParticipant.name = 'Empty Participant';
    emptyParticipant.objectApiName = 'Contact';

    activityItem.id = '00T000000000001';
    activityItem.dateValue = '2026-08-27';
    activityItem.activityDateTime = Datetime.now().getTime();
    activityItem.hasDueDate = true;
    activityItem.title = 'DTO Task';
    activityItem.activityType = 'Task';
    activityItem.category = 'Work';
    activityItem.status = 'Not Started';
    activityItem.description = 'DTO description';
    activityItem.ownerId = UserInfo.getUserId();
    activityItem.ownerName = UserInfo.getName();
    activityItem.linkedRecord = 'Related Account';
    activityItem.linkedRecordId = '001000000000001';
    activityItem.linkedRecordObjectApiName = 'Account';
    activityItem.associatedAccountId = '001000000000001';
    activityItem.associatedAccountName = 'DTO Account';
    activityItem.icon = 'standard:task';
    activityItem.recordObjectApiName = 'Task';
    activityItem.fromAddress = 'sender@example.com';
    activityItem.endDateValue = '2026-08-28';
    activityItem.approximateDate = false;
    activityItem.participants.add(emptyParticipant);
    activityItem.relatedParticipants.add(emptyParticipant);

    activityTimelineData.showExternalToggle = true;
    activityTimelineData.isHomeOfficeUser = true;
    activityTimelineData.isHouseholdRecordContext = true;
    activityTimelineData.isDrpRecordContext = true;
    activityTimelineData.contextBranchId = 'a1B000000000001';
    activityTimelineData.contextBranchName = 'DTO Branch';
    activityTimelineData.hasMoreActivities = true;
    activityTimelineData.nextPageNumber = 2;
    activityTimelineData.activities.add(activityItem);
    activityTimelineData.categoryCounts.put('Work', 1);

    System.assertEquals('Contact', emptyParticipant.objectApiName);
    System.assertNotEquals(null, activityItem.participants);
    System.assertNotEquals(null, activityTimelineData.activities);
    System.assertNotEquals(null, activityTimelineData.categoryCounts);
    System.assertEquals(1, activityItem.participants.size());
    System.assertEquals(1, activityTimelineData.activities.size());
    System.assertEquals(true, activityTimelineData.hasMoreActivities);
    System.assertEquals(2, activityTimelineData.nextPageNumber);
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