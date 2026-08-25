/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import USER_ID from "@salesforce/user/Id";
import getBookOfBusinessData from "@salesforce/apex/BookOfBusinessController.getBookOfBusinessData";
import getSavedViews from "@salesforce/apex/UserPreferenceController.getSavedViews";
import saveSavedViews from "@salesforce/apex/UserPreferenceController.saveSavedViews";
import {
  APPLICATION_NAME,
  VIEW_MODE_CHART,
  VIEW_MODE_TABLE,
  applySavedViewState,
  cloneColumns,
  compactSavedViewsForStorage,
  createDefaultViewState,
  createEmptyFilters,
  createSavedView,
  DEFAULT_COLUMNS,
  deriveProcessedRows,
  FILTER_FIELDS,
  hasSavedViewStateChanged,
  loadSavedViewsPreference,
  MOCK_BOOK_OF_BUSINESS_PAYLOAD,
  normalizeAccountRows,
  parseSavedViewsResponse,
  persistSavedViews,
  resolveSavedViewById,
  resolveSelectedChartSegment,
  resolveSortDirection,
  updateSavedViewFromState
} from "c/bookOfBusinessUtils";

export default class BookOfBusinessTab extends LightningElement {
  @api recordId;

  title = "";
  subtitle = "";
  summary = {};
  kpis = [];
  sourceRows = [];
  viewState = createDefaultViewState();
  savedViews = [];
  savedViewName = "";
  activeViewId = "";
  isConfigureOpen = false;
  draftColumns = cloneColumns(DEFAULT_COLUMNS);
  draftFilters = createEmptyFilters();
  configureDrawerKey = 0;
  isChartExpanded = false;
  isLoading = true;
  errorMessage = "";
  selectedChartSegment = null;
  preferenceErrorMessage = "";
  _hasRestoredLastSelectedView = false;

  connectedCallback() {
    this.loadBookOfBusinessData();
  }

  async loadBookOfBusinessData() {
    this.isLoading = true;
    this.errorMessage = "";

    try {
      const additionalFieldApis = this.getAdditionalFieldApis();
      const data = await getBookOfBusinessData({
        recordId: this.recordId,
        additionalFieldApis
      });
      await this.applyBookOfBusinessPayload(data);
    } catch (error) {
      console.warn("[bookOfBusinessTab] Using mock payload after Apex failure", error);
      await this.applyBookOfBusinessPayload(MOCK_BOOK_OF_BUSINESS_PAYLOAD);
    } finally {
      this.isLoading = false;
    }
  }

  async applyBookOfBusinessPayload(data) {
    const payload = data || MOCK_BOOK_OF_BUSINESS_PAYLOAD;

    this.title = payload.title;
    this.subtitle = payload.subtitle;
    this.summary = payload.summary || {};
    this.kpis = payload.kpis || [];
    this.sourceRows = normalizeAccountRows(payload.accounts || []);
    await this.loadSavedViewsFromServer();
  }

  getAdditionalFieldApis() {
    const defaultKeys = new Set(
      DEFAULT_COLUMNS.map((column) => column.fieldName || column.key)
    );

    return (this.viewState.columns || [])
      .map((column) => column.fieldName || column.key)
      .filter((fieldName) => fieldName && !defaultKeys.has(fieldName));
  }

  async loadSavedViewsFromServer() {
    try {
      const result = await getSavedViews({
        applicationName: APPLICATION_NAME,
        recordId: this.recordId
      });
      let views = parseSavedViewsResponse(result?.viewsJson);
      let lastSelectedViewId = result?.lastSelectedViewId || "";

      if (views.length === 0) {
        const localPreference = loadSavedViewsPreference(this.recordId, USER_ID);

        if (localPreference.views.length > 0) {
          views = localPreference.views;
          lastSelectedViewId = localPreference.lastSelectedViewId || "";
          await this.persistSavedViewsToServer(views, lastSelectedViewId);
          persistSavedViews(this.recordId, USER_ID, [], "");
        }
      }

      this.savedViews = views;

      if (!this._hasRestoredLastSelectedView) {
        this.applyLastSelectedView(lastSelectedViewId);
        this._hasRestoredLastSelectedView = true;
      }

      this.preferenceErrorMessage = "";
    } catch (error) {
      console.warn("[bookOfBusinessTab] Falling back to local saved views", error);
      const localPreference = loadSavedViewsPreference(this.recordId, USER_ID);
      this.savedViews = localPreference.views;

      if (!this._hasRestoredLastSelectedView) {
        this.applyLastSelectedView(localPreference.lastSelectedViewId);
        this._hasRestoredLastSelectedView = true;
      }

      this.preferenceErrorMessage = "";
    }
  }

