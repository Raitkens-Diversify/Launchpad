/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Reusable list toolbar: search, optional Filter button, segmented scope control.
 */
import { LightningElement, api } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

export default class DivListToolbar extends LightningElement {
  @api searchValue = "";
  @api searchPlaceholder = "Search...";
  @api showSearch;
  @api showFilterButton = false;
  @api filterLabel = "Filter";
  @api filterActive = false;

  /** @type {{ value: string, label: string }[]} */
  @api scopeOptions = [];

  @api scopeValue = "";
  @api scopeLabel = "Record scope";

  _stylesLoaded = false;

  connectedCallback() {
    if (this._stylesLoaded) {
      return;
    }

    this._stylesLoaded = true;
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[divListToolbar] Failed to load diversifyStyles", error);
    });
  }

  get shouldShowSearch() {
    return this.showSearch !== false;
  }

  get filterButtonClass() {
    return this.filterActive
      ? "div-toolbar__button div-toolbar__button--active"
      : "div-toolbar__button";
  }

  get showScopeControl() {
    return (this.scopeOptions || []).length > 0;
  }

  handleSearchInput(event) {
    const value = event.target.value || "";
    this.dispatchEvent(
      new CustomEvent("search", {
        detail: { value },
        bubbles: true,
        composed: true,
      })
    );
  }

  handleFilterClick() {
    this.dispatchEvent(
      new CustomEvent("filterclick", {
        bubbles: true,
        composed: true,
      })
    );
  }

  handleScopeChange(event) {
    this.dispatchEvent(
      new CustomEvent("scopechange", {
        detail: event.detail,
        bubbles: true,
        composed: true,
      })
    );
  }
}