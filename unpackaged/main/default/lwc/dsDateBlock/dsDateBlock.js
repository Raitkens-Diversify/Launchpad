import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';

/**
 * dsDateBlock — calendar-tile date: weekday over the day number over the short
 * month ("Tue / 1 / Sep") for agenda rows and event headers. Presentational and
 * Apex-free. Formats in the running user's locale and timezone via Intl
 * (@salesforce/i18n) — never a hardcoded zone. Consumed by dsAgendaRow and
 * resourceDetail.
 *
 * @api value: ISO-8601 string (what an Apex Datetime serializes to). Named
 *   `value`, not `datetime`: LWC maps the global datetime attribute onto the
 *   DOM dateTime property, so an @api datetime never receives the binding.
 * @api variant: 'md' | 'sm'
 *
 * Also exports the shared formatters so hosts render times/dates the same way:
 *   formatTime(iso)      → "10:00 AM"
 *   formatDateTime(iso)  → "Tue, Sep 1, 2026, 10:00 AM"
 *   formatShortDate(iso) → "Tue, Sep 1" (eventBanner date chip; its CSS uppercases)
 *   formatMonthYear(iso) → "September 2026" (eventsPage month headings)
 * and two civil-date helpers for dsCalendar (cell placement + labels):
 *   localDateKey(iso)         → "2026-09-15" — the calendar DAY the instant
 *                               falls on in the user's Salesforce timezone
 *   formatDateKey(key, opts)  → a zone-less "YYYY-MM-DD" / "YYYY-MM" key
 *                               formatted in the user's locale
 */
function toDate(iso) {
    if (!iso) {
        return null;
    }
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? null : d;
}

function fmt(d, options) {
    return new Intl.DateTimeFormat(LOCALE, { timeZone: TIME_ZONE, ...options }).format(d);
}

export function formatTime(iso) {
    const d = toDate(iso);
    return d ? fmt(d, { hour: 'numeric', minute: '2-digit' }) : null;
}

export function formatDateTime(iso) {
    const d = toDate(iso);
    return d
        ? fmt(d, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric',
                   hour: 'numeric', minute: '2-digit' })
        : null;
}

export function formatShortDate(iso) {
    const d = toDate(iso);
    return d ? fmt(d, { weekday: 'short', month: 'short', day: 'numeric' }) : null;
}

export function formatMonthYear(iso) {
    const d = toDate(iso);
    return d ? fmt(d, { month: 'long', year: 'numeric' }) : null;
}

/**
 * The local calendar day an instant falls on, as "YYYY-MM-DD", resolved in
 * the user's Salesforce timezone (not the browser's). This is the ONLY correct
 * way to bucket events into calendar cells: an event at 11:30 PM local is
 * still "today" here even though its UTC date string already says tomorrow.
 * Locale is pinned to en-US so the digits are always ASCII regardless of the
 * running user's LOCALE — this is a key, not display text.
 */
export function localDateKey(value) {
    const d = toDate(value);
    if (!d) {
        return null;
    }
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit'
    }).formatToParts(d);
    const get = (type) => (parts.find((p) => p.type === type) || {}).value;
    return `${get('year')}-${get('month')}-${get('day')}`;
}

const KEY_RE = /^(\d{4})-(0[1-9]|1[0-2])(?:-(0[1-9]|[12]\d|3[01]))?$/;

/**
 * Format a civil date key ("YYYY-MM-DD", or "YYYY-MM" for month-level labels)
 * in the user's locale. A key is zone-less, so it is materialised at UTC
 * midnight and formatted with timeZone 'UTC' — formatting it through
 * TIME_ZONE would shift it a day whenever the browser and Salesforce zones
 * differ (a UTC browser + a Los Angeles user would label Sunday the 6th as
 * Saturday the 5th). dsCalendar never builds `new Date(y, m, d)` for the same
 * reason. Null for an unparseable key.
 */
export function formatDateKey(key, options) {
    const m = KEY_RE.exec(key || '');
    if (!m) {
        return null;
    }
    const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3] || 1)));
    if (Number.isNaN(d.getTime())) {
        return null;
    }
    return new Intl.DateTimeFormat(LOCALE, { timeZone: 'UTC', ...options }).format(d);
}

export default class DsDateBlock extends LightningElement {
    @api value;
    @api variant = 'md';

    get parts() {
        const d = toDate(this.value);
        if (!d) {
            return null;
        }
        return {
            weekday: fmt(d, { weekday: 'short' }),
            day: fmt(d, { day: 'numeric' }),
            month: fmt(d, { month: 'short' }),
            full: fmt(d, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })
        };
    }

    get blockClass() {
        return this.variant === 'sm' ? 'ds-date ds-date--sm' : 'ds-date';
    }
}