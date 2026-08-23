/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Builds notification logs for recipient chunks with governor-limit safeguards.
 */
public without sharing class NotificationRecipientPrepareService {
  private final NotificationPreferenceService preferenceService;
  private final NotificationRuleLogService ruleLogService;

  public NotificationRecipientPrepareService() {
    this(new NotificationPreferenceService(), new NotificationRuleLogService());
  }

  @TestVisible
  private NotificationRecipientPrepareService(
    NotificationPreferenceService preferenceService,
    NotificationRuleLogService ruleLogService
  ) {
    this.preferenceService = preferenceService;
    this.ruleLogService = ruleLogService;
  }

  public NotificationRecipientPrepareModels.ProcessChunkResult processChunk(
    NotificationRecipientPrepareModels.SourcePrepareContext context,
    Integer startIndex,
    Integer requestedChunkSize
  ) {
    NotificationRecipientPrepareModels.ProcessChunkResult result = new NotificationRecipientPrepareModels.ProcessChunkResult();

    if (
      context == null ||
      context.recipientIds == null ||
      context.recipientIds.isEmpty() ||
      startIndex == null ||
      startIndex >= context.recipientIds.size()
    ) {
      result.nextStartIndex = startIndex == null ? 0 : startIndex;
      return result;
    }

    Integer remainingRecipients = context.recipientIds.size() - startIndex;
    Integer chunkSize = requestedChunkSize == null
      ? NotificationGovernorLimitService.resolveRecipientChunkSize(
          remainingRecipients
        )
      : Math.min(requestedChunkSize, remainingRecipients);
    Integer endIndex = startIndex + chunkSize;
    List<Id> chunkRecipientIds = NotificationGovernorLimitService.sliceIds(
      context.recipientIds,
      startIndex,
      endIndex
    );

    if (chunkRecipientIds.isEmpty()) {
      result.nextStartIndex = endIndex;
      return result;
    }

    try {
      result.deliveryItems.addAll(
        buildAndInsertLogsForRecipients(context, chunkRecipientIds)
      );
      result.nextStartIndex = endIndex;
    } catch (Exception error) {
      result.limitReached = NotificationGovernorLimitService.isLimitException(
        error
      );
      result.caughtException = error;
      result.nextStartIndex = startIndex;
      NotificationGovernorLimitService.logLimitException(
        'NotificationRecipientPrepareService.processChunk',
        error
      );
    }

    return result;
  }

  private List<NotificationCenterDeliveryItem> buildAndInsertLogsForRecipients(
    NotificationRecipientPrepareModels.SourcePrepareContext context,
    List<Id> chunkRecipientIds
  ) {
    Set<Id> pitStopBypassRecipientIds = context.pitStopBypassRecipientIds == null
      ? new Set<Id>()
      : context.pitStopBypassRecipientIds;

    List<Id> pitStopChunkRecipientIds = new List<Id>();
    List<Id> normalChunkRecipientIds = new List<Id>();

    for (Id recipientId : chunkRecipientIds) {
      if (pitStopBypassRecipientIds.contains(recipientId)) {
        pitStopChunkRecipientIds.add(recipientId);
      } else {
        normalChunkRecipientIds.add(recipientId);
      }
    }

    Map<Id, Map<String, NotificationPreferenceService.ResolveResult>> channelPreferenceResultsByRecipientId = new Map<Id, Map<String, NotificationPreferenceService.ResolveResult>>();

    if (!pitStopChunkRecipientIds.isEmpty()) {
      channelPreferenceResultsByRecipientId.putAll(
        preferenceService.buildPitStopImmediateChannelResultsForRecipients(
          pitStopChunkRecipientIds
        )
      );
    }

    if (!normalChunkRecipientIds.isEmpty()) {
      channelPreferenceResultsByRecipientId.putAll(
        preferenceService.resolveForRecipientsByChannel(
          context.sourceType,
          normalChunkRecipientIds,
          context.householdId
        )
      );
    }

    List<Notification_Log__c> logsToInsert = new List<Notification_Log__c>();
    List<Notification_Log__c> immediateLogs = new List<Notification_Log__c>();

    for (Id recipientId : chunkRecipientIds) {
      Map<String, NotificationPreferenceService.ResolveResult> channelPreferenceResults = channelPreferenceResultsByRecipientId.get(
        recipientId
      );

      NotificationRuleLogModels.ProcessRecipientRequest processRequest = new NotificationRuleLogModels.ProcessRecipientRequest();
      processRequest.sourceType = context.sourceType;
      processRequest.sourceId = context.sourceId;
      processRequest.recipientId = recipientId;
      processRequest.householdId = context.householdId;
      processRequest.correlationKey = context.correlationKey;
      processRequest.changeContextJson = context.enrichedChangeContextJson;
      processRequest.channelPreferenceResults = channelPreferenceResults == null
        ? new Map<String, NotificationPreferenceService.ResolveResult>()
        : channelPreferenceResults;

      NotificationRuleLogModels.ProcessRecipientResult processResult = ruleLogService.buildRecipientLogs(
        processRequest
      );
      logsToInsert.addAll(processResult.logs);
      immediateLogs.addAll(processResult.immediateLogs);
    }

    ruleLogService.insertLogs(logsToInsert);

    return buildDeliveryItems(immediateLogs);
  }

  private static List<NotificationCenterDeliveryItem> buildDeliveryItems(
    List<Notification_Log__c> immediateLogs
  ) {
    List<NotificationCenterDeliveryItem> deliveryItems = new List<NotificationCenterDeliveryItem>();

    for (Notification_Log__c immediateLog : immediateLogs) {
      NotificationCenterDeliveryItem item = new NotificationCenterDeliveryItem();
      item.logId = immediateLog.Id;
      item.logIdsCsv = String.valueOf(immediateLog.Id);
      item.recipientId = immediateLog.Recipient__c;
      item.channel = NotificationChannelUtils.resolveSingleChannel(
        immediateLog.Channel__c,
        null
      );
      item.frequency = immediateLog.Frequency__c;
      item.sourceType = immediateLog.Source_Type__c;
      item.sourceRecordId = immediateLog.Source_Record_Id__c;
      deliveryItems.add(item);
    }

    return deliveryItems;
  }
}