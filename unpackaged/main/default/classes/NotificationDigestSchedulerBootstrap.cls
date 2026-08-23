/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Ensures notification digest schedulers are registered in the org.
 */
public without sharing class NotificationDigestSchedulerBootstrap {
  public static final String HOURLY_JOB_NAME = NotificationDigestScheduleService.HOURLY_JOB_NAME;
  public static final String DAILY_JOB_NAME = 'Notification Digest Daily';
  public static final String WEEKLY_JOB_NAME = 'Notification Digest Weekly';

  public static void ensureSchedulers() {
    ensureHourlyScheduler();
    ensureDailyScheduler();
    ensureWeeklyScheduler();
  }

  private static void ensureHourlyScheduler() {
    ensureScheduler(
      HOURLY_JOB_NAME,
      '0 0 * * * ?',
      new NotificationDigestHourlyScheduler()
    );
  }

  private static void ensureDailyScheduler() {
    ensureScheduler(
      DAILY_JOB_NAME,
      '0 0 * * * ?',
      new NotificationDigestDailyScheduler()
    );
  }

  private static void ensureWeeklyScheduler() {
    ensureScheduler(
      WEEKLY_JOB_NAME,
      NotificationConstants.DIGEST_WEEKLY_CRON_EXPRESSION,
      new NotificationDigestWeeklyScheduler()
    );
  }

  private static void ensureScheduler(
    String jobName,
    String cronExpression,
    Object scheduler
  ) {
    List<CronTrigger> scheduledJobs = [
      SELECT Id, CronExpression, State
      FROM CronTrigger
      WHERE CronJobDetail.Name = :jobName
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    if (scheduledJobs.isEmpty()) {
      System.schedule(jobName, cronExpression, (Schedulable) scheduler);
      return;
    }

    CronTrigger scheduledJob = scheduledJobs[0];

    if (
      scheduledJob.CronExpression != cronExpression ||
      scheduledJob.State == 'DELETED' ||
      scheduledJob.State == 'COMPLETE' ||
      scheduledJob.State == 'ERROR' ||
      scheduledJob.State == 'PAUSED' ||
      scheduledJob.State == 'PAUSED_BLOCKED' ||
      scheduledJob.State == 'BLOCKED'
    ) {
      if (scheduledJob.State != 'DELETED' && scheduledJob.State != 'COMPLETE') {
        System.abortJob(scheduledJob.Id);
      }

      System.schedule(jobName, cronExpression, (Schedulable) scheduler);
    }
  }
}