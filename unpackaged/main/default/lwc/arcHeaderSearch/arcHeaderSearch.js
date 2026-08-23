import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import communityBasePath from "@salesforce/community/basePath";
import typeahead from "@salesforce/apex/ArcGlobalSearchController.typeahead";

const SEARCH_ICON = "magnifying-glass.svg";
const CLEAR_ICON = "x.svg";
const DEBOUNCE_MS = 300;
const MIN_TERM_LENGTH = 2;
const ALL_TAB_KEY = "all";

/** Split text into [{text, isMatch}] segments around the first case-insensitive hit of term. */
function highlightParts(text, term) {
  if (!text) {
    return [{ text: "", isMatch: false, key: "0" }];
  }
  if (!term) {
    return [{ text, isMatch: false, key: "0" }];
  }

  const lowerText = text.toLowerCase();
  const lowerTerm = term.toLowerCase();
  const index = lowerText.indexOf(lowerTerm);
  if (index === -1) {
    return [{ text, isMatch: false, key: "0" }];
  }

  const parts = [];
  if (index > 0) {
    parts.push({ text: text.slice(0, index), isMatch: false, key: "pre" });
  }
  parts.push({
    text: text.slice(index, index + term.length),
    isMatch: true,
    key: "match"
  });
  const rest = text.slice(index + term.length);
  if (rest) {
    parts.push({ text: rest, isMatch: false, key: "post" });
  }
  return parts;
}

const ROW_CLASS = "arc-search-autosuggest__row";
const ROW_CLASS_HIGHLIGHTED = `${ROW_CLASS} arc-search-autosuggest__row--highlighted`;
const SEARCH_FOR_ROW_CLASS = `${ROW_CLASS} arc-search-autosuggest__row--search-for`;
const SEARCH_FOR_ROW_CLASS_HIGHLIGHTED = `${SEARCH_FOR_ROW_CLASS} arc-search-autosuggest__row--highlighted`;

/**
 * Global header search box: left magnifying-glass icon, "Search…"
 * placeholder, live-typeahead Autosuggest dropdown (per the Figma "Search"
 * node), and Enter still submits to the site's standard global search
 * results page via NavigationMixin.
 */
export default class ArcHeaderSearch extends NavigationMixin(LightningElement) {
  term = "";
  isOpen = false;
  isExpanded = false;
  isLoading = false;
  activeTabKey = ALL_TAB_KEY;
  categories = [];
  totalCount = 0;
  normalizedTerm = "";
  highlightedIndex = -1;

  _debounceId;
  _requestToken = 0;
  _lastSubmittedTerm;

