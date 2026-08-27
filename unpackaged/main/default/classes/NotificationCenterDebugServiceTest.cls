/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationCenterDebugServiceTest {
  @IsTest
  static void triggerDigestPublishesIndividualDeliveryJobsPerLog() {
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case firstCase = createOwnedCase(context, 'First debug case');
    Case secondCase = createOwnedCase(context, 'Second debug case');
    Notification_Log__c firstEmailLog = createCaseDigestLog(
      context,
      firstCase.Id,
      NotificationConstants.CHANNEL_EMAIL,
      'First email item'
    );
    Notification_Log__c secondEmailLog = createCaseDigestLog(
      context,
      secondCase.Id,
      NotificationConstants.CHANNEL_EMAIL,
      'Second email item'
    );
    firstEmailLog.Status__c = NotificationConstants.STATUS_SENT;
    firstEmailLog.Delivered_At__c = System.now();
    secondEmailLog.Status__c = NotificationConstants.STATUS_SENT;
    secondEmailLog.Delivered_At__c = System.now();
    update new List<Notification_Log__c>{ firstEmailLog, secondEmailLog };

    NotificationCenterDebugModels.DigestTriggerResult result;
    Test.startTest();
    System.runAs(context.recipientUser) {
      result = new NotificationCenterDebugService().triggerDigest(
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE
      );
    }
    Integer enqueuedJobCount = NotificationDeliveryDispatcher.testEnqueuedJobCount;
    Test.stopTest();

    System.assertEquals(2, result.publishedEventCount);
    System.assertEquals(2, enqueuedJobCount);
    System.assertEquals(2, result.sourceRecordCount);

    List<Notification_Log__c> updatedLogs = [
      SELECT Status__c
      FROM Notification_Log__c
      WHERE Id IN :new Set<Id>{ firstEmailLog.Id, secondEmailLog.Id }
    ];
    System.assertEquals(2, updatedLogs.size());

    for (Notification_Log__c updatedLog : updatedLogs) {
      System.assertEquals(NotificationConstants.STATUS_SENT, updatedLog.Status__c);
    }
  }

  @IsTest
  static void triggerDigestPublishesEventsForAllChannelLogs() {
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationDeliveryDispatcher.testEnqueuedJobCount = 0;

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);
    Notification_Log__c inAppLog = createDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANNEL_IN_APP
    );
    Notification_Log__c emailLog = createDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANNEL_EMAIL
    );
    inAppLog.Status__c = NotificationConstants.STATUS_SENT;
    inAppLog.Delivered_At__c = System.now();
    emailLog.Status__c = NotificationConstants.STATUS_SENT;
    emailLog.Delivered_At__c = System.now();
    update new List<Notification_Log__c>{ inAppLog, emailLog };

    Test.startTest();
    NotificationCenterDebugModels.DigestTriggerResult result;
    System.runAs(context.recipientUser) {
      result = new NotificationCenterDebugService().triggerDigest(
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE
      );
    }
    Test.stopTest();

    System.assertEquals(2, result.publishedEventCount);
    System.assertEquals(1, result.sourceRecordCount);
    System.assertEquals(2, result.previewCount);
  }

  @IsTest
  static void getDigestPreviewIncludesAllChannelsForSourceRecord() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);
    Notification_Log__c inAppLog = createDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANNEL_IN_APP
    );
    Notification_Log__c emailLog = createDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANNEL_EMAIL
    );

    List<NotificationCenterDebugModels.DebugDigestItem> preview;
    System.runAs(context.recipientUser) {
      preview = new NotificationCenterDebugService().getDigestPreview(
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE
      );
    }

    System.assertEquals(2, preview.size());

    Map<Id, NotificationCenterDebugModels.DebugDigestItem> previewById = new Map<Id, NotificationCenterDebugModels.DebugDigestItem>();
    for (NotificationCenterDebugModels.DebugDigestItem item : preview) {
      previewById.put(item.id, item);
    }

    System.assert(previewById.containsKey(inAppLog.Id));
    System.assert(previewById.containsKey(emailLog.Id));
    System.assertEquals(
      NotificationConstants.CHANNEL_IN_APP,
      previewById.get(inAppLog.Id).channel
    );
    System.assertEquals(
      NotificationConstants.CHANNEL_EMAIL,
      previewById.get(emailLog.Id).channel
    );
    System.assertEquals(
      String.valueOf(caseRecord.Id),
      previewById.get(inAppLog.Id).sourceRecordId
    );
  }

  @IsTest
  static void getDigestPreviewExcludesImmediateItems() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = createOwnedCase(context);

    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Notification_Log__c immediateLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Immediate in-app item',
      null,
      rule.Id
    );
    immediateLog.Source_Record_Id__c = String.valueOf(caseRecord.Id);
    NotificationTestDataFactory.updateRecord(immediateLog);

    Notification_Log__c digestLog = createDigestLog(
      context,
      caseRecord.Id,
      NotificationConstants.CHANNEL_IN_APP
    );

    List<NotificationCenterDebugModels.DebugDigestItem> preview;
    System.runAs(context.recipientUser) {
      preview = new NotificationCenterDebugService().getDigestPreview(
        context.recipientUser.Id,
        NotificationConstants.OBJECT_TYPE_CASE
      );
    }

    System.assertEquals(1, preview.size());
    System.assertEquals(digestLog.Id, preview[0].id);
    System.assertEquals(
      NotificationConstants.FREQUENCY_DIGEST,
      preview[0].frequency
    );
  }

  @IsTest
  static void triggerDigestThrowsWhenNoItemsFound() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Boolean threw = false;
    try {
      System.runAs(context.recipientUser) {
        new NotificationCenterDebugService().triggerDigest(
          context.recipientUser.Id,
          NotificationConstants.OBJECT_TYPE_EVENT
        );
      }
    } catch (IllegalArgumentException error) {
      threw = true;
      System.assert(error.getMessage().contains('No digest notifications were found'));
    }

    System.assertEquals(true, threw);
  }

  @IsTest
  static void controllerAllowsAdminUsers() {
    Test.startTest();
    List<NotificationCenterDebugModels.DebugDigestItem> preview =
      NotificationCenterDebugController.getDigestPreview(
        NotificationConstants.OBJECT_TYPE_CASE
      );
    Test.stopTest();

    System.assertNotEquals(null, preview);
  }

  @IsTest
  static void controllerTriggerDigest_delegatesToService() {
    Boolean didThrow = false;

    try {
      NotificationCenterDebugController.triggerDigest(
        NotificationConstants.OBJECT_TYPE_EVENT
      );
    } catch (Exception expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void controllerRejectsNonAdminUsers() {
    User standardUser = NotificationTestDataFactory.createStandardUser(
      'notifdbgnonadmin'
    );
    Boolean didThrow = false;

    System.runAs(standardUser) {
      try {
        NotificationCenterDebugController.getDigestPreview(
          NotificationConstants.OBJECT_TYPE_CASE
        );
      } catch (Exception expected) {
        didThrow = true;
      }
    }

    System.assertEquals(true, didThrow);
  }

  private static Case createOwnedCase(
    NotificationTestDataFactory.NotificationTestContext context,
    String subject
  ) {
    Case caseRecord = new Case(
      Subject = subject,
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    return caseRecord;
  }

  private static Notification_Log__c createCaseDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id sourceRecordId,
    String channel,
    String title
  ) {
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      channel,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(rule);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      channel,
      NotificationConstants.FREQUENCY_DIGEST,
      title,
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(sourceRecordId);
    NotificationTestDataFactory.updateRecord(logRecord);
    return logRecord;
  }

  private static Case createOwnedCase(
    NotificationTestDataFactory.NotificationTestContext context
  ) {
    Case caseRecord = new Case(
      Subject = 'Debug digest case',
      AccountId = context.household.Id,
      OwnerId = context.recipientUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    return caseRecord;
  }

  private static Notification_Log__c createDigestLog(
    NotificationTestDataFactory.NotificationTestContext context,
    Id sourceRecordId,
    String channel
  ) {
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      channel,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(rule);

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      channel,
      NotificationConstants.FREQUENCY_DIGEST,
      'Debug digest item',
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(sourceRecordId);
    NotificationTestDataFactory.updateRecord(logRecord);
    return logRecord;
  }
}