/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Reusable envelope list: loads wizard envelopes, filters client-side, and renders
 * c-styled-data-table with Experience Cloud link support. Action chrome (New Envelope,
 * row rename/delete) can be hidden for embedded Experience views.
 */
import { LightningElement, api, track } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import LightningToast from "lightning/toast";
import getEnvelopeListData from "@salesforce/apex/EnvelopeLandingApex.getEnvelopeListData";
import getAllFormSchemas from "@salesforce/apex/FieldDetailController.getAllFormSchemas";
import getRegistrationTypeAttributes from "@salesforce/apex/EnvelopeISAController.getRegistrationTypeAttributes";
import getUserPreferences from "@salesforce/apex/WizardEnvelopeStateService.getUserPreferences";
import getMyTeamIds from "@salesforce/apex/FinancialAdvisorTeamAccessController.getMyTeamIds";
import EMPTY_ENVELOPE from "@salesforce/resourceUrl/EmptyEnvelopeV2";
import envelopeWizardStyles from "@salesforce/resourceUrl/envelopeWizardStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import userId from "@salesforce/user/Id";
import {
  formatEnvelopeContentsLabel,
  missingInputsCountLabel,
  sumMissingInputs
} from "c/envelopeFormSchema";

const FILTER_ICON = "funnel-simple.svg";

const ENVELOPE_OBJECT_API_NAME = "Envelope__c";

const COLUMNS = [
  {
    label: "Envelope Name",
    fieldName: "name",
    type: "text",
    sortable: true,
    isLink: true,
    sortType: "text"
  },
  {
    label: "Household",
    fieldName: "household",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Financial Advisor Team",
    fieldName: "advisorTeam",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Created",
    fieldName: "created",
    type: "text",
    sortable: true,
    sortFieldName: "createdRaw",
    sortType: "date"
  },
  {
    label: "Created Date",
    fieldName: "createdDate",
    type: "text",
    sortable: true,
    sortFieldName: "createdRaw",
    sortType: "date"
  },
  {
    label: "Action Items",
    fieldName: "actionItems",
    type: "text",
    sortable: true,
    sortType: "text"
  },
  {
    label: "Missing Items",
    fieldName: "missingItems",
    type: "text",
    sortable: true,
    sortFieldName: "missingItemsCount",
    sortType: "number"
  },
  {
    label: "Last Activity",
    fieldName: "lastActivity",
    type: "text",
    sortable: true,
    sortFieldName: "lastActivityRaw",
    sortType: "date"
  }
];

const ROW_ACTIONS = [
  { label: "Rename", name: "rename", iconName: "utility:edit" },
  { label: "Delete", name: "delete", iconName: "utility:delete" }
];

/*
 * Row menus are off for now, in step with the other ARC tables (see
 * arcRecordListView and workTable): the three dots go away everywhere until
 * real quick actions exist. Flip this to true to bring Rename/Delete back; the
 * menu, its handler and the modals are all still here. The hideRowActions
 * Builder property keeps working on top of it for pages that want them off
 * for good. Done in code rather than in the home page's configuration because
 * a view change needs a site publish to reach users and code does not.
 */
const SHOW_ROW_ACTIONS = false;

/*
 * "My" is the envelopes the user created; "My Team" is the envelopes whose
 * household belongs to one of the user's financial advisor teams. The rows the
 * server hands over are already only the user's teams' envelopes plus their own,
 * so the old "My" (valued All, showing every row) narrowed nothing and the two
 * options looked the same -- the toggle appeared not to work.
 */
const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" }
];

const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50];

export default class EnvelopeTable extends LightningElement {
  @api title = "Envelopes";
  @api hideNewEnvelopeButton = false;
  @api hideRowActions = false;
  @api linkQueryParamObjectApiNames = ENVELOPE_OBJECT_API_NAME;

  // Dashboard-preview mode: hides the pager UI (still caps rows to
  // pageSize) and shows a "Showing X of Y" + "View All" footer instead,
  // matching the Home dashboard's Envelopes card (Figma node 760:126424).
  _showViewAllFooter = false;
  @api
  get showViewAllFooter() {
    return this._showViewAllFooter;
  }
  set showViewAllFooter(value) {
    this._showViewAllFooter = value !== false && value !== "false";
  }

  @api viewAllUrl = "";

  // Not wired to real filter criteria yet — Figma shows the button with no
  // filter panel spec; placeholder until there's a real filter UI to build.
  _showFilterButton = false;
  @api
  get showFilterButton() {
    return this._showFilterButton;
  }
  set showFilterButton(value) {
    this._showFilterButton = value !== false && value !== "false";
  }

