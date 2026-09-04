/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * Suppresses queued and pending notification logs from prior months that were
 * never attempted for delivery.
 */
public without sharing class NotificationStaleLogCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Datetime cutoff;
  private Integer suppressedCount = 0;

  public NotificationStaleLogCleanupBatch() {
    this(Date.today().toStartOfMonth());
  }

  public NotificationStaleLogCleanupBatch(Date cutoffDate) {
    if (cutoffDate == null) {
      cutoffDate = Date.today().toStartOfMonth();
    }

    this.cutoff = Datetime.newInstance(cutoffDate, Time.newInstance(0, 0, 0, 0));
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    // QueryLocator bind variables must be local; instance fields resolve as tmpVar1 and fail.
    Datetime cutoffDatetime = cutoff;

    return Database.getQueryLocator(
      [
        SELECT Id, Status__c, Delivery_Attempt_Count__c
        FROM Notification_Log__c
        WHERE
          CreatedDate < :cutoffDatetime
          AND (
            Status__c = :NotificationConstants.STATUS_QUEUED
            OR Status__c = :NotificationConstants.STATUS_PENDING
          )
          AND (
            Delivery_Attempt_Count__c = NULL
            OR Delivery_Attempt_Count__c = 0
          )
        ORDER BY CreatedDate ASC
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Notification_Log__c> scope) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    NotificationLogDeliveryService.markSuppressed(
      scope,
      NotificationConstants.SUPPRESSION_STALE_QUEUED_CLEANUP
    );
    suppressedCount += scope.size();
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      NotificationStaleLogCleanupBatch.class.getName() +
        ' suppressed ' +
        suppressedCount +
        ' stale notification logs created before ' +
        cutoff
    );
  }

  @TestVisible
  Integer getSuppressedCountForTest() {
    return suppressedCount;
  }
}