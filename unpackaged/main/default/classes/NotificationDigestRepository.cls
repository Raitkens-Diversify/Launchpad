/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * SOQL access for scheduled digest batch scopes (rules and QueryLocators).
 */
public without sharing class NotificationDigestRepository {
  public Database.QueryLocator selectDigestRules(String cadence) {
    if (cadence == NotificationConstants.DIGEST_FREQUENCY_DAILY) {
      String currentHour = NotificationDigestTimezoneService.currentDigestHourValue();

      return Database.getQueryLocator(
        [
          SELECT
            Id,
            Object_Type__c,
            Channel__c,
            User__c,
            Household__c,
            Digest_Cadence__c,
            Digest_Frequency_Hour__c
          FROM Notification_Rule__c
          WHERE
            Is_Active__c = TRUE
            AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
            AND Digest_Cadence__c = :cadence
            AND Digest_Frequency_Hour__c = :currentHour
        ]
      );
    }

    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Object_Type__c,
          Channel__c,
          User__c,
          Household__c,
          Digest_Cadence__c,
          Digest_Frequency_Hour__c
        FROM Notification_Rule__c
        WHERE
          Is_Active__c = TRUE
          AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
          AND Digest_Cadence__c = :cadence
      ]
    );
  }

  public Database.QueryLocator selectQueuedDigestLogsByIds(
    List<Id> logIds,
    String channel
  ) {
    if (String.isBlank(channel)) {
      return Database.getQueryLocator(
        [
          SELECT
            Id,
            Name,
            Recipient__c,
            Channel__c,
            Source_Type__c,
            Notification_Rule__c,
            Title__c,
            Body__c,
            Change_Context__c,
            CreatedDate,
            Source_Record_Id__c,
            Target_Record_Id__c,
            Household__c,
            Status__c,
            Frequency__c,
            Delivery_Attempt_Count__c
          FROM Notification_Log__c
          WHERE
            Id IN :logIds
            AND Status__c = :NotificationConstants.STATUS_QUEUED
            AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        ]
      );
    }

    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          Recipient__c,
          Channel__c,
          Source_Type__c,
          Notification_Rule__c,
          Title__c,
          Body__c,
          Change_Context__c,
          CreatedDate,
          Source_Record_Id__c,
          Target_Record_Id__c,
          Household__c,
          Status__c,
          Frequency__c,
          Delivery_Attempt_Count__c
        FROM Notification_Log__c
        WHERE
          Id IN :logIds
          AND Status__c = :NotificationConstants.STATUS_QUEUED
          AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
          AND Channel__c INCLUDES (:channel)
      ]
    );
  }

  public Database.QueryLocator selectQueuedDigestLogsForSourceRecords(
    List<Id> sourceRecordIds,
    Id recipientId,
    String objectType,
    String channel
  ) {
    Set<String> sourceRecordIdStrings = toSourceRecordIdStrings(sourceRecordIds);

    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Name,
          Recipient__c,
          Channel__c,
          Source_Type__c,
          Notification_Rule__c,
          Title__c,
          Body__c,
          Change_Context__c,
          CreatedDate,
          Source_Record_Id__c,
          Target_Record_Id__c,
          Household__c,
          Status__c,
          Frequency__c,
          Delivery_Attempt_Count__c
        FROM Notification_Log__c
        WHERE
          Status__c = :NotificationConstants.STATUS_QUEUED
          AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
          AND Source_Record_Id__c IN :sourceRecordIdStrings
          AND Recipient__c = :recipientId
          AND Source_Type__c = :objectType
          AND Channel__c INCLUDES (:channel)
      ]
    );
  }

  private static Set<String> toSourceRecordIdStrings(List<Id> sourceRecordIds) {
    Set<String> sourceRecordIdStrings = new Set<String>();

    if (sourceRecordIds == null) {
      return sourceRecordIdStrings;
    }

    for (Id sourceRecordId : sourceRecordIds) {
      if (sourceRecordId != null) {
        sourceRecordIdStrings.add(String.valueOf(sourceRecordId));
      }
    }

    return sourceRecordIdStrings;
  }
}