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
  updateListInfoByName
} from "lightning/uiListsApi";
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
/** Saved views past this count collapse into the trailing "More" tab menu. */
const MAX_VISIBLE_TABS = 5;

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
  filterLogicString = "";
  objectColumns = [];
  currentListViewLabel = "";
  _savedSignature = "";
  _adoptedListViewApiName = "";
  /** Views saved from this component this session, so they tab up immediately. */
  _createdViewApiNames = new Set();
  _appliedTabParam = "";
  _pageRef;
  _searchTimer;
  _stylesLoaded = false;
  _listInfosWire;
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

  disconnectedCallback() {
    window.clearTimeout(this._searchTimer);
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
          action: entry.action || ""
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

  get visibleTabs() {
    return this.buildTabs(this.tabListViews.slice(0, MAX_VISIBLE_TABS));
  }

  get overflowTabs() {
    return this.buildTabs(this.tabListViews.slice(MAX_VISIBLE_TABS));
  }

  get hasOverflowTabs() {
    return this.tabListViews.length > MAX_VISIBLE_TABS;
  }

  buildTabs(listViews) {
    return listViews.map((lv) => {
      const isActive = lv.value === this.selectedListViewApiName;
      return {
        ...lv,
        isActive,
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
    const meta = this.getColumnMeta(this.groupFieldApiName);
    return this.groupFieldApiName
      ? `Group: ${meta?.label || this.groupFieldApiName}`
      : "Group";
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

  get groupableObjectColumns() {
    return (this.objectColumns || []).filter((col) => col.sortable !== false);
  }

  get filterableObjectColumns() {
    return (this.objectColumns || []).filter((col) => col.filterable);
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
      this.columns = displayColumns.map((col) => ({
        fieldApiName: col.fieldApiName || col.fieldName || col.label,
        label: col.label || col.fieldApiName
      }));
      this.currentListViewLabel = data.label || this.selectedListViewApiName;
      this.filterLogicString = data.filterLogicString || "";
      this.adoptSavedFilters(data.filteredByInfo || []);
      this.errorMessage = undefined;
    } else if (error && this.selectedListViewApiName) {
      this.errorMessage = this.reduceError(error);
      this.columns = [];
    }
  }

  @wire(getListRecordsByName, {
    objectApiName: "$objectApiName",
    listViewApiName: "$selectedListViewApiName",
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

    return {
      key: `filter-${filterKeyCounter++}`,
      fieldApiName,
      label: meta?.label || fieldApiName,
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
    this.selectTabView(listViewApiName);
  }

  selectTabView(listViewApiName) {
    this.openPopover = "";
    this.searchTerm = "";
    this.groupFieldApiName = "";
    // Column choices are per view — the next view has its own field set.
    this.hiddenColumnFields = [];
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
      this.openPopover = "";
      this.searchTerm = "";
      this.groupFieldApiName = "";
      this.isLoading = true;
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