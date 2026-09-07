import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import getEvents from '@salesforce/apex/ResourceCenterService.getEvents';
import getResourceBySlug from '@salesforce/apex/ResourceCenterService.getResourceBySlug';
import trackDownload from '@salesforce/apex/ResourceCenterService.trackDownload';
import { messageFrom } from 'c/messageUtil';
import { formatTime, formatDateTime, formatMonthYear, localDateKey } from 'c/dsDateBlock';
import { eventCta, formatDurationMinutes, HELP_HOME_LABEL, CRUMB_HELP_HOME } from 'c/rcConstants';
import { linkContext, readParams, isSiteRef, goToResource, goToHome } from 'c/contextNav';

/**
 * eventsPage — the /help/events route host, in two views behind a tab strip:
 *   Calendar  — (default) c-ds-calendar over EVERY webinar, past and future;
 *               a chip opens c-ds-popover with the same CTA the list rows carry.
 *   Upcoming  — the agenda list: upcoming webinars grouped by month (Sign up),
 *               then past webinars that have a recording ("Watch recording" →
 *               resource detail).
 * Both views read one feed, ResourceCenterService.getEvents — never throws, so
 * an error surfaces as the same friendly empty state as an eventless org. The
 * feed is the whole active set and the client groups it by month; a
 * range-fetching overload is the upgrade path if volume ever warrants it.
 *
 * CTA per row / popover comes from c/rcConstants.eventCta — the ONE place
 * Sign up / Watch recording / "Recording coming soon" are decided (it routes
 * through resourceAction, so status→verb lives there). "Add to calendar"
 * (.ics download) was removed 2026-09-06 at the user's request.
 *
 * Detail modal (2026-09-07): the calendar popover is the quick peek (title,
 * when, meta, the one-sentence blurb, the CTA, "View details"); the full
 * event page — the SAME c-event-detail the Resource Center route renders —
 * opens in a c-ds-modal-v2 from "View details", from a row title, and from
 * "Watch recording" (the player is inside, so nobody leaves the page). The
 * modal loads ResourceCenterService.getResourceBySlug imperatively on open
 * (rich-text agenda, audience, recording file — the feed rows carry none of
 * that); a sibling card inside it swaps the modal to that event; the footer's
 * "Open full page" goes to the Resource Center route through c/contextNav.
 *
 * URL contract: the default Calendar view carries ?month=YYYY-MM (no view
 * param); the list is ?view=upcoming. The pre-2026-09-02 ?view=calendar form
 * still resolves. ?event=<slug> (2026-09-06) deep-links ONE webinar: the
 * calendar opens on its month (an explicit ?month= wins) with its detail
 * popover already open — the Arc announcement banner links here. It is
 * consumed once; a month step or tab switch rewrites the URL without it. In the
 * core app the same state arrives c__-prefixed on the Help_Center_Events tab;
 * c/contextNav.readParams reads whichever form the surface uses. URL sync is
 * SITE-ONLY (the helpArticlePage rule): Lightning owns its own history stack,
 * so on a core-app tab the URL is read on load and never written. On the site
 * both the tab switch and month steps push history so Back walks them and
 * any state is bookmarkable.
 *
 * Dual-surface rules as the other roots: inline everything, no community-only
 * imports. Navigation goes through c/contextNav — a site URL on Experience
 * Cloud, a Lightning PageReference in the core app.
 *
 * Way home: a "Help & Resources › Events" crumb above the heading (the same
 * c-ds-breadcrumbs the article and resource pages carry). It is the ONLY way
 * back when the page is embedded with the branding hidden (ARC), where the
 * chrome's brand crumb is gone.
 */
const VIEW_UPCOMING = 'upcoming';
const VIEW_CALENDAR = 'calendar';
const VIEWS = [VIEW_CALENDAR, VIEW_UPCOMING];
const DEFAULT_VIEW = VIEW_CALENDAR;
const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

export default class EventsPage extends NavigationMixin(LightningElement) {
    /** @api hideBranding — passed through to c-ds-chrome (ARC embeddings
     *  carry their own site chrome); the chrome coerces string values. */
    @api hideBranding = false;

