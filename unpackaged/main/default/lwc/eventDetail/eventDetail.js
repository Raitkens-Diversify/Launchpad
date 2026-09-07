import { LightningElement, api, wire } from 'lwc';
import getEvents from '@salesforce/apex/ResourceCenterService.getEvents';
import {
    detectZone,
    isValidZone,
    zoneTimes,
    formatInZone,
    formatDateInZone,
    formatShortDateInZone,
    eventState,
    msUntilNextState,
    splitPresenters,
    STATE_UPCOMING,
    STATE_SOON,
    STATE_LIVE,
    STATE_RECORDED,
    STATE_ENDED
} from 'c/eventTimeUtil';
import { formatDurationMinutes } from 'c/rcConstants';
import { fileHref } from 'c/contextNav';
import { sanitizeHtml } from 'c/richTextUtil';

/**
 * eventDetail — the event (webinar) detail body. resourceDetail renders it
 * under its breadcrumb whenever the resource is a Webinar and keeps the
 * Related Articles rail below; everything else on the page is here so a
 * reader can answer "what is it, when is it for me, who's running it, how
 * do I join" without reading a paragraph.
 *
 * Layout: eyebrow (type + audience chips) → serif title → one-sentence
 * summary; then a two-column body — the content column (recording player
 * when there is one, "What we'll cover" rich-text agenda, presenter chips,
 * "Who this is for") beside a sticky details card (date tile + full date,
 * the time in the VIEWER'S browser zone with Mountain and Eastern in muted
 * text, duration, ONE primary button) — then three upcoming sibling events.
 * On phones the card collapses into a compact bar above the content (CSS
 * only). No calendar export: "Add to calendar" was removed at the user's
 * request (2026-09-06, again 2026-09-07).
 *
 * State is derived here from datetime + duration + recording against a clock
 * (c/eventTimeUtil.eventState — never a stored status, and finer than
 * WebinarLifecycle's Upcoming/Past/Recorded, which the lists keep):
 *   upcoming → "Sign up" (registration URL)
 *   soon (≤15 min before) / live → "Join now" (the same link) + a live dot
 *   recorded → "Watch recording" (scrolls to the player) + "Recorded on …"
 *   ended, no recording → muted "This event has ended", no button
 * A timer re-derives the state at the next edge, so a page left open flips
 * to "Join now" and to "This event has ended" on its own.
 *
 * Presenters come from the free-text Presenter__c split on commas / "and"
 * (c/eventTimeUtil.splitPresenters) — INTERIM: a related list or a lookup
 * is the structured upgrade; nothing else reads the split.
 *
 * Dual-surface: no community-only imports; the sibling cards emit the
 * composed `resourceselect {slug}` the resourceCenter shell already routes on
 * both surfaces; the recording download goes through c/contextNav.fileHref
 * and reports `resourcedownload {id}` for the shell's tracking. Registration
 * and calendar links are absolute, so they resolve anywhere.
 *
 * Hosts: resourceDetail (the route) and eventsPage's detail modal, which
 * passes `hide-title` because the modal header already carries the name.
 *
 * @api detail      ResourceCenterService.ResourceDetail (a Webinar)
 * @api linkCtx     c/contextNav context (servlet paths for a file recording)
 * @api hideTitle   skip the h1 (eyebrow and summary stay) — modal hosts
 * @api viewerZone  IANA zone override (tests / "view as"); default = browser
 * @api clock       ISO/Date override for the derived state (tests); default = now,
 *                  kept fresh by the edge timer
 */
const MAX_SIBLINGS = 3;
const TIMER_SLACK_MS = 500;
const DEFAULT_MORE_LABEL = 'Webinars & Events';

export default class EventDetail extends LightningElement {
    @api detail;
    @api linkCtx;
    @api viewerZone;
    @api hideTitle = false;

    _clock;
    _now = new Date();
    _timer = null;
    feed = { upcoming: [], past: [] };