  _enableSearch = true;
  @api
  get enableSearch() {
    return this._enableSearch;
  }
  set enableSearch(value) {
    this._enableSearch = value !== false && value !== "false";
  }

  @api searchPlaceholder = "Search envelopes...";

  _enableLastActivityFilter = true;
  @api
  get enableLastActivityFilter() {
    return this._enableLastActivityFilter;
  }
  set enableLastActivityFilter(value) {
    this._enableLastActivityFilter = value !== false && value !== "false";
    if (!this._enableLastActivityFilter) {
      this.dateFilter = "";
    }
  }

  @api lastActivityFilterPlaceholder = "Last Activity";

  _enablePagination = true;
  @api
  get enablePagination() {
    return this._enablePagination;
  }
  set enablePagination(value) {
    this._enablePagination = value !== false && value !== "false";
  }

  _pageSize = 10;
  @api
  get pageSize() {
    return this._pageSize;
  }
  set pageSize(value) {
    this._pageSize = Math.max(1, Number(value) || 10);
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

  emptyEnvelopeIllustration = EMPTY_ENVELOPE;

  // Always empty: the New Envelope dialog's household picker searches server-side
  // (see envelopeCreateModalV2) rather than choosing from a preloaded list.
  @track households = [];
  @track financialAdvisorTeams = [];
  @track envelopes = [];
  @track rows = [];
  @track isLoading = true;

  _schemaCache = {};
  _registrationAttributes = {};
  _userContext = {};
  _metricsById = {};

  @track columns = [...COLUMNS];

  /** Applies a header drag; see the matching handler in workTable. */
  handleColumnReorder(event) {
    const order = event.detail?.columns;
    if (!Array.isArray(order) || !order.length) {
      return;
    }
    const byName = new Map(this.columns.map((col) => [col.fieldName, col]));
    const next = order.map((name) => byName.get(name)).filter(Boolean);
    const missing = this.columns.filter((col) => !order.includes(col.fieldName));
    this.columns = [...next, ...missing];
  }
  defaultSortField = "lastActivity";
  defaultSortDirection = "desc";

  scopeFilter = SCOPE_MY;
  showFilterMenu = false;
  /** Column and contains-value behind the Filter popover. */
  filterField = "";
  filterValue = "";
  dateFilter = "";
  searchTerm = "";
  scopeOptions = SCOPE_OPTIONS;
  currentUserId = userId;
  _myTeamIds = new Set();

  get filterIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${FILTER_ICON}');`;
  }

  showCreateModal = false;
  showRenameModal = false;
  renameEnvelopeId = null;
  renameEnvelopeName = "";
  showDeleteModal = false;
  deleteEnvelopeId = null;
  deleteEnvelopeName = "";

