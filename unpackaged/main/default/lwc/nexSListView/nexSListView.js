/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
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
import getMySavedListViewNames from "@salesforce/apex/NexSListViewController.getMySavedListViewNames";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import {
  buildRecordNavigationReference,
  openRecordInNewTab,
  resolveRecordUrl,
  usesQueryParamRecordRoute
} from "c/recordNavigationUtils";

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
 * Objects whose rows are people, or the household standing in for one. The
 * table paints a person glyph beside the name on these, where it reads as an
 * avatar; everywhere else — a case number, a check log entry — the same glyph
 * decorated a record that is not a person and was only noise. Keyed on the
 * object rather than the column so a page cannot opt into it by accident.
 */
const AVATAR_OBJECT_API_NAMES = new Set(["Account", "Contact", "Lead", "User"]);

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
/** Fields a card shows before the expander; the rest fold away behind it. */
const CARD_SUMMARY_SIZE = 5;
/** Fallback batch size for the card view when no page size is configured. */
const CARD_PAGE_SIZE = 25;
/** Bars past this are dropped — a chart of 200 one-record bars reads as noise. */
const CHART_MAX_BARS = 12;
/* Navy through to the lighter brand blues, so a long series stays legible. */
const CHART_COLOURS = [
  "#032d60",
  "#0f406f",
  "#0b5cab",
  "#0176d3",
  "#1b96ff",
  "#57a3fd",
  "#78b0fd",
  "#aacbff"
];

/** "Barney Rubble" -> "BR"; used for the card avatars. */
const buildInitials = (value) =>
  String(value || "")
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("") || "—";
/* 25 rows per page everywhere except the home screen, whose placements pin
   pageSize themselves and so are unaffected by this default. */
const TABLE_PAGE_SIZE = 25;
const TABLE_PAGE_SIZE_OPTIONS = [10, 25, 50];
const SEARCH_DEBOUNCE_MS = 275;
/** Saved views past this count collapse into the trailing "More" tab menu. */
const MAX_VISIBLE_TABS = 5;
/**
 * Rows the Group and Filter field menus paint at once. Case exposes 419
 * filterable fields and rendering all of them made both menus slow to open and
 * slow to type in; the menu's own search box is how anyone finds a field in a
 * list that long anyway. See fieldMenuOptions.
 */
const MAX_FIELD_MENU_OPTIONS = 50;
/**
 * Shorter than SEARCH_DEBOUNCE_MS: this filters a list already in memory rather
 * than refetching, so it can afford to feel immediate. See handleFieldMenuSearch.
 */
const FIELD_MENU_DEBOUNCE_MS = 120;

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

/**
 * Synthetic, read-only display columns the Lists API derives for certain
 * relationships — valid as `displayColumns` output from getListInfoByName,
 * but rejected as input to createListInfo/updateListInfoByName. See
 * buildListInfoPayload.
 */
const NON_SAVABLE_DISPLAY_COLUMNS = new Set([
  "Who.Name",
  "What.Name",
  "Owner.NameOrAlias"
]);

/** Column label overrides, keyed by field API name — wins over whatever label the view/describe
 * returns. Used where the platform's own label (or a raw API-name fallback) doesn't match the
 * name the business wants shown, e.g. "Permanent State" instead of the State/Country-picklist
 * era's auto-suffixed "Billing State/Province (text only)". Applies across every tab on the
 * object unless COLUMN_LABEL_OVERRIDES_BY_VIEW names a more specific label for that tab's view. */
const COLUMN_LABEL_OVERRIDES = {
  BillingState: "Permanent State",
  Name: "Contact Name",
  PersonMobilePhone: "Phone",
  "RecordType.Name": "Record Type"
};

/** Per-view label overrides, keyed by list view API name then field API name. Wins over
 * COLUMN_LABEL_OVERRIDES for that one tab — e.g. the Households tab's own Name column reads
 * "Household Name" rather than the Contacts tab's "Contact Name". */
const COLUMN_LABEL_OVERRIDES_BY_VIEW = {
  All_Households: { Name: "Household Name" },
  All_Individuals: { Name: "Individual Name" },
  All_Clients: { Name: "Client Name" },
  // BillingState is a person's permanent residence on the Individuals tab, but on an
  // entity's own record it's just the entity's address — "Permanent State" doesn't fit.
  All_Businesses: { Name: "Business Name", BillingState: "State" },
  All_Retirement_Plans: { Name: "Plan Name", BillingState: "State" },
  All_Trusts_Estates: { Name: "Trust Name", BillingState: "State" }
};

/** Cell-value translations, keyed by field API name then by the raw display value. A stopgap for
 * Record Type showing "Person Account" — the business-facing term is "Individual." Confirmed
 * against live data this org's Account records actually break down cleanly as Individual (the
 * "Person Account" record type), Business, Trust, Retirement Plan, Household, and a couple of
 * edge types — Record Type is the right field for this column once this one label is fixed; it
 * does not need replacing. Both key spellings are covered since it's not certain from static
 * metadata alone which one the platform's List Info API actually returns for this column. */
const CELL_VALUE_OVERRIDES = {
  "RecordType.Name": { "Person Account": "Individual" }
};

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
/**
 * The value as a number, or null when it is not one.
 *
 * The digit test is load-bearing. Stripping the non-numeric characters out of
 * a word leaves an empty string, and `Number("")` is 0 rather than NaN — so
 * "Normal" and "High" both came back as 0, every text filter reported
 * "0 equals 0", and every row matched. That is why filtering a list by any
 * picklist or text field appeared to do nothing at all.
 */
const toComparableNumber = (value) => {
  if (value == null || value === "") {
    return null;
  }
  const cleaned = String(value).replace(/[^0-9.eE+-]/g, "");
  if (!/\d/.test(cleaned)) {
    return null;
  }
  const numeric = Number(cleaned);
  return Number.isFinite(numeric) ? numeric : null;
};

/**
 * LWR list-view experience: saved-view tabs, view-mode switch, search,
 * group-by, filter chips, and the save/overwrite view flow, backed by
 * uiListsApi.
 */
export default class NexSListView extends NavigationMixin(LightningElement) {
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
   * Chart tab's initial "Break down by" field, e.g. `Status`. Without this the
   * chart falls back to the first column with repeating (but not all-unique)
   * values — a heuristic that can land on a mostly-blank relationship column
   * (e.g. Contact Name) before it reaches a genuinely useful one.
   */
  @api defaultChartFieldApiName = "";

  /**
   * Ordered, comma-separated field API names to show by default, e.g.
   * `Name,RecordType.Name,Type`. A list view's own column set is often much
   * wider than a screen — AllAccounts returns fourteen — so this picks the
   * ones worth seeing first and puts them in a deliberate order.
   *
   * Everything else the view returns stays in Choose columns, switched off
   * rather than dropped, so nothing becomes unreachable. Configured names
   * the view does not return are ignored, and leaving this blank keeps the
   * view's own columns in the view's own order.
   *
   * Per-tab `"columns"` in viewTabs wins over this: tabs on the same object
   * can front very different fields.
   */
  @api defaultColumns = "";

