/**
 * WebinarAnnouncementService — the ONE place the "webinar → Arc announcement"
 * rules live.
 *
 * Arc's home dashboard shows every Announcement__c with Is_Active__c = true
 * (arcAnnouncements / ArcAnnouncementController, Arc-owned, not in this
 * repo). The object carries no dates, so "announce at a time" and "come down
 * afterwards" are done here by a scheduled sweep (WebinarAnnouncementScheduler,
 * every 15 minutes) over Resource__c webinars:
 *
 *   announceable  Resource_Type__c = Webinar, Is_Active__c, Announce_On_Arc__c,
 *                 effectiveAnnounceAt <= now, and the event has not ENDED
 *                 (Event_Datetime__c + Event_Duration_Minutes__c, 60 when blank)
 *   push          announceable + no Announcement__c yet → insert one (title,
 *                 body, link to the event on the Arc Events calendar) and link it
 *   sync          linked → Is_Active__c follows announceable; while live the
 *                 text/link are refreshed so schedule edits propagate
 *
 * Default announce time: 8:00 AM in the ORG time zone on the event's local
 * date; when the event starts at or before that (an early session) the same
 * time the day before. Never the running user's zone — the scheduler runs as
 * whoever scheduled it.
 *
 * Link: {Arc site}/events?month=YYYY-MM&event=<slug> — eventsPage opens the
 * calendar on that month with the event's popover already open. The surface
 * is the Arc network by name (ARC_SURFACE): the announcement object exists
 * only for Arc, so a constant, not a config row.
 *
 * `now` is always passed in (the WebinarLifecycle discipline) so tests pick
 * boundaries explicitly and one instant binds the whole pass.
 */
