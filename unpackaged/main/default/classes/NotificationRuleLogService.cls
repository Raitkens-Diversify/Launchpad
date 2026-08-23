/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Resolves Notification_Rule__c preferences and creates Notification_Log__c rows
 * per channel. Routes each log to Immediate delivery or Digest queue based on
 * rule Frequency__c.
 */
public without sharing class NotificationRuleLogService {
  public NotificationRuleLogModels.ProcessRecipientResult processRecipient(
    NotificationRuleLogModels.ProcessRecipientRequest request
  ) {
    NotificationRuleLogModels.ProcessRecipientResult result = buildRecipientLogs(
      request
    );
    insertLogs(result.logs);
    return result;
  }

  public NotificationRuleLogModels.ProcessRecipientResult buildRecipientLogs(
    NotificationRuleLogModels.ProcessRecipientRequest request
  ) {
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogModels.ProcessRecipientResult();

    if (request == null) {
      return result;
    }

    if (
      request.channelPreferenceResults != null &&
      !request.channelPreferenceResults.isEmpty()
    ) {
      return buildRecipientLogsByChannel(request);
    }

    if (request.preferenceResult == null) {
      return result;
    }

    return buildRecipientLogsForSinglePreference(request);
  }

  private NotificationRuleLogModels.ProcessRecipientResult buildRecipientLogsByChannel(
    NotificationRuleLogModels.ProcessRecipientRequest request
  ) {
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogModels.ProcessRecipientResult();

    for (String channelName : NotificationConstants.CHANNEL_ORDER) {
      if (!request.channelPreferenceResults.containsKey(channelName)) {
        continue;
      }

      appendChannelLog(
        request,
        request.channelPreferenceResults.get(channelName),
        channelName,
        result
      );
    }

    if (!result.logs.isEmpty()) {
      return result;
    }

    NotificationPreferenceService.ResolveResult suppressedResult = new NotificationPreferenceService.ResolveResult(
      NotificationConstants.SUPPRESSION_NO_PREFERENCE
    );
    Notification_Log__c suppressedLog = buildNotificationLog(
      request.sourceType,
      request.sourceId,
      request.recipientId,
      request.householdId,
      request.correlationKey,
      request.changeContextJson,
      suppressedResult,
      null
    );
    result.logs.add(suppressedLog);

    return result;
  }

  private NotificationRuleLogModels.ProcessRecipientResult buildRecipientLogsForSinglePreference(
    NotificationRuleLogModels.ProcessRecipientRequest request
  ) {
    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogModels.ProcessRecipientResult();
    NotificationPreferenceService.ResolveResult preferenceResult = request.preferenceResult;

    if (!preferenceResult.isAllowed) {
      Notification_Log__c suppressedLog = buildNotificationLog(
        request.sourceType,
        request.sourceId,
        request.recipientId,
        request.householdId,
        request.correlationKey,
        request.changeContextJson,
        preferenceResult,
        null
      );
      result.logs.add(suppressedLog);
      return result;
    }

    List<String> channelNames = NotificationChannelUtils.splitChannels(
      preferenceResult.preference.Channel__c
    );

    if (channelNames.isEmpty()) {
      Notification_Log__c failedLog = buildNotificationLog(
        request.sourceType,
        request.sourceId,
        request.recipientId,
        request.householdId,
        request.correlationKey,
        request.changeContextJson,
        preferenceResult,
        null
      );
      failedLog.Status__c = NotificationConstants.STATUS_FAILED;
      failedLog.Error_Message__c = 'No notification channels configured.';
      result.logs.add(failedLog);
      return result;
    }

    for (String channelName : channelNames) {
      appendChannelLog(request, preferenceResult, channelName, result);
    }

    return result;
  }

  private void appendChannelLog(
    NotificationRuleLogModels.ProcessRecipientRequest request,
    NotificationPreferenceService.ResolveResult preferenceResult,
    String channelName,
    NotificationRuleLogModels.ProcessRecipientResult result
  ) {
    if (preferenceResult == null || !preferenceResult.isAllowed) {
      Notification_Log__c suppressedLog = buildNotificationLog(
        request.sourceType,
        request.sourceId,
        request.recipientId,
        request.householdId,
        request.correlationKey,
        request.changeContextJson,
        preferenceResult,
        channelName
      );
      result.logs.add(suppressedLog);
      return;
    }

    Notification_Log__c notificationLog = buildNotificationLog(
      request.sourceType,
      request.sourceId,
      request.recipientId,
      request.householdId,
      request.correlationKey,
      request.changeContextJson,
      preferenceResult,
      channelName
    );
    routeCreatedLog(notificationLog, result);
    result.logs.add(notificationLog);
  }

  public void insertLogs(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    try {
      NotificationGovernorLimitService.insertInChunks(logs);
    } catch (Exception error) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationRuleLogService.insertLogs',
        error
      );
      throw error;
    }
  }

  @TestVisible
  private void routeCreatedLog(
    Notification_Log__c notificationLog,
    NotificationRuleLogModels.ProcessRecipientResult result
  ) {
    if (notificationLog.Frequency__c == NotificationConstants.FREQUENCY_DIGEST) {
      notificationLog.Status__c = NotificationConstants.STATUS_QUEUED;
      return;
    }

    String normalizedChannel = NotificationChannelUtils.resolveSingleChannel(
      notificationLog.Channel__c,
      null
    );

    if (
      !NotificationConstants.isImmediateEnabledForChannel(normalizedChannel)
    ) {
      notificationLog.Status__c = NotificationConstants.STATUS_SUPPRESSED;
      notificationLog.Suppression_Reason__c = NotificationConstants.SUPPRESSION_USER_IMMEDIATE_DISABLED;
      return;
    }

    notificationLog.Status__c = NotificationConstants.STATUS_QUEUED;
    result.immediateLogs.add(notificationLog);
  }

  public Notification_Log__c buildNotificationLog(
    String sourceType,
    String sourceId,
    Id recipientId,
    Id householdId,
    String correlationKey,
    String changeContextJson,
    NotificationPreferenceService.ResolveResult preferenceResult,
    String channelName
  ) {
    Notification_Log__c notificationLog = new Notification_Log__c();
    notificationLog.Source_Type__c = sourceType;
    notificationLog.Source_Record_Id__c = sourceId;
    notificationLog.Household__c = householdId;
    notificationLog.Recipient__c = recipientId;
    notificationLog.Correlation_Key__c = correlationKey;
    notificationLog.Change_Context__c = NotificationChangeModels.ensureEnrichedJson(
      changeContextJson,
      sourceType,
      sourceId
    );

    if (preferenceResult == null || !preferenceResult.isAllowed) {
      notificationLog.Status__c = NotificationConstants.STATUS_SUPPRESSED;
      notificationLog.Suppression_Reason__c = preferenceResult == null
        ? NotificationConstants.SUPPRESSION_NO_PREFERENCE
        : preferenceResult.suppressionReason;
      return notificationLog;
    }

    notificationLog.Notification_Rule__c = preferenceResult.preference.Id;
    notificationLog.Frequency__c = preferenceResult.preference.Frequency__c;
    notificationLog.Status__c = NotificationConstants.STATUS_PENDING;
    notificationLog.Channel__c = channelName;
    notificationLog.Correlation_Key__c = buildChannelCorrelationKey(
      correlationKey,
      channelName
    );

    return notificationLog;
  }

  private static String buildChannelCorrelationKey(
    String baseKey,
    String channelName
  ) {
    if (String.isBlank(baseKey)) {
      return channelName;
    }

    return baseKey + '-' + channelName;
  }
}