  async refreshAccountData() {
    try {
      const additionalFieldApis = this.getAdditionalFieldApis();
      const data = await getBookOfBusinessData({
        recordId: this.recordId,
        additionalFieldApis
      });
      const payload = data || MOCK_BOOK_OF_BUSINESS_PAYLOAD;

      this.title = payload.title;
      this.subtitle = payload.subtitle;
      this.summary = payload.summary || {};
      this.kpis = payload.kpis || [];
      this.sourceRows = normalizeAccountRows(payload.accounts || []);
    } catch (error) {
      console.warn("[bookOfBusinessTab] Account refresh failed after configure apply", error);
      const payload = MOCK_BOOK_OF_BUSINESS_PAYLOAD;

      this.title = payload.title;
      this.subtitle = payload.subtitle;
      this.summary = payload.summary || {};
      this.kpis = payload.kpis || [];
      this.sourceRows = normalizeAccountRows(payload.accounts || []);
    }
  }

  applyLastSelectedView(lastSelectedViewId) {
    const selectedView = resolveSavedViewById(this.savedViews, lastSelectedViewId);

    if (!selectedView) {
      return;
    }

    this.viewState = applySavedViewState(selectedView);
    this.activeViewId = lastSelectedViewId;
    this.selectedChartSegment = null;
    this.isChartExpanded = false;
  }

  async persistSavedViewsToServer(views, lastSelectedViewId = this.activeViewId) {
    const selectedViewId = lastSelectedViewId || "";

    try {
      await saveSavedViews({
        applicationName: APPLICATION_NAME,
        recordId: this.recordId,
        viewsJson: JSON.stringify(compactSavedViewsForStorage(views || [])),
        lastSelectedViewId: selectedViewId
      });
      this.preferenceErrorMessage = "";
      persistSavedViews(this.recordId, USER_ID, views, selectedViewId);
    } catch (error) {
      console.warn("[bookOfBusinessTab] Server save failed; using local fallback", error);
      persistSavedViews(this.recordId, USER_ID, views, selectedViewId);
      this.preferenceErrorMessage =
        "Saved views stored locally because server persistence is unavailable.";
    }
  }

  get accountCount() {
    return this.summary?.accountCount || 0;
  }

  get totalAumLabel() {
    return this.summary?.totalAumLabel || "$0";
  }

  get isTableView() {
    return this.viewState.viewMode === VIEW_MODE_TABLE;
  }

  get isChartView() {
    return this.viewState.viewMode === VIEW_MODE_CHART;
  }

  get processedView() {
    return deriveProcessedRows({
      sourceRows: this.sourceRows,
      filters: this.viewState.filters,
      sortField: this.viewState.sortField,
      sortDirection: this.viewState.sortDirection,
      columns: this.viewState.columns,
      groupBy: this.viewState.groupBy
    });
  }

  get filteredRows() {
    return this.processedView.filteredRows;
  }

  get tableRows() {
    return this.processedView.tableRows;
  }

  get chartRows() {
    return this.processedView.chartRows;
  }

  get chartData() {
    return this.processedView.chartData;
  }

  get defaultColumns() {
    return DEFAULT_COLUMNS;
  }

  get filterFields() {
    return FILTER_FIELDS;
  }

  get decoratedFilterFields() {
    return FILTER_FIELDS.map((field) => ({
      key: `${field.key}-${this.configureDrawerKey}`,
      fieldKey: field.key,
      label: field.label,
      options: this.getFilterOptionsForField(field.fieldName).map((value) => ({
        label: value,
        value
      })),
      values: [...(this.draftFilters?.[field.key] || [])]
    }));
  }

  getFilterOptionsForField(fieldName) {
    const values = new Set();

    (this.sourceRows || []).forEach((row) => {
      const value = row[fieldName];
      if (value !== null && value !== undefined && value !== "") {
        values.add(String(value));
      }
    });

    return [...values].sort((first, second) =>
      first.localeCompare(second, undefined, { sensitivity: "base" })
    );
  }

  cloneDraftFilters(filters = {}) {
    return FILTER_FIELDS.reduce((accumulator, field) => {
      accumulator[field.key] = [...(filters?.[field.key] || [])];
      return accumulator;
    }, {});
  }

  get resolvedChartSegment() {
    return resolveSelectedChartSegment(
      this.chartData,
      this.selectedChartSegment,
      this.viewState.filters
    );
  }

  get activeViewLabel() {
    if (!this.activeViewId) {
      return "";
    }

    const activeView = this.savedViews.find((view) => view.id === this.activeViewId);
    return activeView?.name || "";
  }

  get hasActiveViewLabel() {
    return Boolean(this.activeViewLabel);
  }

  get hasUnsavedViewChanges() {
    if (!this.activeViewId) {
      return false;
    }

    const activeView = this.savedViews.find((view) => view.id === this.activeViewId);
    return hasSavedViewStateChanged(activeView, this.viewState);
  }

  handleGroupByChange(event) {
    this.viewState = {
      ...this.viewState,
      groupBy: event.detail.groupBy
    };
  }

  handleConfigureOpen() {
    this.draftColumns = cloneColumns(this.viewState.columns);
    this.draftFilters = this.cloneDraftFilters(this.viewState.filters);
    this.configureDrawerKey += 1;
    this.isConfigureOpen = true;
  }

  handleConfigureClose() {
    this.isConfigureOpen = false;
  }

