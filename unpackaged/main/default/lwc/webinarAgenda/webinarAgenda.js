import { LightningElement, wire } from 'lwc';
import getWebinars from '@salesforce/apex/ResourceCenterService.getWebinars';
import {
    WEBINAR_STATUS_UPCOMING,
    WEBINAR_STATUS_PAST,
    WEBINAR_STATUS_RECORDED,
    formatDurationMinutes
} from 'c/rcConstants';
import { formatTime } from 'c/dsDateBlock';

/**
 * webinarAgenda — the landing page's side panel listing upcoming and recent
 * webinars. Container: wires ResourceCenterService.getWebinars, maps each
 * WebinarItem onto the c-ds-agenda-row contract, and owns the CTA routing.
 * Hosted by unifiedLanding in its left column.
 *
 * Per status (server-derived by WebinarLifecycle — never re-derived here):
 *   Upcoming → "Sign up": Registration_URL__c in a new tab (rel=noopener)
 *   Recorded → "Watch": emits `resourceselect { slug }`; the host routes to
 *              the resource detail page, which plays the recording
 *   Past     → no CTA (never a dead button) — "Recording coming soon"
 *
 * Renders nothing when both sections are empty — config off, no access, no
 * webinars, or a wire error all look the same — and reports that via
 * `agendachange { hasItems }` so the landing can collapse to its single-column
 * layout. Both events are plain (not composed): the host listens on the
 * element.
 */
export default class WebinarAgenda extends LightningElement {
    upcoming = [];
    recent = [];
    loaded = false;

    @wire(getWebinars)
    wiredAgenda({ data, error }) {
        if (data) {
            this.upcoming = data.upcoming || [];
            this.recent = data.recent || [];
        } else if (error) {
            // Graceful: a side panel is never worth an error.
            this.upcoming = [];
            this.recent = [];
        } else {
            return;
        }
        this.loaded = true;
        this.dispatchEvent(new CustomEvent('agendachange', { detail: { hasItems: this.hasItems } }));
    }

    get hasItems() {
        return this.upcoming.length > 0 || this.recent.length > 0;
    }
    get showPanel() {
        return this.loaded && this.hasItems;
    }
    get hasUpcoming() {
        return this.upcoming.length > 0;
    }
    get hasRecent() {
        return this.recent.length > 0;
    }
    get upcomingRows() {
        return this.upcoming.map(toRow);
    }
    get recentRows() {
        return this.recent.map(toRow);
    }

    /** "Watch" rows: route to the detail page by slug. */
    handleRowSelect(event) {
        const id = event.detail.id;
        const item = this.recent.find((w) => w.id === id) || this.upcoming.find((w) => w.id === id);
        if (!item) {
            return;
        }
        this.dispatchEvent(new CustomEvent('resourceselect', { detail: { slug: item.slug } }));
    }
}

/** WebinarItem DTO → c-ds-agenda-row item. */
function toRow(w) {
    const meta = [formatTime(w.eventDatetime), w.presenter, formatDurationMinutes(w.durationMinutes)]
        .filter(Boolean)
        .join(' · ');
    const row = { id: w.id, title: w.name, datetime: w.eventDatetime, meta: meta || undefined };
    if (w.status === WEBINAR_STATUS_UPCOMING && w.registrationUrl) {
        row.cta = { label: 'Sign up', href: w.registrationUrl };
    } else if (w.status === WEBINAR_STATUS_RECORDED) {
        row.cta = { label: 'Watch' };
    } else if (w.status === WEBINAR_STATUS_PAST) {
        row.note = 'Recording coming soon';
    }
    return row;
}