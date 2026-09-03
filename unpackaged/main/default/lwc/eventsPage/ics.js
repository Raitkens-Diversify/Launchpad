/**
 * Minimal iCalendar (RFC 5545) writer for the events page's "Add to calendar"
 * download. Bundle-internal on purpose: one consumer today — promote to a
 * c/icsUtil module only when a second appears (the csvUtil rule).
 *
 * The data model has no end-datetime; DTEND is start + durationMinutes, with a
 * 60-minute default when the duration is blank.
 */

const DEFAULT_DURATION_MINUTES = 60;
const MS_PER_MINUTE = 60000;
const LINE_OCTETS = 75;

/** TEXT value escaping per RFC 5545 §3.3.11 (backslash first, CR dropped). */
export function escapeIcsText(value) {
    return String(value == null ? '' : value)
        .replace(/\\/g, '\\\\')
        .replace(/\r/g, '')
        .replace(/\n/g, '\\n')
        .replace(/;/g, '\\;')
        .replace(/,/g, '\\,');
}

/** UTF-8 byte length, computed from code points (TextEncoder is absent in
    some sandboxes — jsdom included). */
function octets(s) {
    let n = 0;
    for (const ch of s) {
        const cp = ch.codePointAt(0);
        n += cp <= 0x7f ? 1 : cp <= 0x7ff ? 2 : cp <= 0xffff ? 3 : 4;
    }
    return n;
}

/**
 * Content-line folding per RFC 5545 §3.1: lines longer than 75 octets break
 * into CRLF + single-space continuations (the leading space counts toward the
 * next line's 75). Splits on characters, never mid-code-point.
 */
export function foldIcsLine(line) {
    if (octets(line) <= LINE_OCTETS) {
        return line;
    }
    const out = [];
    let current = '';
    for (const ch of line) {
        if (octets(current + ch) > LINE_OCTETS) {
            out.push(current);
            current = ' ';
        }
        current += ch;
    }
    out.push(current);
    return out.join('\r\n');
}

/** ISO-8601 (or Date) → iCalendar UTC form "20260901T140000Z"; null when unparseable. */
export function toIcsUtc(value) {
    const d = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(d.getTime())) {
        return null;
    }
    return d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

/**
 * One event (a ResourceCenterService.WebinarItem) → a complete VCALENDAR
 * string, CRLF-terminated. Returns null without a parseable start datetime.
 */
export function buildIcsEvent(item, options = {}) {
    // new Date(null) is the epoch, not an error — reject blanks explicitly.
    if (!item || !item.eventDatetime) {
        return null;
    }
    const start = new Date(item.eventDatetime);
    if (Number.isNaN(start.getTime())) {
        return null;
    }
    const minutes = item.durationMinutes > 0
        ? item.durationMinutes
        : (options.defaultDurationMinutes || DEFAULT_DURATION_MINUTES);
    const end = new Date(start.getTime() + minutes * MS_PER_MINUTE);

    const description = [
        item.description,
        item.registrationUrl ? `Sign up: ${item.registrationUrl}` : null
    ].filter(Boolean).join('\n\n');

    const lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Diversify//Help Center//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        `UID:${item.id}@diversify-help-center`,
        `DTSTAMP:${toIcsUtc(new Date())}`,
        `DTSTART:${toIcsUtc(start)}`,
        `DTEND:${toIcsUtc(end)}`,
        `SUMMARY:${escapeIcsText(item.name)}`
    ];
    if (description) {
        lines.push(`DESCRIPTION:${escapeIcsText(description)}`);
    }
    if (item.registrationUrl) {
        lines.push(`URL:${escapeIcsText(item.registrationUrl)}`);
    }
    lines.push('END:VEVENT', 'END:VCALENDAR');

    return lines.map(foldIcsLine).join('\r\n') + '\r\n';
}