    logoUrl = diversifyLogo;

    events = { upcoming: [], past: [] };
    loaded = false;
    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    view = DEFAULT_VIEW;
    /** 'YYYY-MM' shown by the calendar; null until a param or a nav sets it. */
    month = null;
    selectedId = null;
    anchorRect = null;

    /** Detail modal: the slug being shown (null = closed), its loaded detail, and status. */
    modalSlug = null;
    modalDetail = null;
    modalLoading = false;
    modalError = null;

    /** ?event= slug still to open (cleared once opened or found missing). */
    _pendingEvent = null;
    _monthExplicit = false;
    _pageRef;
    _isSite = false;
    _restored = false;
    _popstateHandler = null;

    // ---- inbound state -------------------------------------------------------

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        this._isSite = isSiteRef(ref);
        // Deep-link state rides the page reference in the core app, and the
        // wire may settle before OR after connectedCallback. Both read; the
        // latch closes once inbound state is found or the viewer acts, so a
        // late (or repeated) emit can never reset a view the viewer chose.
        if (ref && !this._restored) {
            this.restoreFrom(readParams(ref));
        }
    }

    connectedCallback() {
        if (!this._restored) {
            this.restoreFrom(readParams(this._pageRef));
        }
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        this._popstateHandler = () => this.handlePopState();
        window.addEventListener('popstate', this._popstateHandler);
    }

    disconnectedCallback() {
        if (this._popstateHandler) {
            window.removeEventListener('popstate', this._popstateHandler);
            this._popstateHandler = null;
        }
    }

    restoreFrom(params) {
        this.applyParams(params);
        if (params && (params.view || params.month || params.event)) {
            this._restored = true; // a deep link is inbound state too: never re-applied by a late emit
        }
    }

    /** Unknown view → Calendar; malformed month → the current month. */
    applyParams(params) {
        const view = params && params.view;
        const month = params && params.month;
        this.view = VIEWS.includes(view) ? view : DEFAULT_VIEW;
        this._monthExplicit = MONTH_RE.test(month || '');
        this.month = this._monthExplicit ? month : this.todayMonth;
        this._pendingEvent = params && params.event ? String(params.event) : null;
        this.applyPendingMonth();
    }

    @wire(getEvents)
    wiredEvents({ data, error }) {
        if (data) {
            this.events = data;
            this.applyPendingMonth();
        }
        if (data || error) {
            this.loaded = true;
        }
    }

    // ---- ?event= deep link ---------------------------------------------------

    pendingItem() {
        return this._pendingEvent
            ? this.allItems.find((e) => e.slug === this._pendingEvent) || null
            : null;
    }

    /** Without an explicit month, the deep-linked event's month is shown. */
    applyPendingMonth() {
        if (!this._pendingEvent || this._monthExplicit) {
            return;
        }
        const item = this.pendingItem();
        const month = item ? (localDateKey(item.eventDatetime) || '').slice(0, 7) : '';
        if (MONTH_RE.test(month)) {
            this.month = month;
        }
    }

    /** Open the deep-linked event once the feed and the calendar are both on screen. */
    renderedCallback() {
        if (!this._pendingEvent || !this.loaded) {
            return;
        }
        if (!this.isCalendarView) {
            this._pendingEvent = null; // the list has nothing to open
            return;
        }
        const item = this.pendingItem();
        const cal = this.template.querySelector('c-ds-calendar');
        if (!cal || typeof cal.select !== 'function') {
            return;
        }
        this._pendingEvent = null;
        if (item) {
            cal.select(item.id); // false when off the shown month — the calendar is the answer then
        }
    }

    // ---- URL sync (site only) ------------------------------------------------

    syncUrl() {
        if (!this._isSite) {
            return; // core app: Lightning owns the history stack
        }
        try {
            // Read the LIVE url, not the cached page ref — the wire does not
            // re-emit after our own pushState.
            const current = readParams(null);
            // Canonical forms: calendar (the default) → ?month=YYYY-MM only;
            // upcoming → ?view=upcoming only.
            const wantView = this.isCalendarView ? undefined : VIEW_UPCOMING;
            const wantMonth = this.isCalendarView ? this.currentMonth : undefined;
            const currentView = VIEWS.includes(current.view) ? current.view : DEFAULT_VIEW;
            if (currentView === this.view && current.month === wantMonth) {
                return; // deep-link mount or popstate-driven change — URL is right
            }
            const url = new URL(window.location.href);
            url.searchParams.delete('view');
            url.searchParams.delete('month');
            url.searchParams.delete('event'); // the deep link is consumed, never replayed by Back
            if (wantView) {
                url.searchParams.set('view', wantView);
            }
            if (wantMonth) {
                url.searchParams.set('month', wantMonth);
            }
            // Month steps push too (not replace): stepping back through months
            // with the browser's Back is the expected behavior of a calendar.
            window.history.pushState({}, '', url.toString());
        } catch (e) {
            // URL sync is best-effort — never break the page over it.
        }
    }

    handlePopState() {
        this.applyParams(readParams(null));
        this.closePopover();
    }

    // ---- Derived view --------------------------------------------------------

    get todayMonth() {
        return (localDateKey(new Date()) || '').slice(0, 7);
    }

    get currentMonth() {
        return this.month || this.todayMonth;
    }

    get isUpcomingView() {
        return this.view !== VIEW_CALENDAR;
    }

    get isCalendarView() {
        return this.view === VIEW_CALENDAR;
    }

    get tabs() {
        return [
            { value: VIEW_CALENDAR, label: 'Calendar' },
            { value: VIEW_UPCOMING, label: 'Upcoming', count: (this.events.upcoming || []).length }
        ];
    }

    get pageClass() {
        return this.isCalendarView ? 'ev ev--calendar' : 'ev';
    }

    get crumbItems() {
        return [{ label: HELP_HOME_LABEL, key: CRUMB_HELP_HOME }, { label: 'Event Center' }];
    }

    get allItems() {
        return [...(this.events.upcoming || []), ...(this.events.past || [])];
    }

    /** WebinarItem → the webinar-agnostic dsCalendar contract. */
    get calendarEvents() {
        return this.allItems.map((item) => ({
            id: item.id,
            dateIso: item.eventDatetime,
            title: item.name,
            kind: 'webinar',
            status: item.status
        }));
    }

    /** "10:00 AM · 45 min · Jane Doe" + the shared CTA, with the flags the
        template needs (it cannot compare strings). The blurb is the authored
        one-sentence summary when there is one, else the server's plain-text
        description (Description__c is rich text; the detail page renders it). */
    decorate(item) {
        const cta = eventCta(item);
        return {
            ...item,
            description: item.summary || item.description,
            meta: [
                formatTime(item.eventDatetime),
                formatDurationMinutes(item.durationMinutes),
                item.presenter
            ].filter(Boolean).join(' · '),
            cta: {
                ...cta,
                isSignup: Boolean(cta.primary && cta.primary.kind === 'signup'),
                isWatch: Boolean(cta.primary && cta.primary.kind === 'watch'),
                primaryLabel: cta.primary ? cta.primary.label : '',
                primaryHref: cta.primary ? cta.primary.href : undefined
            }
        };
    }

    /** Upcoming events bucketed by month heading. The server sorts ascending,
        so consecutive grouping preserves order without re-sorting. */
    get monthGroups() {
        const groups = [];
        for (const item of this.events.upcoming || []) {
            const label = formatMonthYear(item.eventDatetime) || 'Upcoming';
            const last = groups[groups.length - 1];
            if (last && last.label === label) {
                last.items.push(this.decorate(item));
            } else {
                groups.push({ key: label, label, items: [this.decorate(item)] });
            }
        }
        return groups;
    }

    /** The list shows only past events with something to watch; the feed now
        carries every past webinar so the calendar can show them all. */
    get pastItems() {
        return (this.events.past || [])
            .filter((item) => item.watchable)
            .map((item) => this.decorate(item));
    }

    get hasUpcoming() {
        return (this.events.upcoming || []).length > 0;
    }

    get hasPast() {
        return this.pastItems.length > 0;
    }

    /** Only after the wire settles — a loading page shows nothing, not "no events". */
    get showEmptyUpcoming() {
        return this.loaded && !this.hasUpcoming;
    }

    /** The popover's event: the calendar selection, decorated for the popover. */
    get selectedEvent() {
        if (!this.selectedId) {
            return null;
        }
        const item = this.allItems.find((e) => e.id === this.selectedId);
        if (!item) {
            return null;
        }
        return {
            ...this.decorate(item),
            when: formatDateTime(item.eventDatetime),
            duration: formatDurationMinutes(item.durationMinutes)
        };
    }

    get popoverOpen() {
        return Boolean(this.selectedEvent);
    }

    // ---- Actions -------------------------------------------------------------

    handleCrumb(event) {
        if (event.detail.key === CRUMB_HELP_HOME) {
            goToHome(this, this.linkCtx);
        }
    }

    handleTabChange(event) {
        this._restored = true;
        this.view = event.detail.value;
        this.closePopover();
        this.syncUrl();
    }

    handleMonthChange(event) {
        this._restored = true;
        this.month = event.detail.month;
        this.closePopover();
        this.syncUrl();
    }

    handleEventSelect(event) {
        this.selectedId = event.detail.id;
        this.anchorRect = event.detail.anchorRect;
    }

    closePopover() {
        this.selectedId = null;
        this.anchorRect = null;
    }

    handlePopoverClose() {
        this.closePopover();
    }

    /** Watch recording opens the modal — the player is inside c-event-detail. */
    handleWatch(event) {
        this.openEvent(event.currentTarget.dataset.slug);
    }

    handleTitle(event) {
        this.openEvent(event.currentTarget.dataset.slug);
    }

    /** The popover's "View details": the quick peek hands off to the full page. */
    handleViewDetails(event) {
        const slug = event.currentTarget.dataset.slug;
        this.closePopover();
        this.openEvent(slug);
    }

    handleBrandHome() {
        goToHome(this, this.linkCtx);
    }

    // ---- Detail modal --------------------------------------------------------

    get modalOpen() {
        return Boolean(this.modalSlug);
    }

    /** The feed knows the name before the detail lands, so the header never flashes empty. */
    get modalTitle() {
        if (this.modalDetail && this.modalDetail.name) {
            return this.modalDetail.name;
        }
        const item = this.allItems.find((e) => e.slug === this.modalSlug);
        return item ? item.name : 'Event details';
    }

    get showModalDetail() {
        return Boolean(this.modalDetail) && !this.modalLoading && !this.modalError;
    }

    openEvent(slug) {
        if (!slug) {
            return;
        }
        this.modalSlug = slug;
        this.modalDetail = null;
        this.modalError = null;
        this.modalLoading = true;
        getResourceBySlug({ slug })
            .then((detail) => {
                if (this.modalSlug !== slug) {
                    return; // a later open won
                }
                this.modalDetail = detail;
                this.modalLoading = false;
            })
            .catch((e) => {
                if (this.modalSlug !== slug) {
                    return;
                }
                this.modalError = messageFrom(e, "This event couldn't be loaded.");
                this.modalLoading = false;
            });
    }

    handleModalClose() {
        this.modalSlug = null;
        this.modalDetail = null;
        this.modalError = null;
        this.modalLoading = false;
    }

    /** A sibling card inside the modal: show that event in place. */
    handleModalSibling(event) {
        event.stopPropagation();
        this.openEvent(event.detail.slug);
    }

    /** The recording download inside the modal: count it, as the shell would. */
    handleModalDownload(event) {
        event.stopPropagation();
        if (event.detail && event.detail.id) {
            trackDownload({ resourceId: event.detail.id }).catch(() => {});
        }
    }

    handleOpenFullPage() {
        const slug = this.modalSlug;
        this.handleModalClose();
        goToResource(this, this.linkCtx, { slug });
    }
}