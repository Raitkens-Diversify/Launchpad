/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Schedules daily digest processing at the top of each hour in org time.
 * Rules are filtered by Digest_Frequency_Hour__c during batch execution.
 *
 * Setup:
 * System.schedule(
 *   'Notification Digest Daily',
 *   '0 0 * * * ?',
 *   new NotificationDigestDailyScheduler()
 * );
 */
public with sharing class NotificationDigestDailyScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_DAILY),
      200
    );
  }
}