/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Reusable diversify-styled data table: client-side sorting, anchor record links,
 * optional row-action menu, and optional built-in pagination. Self-contained CSS
 * (no diversifyStyles static resource).
 *
 * Forked from Vestolio's styledDataTable for ARC's arcRecordListView. Launchpad's
 * own shared styledDataTable is untouched -- this is a separate component so ARC
 * gets this design without changing anything for styledDataTable's existing
 * consumers.
 */
import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import {
  buildExperienceRecordPath,
  buildRecordNavigationReference,
  hasActiveTextSelection,
  resolveObjectApiNameFromRecordId,
  resolveRecordUrl,
  shouldAllowNativeRecordNavigation,
  usesQueryParamRecordRoute
} from "c/recordNavigationCommunityUtils";
import {
  SORT_ASC,
  createSortState,
  resolveSortDirection,
  sortRecords
} from "c/dataTableSortUtils";

const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50];
const CARET_RIGHT_ICON = "caret-right.svg";
/** Narrow enough to tuck a column away, wide enough to keep its grip grabbable. */
const MIN_COLUMN_WIDTH = 56;

/**
 * Coerces a public boolean property.
 *
 * A valueless attribute -- `enable-row-navigation` with nothing after it --
 * arrives as the empty string and must read as TRUE. That is why these setters
 * cannot simply call Boolean(value), and why the original
 * `value !== false && value !== "false"` was written the way it was.
 *
 * But that expression returns TRUE for undefined, null and 0, so a caller
 * passing an expression that has not resolved yet switches the property ON.
 * That is not theoretical: arcRecordListView passes
 * has-more-rows={hasMoreServerRows} and is-loading-more={isLoadingMoreRows},
 * and _hasMoreServerRows is assigned straight from batch.hasMore -- undefined
 * whenever the Apex response omits it -- so the getter yields undefined and the
 * table reads it as true. A load-more spinner then shows with nothing able to
 * clear it.
 *
 * Applied only to the properties whose backing field defaults to false.
 * enablePagination defaults to TRUE and genuinely means "on unless explicitly
 * turned off", so it keeps the original comparison.
 */
const toBooleanProperty = (value) => {
  if (value === "") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  return Boolean(value);
};

export default class ArcDataTable extends NavigationMixin(LightningElement) {
  @api keyField = "id";
  @api rowActions = [];
  @api placeholder = "";
  @api title = "";
  @api ariaLabel = "Data table";
  @api defaultLinkObjectApiName = "";
  @api linkObjectApiNameField = "objectApiName";

  // Field whose value bands the body into full-width group rows (Figma "Save &
  // Preview View": Trustee / Primary / Spouse). Empty string disables grouping.
  @api groupField = "";
  /**
   * "comfortable" gives the taller, larger-type rows the list-view design
   * calls for. Anything else keeps the compact default every other consumer
   * of this table already renders.
   */
  @api density = "";
  /**
   * Optional glyph URLs (typically from a static resource). Supplied, they are
   * masked over currentColor; blank keeps the stock lightning-icon. They are
   * published as custom properties on the host so the stylesheet, rather than
   * a per-element style attribute, decides where each one is used.
   */
  @api columnSettingsIconUrl = "";
  @api avatarIconUrl = "";
  /**
   * Caps how many numbered pages the pager shows, ellipses aside. Blank keeps
   * the wider default window every other consumer already renders.
   */
  @api maxPageButtons = "";
  // Renders a column-settings button in the trailing header cell; emits
  // `columnsettings` so the host can open its own column manager.
  _showColumnSettings = false;
  @api
  get showColumnSettings() {
    return this._showColumnSettings;
  }
  set showColumnSettings(value) {
    this._showColumnSettings = toBooleanProperty(value);
  }

  // Lets the header's own columns be dragged into a new order — off by
  // default so every other consumer of this shared table is unaffected.
  // Emits `columnreorder` with the full reordered field-API-name list;
  // rendering the new order (and, for nexSListView, persisting it on Save
  // View) is the host's job.
  _enableColumnReorder = false;
  @api
  get enableColumnReorder() {
    return this._enableColumnReorder;
  }
  set enableColumnReorder(value) {
    this._enableColumnReorder = toBooleanProperty(value);
  }

  // HTML's `draggable` is a tri-state attribute ("true"/"false"/"auto"), not
  // a boolean one — binding the flag straight in would render `draggable`
  // (i.e. "true") even when off, so header cells stay draggable via the
  // string value this getter resolves to.
  get columnDraggable() {
    return this._enableColumnReorder ? "true" : "false";
  }

  _dragFieldName = null;

  /**
   * Lets a user drag a column's trailing edge to widen or narrow it.
   *
   * Widths live for as long as the table is mounted and are keyed by field
   * name, so reordering or re-sorting carries them along; they are deliberately
   * not persisted, since a width that follows one browser and not the next is
   * more confusing than one that simply starts from the content again.
   */
  _enableColumnResize = false;
  @api
  get enableColumnResize() {
    return this._enableColumnResize;
  }
  set enableColumnResize(value) {
    this._enableColumnResize = toBooleanProperty(value);
  }

  /**
   * Names the slot widths are remembered under, e.g.
   * "nexSListView.colWidths.Case.All_Cases". Blank keeps them in memory only.
   */
  _widthStorageKey = "";
  @api
  get columnWidthStorageKey() {
    return this._widthStorageKey;
  }
  set columnWidthStorageKey(value) {
    this._widthStorageKey = value || "";
    // A different key is a different table (another object, another view), so
    // its widths replace rather than inherit the ones on screen.
    this.columnWidths = this.readStoredWidths();
  }

  /** { [fieldName]: px }. Empty until the first drag; see handleResizeStart. */
  @track columnWidths = {};
  _resize = null;

  readStoredWidths() {
    if (!this._widthStorageKey) {
      return {};
    }
    try {
      const raw = window.localStorage.getItem(this._widthStorageKey);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      /* Private browsing or a full quota — widths still work for this page. */
      return {};
    }
  }

  storeWidths(widths) {
    if (!this._widthStorageKey) {
      return;
    }
    try {
      window.localStorage.setItem(
        this._widthStorageKey,
        JSON.stringify(widths)
      );
    } catch {
      /* As above: losing the write costs the user nothing this session. */
    }
  }


  _enablePagination = true;
  @api
  get enablePagination() {
    return this._enablePagination;
  }
  set enablePagination(value) {
    this._enablePagination = value !== false && value !== "false";
  }

  // Dashboard-preview footer: keeps row slicing to pageSize active (rows
  // still cap at pageSize) but swaps the pager UI (page-size select +
  // prev/next) for a "Showing X of Y" + View All row, inside the same
  // footer/card border the pager would otherwise occupy.
  _showFooterViewAll = false;
  @api
  get showFooterViewAll() {
    return this._showFooterViewAll;
  }
  set showFooterViewAll(value) {
    this._showFooterViewAll = toBooleanProperty(value);
  }

  @api viewAllUrl = "";

