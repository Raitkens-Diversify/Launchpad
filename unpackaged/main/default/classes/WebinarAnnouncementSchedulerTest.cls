/**
 * Tests for WebinarAnnouncementScheduler — the 15-minute sweep wrapper. The
 * rules are covered by WebinarAnnouncementServiceTest; these verify the
 * Schedulable plumbing: execute() runs a sweep, and the job schedules.
 */
@IsTest
private class WebinarAnnouncementSchedulerTest {

    @IsTest
    static void executeRunsTheSweep() {
        Resource_Category__c cat = new Resource_Category__c(
            Name = 'Webinars & Events', Slug__c = 'webinars-events', Is_Active__c = true);
        insert cat;
        // Due now: event in an hour, default announce time (8 AM today) is past
        // or, if this test runs before 8 AM org time, the explicit time is.
        insert new Resource__c(
            Name = 'Sweep Me', Slug__c = 'sweep-me', Category__c = cat.Id,
            Resource_Type__c = 'Webinar', Is_Active__c = true,
            Event_Datetime__c = System.now().addHours(1), Event_Duration_Minutes__c = 30,
            Registration_URL__c = 'https://example.com/register',
            Announce_On_Arc__c = true, Announce_At__c = System.now().addMinutes(-5));

        Test.startTest();
        new WebinarAnnouncementScheduler().execute(null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Announcement__c WHERE Is_Active__c = true],
            'execute() pushed the due webinar');
    }

    @IsTest
    static void scheduleAllCreatesFourSlotsOnceAndIsIdempotent() {
        Test.startTest();
        List<String> first = WebinarAnnouncementScheduler.scheduleAll();
        List<String> again = WebinarAnnouncementScheduler.scheduleAll();
        Test.stopTest();

        Assert.areEqual(4, first.size(), 'One job per quarter hour');
        Assert.areEqual(0, again.size(), 'Re-running schedules nothing new');
        Map<String, String> cronByName = new Map<String, String>();
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Webinar Announcement Sweep :%'
        ]) {
            cronByName.put(ct.CronJobDetail.Name, ct.CronExpression);
        }
        Assert.areEqual(4, cronByName.size());
        Assert.areEqual('0 0 * * * ?', cronByName.get('Webinar Announcement Sweep :00'));
        Assert.areEqual('0 15 * * * ?', cronByName.get('Webinar Announcement Sweep :15'));
        Assert.areEqual('0 30 * * * ?', cronByName.get('Webinar Announcement Sweep :30'));
        Assert.areEqual('0 45 * * * ?', cronByName.get('Webinar Announcement Sweep :45'));
    }
}