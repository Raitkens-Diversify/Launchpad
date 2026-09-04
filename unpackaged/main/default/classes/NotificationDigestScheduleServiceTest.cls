/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-29
 */
@IsTest
private class NotificationDigestScheduleServiceTest {
  @IsTest
  static void resolveNextDigestRunLabelReturnsNullWhenQueueIsEmpty() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    String label = NotificationDigestScheduleService.resolveNextDigestRunLabel(
      context.recipientUser.Id,
      0
    );

    System.assertEquals(null, label);
  }

  @IsTest
  static void computeFallbackNextRunUsesNextHourForHourlyCadence() {
    Datetime nextRun = NotificationDigestScheduleService.computeFallbackNextRun(
      NotificationConstants.DIGEST_FREQUENCY_HOURLY
    );

    System.assertNotEquals(null, nextRun);
    System.assert(nextRun > Datetime.now());
  }

  @IsTest
  static void resolveNextDigestRunPrefersHourlyCadenceFromQueuedRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c hourlyRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    hourlyRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_HOURLY;
    update hourlyRule;

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Queued task digest',
      null,
      hourlyRule.Id
    );

    Datetime nextRun = NotificationDigestScheduleService.resolveNextDigestRun(
      context.recipientUser.Id
    );
    Datetime expectedHourlyRun = NotificationDigestScheduleService.computeFallbackNextRun(
      NotificationConstants.DIGEST_FREQUENCY_HOURLY
    );

    System.assertEquals(expectedHourlyRun, nextRun);
  }

  @IsTest
  static void ensureSchedulersRegistersHourlyJob() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    List<CronTrigger> scheduledJobs = [
      SELECT CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :NotificationDigestSchedulerBootstrap.HOURLY_JOB_NAME
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
    ];

    System.assertEquals(1, scheduledJobs.size());
  }

  @IsTest
  static void resolveNextDigestRunLabelReturnsFormattedTime() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c dailyRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    dailyRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(dailyRule);

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Daily digest label item',
      null,
      dailyRule.Id
    );

    String label = NotificationDigestScheduleService.resolveNextDigestRunLabel(
      context.recipientUser.Id,
      1
    );

    System.assertNotEquals(null, label);
  }

  @IsTest
  static void computeFallbackNextRunUsesDailyAndWeeklyCadence() {
    Datetime dailyRun = NotificationDigestScheduleService.computeFallbackNextRun(
      NotificationConstants.DIGEST_FREQUENCY_DAILY
    );
    Datetime weeklyRun = NotificationDigestScheduleService.computeFallbackNextRun(
      NotificationConstants.DIGEST_FREQUENCY_WEEKLY
    );

    System.assertNotEquals(null, dailyRun);
    System.assertNotEquals(null, weeklyRun);
    System.assert(dailyRun > Datetime.now().addMinutes(-1));
    System.assert(weeklyRun > Datetime.now().addMinutes(-1));
  }

  @IsTest
  static void computeNextWeeklyRunTargetsMondayMorningOrgTime() {
    Datetime nextWeeklyRun = NotificationDigestScheduleService.computeFallbackNextRun(
      NotificationConstants.DIGEST_FREQUENCY_WEEKLY
    );
    Date orgDate = Date.valueOf(
      nextWeeklyRun.format(
        'yyyy-MM-dd',
        NotificationDigestTimezoneService.getOrgTimezoneSidKey()
      )
    );
    Integer orgHour = Integer.valueOf(
      nextWeeklyRun.format('H', NotificationDigestTimezoneService.getOrgTimezoneSidKey())
    );
    Integer orgMinute = Integer.valueOf(
      nextWeeklyRun.format('m', NotificationDigestTimezoneService.getOrgTimezoneSidKey())
    );

    System.assertEquals(
      0,
      Math.mod(Date.newInstance(1900, 1, 1).daysBetween(orgDate), 7),
      'Weekly digest fallback should target Monday in org local time.'
    );
    System.assertEquals(NotificationConstants.DIGEST_WEEKLY_LOCAL_HOUR, orgHour);
    System.assertEquals(NotificationConstants.DIGEST_WEEKLY_LOCAL_MINUTE, orgMinute);
    System.assert(nextWeeklyRun > Datetime.now());
  }

  @IsTest
  static void ensureSchedulersRegistersWeeklyJobAtMondayMorning() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    CronTrigger weeklyJob = [
      SELECT CronExpression
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      LIMIT 1
    ];

    System.assertEquals(
      NotificationConstants.DIGEST_WEEKLY_CRON_EXPRESSION,
      weeklyJob.CronExpression
    );
  }

  @IsTest
  static void formatTimeLabelReturnsNullForNullInput() {
    System.assertEquals(null, NotificationDigestScheduleService.formatTimeLabel(null));
  }

  @IsTest
  static void computeNextDailyRunUsesRuleHourInOrgTimezone() {
    Integer hour = NotificationDigestTimezoneService.getOrgLocalHour();
    Datetime nextRun = NotificationDigestScheduleService.computeNextDailyRun(
      String.valueOf(hour)
    );
    Date expectedDate = NotificationDigestTimezoneService.getOrgLocalDate();

    if (NotificationDigestTimezoneService.getOrgLocalHour() >= hour) {
      expectedDate = expectedDate.addDays(1);
    }

    Datetime expected = NotificationDigestTimezoneService.toGmtFromOrgLocal(
      expectedDate,
      hour,
      0
    );

    System.assertEquals(expected, nextRun);
    System.assert(nextRun > Datetime.now());
  }

  @IsTest
  static void computeNextDailyRunReturnsTomorrowWhenDigestHourHasPassed() {
    Integer pastHour = NotificationDigestTimezoneService.getOrgLocalHour();

    if (pastHour > 0) {
      pastHour -= 1;
    }

    Datetime nextRun = NotificationDigestScheduleService.computeNextDailyRun(
      String.valueOf(pastHour)
    );
    Date expectedDate = NotificationDigestTimezoneService.getOrgLocalDate();

    if (NotificationDigestTimezoneService.getOrgLocalHour() >= pastHour) {
      expectedDate = expectedDate.addDays(1);
    }

    Datetime expected = NotificationDigestTimezoneService.toGmtFromOrgLocal(
      expectedDate,
      pastHour,
      0
    );

    System.assertEquals(expected, nextRun);
    System.assert(nextRun > Datetime.now());
  }

  @IsTest
  static void resolveNextDigestRunNeverReturnsPastTime() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c dailyRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    dailyRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    dailyRule.Digest_Frequency_Hour__c = '16';
    NotificationTestDataFactory.updateRecord(dailyRule);

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Past digest label item',
      null,
      dailyRule.Id
    );

    Datetime nextRun = NotificationDigestScheduleService.resolveNextDigestRun(
      context.recipientUser.Id
    );

    System.assertNotEquals(null, nextRun);
    System.assert(nextRun > Datetime.now());
  }

  @IsTest
  static void parseDigestHourRejectsInvalidValues() {
    System.assertEquals(null, NotificationDigestScheduleService.parseDigestHour(null));
    System.assertEquals(null, NotificationDigestScheduleService.parseDigestHour(''));
    System.assertEquals(null, NotificationDigestScheduleService.parseDigestHour('24'));
    System.assertEquals(15, NotificationDigestScheduleService.parseDigestHour('15'));
  }

  @IsTest
  static void resolveNextDigestRunUsesFallbackWhenNoQueuedLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Datetime nextRun = NotificationDigestScheduleService.resolveNextDigestRun(
      context.recipientUser.Id
    );

    System.assertNotEquals(null, nextRun);
  }

  @IsTest
  static void resolveNextRunForScheduleReturnsNullForInvalidSchedule() {
    System.assertEquals(
      null,
      NotificationDigestScheduleService.resolveNextRunForSchedule(null)
    );

    NotificationDigestScheduleService.QueuedDigestSchedule blankCadenceSchedule = new NotificationDigestScheduleService.QueuedDigestSchedule(
      '',
      '8'
    );
    System.assertEquals(
      null,
      NotificationDigestScheduleService.resolveNextRunForSchedule(blankCadenceSchedule)
    );
  }

  @IsTest
  static void resolveNextRunForCadenceReturnsNullForUnknownCadence() {
    System.assertEquals(
      null,
      NotificationDigestScheduleService.resolveNextRunForCadence('Unsupported')
    );
  }

  @IsTest
  static void resolveNextRunForCadenceUsesScheduledJobWhenRegistered() {
    Test.startTest();
    NotificationDigestSchedulerBootstrap.ensureSchedulers();
    Test.stopTest();

    Datetime nextRun = NotificationDigestScheduleService.resolveNextRunForCadence(
      NotificationConstants.DIGEST_FREQUENCY_HOURLY
    );

    System.assertNotEquals(null, nextRun);
    System.assert(nextRun > Datetime.now().addMinutes(-1));
  }

  @IsTest
  static void resolveNextRunForScheduleUsesDailyRuleHour() {
    NotificationDigestScheduleService.QueuedDigestSchedule dailySchedule = new NotificationDigestScheduleService.QueuedDigestSchedule(
      NotificationConstants.DIGEST_FREQUENCY_DAILY,
      String.valueOf(NotificationDigestTimezoneService.getOrgLocalHour())
    );

    Datetime nextRun = NotificationDigestScheduleService.resolveNextRunForSchedule(
      dailySchedule
    );

    System.assertNotEquals(null, nextRun);
    System.assert(nextRun > Datetime.now().addMinutes(-1));
  }

  @IsTest
  static void computeFallbackNextRunReturnsNullForUnknownCadence() {
    System.assertEquals(
      null,
      NotificationDigestScheduleService.computeFallbackNextRun('Unsupported')
    );
  }

  @IsTest
  static void computeNextOrgTopOfHourRunReturnsFutureRun() {
    Datetime nextRun = NotificationDigestScheduleService.computeNextOrgTopOfHourRun();

    System.assertNotEquals(null, nextRun);
    System.assert(nextRun > Datetime.now().addMinutes(-1));
  }

  @IsTest
  static void parseDigestHourRejectsNonNumericValues() {
    System.assertEquals(null, NotificationDigestScheduleService.parseDigestHour('abc'));
  }

  @IsTest
  static void formatTimeLabelReturnsFormattedValue() {
    Datetime sampleRun = Datetime.now().addHours(2);

    System.assertNotEquals(
      null,
      NotificationDigestScheduleService.formatTimeLabel(sampleRun)
    );
  }
}