  /**
   * Extra field API names to offer in Choose columns, comma-separated. They
   * are added to `columns` but never to the default visible set, so they
   * arrive switched off and a user turns on the one they want.
   *
   * A list view carries at most a handful of columns, and Choose columns can
   * only ever offer what `columns` holds — so a field the view omits was not
   * merely hidden, it was unreachable. This is how a page widens that menu
   * without widening the table.
   *
   * Names are fetched eagerly, the same as any other column, so this is a
   * curated list rather than every field on the object: each one adds to the
   * optionalFields of a page-load-sized record fetch whether or not anyone
   * switches it on.
   *
   * Only meaningful alongside `defaultColumns` (or a tab's own `columns`).
   * With no configured default, applyDefaultColumns has no visible set to
   * subtract from and leaves every column on, these included.
   */
  @api availableColumns = "";

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
  /** Record id -> whether its card is showing every field. */
  @track expandedCards = {};
  /** Column the chart counts by; blank falls back to chartFieldApiName. */
  _chartField = "";
  /** How many cards are rendered; grows a batch at a time. */
  _cardLimit = 0;
  showSaveViewModal = false;
  showCreateModal = false;
  saveViewName = "";
  saveViewError;
  isSavingView = false;
  showDeleteViewModal = false;
  /** { value, label } of the view a delete confirm is pending for. */
  deleteViewTarget = null;
  deleteViewError;
  isDeletingView = false;
  filterLogicString = "";
  /** Guards adoptSavedGrouping against the list-info wire's cached re-emits. */
  _groupedListViewApiName = null;
  objectColumns = [];
  /** Search-ready field menu entries, rebuilt only when objectColumns lands. */
  _groupFieldEntries = [];
  _filterFieldEntries = [];
  /** Raw displayColumns from the active list view, before defaults are applied. */
  _listViewColumns = null;
  /** getObjectInfo field describe, used only to label configured extra columns. */
  objectFieldInfo = null;
  currentListViewLabel = "";
  _savedSignature = "";
  _adoptedListViewApiName = "";
  /** View a drag-reorder has already decided the column order for; see applyDefaultColumns. */
  _userReorderedListViewApiName = "";
  /**
   * Views saved during this page's life, so a new tab appears the instant the
   * user hits Save rather than waiting for the Apex wire to come back. The
   * durable answer is savedViewApiNames below; this only covers the gap.
   */
  _createdViewApiNames = new Set();
  /**
   * Configured tabs the user has pulled out of the "More" menu into the main
   * strip this page load, so they can see the tab name (and its own tab) at
   * a glance without reopening the menu. Not persisted anywhere — a fresh
   * load starts empty, same as hiddenColumnFields and every other view-local
   * preference on this component.
   */
  _promotedTabValues = [];
  /**
   * Views on this object the running user saved, straight from the org.
   *
   * getListInfosByObjectName (unlike the single-view getListInfoByName) never
   * returns a `visibility` field in this org, so the strip cannot tell a view
   * the user saved from one the org ships. It used to answer that from
   * localStorage, which meant a saved view stopped tabbing up in any other
   * browser, in a private window, or after the profile was cleared — it still
   * existed in Salesforce, but nothing here could find it again.
   */
  savedViewApiNames = [];
  _appliedTabParam = "";
  _pageRef;
  _searchTimer;
  _fieldMenuSearchTimer;
  _stylesLoaded = false;
  _listInfosWire;
  _savedViewNamesWire;
  _listInfoWire;
  _recordsWire;
  _listObjectInfoWire;

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

  /* ---- Saved grouping ---------------------------------------------------- */

  /**
   * Group-by is stored per view in the browser, not on the list view.
   *
   * A Salesforce list view has no group-by — the Lists API models columns,
   * filters, scope and sort, and nothing else — so grouping had nowhere to go
   * and was simply lost on every save. It is a display preference rather than
   * part of what the view selects, so it lives beside the created-view list in
   * localStorage: an object -> { listViewApiName: fieldApiName } map.
   *
   * The consequence worth knowing: grouping follows the browser, not the view.
   * Sharing a saved view shares its columns, filters and scope; the person you
   * share it with sets their own grouping.
   */
  get _groupingStorageKey() {
    return `nexSListView.grouping.${this.objectApiName}`;
  }

  loadPersistedGrouping() {
    try {
      const raw = window.localStorage.getItem(this._groupingStorageKey);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return {};
    }
  }

  persistGrouping(listViewApiName, fieldApiName) {
    if (!listViewApiName) {
      return;
    }
    try {
      const all = this.loadPersistedGrouping();
      if (fieldApiName) {
        all[listViewApiName] = fieldApiName;
      } else {
        delete all[listViewApiName];
      }
      window.localStorage.setItem(
        this._groupingStorageKey,
        JSON.stringify(all)
      );
    } catch {
      /* localStorage unavailable (private browsing, quota) — grouping still
         works for the rest of this session, it just will not come back. */
    }
  }

  /* ---- Saved-view base list view ----------------------------------------- */

  /**
   * The list view a saved view was created from.
   *
   * createListInfo always creates a view scoped to the running user's own
   * records. It accepts a `scope` and ignores it, and so does
   * updateListInfoByName — both resolve without error and leave the view on
   * "mine". So a view saved off All Tasks came back covering only the tasks
   * the user personally owns, with its filter chip still showing: it read as
   * "my filter matches nothing" when the truth was that the view had quietly
   * stopped looking at everyone else's records. Measured on this org: 34 tasks
   * matched the filter, 0 of them owned by the user who saved the view.
   *
   * Since the scope cannot be set, the records are read from the base view
   * instead — which has the scope the user was actually looking at — and the
   * saved view supplies the columns and filters over the top. The filters then
   * have to run client-side, which is what this component does for every
   * unsaved filter anyway; it already holds the full LIST_VIEW_FETCH_SIZE page
   * and filters it in visibleRows.
   */
  get _viewBaseStorageKey() {
    return `nexSListView.viewBase.${this.objectApiName}`;
  }

  loadPersistedViewBases() {
    try {
      const raw = window.localStorage.getItem(this._viewBaseStorageKey);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return {};
    }
  }

  persistViewBase(listViewApiName, baseApiName) {
    if (!listViewApiName || !baseApiName) {
      return;
    }
    try {
      const all = this.loadPersistedViewBases();
      all[listViewApiName] = baseApiName;
      window.localStorage.setItem(
        this._viewBaseStorageKey,
        JSON.stringify(all)
      );
    } catch {
      /* localStorage unavailable — the saved view still works, it just reads
         its records from its own (user-scoped) record set. */
    }
  }

