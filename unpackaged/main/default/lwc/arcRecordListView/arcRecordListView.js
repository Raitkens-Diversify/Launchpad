/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Forked from Vestolio's arcListView for ARC. Launchpad's own shared arcListView
 * (list-view pinning + server-side label resolution) is untouched -- ARC gets
 * this saved-view-tabs/group-by/chart-cards/pill-column design as a separate
 * component instead.
 */
import { LightningElement, api, wire, track } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import { refreshApex } from "@salesforce/apex";
import {
  getListInfosByObjectName,
  getListInfoByName,
  getListRecordsByName,
  getListObjectInfo,
  createListInfo,
  updateListInfoByName,
  deleteListInfo
} from "lightning/uiListsApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import searchRecords from "@salesforce/apex/ArcRecordSearchController.searchRecords";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import {
  buildRecordNavigationReference,
  resolveRecordUrl,
  usesQueryParamRecordRoute
} from "c/recordNavigationCommunityUtils";

/**
 * Real Phosphor icons (regular weight), rendered as CSS masks so one file
 * covers default/hover/active — the glyph takes its colour from currentColor.
 * Keys mirror the Figma layers, e.g. "Icon Phosphor / FunnelSimple".
 *
 * These land as custom properties on the host rather than inline `style=`
 * bindings, so the stylesheet owns which glyph each class uses and the markup
 * stays free of per-element style attributes.
 */
const ICON_FILES = {
  table: "table",
  cards: "cards-three",
  chart: "chart-pie",
  search: "magnifying-glass",
  group: "stack",
  filter: "funnel-simple",
  plus: "plus",
  caret: "caret-down",
  bookmark: "bookmark-simple",
  close: "x",
  columns: "columns-plus-right",
  check: "check",
  user: "user-fill"
};

/**
 * Objects whose rows are people, or the household standing in for one. See the
 * matching set in nexSListView — the person glyph is an avatar on a contact and
 * noise beside a case number.
 */
const AVATAR_OBJECT_API_NAMES = new Set([
  "Account",
  "Contact",
  "Lead",
  "User"
]);

/**
 * Row menu (Figma "⚡ Row actions menu cell", 797:120088). The design specifies
 * the cell but not its contents, so these are the actions this app can actually
 * carry out: records are edited inline on the detail page, so Edit opens that.
 */
const ROW_ACTIONS = [
  { name: "edit", label: "Edit", iconName: "utility:edit" },
  { name: "newtab", label: "Open in new tab", iconName: "utility:new_window" },
  { name: "copy", label: "Copy link", iconName: "utility:copy_to_clipboard" }
];

const LIST_VIEW_FETCH_SIZE = 2000;
const TABLE_PAGE_SIZE = 25;
const TABLE_PAGE_SIZE_OPTIONS = [10, 25, 50];
const SEARCH_DEBOUNCE_MS = 275;
/**
 * Page size for the opt-in "server search" mode (see enableServerSearch):
 * a small, fast first fetch instead of the default LIST_VIEW_FETCH_SIZE=2000
 * fetch-then-filter-client-side pattern. Real filtering/search in this mode
 * runs server-side via ArcRecordSearchController, keyset-paginated (SOQL's
 * own OFFSET is capped at 2000 same as the UI API, so pages are fetched via
 * "WHERE Id > last id" instead).
 */
const SERVER_SEARCH_PAGE_SIZE = 100;
/**
 * Fallback tab count used only until the strip has measured itself once
 * (first paint, before renderedCallback runs). After that, visibility is
 * decided by actual pixel width via measureTabsIfNeeded/TAB_FIT_RATIO --
 * label lengths vary too much across objects for a fixed count to be right.
 */
const MAX_VISIBLE_TABS = 5;
/** Tabs stay in the strip only while they leave this fraction free for
 * "More" (and whatever trails it); past that point they overflow. */
const TAB_FIT_RATIO = 0.7;

const OPERATOR_LABELS = {
  Equals: "Equals",
  NotEqual: "Does not equal",
  Contains: "Contains",
  NotContain: "Does not contain",
  StartsWith: "Starts with",
  GreaterThan: "Greater than",
  GreaterOrEqual: "Greater or equal",
  LessThan: "Less than",
  LessOrEqual: "Less or equal",
  Includes: "Includes",
  Excludes: "Excludes",
  Within: "Within"
};

let filterKeyCounter = 0;

/** Deep-link params the site's navigation uses, e.g. ?c__tabId=tab2 */
const TAB_PARAM_KEYS = ["c__tabId", "tabId"];

const resolveTabParam = (pageRef) => {
  const state = pageRef?.state || {};

  for (const key of TAB_PARAM_KEYS) {
    if (state[key]) {
      return String(state[key]);
    }
  }

  const params = new URLSearchParams(
    typeof window !== "undefined" ? window.location.search || "" : ""
  );

  for (const key of TAB_PARAM_KEYS) {
    const value = params.get(key);
    if (value) {
      return value;
    }
  }

  // Native Experience Cloud tabsets use a generated tabs-<id> param.
  for (const [key, value] of params.entries()) {
    if (key.startsWith("tabs-") && value) {
      return value;
    }
  }

  return "";
};

const PILL_TONE_COUNT = 8;

/**
 * Stable value → tone mapping for pill columns. The same value always lands on
 * the same colour (across rows, pages and reloads) because the tone is derived
 * from the text itself rather than from row order.
 */
const pillToneClass = (value) => {
  const text = value == null ? "" : `${value}`.trim();

  if (!text) {
    return "div-table-badge div-table-badge--empty";
  }

  let hash = 0;
  for (let index = 0; index < text.length; index += 1) {
    hash = (hash * 31 + text.charCodeAt(index)) % 100000007;
  }

  return `div-table-badge div-table-badge--tone-${(hash % PILL_TONE_COUNT) + 1}`;
};

/** Strips currency/percent formatting so "$8,200,000" compares as a number. */
const toComparableNumber = (value) => {
  if (value == null || value === "") {
    return null;
  }
  const numeric = Number(String(value).replace(/[^0-9.eE+-]/g, ""));
  return Number.isFinite(numeric) ? numeric : null;
};

const DAY_MS = 24 * 60 * 60 * 1000;

/** Date-only field values (e.g. Birthdate) are already a bare "YYYY-MM-DD". */
const formatLocalDateKey = (rawValue) => {
  if (!rawValue) {
    return "";
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(rawValue)) {
    return rawValue;
  }
  const date = new Date(rawValue);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

const startOfLocalDay = (dateKey) => {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day).getTime();
};

/**
 * Date-picker filtering compares whole calendar days (the picker has no time
 * component), so every operator treats the picked day as a single unit —
 * "Greater than" means strictly after that whole day, "Less or equal" means
 * through the end of it, etc. — rather than a millisecond-precise cutoff.
 */
const dateRowMatchesFilter = (row, fieldApiName, operator, operandDateKey) => {
  const rawValue = row[`${fieldApiName}__raw`];
  const rowDayKey = row[`${fieldApiName}__dayKey`];

  if (!rawValue || !rowDayKey || !/^\d{4}-\d{2}-\d{2}$/.test(operandDateKey)) {
    return false;
  }

  const rowTime = new Date(rawValue).getTime();
  const targetStart = startOfLocalDay(operandDateKey);
  const targetNextStart = targetStart + DAY_MS;

  switch (operator) {
    case "Equals":
      return rowDayKey === operandDateKey;
    case "NotEqual":
      return rowDayKey !== operandDateKey;
    case "GreaterThan":
      return rowTime >= targetNextStart;
    case "GreaterOrEqual":
      return rowTime >= targetStart;
    case "LessThan":
      return rowTime < targetStart;
    case "LessOrEqual":
      return rowTime < targetNextStart;
    default:
      return rowDayKey === operandDateKey;
  }
};

const DATE_OPERATOR_KEYS = [
  "Equals",
  "NotEqual",
  "GreaterThan",
  "GreaterOrEqual",
  "LessThan",
  "LessOrEqual"
];

/**
 * LWR list-view experience: saved-view tabs, view-mode switch, search,
 * group-by, filter chips, and the save/overwrite view flow, backed by
 * uiListsApi.
 */
export default class ArcRecordListView extends NavigationMixin(LightningElement) {
  static renderMode = "light";

