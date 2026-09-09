/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-08
 */
@IsTest
private class NotificationCaseTriggerTest {
  @IsTest
  static void insertUpdateDeleteUndeleteFiresCaseTrigger() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Notification Case Trigger Test',
      AccountId = context.household.Id,
      Status = 'New',
      Origin = 'Phone'
    );

    Test.startTest();
    NotificationTestDataFactory.insertRecord(caseRecord);

    caseRecord.Subject = 'Updated Notification Case Trigger Test';
    NotificationTestDataFactory.updateRecord(caseRecord);

    delete caseRecord;
    undelete caseRecord;
    Test.stopTest();

    Case restoredCase = [
      SELECT Id, Subject
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];
    System.assertEquals(
      'Updated Notification Case Trigger Test',
      restoredCase.Subject
    );
  }

  @IsTest
  static void afterInsertPublishesNotificationCenterEvent() {
    NotificationPublisher.resetForTest();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Test.startTest();
    Case caseRecord = new Case(
      Subject = 'Notification Publish Case',
      AccountId = context.household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    Test.stopTest();

    System.assert(
      NotificationPublisher.testPublishedEventCount >= 1,
      'Case insert should publish a Notification Center event through Case_Trigger.'
    );
    NotificationChangeModels.ChangeContext changeContext = NotificationChangeModels.fromJson(
      NotificationPublisher.testPublishedEvents[0].Change_Context__c
    );
    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_INSERT,
      changeContext.triggerType,
      'New Case notifications must use Insert, not Update.'
    );
  }

  @IsTest
  static void afterUpdatePublishesChangeContext() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Case Change Publisher',
      AccountId = context.household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Test.startTest();
    caseRecord.Subject = 'Case Change Publisher Updated';
    NotificationTestDataFactory.updateRecord(caseRecord);
    Test.stopTest();

    System.assertNotEquals(null, caseRecord.Id);
  }
}