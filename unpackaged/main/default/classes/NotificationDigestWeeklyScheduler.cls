/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Schedules weekly digest processing on Monday at 7:00 AM org time.
 *
 * Setup:
 * System.schedule(
 *   'Notification Digest Weekly',
 *   NotificationConstants.DIGEST_WEEKLY_CRON_EXPRESSION,
 *   new NotificationDigestWeeklyScheduler()
 * );
 */
public with sharing class NotificationDigestWeeklyScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    Database.executeBatch(
      new NotificationDigestRuleBatch(NotificationConstants.DIGEST_FREQUENCY_WEEKLY),
      200
    );
  }
}