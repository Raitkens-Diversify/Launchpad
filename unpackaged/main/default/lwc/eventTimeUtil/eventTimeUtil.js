import LOCALE from '@salesforce/i18n/locale';

/**
 * eventTimeUtil — the pure logic behind the event detail page's details
 * card. Apex-free and DOM-free so every rule here is unit-tested against a
 * fixed clock and fixed zones.
 *
 *   detectZone()                  the viewer's BROWSER zone (Intl), the one the
 *                                 detail page shows first. Deliberately not
 *                                 @salesforce/i18n/timeZone (the user's
 *                                 Salesforce zone, which c/dsDateBlock uses for
 *                                 tiles and lists): someone travelling wants the
 *                                 clock on the wall, and the Salesforce zone is
 *                                 already covered when it equals the browser's.
 *   zoneTimes(iso, viewerZone)    [{zone, time, abbr, label, primary}] — the
 *                                 viewer's zone first, then EXTRA_ZONES, with
 *                                 duplicates (same wall-clock + abbreviation)
 *                                 collapsed, so a viewer in Denver sees
 *                                 "9:00 AM MDT · 11:00 AM EDT", not MDT twice.
 *   eventState(item, now)         upcoming | soon | live | recorded | ended,
 *                                 from datetime + duration + recording — never a
 *                                 stored status (WebinarLifecycle's coarser
 *                                 Upcoming/Past/Recorded stays for lists).
 *   splitPresenters(text)         "Kelby and Aubrie" → [{name, initials}] — the
 *                                 interim reading of the free-text Presenter__c
 *                                 (flagged in eventDetail; a related list is
 *                                 the upgrade path).
 *
 * Mirror: DEFAULT_DURATION_MINUTES ↔ WebinarAnnouncementService.DEFAULT_DURATION_MINUTES
 * — change together.
 */

/** Always shown after the viewer's zone: Mountain (the org's home) and Eastern. */
export const EXTRA_ZONES = Object.freeze(['America/Denver', 'America/New_York']);
export const DEFAULT_DURATION_MINUTES = 60;
/** "Join now" appears this many minutes before the start. */
export const SOON_WINDOW_MINUTES = 15;

export const STATE_UPCOMING = 'upcoming';
export const STATE_SOON = 'soon';
export const STATE_LIVE = 'live';
export const STATE_RECORDED = 'recorded';
export const STATE_ENDED = 'ended';

const MS_PER_MINUTE = 60000;

function toDate(value) {
    if (!value) {
        return null;
    }
    const d = value instanceof Date ? value : new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
}

/** The browser's IANA zone, or null when the runtime cannot say. */
export function detectZone() {
    try {
        const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        return zone || null;
    } catch (e) {
        return null;
    }
}

