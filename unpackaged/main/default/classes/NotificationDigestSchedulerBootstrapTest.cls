/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationDigestSchedulerBootstrapTest {
  @IsTest
  static void ensureSchedulersCreatesMissingJobs() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    List<CronTrigger> scheduledJobs = [
      SELECT CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name IN :new List<String>{
          NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
        }
    ];

    System.assertEquals(3, scheduledJobs.size());
  }

  @IsTest
  static void ensureSchedulersIsIdempotentWhenJobsAlreadyExist() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    List<CronTrigger> scheduledJobs = [
      SELECT CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name IN :new List<String>{
          NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
        }
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
    ];

    System.assertEquals(3, scheduledJobs.size());
  }

  @IsTest
  static void ensureSchedulersSkipsExistingJobsIndividually() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    System.abortJob([
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME
      LIMIT 1
    ].Id);
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    List<CronTrigger> scheduledJobs = [
      SELECT CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name IN :new List<String>{
          NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME,
          NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
        }
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
    ];

    System.assertEquals(3, scheduledJobs.size());
  }

  @IsTest
  static void ensureSchedulersRecreatesAbortedHourlyAndWeeklyJobs() {
    NotificationDigestSchedulerBootstrap.ensureSchedulers();

    List<String> jobNames = new List<String>{
      NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME,
      NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
    };

    Test.startTest();
    for (String jobName : jobNames) {
      List<CronTrigger> existingJobs = [
        SELECT Id
        FROM CronTrigger
        WHERE CronJobDetail.Name = :jobName
        LIMIT 1
      ];

      if (!existingJobs.isEmpty()) {
        System.abortJob(existingJobs[0].Id);
      }
    }

    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    System.assertEquals(
      3,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          CronJobDetail.Name IN :new List<String>{
            NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME,
            NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME,
            NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
          }
          AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      ]
    );
  }
}