  /** Object API name, e.g. Envelope__c */
  @api objectApiName = "Envelope__c";
  /** Page title shown in the header */
  @api title = "Envelopes";
  /** Supporting line under the title */
  @api subtitle = "";
  /** Label of the header's primary action; blank hides the button */
  @api newRecordLabel = "";
  /** Default list view API name when first loading */
  @api defaultListViewApiName = "All";
  /**
   * The tab strip's fixed views. Either a JSON array, which also carries each
   * tab's own page heading:
   *   [{"view":"AllAccounts","label":"All Contacts","title":"Contacts",
   *     "subtitle":"…","action":"Add Contact"}]
   * or the short form `apiName=Label` pairs separated by commas. Blank falls
   * back to this placement's own view plus anything the user saves here.
   */
  @api viewTabs = "";
  /**
   * Comma-separated field API names rendered as colour-coded pills instead of
   * plain text, e.g. `BillingState`. Each distinct value gets its own tone.
   */
  @api pillFields = "";
  /**
   * Ordered, comma-separated field API names to show by default, e.g.
   * `Name,Check__r.Name,Amount__c`. Can name fields the list view's own
   * Setup config doesn't carry at all (their label is resolved from the
   * object's own field describe) — not just reorder/hide what the view
   * already returns. Blank leaves the view's own column set/order alone.
   */
  @api defaultColumns = "";
  /**
   * Opt-in pilot mode, scoped per list view rather than per placement: one
   * arcRecordListView instance handles every tab on its page (Account_List's
   * 7 tabs are one instance, not seven), so a plain on/off flag would turn
   * this on for all of them. Instead this is a comma-separated list of the
   * list view API names it should apply to, e.g. "AllAccounts" -- any tab
   * not named here keeps today's behavior exactly: one fetch of up to
   * LIST_VIEW_FETCH_SIZE=2000 rows via lightning/uiListsApi, filtered/
   * grouped/searched entirely client-side. For a named tab, the initial
   * fetch is a small keyset-paginated page via ArcRecordSearchController
   * instead (fast first paint even on a huge unfiltered view), plus an
   * async total-record count. Filter chips, the search box, and group-by
   * still apply live over whatever's currently loaded for instant feedback
   * -- but on Enter (search box or a filter chip's value), a real server
   * re-query runs with that criteria applied, replacing the loaded rows
   * with the actual matching set instead of just re-slicing what happened
   * to be on the first page.
   */
  @api serverSearchListViews = "";

  get enableServerSearch() {
    return this.serverSearchListViewNames.includes(this.selectedListViewApiName);
  }

  get serverSearchListViewNames() {
    return (this.serverSearchListViews || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean);
  }

  /** Every field the object describe knows about, keyed by API name. */
  objectFieldInfo = null;
  /** Which view `applyDefaultColumns` last hid columns for — see there. */
  _defaultedListViewApiName;
  /** View a drag-reorder has already decided the column order for — see applyDefaultColumns. */
  _userReorderedListViewApiName = "";

  @track listViews = [];
  @track columns = [];
  @track tableRows = [];
  @track activeFilters = [];

  selectedListViewApiName;
  errorMessage;
  isLoading = true;
  viewMode = "table";
  searchTerm = "";
  groupFieldApiName = "";
  openPopover = "";
  fieldMenuSearch = "";
  columnMenuSearch = "";
  /** Field API names switched off in the Table Columns dropdown. */
  @track hiddenColumnFields = [];
  showSaveViewModal = false;
  saveViewName = "";
  saveViewError;
  isSavingView = false;
  showDeleteViewModal = false;
  deleteViewTarget;
  deleteViewError;
  isDeletingView = false;
  filterLogicString = "";
  objectColumns = [];
  currentListViewLabel = "";
  _savedSignature = "";
  _adoptedListViewApiName = "";
  /** Views saved from this component this session, so they tab up immediately. */
  _createdViewApiNames = new Set();
  /** Overflow (configured) tabs a "More" click has brought into the strip for
   * this session -- see promoteTab. */
  _promotedTabValues = [];
  /** Natural fit count from the last width measurement -- see
   * measureTabsIfNeeded. Starts at the fixed fallback until first measured. */
  _measuredVisibleCount = MAX_VISIBLE_TABS;
  _tabMeasureSignature = "";
  _appliedTabParam = "";
  _pageRef;
  _searchTimer;
  _stylesLoaded = false;
  _listInfosWire;
  _listInfoWire;
  _recordsWire;
  _listObjectInfoWire;

  // ---- Server search mode state ------------------------------------------
  _serverSearchGeneration = 0;
  _lastConfirmedSearchSignature = "";
  _serverSearchedListViewApiName = "";

