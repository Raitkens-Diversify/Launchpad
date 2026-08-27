import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import { refreshApex } from "@salesforce/apex";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import getActivities from "@salesforce/apex/ArcActivityPanelController.getActivities";
import getFeedComments from "@salesforce/apex/ArcActivityPanelController.getFeedComments";
import createEventApex from "@salesforce/apex/ArcActivityPanelController.createEvent";
import logEmailApex from "@salesforce/apex/ArcActivityPanelController.logEmail";
import postToFeedApex from "@salesforce/apex/ArcActivityPanelController.postToFeed";
import addFeedCommentApex from "@salesforce/apex/ArcActivityPanelController.addFeedComment";
import getRecordFeed from "@salesforce/apex/ArcCaseFeedController.getRecordFeed";

/**
 * arcActivityPanel
 *
 * The Activity | Chatter panel from the right rail of the Lightning account
 * record page, redrawn in ARC.
 *
 * EVERYTHING HERE WAS READ OFF THE LIVE PANEL, not designed from memory. The
 * two composer buttons and their dropdown items, the wording of the filter
 * summary line, the three links, the section heading, the empty-state sentences
 * and every option in the Timeline Settings dialog were taken from
 * /lightning/r/Account/<id>/view with the Activity tab open. Where this differs
 * from that panel the difference is called out in a comment, not left to be
 * discovered.
 *
 * WHY THE COMPOSER HAS ONLY TWO BUTTONS. Because that page has only two -- New
 * Event and Email. Lightning shows New Task and Log a Call on layouts that
 * include those actions; this account's does not, so neither does this.
 *
 * APEX. The timeline and the writes come from ArcActivityPanelController, which
 * is new and standalone. The Chatter post list comes from
 * ArcCaseFeedController.getRecordFeed, which already existed and is called
 * unmodified -- it is not Case-specific despite the name.
 *
 * TWO DELIBERATE DEPARTURES, both flagged in the UI rather than hidden:
 *
 *  - Email LOGS an email; it does not send one. Sending would mean real mail to
 *    real clients from a portal button, through the org's deliverability
 *    settings. The activity it writes is the one a send produces, so the
 *    timeline reads the same.
 *  - View Calendar leaves ARC. ARC has no calendar route, so it opens the
 *    Salesforce calendar in a new tab. The URL is a design property, so it can
 *    be retargeted without a code change.
 */

// ── Tabs ─────────────────────────────────────────────────────────────────────

const TAB_ACTIVITY = "activity";
const TAB_CHATTER = "chatter";

const TABS = [
  { value: TAB_ACTIVITY, label: "Activity" },
  { value: TAB_CHATTER, label: "Chatter" }
];

// ── Timeline Settings, option for option from the Lightning dialog ───────────

const DATE_RANGE_OPTIONS = [
  { value: "all", label: "All time" },
  { value: "next7", label: "Next 7 days" },
  { value: "last7", label: "Last 7 days" },
  { value: "last30", label: "Last 30 days" }
];

const SCOPE_OPTIONS = [
  { value: "all", label: "All activities" },
  { value: "mine", label: "My activities" }
];

/**
 * Listed in the dialog's own order, which is alphabetical by label rather than
 * by the value the server wants.
 */
const TYPE_OPTIONS = [
  { value: "email", label: "Email" },
  { value: "event", label: "Events" },
  { value: "listemail", label: "List email" },
  { value: "call", label: "Logged calls" },
  { value: "task", label: "Tasks" },
  { value: "web", label: "Web" }
];

const SORT_OPTIONS = [
  { value: "oldest", label: "Oldest dates first" },
  { value: "newest", label: "Newest dates first" }
];

const ALL_TYPES = TYPE_OPTIONS.map((option) => option.value);

/**
 * Sent when the user has ticked no types at all.
 *
 * The server reads an empty list as "no filter", which is right for the default
 * but wrong here -- unticking every box would show everything instead of
 * nothing. A type that matches nothing says "none" unambiguously, and survives
 * the round trip through the saved settings.
 */
const NO_TYPES = "none";

const DEFAULTS = Object.freeze({
  dateRange: "all",
  scope: "all",
  types: ALL_TYPES,
  sortUpcoming: "oldest"
});

