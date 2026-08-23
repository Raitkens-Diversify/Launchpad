import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import communityBasePath from "@salesforce/community/basePath";
import fullSearch from "@salesforce/apex/ArcGlobalSearchController.fullSearch";
import { NAV_PATH_CHANGE_EVENT } from "c/arcNavTrailState";

const ALL_TAB_KEY = "all";
const FILTERS_ICON = "funnel-simple.svg";
const CARET_ICON = "caret-right.svg";
const ARROW_LEFT_ICON = "arrow-left.svg";
const EMPTY_SEARCH_ILLUSTRATION = "illustrations/empty-search.svg";
const ALL_TAB_PREVIEW_LIMIT = 5;

/**
 * Full global-search results page (per the Figma "Search results for
 * '<term>'" spec, node 699:51900): page title + total count, filter tabs
 * with per-category counts, and a category-grouped result list. Reads the
 * "term" query param and re-runs the search whenever the URL's term
 * changes (including SPA client-side transitions, via the same
 * NAV_PATH_CHANGE_EVENT the sidebar nav already patches history for).
 */
export default class ArcGlobalSearchResults extends NavigationMixin(
  LightningElement
) {
  term = "";
  activeTabKey = ALL_TAB_KEY;
  categories = [];
  totalCount = 0;
  isLoading = false;

  _lastQueriedTerm;

  get filtersIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${FILTERS_ICON}');`;
  }

  get caretIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_ICON}');`;
  }

  get arrowLeftIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${ARROW_LEFT_ICON}');`;
  }

  get emptySearchIllustrationUrl() {
    return `${NEXS_ICONS}/${EMPTY_SEARCH_ILLUSTRATION}`;
  }

  get showFiltersButton() {
    return this.activeTabKey !== ALL_TAB_KEY;
  }

  get headerRowClass() {
    return this.isAllTab
      ? "arc-search-results__header-row"
      : "arc-search-results__header-row arc-search-results__header-row--end";
  }

  get pageTitle() {
    return `Search results for '${this.term}'`;
  }

  get resultsTotalLabel() {
    return `${this.totalCount} result${this.totalCount === 1 ? "" : "s"} total`;
  }

  get tabs() {
    const tabs = [
      {
        key: ALL_TAB_KEY,
        label: "All",
        count: this.totalCount,
        className: this.tabClass(ALL_TAB_KEY)
      }
    ];
    this.categories.forEach((category) => {
      tabs.push({
        key: category.key,
        label: category.label,
        count: category.totalCount,
        className: this.tabClass(category.key)
      });
    });
    return tabs;
  }

  tabClass(key) {
    return key === this.activeTabKey
      ? "arc-search-results__tab arc-search-results__tab--active"
      : "arc-search-results__tab";
  }

  get isAllTab() {
    return this.activeTabKey === ALL_TAB_KEY;
  }

  get resultsHeaderLabel() {
    return "All Results";
  }

  get visibleGroups() {
    const isAllTab = this.activeTabKey === ALL_TAB_KEY;
    const groups = isAllTab
      ? this.categories
      : this.categories.filter(
          (category) => category.key === this.activeTabKey
        );
    return groups
      .filter((category) => category.items.length > 0)
      .map((category) => {
        const items = isAllTab
          ? category.items.slice(0, ALL_TAB_PREVIEW_LIMIT)
          : category.items;
        return {
          ...category,
          items,
          shownCount: items.length,
          showViewAll: isAllTab && category.totalCount > items.length,
          showCount: isAllTab
        };
      });
  }

  get hasResults() {
    return this.visibleGroups.length > 0;
  }

  get hasSearched() {
    return !this.isLoading && this.term.length > 0;
  }

  get showGlobalEmptyState() {
    return this.hasSearched && this.totalCount === 0;
  }

  get showCategoryEmptyState() {
    return (
      this.hasSearched &&
      !this.showGlobalEmptyState &&
      this.activeTabKey !== ALL_TAB_KEY &&
      this.visibleGroups.length === 0
    );
  }

  connectedCallback() {
    this._onNavChange = () => this.syncFromUrl();
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onNavChange);
    window.addEventListener("popstate", this._onNavChange);
    window.addEventListener("hashchange", this._onNavChange);
    this.syncFromUrl();
  }

  disconnectedCallback() {
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onNavChange);
    window.removeEventListener("popstate", this._onNavChange);
    window.removeEventListener("hashchange", this._onNavChange);
  }

  syncFromUrl() {
    const params = new URLSearchParams(window.location.search || "");
    const term = (params.get("term") || "").trim();
    if (term === this._lastQueriedTerm) {
      return;
    }
    this._lastQueriedTerm = term;
    this.term = term;
    this.activeTabKey = ALL_TAB_KEY;
    this.runSearch(term);
  }

  async runSearch(term) {
    if (!term) {
      this.categories = [];
      this.totalCount = 0;
      return;
    }

    this.isLoading = true;
    try {
      const result = await fullSearch({ term });
      if (term !== this._lastQueriedTerm) {
        return; // superseded by a newer search
      }
      this.categories = (result.categories || []).map((category) => ({
        ...category,
        items: (category.items || []).map((item) => ({
          ...item,
          key: item.id
        }))
      }));
      this.totalCount = result.totalCount || 0;
    } catch (error) {
      console.error("[arcGlobalSearchResults] fullSearch failed", error);
      this.categories = [];
      this.totalCount = 0;
    } finally {
      this.isLoading = false;
    }
  }

  handleTabClick(event) {
    this.activeTabKey = event.currentTarget.dataset.key;
  }

  handleViewAllClick(event) {
    this.activeTabKey = event.currentTarget.dataset.key;
  }

  handleBackToHome(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: `${communityBasePath}/`
      }
    });
  }

  handleResultClick(event) {
    event.preventDefault();
    const { id, objectApiName } = event.currentTarget.dataset;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName,
        actionName: "view"
      }
    });
  }
}