  /**
   * Tells the pager there's more data on the server past whatever `data`
   * currently holds -- a caller doing keyset-paginated server fetches (see
   * arcRecordListView's runServerSearch) only ever hands over the rows
   * it's fetched so far, never the true remote total, so pageCount can't
   * know about the rest on its own. One extra page button appears at the
   * end while this is true; clicking into it (past what local data
   * supports) fires `loadmore` instead of silently rendering an empty
   * page, so the caller gets a chance to fetch the next batch and append
   * it before the click resolves.
   */
  _hasMoreRows = false;
  @api
  get hasMoreRows() {
    return this._hasMoreRows;
  }
  set hasMoreRows(value) {
    this._hasMoreRows = toBooleanProperty(value);
  }

  /**
   * True while the caller's own loadmore fetch (triggered by this table)
   * is in flight. The page the user clicked into has no rows yet -- see
   * isDataAppendOnly -- so showEmptyRow would otherwise render
   * emptyMessage ("No results found") for what is actually a normal,
   * brief loading state, not an empty result.
   */
  _isLoadingMore = false;
  @api
  get isLoadingMore() {
    return this._isLoadingMore;
  }
  set isLoadingMore(value) {
    this._isLoadingMore = toBooleanProperty(value);
  }

  get viewAllIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_RIGHT_ICON}');`;
  }

  get footerViewAllLabel() {
    const shown = Math.min(this._pageSize, this.totalRows);
    return `Showing ${shown} of ${this.totalRows}`;
  }

  get showFooter() {
    return this.totalRows > 0 && (this.showPager || this._showFooterViewAll);
  }

  handleViewAllClick() {
    if (!this.viewAllUrl) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: `${communityBasePath}${this.viewAllUrl}`
      }
    });
  }

  _enableRowClick = false;
  @api
  get enableRowClick() {
    return this._enableRowClick;
  }
  set enableRowClick(value) {
    this._enableRowClick = toBooleanProperty(value);
  }

  /**
   * Whole-row click navigates to the row's record — independent of
   * `enableRowClick`/`rowclick`, which existing consumers (workTable's
   * expand toggle, envelopeTable's edit modal) already repurpose for
   * their own thing. Actions-cell and expand-button clicks stop
   * propagation before this ever sees them (handleActionCellClick,
   * handleExpandChevronClick), so they never trigger navigation.
   */
  _enableRowNavigation = false;
  @api
  get enableRowNavigation() {
    return this._enableRowNavigation;
  }
  set enableRowNavigation(value) {
    this._enableRowNavigation = toBooleanProperty(value);
  }

  /**
   * Opts a table out of primaryColumnIndex's own default: when no column
   * sets isLink/primary, it still falls back to column 0 so every existing
   * table that never bothered to flag one keeps its first column looking
   * and behaving like a link. A table with genuinely nothing to link to
   * (Advertising Item History's Date/Field/User/Original/New Value) has no
   * good column for that fallback to land on, so it opts out entirely
   * instead of one column looking clickable toward an empty href.
   */
  _disableLinks = false;
  @api
  get disableLinks() {
    return this._disableLinks;
  }
  set disableLinks(value) {
    this._disableLinks = toBooleanProperty(value);
  }

  @api rowDetailType = "";
  @api rowDetailGroupsField = "taskGroups";
  @api detailRowActions = [];

  _expandedRowIds = [];
  @api
  get expandedRowIds() {
    return this._expandedRowIds;
  }
  set expandedRowIds(value) {
    if (Array.isArray(value)) {
      this._expandedRowIds = [...value];
      return;
    }

    if (typeof value === "string" && value.trim()) {
      this._expandedRowIds = value.split(",").map((entry) => entry.trim());
      return;
    }

    this._expandedRowIds = [];
  }

  /** @deprecated Use expandedRowIds */
  @api
  get expandedRowId() {
    return this._expandedRowIds[0] || null;
  }
  set expandedRowId(value) {
    this._expandedRowIds = value ? [value] : [];
  }

  @api emptyMessage = "No results found";
  // Comma-separated object API names whose experience links use /{route}?id={recordId}
  // instead of /{route}/{recordId}. Example: "Envelope__c".
  @api linkQueryParamObjectApiNames = "";

  _pageSize = 10;
  @api
  get pageSize() {
    return this._pageSize;
  }
  set pageSize(value) {
    this._pageSize = Math.max(1, Number(value) || 10);
    this.page = 1;
  }

  _pageSizeOptions = DEFAULT_PAGE_SIZE_OPTIONS;
  @api
  get pageSizeOptions() {
    return this._pageSizeOptions;
  }
  set pageSizeOptions(value) {
    this._pageSizeOptions =
      Array.isArray(value) && value.length
        ? [...value]
        : DEFAULT_PAGE_SIZE_OPTIONS;
  }

  _columns = [];
  @api
  get columns() {
    return this._columns;
  }
  set columns(value) {
    this._columns = Array.isArray(value) ? [...value] : [];
    this.applyCurrentSort();
  }

  _sourceData = [];
  @api
  get data() {
    return this._sourceData;
  }
  set data(value) {
    const nextData = Array.isArray(value) ? [...value] : [];
    // A load-more append (see arcRecordListView's loadmore handling) hands
    // back a longer array on the SAME page the user just clicked into --
    // resetting to page 1 here would undo that click the instant its own
    // fetch resolved. Only a genuine replacement (new search, new tab,
    // fewer rows) should snap the pager back to page 1.
    const isAppendOnly = this.isDataAppendOnly(this._sourceData, nextData);

    this._sourceData = nextData;

    if (!isAppendOnly) {
      this.page = 1;
    }

    this.applyCurrentSort();
    this.resolveRecordUrls(this._sourceData);
  }

  _defaultSortField = "";
  @api
  get defaultSortField() {
    return this._defaultSortField;
  }
  set defaultSortField(value) {
    this._defaultSortField = value || "";
    this.initializeSortState();
  }

  _defaultSortDirection = SORT_ASC;
  @api
  get defaultSortDirection() {
    return this._defaultSortDirection;
  }
  set defaultSortDirection(value) {
    this._defaultSortDirection = value || SORT_ASC;
    this.initializeSortState();
  }

  sortedBy = "";
  sortedDirection = SORT_ASC;
  sortedData = [];
  recordUrlById = {};
  page = 1;
  @track _detailGroupExpansion = {};

  // Whether the table's own scroll cues (see .div-table-scroll__fade) show at
  // each edge -- recomputed on scroll, on window resize, and after every
  // render (covers column/row changes that resize the table's content
  // without necessarily resizing the viewport window itself).
  _canScrollLeft = false;
  _canScrollRight = false;
  _handleWindowResize;

  connectedCallback() {
    this.initializeSortState();
    this.applyIconVariables();
    this._handleWindowResize = () => this.updateScrollFadeState();
    window.addEventListener("resize", this._handleWindowResize);
  }

  renderedCallback() {
    // The URLs arrive as public properties, so re-publish after each render.
    this.applyIconVariables();

    // The menu has to exist before it can be measured, so it is placed on the
    // render after it opens. positionActionMenu reassigns _actionMenu and so
    // renders once more; the flags keep that from looping. Focus waits for that
    // second render: until it lands the menu is still visibility:hidden, and
    // focus() on a hidden element is a no-op.
    if (this._actionMenuNeedsPosition) {
      this._actionMenuNeedsPosition = false;
      this._actionMenuNeedsFocus = true;
      this.positionActionMenu();
    } else if (this._actionMenuNeedsFocus) {
      this._actionMenuNeedsFocus = false;
      this.template.querySelector(".arc-data-table__menu-item")?.focus();
    }

    this.updateScrollFadeState();
  }

  get leftScrollFadeClass() {
    return this._canScrollLeft
      ? "div-table-scroll__fade div-table-scroll__fade--left div-table-scroll__fade--visible"
      : "div-table-scroll__fade div-table-scroll__fade--left";
  }

  get rightScrollFadeClass() {
    return this._canScrollRight
      ? "div-table-scroll__fade div-table-scroll__fade--right div-table-scroll__fade--visible"
      : "div-table-scroll__fade div-table-scroll__fade--right";
  }

  handleTableScroll() {
    this.updateScrollFadeState();
  }

  /**
   * A small epsilon rather than a strict >0/<max comparison -- sub-pixel
   * scroll positions (fractional zoom levels, some browsers' rounding) would
   * otherwise leave a fade very faintly stuck on at a true scroll extreme.
   */
  updateScrollFadeState() {
    const scroller = this.template.querySelector(".div-table-scroll");
    if (!scroller) {
      return;
    }

    const canScrollLeft = scroller.scrollLeft > 2;
    const canScrollRight =
      scroller.scrollWidth - scroller.clientWidth - scroller.scrollLeft > 2;

    if (canScrollLeft !== this._canScrollLeft) {
      this._canScrollLeft = canScrollLeft;
    }
    if (canScrollRight !== this._canScrollRight) {
      this._canScrollRight = canScrollRight;
    }
  }

  initializeSortState() {
    const sortState = createSortState({
      fieldName: this._defaultSortField,
      direction: this._defaultSortDirection,
      records: this._sourceData,
      columns: this._columns
    });

    this.sortedBy = sortState.sortedBy;
    this.sortedDirection = sortState.sortedDirection;
    this.sortedData = sortState.sortedData;
  }

  get hasRows() {
    return this.paginatedData.length > 0;
  }

  get hasTitle() {
    return Boolean(this.title?.trim());
  }

  get hasColumnSettingsMask() {
    return Boolean(this.columnSettingsIconUrl);
  }

  applyIconVariables() {
    this.style.setProperty(
      "--adt-icon-columns",
      this.columnSettingsIconUrl ? `url('${this.columnSettingsIconUrl}')` : ""
    );
    this.style.setProperty(
      "--adt-icon-avatar",
      this.avatarIconUrl ? `url('${this.avatarIconUrl}')` : ""
    );
  }

  get isComfortable() {
    return this.density === "comfortable";
  }

  get cardClass() {
    return this.density === "comfortable"
      ? "div-table-card div-table--comfortable-card"
      : "div-table-card";
  }

  get tableClass() {
    const classes = ["div-table"];
    if (this.density === "comfortable") {
      classes.push("div-table--comfortable");
    }
    // Column widths are only honoured reliably under a fixed layout — with the
    // default auto layout the browser treats a cell width as a suggestion and
    // re-solves it against the content. The class only appears once a drag has
    // seeded every column, so a table nobody has resized keeps sizing itself.
    if (this.hasColumnWidths) {
      classes.push("div-table--resized");
    }
    return classes.join(" ");
  }

  get hasColumnWidths() {
    return Object.keys(this.columnWidths).length > 0;
  }

  buildHeaderStyle(column) {
    const width = this.columnWidths[column.fieldName];
    return width ? `width: ${width}px;` : "";
  }

  get emptyColspan() {
    return this._columns.length + (this.hasTrailingColumn ? 1 : 0);
  }

  get hasTrailingColumn() {
    return this.hasRowActions || this._showColumnSettings;
  }

  get showEmptyRow() {
    return !this.hasRows && this._columns.length > 0;
  }

  applyCurrentSort() {
    this.sortedData = this.sortedBy
      ? sortRecords(
          this._sourceData,
          this.sortedBy,
          this.sortedDirection,
          this._columns
        )
      : [...this._sourceData];
  }

  /**
   * True when nextData is previousData unchanged, or previousData with more
   * rows appended after it, either way in the same order -- everything else
   * (a shorter list, a reordered or replaced one, the very first load) is a
   * genuine dataset change the pager should reset for, not a fetch extending
   * the page the user is already on.
   *
   * The equal-length case matters because the host's `data` binding is
   * commonly a derived getter (e.g. a live client-side filter) that returns
   * a brand-new array reference on every render, including renders with no
   * real content change -- such as the one a load-more fetch's own loading
   * flag triggers before its new rows have even arrived. Treating "same
   * length, same rows" as a reset-worthy change would snap the page back to
   * 1 on that intermediate render, before the appended batch this same
   * click asked for ever gets a chance to land on it.
   */
  isDataAppendOnly(previousData, nextData) {
    const previousRows = Array.isArray(previousData) ? previousData : [];
    const nextRows = Array.isArray(nextData) ? nextData : [];

    if (!previousRows.length || nextRows.length < previousRows.length) {
      return false;
    }

    const keyField = this.keyField;

    for (let index = 0; index < previousRows.length; index += 1) {
      const previousKey = `${previousRows[index]?.[keyField] ?? ""}`;
      const nextKey = `${nextRows[index]?.[keyField] ?? ""}`;

      if (previousKey !== nextKey) {
        return false;
      }
    }

    return true;
  }

  get hasRowActions() {
    return Array.isArray(this.rowActions) && this.rowActions.length > 0;
  }

  get hasDetailRowActions() {
    return (
      Array.isArray(this.detailRowActions) && this.detailRowActions.length > 0
    );
  }

  get totalRows() {
    return this.sortedData.length;
  }

  /** Full pages the data on hand actually supports -- see pageCount. */
  get localPageCount() {
    return Math.max(1, Math.ceil(this.totalRows / this._pageSize));
  }

  /**
   * One page longer than the data on hand while hasMoreRows is true, so a
   * trailing page button always exists for the user to click into --
   * clicking it is what asks the caller (see emitPageChange) to fetch the
   * next batch, rather than the pager just running out of pages at
   * whatever happened to be loaded first.
   */
  get pageCount() {
    return this.localPageCount + (this._hasMoreRows ? 1 : 0);
  }

  get clampedPage() {
    return Math.min(this.page, this.pageCount);
  }

  /**
   * Sorted data re-ordered so rows sharing a group value stay contiguous, which
   * is what lets the body emit one band row per group. Stable within a group, so
   * the active column sort still decides the order inside each band.
   */
  get orderedData() {
    if (!this.groupField) {
      return this.sortedData;
    }

    const buckets = new Map();

    for (const record of this.sortedData) {
      const groupValue = this.resolveGroupValue(record);

      if (!buckets.has(groupValue)) {
        buckets.set(groupValue, []);
      }

      buckets.get(groupValue).push(record);
    }

    return [...buckets.values()].flat();
  }

  resolveGroupValue(record) {
    const value = record?.[this.groupField];
    return value == null || value === "" ? "" : `${value}`;
  }

  get paginatedData() {
    if (!this._enablePagination) {
      return this.orderedData;
    }

    const start = (this.clampedPage - 1) * this._pageSize;
    return this.orderedData.slice(start, start + this._pageSize);
  }

  get showPager() {
    return (
      this._enablePagination && this.totalRows > 0 && !this._showFooterViewAll
    );
  }

  get pageSizeSelectValue() {
    return String(this._pageSize);
  }

  get resolvedPageSizeOptions() {
    return this._pageSizeOptions?.length
      ? this._pageSizeOptions
      : DEFAULT_PAGE_SIZE_OPTIONS;
  }

  get pageSizeOptionViews() {
    const current = this._pageSize;

    return this.resolvedPageSizeOptions.map((option) => {
      const value = Number(option);
      return {
        key: String(value),
        value: String(value),
        label: String(value),
        isSelected: value === current
      };
    });
  }

  get prevDisabled() {
    return this.clampedPage <= 1;
  }

  get nextDisabled() {
    return this.clampedPage >= this.pageCount;
  }

  /**
   * Fixed-width window: first and last page always present, the rest centred on
   * the current page, with a gap wherever the run skips a page. Figma's footer
   * shows five numbers — "1 2 3 … 9 10" on page 1 (532:35967).
   */
  buildCappedPages(count, current, cap) {
    if (count <= cap) {
      return Array.from({ length: count }, (unused, index) => index + 1);
    }

    const run = cap - 2;
    const half = Math.floor(run / 2);

    // Near the start or the end the window hugs that edge instead of centring.
    if (current - half <= 2) {
      return [
        ...Array.from({ length: run }, (unused, index) => index + 1),
        "gap-trail",
        ...Array.from({ length: 2 }, (unused, index) => count - 1 + index)
      ];
    }

    if (current + half >= count - 1) {
      return [
        1,
        2,
        "gap-lead",
        ...Array.from(
          { length: run },
          (unused, index) => count - run + 1 + index
        )
      ];
    }

    return [
      1,
      "gap-lead",
      ...Array.from({ length: run }, (unused, index) => current - half + index),
      "gap-trail",
      count
    ];
  }

  get pageItems() {
    const count = this.pageCount;
    const current = this.clampedPage;
    const cap = Number(this.maxPageButtons);
    let pages;

    if (cap >= 5) {
      pages = this.buildCappedPages(count, current, cap);
    } else if (count <= 7) {
      pages = [];
      for (let index = 1; index <= count; index += 1) {
        pages.push(index);
      }
    } else {
      let start = Math.max(2, current - 2);
      let end = Math.min(count - 1, current + 2);

      if (current <= 3) {
        start = 2;
        end = 5;
      }

      if (current >= count - 2) {
        start = count - 4;
        end = count - 1;
      }

      pages = [1];

      if (start > 2) {
        pages.push("gap-lead");
      }

      for (let index = start; index <= end; index += 1) {
        pages.push(index);
      }

      if (end < count - 1) {
        pages.push("gap-trail");
      }

      pages.push(count);
    }

    return pages.map((entry) => {
      if (typeof entry === "string") {
        return { key: entry, isGap: true };
      }

      const isCurrent = entry === current;
      return {
        key: `page-${entry}`,
        isGap: false,
        page: entry,
        label: String(entry),
        ariaCurrent: isCurrent ? "page" : null,
        cssClass: isCurrent
          ? "div-table-pager__btn div-table-pager__btn--current"
          : "div-table-pager__btn"
      };
    });
  }

  get primaryColumnIndex() {
    // A related-record link column (linkRecordIdField) links somewhere
    // else, so it can never be the row's own link.
    const flagged = this._columns.findIndex(
      (column) =>
        !column.linkRecordIdField &&
        (column.primary === true || column.isLink === true)
    );
    if (flagged !== -1) {
      return flagged;
    }
    return this._disableLinks ? -1 : 0;
  }

  buildHeaderClass(column) {
    if (column.type === "number") {
      return "div-table__cell--numeric";
    }

    if (column.type === "currency" || column.type === "percent") {
      return "div-table__cell--currency";
    }

    return "";
  }

  get headerColumns() {
    const primaryIndex = this.primaryColumnIndex;

    return this._columns.map((column, index) => {
      const isActive = this.sortedBy === column.fieldName;
      const isSortable = column.sortable !== false;
      const isAscending = this.sortedDirection === SORT_ASC;

      return {
        key: column.fieldName,
        label: column.label,
        sortable: isSortable,
        // Visible grab affordance — otherwise the only sign a header can be
        // dragged is a cursor change on hover, which nobody discovers. The
        // primary (record-link) column skips it: it can't be reordered
        // (see handleColumnDrop), so a handle on it would just be a dead end.
        showDragHandle: this._enableColumnReorder && index !== primaryIndex,
        // The last column has no trailing edge of its own to pull: it is
        // followed either by the actions cell or by the table's own edge, so a
        // grip there would resize against nothing.
        showResizeGrip:
          this._enableColumnResize &&
          (index < this._columns.length - 1 || this.hasTrailingColumn),
        headerStyle: this.buildHeaderStyle(column),
        headerClass: this.buildHeaderClass(column),
        ariaSort: isActive
          ? isAscending
            ? "ascending"
            : "descending"
          : "none",
        /* An unsorted column draws its idle affordance pointing down in the
           comfortable frame (Figma 532:35967 — all seven headers show ↓ and no
           more than one can be the sorted column). Other densities keep the
           existing up-arrow so their tables are unchanged. */
        sortIcon: isActive
          ? isAscending
            ? "utility:arrowup"
            : "utility:arrowdown"
          : this.isComfortable
            ? "utility:arrowdown"
            : "utility:arrowup",
        sortIconClass: isActive
          ? "div-table__sort-icon div-table__sort-icon--active"
          : "div-table__sort-icon"
      };
    });
  }

  handleColumnSettingsClick() {
    this.dispatchEvent(new CustomEvent("columnsettings"));
  }

  get expandedRowIdSet() {
    return new Set((this._expandedRowIds || []).map((rowId) => `${rowId}`));
  }

  get isWorkTaskDetail() {
    return this.rowDetailType === "workTasks";
  }

  isRowExpanded(rowKey) {
    return this.expandedRowIdSet.has(`${rowKey}`);
  }

  getRowDetailGroups(record) {
    if (!record) {
      return [];
    }

    const groups = record[this.rowDetailGroupsField];
    return Array.isArray(groups) ? groups : [];
  }

  hasExpandableRowDetail(record) {
    return this.getRowDetailGroups(record).some(
      (group) => Array.isArray(group.tasks) && group.tasks.length > 0
    );
  }

  get rows() {
    const primaryIndex = this.primaryColumnIndex;

    return this.paginatedData.map((record) => {
      const rowKey = record[this.keyField];
      const isExpanded = this.isRowExpanded(rowKey);
      const canExpandRow =
        this._enableRowClick && this.hasExpandableRowDetail(record);
      const primaryColumn =
        this._columns[primaryIndex] || this._columns[0] || {};
      const navigationObjectApiName = this.resolveObjectApiName(
        primaryColumn,
        record
      );
      const navigationRecordUrl =
        this.recordUrlById[rowKey] ||
        buildExperienceRecordPath(
          rowKey,
          navigationObjectApiName,
          this.buildLinkPathOptions(navigationObjectApiName)
        );
      const isNavigable = Boolean(
        this._enableRowNavigation && rowKey && navigationObjectApiName
      );
      const rowClass = [
        isExpanded ? "div-table__row--expanded" : "",
        isNavigable ? "div-table__row--clickable" : ""
      ]
        .filter(Boolean)
        .join(" ");

      return {
        key: rowKey,
        rowClass,
        isNavigable,
        navigationRecordUrl,
        navigationObjectApiName,
        groupValue: this.resolveGroupValue(record),
        cells: this._columns.map((column, index) => {
          const isExpandColumn = column.type === "expand";
          const showExpandChevron =
            !isExpandColumn &&
            canExpandRow &&
            column.showExpandChevron === true;
          /*
           * A column can link to a RELATED record instead of the row's own:
           * `linkRecordIdField` names the row field holding that record's id
           * (a task's Case Number -> WhatId, a check log's Client -> Client__c),
           * and `linkObjectApiName` its object -- or, for a polymorphic lookup,
           * the object is read off the id's key prefix. The cell is a link only
           * when the row actually carries an id; a blank lookup stays plain
           * text rather than pointing at nothing.
           */
          const relatedLinkField = column.linkRecordIdField || "";
          const relatedRecordId = relatedLinkField
            ? record[relatedLinkField] || ""
            : "";
          const isRelatedLinkColumn = Boolean(relatedLinkField);
          const isLinkColumn =
            !isExpandColumn &&
            !isRelatedLinkColumn &&
            (column.isLink === true ||
              column.primary === true ||
              index === primaryIndex);
          const objectApiName = isRelatedLinkColumn
            ? column.linkObjectApiName ||
              resolveObjectApiNameFromRecordId(relatedRecordId)
            : isLinkColumn
              ? this.resolveObjectApiName(column, record)
              : "";
          const linkPathOptions = this.buildLinkPathOptions(objectApiName);
          const linkRecordId = isRelatedLinkColumn ? relatedRecordId : rowKey;
          const recordUrl = isRelatedLinkColumn
            ? buildExperienceRecordPath(
                relatedRecordId,
                objectApiName,
                linkPathOptions
              )
            : this.recordUrlById[rowKey] ||
              buildExperienceRecordPath(rowKey, objectApiName, linkPathOptions);
          const rawValue = record[column.fieldName];
          const isPill = column.type === "pill";
          const pillClassField =
            column.pillClassField || `${column.fieldName}PillClass`;
          const displayValue = isPill
            ? (rawValue ?? this.placeholder)
            : this.formatCellValue(rawValue, column.type);

          return {
            key: column.fieldName,
            label: column.label,
            value: displayValue,
            cellClass: this.buildCellClass(
              column,
              isLinkColumn,
              isExpandColumn
            ),
            isLink: isRelatedLinkColumn
              ? Boolean(relatedRecordId && objectApiName)
              : Boolean(isLinkColumn && rowKey),
            // The avatar stands for the record, so it belongs to the column
            // that names it. isLinkColumn is also true of any other column
            // marked as a link, which would have repeated the glyph mid-row.
            hasAvatar: Boolean(
              (index === primaryIndex || column.primary === true) &&
              !isExpandColumn &&
              rowKey &&
              (column.avatarIcon || this.avatarIconUrl)
            ),
            // A masked glyph when the host supplied avatarIconUrl, otherwise
            // the original lightning-icon path.
            hasAvatarMask: Boolean(this.avatarIconUrl),
            avatarIcon: column.avatarIcon || "",
            isPill,
            isExpand: isExpandColumn,
            showExpandChevron,
            isExpanded,
            expandIcon: isExpanded
              ? "utility:chevrondown"
              : "utility:chevronright",
            expandAriaLabel: isExpanded ? "Collapse row" : "Expand row",
            pillClass: record[pillClassField] || "div-work-pill",
            recordId: linkRecordId,
            objectApiName,
            recordUrl,
            linkAriaLabel: displayValue ? `Open ${displayValue}` : "Open record"
          };
        })
      };
    });
  }

  get tableBodyItems() {
    const items = [];
    let currentGroup = null;

    for (const row of this.rows) {
      // The band repeats on every page whose first row continues a group, so a
      // paginated slice never shows unlabelled rows.
      if (this.groupField && row.groupValue !== currentGroup) {
        currentGroup = row.groupValue;
        items.push({
          key: `group-${row.key}`,
          isGroupRow: true,
          groupColspan: this.emptyColspan,
          groupLabel: currentGroup || this.placeholder || "—"
        });
      }

      items.push({
        key: row.key,
        isDataRow: true,
        row
      });

      if (!this.isRowExpanded(row.key)) {
        continue;
      }

      if (this.isWorkTaskDetail) {
        items.push(...this.buildWorkTaskDetailItems(row.key));
        continue;
      }

      items.push({
        key: `${row.key}-detail`,
        isDetailWrapper: true,
        detailTaskGroups: this.getRowDetailGroups(this.findRow(row.key))
      });
    }

    return items;
  }

  buildWorkTaskDetailItems(rowKey) {
    const taskGroups = this.getRowDetailGroups(this.findRow(rowKey));
    const detailColumnCount = 5 + (this.hasDetailRowActions ? 1 : 0);

    const groupViews = taskGroups.map((group) => {
      const isExpanded = this.isDetailGroupExpanded(rowKey, group.key);

      return {
        key: group.key,
        rowKey,
        groupKey: group.key,
        label: group.label,
        isExpanded,
        expandIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
        detailColumnCount,
        tasks: isExpanded
          ? (group.tasks || []).map((task) => this.enrichWorkTask(task))
          : []
      };
    });

    return [
      {
        key: `${rowKey}-work-detail`,
        isWorkDetailSection: true,
        rowKey,
        sectionColspan: this.emptyColspan,
        detailColumnCount,
        groupViews,
        hasGroups: groupViews.length > 0,
        hasDetailRowActions: this.hasDetailRowActions
      }
    ];
  }

  enrichWorkTask(task) {
    return {
      ...task,
      dueDate: task.dueDate || this.placeholder,
      completedDate: task.completedDate || this.placeholder,
      recordUrl: buildExperienceRecordPath(task.id, "Task"),
      linkAriaLabel: task.name ? `Open ${task.name}` : "Open task",
      statusPillClass:
        task.statusPillClass || "div-work-pill div-work-pill--not-started"
    };
  }

  isDetailGroupExpanded(rowKey, groupKey) {
    const expandedGroups = this._detailGroupExpansion[rowKey];

    if (!expandedGroups) {
      return true;
    }

    return expandedGroups.includes(groupKey);
  }

  getDefaultExpandedGroupKeys(rowKey) {
    return this.getRowDetailGroups(this.findRow(rowKey)).map(
      (group) => group.key
    );
  }

  handleDetailGroupToggle(event) {
    event.stopPropagation();

    const rowKey = event.currentTarget.dataset.rowKey;
    const groupKey = event.currentTarget.dataset.groupKey;

    if (!rowKey || !groupKey) {
      return;
    }

    const currentGroups =
      this._detailGroupExpansion[rowKey] ||
      this.getDefaultExpandedGroupKeys(rowKey);

    if (currentGroups.includes(groupKey)) {
      this._detailGroupExpansion = {
        ...this._detailGroupExpansion,
        [rowKey]: currentGroups.filter((key) => key !== groupKey)
      };
      return;
    }

    this._detailGroupExpansion = {
      ...this._detailGroupExpansion,
      [rowKey]: [...currentGroups, groupKey]
    };
  }

  handleDetailGroupKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleDetailGroupToggle(event);
  }

  handleDetailInteraction(event) {
    event.stopPropagation();
  }

  handleDetailTaskLinkClick(event) {
    event.stopPropagation();

    const openInNewContext = shouldAllowNativeRecordNavigation(event);
    if (openInNewContext) {
      return;
    }

    event.preventDefault();

    const recordId = event.currentTarget.dataset.recordId;
    if (!recordId) {
      return;
    }

    const pageReference = buildRecordNavigationReference(recordId, "Task");
    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  formatCellValue(value, columnType) {
    if (value === null || value === undefined || value === "") {
      return this.placeholder;
    }

    if (columnType === "currency") {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD"
      }).format(value);
    }

    if (columnType === "date" || columnType === "datetime") {
      const parsed = new Date(value);
      // A value that doesn't parse into a real date must not take the whole
      // table down with it -- render it as-is (still visible, still
      // debuggable) rather than letting Intl.DateTimeFormat throw on an
      // Invalid Date.
      if (Number.isNaN(parsed.getTime())) {
        return value;
      }
      return columnType === "datetime"
        ? new Intl.DateTimeFormat("en-US", {
            dateStyle: "short",
            timeStyle: "short"
          }).format(parsed)
        : new Intl.DateTimeFormat("en-US").format(parsed);
    }

    return value;
  }

  resolveObjectApiName(column, record) {
    if (column.linkObjectApiName) {
      return column.linkObjectApiName;
    }

    const fieldValue = record?.[this.linkObjectApiNameField];
    if (fieldValue) {
      return fieldValue;
    }

    return this.defaultLinkObjectApiName || "";
  }

  get queryParamLinkObjectApiNameSet() {
    if (!this.linkQueryParamObjectApiNames) {
      return new Set();
    }

    return new Set(
      this.linkQueryParamObjectApiNames
        .split(",")
        .map((entry) => entry.trim())
        .filter(Boolean)
    );
  }

  usesQueryParamLink(objectApiName) {
    return Boolean(
      objectApiName && this.queryParamLinkObjectApiNameSet.has(objectApiName)
    );
  }

  buildLinkPathOptions(objectApiName) {
    return {
      useQueryParam:
        this.usesQueryParamLink(objectApiName) ||
        usesQueryParamRecordRoute(objectApiName)
    };
  }

  buildCellClass(column, isLinkColumn, isExpandColumn) {
    const classes = [];

    if (column.type === "number") {
      classes.push("div-table__cell--numeric");
    }

    // Money/percent columns render right-aligned in the list-view design.
    if (column.type === "currency" || column.type === "percent") {
      classes.push("div-table__cell--currency");
    }

    // Data values — money, counts, dates, phone numbers — carry the design's
    // bold weight, while descriptive text stays regular. Kept on its own class
    // so tables that don't opt into the comfortable density are unaffected.
    if (
      ["number", "currency", "percent", "date", "datetime", "phone"].includes(
        column.type
      )
    ) {
      classes.push("div-table__cell--strong");
    }

    if (isExpandColumn) {
      classes.push("arc-data-table__cell--expand");
    }

    if (isLinkColumn) {
      classes.push("div-table__cell--link");
    }

    if (column.type === "pill") {
      classes.push("div-table__cell--pill");
    }

    if (column.cellClass) {
      classes.push(column.cellClass);
    }

    return classes.join(" ");
  }

  async resolveRecordUrls(rows) {
    if (!rows?.length) {
      this.recordUrlById = {};
      return;
    }

    const linkColumns = this._columns.filter(
      (column) =>
        !column.linkRecordIdField &&
        (column.isLink === true || column.primary === true)
    );

    if (!linkColumns.length && this.primaryColumnIndex === 0) {
      // Default first column may act as link when no explicit flag is set.
    }

    const uniqueRows = [
      ...new Map(rows.map((row) => [row[this.keyField], row])).values()
    ];
    const entries = await Promise.all(
      uniqueRows.map(async (row) => {
        const rowKey = row[this.keyField];
        const linkColumn =
          linkColumns[0] ||
          this._columns[this.primaryColumnIndex] ||
          this._columns[0];
        const objectApiName = linkColumn
          ? this.resolveObjectApiName(linkColumn, row)
          : this.defaultLinkObjectApiName;
        const linkPathOptions = this.buildLinkPathOptions(objectApiName);
        const url = await resolveRecordUrl(
          this,
          rowKey,
          objectApiName,
          linkPathOptions
        );
        return [rowKey, url];
      })
    );

    this.recordUrlById = Object.fromEntries(
      entries.filter(([, url]) => Boolean(url))
    );
  }

  handleSort(event) {
    const fieldName = event.currentTarget.dataset.field;
    if (!fieldName) {
      return;
    }

    this.sortedDirection = resolveSortDirection(
      fieldName,
      this.sortedBy,
      this.sortedDirection
    );
    this.sortedBy = fieldName;
    this.page = 1;
    this.applyCurrentSort();
  }

  handleSortKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    this.handleSort(event);
  }

  // ---- Column resizing ---------------------------------------------------

  /**
   * Seeds every column's width from what it currently measures, then tracks the
   * pointer.
   *
   * Seeding all of them matters: the table only honours widths under a fixed
   * layout, and switching to fixed with just one column sized would let the
   * browser re-solve all the others and make the whole table jump on the first
   * pixel of the drag. Measuring first means the switch is invisible and only
   * the dragged column moves.
   */
  handleResizeStart(event) {
    if (!this._enableColumnResize) {
      return;
    }

    // Keeps the header's own sort button and reorder drag out of it.
    event.preventDefault();
    event.stopPropagation();

    const fieldName = event.currentTarget.dataset.field;
    const headers = [
      ...this.template.querySelectorAll("thead th[data-field]")
    ];
    const widths = { ...this.columnWidths };
    for (const header of headers) {
      const field = header.dataset.field;
      if (field) {
        widths[field] = Math.round(header.getBoundingClientRect().width);
      }
    }

    this._resize = {
      fieldName,
      startX: event.clientX,
      startWidth: widths[fieldName] || 0
    };
    this.columnWidths = widths;

    // On window rather than the grip: the pointer routinely outruns a 4px
    // target, and pointer capture is not reliable across the synthetic shadow
    // Experience sites still render this component under.
    window.addEventListener("pointermove", this.handleResizeMove);
    window.addEventListener("pointerup", this.handleResizeEnd);
    window.addEventListener("pointercancel", this.handleResizeEnd);
  }

  /* Bound fields rather than methods so add/removeEventListener see the same
     reference and the listeners actually come off again. */
  handleResizeMove = (event) => {
    if (!this._resize) {
      return;
    }

    const delta = event.clientX - this._resize.startX;
    const width = Math.max(
      MIN_COLUMN_WIDTH,
      this._resize.startWidth + delta
    );

    this.columnWidths = {
      ...this.columnWidths,
      [this._resize.fieldName]: Math.round(width)
    };
  };

  handleResizeEnd = () => {
    this._resize = null;
    this.removeResizeListeners();
    // Written once the drag settles rather than on every move: the widths in
    // between are not ones the user chose.
    this.storeWidths(this.columnWidths);
  };

  removeResizeListeners() {
    window.removeEventListener("pointermove", this.handleResizeMove);
    window.removeEventListener("pointerup", this.handleResizeEnd);
    window.removeEventListener("pointercancel", this.handleResizeEnd);
  }

  /** Double-clicking the grip hands the column back to the content. */
  handleResizeReset(event) {
    event.preventDefault();
    event.stopPropagation();
    const fieldName = event.currentTarget.dataset.field;
    const widths = { ...this.columnWidths };
    delete widths[fieldName];
    this.columnWidths = widths;
    this.storeWidths(widths);
  }

  disconnectedCallback() {
    this.removeResizeListeners();
    this.detachActionMenuDismissal();
    if (this._handleWindowResize) {
      window.removeEventListener("resize", this._handleWindowResize);
    }
  }

  handleColumnDragStart(event) {
    if (!this._enableColumnReorder || this._resize) {
      // Pulling the resize grip keeps the pointer inside a draggable header, so
      // without this the reorder drag would fire on top of the resize.
      event.preventDefault();
      return;
    }

    const fieldName = event.currentTarget.dataset.field;
    const index = this._columns.findIndex((col) => col.fieldName === fieldName);
    // The first column is the record link (see primaryColumnIndex /
    // handleColumnDrop) — not draggable at all, rather than a drag that
    // silently goes nowhere.
    if (index === this.primaryColumnIndex) {
      event.preventDefault();
      return;
    }

    this._dragFieldName = fieldName;
    event.dataTransfer.effectAllowed = "move";
    // Firefox drops a drag that never had setData called on it.
    event.dataTransfer.setData("text/plain", this._dragFieldName || "");
  }

  // Firing on every dragged-over header would fire constantly; only
  // preventDefault (which is what tells the browser this drop target is
  // valid) while a reorder is actually in progress.
  handleColumnDragOver(event) {
    if (!this._enableColumnReorder || !this._dragFieldName) {
      return;
    }
    event.preventDefault();
  }

  handleColumnDrop(event) {
    if (!this._enableColumnReorder || !this._dragFieldName) {
      return;
    }
    event.preventDefault();

    const draggedField = this._dragFieldName;
    const targetField = event.currentTarget.dataset.field;
    this._dragFieldName = null;

    if (!targetField || targetField === draggedField) {
      return;
    }

    const ordered = [...this._columns];
    const fromIndex = ordered.findIndex(
      (col) => col.fieldName === draggedField
    );
    const toIndex = ordered.findIndex((col) => col.fieldName === targetField);

    if (fromIndex === -1 || toIndex === -1) {
      return;
    }

    // The first column doubles as the record link (see primaryColumnIndex) —
    // moving it out of, or another column into, that slot would silently
    // hand the link to whatever landed there instead.
    const primaryIndex = this.primaryColumnIndex;
    if (fromIndex === primaryIndex || toIndex === primaryIndex) {
      return;
    }

    const [moved] = ordered.splice(fromIndex, 1);
    ordered.splice(toIndex, 0, moved);

    this.dispatchEvent(
      new CustomEvent("columnreorder", {
        detail: { columns: ordered.map((col) => col.fieldName) },
        bubbles: true,
        composed: true
      })
    );
  }

  handleColumnDragEnd() {
    this._dragFieldName = null;
  }

  handlePageSizeChange(event) {
    const nextPageSize = Number(event.target.value);
    if (!nextPageSize || nextPageSize === this._pageSize) {
      return;
    }

    this._pageSize = nextPageSize;
    this.page = 1;
  }

  handlePrevious() {
    this.emitPageChange(this.clampedPage - 1);
  }

  handleNext() {
    this.emitPageChange(this.clampedPage + 1);
  }

  handlePageClick(event) {
    this.emitPageChange(Number(event.currentTarget.dataset.page));
  }

  emitPageChange(targetPage) {
    const page = Math.min(Math.max(1, targetPage), this.pageCount);
    if (page === this.clampedPage) {
      return;
    }

    this.page = page;
    // Set first so paginatedData already targets the right slice the
    // instant the caller's next batch lands -- no second click needed to
    // "arrive" on the page that triggered the fetch.
    if (page > this.localPageCount && this._hasMoreRows) {
      this.dispatchEvent(new CustomEvent("loadmore", { bubbles: true, composed: true }));
    }
  }

  findRow(rowId) {
    return this._sourceData.find(
      (record) => `${record[this.keyField]}` === `${rowId}`
    );
  }

  emitRowClick(row) {
    this.dispatchEvent(
      new CustomEvent("rowclick", {
        detail: { row },
        bubbles: true,
        composed: true
      })
    );
  }

  emitRowAction(detail) {
    this.dispatchEvent(
      new CustomEvent("rowaction", {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  handleExpandChevronClick(event) {
    event.stopPropagation();

    if (!this._enableRowClick) {
      return;
    }

    const row = this.findRow(event.currentTarget.dataset.id);
    if (!this.hasExpandableRowDetail(row)) {
      return;
    }

    this.emitRowClick(row);
  }

  handleRecordLinkClick(event) {
    event.stopPropagation();

    if (hasActiveTextSelection()) {
      // A drag-to-select-and-copy gesture over the link still fires this
      // click on mouseup -- block the anchor's own native navigation too,
      // not just the programmatic navigate below.
      event.preventDefault();
      return;
    }

    const recordId = event.currentTarget.dataset.recordId;
    const objectApiName = event.currentTarget.dataset.objectApiName;
    const openInNewContext = shouldAllowNativeRecordNavigation(event);

    if (openInNewContext) {
      return;
    }

    event.preventDefault();

    if (!recordId) {
      return;
    }

    if (this.dispatchRowNavigateEvent(recordId, objectApiName)) {
      return;
    }

    const linkPathOptions = this.buildLinkPathOptions(objectApiName);
    const pageReference = buildRecordNavigationReference(
      recordId,
      objectApiName,
      linkPathOptions
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  /**
   * Cancelable escape hatch for a caller that wants to do something other
   * than navigate on click -- Product Detail's Related Products table opens
   * a quick-view popup instead. Fires on both click paths (the isLink cell's
   * own anchor, and a whole-row click under enableRowNavigation) so a
   * listener only has to handle one event regardless of where the click
   * landed. Returns true if a listener called preventDefault(), meaning the
   * caller should skip its own default navigation.
   */
  dispatchRowNavigateEvent(recordId, objectApiName) {
    const navigateEvent = new CustomEvent("rownavigate", {
      cancelable: true,
      detail: { recordId, objectApiName }
    });
    this.dispatchEvent(navigateEvent);
    return navigateEvent.defaultPrevented;
  }

  handleActionCellClick(event) {
    event.stopPropagation();
  }

  handleRowNavigate(event) {
    if (!this._enableRowNavigation) {
      return;
    }

    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    if (hasActiveTextSelection()) {
      return;
    }

    const rowId = event.currentTarget.dataset.id;
    const row = this.rows.find(
      (candidate) => `${candidate.key}` === `${rowId}`
    );

    if (!row?.isNavigable) {
      return;
    }

    if (this.dispatchRowNavigateEvent(row.key, row.navigationObjectApiName)) {
      return;
    }

    const pageReference = buildRecordNavigationReference(
      row.key,
      row.navigationObjectApiName,
      this.buildLinkPathOptions(row.navigationObjectApiName)
    );

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  /* ---- Row-actions menu ---------------------------------------------------
     Our own menu rather than lightning-button-menu. That component lays its
     dropdown out inside the 28px trigger, which is itself inside the 36px pinned
     actions column, so the dropdown shrink-to-fit down to ~125px and truncated
     its longest label ("Open in new tab" -> "Open in new"). Nothing could be done
     about it from here: the base component renders under synthetic shadow, so
     ::part(dropdown) is inert despite the element advertising
     part="overlay dropdown", and menu-alignment="auto" does not portal it out of
     the cell either. Ours renders outside .div-table-scroll and is positioned
     fixed, so it escapes the scroller's clipping and sizes to its content. */

  /** { kind: 'row' | 'detail', id, actions, top, left, positioned } while open. */
  _actionMenu = null;
  _actionMenuTrigger = null;
  _actionMenuNeedsPosition = false;
  _actionMenuNeedsFocus = false;

  get isActionMenuOpen() {
    return !!this._actionMenu;
  }

  get actionMenuItems() {
    return this._actionMenu ? this._actionMenu.actions : [];
  }

  get actionMenuStyle() {
    if (!this._actionMenu) {
      return "";
    }
    // Hidden for the first render: the menu has to be in the DOM before it can be
    // measured, and an unpositioned one would flash in the viewport's top-left.
    const visibility = this._actionMenu.positioned ? "visible" : "hidden";
    return `top:${this._actionMenu.top}px;left:${this._actionMenu.left}px;visibility:${visibility};`;
  }

  handleRowMenuTrigger(event) {
    event.stopPropagation();
    this.toggleActionMenu(event.currentTarget, "row", this.rowActions);
  }

  handleDetailMenuTrigger(event) {
    event.stopPropagation();
    this.toggleActionMenu(event.currentTarget, "detail", this.detailRowActions);
  }

  toggleActionMenu(trigger, kind, actions) {
    const id = trigger.dataset.id;
    // Same kebab again closes it, matching how the old menu behaved.
    if (
      this._actionMenu &&
      this._actionMenu.kind === kind &&
      `${this._actionMenu.id}` === `${id}`
    ) {
      this.closeActionMenu(true);
      return;
    }

    this.closeActionMenu();
    this._actionMenuTrigger = trigger;
    trigger.setAttribute("aria-expanded", "true");
    this._actionMenu = {
      kind,
      id,
      actions: Array.isArray(actions) ? actions : [],
      top: 0,
      left: 0,
      positioned: false
    };
    this._actionMenuNeedsPosition = true;
    this.attachActionMenuDismissal();
  }

  closeActionMenu(restoreFocus = false) {
    if (!this._actionMenu) {
      return;
    }
    this._actionMenu = null;
    this._actionMenuNeedsPosition = false;
    this._actionMenuNeedsFocus = false;
    this.detachActionMenuDismissal();

    const trigger = this._actionMenuTrigger;
    this._actionMenuTrigger = null;
    if (trigger) {
      trigger.setAttribute("aria-expanded", "false");
      if (restoreFocus) {
        trigger.focus();
      }
    }
  }

  // Right-aligned under the kebab, flipped above it when the viewport bottom is
  // closer than the menu is tall, and clamped so it can never hang off an edge.
  positionActionMenu() {
    const menu = this.template.querySelector(".arc-data-table__menu");
    const trigger = this._actionMenuTrigger;
    if (!menu || !trigger || !this._actionMenu) {
      return;
    }

    const GAP = 4;
    const EDGE = 8;
    const anchor = trigger.getBoundingClientRect();
    const box = menu.getBoundingClientRect();

    let top = anchor.bottom + GAP;
    if (top + box.height > window.innerHeight - EDGE) {
      const above = anchor.top - GAP - box.height;
      top = above >= EDGE ? above : Math.max(EDGE, window.innerHeight - EDGE - box.height);
    }

    let left = anchor.right - box.width;
    left = Math.max(EDGE, Math.min(left, window.innerWidth - box.width - EDGE));

    this._actionMenu = {
      ...this._actionMenu,
      top: Math.round(top),
      left: Math.round(left),
      positioned: true
    };
  }

  attachActionMenuDismissal() {
    if (this._onActionMenuPointerDown) {
      return;
    }

    this._onActionMenuPointerDown = (event) => {
      const path = event.composedPath ? event.composedPath() : [];
      const menu = this.template.querySelector(".arc-data-table__menu");
      if (
        (this._actionMenuTrigger && path.includes(this._actionMenuTrigger)) ||
        (menu && path.includes(menu))
      ) {
        return;
      }
      this.closeActionMenu();
    };
    // The menu is positioned once, so any scroll would leave it stranded beside a
    // row that has moved. Capture, so the table's own scroller counts too.
    this._onActionMenuReflow = () => this.closeActionMenu();
    this._onActionMenuKeyDown = (event) => {
      if (event.key === "Escape") {
        this.closeActionMenu(true);
      }
    };

    document.addEventListener("pointerdown", this._onActionMenuPointerDown, true);
    document.addEventListener("keydown", this._onActionMenuKeyDown, true);
    window.addEventListener("scroll", this._onActionMenuReflow, true);
    window.addEventListener("resize", this._onActionMenuReflow);
  }

  detachActionMenuDismissal() {
    if (!this._onActionMenuPointerDown) {
      return;
    }
    document.removeEventListener("pointerdown", this._onActionMenuPointerDown, true);
    document.removeEventListener("keydown", this._onActionMenuKeyDown, true);
    window.removeEventListener("scroll", this._onActionMenuReflow, true);
    window.removeEventListener("resize", this._onActionMenuReflow);
    this._onActionMenuPointerDown = null;
    this._onActionMenuKeyDown = null;
    this._onActionMenuReflow = null;
  }

  handleActionMenuKeyDown(event) {
    const items = [
      ...this.template.querySelectorAll(".arc-data-table__menu-item")
    ];
    if (!items.length) {
      return;
    }

    const current = items.indexOf(this.template.activeElement);
    let next = null;

    if (event.key === "ArrowDown") {
      next = current < 0 ? 0 : (current + 1) % items.length;
    } else if (event.key === "ArrowUp") {
      next = current <= 0 ? items.length - 1 : current - 1;
    } else if (event.key === "Home") {
      next = 0;
    } else if (event.key === "End") {
      next = items.length - 1;
    } else if (event.key === "Tab") {
      // Nothing inside the menu is tabbable beyond the items, so a Tab means the
      // user is leaving; close rather than stranding an orphaned overlay.
      this.closeActionMenu();
      return;
    } else {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    items[next].focus();
  }

  handleActionMenuSelect(event) {
    event.stopPropagation();
    const name = event.currentTarget.dataset.value;
    const menu = this._actionMenu;
    this.closeActionMenu(true);
    if (!menu) {
      return;
    }

    if (menu.kind === "detail") {
      this.emitRowAction({
        action: { name },
        row: {
          id: menu.id,
          objectApiName: "Task"
        }
      });
      return;
    }

    this.emitRowAction({ action: { name }, row: this.findRow(menu.id) });
  }
}