// ── Composer dropdowns, item for item ────────────────────────────────────────

const EVENT_MENU = [
  { id: "new-event", label: "New Event" },
  { id: "view-calendar", label: "View Calendar" }
];

const EMAIL_MENU = [
  { id: "outlook", label: "Send with Outlook" },
  { id: "gmail", label: "Send with Gmail" },
  { id: "email-preferences", label: "Set My Email Preferences" }
];

const MENU_EVENT = "event";
const MENU_EMAIL = "email";

// ── Sections ─────────────────────────────────────────────────────────────────

const UPCOMING_KEY = "upcoming";
const UPCOMING_TITLE = "Upcoming & Overdue";
const UNDATED_KEY = "undated";

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December"
];

// ── Sizes and routes ─────────────────────────────────────────────────────────

const PAST_PAGE_SIZE = 25;
const FEED_PAGE_SIZE = 20;

/** ARC's own activity list, which is where View All can land inside the site. */
const TASK_LIST_ROUTE = "/task/Task/Default";

/** ARC's Settings page carries the notification preferences. */
const SETTINGS_ROUTE = "/settings";

const GMAIL_COMPOSE = "https://mail.google.com/mail/?view=cm&fs=1";
const OUTLOOK_COMPOSE =
  "https://outlook.office.com/mail/deeplink/compose";

const STORAGE_KEY = "arc.activityPanel.timelineSettings";

// ── Formatters ───────────────────────────────────────────────────────────────

const DATE_FORMAT = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  year: "numeric"
});

const TIME_FORMAT = new Intl.DateTimeFormat(undefined, {
  hour: "numeric",
  minute: "2-digit"
});

const DATE_TIME_FORMAT = new Intl.DateTimeFormat(undefined, {
  month: "long",
  day: "numeric",
  year: "numeric",
  hour: "numeric",
  minute: "2-digit"
});

/**
 * A date-only value arrives as "2026-08-27". new Date() reads that as UTC
 * midnight, which renders as the day before anywhere west of Greenwich -- so it
 * is split by hand into a local date instead. This is the difference between a
 * task showing its real due date and showing yesterday's.
 */
const parseDateOnly = (value) => {
  if (!value) {
    return null;
  }
  const parts = String(value).slice(0, 10).split("-");
  if (parts.length !== 3) {
    return null;
  }
  const [year, month, day] = parts.map(Number);
  if (!year || !month || !day) {
    return null;
  }
  return new Date(year, month - 1, day);
};

const parseDateTime = (value) => {
  if (!value) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const readStored = () => {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : null;
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    /* Private browsing, or storage disabled — defaults still apply. */
    return null;
  }
};

const writeStored = (settings) => {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    /* As above: losing the write costs the user only this preference. */
  }
};

export default class ArcActivityPanel extends NavigationMixin(LightningElement) {
  /** The object whose record page this sits on. */
  @api objectApiName = "Account";

  /**
   * Where View Calendar goes. ARC has no calendar of its own, so this leaves the
   * site; exposed as a property so it can be pointed elsewhere -- an ARC
   * calendar page, once there is one -- without touching this component.
   */
  @api calendarUrl = "/lightning/o/Event/home";

  recordId;
  activeTab = TAB_ACTIVITY;

  // ---- applied filters (what the server is being asked for) ---------------

  appliedDateRange = DEFAULTS.dateRange;
  appliedScope = DEFAULTS.scope;
  appliedTypes = DEFAULTS.types;
  appliedSort = DEFAULTS.sortUpcoming;

  // ---- draft filters (what the settings dialog is showing) ---------------

  draftDateRange = DEFAULTS.dateRange;
  draftScope = DEFAULTS.scope;
  draftTypes = DEFAULTS.types;
  draftSort = DEFAULTS.sortUpcoming;

  isSettingsOpen = false;
  openMenu = null;

  /**
   * Free-text filter over the loaded timeline.
   *
   * CLIENT-SIDE ON PURPOSE. It filters what is already here -- every upcoming and
   * overdue activity, plus the most recent page of past ones -- rather than
   * issuing another query. A server-side search would need its own SOQL and would
   * still be capped, and the Lightning panel this copies has no search at all, so
   * there is no behaviour to match. Anything older than the loaded page is
   * reached through View All, and the hint under the box says so when a search is
   * running.
   */
  searchTerm = "";