  removePersistedViewBase(listViewApiName) {
    try {
      const all = this.loadPersistedViewBases();
      delete all[listViewApiName];
      window.localStorage.setItem(
        this._viewBaseStorageKey,
        JSON.stringify(all)
      );
    } catch {
      /* Nothing to clean up if storage is unavailable. */
    }
  }

  /** The view the records wire reads from; see _viewBaseStorageKey. */
  get recordsListViewApiName() {
    return (
      this.loadPersistedViewBases()[this.selectedListViewApiName] ||
      this.selectedListViewApiName
    );
  }

  /** True when the record set already has the active view's filters applied. */
  get recordsAreServerFiltered() {
    return this.recordsListViewApiName === this.selectedListViewApiName;
  }

  /**
   * Restores this view's grouping when it becomes the active one. Guarded on
   * the view actually changing, the same way adoptSavedFilters is: the
   * list-info wire re-emits from cache, and re-seeding on every emit would
   * undo a grouping the user had just cleared.
   */
  adoptSavedGrouping() {
    if (this._groupedListViewApiName === this.selectedListViewApiName) {
      return;
    }
    this._groupedListViewApiName = this.selectedListViewApiName;
    this.groupFieldApiName =
      this.loadPersistedGrouping()[this.selectedListViewApiName] || "";
  }