  connectedCallback() {
    this.applyIconVariables();
    if (!this.selectedListViewApiName) {
      this.selectedListViewApiName = this.defaultListViewApiName;
    }
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch(() => {
        /* Theme CSS optional if inline/component CSS covers layout */
      });
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this._searchTimer);
    this._tabResizeObserver?.disconnect();
  }

  renderedCallback() {
    this.observeTabStripResize();
    this.measureTabsIfNeeded();
  }

  /**
   * The strip's own clientWidth is stable regardless of how many tabs are
   * currently rendered inside it -- it's a flex item stretched by its
   * ancestor header (align-items: stretch, column direction), not sized by
   * its children -- so a resize here always means the viewport/layout
   * actually changed, never "we changed the tab count and now need to
   * measure again" (that's covered by measureTabsIfNeeded's own signature
   * check instead, since a resize here wouldn't fire for it).
   */
  observeTabStripResize() {
    if (this._tabResizeObserver) {
      return;
    }
    // Light DOM (lwc:render-mode="light") has no shadow root, so there's no
    // this.template here -- query the host element directly instead.
    const container = this.querySelector(".arc-record-list-view__tabs");
    if (!container || typeof ResizeObserver === "undefined") {
      return;
    }
    this._tabResizeObserver = new ResizeObserver(() => {
      this._tabMeasureSignature = "";
      this.measureTabsIfNeeded();
    });
    this._tabResizeObserver.observe(container);
  }

  /**
   * Decides how many tabs fit before "More" by measuring real rendered
   * widths off the hidden measuring layer (see the .arc-record-list-view__
   * tab-measure template block) rather than guessing at label pixel widths
   * -- label length varies too much across objects for a fixed tab count
   * to make sense (see MAX_VISIBLE_TABS comment). Keeps ~30% of the strip
   * free for "More" plus whatever trails it (TAB_FIT_RATIO).
   */
  measureTabsIfNeeded() {
    const container = this.querySelector(".arc-record-list-view__tabs");
    const measure = this.querySelector(".arc-record-list-view__tab-measure");
    if (!container || !measure) {
      return;
    }

    // Includes selectedListViewApiName because the active tab is the only
    // one that can carry a delete-x (see buildTabs' showDelete), so which
    // tab is active can itself change the widths being measured.
    const signature = `${container.clientWidth}|${this.selectedListViewApiName}|${this.tabListViews
      .map((tab) => tab.value)
      .join(",")}`;
    if (signature === this._tabMeasureSignature) {
      return;
    }
    this._tabMeasureSignature = signature;

    const items = Array.from(
      measure.querySelectorAll("[data-measure-value]")
    );
    if (!items.length) {
      return;
    }
    const moreButton = measure.querySelector("[data-measure-more]");
    const moreWidth = moreButton ? moreButton.offsetWidth : 0;
    const availableWidth = container.clientWidth * TAB_FIT_RATIO;

    let used = 0;
    let fitCount = 0;
    for (let i = 0; i < items.length; i += 1) {
      const width = items[i].offsetWidth;
      const isLast = i === items.length - 1;
      const reserve = isLast ? 0 : moreWidth;
      if (fitCount > 0 && used + width + reserve > availableWidth) {
        break;
      }
      used += width;
      fitCount += 1;
    }

    const nextCount = Math.max(1, fitCount);
    if (nextCount !== this._measuredVisibleCount) {
      this._measuredVisibleCount = nextCount;
    }
  }

  /**
   * Honours ?c__tabId=tab2 style deep links from the site navigation. The tab
   * strip lives in this component now, so the param is resolved here instead
   * of by a separate helper component clicking into the DOM.
   */
  @wire(CurrentPageReference)
  handlePageReference(pageRef) {
    this._pageRef = pageRef;
    this.applyTabFromUrl();
  }

  applyTabFromUrl() {
    const target = resolveTabParam(this._pageRef);
    const tabs = this.configuredTabs;

    if (!target || !tabs.length || target === this._appliedTabParam) {
      return;
    }

    const normalized = target.toLowerCase().replace(/\s+/g, "");
    const matched =
      tabs.find(
        (tab) =>
          tab.value.toLowerCase() === normalized ||
          tab.label.toLowerCase().replace(/\s+/g, "") === normalized
      ) || tabs[parseInt(target.replace(/^\D+/g, ""), 10) - 1];

    if (!matched) {
      return;
    }

    this._appliedTabParam = target;

    if (matched.value !== this.selectedListViewApiName) {
      this.selectTabView(matched.value);
    }
  }

  // ---- Icons -------------------------------------------------------------

  /** Publishes every Phosphor glyph as a `--arc-icon-*` custom property. */
  applyIconVariables() {
    for (const [key, file] of Object.entries(ICON_FILES)) {
      const url = `${NEXS_ICONS}/${file}.svg`;
      this.style.setProperty(`--arc-icon-${key}`, `url('${url}')`);
      // Warm the HTTP cache: a mask-image is only fetched when something
      // first uses it, so a glyph that appears on interaction (a menu
      // check, a chip's clear button) would otherwise paint late.
      this.preloadIcon(url);
    }
  }

  preloadIcon(url) {
    if (typeof Image === "undefined") {
      return;
    }

    const image = new Image();
    image.src = url;
  }

  /** Empty for a non-person object, which is how the table draws no avatar. */
  get avatarIconUrl() {
    return AVATAR_OBJECT_API_NAMES.has(this.objectApiName)
      ? `${NEXS_ICONS}/${ICON_FILES.user}.svg`
      : "";
  }

  get columnSettingsIconUrl() {
    return `${NEXS_ICONS}/${ICON_FILES.columns}.svg`;
  }

  // ---- Header + tabs -----------------------------------------------------

  /** Without the tab strip the header owns its own bottom padding. */
  get pageHeaderClass() {
    return this.hasViewTabs
      ? "arc-record-list-view__page-header"
      : "arc-record-list-view__page-header arc-record-list-view__page-header--no-tabs";
  }

  /** Heading text follows the active tab, falling back to the page defaults. */
  get headingTitle() {
    return this.activeConfiguredTab?.heading || this.title;
  }

  get headingSubtitle() {
    const tab = this.activeConfiguredTab;
    return tab ? tab.tagline : this.subtitle;
  }

  get headingActionLabel() {
    const tab = this.activeConfiguredTab;
    return tab ? tab.action : this.newRecordLabel;
  }

  get hasSubtitle() {
    return Boolean(this.headingSubtitle);
  }

  get hasNewRecordAction() {
    return Boolean(this.headingActionLabel);
  }

  /**
   * The strip shows this placement's own view plus views the user saved here —
   * not the org's whole list-view catalogue. The site's page tabs already
   * provide top-level navigation; duplicating it here fights the design.
   */
  get tabListViews() {
    const created = this._createdViewApiNames;
    const configured = this.configuredTabs;

    if (configured.length) {
      // Configured tabs lead, in the order given; views saved here follow.
      const pinned = new Set(configured.map((tab) => tab.value));
      const saved = this.listViews.filter(
        (lv) =>
          !pinned.has(lv.value) &&
          (created.has(lv.value) || lv.visibility === "Private")
      );

      return [...configured, ...saved];
    }

    return this.listViews.filter(
      (lv) =>
        lv.value === this.defaultListViewApiName ||
        lv.value === this.selectedListViewApiName ||
        lv.visibility === "Private" ||
        created.has(lv.value)
    );
  }

  /**
   * Parses the `viewTabs` property. The label after `=` wins over the list
   * view's own name so the strip can read "All Contacts" where the org calls
   * the view "All Accounts".
   */
  get configuredTabs() {
    const raw = (this.viewTabs || "").trim();
    if (!raw) {
      return [];
    }

    const entries = raw.startsWith("[")
      ? this.parseJsonTabs(raw)
      : raw
          .split(",")
          .map((entry) => entry.trim())
          .filter(Boolean)
          .map((entry) => {
            const [apiName, ...labelParts] = entry.split("=");
            return {
              view: apiName.trim(),
              label: labelParts.join("=").trim()
            };
          });

    return entries
      .filter((entry) => entry.view)
      .map((entry) => {
        const known = this.listViews.find((lv) => lv.value === entry.view);

        return {
          ...(known || {}),
          value: entry.view,
          label: entry.label || known?.label || entry.view,
          heading: entry.title || "",
          tagline: entry.subtitle || "",
          action: entry.action || "",
          /* Ordered field API names (optionally "field=Label") this tab
             shows by default -- see configuredColumnEntries. Only the JSON
             viewTabs form carries this; the comma-pair form has no room
             for a third value per entry. */
          columns: entry.columns || ""
        };
      });
  }

  parseJsonTabs(raw) {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcRecordListView] viewTabs is not valid JSON", error);
      return [];
    }
  }

  /** The configured tab currently selected, if any. */
  get activeConfiguredTab() {
    return this.configuredTabs.find(
      (tab) => tab.value === this.selectedListViewApiName
    );
  }

  /**
   * A strip holding a single tab is pure duplication of the site's own page
   * tab, so it stays hidden until there is a second view to switch to.
   */
  get hasViewTabs() {
    return this.tabListViews.length > 1;
  }

  /**
   * Every tab, in strip order, with isActive/showDelete/showUnpromote/
   * className resolved. The measuring layer in the template renders this
   * whole list (invisibly) so measureTabsIfNeeded can read real pixel
   * widths -- including the delete-button width on whichever tab happens
   * to be active -- before the visible/overflow split is decided.
   */
  get allBuiltTabs() {
    return this.buildTabs(this.tabListViews);
  }

  /**
   * Splits allBuiltTabs into what the strip shows up front versus what
   * waits behind "More": the natural fit from the last width measurement
   * (_measuredVisibleCount), plus any tab a "More" click has promoted out
   * of it (see promoteTab). A promoted tab is appended after the natural
   * ones rather than displacing one of them, so bringing a tab forward
   * never costs the user a tab they could already see.
   */
  get orderedBuiltTabs() {
    const all = this.allBuiltTabs;
    const natural = all.slice(0, this._measuredVisibleCount);
    const naturalValues = new Set(natural.map((tab) => tab.value));
    const promotedExtra = this._promotedTabValues
      .filter((value) => !naturalValues.has(value))
      .map((value) => all.find((tab) => tab.value === value))
      .filter(Boolean);

    return {
      visible: [...natural, ...promotedExtra],
      overflow: all.filter(
        (tab) =>
          !naturalValues.has(tab.value) &&
          !this._promotedTabValues.includes(tab.value)
      )
    };
  }

  get visibleTabs() {
    return this.orderedBuiltTabs.visible;
  }

  get overflowTabs() {
    return this.orderedBuiltTabs.overflow;
  }

  get hasOverflowTabs() {
    return this.overflowTabs.length > 0;
  }

  buildTabs(listViews) {
    const configuredValues = new Set(this.configuredTabs.map((tab) => tab.value));
    return listViews.map((lv) => {
      const isActive = lv.value === this.selectedListViewApiName;
      return {
        ...lv,
        isActive,
        // Only the active view can be closed, and only when it isn't one of
        // this placement's configured tabs, or the object's own default view
        // -- those stay put no matter which one is on screen (Vestolio's
        // tab-closability rule). The defaultListViewApiName check matters
        // even when viewTabs is unset: with no configured tabs at all,
        // configuredValues is empty and would otherwise protect nothing.
        showDelete:
          isActive &&
          !configuredValues.has(lv.value) &&
          lv.value !== this.defaultListViewApiName,
        deleteAriaLabel: `Delete view ${lv.label}`,
        showUnpromote: this._promotedTabValues.includes(lv.value),
        unpromoteAriaLabel: `Remove ${lv.label} from the tab strip`,
        tabIndex: isActive ? 0 : -1,
        className: isActive
          ? "arc-record-list-view__tab arc-record-list-view__tab--active"
          : "arc-record-list-view__tab"
      };
    });
  }

  get showMoreTabsMenu() {
    return this.openPopover === "moreTabs";
  }

  get deleteViewTargetLabel() {
    return this.deleteViewTarget?.label || "";
  }

  // ---- View mode ---------------------------------------------------------

  get isTableView() {
    return this.viewMode === "table";
  }

  get isCardsView() {
    return this.viewMode === "cards";
  }

  get isChartView() {
    return this.viewMode === "chart";
  }

  get tableSegmentClass() {
    return this.segmentClass("table");
  }

  get cardsSegmentClass() {
    return this.segmentClass("cards");
  }

  get chartSegmentClass() {
    return this.segmentClass("chart");
  }

  segmentClass(mode) {
    return this.viewMode === mode
      ? "arc-record-list-view__segment arc-record-list-view__segment--active"
      : "arc-record-list-view__segment";
  }

  // ---- Table wiring ------------------------------------------------------

  get pageSizeNumber() {
    return TABLE_PAGE_SIZE;
  }

  get hasColumns() {
    return this.columns && this.columns.length > 0;
  }

  get visibleColumnDefs() {
    return (this.columns || []).filter(
      (col) => !this.hiddenColumnFields.includes(col.fieldApiName)
    );
  }

  /** Field API names configured to render as pills. */
  get pillFieldNames() {
    return (this.pillFields || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean);
  }

  get tableColumns() {
    const pillFieldNames = this.pillFieldNames;

    return this.visibleColumnDefs.map((col, index) => ({
      label: col.label,
      fieldName: col.fieldApiName,
      type: pillFieldNames.includes(col.fieldApiName)
        ? "pill"
        : this.resolveColumnType(col.fieldApiName),
      sortable: true,
      sortType: "text",
      isLink: index === 0
    }));
  }

  get rowActions() {
    return ROW_ACTIONS;
  }

  /**
   * `rowaction` carries { action, row }; the row is the record shape this
   * component builds, so `id` is the record id.
   */
  async handleRowAction(event) {
    const { action, row } = event.detail || {};
    const recordId = row?.id;

    if (!action?.name || !recordId) {
      return;
    }

    if (action.name === "newtab") {
      await this.openRecordInNewTab(recordId);
      return;
    }

    if (action.name === "copy") {
      await this.copyRecordLink(recordId);
      return;
    }

    // Edit — this app edits records inline on the detail page.
    const reference = buildRecordNavigationReference(
      recordId,
      this.objectApiName,
      { useQueryParam: usesQueryParamRecordRoute(this.objectApiName) }
    );

    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  /**
   * Opens a record in a new browser tab. Ported locally from Vestolio's
   * recordNavigationUtils.openRecordInNewTab (which recordNavigationCommunityUtils
   * doesn't re-export) rather than adding a shared-file export -- keeps this
   * fork's footprint at zero shared-file changes. arcRecordListView is
   * Experience-Cloud-only (no lightning__AppPage/RecordPage target), so only
   * the browser-tab half of that helper ever applies; its console-workspace-tab
   * branch is dead code here and wasn't carried over. Matches the original
   * call site exactly, including not passing objectApiName.
   */
  async openRecordInNewTab(recordId) {
    if (!recordId) {
      return;
    }
    const url = await resolveRecordUrl(this, recordId);
    if (!url) {
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  }

  async copyRecordLink(recordId) {
    try {
      const path = await resolveRecordUrl(this, recordId, this.objectApiName);

      if (!path) {
        return;
      }

      const absolute = new URL(path, window.location.origin).href;
      await navigator.clipboard.writeText(absolute);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcRecordListView] Could not copy the record link", error);
    }
  }

  get enableTablePagination() {
    return true;
  }

  get tablePageSizeOptions() {
    return TABLE_PAGE_SIZE_OPTIONS;
  }

  get listViewFetchSize() {
    return LIST_VIEW_FETCH_SIZE;
  }

  /**
   * getListRecordsByName's own listViewApiName is a required identifier --
   * an undefined value is the standard, documented way to keep a wire
   * adapter from firing at all (the same pattern this file's other wires
   * already use, gated on $_recordId-style values). In server search mode
   * the row data comes from runServerSearch/ArcRecordSearchController
   * instead, so this suppresses the old fetch-2000-rows call entirely
   * rather than letting it run to waste alongside the new one.
   */
  get wireListViewApiName() {
    return this.enableServerSearch ? undefined : this.selectedListViewApiName;
  }

  get linkQueryParamObjectApiNames() {
    return usesQueryParamRecordRoute(this.objectApiName)
      ? this.objectApiName
      : "";
  }

  get tableEmptyMessage() {
    return this.isLoading ? "Loading…" : "No records to display.";
  }

  get hasError() {
    return !!this.errorMessage;
  }

  /**
   * Fields the row map must carry: the display columns plus any field only a
   * filter or the group-by references, so both can evaluate off the row.
   */
  get supportingFieldApiNames() {
    const displayed = new Set(this.columns.map((col) => col.fieldApiName));
    const extras = new Set();

    if (this.groupFieldApiName && !displayed.has(this.groupFieldApiName)) {
      extras.add(this.groupFieldApiName);
    }

    this.activeFilters.forEach((filter) => {
      if (filter.fieldApiName && !displayed.has(filter.fieldApiName)) {
        extras.add(filter.fieldApiName);
      }
    });

    return [...extras];
  }

  get optionalFields() {
    if (!this.columns.length) {
      return undefined;
    }
    const fields = [
      ...this.columns.map((col) => col.fieldApiName),
      ...this.supportingFieldApiNames
    ].map((fieldApiName) => `${this.objectApiName}.${fieldApiName}`);
    const idField = `${this.objectApiName}.Id`;
    if (!fields.includes(idField)) {
      fields.unshift(idField);
    }
    return fields;
  }

  // ---- Client-side search + filters --------------------------------------

  get visibleRows() {
    const term = this.searchTerm.trim().toLowerCase();

    return this.tableRows.filter((row) => {
      if (
        !this.activeFilters.every((filter) =>
          this.rowMatchesFilter(row, filter)
        )
      ) {
        return false;
      }

      if (!term) {
        return true;
      }

      return this.columns.some((col) =>
        String(row[col.fieldApiName] ?? "")
          .toLowerCase()
          .includes(term)
      );
    });
  }

  rowMatchesFilter(row, filter) {
    const operand = (filter.operandValue || "").trim();

    if (!filter.fieldApiName || !operand) {
      return true;
    }

    if (this.isDateFieldApiName(filter.fieldApiName)) {
      return dateRowMatchesFilter(
        row,
        filter.fieldApiName,
        filter.operator,
        operand
      );
    }

    const rawValue = String(row[filter.fieldApiName] ?? "");
    const value = rawValue.toLowerCase();
    const target = operand.toLowerCase();
    const numericValue = toComparableNumber(rawValue);
    const numericTarget = toComparableNumber(operand);
    const bothNumeric = numericValue !== null && numericTarget !== null;
    // An adopted multi-value "equals" (e.g. a Households tab matching two
    // differently-typed record types both labeled "Household") arrives as
    // several labels joined with "; " (see adoptSavedFilters) -- a single
    // row can only carry one of those labels, never the joined string, so
    // Equals/NotEqual has to treat this as "matches any of them" the same
    // way the server's own IN/NOT IN resolution does, not a literal
    // string-equals against the whole joined value.
    const targetList = target
      .split(";")
      .map((piece) => piece.trim())
      .filter(Boolean);

    switch (filter.operator) {
      case "Equals":
        return bothNumeric
          ? numericValue === numericTarget
          : targetList.length > 1
            ? targetList.includes(value)
            : value === target;
      case "NotEqual":
        return bothNumeric
          ? numericValue !== numericTarget
          : targetList.length > 1
            ? !targetList.includes(value)
            : value !== target;
      case "NotContain":
        return !value.includes(target);
      case "StartsWith":
        return value.startsWith(target);
      case "GreaterThan":
        return bothNumeric ? numericValue > numericTarget : value > target;
      case "GreaterOrEqual":
        return bothNumeric ? numericValue >= numericTarget : value >= target;
      case "LessThan":
        return bothNumeric ? numericValue < numericTarget : value < target;
      case "LessOrEqual":
        return bothNumeric ? numericValue <= numericTarget : value <= target;
      default:
        return value.includes(target);
    }
  }

  get hasActiveFilters() {
    return this.activeFilters.length > 0;
  }

  get filterChips() {
    return this.activeFilters.map((filter) => ({
      ...filter,
      chipLabel: filter.operandValue
        ? `${filter.label}: ${filter.operandValue}`
        : filter.label,
      isOpen: this.openPopover === filter.key,
      hasValue: Boolean(filter.operandValue),
      isDateField: this.isDateFieldApiName(filter.fieldApiName),
      operatorOptions: this.buildOperatorOptions(filter.fieldApiName).map(
        (opt) => ({ ...opt, selected: opt.value === filter.operator })
      )
    }));
  }

  get cardRows() {
    return this.visibleRows.map((row) => ({
      key: row.id,
      title: row[this.columns[0]?.fieldApiName] || "—",
      fields: this.columns.slice(1).map((col) => ({
        key: `${row.id}-${col.fieldApiName}`,
        label: col.label,
        value: row[col.fieldApiName] || "—"
      }))
    }));
  }

  // ---- Group by ----------------------------------------------------------

  get groupButtonLabel() {
    return this.groupFieldApiName
      ? `Group: ${this.getDisplayedColumnLabel(this.groupFieldApiName)}`
      : "Group";
  }

  /**
   * arcDataTable buckets rows by exact value equality; for a date/datetime
   * group field that would put every row in its own group (down to the
   * second), so grouping by a date field points at its precomputed
   * calendar-day key instead of the raw field.
   */
  get effectiveGroupField() {
    if (
      this.groupFieldApiName &&
      this.isDateFieldApiName(this.groupFieldApiName)
    ) {
      return `${this.groupFieldApiName}__dayKey`;
    }
    return this.groupFieldApiName;
  }

  get groupButtonClass() {
    return this.groupFieldApiName
      ? "arc-record-list-view__button arc-record-list-view__button--neutral arc-record-list-view__button--on"
      : "arc-record-list-view__button arc-record-list-view__button--neutral";
  }

  get showGroupMenu() {
    return this.openPopover === "group";
  }

  get showFilterMenu() {
    return this.openPopover === "filter";
  }

  get showSaveViewMenu() {
    return this.openPopover === "saveView";
  }

  get hasOpenPopover() {
    return Boolean(this.openPopover);
  }

  /** Field list shared by the Group and Filter menus, narrowed by its search box. */
  get fieldMenuOptions() {
    const term = this.fieldMenuSearch.trim().toLowerCase();
    const source =
      this.openPopover === "group"
        ? this.groupableObjectColumns
        : this.filterableObjectColumns;

    const isGroupMenu = this.openPopover === "group";

    return source
      .filter((col) => !term || (col.label || "").toLowerCase().includes(term))
      .map((col) => {
        // Figma's menu row reserves a 16px checkmark slot on every row
        // and fills it for the current selection (Group / Dropdown,
        // 532:39348). For the filter menu "selected" means the field
        // already has a chip.
        const isSelected = isGroupMenu
          ? col.fieldApiName === this.groupFieldApiName
          : this.activeFilters.some(
              (filter) => filter.fieldApiName === col.fieldApiName
            );

        return {
          key: col.fieldApiName,
          label: col.label || col.fieldApiName,
          value: col.fieldApiName,
          isSelected,
          checkClass: isSelected
            ? "arc-record-list-view__menu-check arc-record-list-view__menu-check--on"
            : "arc-record-list-view__menu-check"
        };
      });
  }

  get hasFieldMenuOptions() {
    return this.fieldMenuOptions.length > 0;
  }

  /**
   * Group/Filter options are scoped to the table's own currently-displayed
   * columns (not the object's full field catalogue), so the menus can never
   * offer a field the user can't see on screen, and a column added via
   * defaultColumns or the Table Columns menu is picked up automatically. A
   * column with no matching describe metadata defaults to usable. Labels
   * come straight off the column def, the same source tableColumns reads,
   * so a menu entry can never say something different than its header.
   */
  get groupableObjectColumns() {
    return this.visibleColumnDefs
      .filter(
        (col) => this.getColumnMeta(col.fieldApiName)?.sortable !== false
      )
      .map((col) => this.toFieldMenuColumn(col));
  }

  get filterableObjectColumns() {
    return this.visibleColumnDefs
      .filter((col) => {
        const meta = this.getColumnMeta(col.fieldApiName);
        return meta ? Boolean(meta.filterable) : true;
      })
      .map((col) => this.toFieldMenuColumn(col));
  }

  toFieldMenuColumn(col) {
    return {
      fieldApiName: col.fieldApiName,
      label: col.label,
      dataType: this.getColumnMeta(col.fieldApiName)?.dataType
    };
  }

  // ---- Saved-view dirty state -------------------------------------------

  get currentSignature() {
    return JSON.stringify({
      group: this.groupFieldApiName,
      hiddenColumns: [...this.hiddenColumnFields].sort(),
      filters: this.activeFilters.map((filter) => ({
        field: filter.fieldApiName,
        operator: filter.operator,
        value: filter.operandValue
      }))
    });
  }

  get hasUnsavedViewChanges() {
    return this.currentSignature !== this._savedSignature;
  }

  /** A view created here can be overwritten; stock views only fork. */
  get canOverwriteCurrentView() {
    return (
      Boolean(this.selectedListViewApiName) && this.currentListViewIsPrivate
    );
  }

  get currentListViewIsPrivate() {
    return this._listInfoWire?.data?.visibility === "Private";
  }

  // ---- Wires -------------------------------------------------------------

  @wire(getListObjectInfo, { objectApiName: "$objectApiName" })
  wiredListObjectInfo(result) {
    this._listObjectInfoWire = result;
    const { data, error } = result;
    if (data) {
      this.objectColumns = data.columns || [];
    } else if (error) {
      this.objectColumns = [];
    }
  }

  /*
   * The field describe, purely for the labels of configured columns the list
   * view does not carry. getListObjectInfo would seem to be the closer fit,
   * but it only describes the columns its own list machinery offers and comes
   * back empty for some objects; the object describe always has every field.
   */
  @wire(getObjectInfo, { objectApiName: "$objectApiName" })
  wiredObjectInfo({ data }) {
    this.objectFieldInfo = data?.fields || null;
    // This wire and the list-info wire settle in either order, so rebuild once
    // the labels land rather than dropping the extras when it arrives second.
    if (this._listInfoWire?.data) {
      this.columns = this.applyDefaultColumns(
        this.baseDisplayColumns(this._listInfoWire.data)
      );
    }
  }

  @wire(getListInfosByObjectName, {
    objectApiName: "$objectApiName",
    pageSize: 100,
    recentListsOnly: false
  })
  wiredListInfos(result) {
    this._listInfosWire = result;
    const { data, error } = result;
    if (data) {
      const lists = data.lists || [];
      this.listViews = lists.map((item) => ({
        label: item.label || item.apiName,
        value: item.apiName,
        visibility: item.visibility
      }));
      if (
        !this.selectedListViewApiName ||
        !this.listViews.some((lv) => lv.value === this.selectedListViewApiName)
      ) {
        // Prefer the view this placement is pinned to over an arbitrary first.
        const pinned = this.listViews.find(
          (lv) => lv.value === this.defaultListViewApiName
        );
        this.selectedListViewApiName =
          pinned?.value ||
          this.listViews[0]?.value ||
          this.defaultListViewApiName;
      }
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
    }
  }

  @wire(getListInfoByName, {
    objectApiName: "$objectApiName",
    listViewApiName: "$selectedListViewApiName"
  })
  wiredListInfo(result) {
    this._listInfoWire = result;
    const { data, error } = result;
    if (data) {
      this.columns = this.applyDefaultColumns(this.baseDisplayColumns(data));
      this.currentListViewLabel = data.label || this.selectedListViewApiName;
      this.filterLogicString = data.filterLogicString || "";
      this.adoptSavedFilters(data.filteredByInfo || []);
      this.errorMessage = undefined;
      // Runs once per view (not on every wire re-emit, e.g. a refreshApex
      // mid-edit) -- columns and the view's own base filters (just adopted
      // above) are both ready by this point, which connectedCallback alone
      // can't guarantee since they arrive from this same wire.
      if (
        this.enableServerSearch &&
        this._serverSearchedListViewApiName !== this.selectedListViewApiName
      ) {
        this._serverSearchedListViewApiName = this.selectedListViewApiName;
        this.runServerSearch();
      }
    } else if (error && this.selectedListViewApiName) {
      this.errorMessage = this.reduceError(error);
      this.columns = [];
    }
  }

  /** The list view's own column set, as `wiredListInfo` always rendered it. */
  baseDisplayColumns(data) {
    const displayColumns = data.displayColumns || [];
    return displayColumns.map((col) => ({
      fieldApiName: col.fieldApiName || col.fieldName || col.label,
      label: col.label || col.fieldApiName
    }));
  }

  /**
   * Ordered {fieldApiName, label} pairs configured for the active tab, or
   * the placement-wide defaultColumns when the tab carries none of its own
   * -- each entry is "field" or "field=Label"; the label lets one tab call
   * the same field "Client Name" where another calls it "Household Name"
   * (or "Permanent State" vs plain "State" for BillingState), something no
   * single object-level field label could do across every tab at once.
   */
  get configuredColumnEntries() {
    const raw = this.activeConfiguredTab?.columns || this.defaultColumns || "";
    return raw
      .split(",")
      .map((entry) => entry.trim())
      .filter(Boolean)
      .map((entry) => {
        const [name, ...labelParts] = entry.split("=");
        return {
          fieldApiName: name.trim(),
          label: labelParts.join("=").trim()
        };
      })
      .filter((entry) => entry.fieldApiName);
  }

  /** Ordered default columns configured for the active tab. */
  get configuredDefaultColumns() {
    return this.configuredColumnEntries.map((entry) => entry.fieldApiName);
  }

  /**
   * Configured columns the list view itself does not return.
   *
   * `defaultColumns` reads as "the columns this page shows", but it could only
   * ever reorder and hide what the list view already carried — naming a field
   * the view omitted dropped it silently. The record payload is fetched with
   * explicit optionalFields rather than the view's own column set, so the
   * value is there for the asking; only the label has to come from somewhere,
   * and the object field describe already has every field.
   *
   * A name that is neither in the view nor on the object (a typo, or a
   * relationship path the object info does not describe) still drops out
   * rather than rendering a column of blanks under a guessed heading.
   */
  buildExtraConfiguredColumns(existing) {
    const known = new Set(existing.map((col) => col.fieldApiName));
    return [...new Set(this.configuredDefaultColumns)]
      .filter((name) => !known.has(name))
      .map((name) => {
        const label = this.resolveFieldLabel(name);
        return label ? { fieldApiName: name, label } : null;
      })
      .filter(Boolean);
  }

  /**
   * The column heading for a field API name. A dotted path is described by its
   * last hop on the related object, which this component cannot see, so it
   * falls back to the relationship's own label ("Financial Advisor Team" for
   * Financial_Advisor_Team__r.Name) and finally to a humanized API name.
   */
  resolveFieldLabel(fieldApiName) {
    const fields = this.objectFieldInfo;
    if (!fields) {
      return "";
    }

    if (fields[fieldApiName]) {
      return fields[fieldApiName].label || fieldApiName;
    }

    const [relationship] = String(fieldApiName).split(".");
    const owner = Object.values(fields).find(
      (field) => field.relationshipName === relationship
    );
    if (owner) {
      return owner.label || relationship;
    }

    return this.getColumnMeta(fieldApiName)?.label || "";
  }

  /**
   * Puts the configured columns first, in the configured order (applying
   * this tab's own label override where one is given), and switches the
   * rest off. The unconfigured ones stay in `columns` so the Table
   * Columns dropdown still offers them — hiding is a default, not a deletion.
   *
   * Guarded on the view actually changing: this wire re-emits from cache
   * (e.g. a refreshApex), and re-seeding on every emit would undo a column
   * the user had just switched back on via that dropdown.
   */
  applyDefaultColumns(listViewColumns) {
    const columns = [
      ...listViewColumns,
      ...this.buildExtraConfiguredColumns(listViewColumns)
    ];

    // A drag-reordered column set for this same view takes precedence over
    // the configured default order on any re-emit (e.g. the refreshApex a
    // view save triggers) -- otherwise the reorder the user just made would
    // silently snap back the moment the wire re-fires. Re-key against the
    // fresh column metadata (labels, etc.) rather than reusing this.columns
    // wholesale, so anything server-side about the columns still updates.
    if (this._userReorderedListViewApiName === this.selectedListViewApiName) {
      const byName = new Map(columns.map((col) => [col.fieldApiName, col]));
      const known = new Set(this.columns.map((col) => col.fieldApiName));
      const currentOrder = this.columns
        .map((col) => byName.get(col.fieldApiName))
        .filter(Boolean);
      const newlyAppeared = columns.filter(
        (col) => !known.has(col.fieldApiName)
      );
      return [...currentOrder, ...newlyAppeared];
    }

    const configuredEntries = this.configuredColumnEntries;
    if (!configuredEntries.length) {
      return columns;
    }

    const byName = new Map(columns.map((col) => [col.fieldApiName, col]));
    const ordered = configuredEntries
      .map((entry) => {
        const col = byName.get(entry.fieldApiName);
        if (!col) {
          return null;
        }
        return entry.label ? { ...col, label: entry.label } : col;
      })
      .filter(Boolean);

    if (!ordered.length) {
      return columns;
    }

    const chosen = new Set(ordered.map((col) => col.fieldApiName));
    const rest = columns.filter((col) => !chosen.has(col.fieldApiName));

    if (this._defaultedListViewApiName !== this.selectedListViewApiName) {
      this._defaultedListViewApiName = this.selectedListViewApiName;
      this.hiddenColumnFields = rest.map((col) => col.fieldApiName);
    }

    return [...ordered, ...rest];
  }

  /**
   * A user drag-reorder always wins over the configured default order from
   * then on for this view (see applyDefaultColumns) -- switching a column
   * on/off from the Table Columns menu already stays put the same way via
   * hiddenColumnFields; this is the reorder equivalent of that.
   */
  handleColumnReorder(event) {
    const orderedVisibleNames = event.detail?.columns || [];
    if (!orderedVisibleNames.length) {
      return;
    }

    const byName = new Map(this.columns.map((col) => [col.fieldApiName, col]));
    const reorderedVisible = orderedVisibleNames
      .map((name) => byName.get(name))
      .filter(Boolean);
    const visibleSet = new Set(orderedVisibleNames);
    const rest = this.columns.filter(
      (col) => !visibleSet.has(col.fieldApiName)
    );

    this.columns = [...reorderedVisible, ...rest];
    this._userReorderedListViewApiName = this.selectedListViewApiName;
  }

  @wire(getListRecordsByName, {
    objectApiName: "$objectApiName",
    listViewApiName: "$wireListViewApiName",
    optionalFields: "$optionalFields",
    pageSize: "$listViewFetchSize"
  })
  wiredRecords(result) {
    this._recordsWire = result;
    if (this.enableServerSearch) {
      // Row data comes from runServerSearch instead; wireListViewApiName
      // already keeps this adapter from actually fetching, but a stray
      // empty emission (if the platform ever sends one for an undefined
      // required param) must not race with a search already in flight.
      return;
    }
    const { data, error } = result;
    this.isLoading = false;
    if (data) {
      const records = data.records || [];
      this.tableRows = records.map((rec) => this.mapRecordToTableRow(rec));
      this.errorMessage = undefined;
    } else if (error && this.selectedListViewApiName && this.optionalFields) {
      this.errorMessage = this.reduceError(error);
      this.tableRows = [];
    }
  }

  /**
   * Seeds the chips from the list view's own criteria and rebaselines dirty
   * state. Guarded on the view actually changing so a cache re-emit never
   * throws away chips the user is still editing.
   */
  adoptSavedFilters(filteredByInfo) {
    if (this._adoptedListViewApiName === this.selectedListViewApiName) {
      return;
    }
    this._adoptedListViewApiName = this.selectedListViewApiName;

    this.activeFilters = filteredByInfo.map((filter) =>
      this.buildFilterChip(
        filter.fieldApiName,
        filter.operator,
        (filter.operandLabels || []).filter(Boolean).join("; ")
      )
    );
    this._savedSignature = this.currentSignature;
  }

  mapRecordToTableRow(rec) {
    const id = rec?.fields?.Id?.value || rec?.id;
    const row = {
      id,
      objectApiName: this.objectApiName
    };

    const fieldApiNames = [
      ...this.columns.map((col) => col.fieldApiName),
      ...this.supportingFieldApiNames
    ];

    const pillFieldNames = this.pillFieldNames;

    fieldApiNames.forEach((fieldApiName) => {
      const field = rec?.fields?.[fieldApiName];
      const value = this.resolveFieldCellValue(field, fieldApiName);
      row[fieldApiName] = value;

      // arcDataTable reads the tone from `<field>PillClass` on the row.
      if (pillFieldNames.includes(fieldApiName)) {
        row[`${fieldApiName}PillClass`] = pillToneClass(value);
      }

      // Date/DateTime fields also carry the raw timestamp and a local
      // calendar-day key alongside the formatted display value, so filtering
      // and grouping can compare real dates instead of a formatted string.
      if (this.isDateFieldApiName(fieldApiName)) {
        const rawValue = field?.value ?? null;
        row[`${fieldApiName}__raw`] = rawValue;
        row[`${fieldApiName}__dayKey`] = formatLocalDateKey(rawValue);
      }
    });

    return row;
  }

  // ---- Server search mode -------------------------------------------------

  /** Displayed columns plus any field only a filter/group-by references. */
  get searchFieldApiNames() {
    return [
      ...this.columns.map((col) => col.fieldApiName),
      ...this.supportingFieldApiNames
    ];
  }

  get currentFilterSearchSignature() {
    return JSON.stringify({
      search: this.searchTerm,
      filters: this.activeFilters
        .filter((f) => f.fieldApiName && f.operandValue)
        .map((f) => ({
          field: f.fieldApiName,
          operator: f.operator,
          value: f.operandValue
        }))
    });
  }

  /**
   * True once the user has typed/picked a filter or search value that
   * hasn't been confirmed (Enter) yet -- what's on screen is only whatever
   * was already loaded, live-filtered client-side, not a real search of
   * every matching record.
   */
  get hasUnconfirmedServerSearch() {
    if (!this.enableServerSearch) {
      return false;
    }
    const hasCriteria =
      Boolean(this.searchTerm.trim()) ||
      this.activeFilters.some((f) => f.fieldApiName && f.operandValue);
    return hasCriteria && this.currentFilterSearchSignature !== this._lastConfirmedSearchSignature;
  }

  get serverSearchHintMessage() {
    return "Showing results from the rows already loaded — press Enter to search all matching records.";
  }

  /**
   * Runs a real server-side search with whatever filters, search term, and
   * columns are current right now, replacing tableRows with the actual
   * matching set (up to SERVER_SEARCH_PAGE_SIZE) instead of re-slicing
   * whatever happened to already be loaded.
   */
  async runServerSearch() {
    if (!this.enableServerSearch || !this.objectApiName) {
      return;
    }

    const generation = ++this._serverSearchGeneration;
    this._lastConfirmedSearchSignature = this.currentFilterSearchSignature;
    this.isLoading = true;
    this.errorMessage = undefined;

    const filters = this.activeFilters
      .filter((f) => f.fieldApiName && f.operandValue)
      .map((f) => ({
        fieldApiName: f.fieldApiName,
        operator: f.operator,
        operandValue: f.operandValue
      }));
    const searchTerm = this.searchTerm.trim();
    const searchableFields = this.columns.map((col) => col.fieldApiName);

    try {
      const result = await searchRecords({
        objectApiName: this.objectApiName,
        fieldApiNames: this.searchFieldApiNames,
        filters,
        searchTerm,
        searchableFields,
        afterId: null,
        pageSize: SERVER_SEARCH_PAGE_SIZE
      });
      if (generation !== this._serverSearchGeneration) {
        return;
      }
      // Aligned by the field list the server actually selected, not the one
      // requested -- a requested path can fail server-side validation and
      // get dropped, which would silently shift every later cell by one if
      // rows were mapped against the request instead.
      const selectedFieldApiNames = result?.fieldApiNames || [];
      this.tableRows = (result?.rows || []).map((row) =>
        this.mapSearchRowToTableRow(row, selectedFieldApiNames)
      );
    } catch (error) {
      if (generation === this._serverSearchGeneration) {
        this.errorMessage = this.reduceError(error);
        this.tableRows = [];
      }
    } finally {
      if (generation === this._serverSearchGeneration) {
        this.isLoading = false;
      }
    }
  }

  /** Builds a table row from ArcRecordSearchController.SearchRow's flat cells. */
  mapSearchRowToTableRow(row, fieldApiNames) {
    const tableRow = { id: row.id, objectApiName: this.objectApiName };
    const pillFieldNames = this.pillFieldNames;

    fieldApiNames.forEach((fieldApiName, index) => {
      const rawValue = row.cells?.[index] ?? "";
      tableRow[fieldApiName] = rawValue;

      if (pillFieldNames.includes(fieldApiName)) {
        tableRow[`${fieldApiName}PillClass`] = pillToneClass(rawValue);
      }

      if (this.isDateFieldApiName(fieldApiName)) {
        tableRow[`${fieldApiName}__raw`] = rawValue || null;
        tableRow[`${fieldApiName}__dayKey`] = formatLocalDateKey(rawValue);
      }
    });

    return tableRow;
  }

  isNumericFieldType(fieldApiName) {
    const dataType = (
      this.getColumnMeta(fieldApiName)?.dataType || ""
    ).toLowerCase();

    return (
      dataType.includes("currency") ||
      dataType.includes("double") ||
      dataType.includes("int") ||
      dataType.includes("percent") ||
      dataType === "number"
    );
  }

  isDateFieldApiName(fieldApiName) {
    return this.resolveColumnType(fieldApiName) === "date";
  }

  /** Numerics stay raw so the table formats them; everything else uses displayValue. */
  resolveFieldCellValue(field, fieldApiName) {
    if (!field) {
      return "";
    }

    if (this.isNumericFieldType(fieldApiName)) {
      return field.value != null && field.value !== "" ? field.value : "";
    }

    if (field.displayValue != null && field.displayValue !== "") {
      return field.displayValue;
    }

    return field.value != null ? String(field.value) : "";
  }

  resolveColumnType(fieldApiName) {
    const meta = this.getColumnMeta(fieldApiName);
    const dataType = (meta?.dataType || "").toLowerCase();

    if (
      dataType.includes("currency") ||
      dataType.includes("double") ||
      dataType.includes("percent")
    ) {
      return "currency";
    }

    if (dataType.includes("int") || dataType === "number") {
      return "number";
    }

    if (dataType.includes("phone")) {
      return "phone";
    }

    if (dataType.includes("date")) {
      return "date";
    }

    return "text";
  }

  getColumnMeta(fieldApiName) {
    return (
      this.objectColumns.find((col) => col.fieldApiName === fieldApiName) ||
      null
    );
  }

  getOperatorLabel(operator) {
    return OPERATOR_LABELS[operator] || operator;
  }

  buildOperatorOptions(fieldApiName) {
    const meta = this.getColumnMeta(fieldApiName);
    if (meta?.supportedFilterOperators?.length) {
      return meta.supportedFilterOperators.map((operator) => ({
        label: this.getOperatorLabel(operator),
        value: operator
      }));
    }
    const operatorKeys = this.isDateFieldApiName(fieldApiName)
      ? DATE_OPERATOR_KEYS
      : Object.keys(OPERATOR_LABELS);
    return operatorKeys.map((operator) => ({
      label: this.getOperatorLabel(operator),
      value: operator
    }));
  }

  /** Label for a currently-displayed column, guaranteed to match its header. */
  getDisplayedColumnLabel(fieldApiName) {
    const col = this.columns.find((c) => c.fieldApiName === fieldApiName);
    return col?.label || this.getColumnMeta(fieldApiName)?.label || fieldApiName;
  }

  buildFilterChip(fieldApiName, operator, operandValue = "") {
    const meta = this.getColumnMeta(fieldApiName);
    const supported = this.buildOperatorOptions(fieldApiName);
    const resolvedOperator =
      operator ||
      meta?.defaultFilterOperator ||
      supported[0]?.value ||
      "Contains";

    return {
      key: `filter-${filterKeyCounter++}`,
      fieldApiName,
      label: this.getDisplayedColumnLabel(fieldApiName),
      operator: resolvedOperator,
      operandValue
    };
  }

  // ---- Interaction: tabs, view mode, search ------------------------------

  handleTabClick(event) {
    const listViewApiName = event.currentTarget.dataset.value;
    if (!listViewApiName || listViewApiName === this.selectedListViewApiName) {
      return;
    }
    if (event.currentTarget.dataset.source === "overflow") {
      this.promoteTab(listViewApiName);
    }
    this.selectTabView(listViewApiName);
  }

  /**
   * Brings a configured tab out of "More" and into the strip for the rest
   * of the session. Saved/private views don't need this -- once active they
   * already get their own delete-x (see buildTabs' showDelete), so stacking
   * a second dismiss control on the same tab would just be confusing.
   */
  promoteTab(listViewApiName) {
    const isConfiguredTab = this.configuredTabs.some(
      (tab) => tab.value === listViewApiName
    );
    if (!isConfiguredTab || this._promotedTabValues.includes(listViewApiName)) {
      return;
    }
    this._promotedTabValues = [...this._promotedTabValues, listViewApiName];
  }

  /**
   * The "x" on a promoted tab. Only removes it from the strip -- it's one
   * of this placement's configured views, so there's nothing to delete --
   * and if it's the one on screen this falls back to the first configured
   * tab rather than leaving the strip on a tab it no longer shows.
   */
  handleUnpromoteTabClick(event) {
    event.stopPropagation();
    const listViewApiName = event.currentTarget.dataset.value;
    if (!listViewApiName) {
      return;
    }
    this._promotedTabValues = this._promotedTabValues.filter(
      (value) => value !== listViewApiName
    );
    if (this.selectedListViewApiName === listViewApiName) {
      const fallback = this.configuredTabs[0]?.value || this.defaultListViewApiName;
      this.selectTabView(fallback);
    }
  }

  handleDeleteViewClick(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;
    if (!value) {
      return;
    }
    this.deleteViewTarget = { value, label };
    this.deleteViewError = undefined;
    this.openPopover = "";
    this.showDeleteViewModal = true;
  }

  closeDeleteViewModal() {
    this.showDeleteViewModal = false;
    this.deleteViewTarget = null;
    this.deleteViewError = undefined;
    this.isDeletingView = false;
  }

  async handleDeleteViewConfirm() {
    const target = this.deleteViewTarget;
    if (!target) {
      return;
    }
    this.isDeletingView = true;
    this.deleteViewError = undefined;

    try {
      await deleteListInfo({
        objectApiName: this.objectApiName,
        listViewApiName: target.value
      });
      this.listViews = this.listViews.filter((lv) => lv.value !== target.value);
      this._createdViewApiNames.delete(target.value);
      this._promotedTabValues = this._promotedTabValues.filter(
        (value) => value !== target.value
      );
      refreshApex(this._listInfosWire).catch(() => {
        /* Best-effort refresh -- local state above already reflects the delete. */
      });

      if (this.selectedListViewApiName === target.value) {
        const fallback = this.configuredTabs[0]?.value || this.defaultListViewApiName;
        this.selectTabView(fallback);
      }

      this.showDeleteViewModal = false;
      this.deleteViewTarget = null;
    } catch (error) {
      this.deleteViewError = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[arcRecordListView] Failed to delete list view", error);
    } finally {
      this.isDeletingView = false;
    }
  }

  selectTabView(listViewApiName) {
    this.openPopover = "";
    this.searchTerm = "";
    this.groupFieldApiName = "";
    // Column choices are per view — the next view has its own field set,
    // including any reorder: a reorder made on one tab has no bearing on
    // what order another tab's columns should start in.
    this.hiddenColumnFields = [];
    this._userReorderedListViewApiName = "";
    this.isLoading = true;
    this.selectedListViewApiName = listViewApiName;
  }

  handleTabKeyDown(event) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") {
      return;
    }

    const tabs = this.tabListViews;
    const currentIndex = tabs.findIndex(
      (lv) => lv.value === this.selectedListViewApiName
    );

    if (currentIndex === -1) {
      return;
    }

    const offset = event.key === "ArrowRight" ? 1 : -1;
    const next = tabs[(currentIndex + offset + tabs.length) % tabs.length];

    if (next) {
      event.preventDefault();
      this.selectTabView(next.value);
    }
  }

  handleViewModeChange(event) {
    this.viewMode = event.currentTarget.dataset.mode;
    this.openPopover = "";
  }

  handleSearchInput(event) {
    const value = event.target.value;
    window.clearTimeout(this._searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._searchTimer = window.setTimeout(() => {
      this.searchTerm = value;
    }, SEARCH_DEBOUNCE_MS);
  }

  /** Enter confirms a server search immediately, bypassing the debounce. */
  handleSearchKeyDown(event) {
    if (event.key !== "Enter" || !this.enableServerSearch) {
      return;
    }
    window.clearTimeout(this._searchTimer);
    this.searchTerm = event.target.value;
    this.runServerSearch();
  }

  /**
   * Navigates to the object's standard "new" page. The `newrecord` event is
   * kept so a host page can intercept and handle creation its own way.
   */
  handleNewRecord() {
    this.dispatchEvent(
      new CustomEvent("newrecord", {
        detail: { objectApiName: this.objectApiName }
      })
    );

    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: this.objectApiName,
        actionName: "new"
      }
    });
  }

  // ---- Interaction: popovers --------------------------------------------

  handleTogglePopover(event) {
    const popover = event.currentTarget.dataset.popover;
    this.openPopover = this.openPopover === popover ? "" : popover;
    this.fieldMenuSearch = "";
    this.pruneEmptyFilters();
  }

  handleBackdropClick() {
    this.openPopover = "";
    this.pruneEmptyFilters();
  }

  handleFieldMenuSearch(event) {
    this.fieldMenuSearch = event.target.value;
  }

  handleGroupFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.value;
    this.groupFieldApiName =
      this.groupFieldApiName === fieldApiName ? "" : fieldApiName;
    this.openPopover = "";
  }

  handleClearGroup() {
    this.groupFieldApiName = "";
    this.openPopover = "";
  }

  handleFilterFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.value;
    const chip = this.buildFilterChip(fieldApiName);
    this.activeFilters = [...this.activeFilters, chip];
    // Chip opens straight into its operator/value editor, as in the design.
    this.openPopover = chip.key;
    this.fieldMenuSearch = "";
  }

  handleChipClick(event) {
    const key = event.currentTarget.dataset.key;
    this.openPopover = this.openPopover === key ? "" : key;
    this.pruneEmptyFilters();
  }

  handleChipOperatorChange(event) {
    const key = event.currentTarget.dataset.key;
    const operator = event.target.value;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key ? { ...filter, operator } : filter;
    });
  }

  handleChipValueChange(event) {
    const key = event.currentTarget.dataset.key;
    const operandValue = event.target.value;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key ? { ...filter, operandValue } : filter;
    });
  }

  /** Enter confirms this filter chip's value as a real server search. */
  handleChipValueKeyDown(event) {
    if (event.key !== "Enter" || !this.enableServerSearch) {
      return;
    }
    const key = event.currentTarget.dataset.key;
    const operandValue = event.target.value;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key ? { ...filter, operandValue } : filter;
    });
    this.runServerSearch();
  }

  handleChipDateChange(event) {
    const key = event.currentTarget.dataset.key;
    const operandValue = event.target.value;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key ? { ...filter, operandValue } : filter;
    });
    // A date picker selection is already a complete, discrete choice --
    // confirm it as a real search immediately rather than waiting for a
    // separate Enter press the date input has no obvious way to make.
    if (this.enableServerSearch) {
      this.runServerSearch();
    }
  }

  /**
   * Figma's filter popover clears the value with the × inside the field and
   * has no "Remove filter" link, so a chip left without a value is dropped
   * when the popover closes rather than lingering as a no-op.
   */
  handleChipValueClear(event) {
    const key = event.currentTarget.dataset.key;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key ? { ...filter, operandValue: "" } : filter;
    });
  }

  pruneEmptyFilters() {
    // The chip currently being edited is spared — it is empty by design
    // until the user types a value into it.
    const openKey = this.openPopover;
    const remaining = this.activeFilters.filter(
      (filter) => Boolean(filter.operandValue) || filter.key === openKey
    );

    if (remaining.length !== this.activeFilters.length) {
      this.activeFilters = remaining;
    }
  }

  handleClearFilters() {
    this.activeFilters = [];
    this.openPopover = "";
    if (this.enableServerSearch) {
      this.runServerSearch();
    }
  }

  // ---- Interaction: save view -------------------------------------------

  handleSaveViewClick() {
    if (this.canOverwriteCurrentView) {
      this.openPopover = this.openPopover === "saveView" ? "" : "saveView";
      return;
    }
    this.openSaveViewModal();
  }

  openSaveViewModal() {
    this.saveViewName = "";
    this.saveViewError = undefined;
    this.openPopover = "";
    this.showSaveViewModal = true;
  }

  closeSaveViewModal() {
    this.showSaveViewModal = false;
    this.saveViewError = undefined;
    this.isSavingView = false;
  }

  handleSaveViewNameChange(event) {
    this.saveViewName = event.target.value;
  }

  async handleOverwriteView() {
    this.openPopover = "";
    this.isSavingView = true;

    try {
      await updateListInfoByName({
        objectApiName: this.objectApiName,
        listViewApiName: this.selectedListViewApiName,
        ...this.buildListInfoPayload({ includeEmptyFilters: true })
      });
      this._savedSignature = this.currentSignature;
      await this.refreshListData();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[arcRecordListView] Failed to overwrite list view", error);
    } finally {
      this.isSavingView = false;
    }
  }

  async handleSaveViewConfirm() {
    const label = (this.saveViewName || "").trim();
    if (!label) {
      this.saveViewError = "Enter a name for this view.";
      return;
    }

    const listViewApiName = this.buildListViewApiName(label);
    if (!listViewApiName) {
      this.saveViewError = "View name must include letters or numbers.";
      return;
    }

    this.isSavingView = true;
    this.saveViewError = undefined;

    try {
      const result = await createListInfo({
        objectApiName: this.objectApiName,
        listViewApiName,
        label,
        visibility: "Private",
        ...this.buildListInfoPayload()
      });

      const createdApiName =
        result?.apiName || result?.data?.apiName || listViewApiName;

      this.showSaveViewModal = false;
      this.selectedListViewApiName = createdApiName;
      this._savedSignature = this.currentSignature;
      this._createdViewApiNames.add(createdApiName);

      if (!this.listViews.some((lv) => lv.value === createdApiName)) {
        this.listViews = [
          ...this.listViews,
          { label, value: createdApiName, visibility: "Private" }
        ];
      }

      await this.refreshListData();
    } catch (error) {
      this.saveViewError = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[arcRecordListView] Failed to save list view", error);
    } finally {
      this.isSavingView = false;
    }
  }

  /**
   * @param includeEmptyFilters send an empty filteredByInfo instead of omitting
   * it, so overwriting a view after "Clear Filters" actually clears them.
   */
  buildListInfoPayload({ includeEmptyFilters = false } = {}) {
    const displayColumns = this.visibleColumnDefs.map(
      (col) => col.fieldApiName
    );
    const filteredByInfo = this.activeFilters
      .map((filter) => ({
        fieldApiName: filter.fieldApiName,
        operator: filter.operator,
        operandLabels: this.parseOperandLabels(filter.operandValue)
      }))
      .filter(
        (filter) =>
          filter.fieldApiName &&
          filter.operator &&
          filter.operandLabels.length > 0
      );

    const payload = { displayColumns };

    if (filteredByInfo.length || includeEmptyFilters) {
      payload.filteredByInfo = filteredByInfo;
      payload.filterLogicString = Array.from(
        { length: filteredByInfo.length },
        (_, index) => index + 1
      ).join(" AND ");
    }

    return payload;
  }

  parseOperandLabels(value) {
    if (value == null || value === "") {
      return [];
    }
    return String(value)
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean);
  }

  // ---- Table Columns dropdown (Figma 532:39223) -------------------------

  get showColumnsMenu() {
    return this.openPopover === "columns";
  }

  /**
   * One row per column the list view returns. The first is the record link
   * and stays on — switching it off would leave rows with nothing to click.
   */
  get columnMenuItems() {
    const term = this.columnMenuSearch.trim().toLowerCase();

    return (this.columns || [])
      .map((col, index) => {
        const checked = !this.hiddenColumnFields.includes(col.fieldApiName);
        const isLocked = index === 0;
        let modifier = checked ? "on" : "off";
        if (isLocked) {
          modifier = "locked";
        }

        return {
          value: col.fieldApiName,
          label: col.label || col.fieldApiName,
          checked,
          isLocked,
          trackClass: `arc-record-list-view__toggle arc-record-list-view__toggle--${modifier}`
        };
      })
      .filter((item) => !term || item.label.toLowerCase().includes(term));
  }

  get hasColumnMenuItems() {
    return this.columnMenuItems.length > 0;
  }

  openColumnsMenu() {
    if (!this.columns?.length) {
      return;
    }
    this.columnMenuSearch = "";
    this.openPopover = "columns";
  }

  handleColumnMenuSearch(event) {
    this.columnMenuSearch = event.target.value || "";
  }

  handleColumnToggle(event) {
    const field = event.currentTarget.dataset.field;
    if (!field) {
      return;
    }

    const hidden = [...this.hiddenColumnFields];
    const position = hidden.indexOf(field);

    if (position === -1) {
      // Never let the last visible column be switched off.
      if (this.visibleColumnDefs.length <= 1) {
        return;
      }
      hidden.push(field);
    } else {
      hidden.splice(position, 1);
    }

    this.hiddenColumnFields = hidden;
  }

  async refreshListData() {
    this.isLoading = true;
    const refreshTasks = [];
    if (this._listInfoWire) {
      refreshTasks.push(refreshApex(this._listInfoWire));
    }
    // In server search mode the records wire is disabled (see
    // wireListViewApiName) and never carries real data, so refreshing it
    // would be a no-op -- runServerSearch below is the real refresh.
    if (this._recordsWire && !this.enableServerSearch) {
      refreshTasks.push(refreshApex(this._recordsWire));
    }
    if (refreshTasks.length) {
      await Promise.all(refreshTasks);
    }
    if (this.enableServerSearch) {
      await this.runServerSearch();
    }
  }

  toApiName(label) {
    if (!label) {
      return "";
    }
    let apiName = label
      .trim()
      .replace(/[^a-zA-Z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "");
    if (/^[0-9]/.test(apiName)) {
      apiName = `X${apiName}`;
    }
    return apiName.substring(0, 40);
  }

  buildListViewApiName(label) {
    const base = this.toApiName(label);
    if (!base) {
      return "";
    }
    const suffix = (
      typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
        ? crypto.randomUUID()
        : `${Date.now()}${Math.random().toString(36).slice(2)}`
    ).replace(/-/g, "");
    const maxBaseLength = Math.max(1, 80 - 1 - suffix.length);
    return `${base.substring(0, maxBaseLength)}_${suffix}`;
  }

  reduceError(error) {
    if (!error) {
      return "Unknown error";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }
    if (typeof error.body?.message === "string") {
      return error.body.message;
    }
    if (typeof error.message === "string") {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch {
      return "Unexpected error";
    }
  }
}