  /** Section keys the user has collapsed. An array so the template re-renders. */
  collapsedKeys = [];

  // ---- new event form ----------------------------------------------------

  isEventFormOpen = false;
  eventSubject = "";
  eventStart = "";
  eventEnd = "";
  eventAllDay = false;
  eventLocation = "";
  eventDescription = "";

  // ---- log email form ---------------------------------------------------

  isEmailFormOpen = false;
  emailTo = "";
  emailSubject = "";
  emailBody = "";

  // ---- chatter ----------------------------------------------------------

  postBody = "";
  feedSort = "newest";
  commentDrafts = {};
  openCommentFor = null;

  // ---- shared -----------------------------------------------------------

  isSaving = false;
  statusMessage;
  statusIsError = false;

  activityData;
  activityError;
  feedData;
  feedError;
  feedItemIds = [];
  commentsByFeedItem = {};

  _activityResult;
  _feedResult;
  _commentsResult;
  _documentClickHandler;

  // ========================================================================
  // Lifecycle
  // ========================================================================

  connectedCallback() {
    const stored = readStored();
    if (stored) {
      this.appliedDateRange = stored.dateRange || DEFAULTS.dateRange;
      this.appliedScope = stored.scope || DEFAULTS.scope;
      this.appliedTypes = Array.isArray(stored.types) && stored.types.length
        ? stored.types
        : DEFAULTS.types;
      this.appliedSort = stored.sortUpcoming || DEFAULTS.sortUpcoming;
    }
    this.syncDraftFromApplied();

    /*
     * A dropdown closes when the click lands anywhere else, which is what the
     * Lightning menus do. Bound at document level because the click that should
     * close it usually happens outside this component entirely.
     */
    this._documentClickHandler = () => {
      if (this.openMenu) {
        this.openMenu = null;
      }
    };
    document.addEventListener("click", this._documentClickHandler);
  }

  disconnectedCallback() {
    if (this._documentClickHandler) {
      document.removeEventListener("click", this._documentClickHandler);
      this._documentClickHandler = null;
    }
  }

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const next =
      resolveRecordIdFromPageReference(pageRef, this.objectApiName) || undefined;

