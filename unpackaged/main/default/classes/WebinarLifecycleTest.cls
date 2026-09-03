@isTest
private class WebinarLifecycleTest {

    @isTest
    static void futureEventIsUpcomingRegardlessOfRecording() {
        Datetime now = Datetime.newInstanceGmt(2026, 9, 1, 17, 0, 0);
        Datetime later = now.addMinutes(1);
        Assert.areEqual(WebinarLifecycle.UPCOMING, WebinarLifecycle.status(later, false, now));
        Assert.areEqual(WebinarLifecycle.UPCOMING, WebinarLifecycle.status(later, true, now),
            'A recording attached ahead of time does not make a future event Recorded.');
    }

    @isTest
    static void exactlyNowHasStarted() {
        Datetime now = Datetime.newInstanceGmt(2026, 9, 1, 17, 0, 0);
        Assert.areEqual(WebinarLifecycle.PAST, WebinarLifecycle.status(now, false, now),
            'At the boundary the event has started: not Upcoming.');
        Assert.areEqual(WebinarLifecycle.RECORDED, WebinarLifecycle.status(now, true, now));
    }

    @isTest
    static void pastEventSplitsOnRecording() {
        Datetime now = Datetime.newInstanceGmt(2026, 9, 1, 17, 0, 0);
        Datetime earlier = now.addDays(-1);
        Assert.areEqual(WebinarLifecycle.PAST, WebinarLifecycle.status(earlier, false, now));
        Assert.areEqual(WebinarLifecycle.RECORDED, WebinarLifecycle.status(earlier, true, now));
        Assert.isNull(WebinarLifecycle.status(null, true, now), 'No event date - no lifecycle.');
    }

    @isTest
    static void recordingIsEmbedOrFile() {
        Assert.isTrue(WebinarLifecycle.hasRecording('https://www.youtube.com/embed/x', false), 'Embed counts.');
        Assert.isTrue(WebinarLifecycle.hasRecording(null, true), 'An attached file counts.');
        Assert.isTrue(WebinarLifecycle.hasRecording('https://player.vimeo.com/video/1', true));
        Assert.isFalse(WebinarLifecycle.hasRecording('  ', false), 'Blank embed and no file: nothing to watch.');
        Assert.isFalse(WebinarLifecycle.hasRecording(null, null));
    }

    @isTest
    static void statusForRowOnlyForWebinars() {
        Datetime now = Datetime.newInstanceGmt(2026, 9, 1, 17, 0, 0);
        Resource__c video = new Resource__c(
            Resource_Type__c = 'Video', Event_Datetime__c = now.addDays(-1),
            Video_Embed_URL__c = 'https://www.youtube.com/embed/x');
        Assert.isNull(WebinarLifecycle.statusFor(video, true, now), 'Only webinars carry a lifecycle.');
        Assert.isNull(WebinarLifecycle.statusFor(null, true, now));

        Resource__c webinar = new Resource__c(
            Resource_Type__c = WebinarLifecycle.TYPE_WEBINAR, Event_Datetime__c = now.addDays(-1));
        Assert.areEqual(WebinarLifecycle.PAST, WebinarLifecycle.statusFor(webinar, false, now));
        Assert.areEqual(WebinarLifecycle.RECORDED, WebinarLifecycle.statusFor(webinar, true, now),
            'A file recording flips Past to Recorded.');
        webinar.Video_Embed_URL__c = 'https://www.youtube.com/embed/x';
        Assert.areEqual(WebinarLifecycle.RECORDED, WebinarLifecycle.statusFor(webinar, false, now),
            'An embed recording flips Past to Recorded.');
        webinar.Event_Datetime__c = now.addDays(1);
        Assert.areEqual(WebinarLifecycle.UPCOMING, WebinarLifecycle.statusFor(webinar, false, now));
        Assert.isTrue(WebinarLifecycle.isWebinar('Webinar'));
        Assert.isFalse(WebinarLifecycle.isWebinar('PDF'));
    }
}