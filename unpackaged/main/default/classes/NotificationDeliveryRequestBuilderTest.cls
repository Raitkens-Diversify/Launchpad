/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationDeliveryRequestBuilderTest {
  @IsTest
  static void fromLogsGroupsImmediateChannelsForSameRecipientSource() {
    Id recipientId = UserInfo.getUserId();
    String sourceRecordId = '500000000000001AAA';

    Notification_Log__c emailLog = new Notification_Log__c(
      Recipient__c = recipientId,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = sourceRecordId,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Title__c = 'Grouped title',
      Body__c = 'Grouped body'
    );
    Notification_Log__c inAppLog = new Notification_Log__c(
      Recipient__c = recipientId,
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = sourceRecordId,
      Channel__c = NotificationConstants.CHANNEL_IN_APP,
      Status__c = NotificationConstants.STATUS_PENDING,
      Frequency__c = NotificationConstants.FREQUENCY_IMMEDIATE,
      Title__c = 'Grouped title',
      Body__c = 'Grouped body'
    );
    NotificationTestDataFactory.insertRecords(new List<SObject>{ emailLog, inAppLog });

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromLogs(
      new List<Notification_Log__c>{ emailLog, inAppLog },
      true
    );

    System.assertEquals(1, requests.size());
    System.assertEquals(2, requests[0].logIds.size());
    System.assertEquals(recipientId, requests[0].recipientId);
    System.assertEquals(null, requests[0].channel);
  }

  @IsTest
  static void fromDeliveryItemsGroupsWithoutQuery() {
    Id recipientId = UserInfo.getUserId();
    String sourceRecordId = '500000000000002AAA';

    NotificationCenterDeliveryItem emailItem = new NotificationCenterDeliveryItem();
    emailItem.logId = UserInfo.getUserId();
    emailItem.recipientId = recipientId;
    emailItem.channel = NotificationConstants.CHANNEL_EMAIL;
    emailItem.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    emailItem.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    emailItem.sourceRecordId = sourceRecordId;

    NotificationCenterDeliveryItem inAppItem = new NotificationCenterDeliveryItem();
    inAppItem.logId = UserInfo.getUserId();
    inAppItem.recipientId = recipientId;
    inAppItem.channel = NotificationConstants.CHANNEL_IN_APP;
    inAppItem.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    inAppItem.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    inAppItem.sourceRecordId = sourceRecordId;

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromDeliveryItems(
      new List<NotificationCenterDeliveryItem>{ emailItem, inAppItem }
    );

    System.assertEquals(1, requests.size());
    System.assertEquals(2, requests[0].logIds.size());
  }

  @IsTest
  static void fromLogIdBuildsSingleLogRequest() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_PENDING,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Single log request',
      null,
      null
    );

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromLogId(
      logRecord.Id
    );

    System.assertEquals(1, request.logIds.size());
    System.assertEquals(logRecord.Id, request.logIds[0]);
  }

  @IsTest
  static void fromDigestCopiesDigestRequestFields() {
    NotificationDigestModels.DigestDeliveryRequest digestRequest = new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = UserInfo.getUserId();
    digestRequest.channel = NotificationConstants.CHANNEL_EMAIL;
    digestRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    digestRequest.logIds = new List<Id>{ UserInfo.getUserId() };
    digestRequest.cadence = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    digestRequest.attemptNumber = 2;

    NotificationDeliveryModels.DeliveryRequest request = NotificationDeliveryRequestBuilder.fromDigest(
      digestRequest
    );

    System.assertEquals(digestRequest.recipientId, request.recipientId);
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, request.frequency);
    System.assertEquals(2, request.attemptNumber);
  }

  @IsTest
  static void fromLogIdStringsTrimsAndSkipsBlankValues() {
    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromLogIdStrings(
      new List<String>{ ' ', null }
    );

    System.assertEquals(0, requests.size());
  }

  @IsTest
  static void fromLogsIncludesDigestRequestsWhenNotImmediateOnly() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    rule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(rule);

    Notification_Log__c digestLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest builder item',
      null,
      rule.Id
    );

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromLogs(
      new List<Notification_Log__c>{ digestLog },
      false
    );

    System.assertEquals(1, requests.size());
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, requests[0].frequency);
  }

  @IsTest
  static void fromDeliveryItemsSkipsNonImmediateFrequency() {
    NotificationCenterDeliveryItem digestItem = new NotificationCenterDeliveryItem();
    digestItem.logId = UserInfo.getUserId();
    digestItem.recipientId = UserInfo.getUserId();
    digestItem.channel = NotificationConstants.CHANNEL_EMAIL;
    digestItem.frequency = NotificationConstants.FREQUENCY_DIGEST;
    digestItem.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    digestItem.sourceRecordId = '500000000000003AAA';

    List<NotificationDeliveryModels.DeliveryRequest> requests = NotificationDeliveryRequestBuilder.fromDeliveryItems(
      new List<NotificationCenterDeliveryItem>{ digestItem }
    );

    System.assertEquals(0, requests.size());
  }
}