  disconnectedCallback() {
    window.clearTimeout(this._searchTimer);
    window.clearTimeout(this._fieldMenuSearchTimer);
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

  /** Publishes every Phosphor glyph as a `--nexs-icon-*` custom property. */
  applyIconVariables() {
    for (const [key, file] of Object.entries(ICON_FILES)) {
      const url = `${NEXS_ICONS}/${file}.svg`;
      this.style.setProperty(`--nexs-icon-${key}`, `url('${url}')`);
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

  /**
   * Passed to the table, which masks it the same way. Empty for an object whose
   * records are not people, which is how the table knows to draw no avatar at
   * all — see AVATAR_OBJECT_API_NAMES.
   */
  get avatarIconUrl() {
    return AVATAR_OBJECT_API_NAMES.has(this.objectApiName)
      ? `${NEXS_ICONS}/${ICON_FILES.user}.svg`
      : "";
  }

  /**
   * Widths are remembered per view, not per object: two views of the same
   * object routinely show different columns, so one shared slot would apply a
   * width to a column the other view does not have.
   */
  get columnWidthStorageKey() {
    return `nexSListView.colWidths.${this.objectApiName}.${this.selectedListViewApiName}`;
  }

  get columnSettingsIconUrl() {
    return `${NEXS_ICONS}/${ICON_FILES.columns}.svg`;
  }

  // ---- Header + tabs -----------------------------------------------------

  /** Without the tab strip the header owns its own bottom padding. */
  get pageHeaderClass() {
    return this.hasViewTabs
      ? "nexs-list-view__page-header"
      : "nexs-list-view__page-header nexs-list-view__page-header--no-tabs";
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
  /**
   * Every view the strip should treat as the user's own: what the org says
   * they created, plus anything saved since this page loaded. The second half
   * only matters for the moment between createListInfo resolving and the Apex
   * wire refreshing.
   */
  get mySavedViewApiNames() {
    return new Set([...this.savedViewApiNames, ...this._createdViewApiNames]);
  }

  get tabListViews() {
    const created = this.mySavedViewApiNames;
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
          /* Ordered field API names this tab shows by default. */
          columns: entry.columns || "",
          /* Ordered field API names the generic create dialog offers; see
             quickCreateFields. */
          createFields: entry.createFields || ""
        };
      });
  }

  parseJsonTabs(raw) {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[nexSListView] viewTabs is not valid JSON", error);
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
   * Splits tabListViews into what the strip shows up front versus what waits
   * behind "More" — the natural first MAX_VISIBLE_TABS, plus any tab a click
   * from the More menu has promoted out of it (see promoteTab). A promoted
   * tab is added after the natural ones rather than displacing one of them,
   * so "bring it before More" never costs the user a tab they could already
   * see.
   */
  get orderedTabListViews() {
    const all = this.tabListViews;
    const natural = all.slice(0, MAX_VISIBLE_TABS);
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
    return this.buildTabs(this.orderedTabListViews.visible);
  }

  get overflowTabs() {
    return this.buildTabs(this.orderedTabListViews.overflow);
  }

  get hasOverflowTabs() {
    return this.orderedTabListViews.overflow.length > 0;
  }

  /**
   * Pulls a configured tab out of "More" and into the main strip for the
   * rest of this page load. Only configured tabs qualify — a saved/private
   * view already gets its own always-on delete "x" once it's active, and
   * stacking a second "x" with different behaviour on the same tab would
   * just be confusing.
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

  buildTabs(listViews) {
    // Configured tabs (viewTabs) are the page's stock views — only tabs
    // saved from this component (private views) are safe to let the user
    // delete outright.
    const configuredValues = new Set(
      this.configuredTabs.map((tab) => tab.value)
    );

    return listViews.map((lv) => {
      const isActive = lv.value === this.selectedListViewApiName;
      return {
        ...lv,
        isActive,
        // The delete "x" only makes sense once a view is the one on screen —
        // showing it on every custom tab crowded the strip and had no active
        // indicator under it, so it looked like it was cutting the tab's
        // underline.
        showDelete: isActive && !configuredValues.has(lv.value),
        deleteAriaLabel: `Delete view ${lv.label}`,
        // Unlike showDelete, shown on every promoted tab regardless of which
        // one is active — a tab promoted by mistake still needs to be
        // dismissible, not just the one currently on screen.
        showUnpromote: this._promotedTabValues.includes(lv.value),
        unpromoteAriaLabel: `Remove ${lv.label} from the tab strip`,
        tabIndex: isActive ? 0 : -1,
        className: isActive
          ? "nexs-list-view__tab nexs-list-view__tab--active"
          : "nexs-list-view__tab"
      };
    });
  }

  get showMoreTabsMenu() {
    return this.openPopover === "moreTabs";
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
      ? "nexs-list-view__segment nexs-list-view__segment--active"
      : "nexs-list-view__segment";
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
      label: this.getColumnLabel(col.fieldApiName, col.label),
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
      await openRecordInNewTab(this, recordId, this.objectApiName);
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
      console.error("[nexSListView] Could not copy the record link", error);
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
    /*
     * A chip seeded from the list view's own criteria describes a filter the
     * server has already applied to the rows it returned, so re-running it
     * here can only take rows away. It reliably does: the chip carries the
     * criterion's display labels, not the row's rendered value — Task's "My
     * Open Tasks" filters on IsClosed and seeds the operand "0", which never
     * equals the row's "false", so every row was dropped and the tab read
     * "No records to display" against 18 real records. The chip stays visible
     * so the view's criteria are legible; it just does not filter twice.
     */
    if (filter.serverApplied) {
      return true;
    }

    const operand = (filter.operandValue || "").trim();

    if (!filter.fieldApiName || !operand) {
      return true;
    }

    const rawValue = String(row[filter.fieldApiName] ?? "");
    const value = rawValue.toLowerCase();
    const target = operand.toLowerCase();
    const numericValue = toComparableNumber(rawValue);
    const numericTarget = toComparableNumber(operand);
    const bothNumeric = numericValue !== null && numericTarget !== null;

    switch (filter.operator) {
      case "Equals":
        return bothNumeric ? numericValue === numericTarget : value === target;
      case "NotEqual":
        return bothNumeric ? numericValue !== numericTarget : value !== target;
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
      operatorOptions: this.buildOperatorOptions(filter.fieldApiName).map(
        (opt) => ({ ...opt, selected: opt.value === filter.operator })
      )
    }));
  }

  /**
   * Cards.
   *
   * The old shape dumped every column into one flat list, so a card was
   * mostly a column of em dashes with the few real values lost among them.
   * Populated fields are hoisted to the front and the first CARD_SUMMARY_SIZE
   * of them are shown; the remainder — blanks included — sit behind a
   * per-card expander, so a card is scannable but nothing is lost.
   */
  /**
   * Cards render straight from visibleRows, which is every filtered record —
   * 774 of them on All Contacts. The table never had this problem because
   * styledDataTable paginates internally. Cards page in a batch at a time
   * instead, so the first paint is one screenful rather than the whole list.
   */
  get cardLimit() {
    return this._cardLimit || this.pageSizeNumber || CARD_PAGE_SIZE;
  }

  get hasMoreCards() {
    return this.visibleRows.length > this.cardLimit;
  }

  get moreCardsLabel() {
    const remaining = this.visibleRows.length - this.cardLimit;
    const next = Math.min(remaining, this.pageSizeNumber || CARD_PAGE_SIZE);
    return `Show ${next} more of ${remaining} remaining`;
  }

  handleShowMoreCards() {
    this._cardLimit = this.cardLimit + (this.pageSizeNumber || CARD_PAGE_SIZE);
  }

  get cardRows() {
    const [titleColumn, ...restColumns] = this.visibleColumnDefs;

    return this.visibleRows.slice(0, this.cardLimit).map((row) => {
      const fields = restColumns.map((col) => {
        const raw = row[col.fieldApiName];
        const value =
          raw === null || raw === undefined || raw === "" ? "" : String(raw);
        return {
          key: `${row.id}-${col.fieldApiName}`,
          label: this.getColumnLabel(col.fieldApiName, col.label),
          value: value || "—",
          hasValue: Boolean(value) && value !== "-"
        };
      });

      const populated = fields.filter((f) => f.hasValue);
      const empty = fields.filter((f) => !f.hasValue);
      const ordered = [...populated, ...empty];
      const summary = ordered.slice(0, CARD_SUMMARY_SIZE);
      const extra = ordered.slice(CARD_SUMMARY_SIZE);
      const isExpanded = Boolean(this.expandedCards[row.id]);
      const title = row[titleColumn?.fieldApiName] || "—";

      return {
        key: row.id,
        recordId: row.id,
        title,
        initials: buildInitials(title),
        populatedCount: `${populated.length}/${fields.length} fields`,
        fields: isExpanded ? ordered : summary,
        hasExtra: extra.length > 0,
        isExpanded,
        toggleLabel: isExpanded ? "Show less" : `Show ${extra.length} more`,
        toggleIconClass: isExpanded
          ? "nexs-list-view__card-chevron nexs-list-view__card-chevron--open"
          : "nexs-list-view__card-chevron"
      };
    });
  }

  handleCardToggle(event) {
    const recordId = event.currentTarget.dataset.id;
    if (!recordId) {
      return;
    }
    this.expandedCards = {
      ...this.expandedCards,
      [recordId]: !this.expandedCards[recordId]
    };
  }

  handleCardOpen(event) {
    event.preventDefault();
    const recordId = event.currentTarget.dataset.id;
    if (!recordId) {
      return;
    }
    const reference = buildRecordNavigationReference(
      recordId,
      this.objectApiName,
      { useQueryParam: usesQueryParamRecordRoute(this.objectApiName) }
    );
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  // ---- Chart -------------------------------------------------------------

  /**
   * Chart.
   *
   * There was no chart — the tab rendered "Chart view is not configured".
   * This counts the visible rows by whichever column is chosen and draws
   * them as bars. Deliberately CSS rather than a charting library: the data
   * is a single series of counts, and a widths-and-labels bar chart carries
   * no dependency, no canvas sizing to manage, and stays readable to a
   * screen reader through the underlying list markup.
   */
  get chartFieldApiName() {
    if (
      this._chartField &&
      this.visibleColumnDefs.some((c) => c.fieldApiName === this._chartField)
    ) {
      return this._chartField;
    }
    // Default to whatever is being grouped by, else the placement's
    // configured default, else the first column that repeats values — a
    // column of unique names makes a useless chart.
    if (this.groupFieldApiName) {
      return this.groupFieldApiName;
    }
    if (
      this.defaultChartFieldApiName &&
      this.visibleColumnDefs.some(
        (c) => c.fieldApiName === this.defaultChartFieldApiName
      )
    ) {
      return this.defaultChartFieldApiName;
    }
    const best = this.visibleColumnDefs.find((col) => {
      const values = new Set(
        this.visibleRows.map((r) => r[col.fieldApiName] || "")
      );
      return values.size > 1 && values.size < this.visibleRows.length;
    });
    return best?.fieldApiName || this.visibleColumnDefs[0]?.fieldApiName || "";
  }

  get chartFieldOptions() {
    return this.visibleColumnDefs.map((col) => ({
      label: this.getColumnLabel(col.fieldApiName, col.label),
      value: col.fieldApiName,
      selected: col.fieldApiName === this.chartFieldApiName
    }));
  }

  get chartFieldLabel() {
    const fallback =
      this.findColumn(this.chartFieldApiName)?.label ||
      this.getColumnMeta(this.chartFieldApiName)?.label ||
      "field";
    return this.getColumnLabel(this.chartFieldApiName, fallback);
  }

  get chartBars() {
    const field = this.chartFieldApiName;
    if (!field) {
      return [];
    }

    const counts = new Map();
    this.visibleRows.forEach((row) => {
      const raw = row[field];
      const label =
        raw === null || raw === undefined || raw === "" || raw === "-"
          ? "(blank)"
          : String(raw);
      counts.set(label, (counts.get(label) || 0) + 1);
    });

    const entries = [...counts.entries()].sort((a, b) => b[1] - a[1]);
    const capped = entries.slice(0, CHART_MAX_BARS);
    const max = capped.length ? capped[0][1] : 0;
    const total = this.visibleRows.length || 1;

    return capped.map(([label, count], index) => ({
      key: label,
      label,
      count,
      percent: `${Math.round((count / total) * 100)}%`,
      // Widths are relative to the tallest bar so short series still
      // fill the plot; the percentage beside it stays relative to total.
      barStyle: `width: ${max ? Math.max(2, Math.round((count / max) * 100)) : 0}%; background: ${CHART_COLOURS[index % CHART_COLOURS.length]};`
    }));
  }

  get chartSummary() {
    const shown = this.chartBars.length;
    const rows = this.visibleRows.length;
    return `${rows} record${rows === 1 ? "" : "s"} across ${shown} value${shown === 1 ? "" : "s"}`;
  }

  get hasChartData() {
    return this.chartBars.length > 0;
  }

  handleChartFieldChange(event) {
    this._chartField = event.target.value;
  }

  // ---- Group by ----------------------------------------------------------

  get groupButtonLabel() {
    if (!this.groupFieldApiName) {
      return "Group";
    }
    const fallback =
      this.findColumn(this.groupFieldApiName)?.label ||
      this.getColumnMeta(this.groupFieldApiName)?.label ||
      this.groupFieldApiName;
    return `Group: ${this.getColumnLabel(this.groupFieldApiName, fallback)}`;
  }

  get groupButtonClass() {
    return this.groupFieldApiName
      ? "nexs-list-view__button nexs-list-view__button--neutral nexs-list-view__button--on"
      : "nexs-list-view__button nexs-list-view__button--neutral";
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

  /**
   * Field list shared by the Group and Filter menus, narrowed by its search box.
   *
   * Both menus offer every field the object exposes — 419 filterable ones on
   * Case — and this rebuilt the whole option list on every render. Two costs
   * came out of that: opening the menu painted 419 buttons, and each keystroke
   * in the search box re-derived all 419 option objects (running
   * activeFilters.some() once per field) before re-rendering, measured at
   * 33-67ms per key on a desktop.
   *
   * The searchable form of each field is now built once per object in
   * wiredListObjectInfo, so a keystroke is a substring test over precomputed
   * strings, and only the first MAX_FIELD_MENU_OPTIONS matches are turned into
   * options and painted. The list is alphabetical by nothing in particular —
   * it is the object's own column order — so a cap could silently hide the
   * field someone is looking for; fieldMenuOverflowLabel says how many are held
   * back and that typing narrows them.
   */
  get fieldMenuOptions() {
    const isGroupMenu = this.openPopover === "group";

    return this.fieldMenuMatches
      .slice(0, MAX_FIELD_MENU_OPTIONS)
      .map((entry) => {
        // Figma's menu row reserves a 16px checkmark slot on every row
        // and fills it for the current selection (Group / Dropdown,
        // 532:39348). For the filter menu "selected" means the field
        // already has a chip.
        const isSelected = isGroupMenu
          ? entry.value === this.groupFieldApiName
          : this.activeFilters.some(
              (filter) => filter.fieldApiName === entry.value
            );

        return {
          key: entry.key,
          label: entry.label,
          value: entry.value,
          isSelected,
          checkClass: isSelected
            ? "nexs-list-view__menu-check nexs-list-view__menu-check--on"
            : "nexs-list-view__menu-check"
        };
      });
  }

  /** Every field matching the search box, before the render cap is applied. */
  get fieldMenuMatches() {
    const entries =
      this.openPopover === "group"
        ? this._groupFieldEntries
        : this._filterFieldEntries;
    const term = this.fieldMenuSearch.trim().toLowerCase();

    return term
      ? entries.filter((entry) => entry.search.includes(term))
      : entries;
  }

  get hasFieldMenuOptions() {
    return this.fieldMenuMatches.length > 0;
  }

  get hasMoreFieldMenuOptions() {
    return this.fieldMenuMatches.length > MAX_FIELD_MENU_OPTIONS;
  }

  get fieldMenuOverflowLabel() {
    return `Showing ${MAX_FIELD_MENU_OPTIONS} of ${this.fieldMenuMatches.length} fields — keep typing to narrow`;
  }

  /**
   * Precomputes both menus' entries. Called from the wire rather than derived
   * lazily in a getter: assigning a field during render would mark the
   * component dirty and re-render it again.
   */
  buildFieldMenuEntries() {
    // Sourced from this tab's own columns rather than the object's full field list — a field
    // hidden by default (still toggleable in the column menu) belongs here, but nothing outside
    // this tab's column set does. A column not in the object's own describe (a relationship path
    // like RecordType.Name or Financial_Advisor_Team__r.Name) has no describe-level
    // sortable/filterable flag to check, so it defaults to usable since it's already a real,
    // working column on this tab.
    const columns = this.columns || [];
    const toEntry = (col) => {
      const label = this.getColumnLabel(
        col.fieldApiName,
        col.label || col.fieldApiName
      );
      return {
        key: col.fieldApiName,
        label,
        value: col.fieldApiName,
        search: label.toLowerCase()
      };
    };

    this._groupFieldEntries = columns
      .filter((col) => this.getColumnMeta(col.fieldApiName)?.sortable !== false)
      .map(toEntry);
    this._filterFieldEntries = columns
      .filter((col) => {
        const meta = this.getColumnMeta(col.fieldApiName);
        return meta ? Boolean(meta.filterable) : true;
      })
      .map(toEntry);
  }

  // ---- Saved-view dirty state -------------------------------------------

  get currentSignature() {
    return JSON.stringify({
      group: this.groupFieldApiName,
      hiddenColumns: [...this.hiddenColumnFields].sort(),
      // Unsorted — a pure reorder (same columns, new sequence) must dirty
      // the view same as a visibility change does, so a drag alone is
      // enough to surface Save View.
      columnOrder: this.visibleColumnDefs.map((col) => col.fieldApiName),
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
    this.buildFieldMenuEntries();
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
    this.rebuildColumns();
  }

  /**
   * Which views on this object are the user's own. Refreshed after a save or a
   * delete, the same way the list-info wire is; see savedViewApiNames.
   */
  @wire(getMySavedListViewNames, { objectApiName: "$objectApiName" })
  wiredSavedViewNames(result) {
    this._savedViewNamesWire = result;
    const { data } = result;
    if (data) {
      this.savedViewApiNames = [...data];
    }
    /* An error here is not worth surfacing: the strip still shows the
       configured tabs plus anything saved in this session, which is what it
       did before the server had an opinion. */
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
      const displayColumns = data.displayColumns || [];
      this._listViewColumns = displayColumns.map((col) => ({
        fieldApiName: col.fieldApiName || col.fieldName || col.label,
        label: col.label || col.fieldApiName
      }));
      this.rebuildColumns();
      this.currentListViewLabel = data.label || this.selectedListViewApiName;
      this.filterLogicString = data.filterLogicString || "";
      this.adoptSavedFilters(data.filteredByInfo || []);
      this.adoptSavedGrouping();
      this.errorMessage = undefined;
    } else if (error && this.selectedListViewApiName) {
      this.errorMessage = this.reduceError(error);
      this._listViewColumns = [];
      this.columns = [];
      this._groupFieldEntries = [];
      this._filterFieldEntries = [];
    }
  }

  /**
   * Recomputes the visible column set from the list view's own columns plus
   * whatever the page configured. Called from both the list-info and the
   * object-info wires because either can be the last to settle.
   */
  rebuildColumns() {
    if (!this._listViewColumns) {
      return;
    }
    this.columns = this.applyDefaultColumns(this._listViewColumns);
    // Group/filter entries are keyed off this tab's own columns (see
    // buildFieldMenuEntries), so they're only ever correct right after this
    // assignment — not at the moment a tab switch is requested, since the
    // wire for the new tab settles asynchronously afterward.
    this.buildFieldMenuEntries();
  }

  /**
   * Configured columns the list view itself does not return.
   *
   * `defaultColumns` reads as "the columns this page shows", but it could only
   * ever reorder and hide what the list view already carried — naming a field
   * the view omitted dropped it silently. The record payload is fetched with
   * explicit optionalFields rather than the view's own column set, so the
   * value is there for the asking; only the label has to come from somewhere,
   * and getListObjectInfo already describes every column the object offers.
   *
   * A name that is neither in the view nor on the object (a typo, or a
   * relationship path the object info does not describe) still drops out
   * rather than rendering a column of blanks under a guessed heading.
   */
  buildExtraConfiguredColumns(existing) {
    const known = new Set(existing.map((col) => col.fieldApiName));
    const requested = [
      ...this.configuredDefaultColumns,
      ...this.configuredAvailableColumns
    ];
    return [...new Set(requested)]
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

  @wire(getListRecordsByName, {
    objectApiName: "$objectApiName",
    listViewApiName: "$recordsListViewApiName",
    optionalFields: "$optionalFields",
    pageSize: "$listViewFetchSize"
  })
  wiredRecords(result) {
    this._recordsWire = result;
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

  /** Ordered default columns for the current tab, tab config winning. */
  get configuredDefaultColumns() {
    const raw = this.activeConfiguredTab?.columns || this.defaultColumns || "";
    return raw
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean);
  }

  /** Field names offered in Choose columns but not shown by default. */
  get configuredAvailableColumns() {
    return (this.availableColumns || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean);
  }

  /**
   * Puts the configured columns first, in the configured order, and switches
   * the rest off. The unconfigured ones stay in `columns` so Choose columns
   * still offers them — hiding is a default, not a deletion.
   *
   * Guarded on the view actually changing, the same way adoptSavedFilters is:
   * this wire re-emits from cache, and re-seeding on every emit would undo a
   * column the user had just switched on.
   */
  applyDefaultColumns(listViewColumns) {
    const columns = [
      ...listViewColumns,
      ...this.buildExtraConfiguredColumns(listViewColumns)
    ];

    // A drag-reordered column set for this same view takes precedence over
    // the configured default order on any re-emit (e.g. the refreshApex a
    // view save triggers) — otherwise the reorder the user just made would
    // silently snap back the moment the wire re-fires. Re-key against the
    // fresh column metadata (labels, etc.) rather than reusing `this.columns`
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

    const configured = this.configuredDefaultColumns;
    if (!configured.length) {
      return columns;
    }

    const byName = new Map(columns.map((col) => [col.fieldApiName, col]));
    const ordered = configured.map((name) => byName.get(name)).filter(Boolean);

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
   * Drag-and-drop column reorder from the table header (styledDataTable's
   * `columnreorder`, gated by `enable-column-reorder`). The event carries
   * only the currently-visible columns in their new order; hidden ones stay
   * put, appended after, exactly as applyDefaultColumns already does.
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

    this.activeFilters = filteredByInfo.map((filter) => ({
      ...this.buildFilterChip(
        filter.fieldApiName,
        filter.operator,
        (filter.operandLabels || []).filter(Boolean).join("; ")
      ),
      // Only skip the client-side pass when the records really came from this
      // view. A saved view reads its records from the base view it was created
      // from, which has not applied these filters.
      serverApplied: this.recordsAreServerFiltered
    }));
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
      const field = this.resolveFieldNode(rec, fieldApiName);
      const value = this.resolveFieldCellValue(field, fieldApiName);
      row[fieldApiName] = value;

      // styledDataTable reads the tone from `<field>PillClass` on the row.
      if (pillFieldNames.includes(fieldApiName)) {
        row[`${fieldApiName}PillClass`] = pillToneClass(value);
      }
    });

    return row;
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

  /**
   * Walks a display column down to its field node.
   *
   * List views address related fields with a dotted path — "Who.Name",
   * "Owner.NameOrAlias", "Financial_Advisor_Team__r.Name" — but the records
   * API returns them nested, as `fields.Who.value.fields.Name`. A flat
   * `fields["Who.Name"]` lookup therefore misses entirely and the cell renders
   * as the empty placeholder even though the record holds a value. Every
   * relationship column on the Task list views is spelled this way.
   */
  resolveFieldNode(rec, fieldApiName) {
    const parts = String(fieldApiName || "").split(".");
    let node = rec?.fields?.[parts[0]];

    for (let i = 1; i < parts.length && node; i += 1) {
      node = node.value?.fields?.[parts[i]];
    }

    return node;
  }

  /** Numerics stay raw so the table formats them; everything else uses displayValue. */
  resolveFieldCellValue(field, fieldApiName) {
    if (!field) {
      return "";
    }

    const overrides = CELL_VALUE_OVERRIDES[fieldApiName];

    if (this.isNumericFieldType(fieldApiName)) {
      const value =
        field.value != null && field.value !== "" ? field.value : "";
      return overrides?.[value] ?? value;
    }

    if (field.displayValue != null && field.displayValue !== "") {
      return overrides?.[field.displayValue] ?? field.displayValue;
    }

    const value = field.value != null ? String(field.value) : "";
    return overrides?.[value] ?? value;
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

  /** Looks up a field's own entry in this tab's column set — the platform's already-resolved
   * label for a relationship-path column (Financial_Advisor_Team__r.Name) lives here, not in
   * getColumnMeta's object-level describe, which only knows the object's own direct fields. */
  findColumn(fieldApiName) {
    return (
      (this.columns || []).find((col) => col.fieldApiName === fieldApiName) ||
      null
    );
  }

  /** Resolves a field's display label for the active tab: per-view override, then the
   * shared override, then whatever the caller already had on hand. */
  getColumnLabel(fieldApiName, fallback) {
    const perView =
      COLUMN_LABEL_OVERRIDES_BY_VIEW[this.selectedListViewApiName];
    return (
      (perView && perView[fieldApiName]) ||
      COLUMN_LABEL_OVERRIDES[fieldApiName] ||
      fallback
    );
  }

  getOperatorLabel(operator) {
    return OPERATOR_LABELS[operator] || operator;
  }

  buildOperatorOptions(fieldApiName) {
    const meta = this.getColumnMeta(fieldApiName);
    const operators = meta?.supportedFilterOperators?.length
      ? meta.supportedFilterOperators
      : Object.keys(OPERATOR_LABELS);
    return operators.map((operator) => ({
      label: this.getOperatorLabel(operator),
      value: operator
    }));
  }

  buildFilterChip(fieldApiName, operator, operandValue = "") {
    const meta = this.getColumnMeta(fieldApiName);
    const supported = this.buildOperatorOptions(fieldApiName);
    const resolvedOperator =
      operator ||
      meta?.defaultFilterOperator ||
      supported[0]?.value ||
      "Contains";

    const fallback =
      this.findColumn(fieldApiName)?.label || meta?.label || fieldApiName;

    return {
      key: `filter-${filterKeyCounter++}`,
      fieldApiName,
      label: this.getColumnLabel(fieldApiName, fallback),
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
   * The "x" on a promoted tab. Only removes it from the strip — the tab
   * itself is one of the page's configured views, so there's nothing to
   * delete, and if it's the one on screen this falls back to the first
   * configured tab rather than leaving the strip on a tab it no longer shows.
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
      const fallback = this.configuredTabs[0]?.value;
      if (fallback) {
        this.selectTabView(fallback);
      }
    }
  }

  selectTabView(listViewApiName) {
    this.openPopover = "";
    this.searchTerm = "";
    this.groupFieldApiName = "";
    // Column choices are per view — the next view has its own field set. Whichever fields the
    // view's own configuredDefaultColumns leaves out of its explicit order default back to hidden
    // (applyDefaultColumns), so a field just needs to be left out of a tab's `columns` config to
    // start hidden by default here, rather than needing a separate hidden-fields list.
    this.hiddenColumnFields = [];
    this.isLoading = true;
    // Cleared rather than left stale: the new tab's own set lands via
    // rebuildColumns once its columns wire settles (see there).
    this._groupFieldEntries = [];
    this._filterFieldEntries = [];
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
      this.openPopover = "";
      this.searchTerm = "";
      this.groupFieldApiName = "";
      this.isLoading = true;
      this._groupFieldEntries = [];
      this._filterFieldEntries = [];
      this.selectedListViewApiName = next.value;
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

  /**
   * Opens the create dialog. It used to navigate to the object's standard
   * "new" page, which an LWR site has no route for — the click simply took
   * you somewhere with no usable form. The `newrecord` event is kept so a
   * host page can still intercept and handle creation its own way.
   */
  handleNewRecord() {
    this.dispatchEvent(
      new CustomEvent("newrecord", {
        detail: { objectApiName: this.objectApiName }
      })
    );

    this.showCreateModal = true;
  }

  handleCreateClose() {
    this.showCreateModal = false;
  }

  /** Lands the user on the record they just made, and refreshes the list. */
  handleCreated(event) {
    const { recordId } = event.detail || {};
    this.showCreateModal = false;

    if (!recordId) {
      return;
    }

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
   * Field API names a tab wants on a generic create dialog, e.g.
   * `"createFields": "Client__c,Status__c,Amount__c"`. The only supported
   * create path now — a tab with a `newrecord` action but no `createFields`
   * has nothing to open and shows no button (see hasNewRecordAction).
   */
  get quickCreateFields() {
    return this.activeConfiguredTab?.createFields || "";
  }

  get usesQuickCreate() {
    return Boolean(this.quickCreateFields);
  }

  get showQuickCreateModal() {
    return this.showCreateModal && this.usesQuickCreate;
  }

  get createHeadingLabel() {
    return this.headingActionLabel || "Add record";
  }

  // ---- Interaction: popovers --------------------------------------------

  handleTogglePopover(event) {
    const popover = event.currentTarget.dataset.popover;
    this.openPopover = this.openPopover === popover ? "" : popover;
    this.resetFieldMenuSearch();
    this.pruneEmptyFilters();
  }

  handleBackdropClick() {
    this.openPopover = "";
    this.pruneEmptyFilters();
  }

  /**
   * Debounced for the same reason handleSearchInput is, and it matters more
   * here. fieldMenuSearch is component state, so setting it on every keystroke
   * re-rendered the whole list view — table, chips, tab strip — not just the
   * menu. Measured on Case that was ~90ms a key, and narrowing the menu from 50
   * matches to 7 barely moved it, which is what showed the cost was the
   * surrounding render rather than the option rows. The input keeps its own
   * typed text natively in between, so the box stays responsive.
   */
  handleFieldMenuSearch(event) {
    const value = event.target.value;
    window.clearTimeout(this._fieldMenuSearchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._fieldMenuSearchTimer = window.setTimeout(() => {
      this.fieldMenuSearch = value;
    }, FIELD_MENU_DEBOUNCE_MS);
  }

  handleGroupFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.value;
    this.groupFieldApiName =
      this.groupFieldApiName === fieldApiName ? "" : fieldApiName;
    this.openPopover = "";
    this.persistGrouping(this.selectedListViewApiName, this.groupFieldApiName);
  }

  handleClearGroup() {
    this.groupFieldApiName = "";
    this.openPopover = "";
    this.persistGrouping(this.selectedListViewApiName, "");
  }

  handleFilterFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.value;
    const chip = this.buildFilterChip(fieldApiName);
    this.activeFilters = [...this.activeFilters, chip];
    // Chip opens straight into its operator/value editor, as in the design.
    this.openPopover = chip.key;
    this.resetFieldMenuSearch();
  }

  /**
   * Clears the term and any keystroke still waiting out its debounce — without
   * dropping the timer, a pending one would write the old term back over the
   * cleared box after the menu had already moved on.
   */
  resetFieldMenuSearch() {
    window.clearTimeout(this._fieldMenuSearchTimer);
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
      // Once edited it is the user's filter, not the saved view's, so it
      // starts evaluating here on top of what the server already returned.
      return filter.key === key
        ? { ...filter, operator, serverApplied: false }
        : filter;
    });
  }

  handleChipValueChange(event) {
    const key = event.currentTarget.dataset.key;
    const operandValue = event.target.value;
    this.activeFilters = this.activeFilters.map((filter) => {
      return filter.key === key
        ? { ...filter, operandValue, serverApplied: false }
        : filter;
    });
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
      console.error("[nexSListView] Failed to overwrite list view", error);
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

      // Before the tab switch below moves selectedListViewApiName on.
      this.persistViewBase(createdApiName, this.selectedListViewApiName);

      this.showSaveViewModal = false;
      this._savedSignature = this.currentSignature;
      this._createdViewApiNames.add(createdApiName);
      // Grouping is part of what the user set up before hitting Save, so it
      // travels to the new view even though the list view itself cannot hold
      // it. Recorded against the new name before switching, so the wire that
      // fires on the switch reads it back rather than finding nothing.
      this.persistGrouping(createdApiName, this.groupFieldApiName);
      this._groupedListViewApiName = createdApiName;

      if (!this.listViews.some((lv) => lv.value === createdApiName)) {
        this.listViews = [
          ...this.listViews,
          { label, value: createdApiName, visibility: "Private" }
        ];
      }

      // createListInfo doesn't invalidate the getListInfosByObjectName wire's
      // own LDS cache — the manual append above only patches THIS instance's
      // in-memory listViews. Without this, a fresh mount later (e.g. the user
      // navigates away and back) can still be served the pre-creation cached
      // list, silently dropping the new tab. Not awaited: the local append
      // already makes this instance correct immediately.
      refreshApex(this._listInfosWire).catch(() => {
        /* Best-effort — the manual append above covers this instance either way. */
      });
      // Same reason, for the wire that decides whether the view is the user's
      // own: without it the new tab would rest on _createdViewApiNames alone
      // and disappear on the next mount.
      refreshApex(this._savedViewNamesWire).catch(() => {
        /* Best-effort — _createdViewApiNames covers this instance meanwhile. */
      });

      // Switching to the just-created view's api name is itself the reactive
      // trigger that re-runs getListInfoByName/getListRecordsByName for it —
      // a brand-new api name the wires have never queried, so there's no
      // stale cache to bust. Calling refreshListData() here instead forces a
      // refetch through this._listInfoWire/this._recordsWire, which still
      // hold the OLD view's wire config at this point in the synchronous
      // call stack (the reactive re-wire for the new api name hasn't run
      // yet) — so it reloads the view just switched away from, and the
      // table only reflects the new one once/if something else happens to
      // re-render it. Setting isLoading gives the same "data's on its way"
      // affordance selectTabView already shows on a tab switch.
      this.isLoading = true;
      this.selectedListViewApiName = createdApiName;
    } catch (error) {
      this.saveViewError = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[nexSListView] Failed to save list view", error);
    } finally {
      this.isSavingView = false;
    }
  }

  // ---- Interaction: delete view ------------------------------------------

  get deleteViewTargetLabel() {
    return this.deleteViewTarget?.label || "";
  }

  handleDeleteViewClick(event) {
    // The delete button sits next to (not inside) the tab button, but stop
    // the click from bubbling to anything else listening on the tab strip.
    event.stopPropagation();
    const value = event.currentTarget.dataset.value;
    if (!value) {
      return;
    }
    this.deleteViewTarget = {
      value,
      label: event.currentTarget.dataset.label || value
    };
    this.deleteViewError = undefined;
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
      this.savedViewApiNames = this.savedViewApiNames.filter(
        (apiName) => apiName !== target.value
      );
      this.removePersistedViewBase(target.value);
      this.persistGrouping(target.value, "");

      // Same reasoning as the create path — deleteListInfo doesn't invalidate
      // the getListInfosByObjectName wire's own cache, so without this a
      // fresh mount could still see the deleted view in a stale cached list.
      refreshApex(this._listInfosWire).catch(() => {
        /* Best-effort — the manual filter above covers this instance either way. */
      });
      refreshApex(this._savedViewNamesWire).catch(() => {
        /* Best-effort — the manual filter above covers this instance either way. */
      });

      if (this.selectedListViewApiName === target.value) {
        const fallback =
          this.configuredTabs[0]?.value || this.defaultListViewApiName;
        this.isLoading = true;
        this.selectedListViewApiName = fallback;
      }

      this.showDeleteViewModal = false;
      this.deleteViewTarget = null;
    } catch (error) {
      this.deleteViewError = this.reduceError(error);
      // eslint-disable-next-line no-console
      console.error("[nexSListView] Failed to delete list view", error);
    } finally {
      this.isDeletingView = false;
    }
  }

  /**
   * @param includeEmptyFilters send an empty filteredByInfo instead of omitting
   * it, so overwriting a view after "Clear Filters" actually clears them.
   */
  buildListInfoPayload({ includeEmptyFilters = false } = {}) {
    const requested = this.visibleColumnDefs.map((col) => col.fieldApiName);
    // Who.Name/What.Name (Task/Event's polymorphic lookups) and
    // Owner.NameOrAlias are read-only synthetic columns the Lists API
    // derives for display — getListInfoByName returns them fine, but
    // createListInfo/updateListInfoByName reject them outright ("Something's
    // not right with your input parameters"), failing the save entirely.
    // Drop them from the saved column set; the real Financial_Advisor_Team__r
    // /Owner.FirstName-style relationship columns are ordinary lookups and
    // save without issue. Falls back to the unfiltered list on the (unlikely)
    // chance every visible column was one of these, so the payload is never
    // sent with zero display columns.
    const filtered = requested.filter(
      (name) => !NON_SAVABLE_DISPLAY_COLUMNS.has(name)
    );
    const displayColumns = filtered.length ? filtered : requested;
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
          label: this.getColumnLabel(
            col.fieldApiName,
            col.label || col.fieldApiName
          ),
          checked,
          isLocked,
          trackClass: `nexs-list-view__toggle nexs-list-view__toggle--${modifier}`
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
    if (this._recordsWire) {
      refreshTasks.push(refreshApex(this._recordsWire));
    }
    if (refreshTasks.length) {
      await Promise.all(refreshTasks);
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

  /**
   * List view developerName has a hard 40-character limit (this previously
   * budgeted for 80, so anything past a short label silently failed
   * createListInfo with "exceeds the 40 character limit" — every save-as-new
   * attempt whose label + a full-UUID suffix ran past 40 chars, which in
   * practice was most of them). An 8-hex-char suffix (~4.3 billion values) is
   * still effectively collision-free for one user's saved views and leaves
   * room for the label to stay legible within the limit.
   */
  buildListViewApiName(label) {
    const base = this.toApiName(label);
    if (!base) {
      return "";
    }
    const MAX_DEVELOPER_NAME_LENGTH = 40;
    const SUFFIX_LENGTH = 8;
    const suffix = (
      typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
        ? crypto.randomUUID().replace(/-/g, "")
        : `${Date.now()}${Math.random().toString(36).slice(2)}`
    ).slice(0, SUFFIX_LENGTH);
    const maxBaseLength = Math.max(
      1,
      MAX_DEVELOPER_NAME_LENGTH - 1 - suffix.length
    );
    return `${base.substring(0, maxBaseLength)}_${suffix}`;
  }

  reduceError(error) {
    if (!error) {
      return "Unknown error";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }

    // The UI API's own validation failures carry a generic top-level message
    // ("Something's not right with your input parameters...") with the
    // actual reason nested under output.errors/fieldErrors — surface those
    // instead of the generic text whenever they're present.
    const output = error.body?.output;
    const detailParts = [
      ...(Array.isArray(output?.errors)
        ? output.errors.map((e) => e.message).filter(Boolean)
        : []),
      ...(output?.fieldErrors && typeof output.fieldErrors === "object"
        ? Object.values(output.fieldErrors)
            .flat()
            .map((e) => e?.errorMessage || e?.message)
            .filter(Boolean)
        : [])
    ];
    if (detailParts.length) {
      return detailParts.join(" ");
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