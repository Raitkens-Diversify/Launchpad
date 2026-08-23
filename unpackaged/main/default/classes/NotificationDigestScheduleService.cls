/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-29
 *
 * Resolves the next digest batch run from scheduled jobs and queued log cadences.
 */
public with sharing class NotificationDigestScheduleService {
  public static final String HOURLY_JOB_NAME = 'Notification Digest Hourly';

  private static final Map<String, String> JOB_NAME_BY_CADENCE = new Map<String, String>{
    NotificationConstants.DIGEST_FREQUENCY_HOURLY => HOURLY_JOB_NAME,
    NotificationConstants.DIGEST_FREQUENCY_DAILY => NotificationDigestSchedulerBootstrap.DAILY_JOB_NAME,
    NotificationConstants.DIGEST_FREQUENCY_WEEKLY => NotificationDigestSchedulerBootstrap.WEEKLY_JOB_NAME
  };

  public static String resolveNextDigestRunLabel(Id recipientId, Integer queuedCount) {
    if (queuedCount == null || queuedCount <= 0) {
      return null;
    }

    Datetime nextRun = resolveNextDigestRun(recipientId);
    return nextRun == null ? null : formatTimeLabel(nextRun);
  }

  public static Datetime resolveNextDigestRun(Id recipientId) {
    List<QueuedDigestSchedule> queuedSchedules = selectQueuedDigestSchedules(recipientId);

    if (queuedSchedules.isEmpty()) {
      queuedSchedules.add(new QueuedDigestSchedule(NotificationConstants.DIGEST_FREQUENCY_HOURLY, null));
      queuedSchedules.add(new QueuedDigestSchedule(NotificationConstants.DIGEST_FREQUENCY_DAILY, null));
      queuedSchedules.add(new QueuedDigestSchedule(NotificationConstants.DIGEST_FREQUENCY_WEEKLY, null));
    }

    Datetime earliestRun;

    for (QueuedDigestSchedule schedule : queuedSchedules) {
      Datetime candidate = resolveNextRunForSchedule(schedule);

      if (candidate == null) {
        continue;
      }

      if (earliestRun == null || candidate < earliestRun) {
        earliestRun = candidate;
      }
    }

    return earliestRun == null || earliestRun > Datetime.now()
      ? earliestRun
      : advancePastDigestRun(earliestRun, queuedSchedules);
  }

  public static String formatTimeLabel(Datetime value) {
    if (value == null) {
      return null;
    }

    String timezoneSidKey = NotificationDigestTimezoneService.getOrgTimezoneSidKey();
    String formattedTime = value.format('MMM d, h:mm a', timezoneSidKey);
    String timezoneAbbreviation = NotificationDigestTimezoneService.getDigestTimezoneAbbreviation();

    if (String.isBlank(timezoneAbbreviation)) {
      return formattedTime;
    }

    return formattedTime + ' ' + timezoneAbbreviation;
  }

  private static List<QueuedDigestSchedule> selectQueuedDigestSchedules(Id recipientId) {
    Map<String, QueuedDigestSchedule> scheduleByKey = new Map<String, QueuedDigestSchedule>();

    for (AggregateResult row : [
      SELECT
        Notification_Rule__r.Digest_Cadence__c cadence,
        Notification_Rule__r.Digest_Frequency_Hour__c digestHour
      FROM Notification_Log__c
      WHERE
        Recipient__c = :recipientId
        AND Status__c = :NotificationConstants.STATUS_QUEUED
        AND Frequency__c = :NotificationConstants.FREQUENCY_DIGEST
        AND Notification_Rule__r.Digest_Cadence__c != NULL
      GROUP BY
        Notification_Rule__r.Digest_Cadence__c,
        Notification_Rule__r.Digest_Frequency_Hour__c
    ]) {
      String cadence = (String) row.get('cadence');
      String digestHour = (String) row.get('digestHour');
      String scheduleKey = buildScheduleKey(cadence, digestHour);

      if (!scheduleByKey.containsKey(scheduleKey)) {
        scheduleByKey.put(
          scheduleKey,
          new QueuedDigestSchedule(cadence, digestHour)
        );
      }
    }

    return scheduleByKey.values();
  }

  @TestVisible
  private static Datetime resolveNextRunForSchedule(QueuedDigestSchedule schedule) {
    if (schedule == null || String.isBlank(schedule.cadence)) {
      return null;
    }

    if (schedule.cadence == NotificationConstants.DIGEST_FREQUENCY_DAILY) {
      return computeNextDailyRun(schedule.digestHour);
    }

    return resolveNextRunForCadence(schedule.cadence);
  }

  @TestVisible
  private static Datetime resolveNextRunForCadence(String cadence) {
    String jobName = JOB_NAME_BY_CADENCE.get(cadence);

    if (jobName == null) {
      return null;
    }

    List<CronTrigger> scheduledJobs = [
      SELECT NextFireTime
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :jobName
        AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
      LIMIT 1
    ];

    if (!scheduledJobs.isEmpty() && scheduledJobs[0].NextFireTime != null) {
      Datetime nextFireTime = scheduledJobs[0].NextFireTime;

      if (nextFireTime > Datetime.now()) {
        return nextFireTime;
      }
    }

    return computeFallbackNextRun(cadence);
  }

  @TestVisible
  private static Datetime computeNextDailyRun(String digestHour) {
    Integer hour = parseDigestHour(digestHour);

    if (hour == null) {
      return computeFallbackNextRun(NotificationConstants.DIGEST_FREQUENCY_DAILY);
    }

    Date orgDate = NotificationDigestTimezoneService.getOrgLocalDate();
    Integer orgHour = NotificationDigestTimezoneService.getOrgLocalHour();

    if (orgHour >= hour) {
      orgDate = orgDate.addDays(1);
    }

    return NotificationDigestTimezoneService.toGmtFromOrgLocal(
      orgDate,
      hour,
      0
    );
  }

  @TestVisible
  private static Integer parseDigestHour(String digestHour) {
    if (String.isBlank(digestHour)) {
      return null;
    }

    try {
      Integer hour = Integer.valueOf(digestHour.trim());

      if (hour < 0 || hour > 23) {
        return null;
      }

      return hour;
    } catch (Exception ex) {
      return null;
    }
  }

  @TestVisible
  private static Datetime computeFallbackNextRun(String cadence) {
    if (
      cadence == NotificationConstants.DIGEST_FREQUENCY_HOURLY ||
      cadence == NotificationConstants.DIGEST_FREQUENCY_DAILY
    ) {
      return computeNextOrgTopOfHourRun();
    }

    if (cadence == NotificationConstants.DIGEST_FREQUENCY_WEEKLY) {
      return computeNextWeeklyRun();
    }

    return null;
  }

  @TestVisible
  private static Datetime computeNextOrgTopOfHourRun() {
    Date orgDate = NotificationDigestTimezoneService.getOrgLocalDate();
    Integer orgHour = NotificationDigestTimezoneService.getOrgLocalHour();
    Datetime thisHourRun = NotificationDigestTimezoneService.toGmtFromOrgLocal(
      orgDate,
      orgHour,
      0
    );

    if (Datetime.now() < thisHourRun) {
      return thisHourRun;
    }

    if (orgHour >= 23) {
      return NotificationDigestTimezoneService.toGmtFromOrgLocal(
        orgDate.addDays(1),
        0,
        0
      );
    }

    return NotificationDigestTimezoneService.toGmtFromOrgLocal(
      orgDate,
      orgHour + 1,
      0
    );
  }

  @TestVisible
  private static Datetime computeNextWeeklyRun() {
    Date orgDate = NotificationDigestTimezoneService.getOrgLocalDate();

    for (Integer offset = 0; offset <= 7; offset++) {
      Date candidateDate = orgDate.addDays(offset);

      if (!isMonday(candidateDate)) {
        continue;
      }

      Datetime candidate = NotificationDigestTimezoneService.toGmtFromOrgLocal(
        candidateDate,
        NotificationConstants.DIGEST_WEEKLY_LOCAL_HOUR,
        NotificationConstants.DIGEST_WEEKLY_LOCAL_MINUTE
      );

      if (candidate > Datetime.now()) {
        return candidate;
      }
    }

    return null;
  }

  private static Datetime advancePastDigestRun(
    Datetime pastRun,
    List<QueuedDigestSchedule> queuedSchedules
  ) {
    for (QueuedDigestSchedule schedule : queuedSchedules) {
      Integer hour = parseDigestHour(schedule.digestHour);

      if (
        schedule.cadence != NotificationConstants.DIGEST_FREQUENCY_DAILY ||
        hour == null
      ) {
        continue;
      }

      Date orgDate = NotificationDigestTimezoneService.getOrgLocalDate().addDays(1);
      Datetime candidate = NotificationDigestTimezoneService.toGmtFromOrgLocal(
        orgDate,
        hour,
        0
      );

      while (candidate <= Datetime.now()) {
        orgDate = orgDate.addDays(1);
        candidate = NotificationDigestTimezoneService.toGmtFromOrgLocal(
          orgDate,
          hour,
          0
        );
      }

      return candidate;
    }

    if (pastRun != null) {
      Datetime candidate = computeNextOrgTopOfHourRun();

      if (candidate != null && candidate > Datetime.now()) {
        return candidate;
      }
    }

    return pastRun;
  }

  private static String buildScheduleKey(String cadence, String digestHour) {
    return String.valueOf(cadence) + '|' + String.valueOf(digestHour);
  }

  private static Boolean isMonday(Date value) {
    return Math.mod(
        Date.newInstance(1900, 1, 1).daysBetween(value),
        7
      ) == 0;
  }

  @TestVisible
  private class QueuedDigestSchedule {
    public String cadence { get; private set; }
    public String digestHour { get; private set; }

    public QueuedDigestSchedule(String cadence, String digestHour) {
      this.cadence = cadence;
      this.digestHour = digestHour;
    }
  }
}