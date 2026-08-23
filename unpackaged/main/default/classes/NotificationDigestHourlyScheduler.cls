/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-29
 *
 * Schedules hourly digest processing at the top of each hour in org time.
 *
 * Setup:
 * System.schedule(
 *   'Notification Digest Hourly',
 *   '0 0 * * * ?',
 *   new NotificationDigestHourlyScheduler()
 * );
 */
public with sharing class NotificationDigestHourlyScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_HOURLY),
      200
    );
  }
}