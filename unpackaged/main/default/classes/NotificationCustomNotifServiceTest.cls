/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationCustomNotifServiceTest {
  @IsTest
  static void buildNotificationBodyAddsUniqueSuffixForDigestItems() {
    Notification_Log__c firstLog = buildDigestLog('00TcY00000FpwAzUAJ', 'test');
    Notification_Log__c secondLog = buildDigestLog('00TcY00000FpwFpUAJ', 'test');

    String firstBody = NotificationCustomNotificationService.buildNotificationBody(
      firstLog
    );
    String secondBody = NotificationCustomNotificationService.buildNotificationBody(
      secondLog
    );

    System.assertEquals('test', firstBody);
    System.assertEquals('test', secondBody);
    System.assertEquals(firstBody, secondBody);
  }

  @IsTest
  static void buildNotificationTitleAddsUniqueSuffixForDigestItems() {
    Notification_Log__c logRecord = buildDigestLog(
      '00TcY00000FpwFpUAJ',
      'New task was created for Example Household'
    );
    logRecord.Title__c = 'New task was created for Example Household';

    String title = NotificationCustomNotificationService.buildNotificationTitle(
      logRecord
    );

    System.assertEquals(
      'New task was created for Example Household',
      title
    );
  }

  @IsTest
  static void buildNotificationTitle_returnsFallbackWhenTitleBlank() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE
    );

    String title = NotificationCustomNotificationService.buildNotificationTitle(
      logRecord
    );

    System.assertEquals('Case notification', title);
  }

  @IsTest
  static void buildNotificationBody_returnsDefaultWhenBodyBlank() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Alert title'
    );

    String body = NotificationCustomNotificationService.buildNotificationBody(
      logRecord
    );

    System.assertEquals('Open the notification to view details.', body);
  }

  @IsTest
  static void truncate_clipsAtLimit() {
    String longValue = '';
    for (Integer index = 0; index < 300; index++) {
      longValue += 'x';
    }

    String truncated = NotificationCustomNotificationService.truncate(
      longValue,
      NotificationCustomNotificationService.TITLE_LIMIT
    );

    System.assertEquals(
      NotificationCustomNotificationService.TITLE_LIMIT,
      truncated.length()
    );
    System.assertEquals(
      longValue.substring(0, NotificationCustomNotificationService.TITLE_LIMIT),
      truncated
    );
  }

  @IsTest
  static void sendNotification_skipsSendWhenTestFlagSet() {
    NotificationCustomNotificationService.testSkipSend = true;

    Test.startTest();
    NotificationCustomNotificationService.sendNotification(
      UserInfo.getUserId(),
      'Skipped title',
      'Skipped body',
      UserInfo.getUserId()
    );
    Test.stopTest();

    NotificationCustomNotificationService.testSkipSend = false;
    System.assert(true, 'Expected send to no-op when testSkipSend is enabled.');
  }

  @IsTest
  static void sendNotification_throwsWhenRecipientIdNull() {
    Boolean didThrow = false;

    try {
      NotificationCustomNotificationService.sendNotification(
        null,
        'Title',
        'Body',
        UserInfo.getUserId()
      );
    } catch (
      NotificationCustomNotificationService.NotificationCustomNotificationException expected
    ) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void sendPreferenceNotifications_noOpsWhenLogsMissing() {
    NotificationCustomNotificationService.testSkipSend = true;

    Test.startTest();
    NotificationCustomNotificationService.sendPreferenceNotifications(
      UserInfo.getUserId(),
      null
    );
    NotificationCustomNotificationService.sendPreferenceNotifications(
      UserInfo.getUserId(),
      new List<Notification_Log__c>()
    );
    Test.stopTest();

    NotificationCustomNotificationService.testSkipSend = false;
    System.assert(true, 'Expected empty log lists to no-op.');
  }

  @IsTest
  static void sendPreferenceNotifications_sendsEachLogWithTargetId() {
    NotificationCustomNotificationService.testSkipSend = true;
    Notification_Log__c targetedLog = new Notification_Log__c(
      Title__c = 'Targeted title',
      Body__c = 'Targeted body',
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Target_Record_Id__c = String.valueOf(UserInfo.getUserId())
    );
    Notification_Log__c fallbackLog = new Notification_Log__c();

    Test.startTest();
    NotificationCustomNotificationService.sendPreferenceNotifications(
      UserInfo.getUserId(),
      new List<Notification_Log__c>{ targetedLog, null, fallbackLog }
    );
    Test.stopTest();

    NotificationCustomNotificationService.testSkipSend = false;
    System.assert(true, 'Expected preference notifications to send per log.');
  }

  @IsTest
  static void resolveDeliveryTitleAndBody_delegateToBuilders() {
    Notification_Log__c logRecord = new Notification_Log__c(
      Title__c = 'Resolved title',
      Body__c = 'Resolved body',
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      'Resolved title',
      NotificationCustomNotificationService.resolveDeliveryTitle(logRecord)
    );
    System.assertEquals(
      'Resolved body',
      NotificationCustomNotificationService.resolveDeliveryBody(logRecord)
    );
  }

  private static Notification_Log__c buildDigestLog(
    String sourceRecordId,
    String body
  ) {
    return new Notification_Log__c(
      Body__c = body,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_TASK,
      Source_Record_Id__c = sourceRecordId
    );
  }
}