  async handleConfigureApply() {
    const columnManager = this.template.querySelector("c-ds-column-manager");
    const nextColumns = columnManager
      ? columnManager.getDraftColumns()
      : this.draftColumns;

    this.viewState = {
      ...this.viewState,
      columns: cloneColumns(nextColumns),
      filters: this.cloneDraftFilters(this.draftFilters)
    };
    this.isConfigureOpen = false;
    this.selectedChartSegment = null;
    await this.refreshAccountData();
  }

  handleConfigureReset() {
    this.draftColumns = cloneColumns(DEFAULT_COLUMNS);
    this.draftFilters = createEmptyFilters();
    this.configureDrawerKey += 1;
  }

  handleDraftColumnsChange(event) {
    this.draftColumns = cloneColumns(event.detail.columns);
  }

  handleDraftFilterChange(event) {
    const fieldKey = event.currentTarget.dataset.fieldKey;
    const { value } = event.detail;

    if (!fieldKey) {
      return;
    }

    this.draftFilters = {
      ...this.draftFilters,
      [fieldKey]: [...(value || [])]
    };
  }

  handleSegmentSelect(event) {
    this.selectedChartSegment = event.detail.segmentKey;
  }

  handleChartExpandChange(event) {
    this.isChartExpanded = event.detail.expanded;
  }

  handleChartTypeChange(event) {
    this.viewState = {
      ...this.viewState,
      chartType: event.detail.chartType
    };
  }

  async handleViewModeChange(event) {
    const nextViewMode = event.detail.viewMode;

    if (
      nextViewMode !== this.viewState.viewMode &&
      this.hasUnsavedViewChanges
    ) {
      const nextModeLabel = nextViewMode === VIEW_MODE_CHART ? "Chart" : "Table";
      const confirmed = await LightningConfirm.open({
        label: "Unsaved changes",
        message: `You have unsaved changes to "${this.activeViewLabel}". Switch to ${nextModeLabel} without saving?`,
        theme: "warning",
        variant: "header"
      });

      if (!confirmed) {
        return;
      }
    }

    if (nextViewMode !== VIEW_MODE_TABLE) {
      this.isConfigureOpen = false;
      this.isChartExpanded = false;
    }

    this.viewState = {
      ...this.viewState,
      viewMode: nextViewMode
    };
  }

  handleSortChange(event) {
    const fieldName = event.detail.fieldName;
    this.viewState = {
      ...this.viewState,
      sortField: fieldName,
      sortDirection: resolveSortDirection(
        fieldName,
        this.viewState.sortField,
        this.viewState.sortDirection
      )
    };
  }

  async handleRenameView(event) {
    const trimmedName = (event.detail?.name || "").trim();
    const viewId = event.detail?.viewId || this.activeViewId;

    if (!trimmedName || !viewId) {
      return;
    }

    const viewIndex = this.savedViews.findIndex((view) => view.id === viewId);

    if (viewIndex < 0) {
      return;
    }

    const isDuplicateName = this.savedViews.some(
      (view) =>
        view.id !== viewId &&
        (view.name || "").trim().toLowerCase() === trimmedName.toLowerCase()
    );

    if (isDuplicateName) {
      return;
    }

    const nextViews = [...this.savedViews];
    nextViews[viewIndex] = {
      ...nextViews[viewIndex],
      name: trimmedName
    };
    this.savedViews = nextViews;
    await this.persistSavedViewsToServer(nextViews, this.activeViewId);
  }

  async handleUpdateView() {
    if (!this.activeViewId) {
      return;
    }

    const viewIndex = this.savedViews.findIndex((view) => view.id === this.activeViewId);

    if (viewIndex < 0) {
      return;
    }

    const nextViews = [...this.savedViews];
    nextViews[viewIndex] = updateSavedViewFromState(nextViews[viewIndex], this.viewState);
    this.savedViews = nextViews;
    await this.persistSavedViewsToServer(nextViews, this.activeViewId);
  }

  async handleSaveView(event) {
    const trimmedName = (event.detail?.name || "").trim();

    if (!trimmedName) {
      return;
    }

    const isDuplicateName = this.savedViews.some(
      (view) => (view.name || "").trim().toLowerCase() === trimmedName.toLowerCase()
    );

    if (isDuplicateName) {
      return;
    }

    const newView = createSavedView(trimmedName, this.viewState);
    const nextViews = [...this.savedViews, newView];

    this.savedViews = nextViews;
    this.activeViewId = newView.id;
    await this.persistSavedViewsToServer(nextViews, newView.id);
    this.savedViewName = "";
  }

  async handleApplyView(event) {
    const viewId = event.detail.viewId;
    const selectedView = this.savedViews.find((view) => view.id === viewId);

    if (!selectedView) {
      return;
    }

    this.viewState = applySavedViewState(selectedView);
    this.activeViewId = viewId;
    this.selectedChartSegment = null;
    this.isChartExpanded = false;
    await this.persistSavedViewsToServer(this.savedViews, viewId);
  }

  async handleDeleteView(event) {
    const viewId = event.detail.viewId;
    const nextViews = this.savedViews.filter((view) => view.id !== viewId);
    this.savedViews = nextViews;

    if (this.activeViewId === viewId) {
      this.activeViewId = "";
    }

    await this.persistSavedViewsToServer(nextViews, this.activeViewId);
  }
}