/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 *
 * Unified notification delivery for immediate and digest channels.
 */
public without sharing class NotificationDeliveryService {
  public static Boolean skipRetryEnqueueForTest = false;

  @TestVisible
  static Integer testDeliveryExecutionCount = 0;

  private final NotificationLogRepository repository;

  public NotificationDeliveryService() {
    this(new NotificationLogRepository());
  }

  @TestVisible
  NotificationDeliveryService(NotificationLogRepository repository) {
    this.repository = repository;
  }

  public void deliver(NotificationDeliveryModels.DeliveryRequest request) {
    if (request == null || request.logIds == null || request.logIds.isEmpty()) {
      return;
    }

    hydrateImmediateFrequencyIfNeeded(request);

    if (
      request.frequency == NotificationConstants.FREQUENCY_IMMEDIATE &&
      !NotificationGovernorLimitService.canProcessImmediateDelivery()
    ) {
      deferImmediateDelivery(request);
      return;
    }

    try {
      deliverSafely(request);
    } catch (Exception error) {
      if (isGovernorLimitFailure(error)) {
        NotificationGovernorLimitService.logLimitException(
          'NotificationDeliveryService.deliver',
          error
        );
        deferImmediateDelivery(request);
        return;
      }

      throw error;
    }
  }

  private void deliverSafely(NotificationDeliveryModels.DeliveryRequest request) {
    List<Notification_Log__c> logs = loadDeliverableLogs(request);

    if (logs.isEmpty()) {
      return;
    }

    testDeliveryExecutionCount++;

    request = hydrateRequestFromLogs(request, logs);
    logs = expandDigestGroupIfNeeded(request, logs);

    if (logs.isEmpty()) {
      return;
    }

    if (shouldDeliverImmediateLogsIndividually(request, logs)) {
      deliverImmediateLogsIndividually(request, logs);
      return;
    }

    deliverSingleRequest(request, logs);
  }

  private void deliverImmediateLogsIndividually(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    NotificationEmailDeliveryService.beginBatch();
    try {
      for (Notification_Log__c logRecord : logs) {
        NotificationDeliveryModels.DeliveryRequest singleRequest = buildSingleLogRequest(
          request,
          logRecord
        );
        deliverSingleRequest(
          singleRequest,
          new List<Notification_Log__c>{ logRecord }
        );
      }
    } finally {
      NotificationEmailDeliveryService.endBatch();
    }
  }

  private void deliverSingleRequest(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    if (
      !NotificationConstants.isFrequencyEnabledForChannel(
        request.channel,
        request.frequency
      )
    ) {
      NotificationLogDeliveryService.markSuppressed(
        logs,
        resolveSuppressionReason(request.frequency)
      );
      return;
    }

    enrichLogsIfNeeded(logs, request);
    persistEnrichedContentIfChanged(logs);

    NotificationDigestModels.ConsolidatedMessage message = buildMessage(
      request,
      logs
    );

    NotificationDeliveryModels.DeliveryContext deliveryContext = new NotificationDeliveryModels.DeliveryContext();
    deliveryContext.request = request;
    deliveryContext.logs = logs;
    deliveryContext.message = message;

    INotificationChannelHandler handler = NotificationChannelRouter.getHandler(
      request.channel
    );
    NotificationDigestModels.DeliveryResult result = handler.deliver(
      deliveryContext
    );

    if (result.suppressed == true) {
      NotificationLogDeliveryService.markSuppressed(logs, result.suppressionReason);
      return;
    }

    if (result.success != true) {
      throw new NotificationDeliveryException(
        String.isBlank(result.errorMessage)
          ? 'Notification delivery failed.'
          : result.errorMessage
      );
    }

    if (request.channel != NotificationConstants.CHANNEL_EMAIL) {
      NotificationLogDeliveryService.markSent(logs);
    }
  }

  public void handleFailure(
    NotificationDeliveryModels.DeliveryRequest request,
    Exception error
  ) {
    if (request == null || request.logIds == null || request.logIds.isEmpty()) {
      return;
    }

    if (isGovernorLimitFailure(error)) {
      deferImmediateDelivery(request);
      return;
    }

    List<Notification_Log__c> logs = repository.selectLogsForRetry(request.logIds);

    if (logs.isEmpty()) {
      return;
    }

    String errorMessage = error == null
      ? 'Unknown notification delivery error.'
      : error.getMessage();

    scheduleRetryOrFail(logs, errorMessage, request);
  }

  public static void scheduleRetryOrFail(
    List<Notification_Log__c> logs,
    String errorMessage
  ) {
    scheduleRetryOrFail(logs, errorMessage, null);
  }

  public static void scheduleRetryOrFail(
    List<Notification_Log__c> logs,
    String errorMessage,
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    if (isGovernorLimitMessage(errorMessage)) {
      enqueueRetries(logs, request);
      return;
    }

    List<Notification_Log__c> retryLogs = new List<Notification_Log__c>();
    List<Notification_Log__c> failedLogs = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      Integer maxAttempts = resolveMaxAttempts(logRecord.Frequency__c);
      Integer priorAttempts = resolvePriorAttempts(logRecord, request);
      Integer attemptsAfterFailure = priorAttempts + 1;

      if (attemptsAfterFailure >= maxAttempts) {
        failedLogs.add(logRecord);
        continue;
      }

      retryLogs.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Delivery_Attempt_Count__c = attemptsAfterFailure,
          Error_Message__c = errorMessage
        )
      );
    }

    if (!retryLogs.isEmpty()) {
      update retryLogs;
      enqueueRetries(retryLogs, request);
    }

    if (!failedLogs.isEmpty()) {
      NotificationLogDeliveryService.markFailed(failedLogs, errorMessage);
    }
  }

  @TestVisible
  static void simulateFailureForTest(
    NotificationDeliveryModels.DeliveryRequest request,
    Exception error
  ) {
    new NotificationDeliveryService().handleFailure(request, error);
  }

  private void hydrateImmediateFrequencyIfNeeded(
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (
      request == null ||
      !String.isBlank(request.frequency) ||
      request.logIds == null ||
      request.logIds.isEmpty()
    ) {
      return;
    }

    List<Notification_Log__c> seedLogs = repository.selectLogsByIds(
      new List<Id>{ request.logIds[0] }
    );

    if (seedLogs.isEmpty() || String.isBlank(seedLogs[0].Frequency__c)) {
      return;
    }

    request.frequency = seedLogs[0].Frequency__c;
  }

  private static void deferImmediateDelivery(
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (skipRetryEnqueueForTest || request == null) {
      return;
    }

    if (!NotificationGovernorLimitService.canEnqueueQueueableJob()) {
      return;
    }

    NotificationDeliveryDispatcher.enqueueRequests(
      new List<NotificationDeliveryModels.DeliveryRequest>{ request }
    );
  }

  private static Boolean shouldDeliverImmediateLogsIndividually(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    if (request.frequency != NotificationConstants.FREQUENCY_IMMEDIATE) {
      return false;
    }

    if (logs == null || logs.size() <= 1) {
      return false;
    }

    return hasMultipleDistinctChannels(logs);
  }

  private static Boolean hasMultipleDistinctChannels(
    List<Notification_Log__c> logs
  ) {
    Set<String> channelNames = new Set<String>();

    for (Notification_Log__c logRecord : logs) {
      channelNames.add(
        NotificationChannelUtils.resolveSingleChannel(logRecord.Channel__c, null)
      );
    }

    return channelNames.size() > 1;
  }

  private static NotificationDeliveryModels.DeliveryRequest buildSingleLogRequest(
    NotificationDeliveryModels.DeliveryRequest request,
    Notification_Log__c logRecord
  ) {
    NotificationDeliveryModels.DeliveryRequest singleRequest = new NotificationDeliveryModels.DeliveryRequest();
    singleRequest.logIds = new List<Id>{ logRecord.Id };
    singleRequest.recipientId = request.recipientId;
    singleRequest.sourceType = request.sourceType;
    singleRequest.frequency = request.frequency;
    singleRequest.attemptNumber = request.attemptNumber;
    singleRequest.channel = NotificationChannelUtils.resolveSingleChannel(
      logRecord.Channel__c,
      null
    );
    return singleRequest;
  }

  private List<Notification_Log__c> loadDeliverableLogs(
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (
      request.deliverIndividually == true ||
      request.frequency == NotificationConstants.FREQUENCY_DIGEST
    ) {
      return repository.selectQueuedDigestLogsByIds(request.logIds);
    }

    return repository.promoteAndSelectPendingImmediateLogsByIds(request.logIds);
  }

  private static NotificationDeliveryModels.DeliveryRequest hydrateRequestFromLogs(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    Notification_Log__c firstLog = logs[0];

    if (request.recipientId == null) {
      request.recipientId = firstLog.Recipient__c;
    }

    if (String.isBlank(request.channel)) {
      request.channel = NotificationChannelUtils.resolveSingleChannel(
        firstLog.Channel__c,
        null
      );
    }

    if (String.isBlank(request.sourceType)) {
      request.sourceType = firstLog.Source_Type__c;
    }

    if (String.isBlank(request.frequency)) {
      request.frequency = firstLog.Frequency__c;
    }

    return request;
  }

  private List<Notification_Log__c> expandDigestGroupIfNeeded(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    if (
      request.deliverIndividually == true ||
      request.frequency != NotificationConstants.FREQUENCY_DIGEST
    ) {
      return logs;
    }

    List<Notification_Log__c> expandedLogs = repository.selectQueuedLogsForDeliveryGroup(
      logs[0],
      request.cadence
    );

    if (expandedLogs.isEmpty()) {
      return logs;
    }

    request.logIds = extractLogIds(expandedLogs);
    return expandedLogs;
  }

  private static NotificationDigestModels.ConsolidatedMessage buildMessage(
    NotificationDeliveryModels.DeliveryRequest request,
    List<Notification_Log__c> logs
  ) {
    if (
      request.frequency == NotificationConstants.FREQUENCY_DIGEST &&
      request.deliverIndividually != true
    ) {
      return NotificationDigestMessageBuilder.buildForChannel(
        request.sourceType,
        logs,
        request.channel
      );
    }

    Notification_Log__c logRecord = logs[0];

    if (hasCompleteMessageContent(logRecord)) {
      return buildMessageFromLog(
        logRecord,
        request.channel,
        request.frequency
      );
    }

    NotificationSourceContextService.ResolveResult context = NotificationSourceContextService.resolve(
      logRecord.Source_Type__c,
      logRecord.Source_Record_Id__c,
      logRecord.Household__c
    );

    NotificationDigestModels.ConsolidatedMessage message = new NotificationDigestModels.ConsolidatedMessage();
    message.itemCount = 1;
    message.title = String.isBlank(logRecord.Title__c)
      ? context.title
      : logRecord.Title__c;
    message.body = String.isBlank(logRecord.Body__c)
      ? context.body
      : logRecord.Body__c;
    message.targetId = NotificationDigestContentService.resolveTargetId(logRecord);

    if (request.channel == NotificationConstants.CHANNEL_EMAIL) {
      message.title = resolveDigestEmailSubject(
        request.frequency,
        logRecord,
        message.title
      );
    }

    return message;
  }

  private static NotificationDigestModels.ConsolidatedMessage buildMessageFromLog(
    Notification_Log__c logRecord,
    String channel,
    String frequency
  ) {
    NotificationDigestModels.ConsolidatedMessage message = new NotificationDigestModels.ConsolidatedMessage();
    message.itemCount = 1;
    message.title = logRecord.Title__c;
    message.body = logRecord.Body__c;
    message.targetId = NotificationDigestContentService.resolveTargetId(logRecord);

    if (channel == NotificationConstants.CHANNEL_EMAIL) {
      message.title = resolveDigestEmailSubject(
        frequency,
        logRecord,
        message.title
      );
    }

    return message;
  }

  private static String resolveDigestEmailSubject(
    String frequency,
    Notification_Log__c logRecord,
    String fallbackTitle
  ) {
    if (
      frequency == NotificationConstants.FREQUENCY_DIGEST ||
      logRecord.Frequency__c == NotificationConstants.FREQUENCY_DIGEST
    ) {
      return NotificationDigestMessageBuilder.buildEmailSubject();
    }

    return buildDistinctEmailSubject(fallbackTitle, logRecord);
  }

  private static Boolean hasCompleteMessageContent(Notification_Log__c logRecord) {
    return logRecord != null &&
      !String.isBlank(logRecord.Title__c) &&
      !String.isBlank(logRecord.Body__c);
  }

  private static void enrichLogsIfNeeded(
    List<Notification_Log__c> logs,
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (
      request != null &&
      request.frequency == NotificationConstants.FREQUENCY_DIGEST &&
      request.deliverIndividually != true &&
      request.channel == NotificationConstants.CHANNEL_EMAIL
    ) {
      return;
    }

    List<Notification_Log__c> logsNeedingContent = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      if (!hasCompleteMessageContent(logRecord)) {
        logsNeedingContent.add(logRecord);
      }
    }

    NotificationDigestContentService.enrichLogs(logsNeedingContent);
  }

  private static String buildDistinctEmailSubject(
    String title,
    Notification_Log__c logRecord
  ) {
    String normalizedTitle = String.isBlank(title) ? 'Notification' : title.trim();

    if (!String.isBlank(logRecord.Source_Record_Id__c)) {
      return normalizedTitle + ' [' + logRecord.Source_Record_Id__c + ']';
    }

    return normalizedTitle;
  }

  private static String resolveSuppressionReason(String frequency) {
    return frequency == NotificationConstants.FREQUENCY_DIGEST
      ? NotificationConstants.SUPPRESSION_USER_DIGEST_DISABLED
      : NotificationConstants.SUPPRESSION_USER_IMMEDIATE_DISABLED;
  }

  private static Integer resolveMaxAttempts(String frequency) {
    return frequency == NotificationConstants.FREQUENCY_DIGEST
      ? NotificationConstants.MAX_DIGEST_DELIVERY_ATTEMPTS
      : NotificationConstants.MAX_IMMEDIATE_DELIVERY_ATTEMPTS;
  }

  private static Integer resolvePriorAttempts(
    Notification_Log__c logRecord,
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    Integer dbAttempts = logRecord.Delivery_Attempt_Count__c == null
      ? 0
      : logRecord.Delivery_Attempt_Count__c.intValue();

    if (request != null && request.attemptNumber != null && request.attemptNumber > 0) {
      return Math.max(dbAttempts, request.attemptNumber);
    }

    return dbAttempts;
  }

  private static void persistEnrichedContentIfChanged(
    List<Notification_Log__c> logs
  ) {
    List<Notification_Log__c> updates = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : logs) {
      if (
        String.isBlank(logRecord.Title__c) &&
        String.isBlank(logRecord.Body__c) &&
        String.isBlank(logRecord.Target_Record_Id__c)
      ) {
        continue;
      }

      updates.add(
        new Notification_Log__c(
          Id = logRecord.Id,
          Title__c = logRecord.Title__c,
          Body__c = logRecord.Body__c,
          Target_Record_Id__c = logRecord.Target_Record_Id__c
        )
      );
    }

    if (!updates.isEmpty()) {
      update updates;
    }
  }

  private static List<Id> extractLogIds(List<Notification_Log__c> logs) {
    List<Id> logIds = new List<Id>();

    for (Notification_Log__c logRecord : logs) {
      logIds.add(logRecord.Id);
    }

    return logIds;
  }

  private static void enqueueRetries(
    List<Notification_Log__c> logs,
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    if (skipRetryEnqueueForTest) {
      return;
    }

    List<NotificationDeliveryModels.DeliveryRequest> retryRequests = buildRetryRequests(
      logs,
      request
    );

    if (retryRequests.isEmpty()) {
      return;
    }

    NotificationDeliveryDispatcher.enqueueRequests(retryRequests);
  }

  private static List<NotificationDeliveryModels.DeliveryRequest> buildRetryRequests(
    List<Notification_Log__c> logs,
    NotificationDeliveryModels.DeliveryRequest request
  ) {
    List<NotificationDeliveryModels.DeliveryRequest> retryRequests = new List<NotificationDeliveryModels.DeliveryRequest>();

    if (logs == null || logs.isEmpty()) {
      return retryRequests;
    }

    if (request != null && request.frequency == NotificationConstants.FREQUENCY_IMMEDIATE) {
      return NotificationDeliveryRequestBuilder.fromLogs(logs, true);
    }

    for (Notification_Log__c logRecord : logs) {
      NotificationDeliveryModels.DeliveryRequest retryRequest = request == null
        ? NotificationDeliveryRequestBuilder.fromLogId(logRecord.Id)
        : request.withAttemptNumber(
            logRecord.Delivery_Attempt_Count__c == null
              ? 1
              : logRecord.Delivery_Attempt_Count__c.intValue()
          );

      if (request == null) {
        retryRequest.logIds = new List<Id>{ logRecord.Id };
      }

      retryRequests.add(retryRequest);
    }

    return retryRequests;
  }

  private static Boolean isGovernorLimitFailure(Exception error) {
    return NotificationGovernorLimitService.isLimitException(error) ||
      (error != null && isGovernorLimitMessage(error.getMessage()));
  }

  private static Boolean isGovernorLimitMessage(String errorMessage) {
    return !String.isBlank(errorMessage) &&
      (errorMessage.contains('Insufficient SOQL budget') ||
      NotificationGovernorLimitService.isSoqlLimitMessage(errorMessage) ||
      NotificationGovernorLimitService.isEmailInvocationLimitMessage(
        errorMessage
      ) ||
      NotificationGovernorLimitService.isQueueableLimitMessage(errorMessage) ||
      errorMessage == NotificationConstants.ERROR_GOVERNOR_LIMIT);
  }

  public class NotificationDeliveryException extends Exception {
  }
}