    @api
    get clock() {
        return this._clock;
    }
    set clock(value) {
        this._clock = value;
        const d = value ? new Date(value) : null;
        this._now = d && !Number.isNaN(d.getTime()) ? d : new Date();
        this.armTimer();
    }

    @wire(getEvents)
    wiredEvents({ data }) {
        if (data) {
            this.feed = data;
        }
    }

    connectedCallback() {
        this.armTimer();
    }

    disconnectedCallback() {
        this.clearTimer();
    }

    // ---- clock ---------------------------------------------------------------

    /** With no override, wake at the next state edge (soon / live / over). */
    armTimer() {
        this.clearTimer();
        if (this._clock || !this.detail) {
            return;
        }
        const wait = msUntilNextState(this.detail, this._now);
        if (wait === null) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setTimeout(() => {
            this._now = new Date();
            this.armTimer();
        }, wait + TIMER_SLACK_MS);
    }

    clearTimer() {
        if (this._timer) {
            clearTimeout(this._timer);
            this._timer = null;
        }
    }

    /** The HTML last injected into the manual container (re-inject only on change). */
    _renderedHtml = null;

    renderedCallback() {
        // The detail can arrive after connect; the timer keys off its start.
        if (!this._timer && !this._clock && this.detail) {
            this.armTimer();
        }
        // Rich-text agenda → the lwc:dom="manual" container. Sanitized on save
        // by the platform (rich text area) and again here (c/richTextUtil), the
        // same idiom nexsArticleViewer uses for bodies.
        const container = this.template.querySelector('.evd__rich');
        const html = this.descriptionHtml;
        if (container && this._renderedHtml !== html) {
            container.innerHTML = sanitizeHtml(html);
            this._renderedHtml = html;
        }
        if (!container) {
            this._renderedHtml = null;
        }
    }

    // ---- header ----------------------------------------------------------------

    get showTitle() {
        return this.hideTitle !== true && this.hideTitle !== 'true';
    }

    get typeLabel() {
        return (this.detail && this.detail.resourceType) || 'Event';
    }

    get audienceChips() {
        return ((this.detail && this.detail.audience) || []).map((a) => ({ key: a, label: a }));
    }

    /** "Lite users and Full users" / "Lite users, Full users, and Retirement plan advisors". */
    get audienceLine() {
        const a = (this.detail && this.detail.audience) || [];
        if (!a.length) {
            return null;
        }
        if (a.length === 1) {
            return a[0];
        }
        if (a.length === 2) {
            return `${a[0]} and ${a[1]}`;
        }
        return `${a.slice(0, -1).join(', ')}, and ${a[a.length - 1]}`;
    }

    // ---- content column --------------------------------------------------------

    get descriptionHtml() {
        const html = this.detail && this.detail.descriptionHtml;
        return html && html.trim() ? html : null;
    }

    get hasDescription() {
        return !!this.descriptionHtml;
    }

    get coverHeading() {
        const s = this.state;
        return s === STATE_RECORDED || s === STATE_ENDED ? 'What we covered' : "What we'll cover";
    }

    get presenters() {
        return splitPresenters(this.detail && this.detail.presenter);
    }

    get hasPresenters() {
        return this.presenters.length > 0;
    }

    get hasFile() {
        return !!(this.detail && this.detail.file && this.detail.file.downloadUrl);
    }

    /** Recorded with an embed URL: the same 16:9 player the Video type uses. */
    get showEmbed() {
        return this.isRecorded && !!this.detail.videoEmbedUrl;
    }

    /** Recorded with no embed: the newest attached file IS the recording. */
    get showFileVideo() {
        return this.isRecorded && !this.detail.videoEmbedUrl && this.hasFile;
    }

    get fileVideoSrc() {
        return this.hasFile ? fileHref(this.linkCtx, this.detail.file.downloadUrl) : null;
    }

