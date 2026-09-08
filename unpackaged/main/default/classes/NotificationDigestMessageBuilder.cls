/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-07
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
    message.title = buildTitle(
      sourceType,
      itemCount,
      bodyLimit == EMAIL_BODY_LIMIT,
      logs
    );

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
    return buildEmailSubject(null, null);
  }

  public static String buildEmailSubject(String sourceType) {
    return buildEmailSubject(sourceType, null);
  }

  public static String buildEmailSubject(
    String sourceType,
    List<Notification_Log__c> logs
  ) {
    String typeLabel = buildEmailSubjectLabel(sourceType);
    String householdName = resolveSingleHouseholdName(logs);

    if (!String.isBlank(householdName)) {
      return typeLabel + ' — ' + householdName + ' - ' + Date.today().format();
    }

    return typeLabel + ' - ' + Date.today().format();
  }

  public static String buildEmailSubjectLabel(String sourceType) {
    return normalizeSourceType(sourceType) + ' Digest';
  }

  private static String buildTitle(
    String sourceType,
    Integer itemCount,
    Boolean forEmail,
    List<Notification_Log__c> logs
  ) {
    if (forEmail == true) {
      return buildEmailSubject(sourceType, logs);
    }

    String normalizedSourceType = normalizeSourceType(sourceType);
    String countLabel = itemCount == 1 ? '1 update' : itemCount + ' updates';
    return normalizedSourceType + ' digest — ' + countLabel;
  }

  private static String normalizeSourceType(String sourceType) {
    return String.isBlank(sourceType) ? 'Notification' : sourceType.trim();
  }

  private static String resolveSingleHouseholdName(List<Notification_Log__c> logs) {
    Set<Id> householdIds = collectHouseholdIds(logs);

    if (householdIds.size() != 1) {
      return null;
    }

    List<Account> households = [
      SELECT Name
      FROM Account
      WHERE Id IN :householdIds
      LIMIT 1
    ];

    if (households.isEmpty() || String.isBlank(households[0].Name)) {
      return null;
    }

    return households[0].Name.trim();
  }

  private static Set<Id> collectHouseholdIds(List<Notification_Log__c> logs) {
    Set<Id> householdIds = new Set<Id>();

    if (logs == null || logs.isEmpty()) {
      return householdIds;
    }

    for (Notification_Log__c logRecord : logs) {
      if (logRecord != null && logRecord.Household__c != null) {
        householdIds.add(logRecord.Household__c);
      }
    }

    return householdIds;
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