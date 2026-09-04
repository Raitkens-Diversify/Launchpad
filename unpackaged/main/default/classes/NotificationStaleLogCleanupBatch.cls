/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * Suppresses queued and pending notification logs from prior months that were
 * never attempted for delivery.
 */
public without sharing class NotificationStaleLogCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Datetime cutoff;
  private final String queryLocatorSoql;
  private Integer suppressedCount = 0;

  public NotificationStaleLogCleanupBatch() {
    this(Date.today().toStartOfMonth());
  }

  public NotificationStaleLogCleanupBatch(Date cutoffDate) {
    if (cutoffDate == null) {
      cutoffDate = Date.today().toStartOfMonth();
    }

    this.cutoff = Datetime.newInstance(cutoffDate, Time.newInstance(0, 0, 0, 0));
    this.queryLocatorSoql = buildQueryLocatorSoql(this.cutoff);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    // QueryLocator cannot bind instance fields (tmpVar1). Use a pre-built dynamic query.
    return Database.getQueryLocator(queryLocatorSoql);
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

  private static String buildQueryLocatorSoql(Datetime cutoffDatetime) {
    String cutoffLiteral = cutoffDatetime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    String queuedStatus = String.escapeSingleQuotes(
      NotificationConstants.STATUS_QUEUED
    );
    String pendingStatus = String.escapeSingleQuotes(
      NotificationConstants.STATUS_PENDING
    );

    return 'SELECT Id, Status__c, Delivery_Attempt_Count__c ' +
      'FROM Notification_Log__c ' +
      'WHERE CreatedDate < ' +
      cutoffLiteral +
      ' ' +
      'AND (Status__c = \'' +
      queuedStatus +
      '\' OR Status__c = \'' +
      pendingStatus +
      '\') ' +
      'AND (Delivery_Attempt_Count__c = NULL OR Delivery_Attempt_Count__c = 0) ' +
      'ORDER BY CreatedDate ASC';
  }

  @TestVisible
  Integer getSuppressedCountForTest() {
    return suppressedCount;
  }
}