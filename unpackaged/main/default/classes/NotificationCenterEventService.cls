/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Orchestration for Notification Center Event platform event handling.
 */
public without sharing class NotificationCenterEventService {
  private final NotificationLogRepository logRepository;

  public NotificationCenterEventService() {
    this(new NotificationLogRepository());
  }

  @TestVisible
  private NotificationCenterEventService(NotificationLogRepository logRepository) {
    this.logRepository = logRepository;
  }

  public List<NotificationCenterDeliveryItem> prepareSourceRecord(
    String sourceType,
    String sourceId
  ) {
    return prepareSourceRecord(sourceType, sourceId, null);
  }

  public List<NotificationCenterDeliveryItem> prepareSourceRecord(
    String sourceType,
    String sourceId,
    String changeContextJson
  ) {
    if (String.isBlank(sourceType) || String.isBlank(sourceId)) {
      return new List<NotificationCenterDeliveryItem>();
    }

    try {
      NotificationRecipientPrepareModels.SourcePrepareContext prepareContext = NotificationPrepareContextFactory.build(
        sourceType,
        sourceId,
        changeContextJson
      );

      if (prepareContext == null) {
        return new List<NotificationCenterDeliveryItem>();
      }

      return NotificationRecipientPrepareDispatcher.processRecipients(
        prepareContext
      );
    } catch (Exception error) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationCenterEventService.prepareSourceRecord',
        error
      );
      return new List<NotificationCenterDeliveryItem>();
    }
  }

  public List<NotificationCenterDeliveryItem> prepareNotificationLog(
    String sourceId
  ) {
    if (String.isBlank(sourceId)) {
      return new List<NotificationCenterDeliveryItem>();
    }

    List<Notification_Log__c> seedLogs = logRepository.selectQueuedDigestLogsByIds(
      new List<Id>{ (Id) sourceId }
    );
    if (seedLogs.isEmpty()) {
      return new List<NotificationCenterDeliveryItem>();
    }

    Notification_Log__c seedLog = seedLogs[0];
    return new List<NotificationCenterDeliveryItem>{
      buildLogIdDeliveryItem(seedLog)
    };
  }

  private NotificationCenterDeliveryItem buildLogIdDeliveryItem(
    Notification_Log__c notificationLog
  ) {
    NotificationCenterDeliveryItem item = new NotificationCenterDeliveryItem();
    item.logId = notificationLog.Id;
    item.logIdsCsv = String.valueOf(notificationLog.Id);
    item.recipientId = notificationLog.Recipient__c;
    item.channel = NotificationChannelUtils.resolveSingleChannel(
      notificationLog.Channel__c,
      null
    );
    item.frequency = notificationLog.Frequency__c;
    item.sourceType = notificationLog.Source_Type__c;
    item.sourceRecordId = notificationLog.Source_Record_Id__c;
    return item;
  }
}