  _stylesLoaded = false;

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, envelopeWizardStyles).catch((error) => {
        // eslint-disable-next-line no-console
        console.error(
          "[envelopeTable] Failed to load envelopeWizardStyles",
          error
        );
      });
    }

    this.loadData();
  }

  @api
  refresh() {
    return this.loadData();
  }

  get showToolbarActions() {
    return !this.hideNewEnvelopeButton;
  }

  get effectiveRowActions() {
    return this.hideRowActions || !SHOW_ROW_ACTIONS ? [] : ROW_ACTIONS;
  }

  get hasRowActions() {
    return !this.hideRowActions;
  }

  get tableRows() {
    return this.filteredRows.map((row) => ({
      ...row,
      objectApiName: ENVELOPE_OBJECT_API_NAME
    }));
  }

  loadData() {
    this.isLoading = true;

    return Promise.all([
      getEnvelopeListData(),
      this._loadFormContext(),
      getMyTeamIds().catch(() => [])
    ])
      .then(([result, , teamIds]) => {
        // getEnvelopeListData resolves household/team names server-side per row (via the
        // Envelope_Content__c junction), so there's no household list to join client-side
        // anymore -- households stays empty, and the New Envelope dialog's household picker
        // falls back to its own server-side search (same as it already does on envelopeListV2).
        this.households = [];
        this.financialAdvisorTeams = (result.advisorTeamOptions || []).map((option) => ({
          Id: option.value,
          Name: option.label
        }));
        this.envelopes = result.envelopes || [];
        this._myTeamIds = new Set(teamIds || []);
        this._metricsById = {};
        (result.envelopeMetrics || []).forEach((metric) => {
          this._metricsById[metric.envelopeId] = metric;
        });
        this.buildRows();
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[envelopeTable] Failed to load envelope data", error);
        this.showToast("Error", "Failed to load envelopes", "error");
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Each envelope arrives already resolved to its household name/id and advisor team
  // name/id (getEnvelopeListData joins them server-side through the Envelope_Content__c
  // junction), so there's no client-side household/team join to build here anymore.
  buildRows() {
    const hasSchema = Object.keys(this._schemaCache || {}).length > 0;
    const context = {
      schemaCache: this._schemaCache,
      registrationAttributes: this._registrationAttributes,
      userContext: this._userContext
    };

    this.rows = (this.envelopes || []).map((envelope) => {
      const metrics = this._metricsById[envelope.id];
      const hasState = Boolean(metrics?.hasState);
      const hasCounts = Boolean(metrics?.hasCounts);
      const missing =
        hasState && hasSchema
          ? sumMissingInputs(
              this._missingInputItems(metrics.actionSources),
              context
            )
          : null;

      return {
        id: envelope.id,
        name: envelope.name || "",
        household: envelope.householdName || "",
        householdId: envelope.householdId || null,
        teamId: envelope.advisorTeamId || null,
        advisorTeam: envelope.advisorTeamName || "",
        createdById: envelope.createdById || null,
        ownerId: envelope.ownerId || null,
        created: envelope.createdDate
          ? `${this.formatDateTime(envelope.createdDate)} - ${
              envelope.createdByName || ""
            }`
          : "",
        createdDate: envelope.createdDate
          ? this.formatDateOnly(envelope.createdDate)
          : "",
        createdRaw: envelope.createdDate || null,
        actionItems: hasCounts
          ? formatEnvelopeContentsLabel({
              members: metrics.members,
              isas: metrics.isas
            })
          : "",
        missingItems: missing
          ? missingInputsCountLabel(missing.count, missing.hasPlus)
          : null,
        missingItemsCount: missing ? missing.count : null,
        lastActivity: envelope.lastModifiedDate
          ? `${this.formatDateTime(envelope.lastModifiedDate)} - ${
              envelope.lastModifiedByName || ""
            }`
          : "",
        lastActivityRaw: envelope.lastModifiedDate || null
      };
    });
  }

  formatDateTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }

    const datePart = date.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric"
    });
    const timePart = date.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    });

    return `${datePart} ${timePart}`;
  }

  formatDateOnly(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }

    return date.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric"
    });
  }

  toLocalDateKey(value) {
    if (!value) {
      return "";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }

    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  get filteredRows() {
    const term = this.searchTerm.trim().toLowerCase();

    return this.rows.filter((row) => {
      const matchesSearch =
        !term ||
        row.name.toLowerCase().includes(term) ||
        row.household.toLowerCase().includes(term);
      const matchesScope =
        this.scopeFilter === SCOPE_MY
          ? row.createdById === this.currentUserId
          : Boolean(row.teamId && this._myTeamIds.has(row.teamId));
      const matchesDate =
        !this.enableLastActivityFilter ||
        !this.dateFilter ||
        this.toLocalDateKey(row.lastActivityRaw) === this.dateFilter;
      // Contains, case-insensitive — the same test the list views' chips use.
      // A date-type field (Created Date, Created, Last Activity) compares
      // whole calendar days against its raw value instead.
      const dateRawField = this.filterFieldDateRawField;
      const filterTerm = this.filterValue.trim().toLowerCase();
      const matchesFilter = !this.filterField
        ? true
        : dateRawField
        ? !this.filterValue ||
          this.toLocalDateKey(row[dateRawField]) === this.filterValue
        : !filterTerm ||
          String(row[this.filterField] ?? "")
            .toLowerCase()
            .includes(filterTerm);

      return matchesSearch && matchesScope && matchesDate && matchesFilter;
    });
  }

  get hasEnvelopes() {
    return this.rows.length > 0;
  }

  get hasFilteredRows() {
    return this.filteredRows.length > 0;
  }

  get hasActiveFilters() {
    return (
      Boolean(this.searchTerm.trim()) ||
      this.scopeFilter === SCOPE_TEAM ||
      (this.enableLastActivityFilter && Boolean(this.dateFilter))
    );
  }

  get showResetFilters() {
    return this.hasActiveFilters && !this.hasFilteredRows;
  }

  get tableEmptyMessage() {
    if (this.hasActiveFilters) {
      return "We can't find any item matching your search or filters.";
    }

    return "No results found";
  }

  get householdOptions() {
    return (this.households || []).map((household) => ({
      label: household.Name,
      value: household.Id
    }));
  }

  get advisorTeamOptions() {
    return (this.financialAdvisorTeams || []).map((team) => ({
      label: team.Name,
      value: team.Id
    }));
  }

  handleScopeChange(event) {
    this.scopeFilter = event.detail?.value ?? SCOPE_MY;
  }

  handleSearchChange(event) {
    this.searchTerm = event.detail.value || "";
  }

  handleResetFilters() {
    this.searchTerm = "";
    this.scopeFilter = SCOPE_MY;
    this.dateFilter = "";
  }

  handleDateChange(event) {
    this.dateFilter = event.target.value || "";
  }

  handleRowAction(event) {
    const { action, row } = event.detail;

    if (action.name === "rename") {
      this.renameEnvelopeId = row.id;
      this.renameEnvelopeName = row.name;
      this.showRenameModal = true;
      return;
    }

    if (action.name === "delete") {
      this.deleteEnvelopeId = row.id;
      this.deleteEnvelopeName = row.name;
      this.showDeleteModal = true;
    }
  }

  handleRowClick(event) {
    const { row } = event.detail;
    this.dispatchOpenCreated({
      envelopeId: row.id || null,
      title: row.name || "",
      householdName: row.household || "",
      householdId: row.householdId || null
    });
  }

  handleNewEnvelope() {
    this.showCreateModal = true;
  }

  /**
   * Opens the filter popover. This was a no-op placeholder, so the button did
   * nothing at all. It now matches the list views: pick a column, type a value,
   * apply — filtering the rows already on screen, alongside search and scope.
   */
  handleFilterClick() {
    this.showFilterMenu = !this.showFilterMenu;
  }

  get filterFieldOptions() {
    return COLUMNS.filter((col) => col.fieldName).map((col) => ({
      label: col.label,
      value: col.fieldName,
      selected: col.fieldName === this.filterField
    }));
  }

  get filterFieldLabel() {
    return (
      COLUMNS.find((col) => col.fieldName === this.filterField)?.label || ""
    );
  }

  get hasFilterChip() {
    return Boolean(this.filterField && this.filterValue.trim());
  }

  get filterChipLabel() {
    return `${this.filterFieldLabel}: ${this.filterValue.trim()}`;
  }

  /** The raw date field backing the selected filter field, when it's date-typed. */
  get filterFieldDateRawField() {
    const col = COLUMNS.find((c) => c.fieldName === this.filterField);
    return col?.sortType === "date" ? col.sortFieldName : "";
  }

  get isDateFilterField() {
    return Boolean(this.filterFieldDateRawField);
  }

  handleFilterFieldChange(event) {
    const fieldName = event.target.value;
    // Value from a text box and a date-picker aren't interchangeable, so
    // switching field types clears whatever was already typed/picked.
    if (fieldName !== this.filterField) {
      this.filterValue = "";
    }
    this.filterField = fieldName;
  }

  handleFilterValueChange(event) {
    this.filterValue = event.target.value;
  }

  handleFilterApply() {
    this.showFilterMenu = false;
  }

  handleFilterClear() {
    this.filterField = "";
    this.filterValue = "";
    this.showFilterMenu = false;
  }

  handleCloseCreateModal() {
    this.showCreateModal = false;
  }

  handleCreateEnvelope(event) {
    this.showCreateModal = false;
    this.dispatchOpenCreated({ ...(event.detail || {}) });
  }

  handleCloseRenameModal() {
    this.showRenameModal = false;
  }

  handleRenameEnvelope() {
    this.showRenameModal = false;
    this.loadData();
  }

  handleCloseDeleteModal() {
    this.showDeleteModal = false;
  }

  handleDeleteEnvelope() {
    this.showDeleteModal = false;
    this.loadData();
  }

  dispatchOpenCreated(detail) {
    this.dispatchEvent(
      new CustomEvent("opencreated", {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }

  showToast(title, message, variant) {
    LightningToast.show({ label: title, message, variant }, this);
  }

  _loadFormContext() {
    return Promise.all([
      getAllFormSchemas().catch(() => ({})),
      getRegistrationTypeAttributes().catch(() => ({})),
      getUserPreferences().catch(() => null)
    ]).then(([schemas, registrationAttributes, prefs]) => {
      this._schemaCache = schemas || {};
      this._registrationAttributes = registrationAttributes || {};
      this._userContext = {
        Relationship_to_Firm__c: prefs?.relationshipToFirm ?? null
      };
    });
  }

  _missingInputItems(actionSources) {
    return (actionSources || []).map((source) => ({
      entity: { groupId: source.groupId, type: source.entityType },
      formData: source.formData
    }));
  }
}