    /** Download for a file recording (null for embeds and for no recording). */
    get downloadHref() {
        return this.showFileVideo ? this.fileVideoSrc : null;
    }

    // ---- state -----------------------------------------------------------------

    get state() {
        return this.detail ? eventState(this.detail, this._now) : null;
    }

    get isLive() {
        return this.state === STATE_LIVE;
    }

    get isSoon() {
        return this.state === STATE_SOON;
    }

    get isRecorded() {
        return this.state === STATE_RECORDED;
    }

    get isEnded() {
        return this.state === STATE_ENDED;
    }

    get cardClass() {
        return this.state ? `evd__card evd__card--${this.state}` : 'evd__card';
    }

    // ---- details card ------------------------------------------------------------

    get zone() {
        return isValidZone(this.viewerZone) ? this.viewerZone : detectZone();
    }

    get times() {
        return this.detail ? zoneTimes(this.detail.eventDatetime, this.zone) : [];
    }

    /** The viewer's own time — the big one. */
    get primaryTime() {
        const t = this.times[0];
        return t ? t.label : null;
    }

    /** The other zones as muted text: "9:00 AM MDT · 11:00 AM EDT". */
    get otherTimes() {
        const rest = this.times.slice(1).map((t) => t.label);
        return rest.length ? rest.join(' · ') : null;
    }

    get fullDate() {
        return this.detail ? formatDateInZone(this.detail.eventDatetime, this.zone) : null;
    }

    get duration() {
        return formatDurationMinutes(this.detail && this.detail.durationMinutes);
    }

    get recordedOn() {
        return this.isRecorded ? formatShortDateInZone(this.detail.eventDatetime, this.zone) : null;
    }

    get joinUrl() {
        return (this.detail && this.detail.registrationUrl) || null;
    }

    /** {label, href?} for the ONE primary button, or null (ended, or nothing to link). */
    get cta() {
        switch (this.state) {
            case STATE_UPCOMING:
                return this.joinUrl ? { label: 'Sign up', href: this.joinUrl } : null;
            case STATE_SOON:
            case STATE_LIVE:
                return this.joinUrl ? { label: 'Join now', href: this.joinUrl } : null;
            case STATE_RECORDED:
                return { label: 'Watch recording' };
            default:
                return null;
        }
    }

    get ctaLabel() {
        return this.cta ? this.cta.label : '';
    }

    get ctaHref() {
        return this.cta && this.cta.href ? this.cta.href : null;
    }

    get hasCtaLink() {
        return !!this.ctaHref;
    }

    get ctaIsWatch() {
        return !!this.cta && !this.cta.href;
    }

    // ---- siblings ----------------------------------------------------------------

    get moreHeading() {
        const name = this.detail && this.detail.categoryName;
        return `More in ${name || DEFAULT_MORE_LABEL}`;
    }

    /** The next three upcoming events that are not this one. */
    get siblings() {
        const self = this.detail && this.detail.slug;
        return (this.feed.upcoming || [])
            .filter((e) => e.slug !== self)
            .slice(0, MAX_SIBLINGS)
            .map((e) => {
                const t = formatInZone(e.eventDatetime, this.zone);
                return { id: e.id, slug: e.slug, name: e.name, eventDatetime: e.eventDatetime,
                         time: t ? t.label : '' };
            });
    }

    get hasSiblings() {
        return this.siblings.length > 0;
    }

    // ---- actions -------------------------------------------------------------------

    handleWatch() {
        const player = this.template.querySelector('.evd__player');
        if (player && typeof player.scrollIntoView === 'function') {
            player.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    handleDownload() {
        this.dispatchEvent(new CustomEvent('resourcedownload', {
            detail: { id: this.detail.id }, bubbles: true, composed: true
        }));
    }

    handleSibling(event) {
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug: event.currentTarget.dataset.slug }, bubbles: true, composed: true
        }));
    }
}