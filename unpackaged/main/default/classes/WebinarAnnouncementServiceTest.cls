/**
 * WebinarAnnouncementServiceTest — the announce / retire rules and the sweep.
 * Instants are explicit (the WebinarLifecycle discipline) and the org zone is
 * pinned to America/Denver so the 8:00 AM default is deterministic.
 */
@IsTest
private class WebinarAnnouncementServiceTest {

    private static final String TZ = 'America/Denver';
    // Tue 2026-09-08 9:00 AM MDT (UTC-6).
    private static final Datetime EVENT = Datetime.newInstanceGmt(2026, 9, 8, 15, 0, 0);
    private static final Datetime EIGHT_AM = Datetime.newInstanceGmt(2026, 9, 8, 14, 0, 0);

    @TestSetup
    static void setup() {
        insert new Resource_Category__c(
            Name = 'Webinars & Events', Slug__c = 'webinars-events', Is_Active__c = true);
    }

    private static Id categoryId() {
        return [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'webinars-events' LIMIT 1].Id;
    }

    private static Resource__c webinar(String slug, Datetime eventAt, Boolean announce) {
        Resource__c r = new Resource__c(
            Name = 'Getting Started with Arc', Slug__c = slug, Category__c = categoryId(),
            Resource_Type__c = 'Webinar', Is_Active__c = true,
            Event_Datetime__c = eventAt, Event_Duration_Minutes__c = 60,
            Presenter__c = 'Kelby and Aubrie', Description__c = 'Essential for Lite users.',
            Registration_URL__c = 'https://example.com/register',
            Announce_On_Arc__c = announce);
        insert r;
        return r;
    }

    private static Resource__c reload(Id id) {
        return [
            SELECT Id, Name, Slug__c, Description__c, Summary__c, Resource_Type__c, Is_Active__c,
                   Event_Datetime__c, Event_Duration_Minutes__c, Presenter__c,
                   Announce_On_Arc__c, Announce_At__c, Announcement__c,
                   Announcement__r.Name, Announcement__r.Body__c,
                   Announcement__r.Link_URL__c, Announcement__r.Is_Active__c
            FROM Resource__c WHERE Id = :id
        ];
    }

