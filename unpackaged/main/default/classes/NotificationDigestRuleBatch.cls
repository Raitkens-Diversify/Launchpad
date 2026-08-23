/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Finds active digest rules for a cadence and publishes Notification Center Events.
 * Optional log id scope limits debug processing to explicit preview rows.
 */
public without sharing class NotificationDigestRuleBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final String cadence;
  private final Id recipientId;
  private final String objectType;
  private final String channel;
  private final List<Id> sourceRecordIds;
  private final List<Id> logIds;
  private final NotificationDigestRepository repository;

  public NotificationDigestRuleBatch(String cadence) {
    this(cadence, null, null, null, null, null, new NotificationDigestRepository());
  }

  public NotificationDigestRuleBatch(String cadence, List<Id> logIds) {
    this(
      cadence,
      null,
      null,
      null,
      logIds,
      null,
      new NotificationDigestRepository()
    );
  }

  public NotificationDigestRuleBatch(
    String cadence,
    Id recipientId,
    String objectType,
    List<Id> sourceRecordIds
  ) {
    this(
      cadence,
      recipientId,
      objectType,
      sourceRecordIds,
      null,
      NotificationConstants.CHANNEL_EMAIL,
      new NotificationDigestRepository()
    );
  }

  @TestVisible
  private NotificationDigestRuleBatch(
    String cadence,
    Id recipientId,
    String objectType,
    List<Id> sourceRecordIds,
    List<Id> logIds,
    String channel,
    NotificationDigestRepository repository
  ) {
    this.cadence = cadence;
    this.recipientId = recipientId;
    this.objectType = objectType;
    this.channel = channel;
    this.sourceRecordIds = sourceRecordIds == null
      ? new List<Id>()
      : new List<Id>(sourceRecordIds);
    this.logIds = logIds == null ? new List<Id>() : new List<Id>(logIds);
    this.repository = repository;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    if (hasLogIdScope()) {
      return repository.selectQueuedDigestLogsByIds(logIds, channel);
    }

    if (hasSourceRecordScope()) {
      return repository.selectQueuedDigestLogsForSourceRecords(
        sourceRecordIds,
        recipientId,
        objectType,
        channel
      );
    }

    return repository.selectDigestRules(cadence);
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    if (hasLogIdScope() || hasSourceRecordScope()) {
      publishDeliveryEventsForLogs((List<Notification_Log__c>) scope);
      return;
    }

    Set<Id> ruleIds = new Set<Id>();
    for (Notification_Rule__c rule : (List<Notification_Rule__c>) scope) {
      ruleIds.add(rule.Id);
    }

    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests = NotificationDeliveryGroupingService.buildDeliveryRequestsForRuleIds(
      ruleIds,
      cadence
    );

    if (deliveryRequests.isEmpty()) {
      return;
    }

    NotificationCenterEventPublisher.publishDigestDeliveryGroups(deliveryRequests);
  }

  public void finish(Database.BatchableContext context) {
  }

  private Boolean hasLogIdScope() {
    return !logIds.isEmpty();
  }

  private Boolean hasSourceRecordScope() {
    return !sourceRecordIds.isEmpty();
  }

  private void publishDeliveryEventsForLogs(List<Notification_Log__c> logs) {
    Map<String, List<Notification_Log__c>> groupedLogs = NotificationDeliveryGroupingService.groupLogsByDeliveryKey(
      logs
    );
    List<NotificationDigestModels.DigestDeliveryRequest> deliveryRequests = new List<NotificationDigestModels.DigestDeliveryRequest>();

    for (List<Notification_Log__c> logGroup : groupedLogs.values()) {
      deliveryRequests.add(
        NotificationDeliveryGroupingService.buildDeliveryRequest(
          logGroup,
          cadence,
          0,
          channel
        )
      );
    }

    if (deliveryRequests.isEmpty()) {
      return;
    }

    NotificationCenterEventPublisher.publishDigestDeliveryGroups(deliveryRequests);
  }
}