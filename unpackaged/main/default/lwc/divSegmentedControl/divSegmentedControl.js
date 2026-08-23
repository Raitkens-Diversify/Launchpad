/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Flat segmented control (All | My Team). Uses .div-segmented from diversifyStyles.
 */
import { LightningElement, api } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

export default class DivSegmentedControl extends LightningElement {
  /** @type {{ value: string, label: string }[]} */
  @api options = [];

  @api value = "";
  @api groupLabel = "Options";

  _stylesLoaded = false;

  connectedCallback() {
    if (this._stylesLoaded) {
      return;
    }

    this._stylesLoaded = true;
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[divSegmentedControl] Failed to load diversifyStyles", error);
    });
  }

  get decoratedOptions() {
    return (this.options || []).map((option) => {
      const isSelected = option.value === this.value;
      return {
        key: option.value,
        value: option.value,
        label: option.label,
        ariaPressed: isSelected,
        cssClass: isSelected
          ? "div-segmented__option div-segmented__option--selected"
          : "div-segmented__option",
      };
    });
  }

  handleSelect(event) {
    const nextValue = event.currentTarget.dataset.value;
    if (!nextValue || nextValue === this.value) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: nextValue },
        bubbles: true,
        composed: true,
      })
    );
  }
}