    /** Route the Arc link through the seams: no Site/SiteDetail in tests. */
    private static void seedArcSite() {
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Arc') => new Help_Surface__mdt(
                Network_Name__c = 'Arc', Home_Path__c = 'help-center', Article_Path__c = 'article',
                Resources_Path__c = 'learning', Events_Path__c = 'events')
        };
        ResourceCenterService.siteBaseOverride.put('Arc', 'https://arc.example');
    }

    // ---- default announce time ------------------------------------------------------

    @IsTest
    static void defaultAnnounceTimeIsEightAmOrgTimeOnTheEventDay() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        Assert.areEqual(EIGHT_AM, WebinarAnnouncementService.effectiveAnnounceAt(EVENT, null),
            '9 AM MDT event → 8 AM MDT the same day (14:00Z)');
        Datetime explicitAt = Datetime.newInstanceGmt(2026, 9, 7, 20, 0, 0);
        Assert.areEqual(explicitAt, WebinarAnnouncementService.effectiveAnnounceAt(EVENT, explicitAt),
            'An explicit time wins');
        Assert.isNull(WebinarAnnouncementService.effectiveAnnounceAt(null, null));
        // A 10 PM MDT event is still "today" locally though already tomorrow in UTC.
        Datetime lateEvent = Datetime.newInstanceGmt(2026, 9, 9, 4, 0, 0);
        Assert.areEqual(EIGHT_AM, WebinarAnnouncementService.effectiveAnnounceAt(lateEvent, null),
            'Local date, not the UTC date');
    }

    @IsTest
    static void earlyEventsAnnounceTheDayBefore() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        Datetime dayBefore = Datetime.newInstanceGmt(2026, 9, 7, 14, 0, 0);
        Datetime sevenAm = Datetime.newInstanceGmt(2026, 9, 8, 13, 0, 0);
        Assert.areEqual(dayBefore, WebinarAnnouncementService.effectiveAnnounceAt(sevenAm, null),
            '7 AM event: 8 AM would be after the start');
        Assert.areEqual(dayBefore, WebinarAnnouncementService.effectiveAnnounceAt(EIGHT_AM, null),
            'Exactly 8 AM: never announce at the start');
    }

    // ---- announceable ------------------------------------------------------------

    @IsTest
    static void announceableFollowsFlagActivityWindowAndEnd() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        Resource__c r = webinar('w1', EVENT, true);
        r = reload(r.Id);

        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EIGHT_AM.addMinutes(-1)),
            'Before the announce time');
        Assert.isTrue(WebinarAnnouncementService.isAnnounceable(r, EIGHT_AM), 'At the announce time');
        Assert.isTrue(WebinarAnnouncementService.isAnnounceable(r, EVENT.addMinutes(59)),
            'Still live while the event runs');
        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EVENT.addMinutes(60)),
            'Ended = start + duration');

        r.Announce_On_Arc__c = false;
        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EIGHT_AM), 'Flag off');
        r.Announce_On_Arc__c = true;
        r.Is_Active__c = false;
        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EIGHT_AM), 'Inactive webinar');
        r.Is_Active__c = true;
        r.Resource_Type__c = 'PDF';
        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EIGHT_AM), 'Not a webinar');

        r.Resource_Type__c = 'Webinar';
        r.Event_Duration_Minutes__c = null;
        Assert.isTrue(WebinarAnnouncementService.isAnnounceable(r, EVENT.addMinutes(59)),
            'Blank duration counts as 60 minutes');
        Assert.isFalse(WebinarAnnouncementService.isAnnounceable(r, EVENT.addMinutes(60)));
        Assert.isFalse(WebinarAnnouncementService.hasEnded(null, EVENT));
    }

    @IsTest
    static void statusForTheEditor() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        Resource__c r = reload(webinar('w2', EVENT, true).Id);

        Assert.areEqual('Scheduled', WebinarAnnouncementService.statusFor(r, null, EIGHT_AM.addMinutes(-1)));
        Assert.areEqual('Pending', WebinarAnnouncementService.statusFor(r, null, EIGHT_AM),
            'Due but the sweep has not pushed yet');
        Assert.areEqual('Live', WebinarAnnouncementService.statusFor(r, true, EIGHT_AM));
        Assert.areEqual('Ended', WebinarAnnouncementService.statusFor(r, true, EVENT.addHours(2)));
        r.Announce_On_Arc__c = false;
        Assert.isNull(WebinarAnnouncementService.statusFor(r, true, EIGHT_AM), 'Not flagged → no line');
        Assert.isNull(WebinarAnnouncementService.statusFor(null, null, EIGHT_AM));
    }

    // ---- content -------------------------------------------------------------------

    @IsTest
    static void bodyAndLinkAreBuiltFromTheWebinar() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        seedArcSite();
        Resource__c r = reload(webinar('getting-started', EVENT, true).Id);

        Announcement__c a = WebinarAnnouncementService.build(r);
        Assert.isTrue(a.Is_Active__c);
        Assert.areEqual('Getting Started with Arc', a.Name);
        Assert.areEqual('Tue, Sep 8 at 9:00 AM MDT · 60 min · Led by Kelby and Aubrie. Essential for Lite users.',
            a.Body__c);
        Assert.areEqual('https://arc.example/events?month=2026-09&event=getting-started', a.Link_URL__c);

        r.Presenter__c = null;
        r.Event_Duration_Minutes__c = null;
        r.Description__c = null;
        Assert.areEqual('Tue, Sep 8 at 9:00 AM MDT.', WebinarAnnouncementService.bodyFor(r),
            'Blank parts drop out');

        // Description__c is rich text: the body carries its plain form, and the
        // authored one-sentence summary wins when there is one.
        r.Description__c = '<ul><li>Logging in</li><li>Search</li></ul>';
        Assert.areEqual('Tue, Sep 8 at 9:00 AM MDT. Logging in; Search',
            WebinarAnnouncementService.bodyFor(r));
        r.Summary__c = 'The essentials of Arc.';
        Assert.areEqual('Tue, Sep 8 at 9:00 AM MDT. The essentials of Arc.',
            WebinarAnnouncementService.bodyFor(r));

        // No resolvable site → no link, never an exception.
        WebinarAnnouncementService.surfaceOverride = 'No Such Network';
        Assert.isNull(WebinarAnnouncementService.linkFor(r));
    }

    @IsTest
    static void bodyIsCappedAtTheFieldLength() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        Resource__c r = reload(webinar('long-one', EVENT, true).Id);
        r.Description__c = 'x'.repeat(600);
        String body = WebinarAnnouncementService.bodyFor(r);
        Assert.areEqual(500, body.length());
        Assert.isTrue(body.endsWith('…'));
        Assert.areEqual('ab', WebinarAnnouncementService.truncate('ab', 2));
        Assert.isNull(WebinarAnnouncementService.truncate(null, 2));
    }

    // ---- sweep ---------------------------------------------------------------------

    @IsTest
    static void sweepPushesLinksRetiresAndNeverDuplicates() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        seedArcSite();
        Resource__c r = webinar('w3', EVENT, true);
        // Flagged but not due, and a linked-nothing unflagged one: untouched.
        Resource__c later = webinar('w3-later', EVENT.addDays(5), true);
        Resource__c quiet = webinar('w3-quiet', EVENT, false);

        Test.startTest();
        WebinarAnnouncementService.SweepResult early = WebinarAnnouncementService.sweep(EIGHT_AM.addMinutes(-1));
        Assert.areEqual(0, early.created, 'Nothing due yet');
        Assert.areEqual(0, [SELECT COUNT() FROM Announcement__c]);

        WebinarAnnouncementService.SweepResult due = WebinarAnnouncementService.sweep(EIGHT_AM);
        Test.stopTest();

        Assert.areEqual(1, due.created, due.summary());
        Assert.areEqual(0, due.failed, due.summary());
        r = reload(r.Id);
        Assert.isNotNull(r.Announcement__c, 'The webinar is linked to its announcement');
        Assert.isTrue(r.Announcement__r.Is_Active__c);
        Assert.areEqual('Getting Started with Arc', r.Announcement__r.Name);
        Assert.areEqual('https://arc.example/events?month=2026-09&event=w3', r.Announcement__r.Link_URL__c);
        Assert.isNull(reload(later.Id).Announcement__c, 'Not due → not pushed');
        Assert.isNull(reload(quiet.Id).Announcement__c, 'Not flagged → not pushed');

        // Idempotent: the same instant again changes nothing.
        WebinarAnnouncementService.SweepResult again = WebinarAnnouncementService.sweep(EIGHT_AM);
        Assert.areEqual(0, again.created + again.refreshed + again.retired + again.reactivated, again.summary());
        Assert.areEqual(1, [SELECT COUNT() FROM Announcement__c], 'One announcement per webinar, ever');

        // Ended → retired (record kept, inactive).
        WebinarAnnouncementService.SweepResult over = WebinarAnnouncementService.sweep(EVENT.addMinutes(60));
        Assert.areEqual(1, over.retired, over.summary());
        Assert.isFalse(reload(r.Id).Announcement__r.Is_Active__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Announcement__c]);
    }

    @IsTest
    static void sweepRefreshesTextWhileLiveAndReactivatesTheSameRecord() {
        WebinarAnnouncementService.orgTimeZoneOverride = TZ;
        seedArcSite();
        Resource__c r = webinar('w4', EVENT, true);
        WebinarAnnouncementService.sweep(EIGHT_AM);
        Id announcementId = reload(r.Id).Announcement__c;
        Assert.isNotNull(announcementId);

        // A schedule edit propagates on the next pass.
        r.Name = 'Getting Started with Arc (moved)';
        r.Event_Datetime__c = EVENT.addHours(1);
        update r;
        WebinarAnnouncementService.SweepResult moved = WebinarAnnouncementService.sweep(EIGHT_AM.addMinutes(15));
        Assert.areEqual(1, moved.refreshed, moved.summary());
        Announcement__c a = [SELECT Name, Body__c, Is_Active__c FROM Announcement__c WHERE Id = :announcementId];
        Assert.areEqual('Getting Started with Arc (moved)', a.Name);
        Assert.isTrue(a.Body__c.startsWith('Tue, Sep 8 at 10:00 AM MDT'), a.Body__c);

        // Unflag → retired; re-flag → the SAME record comes back, no duplicate.
        r.Announce_On_Arc__c = false;
        update r;
        WebinarAnnouncementService.SweepResult unflag = WebinarAnnouncementService.sweep(EIGHT_AM.addMinutes(30));
        Assert.areEqual(1, unflag.retired, unflag.summary());
        Assert.isFalse([SELECT Is_Active__c FROM Announcement__c WHERE Id = :announcementId].Is_Active__c);

        r.Announce_On_Arc__c = true;
        update r;
        WebinarAnnouncementService.SweepResult reflag = WebinarAnnouncementService.sweep(EIGHT_AM.addMinutes(45));
        Assert.areEqual(1, reflag.reactivated, reflag.summary());
        Assert.isTrue([SELECT Is_Active__c FROM Announcement__c WHERE Id = :announcementId].Is_Active__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Announcement__c]);

        // A type switch on a linked row retires it too (the query is not type-gated).
        r.Resource_Type__c = 'PDF';
        update r;
        WebinarAnnouncementService.SweepResult switched = WebinarAnnouncementService.sweep(EIGHT_AM.addMinutes(50));
        Assert.areEqual(1, switched.retired, switched.summary());
    }

    @IsTest
    static void orgTimeZoneComesFromTheOrganization() {
        String expected = [SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey;
        Assert.areEqual(expected, WebinarAnnouncementService.orgTimeZoneId());
        Assert.areEqual(expected, WebinarAnnouncementService.orgTimeZoneId(), 'Cached');
    }
}