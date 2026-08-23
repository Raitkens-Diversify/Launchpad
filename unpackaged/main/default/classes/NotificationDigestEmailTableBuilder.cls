/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Builds consolidated HTML digest email tables by object type.
 */
public without sharing class NotificationDigestEmailTableBuilder {
  public static String build(
    String sourceType,
    List<Notification_Log__c> logs,
    Integer bodyLimit
  ) {
    if (logs == null || logs.isEmpty()) {
      return '';
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      return NotificationCaseEmailContentService.buildDigestTable(logs, bodyLimit);
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_TASK) {
      return NotificationTaskEmailContentService.buildDigestTable(logs, bodyLimit);
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_EVENT) {
      return NotificationEventEmailContentService.buildDigestTable(logs, bodyLimit);
    }

    return NotificationDigestMessageBuilder.buildPlainTextBody(logs, bodyLimit);
  }
}