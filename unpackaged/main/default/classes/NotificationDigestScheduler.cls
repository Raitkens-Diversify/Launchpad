/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Schedules digest batch processing for hourly, daily, or weekly cadences.
 */
public with sharing class NotificationDigestScheduler implements Schedulable {
  private final String cadence;

  public NotificationDigestScheduler(String cadence) {
    this.cadence = cadence;
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(new NotificationDigestRuleBatch(cadence), 200);
  }
}