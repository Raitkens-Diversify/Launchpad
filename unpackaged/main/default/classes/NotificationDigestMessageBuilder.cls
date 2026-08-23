/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Builds consolidated digest title/body for grouped notification logs.
 */
public with sharing class NotificationDigestMessageBuilder {
  public static final Integer CUSTOM_NOTIFICATION_BODY_LIMIT = 750;
  public static final Integer EMAIL_BODY_LIMIT = 32000;

  public static NotificationDigestModels.ConsolidatedMessage build(
    String sourceType,
    List<Notification_Log__c> logs,
    Integer bodyLimit
  ) {
    Integer itemCount = logs.size();
    NotificationDigestModels.ConsolidatedMessage message = new NotificationDigestModels.ConsolidatedMessage();
    message.itemCount = itemCount;
    message.title = buildTitle(sourceType, itemCount, bodyLimit == EMAIL_BODY_LIMIT);

    if (bodyLimit == EMAIL_BODY_LIMIT) {
      message.body = NotificationDigestEmailTableBuilder.build(
        sourceType,
        logs,
        bodyLimit
      );
    } else {
      NotificationDigestContentService.enrichLogs(logs);
      message.body = buildPlainTextBody(logs, bodyLimit);
    }

    message.targetId = NotificationDigestContentService.resolvePrimaryTargetId(
      logs
    );
    return message;
  }

  public static NotificationDigestModels.ConsolidatedMessage buildForChannel(
    String sourceType,
    List<Notification_Log__c> logs,
    String channel
  ) {
    Integer bodyLimit = channel == NotificationConstants.CHANNEL_EMAIL
      ? EMAIL_BODY_LIMIT
      : CUSTOM_NOTIFICATION_BODY_LIMIT;

    return build(sourceType, logs, bodyLimit);
  }

  public static String buildPlainTextBody(
    List<Notification_Log__c> logs,
    Integer bodyLimit
  ) {
    List<String> lines = new List<String>();
    Integer lineNumber = 1;

    for (Notification_Log__c logRecord : logs) {
      String line = lineNumber + '. ' + resolveLineText(logRecord);
      lines.add(line);
      lineNumber++;
    }

    String body = String.join(lines, '\n');
    return truncateWithOverflow(body, bodyLimit, logs.size());
  }

  public static String buildEmailSubject() {
    return 'Email Digest - ' + Date.today().format();
  }

  private static String buildTitle(
    String sourceType,
    Integer itemCount,
    Boolean forEmail
  ) {
    if (forEmail == true) {
      return buildEmailSubject();
    }

    String normalizedSourceType = String.isBlank(sourceType)
      ? 'Notification'
      : sourceType;
    String countLabel = itemCount == 1 ? '1 update' : itemCount + ' updates';
    return normalizedSourceType + ' digest — ' + countLabel;
  }

  private static String resolveLineText(Notification_Log__c logRecord) {
    if (!String.isBlank(logRecord.Body__c) && !isHtmlBody(logRecord.Body__c)) {
      return logRecord.Body__c.trim();
    }

    if (String.isBlank(logRecord.Source_Record_Id__c)) {
      if (!String.isBlank(logRecord.Title__c)) {
        return logRecord.Title__c.trim();
      }

      return 'Notification item';
    }

    NotificationSourceContextService.ResolveResult context = NotificationSourceContextService.resolve(
      logRecord.Source_Type__c,
      logRecord.Source_Record_Id__c,
      logRecord.Household__c
    );

    if (isUsableSourceDetail(context.sourceDetail)) {
      return context.sourceDetail.trim();
    }

    if (!String.isBlank(context.body)) {
      return context.body.trim();
    }

    if (!String.isBlank(logRecord.Title__c)) {
      return logRecord.Title__c.trim();
    }

    return 'Notification item';
  }

  private static Boolean isHtmlBody(String body) {
    return body.contains('<table') || body.contains('<p>');
  }

  private static Boolean isUsableSourceDetail(String sourceDetail) {
    if (String.isBlank(sourceDetail)) {
      return false;
    }

    return !sourceDetail.endsWith('details unavailable');
  }

  private static String truncateWithOverflow(
    String body,
    Integer bodyLimit,
    Integer totalCount
  ) {
    if (String.isBlank(body) || body.length() <= bodyLimit) {
      return body;
    }

    String suffix = '\n+ ' + totalCount + ' more';
    Integer allowedLength = bodyLimit - suffix.length();

    if (allowedLength <= 0) {
      return NotificationCustomNotificationService.truncate(body, bodyLimit);
    }

    return NotificationCustomNotificationService.truncate(body, allowedLength) +
      suffix;
  }
}