public with sharing class WebinarAnnouncementService {

    /** Network name of the site whose Events page the announcement links to. */
    public static final String ARC_SURFACE = 'Arc';
    public static final Integer DEFAULT_ANNOUNCE_HOUR = 8;
    public static final Integer DEFAULT_DURATION_MINUTES = 60;
    /** Announcement__c.Body__c is LongTextArea(500); Name is Text(80). */
    public static final Integer BODY_MAX = 500;
    public static final Integer NAME_MAX = 80;

    public static final String STATUS_SCHEDULED = 'Scheduled'; // announce time still ahead
    public static final String STATUS_PENDING = 'Pending';     // due, the sweep has not pushed yet
    public static final String STATUS_LIVE = 'Live';           // pushed and active
    public static final String STATUS_ENDED = 'Ended';         // the event is over

    /** Test seams. */
    @TestVisible private static String surfaceOverride;
    @TestVisible private static String orgTimeZoneOverride;
    private static String orgTz;

    public class SweepResult {
        public Integer created = 0;
        public Integer refreshed = 0;
        public Integer retired = 0;
        public Integer reactivated = 0;
        public Integer failed = 0;
        public String summary() {
            return 'created ' + created + ', refreshed ' + refreshed + ', retired ' + retired
                + ', reactivated ' + reactivated + ', failed ' + failed;
        }
    }

    // ---- Rules --------------------------------------------------------------------

    /** The org's time zone id (Organization.TimeZoneSidKey), cached per transaction. */
    public static String orgTimeZoneId() {
        if (orgTimeZoneOverride != null) {
            return orgTimeZoneOverride;
        }
        if (orgTz == null) {
            orgTz = [SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey;
        }
        return orgTz;
    }

    /**
     * When the announcement goes live: the explicit Announce_At__c, else
     * 8:00 AM org time on the event's local date, else (event at or before
     * 8:00 AM) 8:00 AM the day before. Null only when there is no event time.
     */
    public static Datetime effectiveAnnounceAt(Datetime eventAt, Datetime announceAt) {
        if (announceAt != null) {
            return announceAt;
        }
        if (eventAt == null) {
            return null;
        }
        Datetime candidate = localWallClock(eventAt, DEFAULT_ANNOUNCE_HOUR);
        if (candidate >= eventAt) {
            candidate = localWallClock(eventAt.addDays(-1), DEFAULT_ANNOUNCE_HOUR);
        }
        return candidate;
    }

    /** `hour`:00 in the org zone on the org-zone calendar day of `instant`. */
    @TestVisible private static Datetime localWallClock(Datetime instant, Integer hour) {
        TimeZone tz = TimeZone.getTimeZone(orgTimeZoneId());
        Datetime shifted = instant.addSeconds(tz.getOffset(instant) / 1000);
        Datetime wall = Datetime.newInstanceGmt(shifted.dateGmt(), Time.newInstance(hour, 0, 0, 0));
        // `wall` reads the local clock as GMT; subtract the zone's offset at
        // that moment to get the real instant (8 AM is hours away from any
        // DST switch, so the offset lookup on `wall` is safe).
        return wall.addSeconds(-tz.getOffset(wall) / 1000);
    }

    /** Event end = start + duration (60 min when blank); ended once end <= now. */
    public static Boolean hasEnded(Resource__c r, Datetime now) {
        if (r == null || r.Event_Datetime__c == null) {
            return false;
        }
        Integer minutes = r.Event_Duration_Minutes__c == null
            ? DEFAULT_DURATION_MINUTES : r.Event_Duration_Minutes__c.intValue();
        return r.Event_Datetime__c.addMinutes(minutes) <= now;
    }

    /** Should this webinar's announcement be live at `now`? */
    public static Boolean isAnnounceable(Resource__c r, Datetime now) {
        if (r == null || !WebinarLifecycle.isWebinar(r.Resource_Type__c)) {
            return false;
        }
        if (r.Is_Active__c != true || r.Announce_On_Arc__c != true || r.Event_Datetime__c == null) {
            return false;
        }
        Datetime at = effectiveAnnounceAt(r.Event_Datetime__c, r.Announce_At__c);
        return at != null && at <= now && !hasEnded(r, now);
    }

    /**
     * Editor status line: null when the webinar is not flagged (or not a
     * webinar), else Ended / Live / Pending / Scheduled. `linkedActive` is
     * Announcement__r.Is_Active__c (null when nothing is linked yet).
     */
    public static String statusFor(Resource__c r, Boolean linkedActive, Datetime now) {
        if (r == null || !WebinarLifecycle.isWebinar(r.Resource_Type__c)
            || r.Announce_On_Arc__c != true || r.Event_Datetime__c == null) {
            return null;
        }
        if (hasEnded(r, now)) {
            return STATUS_ENDED;
        }
        Datetime at = effectiveAnnounceAt(r.Event_Datetime__c, r.Announce_At__c);
        if (at != null && at <= now) {
            return linkedActive == true ? STATUS_LIVE : STATUS_PENDING;
        }
        return STATUS_SCHEDULED;
    }

    // ---- Announcement content -------------------------------------------------------

    /** A fresh Announcement__c for the webinar (active). */
    public static Announcement__c build(Resource__c r) {
        Announcement__c a = new Announcement__c(Is_Active__c = true);
        applyContent(r, a);
        return a;
    }

    /** Writes the webinar's current title/body/link onto `a`; true when any changed. */
    public static Boolean applyContent(Resource__c r, Announcement__c a) {
        String name = truncate(r.Name, NAME_MAX);
        String body = bodyFor(r);
        String link = linkFor(r);
        Boolean changed = a.Name != name || a.Body__c != body || a.Link_URL__c != link;
        a.Name = name;
        a.Body__c = body;
        a.Link_URL__c = link;
        return changed;
    }

    /** "Tue, Sep 8 at 9:00 AM MDT · 60 min · Led by Kelby and Aubrie. <description>", ≤ 500 chars. */
    public static String bodyFor(Resource__c r) {
        List<String> parts = new List<String>();
        if (r.Event_Datetime__c != null) {
            parts.add(r.Event_Datetime__c.format('EEE, MMM d \'at\' h:mm a z', orgTimeZoneId()));
        }
        if (r.Event_Duration_Minutes__c != null) {
            parts.add(r.Event_Duration_Minutes__c.intValue() + ' min');
        }
        if (String.isNotBlank(r.Presenter__c)) {
            parts.add('Led by ' + r.Presenter__c.trim());
        }
        String body = parts.isEmpty() ? '' : String.join(parts, ' · ') + '.';
        if (String.isNotBlank(r.Description__c)) {
            body = (String.isBlank(body) ? '' : body + ' ') + r.Description__c.trim();
        }
        return truncate(body, BODY_MAX);
    }

    /** {Arc events page}?month=YYYY-MM&event=<slug>, or null when the site can't be resolved. */
    public static String linkFor(Resource__c r) {
        String base = ResourceCenterService.eventsUrlFor(
            surfaceOverride != null ? surfaceOverride : ARC_SURFACE);
        if (base == null) {
            return null;
        }
        List<String> query = new List<String>();
        if (r.Event_Datetime__c != null) {
            query.add('month=' + r.Event_Datetime__c.format('yyyy-MM', orgTimeZoneId()));
        }
        if (String.isNotBlank(r.Slug__c)) {
            query.add('event=' + EncodingUtil.urlEncode(r.Slug__c.trim(), 'UTF-8'));
        }
        return query.isEmpty() ? base : base + '?' + String.join(query, '&');
    }

    @TestVisible private static String truncate(String s, Integer max) {
        if (s == null || s.length() <= max) {
            return s;
        }
        return s.substring(0, max - 1) + '…';
    }

    // ---- The sweep ------------------------------------------------------------------

    /**
     * One pass at `now`: push announcements that became due, and keep every
     * linked announcement's active flag (and, while live, its text) in step
     * with its webinar. Partial-success DML: one bad row never blocks the
     * rest; failures are logged and counted, never thrown.
     */
    public static SweepResult sweep(Datetime now) {
        SweepResult out = new SweepResult();
        List<Resource__c> rows = [
            SELECT Id, Name, Slug__c, Description__c, Resource_Type__c, Is_Active__c,
                   Event_Datetime__c, Event_Duration_Minutes__c, Presenter__c,
                   Announce_On_Arc__c, Announce_At__c, Announcement__c,
                   Announcement__r.Name, Announcement__r.Body__c,
                   Announcement__r.Link_URL__c, Announcement__r.Is_Active__c
            FROM Resource__c
            WHERE Announce_On_Arc__c = true OR Announcement__c != null
        ];

        List<Announcement__c> toInsert = new List<Announcement__c>();
        List<Resource__c> owners = new List<Resource__c>();
        List<Announcement__c> toUpdate = new List<Announcement__c>();

        for (Resource__c r : rows) {
            Boolean wantLive = isAnnounceable(r, now);
            if (r.Announcement__c == null) {
                if (wantLive) {
                    toInsert.add(build(r));
                    owners.add(r);
                }
                continue;
            }
            Announcement__c current = new Announcement__c(
                Id = r.Announcement__c,
                Name = r.Announcement__r.Name,
                Body__c = r.Announcement__r.Body__c,
                Link_URL__c = r.Announcement__r.Link_URL__c,
                Is_Active__c = r.Announcement__r.Is_Active__c
            );
            Boolean changed = wantLive ? applyContent(r, current) : false;
            if (current.Is_Active__c != wantLive) {
                current.Is_Active__c = wantLive;
                changed = true;
                if (wantLive) {
                    out.reactivated++;
                } else {
                    out.retired++;
                }
            } else if (changed) {
                out.refreshed++;
            }
            if (changed) {
                toUpdate.add(current);
            }
        }

        if (!toInsert.isEmpty()) {
            List<Resource__c> links = new List<Resource__c>();
            List<Database.SaveResult> inserted = Database.insert(toInsert, false);
            for (Integer i = 0; i < inserted.size(); i++) {
                if (inserted[i].isSuccess()) {
                    links.add(new Resource__c(Id = owners[i].Id, Announcement__c = inserted[i].getId()));
                } else {
                    out.failed++;
                    logFailure('insert announcement for ' + owners[i].Slug__c, inserted[i].getErrors());
                }
            }
            List<Database.SaveResult> linked = Database.update(links, false);
            for (Integer i = 0; i < linked.size(); i++) {
                if (linked[i].isSuccess()) {
                    out.created++;
                } else {
                    out.failed++;
                    logFailure('link announcement to ' + links[i].Id, linked[i].getErrors());
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> updated = Database.update(toUpdate, false);
            for (Integer i = 0; i < updated.size(); i++) {
                if (!updated[i].isSuccess()) {
                    out.failed++;
                    logFailure('update announcement ' + toUpdate[i].Id, updated[i].getErrors());
                }
            }
        }

        System.debug(LoggingLevel.INFO, 'WebinarAnnouncementService.sweep @ ' + now + ': ' + out.summary());
        return out;
    }

    private static void logFailure(String what, List<Database.Error> errors) {
        String msg = errors == null || errors.isEmpty() ? 'unknown error' : errors[0].getMessage();
        System.debug(LoggingLevel.ERROR, 'WebinarAnnouncementService: could not ' + what + ' — ' + msg);
    }
}