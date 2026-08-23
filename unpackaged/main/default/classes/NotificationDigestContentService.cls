/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Enriches notification log content for digest delivery.
 */
public without sharing class NotificationDigestContentService {
  public static void enrichLogs(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return;
    }

    for (Notification_Log__c logRecord : logs) {
      enrichLog(logRecord);
    }
  }

  public static void enrichLog(Notification_Log__c logRecord) {
    if (logRecord == null || hasCompleteContent(logRecord)) {
      return;
    }

    try {
      enrichLogSafely(logRecord);
    } catch (Exception error) {
      NotificationGovernorLimitService.logLimitException(
        'NotificationDigestContentService.enrichLog',
        error
      );

      if (String.isBlank(logRecord.Title__c)) {
        logRecord.Title__c = 'Notification update';
      }

      if (String.isBlank(logRecord.Body__c)) {
        logRecord.Body__c = NotificationConstants.ERROR_GOVERNOR_LIMIT;
      }
    }
  }

  private static void enrichLogSafely(Notification_Log__c logRecord) {
    if (logRecord.Source_Type__c == NotificationConstants.OBJECT_TYPE_TASK) {
      enrichTaskLog(logRecord);
      return;
    }

    if (logRecord.Source_Type__c == NotificationConstants.OBJECT_TYPE_EVENT) {
      enrichEventLog(logRecord);
      return;
    }

    if (logRecord.Source_Type__c == NotificationConstants.OBJECT_TYPE_CASE) {
      enrichCaseLog(logRecord);
      return;
    }

    NotificationSourceContextService.ResolveResult context = NotificationSourceContextService.resolve(
      logRecord.Source_Type__c,
      logRecord.Source_Record_Id__c,
      logRecord.Household__c
    );

    if (String.isBlank(logRecord.Title__c)) {
      logRecord.Title__c = context.title;
    }

    if (String.isBlank(logRecord.Body__c)) {
      logRecord.Body__c = context.body;
    }

    if (
      String.isBlank(readPopulatedTargetRecordId(logRecord)) &&
      !String.isBlank(context.targetRecordId)
    ) {
      logRecord.Target_Record_Id__c = context.targetRecordId;
    }
  }

  private static void enrichTaskLog(Notification_Log__c logRecord) {
    NotificationTaskEmailContentService.ContentResult content = NotificationTaskEmailContentService.build(
      logRecord
    );
    applyStructuredContent(
      logRecord,
      content.title,
      content.htmlBody,
      content.plainBody,
      content.targetRecordId
    );
  }

  private static void enrichEventLog(Notification_Log__c logRecord) {
    NotificationEventEmailContentService.ContentResult content = NotificationEventEmailContentService.build(
      logRecord
    );
    applyStructuredContent(
      logRecord,
      content.title,
      content.htmlBody,
      content.plainBody,
      content.targetRecordId
    );
  }

  private static void enrichCaseLog(Notification_Log__c logRecord) {
    NotificationCaseEmailContentService.ContentResult content = NotificationCaseEmailContentService.build(
      logRecord
    );
    applyStructuredContent(
      logRecord,
      content.title,
      content.htmlBody,
      content.plainBody,
      content.targetRecordId
    );
  }

  private static void applyStructuredContent(
    Notification_Log__c logRecord,
    String title,
    String htmlBody,
    String plainBody,
    String targetRecordId
  ) {
    if (String.isBlank(logRecord.Title__c)) {
      logRecord.Title__c = title;
    }

    if (String.isBlank(logRecord.Body__c)) {
      logRecord.Body__c = isEmailChannel(logRecord.Channel__c)
        ? htmlBody
        : plainBody;
    }

    if (
      String.isBlank(readPopulatedTargetRecordId(logRecord)) &&
      !String.isBlank(targetRecordId)
    ) {
      logRecord.Target_Record_Id__c = targetRecordId;
    }
  }

  private static String readPopulatedTargetRecordId(
    Notification_Log__c logRecord
  ) {
    return readPopulatedString(logRecord, 'Target_Record_Id__c');
  }

  private static Boolean isEmailChannel(String channelName) {
    return NotificationChannelUtils.resolveSingleChannel(channelName, null) ==
      NotificationConstants.CHANNEL_EMAIL;
  }

  private static Boolean hasCompleteContent(Notification_Log__c logRecord) {
    return !String.isBlank(logRecord.Title__c) && !String.isBlank(logRecord.Body__c);
  }

  public static Id resolveTargetId(Notification_Log__c logRecord) {
    if (logRecord == null) {
      return null;
    }

    String targetRecordId = readPopulatedString(logRecord, 'Target_Record_Id__c');
    if (!String.isBlank(targetRecordId)) {
      return (Id) targetRecordId;
    }

    String sourceRecordId = readPopulatedString(logRecord, 'Source_Record_Id__c');
    if (!String.isBlank(sourceRecordId)) {
      return (Id) sourceRecordId;
    }

    if (!hasPopulatedField(logRecord, 'Household__c')) {
      return null;
    }

    return logRecord.Household__c;
  }

  private static String readPopulatedString(
    Notification_Log__c logRecord,
    String fieldApiName
  ) {
    if (!hasPopulatedField(logRecord, fieldApiName)) {
      return null;
    }

    Object fieldValue = logRecord.get(fieldApiName);
    return fieldValue == null ? null : String.valueOf(fieldValue);
  }

  private static Boolean hasPopulatedField(
    Notification_Log__c logRecord,
    String fieldApiName
  ) {
    return logRecord.getPopulatedFieldsAsMap().containsKey(fieldApiName);
  }

  public static Id resolvePrimaryTargetId(List<Notification_Log__c> logs) {
    if (logs == null || logs.isEmpty()) {
      return null;
    }

    for (Notification_Log__c logRecord : logs) {
      Id targetId = resolveTargetId(logRecord);
      if (targetId != null) {
        return targetId;
      }
    }

    return null;
  }
}