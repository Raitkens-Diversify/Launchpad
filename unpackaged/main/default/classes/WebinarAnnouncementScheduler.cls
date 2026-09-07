/**
 * WebinarAnnouncementScheduler
 *
 * Every-15-minutes sweep pushing webinar announcements to Arc and retiring
 * them after the event (rules: WebinarAnnouncementService). Thin by design:
 * scheduled Apex over a scheduled flow so there is exactly ONE implementation
 * of the announce / retire rules, visible on the Apex Jobs page. Volumes are
 * tens of rows, so no Batchable.
 *
 * NOT self-scheduling. Schedule once after deploy (any admin) with
 * scripts/apex/scheduleWebinarAnnouncements.apex. Salesforce cron takes a
 * single integer for the minute, so "every 15 minutes" is FOUR jobs
 * (:00 / :15 / :30 / :45), one per entry in MINUTES, named JOB_NAME + ' :MM'.
 * The 15-minute grain is the announcement's precision: it goes live within
 * 15 minutes of the chosen time.
 */
public with sharing class WebinarAnnouncementScheduler implements Schedulable {

    public static final String JOB_NAME = 'Webinar Announcement Sweep';
    public static final List<String> MINUTES = new List<String>{ '00', '15', '30', '45' };

    /** Job name for one of the four minute slots. */
    public static String jobName(String minute) {
        return JOB_NAME + ' :' + minute;
    }

    /** Cron for one minute slot: top of that minute, every hour, every day. */
    public static String cron(String minute) {
        return '0 ' + Integer.valueOf(minute) + ' * * * ?';
    }

    /** Schedules the slots not already scheduled; returns the names it created. */
    public static List<String> scheduleAll() {
        Set<String> existing = new Set<String>();
        String pattern = JOB_NAME + ' :%';
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern
        ]) {
            existing.add(ct.CronJobDetail.Name);
        }
        List<String> scheduled = new List<String>();
        for (String minute : MINUTES) {
            String name = jobName(minute);
            if (existing.contains(name)) {
                continue;
            }
            System.schedule(name, cron(minute), new WebinarAnnouncementScheduler());
            scheduled.add(name);
        }
        return scheduled;
    }

    public void execute(SchedulableContext context) {
        WebinarAnnouncementService.sweep(System.now());
    }
}