/** True when Intl accepts the zone name (a bad @api override must not throw in render). */
export function isValidZone(zone) {
    if (!zone) {
        return false;
    }
    try {
        new Intl.DateTimeFormat('en-US', { timeZone: zone });
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * {time: "9:00 AM", abbr: "MDT", label: "9:00 AM MDT"} for an instant in a
 * zone, in the user's locale. The abbreviation comes from Intl's short zone
 * name — "MDT"/"EDT"/"HST" for US zones, "GMT+1"-style elsewhere. Null when
 * the instant or the zone is unusable.
 */
export function formatInZone(iso, zone) {
    const d = toDate(iso);
    if (!d || !isValidZone(zone)) {
        return null;
    }
    const parts = new Intl.DateTimeFormat(LOCALE, {
        timeZone: zone, hour: 'numeric', minute: '2-digit', timeZoneName: 'short'
    }).formatToParts(d);
    const abbr = (parts.find((p) => p.type === 'timeZoneName') || {}).value || '';
    // ICU separates "9:00" and "AM" with U+202F (narrow no-break space) in
    // recent runtimes; a plain space keeps the label copy-and-paste friendly.
    const time = parts
        .filter((p) => p.type !== 'timeZoneName')
        .map((p) => p.value)
        .join('')
        .replace(/[\u202F\u00A0]/g, ' ')
        .replace(/[,\s]+$/, '');
    return { time, abbr, label: abbr ? `${time} ${abbr}` : time };
}

/** Full date in a zone: "Tuesday, September 8, 2026". */
export function formatDateInZone(iso, zone) {
    const d = toDate(iso);
    if (!d || !isValidZone(zone)) {
        return null;
    }
    return new Intl.DateTimeFormat(LOCALE, {
        timeZone: zone, weekday: 'long', month: 'long', day: 'numeric', year: 'numeric'
    }).format(d);
}

/** Short date in a zone: "Sep 8, 2026" (the "Recorded on" line). */
export function formatShortDateInZone(iso, zone) {
    const d = toDate(iso);
    if (!d || !isValidZone(zone)) {
        return null;
    }
    return new Intl.DateTimeFormat(LOCALE, {
        timeZone: zone, month: 'short', day: 'numeric', year: 'numeric'
    }).format(d);
}

/**
 * The time in the viewer's zone, then each EXTRA_ZONE that adds information.
 * Two zones are the same entry when they render the same wall-clock AND
 * abbreviation for this instant (Denver + Phoenix in winter, say). The
 * viewer's entry is `primary`. Falls back to the extras alone when the
 * viewer's zone is unknown.
 */
export function zoneTimes(iso, viewerZone, extraZones = EXTRA_ZONES) {
    const out = [];
    const seen = new Set();
    const zones = [viewerZone, ...extraZones].filter(Boolean);
    zones.forEach((zone, index) => {
        const f = formatInZone(iso, zone);
        if (!f || seen.has(f.label)) {
            return;
        }
        seen.add(f.label);
        out.push({ zone, ...f, primary: index === 0 && zone === viewerZone });
    });
    if (out.length && !out[0].primary) {
        out[0] = { ...out[0], primary: true };
    }
    return out;
}

/** {start, end} for an event; end = start + duration (default 60). Null without a start. */
export function eventWindow(item) {
    const start = toDate(item && item.eventDatetime);
    if (!start) {
        return null;
    }
    const minutes = item.durationMinutes > 0 ? Number(item.durationMinutes) : DEFAULT_DURATION_MINUTES;
    return { start, end: new Date(start.getTime() + minutes * MS_PER_MINUTE) };
}

/** A recording is an embed URL or an attached file — the WebinarLifecycle rule. */
export function hasRecording(item) {
    return !!(item && (item.videoEmbedUrl || (item.file && item.file.downloadUrl)));
}

/**
 * The detail page's state at `now` (a Date):
 *   upcoming  — more than SOON_WINDOW_MINUTES before the start
 *   soon      — within the window before the start (Join now)
 *   live      — start ≤ now < end (Join now + live indicator)
 *   recorded  — the event has started and a recording exists (Watch)
 *   ended     — over, nothing to watch yet
 * Null without a start datetime. A recording present while the session is
 * still live does not shortcut to "recorded" — the join link is the action.
 */
export function eventState(item, now = new Date()) {
    const win = eventWindow(item);
    if (!win) {
        return null;
    }
    const t = now.getTime();
    if (t < win.start.getTime() - SOON_WINDOW_MINUTES * MS_PER_MINUTE) {
        return STATE_UPCOMING;
    }
    if (t < win.start.getTime()) {
        return STATE_SOON;
    }
    if (t < win.end.getTime()) {
        return STATE_LIVE;
    }
    return hasRecording(item) ? STATE_RECORDED : STATE_ENDED;
}

/** Whole milliseconds until the next state change from `now` (for a refresh timer), or null. */
export function msUntilNextState(item, now = new Date()) {
    const win = eventWindow(item);
    if (!win) {
        return null;
    }
    const t = now.getTime();
    const edges = [
        win.start.getTime() - SOON_WINDOW_MINUTES * MS_PER_MINUTE,
        win.start.getTime(),
        win.end.getTime()
    ].filter((edge) => edge > t);
    return edges.length ? edges[0] - t : null;
}

/** "Kelby Ann" → "KA"; "Kelby" → "K"; a title after a comma is ignored ("Meg, CFP" → "M"). */
export function initialsOf(name) {
    const words = String(name || '')
        .split(',')[0]
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (!words.length) {
        return '';
    }
    const first = words[0][0];
    const last = words.length > 1 ? words[words.length - 1][0] : '';
    return (first + last).toUpperCase();
}

/**
 * Free-text Presenter__c → people. Splits on commas, ampersands, slashes and
 * the word "and"; drops a leading "Led by"; ignores blanks. One name → one
 * chip; blank → []. Interim until presenters are structured data.
 */
export function splitPresenters(text) {
    if (!text) {
        return [];
    }
    return String(text)
        .replace(/^\s*(led|presented|hosted)\s+by\s+/i, '')
        .split(/\s*(?:,|&|\/|\band\b|\+)\s*/i)
        .map((s) => s.trim())
        .filter(Boolean)
        .map((name) => ({ name, initials: initialsOf(name) }));
}