  get iconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${SEARCH_ICON}');`;
  }

  get clearIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CLEAR_ICON}');`;
  }

  get showClearButton() {
    return this.term.length > 0;
  }

  /** Suggestions being open is itself a reason to stay expanded — a stray
   * focus blip that flips isExpanded false shouldn't shrink the box out
   * from under an open dropdown. Only shrinks once the dropdown is
   * genuinely closed (or there's text staying in an otherwise-collapsed box). */
  get isVisuallyExpanded() {
    return this.isExpanded || this.isOpen;
  }

  get boxClass() {
    return this.isVisuallyExpanded
      ? "arc-header-search__box arc-header-search__box--expanded"
      : "arc-header-search__box";
  }

  get dropdownClass() {
    return this.isVisuallyExpanded
      ? "arc-search-autosuggest arc-search-autosuggest--expanded"
      : "arc-search-autosuggest";
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
      ? "arc-search-autosuggest__tab arc-search-autosuggest__tab--active"
      : "arc-search-autosuggest__tab";
  }

  get visibleGroups() {
    const groups =
      this.activeTabKey === ALL_TAB_KEY
        ? this.categories
        : this.categories.filter(
            (category) => category.key === this.activeTabKey
          );
    return groups.filter((category) => category.items.length > 0);
  }

  /** visibleGroups' items annotated with a flat index (search-for row counts
   * as index 0 when shown) so keyboard up/down and the highlight class stay
   * in sync with click/Enter activation. */
  get renderGroups() {
    let index = this.showSearchForRow ? 1 : 0;
    return this.visibleGroups.map((category) => ({
      ...category,
      items: category.items.map((item) => {
        const flatIndex = index;
        index += 1;
        return {
          ...item,
          flatIndex,
          rowClass:
            flatIndex === this.highlightedIndex
              ? ROW_CLASS_HIGHLIGHTED
              : ROW_CLASS
        };
      })
    }));
  }

  get hasResults() {
    return this.visibleGroups.length > 0;
  }

  get shownCount() {
    return this.visibleGroups.reduce(
      (sum, category) => sum + category.items.length,
      0
    );
  }

  get visibleTotalCount() {
    if (this.activeTabKey === ALL_TAB_KEY) {
      return this.totalCount;
    }
    const active = this.categories.find(
      (category) => category.key === this.activeTabKey
    );
    return active ? active.totalCount : 0;
  }

  get resultsSummary() {
    return `Showing ${this.shownCount} out of ${this.visibleTotalCount} results`;
  }

  get showSearchForRow() {
    return this.normalizedTerm.length >= MIN_TERM_LENGTH;
  }

  get searchForRowClass() {
    return this.showSearchForRow && this.highlightedIndex === 0
      ? SEARCH_FOR_ROW_CLASS_HIGHLIGHTED
      : SEARCH_FOR_ROW_CLASS;
  }

  get flatItemCount() {
    return (this.showSearchForRow ? 1 : 0) + this.shownCount;
  }

  get hasSearched() {
    return !this.isLoading && this.term.trim().length >= MIN_TERM_LENGTH;
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

  handleFocus() {
    this.isExpanded = true;
    if (this.term.trim().length >= MIN_TERM_LENGTH) {
      this.isOpen = true;
    }
  }

  handleInput(event) {
    this.term = event.target.value || "";
    window.clearTimeout(this._debounceId);
    this.highlightedIndex = -1;

    const term = this.term.trim();
    if (term.length < MIN_TERM_LENGTH) {
      this.isOpen = false;
      this.categories = [];
      this.totalCount = 0;
      this.normalizedTerm = "";
      return;
    }

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._debounceId = window.setTimeout(() => {
      this.runSearch(term);
    }, DEBOUNCE_MS);
  }

  async runSearch(term) {
    const requestToken = ++this._requestToken;
    this.isLoading = true;
    this.isOpen = true;

    try {
      const result = await typeahead({ term });
      if (requestToken !== this._requestToken) {
        return; // a newer keystroke superseded this request
      }
      this.normalizedTerm = result.normalizedTerm || "";
      this.categories = (result.categories || []).map((category) => ({
        ...category,
        items: (category.items || []).map((item) => ({
          ...item,
          key: item.id,
          titleParts: highlightParts(item.title, this.normalizedTerm)
        }))
      }));
      this.totalCount = result.totalCount || 0;
      this.activeTabKey = ALL_TAB_KEY;
      this.highlightedIndex = -1;
    } catch (error) {
      console.error("[arcHeaderSearch] typeahead failed", error);
      this.categories = [];
      this.totalCount = 0;
    } finally {
      if (requestToken === this._requestToken) {
        this.isLoading = false;
      }
    }
  }

  handleTabClick(event) {
    this.activeTabKey = event.currentTarget.dataset.key;
    this.highlightedIndex = -1;
  }

  handleResultClick(event) {
    event.preventDefault();
    const { id, objectApiName } = event.currentTarget.dataset;
    this.navigateToRecord(id, objectApiName);
  }

  handleSearchForClick(event) {
    event.preventDefault();
    this.submitSearch();
  }

  /**
   * Delegated on the component root (not just the <input>) so Escape/Enter/
   * arrows work no matter which inner control currently has focus — a tab
   * button or a result link, not only the search box itself.
   */
  handleKeyDown(event) {
    if (event.key === "Escape") {
      event.stopPropagation();
      this.closeDropdown();
      this.isExpanded = false;
      // Closing state alone isn't enough — if the input (or a row) still
      // has real focus, :focus-within keeps the blue ring lit AND typing
      // again won't re-expand the box (a "focus" event only fires when
      // focus newly arrives, not while it's already there). Blurring
      // resets both, so a fresh click/focus is what re-expands it.
      if (
        event.target &&
        typeof event.target.blur === "function" &&
        this.template.contains(event.target)
      ) {
        event.target.blur();
      }
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      this.moveHighlight(1);
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      this.moveHighlight(-1);
      return;
    }

    if (event.key !== "Enter") {
      return;
    }

    // If a specific row/link already has real DOM focus (clicked, or
    // Tabbed to), activate THAT one directly — it may not match
    // highlightedIndex, which only tracks arrow-key movement.
    const focusedRow = event.target.closest
      ? event.target.closest(
          "[data-id], .arc-search-autosuggest__row--search-for"
        )
      : null;
    if (focusedRow) {
      event.preventDefault();
      if (focusedRow.dataset && focusedRow.dataset.id) {
        this.navigateToRecord(
          focusedRow.dataset.id,
          focusedRow.dataset.objectApiName
        );
      } else {
        this.submitSearch();
      }
      return;
    }

    event.preventDefault();
    this.activateHighlighted();
  }

  moveHighlight(delta) {
    if (!this.isOpen) {
      return;
    }
    const count = this.flatItemCount;
    if (count === 0) {
      return;
    }
    this.highlightedIndex =
      this.highlightedIndex === -1
        ? delta > 0
          ? 0
          : count - 1
        : (this.highlightedIndex + delta + count) % count;

    // Move real DOM focus to the highlighted row too — not just a CSS
    // class — so it's unambiguous which row is selected, and so a
    // subsequent Enter's event.target naturally IS that row. Deferred a
    // tick so the template has re-rendered with the new highlight index
    // (and therefore the row's data-flat-index) before we query for it.
    const targetIndex = this.highlightedIndex;
    Promise.resolve().then(() => {
      if (this.highlightedIndex !== targetIndex) {
        return; // superseded by another key press already
      }
      const row = this.template.querySelector(
        `[data-flat-index="${targetIndex}"]`
      );
      if (row) {
        row.focus({ preventScroll: false });
      }
    });
  }

  /** Enter's target: the keyboard-highlighted row if any, else the default
   * "search for <term>" full-search action. */
  activateHighlighted() {
    if (
      !this.isOpen ||
      this.highlightedIndex === -1 ||
      (this.showSearchForRow && this.highlightedIndex === 0)
    ) {
      this.submitSearch();
      return;
    }

    let index = this.showSearchForRow ? 1 : 0;
    for (const category of this.visibleGroups) {
      for (const item of category.items) {
        if (index === this.highlightedIndex) {
          this.navigateToRecord(item.id, item.objectApiName);
          return;
        }
        index += 1;
      }
    }
    this.submitSearch();
  }

  navigateToRecord(id, objectApiName) {
    this.closeDropdown();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: id,
        objectApiName,
        actionName: "view"
      }
    });
  }

  /** Delegated on the component root via focusout (bubbles, unlike blur) so
   * focus leaving ANY inner control — the input, a tab button, a result
   * link — is caught, not just the input itself. */
  handleFocusOut(event) {
    const next = event.relatedTarget;
    if (next && this.template.contains(next)) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      // relatedTarget is unreliable for mouse-triggered focus changes,
      // especially when the row being clicked gets re-rendered mid-click
      // (e.g. a highlight-class update) — it can report null even though
      // focus actually landed on another control inside this component.
      // Re-checking activeElement after the tick catches that case instead
      // of collapsing the box out from under a still-open dropdown.
      if (this.template.activeElement) {
        return;
      }
      this.closeDropdown();
      this.isExpanded = false;
    }, 0);
  }

  handleIconClick() {
    this.submitSearch();
  }

  handleClearClick(event) {
    event.preventDefault();
    this.term = "";
    this.normalizedTerm = "";
    this.categories = [];
    this.totalCount = 0;
    window.clearTimeout(this._debounceId);
    this.closeDropdown();

    const input = this.template.querySelector(".arc-header-search__input");
    if (input) {
      input.focus();
    }
  }

  closeDropdown() {
    this.isOpen = false;
    this.highlightedIndex = -1;
  }

  submitSearch() {
    const term = this.term.trim();

    if (!term) {
      return;
    }

    this.closeDropdown();
    // Neither "standard__globalSearch" (not a real PageReference type) nor
    // "standard__search" (the documented type — resolves inconsistently in
    // this site/preview) reliably reached the results page. This site does
    // have a real, working Global Search route though (confirmed in
    // digitalExperiences/site/ARC1/sfdc_cms__route/Search__c: routeType
    // "global-search", urlPrefix "global-search", urlName "search" — the
    // same OOTB search page scoped to Account/Case/Task/Financial_Account__c).
    const path = `/global-search/search`;
    const url = `${communityBasePath}${path}?term=${encodeURIComponent(term)}`;
    const onResultsPage = window.location.pathname
      .replace(/\/$/, "")
      .endsWith(path);

    if (onResultsPage && term === this._lastSubmittedTerm) {
      // Genuinely nothing to do: same term, and the results page showing
      // it is still the one mounted (we never navigated away from it).
      return;
    }
    this._lastSubmittedTerm = term;

    if (onResultsPage) {
      // Already on the results page — just a new term for the same route.
      // Going through NavigationMixin here forces a full page reload (the
      // router treats a query-only change to the current route as a fresh
      // navigation); pushState instead updates the URL in place, and the
      // history patch installed by the sidebar nav (patchHistoryForNavigation)
      // dispatches NAV_PATH_CHANGE_EVENT for it, which arcGlobalSearchResults
      // listens for to re-run its search without remounting.
      window.history.pushState({}, "", url);
      return;
    }

    // Navigating in from elsewhere in the site — a real route change, so
    // NavigationMixin's soft transition (same one record navigation uses)
    // is what swaps the main region in.
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url
      }
    });
  }
}