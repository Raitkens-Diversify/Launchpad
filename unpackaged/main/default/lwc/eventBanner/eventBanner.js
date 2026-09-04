import { LightningElement, api } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import { formatTime, formatShortDate } from 'c/dsDateBlock';
import { formatDurationMinutes } from 'c/rcConstants';

/* localStorage guarded like uatTesterApp/bookOfBusinessUtils: typeof checks +
 * try/catch — private mode or storage quirks degrade to "dismissal doesn't
 * persist", never an error. Key is per-user so shared machines don't leak
 * scope. The stored value is the dismissed event's record Id: a *different*
 * next event re-shows the banner without any versioning bookkeeping. */
const DISMISS_KEY_PREFIX = 'dismissedEventBanner.';

function storageKey() {
    return DISMISS_KEY_PREFIX + USER_ID;
}

function readDismissedId() {
    if (typeof window === 'undefined' || !window.localStorage) {
        return null;
    }
    try {
        return window.localStorage.getItem(storageKey());
    } catch (e) {
        return null;
    }
}

function writeDismissedId(eventId) {
    if (typeof window === 'undefined' || !window.localStorage) {
        return;
    }
    try {
        window.localStorage.setItem(storageKey(), eventId);
    } catch (e) {
        // Not persistable — the dismissal still holds for this render.
    }
}

/**
 * eventBanner — slim single-line strip below the landing hero announcing the
 * next upcoming event: date chip, title, time + duration, Sign up, dismiss.
 * Presentational and Apex-free: the host passes the next upcoming WebinarItem
 * (from ResourceCenterService.getEvents) via @api event; null renders nothing,
 * so an eventless org leaves no layout gap. Hosted by unifiedLanding.
 */
export default class EventBanner extends LightningElement {
    /** The next upcoming event (a ResourceCenterService.WebinarItem) or null. */
    @api event;

    _dismissed = false;

    get visible() {
        return Boolean(
            this.event && this.event.id
            && !this._dismissed
            && readDismissedId() !== this.event.id
        );
    }

    get dateChip() {
        return formatShortDate(this.event && this.event.eventDatetime);
    }

    /** "10:00 AM · 45 min" — either half drops out when unknown. */
    get meta() {
        return [
            formatTime(this.event && this.event.eventDatetime),
            formatDurationMinutes(this.event && this.event.durationMinutes)
        ].filter(Boolean).join(' · ');
    }

    get hasSignup() {
        return Boolean(this.event && this.event.registrationUrl);
    }

    handleDismiss() {
        writeDismissedId(this.event.id);
        this._dismissed = true;
    }
}