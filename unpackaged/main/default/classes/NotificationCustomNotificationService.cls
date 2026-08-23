/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Sends Salesforce custom notifications for the Notification_Preference type.
 */
public with sharing class NotificationCustomNotificationService {
  private static Map<String, Id> notificationTypeIdByDeveloperName = new Map<String, Id>();

  public static final Integer TITLE_LIMIT = 255;
  public static final Integer BODY_LIMIT = 750;

  @TestVisible
  private static Boolean testSkipSend = false;

  public static String resolveDeliveryTitle(Notification_Log__c item) {
    return buildNotificationTitle(item);
  }

  public static String resolveDeliveryBody(Notification_Log__c item) {
    return buildNotificationBody(item);
  }

  @TestVisible
  private static String buildNotificationTitle(Notification_Log__c item) {
    if (String.isBlank(item?.Title__c)) {
      return buildFallbackTitle(item?.Source_Type__c);
    }

    return item.Title__c;
  }

  @TestVisible
  private static String buildNotificationBody(Notification_Log__c item) {
    if (String.isBlank(item?.Body__c)) {
      return 'Open the notification to view details.';
    }

    return item.Body__c;
  }

  public static void sendNotification(
    Id recipientId,
    String title,
    String body,
    Id targetId
  ) {
    sendNotification(
      recipientId,
      title,
      body,
      targetId,
      NotificationConstants.CUSTOM_NOTIFICATION_PREFERENCE
    );
  }

  public static void sendNotification(
    Id recipientId,
    String title,
    String body,
    Id targetId,
    String notificationTypeDeveloperName
  ) {
    if (recipientId == null) {
      throw new NotificationCustomNotificationException('Recipient Id is required.');
    }

    if (testSkipSend && Test.isRunningTest()) {
      return;
    }

    Id notificationTypeId = getNotificationTypeId(notificationTypeDeveloperName);
    Messaging.CustomNotification notification = new Messaging.CustomNotification();
    notification.setNotificationTypeId(notificationTypeId);
    notification.setSenderId(UserInfo.getUserId());
    notification.setTitle(truncate(title, TITLE_LIMIT));
    notification.setBody(truncate(body, BODY_LIMIT));

    if (targetId != null) {
      notification.setTargetId(targetId);
    }

    notification.send(new Set<String>{ String.valueOf(recipientId) });
  }

  private static Id getNotificationTypeId(String developerName) {
    String normalizedDeveloperName = String.isBlank(developerName)
      ? NotificationConstants.CUSTOM_NOTIFICATION_PREFERENCE
      : developerName.trim();

    if (notificationTypeIdByDeveloperName.containsKey(normalizedDeveloperName)) {
      return notificationTypeIdByDeveloperName.get(normalizedDeveloperName);
    }

    List<CustomNotificationType> notificationTypes = [
      SELECT Id
      FROM CustomNotificationType
      WHERE DeveloperName = :normalizedDeveloperName
      LIMIT 1
    ];

    if (notificationTypes.isEmpty()) {
      throw new NotificationCustomNotificationException(
        'Custom notification type ' +
          normalizedDeveloperName +
          ' was not found.'
      );
    }

    notificationTypeIdByDeveloperName.put(
      normalizedDeveloperName,
      notificationTypes[0].Id
    );
    return notificationTypes[0].Id;
  }

  @TestVisible
  private static Id getNotificationPreferenceTypeId() {
    return getNotificationTypeId(NotificationConstants.CUSTOM_NOTIFICATION_PREFERENCE);
  }

  private static String buildFallbackTitle(String objectType) {
    return String.isBlank(objectType)
      ? 'Notification'
      : objectType + ' notification';
  }

  public static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value) || value.length() <= maxLength) {
      return value;
    }

    return value.substring(0, maxLength);
  }

  public class NotificationCustomNotificationException extends Exception {
  }
}