    if (next !== this.recordId) {
      this.recordId = next;
    }
  }

  // ========================================================================
  // Data
  // ========================================================================

  @wire(getActivities, {
    recordId: "$recordId",
    dateRange: "$appliedDateRange",
    scope: "$appliedScope",
    types: "$appliedTypes",
    pageSize: PAST_PAGE_SIZE
  })
  wiredActivities(result) {
    this._activityResult = result;
    const { data, error } = result;

    if (data) {
      this.activityData = data;
      this.activityError = undefined;
      return;
    }
    if (error) {
      this.activityData = undefined;
      this.activityError =
        error?.body?.message || "Unable to load this record's activity.";
    }
  }

  @wire(getRecordFeed, { recordId: "$recordId", pageSize: FEED_PAGE_SIZE })
  wiredFeed(result) {
    this._feedResult = result;
    const { data, error } = result;

    if (data) {
      this.feedData = data;
      this.feedError = undefined;
      // Set as a field, not derived in a getter: a wire's reactive parameter
      // tracks fields, and getFeedComments below has to re-run when the feed
      // changes.
      this.feedItemIds = (data.entries || []).map((entry) => entry.id);
      return;
    }
    if (error) {
      this.feedData = undefined;
      this.feedItemIds = [];
      this.feedError = error?.body?.message || "Unable to load the feed.";
    }
  }

  /**
   * Comments live here rather than in the feed read because
   * ArcCaseFeedController.getRecordFeed does not return them and that class is
   * not being modified. Keyed by post so the template can look them up.
   */
  @wire(getFeedComments, { feedItemIds: "$feedItemIds" })
  wiredComments(result) {
    this._commentsResult = result;
    const { data } = result;

    if (!data) {
      return;
    }
    const grouped = {};
    data.forEach((comment) => {
      const key = comment.FeedItemId;
      if (!grouped[key]) {
        grouped[key] = [];
      }
      grouped[key].push({
        id: comment.Id,
        body: comment.CommentBody,
        actorName: comment.CreatedBy ? comment.CreatedBy.Name : "",
        whenLabel: this.formatDateTime(comment.CreatedDate)
      });
    });
    this.commentsByFeedItem = grouped;
  }

  // ========================================================================
  // Tabs
  // ========================================================================

  get tabs() {
    return TABS;
  }

  get showActivity() {
    return this.activeTab === TAB_ACTIVITY;
  }

  get showChatter() {
    return this.activeTab === TAB_CHATTER;
  }

  handleTabChange(event) {
    this.activeTab = event.detail.value;
    this.openMenu = null;
    this.clearStatus();
  }

  // ========================================================================
  // Composer
  // ========================================================================

  get eventMenu() {
    return EVENT_MENU;
  }

  get emailMenu() {
    return EMAIL_MENU;
  }

  get isEventMenuOpen() {
    return this.openMenu === MENU_EVENT;
  }

  get isEmailMenuOpen() {
    return this.openMenu === MENU_EMAIL;
  }

  get eventMenuExpanded() {
    return this.isEventMenuOpen ? "true" : "false";
  }

  get emailMenuExpanded() {
    return this.isEmailMenuOpen ? "true" : "false";
  }

  handleMenuToggle(event) {
    // The document listener would otherwise close the menu this click opened.
    event.stopPropagation();
    const which = event.currentTarget.dataset.menu;
    this.openMenu = this.openMenu === which ? null : which;
  }

  handleEventMenuSelect(event) {
    event.stopPropagation();
    this.openMenu = null;

    const id = event.currentTarget.dataset.id;
    if (id === "new-event") {
      this.openEventForm();
      return;
    }
    if (id === "view-calendar") {
      this.openExternal(this.calendarUrl);
    }
  }

  handleEmailMenuSelect(event) {
    event.stopPropagation();
    this.openMenu = null;

    const id = event.currentTarget.dataset.id;
    if (id === "gmail") {
      this.openExternal(GMAIL_COMPOSE);
      return;
    }
    if (id === "outlook") {
      this.openExternal(OUTLOOK_COMPOSE);
      return;
    }
    if (id === "email-preferences") {
      this.navigateWithin(SETTINGS_ROUTE);
    }
  }

  // ========================================================================
  // Filter summary and the three links
  // ========================================================================

  /** "All time • All activities • All types", built the way the panel builds it. */
  get filterSummary() {
    const range = DATE_RANGE_OPTIONS.find(
      (option) => option.value === this.appliedDateRange
    );
    const scope = SCOPE_OPTIONS.find(
      (option) => option.value === this.appliedScope
    );

    const typeLabel =
      this.appliedTypes.length === ALL_TYPES.length
        ? "All types"
        : TYPE_OPTIONS.filter((option) =>
            this.appliedTypes.includes(option.value)
          )
            .map((option) => option.label)
            .join(", ");

    return [
      range ? range.label : "All time",
      scope ? scope.label : "All activities",
      typeLabel || "No types"
    ].join(" • ");
  }

  get normalisedSearch() {
    return (this.searchTerm || "").trim().toLowerCase();
  }

  get isSearching() {
    return this.normalisedSearch.length > 0;
  }

  /**
   * Matches the fields a person would actually search by: what it was called,
   * what it said, who owns it, what it hangs off, and its type.
   */
  matchesSearch(entry) {
    const term = this.normalisedSearch;
    if (!term) {
      return true;
    }
    return [
      entry.title,
      entry.description,
      entry.ownerName,
      entry.relatedName,
      entry.typeLabel,
      entry.status
    ]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(term));
  }

  get searchResultLabel() {
    const count = this.matchCount;
    return count === 1 ? "1 result" : `${count} results`;
  }

  get matchCount() {
    return this.timelineSections.reduce(
      (total, section) => total + section.entries.length,
      0
    );
  }

  handleSearchChange(event) {
    this.searchTerm = event.target.value || "";
  }

  handleClearSearch() {
    this.searchTerm = "";
  }

  get isAnyCollapsed() {
    return this.collapsedKeys.length > 0;
  }

  get expandAllLabel() {
    return this.isAnyCollapsed ? "Expand All" : "Collapse All";
  }

  handleRefresh() {
    this.clearStatus();
    if (this._activityResult) {
      refreshApex(this._activityResult);
    }
  }

  handleToggleExpandAll() {
    this.collapsedKeys = this.isAnyCollapsed
      ? []
      : this.timelineSections.map((section) => section.key);
  }

  handleViewAll() {
    this.navigateWithin(TASK_LIST_ROUTE);
  }

  /**
   * The brand button in the empty state. In Lightning it clears whatever is
   * hiding activities, which is exactly restoring the defaults and opening every
   * section.
   */
  handleShowAllActivities() {
    this.applyFilters(DEFAULTS, false);
    this.collapsedKeys = [];
    // A search is a filter too, and this button's job is "stop hiding things".
    this.searchTerm = "";
  }

  // ========================================================================
  // Timeline Settings dialog
  // ========================================================================

  handleOpenSettings(event) {
    event.stopPropagation();
    this.syncDraftFromApplied();
    this.isSettingsOpen = true;
  }

  handleCloseSettings() {
    this.isSettingsOpen = false;
  }

  get dateRangeOptions() {
    return DATE_RANGE_OPTIONS.map((option) => ({
      ...option,
      checked: option.value === this.draftDateRange
    }));
  }

  get scopeOptions() {
    return SCOPE_OPTIONS.map((option) => ({
      ...option,
      checked: option.value === this.draftScope
    }));
  }

  get sortOptions() {
    return SORT_OPTIONS.map((option) => ({
      ...option,
      checked: option.value === this.draftSort
    }));
  }

  get typeOptions() {
    return TYPE_OPTIONS.map((option) => ({
      ...option,
      checked: this.draftTypes.includes(option.value)
    }));
  }

  get allTypesChecked() {
    return this.draftTypes.length === ALL_TYPES.length;
  }

  handleDraftDateRange(event) {
    this.draftDateRange = event.currentTarget.dataset.value;
  }

  handleDraftScope(event) {
    this.draftScope = event.currentTarget.dataset.value;
  }

  handleDraftSort(event) {
    this.draftSort = event.currentTarget.dataset.value;
  }

  handleDraftAllTypes(event) {
    this.draftTypes = event.target.checked ? ALL_TYPES : [];
  }

  handleDraftType(event) {
    const value = event.currentTarget.dataset.value;
    const checked = event.target.checked;
    const next = this.draftTypes.filter((type) => type !== value);
    if (checked) {
      next.push(value);
    }
    this.draftTypes = next;
  }

  handleRestoreDefaults() {
    this.draftDateRange = DEFAULTS.dateRange;
    this.draftScope = DEFAULTS.scope;
    this.draftTypes = DEFAULTS.types;
    this.draftSort = DEFAULTS.sortUpcoming;
  }

  /** Apply: this visit only. */
  handleApply() {
    this.applyFilters(this.draftSettings, false);
    this.isSettingsOpen = false;
  }

  /**
   * Apply & Save: remembered for next time.
   *
   * Kept in this browser rather than on the user record. Persisting it
   * server-side would mean either a new field or writing to an existing
   * preferences object, and a view filter is not worth either.
   */
  handleApplyAndSave() {
    this.applyFilters(this.draftSettings, true);
    this.isSettingsOpen = false;
  }

  get draftSettings() {
    return {
      dateRange: this.draftDateRange,
      scope: this.draftScope,
      types: this.draftTypes,
      sortUpcoming: this.draftSort
    };
  }

  applyFilters(settings, persist) {
    // A new array each time, so the wire sees a changed configuration.
    const types = settings.types.length ? [...settings.types] : [NO_TYPES];

    this.appliedDateRange = settings.dateRange;
    this.appliedScope = settings.scope;
    this.appliedTypes = types;
    this.appliedSort = settings.sortUpcoming;
    this.syncDraftFromApplied();

    if (persist) {
      // Persist what was applied, not what was drafted, so "no types" comes
      // back as no types rather than reverting to all of them.
      writeStored({ ...settings, types });
    }
  }

  syncDraftFromApplied() {
    this.draftDateRange = this.appliedDateRange;
    this.draftScope = this.appliedScope;
    this.draftTypes = [...this.appliedTypes];
    this.draftSort = this.appliedSort;
  }

  // ========================================================================
  // Timeline
  // ========================================================================

  /**
   * Upcoming & Overdue first, then one section per month of past activity,
   * newest month first -- the grouping the Lightning timeline uses.
   *
   * Upcoming & Overdue is built even when it holds nothing, because that is
   * where the panel puts its empty state.
   */
  get timelineSections() {
    const data = this.activityData;
    if (!data) {
      return [];
    }

    const upcoming = this.sortUpcomingEntries(
      (data.upcoming || []).filter((entry) => this.matchesSearch(entry))
    );

    const sections = [
      this.buildSection(UPCOMING_KEY, UPCOMING_TITLE, upcoming, true)
    ];

    const groups = [];
    const byKey = {};

    (data.past || []).filter((entry) => this.matchesSearch(entry)).forEach((entry) => {
      const when = parseDateTime(entry.sortDate);
      const key = when
        ? `${when.getFullYear()}-${when.getMonth()}`
        : UNDATED_KEY;

      if (!byKey[key]) {
        byKey[key] = {
          key,
          title: when
            ? `${MONTH_NAMES[when.getMonth()]} • ${when.getFullYear()}`
            : "No date",
          entries: []
        };
        groups.push(byKey[key]);
      }
      byKey[key].entries.push(entry);
    });

    groups.forEach((group) => {
      sections.push(
        this.buildSection(group.key, group.title, group.entries, false)
      );
    });

    return sections;
  }

  /** SORT UPCOMING & OVERDUE ACTIVITIES, done here because it needs no reread. */
  sortUpcomingEntries(entries) {
    const sorted = [...entries].sort((a, b) => {
      const left = parseDateTime(a.sortDate);
      const right = parseDateTime(b.sortDate);
      if (!left && !right) {
        return 0;
      }
      // An activity with no date sorts last either way round, matching the
      // server's NULLS LAST ordering.
      if (!left) {
        return 1;
      }
      if (!right) {
        return -1;
      }
      return left.getTime() - right.getTime();
    });

    return this.appliedSort === "newest" ? sorted.reverse() : sorted;
  }

  buildSection(key, title, entries, showEmptyState) {
    const isOpen = !this.collapsedKeys.includes(key);
    const isEmpty = showEmptyState && entries.length === 0;

    return {
      key,
      title,
      isOpen,
      ariaExpanded: isOpen ? "true" : "false",
      iconName: isOpen ? "utility:chevrondown" : "utility:chevronright",
      count: entries.length,
      entries: entries.map((entry) => this.decorate(entry)),
      // Only one of these is ever true. A search that matched nothing is not
      // the same as a record with nothing on it, and the two need different
      // wording and a different button.
      showEmptyState: isEmpty && !this.isSearching,
      showSearchEmptyState: isEmpty && this.isSearching
    };
  }

  /**
   * Row display strings, computed here because a template cannot branch on a
   * per-row basis without a getter, and a getter is not available inside
   * for:each.
   */
  decorate(entry) {
    return {
      ...entry,
      whenLabel: this.buildWhenLabel(entry),
      metaLabel: [
        entry.typeLabel,
        entry.ownerName,
        entry.relatedName,
        entry.location
      ]
        .filter(Boolean)
        .join(" • "),
      hasDescription: Boolean(entry.description),
      rowClass: entry.isOverdue
        ? "arc-activity__row arc-activity__row_overdue"
        : "arc-activity__row"
    };
  }

  buildWhenLabel(entry) {
    if (entry.kind === "Event") {
      if (entry.isAllDay) {
        const day = parseDateOnly(entry.activityDate);
        return day ? `${DATE_FORMAT.format(day)} • All day` : "All day";
      }

      const start = parseDateTime(entry.startDateTime);
      const end = parseDateTime(entry.endDateTime);
      if (!start) {
        return "No date";
      }
      return end
        ? `${DATE_FORMAT.format(start)}, ${TIME_FORMAT.format(start)} – ${TIME_FORMAT.format(end)}`
        : `${DATE_FORMAT.format(start)}, ${TIME_FORMAT.format(start)}`;
    }

    const due = parseDateOnly(entry.activityDate);
    if (!due) {
      return "No due date";
    }
    return entry.isOverdue
      ? `Overdue • ${DATE_FORMAT.format(due)}`
      : DATE_FORMAT.format(due);
  }

  handleToggleSection(event) {
    const key = event.currentTarget.dataset.key;
    this.collapsedKeys = this.collapsedKeys.includes(key)
      ? this.collapsedKeys.filter((existing) => existing !== key)
      : [...this.collapsedKeys, key];
  }

  /**
   * True only once a record is known and the read has neither returned nor
   * failed. Without the recordId test this would spin for ever on a page with no
   * record, because a wire does not call the server while a reactive parameter
   * is undefined.
   */
  get isTimelineLoading() {
    return Boolean(this.recordId) && !this.activityData && !this.activityError;
  }

  get hasMorePast() {
    return Boolean(this.activityData && this.activityData.hasMore);
  }

  // ========================================================================
  // New Event
  // ========================================================================

  openEventForm() {
    this.eventSubject = "";
    this.eventStart = "";
    this.eventEnd = "";
    this.eventAllDay = false;
    this.eventLocation = "";
    this.eventDescription = "";
    this.clearStatus();
    this.isEventFormOpen = true;
  }

  handleNewEventClick(event) {
    event.stopPropagation();
    this.openMenu = null;
    this.openEventForm();
  }

  handleCloseEventForm() {
    this.isEventFormOpen = false;
  }

  handleEventField(event) {
    const field = event.currentTarget.dataset.field;
    const value =
      field === "eventAllDay" ? event.target.checked : event.target.value;
    this[field] = value;
  }

  handleSaveEvent() {
    if (!this.eventSubject || !this.eventStart) {
      this.setStatus("Subject and a start date and time are required.", true);
      return;
    }

    this.isSaving = true;
    createEventApex({
      recordId: this.recordId,
      subject: this.eventSubject,
      startDateTime: this.eventStart,
      endDateTime: this.eventAllDay ? null : this.eventEnd || null,
      allDay: this.eventAllDay,
      location: this.eventLocation,
      description: this.eventDescription
    })
      .then(() => {
        this.isEventFormOpen = false;
        this.setStatus("Event created.", false);
        return refreshApex(this._activityResult);
      })
      .catch((error) => {
        this.setStatus(
          error?.body?.message || "The event could not be created.",
          true
        );
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  // ========================================================================
  // Email
  // ========================================================================

  handleEmailClick(event) {
    event.stopPropagation();
    this.openMenu = null;
    this.emailTo = "";
    this.emailSubject = "";
    this.emailBody = "";
    this.clearStatus();
    this.isEmailFormOpen = true;
  }

  handleCloseEmailForm() {
    this.isEmailFormOpen = false;
  }

  handleEmailField(event) {
    this[event.currentTarget.dataset.field] = event.target.value;
  }

  handleLogEmail() {
    if (!this.emailSubject) {
      this.setStatus("A subject is required.", true);
      return;
    }

    this.isSaving = true;
    logEmailApex({
      recordId: this.recordId,
      subject: this.emailSubject,
      toAddress: this.emailTo,
      body: this.emailBody
    })
      .then(() => {
        this.isEmailFormOpen = false;
        this.setStatus("Email logged on this record.", false);
        return refreshApex(this._activityResult);
      })
      .catch((error) => {
        this.setStatus(
          error?.body?.message || "The email could not be logged.",
          true
        );
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  // ========================================================================
  // Chatter
  // ========================================================================

  get feedEntries() {
    const entries = (this.feedData && this.feedData.entries) || [];
    const ordered =
      this.feedSort === "oldest" ? [...entries].reverse() : [...entries];

    return ordered.map((entry) => {
      const comments = this.commentsByFeedItem[entry.id] || [];
      return {
        ...entry,
        whenLabel: this.formatDateTime(entry.createdDate),
        hasHeader: Boolean(entry.title),
        hasBody: Boolean(entry.body),
        hasChanges: Boolean(entry.changes && entry.changes.length),
        changes: (entry.changes || []).map((change, index) => ({
          ...change,
          key: `${entry.id}-${index}`
        })),
        comments,
        hasComments: comments.length > 0,
        commentCount: comments.length,
        isCommentOpen: this.openCommentFor === entry.id,
        commentDraft: this.commentDrafts[entry.id] || ""
      };
    });
  }

  get feedCount() {
    return this.feedEntries.length;
  }

  get feedCountLabel() {
    return this.feedCount === 1
      ? "1 Chatter Feed Item"
      : `${this.feedCount} Chatter Feed Items`;
  }

  get isFeedLoading() {
    return Boolean(this.recordId) && !this.feedData && !this.feedError;
  }

  get showFeedEmpty() {
    return Boolean(this.feedData) && this.feedCount === 0;
  }

  get feedSortOptions() {
    return [
      {
        value: "newest",
        label: "Latest posts",
        selected: this.feedSort === "newest"
      },
      {
        value: "oldest",
        label: "Oldest posts",
        selected: this.feedSort === "oldest"
      }
    ];
  }

  /**
   * The footer only makes sense once the feed has arrived and holds something.
   * Keying it off "not empty" would print "End of Feed • 0 Chatter Feed Items"
   * for as long as the read takes.
   */
  get showFeedEnd() {
    return Boolean(this.feedData) && this.feedCount > 0;
  }

  get canShare() {
    return Boolean(this.postBody && this.postBody.trim()) && !this.isSaving;
  }

  handleFeedSortChange(event) {
    this.feedSort = event.target.value;
  }

  handleRefreshFeed() {
    this.clearStatus();
    if (this._feedResult) {
      refreshApex(this._feedResult);
    }
  }

  handlePostBodyChange(event) {
    this.postBody = event.target.value;
  }

  handleShare() {
    if (!this.canShare) {
      return;
    }

    this.isSaving = true;
    postToFeedApex({ recordId: this.recordId, body: this.postBody })
      .then(() => {
        this.postBody = "";
        this.setStatus("Posted.", false);
        return refreshApex(this._feedResult);
      })
      .catch((error) => {
        this.setStatus(error?.body?.message || "The post could not be saved.", true);
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  handleToggleComment(event) {
    const id = event.currentTarget.dataset.id;
    this.openCommentFor = this.openCommentFor === id ? null : id;
  }

  handleCommentDraft(event) {
    const id = event.currentTarget.dataset.id;
    this.commentDrafts = { ...this.commentDrafts, [id]: event.target.value };
  }

  handleAddComment(event) {
    const id = event.currentTarget.dataset.id;
    const body = this.commentDrafts[id];

    if (!body || !body.trim()) {
      return;
    }

    this.isSaving = true;
    addFeedCommentApex({ feedItemId: id, body })
      .then(() => {
        this.commentDrafts = { ...this.commentDrafts, [id]: "" };
        this.openCommentFor = null;
        this.setStatus("Comment added.", false);
        /*
         * The comments read has to be refreshed directly. Rebuilding
         * feedItemIds would not do it: LWC compares a wire configuration by
         * value, and the post ids are exactly what has NOT changed.
         */
        return refreshApex(this._commentsResult);
      })
      .catch((error) => {
        this.setStatus(
          error?.body?.message || "The comment could not be saved.",
          true
        );
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  // ========================================================================
  // Helpers
  // ========================================================================

  formatDateTime(value) {
    const parsed = parseDateTime(value);
    return parsed ? DATE_TIME_FORMAT.format(parsed) : "";
  }

  get statusClass() {
    return this.statusIsError
      ? "arc-activity__status arc-activity__status_error"
      : "arc-activity__status";
  }

  setStatus(message, isError) {
    this.statusMessage = message;
    this.statusIsError = isError;
  }

  clearStatus() {
    this.statusMessage = undefined;
    this.statusIsError = false;
  }

  /** A route inside ARC, which needs the site's own base path in front of it. */
  navigateWithin(route) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: `${communityBasePath}${route}` }
    });
  }

  /** Anything outside ARC opens in its own tab rather than replacing the site. */
  openExternal(url) {
    if (!url) {
      return;
    }
    window.open(url, "_blank", "noopener");
  }
}