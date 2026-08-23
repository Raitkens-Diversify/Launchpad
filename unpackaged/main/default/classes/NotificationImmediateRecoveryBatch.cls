/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Re-enqueues stale pending immediate notification logs for delivery.
 */
public without sharing class NotificationImmediateRecoveryBatch implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime staleThreshold = System.now().addMinutes(
      -1 * NotificationConstants.IMMEDIATE_RECOVERY_STALE_MINUTES
    );

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Notification_Log__c
        WHERE
          Frequency__c = :NotificationConstants.FREQUENCY_IMMEDIATE
          AND CreatedDate <= :staleThreshold
          AND (
            Delivery_Attempt_Count__c = NULL
            OR Delivery_Attempt_Count__c <
              :NotificationConstants.MAX_IMMEDIATE_DELIVERY_ATTEMPTS
          )
          AND (
            Status__c = :NotificationConstants.STATUS_PENDING
            OR Status__c = :NotificationConstants.STATUS_QUEUED
          )
        ORDER BY CreatedDate ASC
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Notification_Log__c> scope) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    List<Id> logIds = new List<Id>();

    for (Notification_Log__c logRecord : scope) {
      logIds.add(logRecord.Id);
    }

    NotificationDeliveryDispatcher.enqueueLogIds(logIds);
  }

  public void finish(Database.BatchableContext context) {
  }
}