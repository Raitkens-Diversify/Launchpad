/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

const MENU_MAX_HEIGHT_PX = 176;
const MENU_MIN_HEIGHT_PX = 80;
const MENU_VIEWPORT_PADDING_PX = 8;

export default class DivMultiSelect extends LightningElement {
  @api label = "";
  @api placeholder = "Search...";
  @api options = [];
  @api disabled = false;
  @api emptyMessage = "No options match your search.";
  @api variant = "default";
  @api chipPlacement = "inline";

  searchTerm = "";
  isOpen = false;
  _selectedValues = [];
  _instanceId = "";
  _outsidePointerHandler;
  _escapeHandler;
  _globalOpenHandler;
  _focusOutHandler;
  _menuRepositionHandler;
  _outsideListenersBound = false;
  _menuPositionBound = false;
  _needsMenuPosition = false;
  _menuStyle = "";
  _menuOpensAbove = false;
  _suppressCloseUntil = 0;
  stylesLoaded = false;

  @api
  get value() {
    return this._selectedValues;
  }

  set value(nextValue) {
    this._selectedValues = Array.isArray(nextValue) ? [...nextValue] : [];
  }

  get showLabel() {
    return Boolean(this.label);
  }

  get isSearchVariant() {
    return this.variant === "search";
  }

  get isChipsBelow() {
    return this.chipPlacement === "below";
  }

  get rootClass() {
    const classes = ["div-multiselect", "slds-form-element"];

    if (this.isSearchVariant) {
      classes.push("div-multiselect--search");
    }

    if (this.isChipsBelow) {
      classes.push("div-multiselect--chips-below");
    }

    return classes.join(" ");
  }

  get selectedChips() {
    return this._selectedValues.map((optionValue) => {
      const match = (this.options || []).find((option) => option.value === optionValue);

      return {
        value: optionValue,
        label: match?.label || optionValue,
        removeAriaLabel: `Remove ${match?.label || optionValue}`
      };
    });
  }

  get showOverflowBadge() {
    return !this.isChipsBelow && this.selectedChips.length > 1;
  }

  get overflowTotal() {
    return this.selectedChips.length;
  }

  get overflowAriaLabel() {
    return `${this.overflowTotal} items selected`;
  }

  get visibleChips() {
    if (this.isChipsBelow || !this.selectedChips.length) {
      return [];
    }

    if (this.showOverflowBadge) {
      return [this.selectedChips[this.selectedChips.length - 1]];
    }

    return this.selectedChips;
  }

  get belowChips() {
    return this.isChipsBelow ? this.selectedChips : [];
  }

  get hasBelowChips() {
    return this.belowChips.length > 0;
  }

  get inputPlaceholder() {
    if (this.isChipsBelow || !this.selectedChips.length) {
      return this.placeholder;
    }

    return "";
  }

  get searchAriaLabel() {
    return this.label ? `Search ${this.label}` : "Search options";
  }

  get filteredOptions() {
    const term = this.searchTerm.trim().toLowerCase();

    return (this.options || [])
      .filter(
        (option) =>
          !term || String(option.label || "").toLowerCase().includes(term)
      )
      .map((option) => {
        const isSelected = this._selectedValues.includes(option.value);

        return {
          ...option,
          isSelected,
          optionClass: isSelected
            ? "div-multiselect__option div-multiselect__option_selected"
            : "div-multiselect__option"
        };
      });
  }

  get hasNoFilteredOptions() {
    return this.filteredOptions.length === 0;
  }

  get controlClass() {
    const classes = ["div-multiselect__control"];

    if (this.isSearchVariant) {
      classes.push("div-multiselect__control_search");
    }

    if (this.disabled) {
      classes.push("div-multiselect__control_disabled");
    }

    if (this.isOpen) {
      classes.push("div-multiselect__control_open");
    }

    return classes.join(" ");
  }

  get menuClass() {
    const classes = ["div-multiselect__menu"];

    if (this._menuOpensAbove) {
      classes.push("div-multiselect__menu_top");
    }

    return classes.join(" ");
  }

  get menuStyle() {
    return this._menuStyle;
  }

  get ariaExpanded() {
    return this.isOpen ? "true" : "false";
  }

  get showToggleButton() {
    return !this.isSearchVariant;
  }

  connectedCallback() {
    if (!this.stylesLoaded) {
      loadStyle(this, diversifyStyles)
        .then(() => {
          this.stylesLoaded = true;
        })
        .catch((error) => {
          console.error("[divMultiSelect] Failed to load diversifyStyles", error);
        });
    }

    this._instanceId = `div-ms-${Math.random().toString(36).slice(2)}`;

    this._globalOpenHandler = (event) => {
      if (event.detail?.instanceId !== this._instanceId && this.isOpen) {
        this.closeDropdown();
      }
    };

    this._outsidePointerHandler = (event) => {
      if (!this.isOpen || this.shouldSuppressClose()) {
        return;
      }

      if (!this.isEventInsideComponent(event)) {
        this.closeDropdown();
      }
    };

    this._escapeHandler = (event) => {
      if (event.key !== "Escape" || !this.isOpen) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      this.closeDropdown();
    };

    this._focusOutHandler = () => {
      if (!this.isOpen) {
        return;
      }

      // Allow focus to move within the component before checking.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        if (!this.isOpen || this.shouldSuppressClose()) {
          return;
        }

        const root = this.template.querySelector(".div-multiselect");

        if (root && root.matches(":focus-within")) {
          return;
        }

        this.closeDropdown();
      }, 0);
    };

    document.addEventListener("divmultiselectopen", this._globalOpenHandler);
  }

  disconnectedCallback() {
    if (this._globalOpenHandler) {
      document.removeEventListener("divmultiselectopen", this._globalOpenHandler);
    }

    this.unbindOutsideListeners();
    this.unbindMenuPositionListeners();
  }

  bindOutsideListeners() {
    if (this._outsideListenersBound) {
      return;
    }

    window.addEventListener("pointerdown", this._outsidePointerHandler, true);
    window.addEventListener("mousedown", this._outsidePointerHandler, true);
    window.addEventListener("touchstart", this._outsidePointerHandler, true);
    window.addEventListener("keydown", this._escapeHandler, true);
    this._outsideListenersBound = true;
  }

  unbindOutsideListeners() {
    if (!this._outsideListenersBound) {
      return;
    }

    window.removeEventListener("pointerdown", this._outsidePointerHandler, true);
    window.removeEventListener("mousedown", this._outsidePointerHandler, true);
    window.removeEventListener("touchstart", this._outsidePointerHandler, true);
    window.removeEventListener("keydown", this._escapeHandler, true);
    this._outsideListenersBound = false;
  }

  shouldSuppressClose() {
    return Date.now() < this._suppressCloseUntil;
  }

  markMenuInteraction() {
    this._suppressCloseUntil = Date.now() + 250;
  }

  isEventInsideComponent(event) {
    const path = event.composedPath?.() ?? [];

    if (path.includes(this.template.host)) {
      return true;
    }

    const menu = this.template.querySelector(".div-multiselect__menu");
    const controlWrap = this.template.querySelector(".div-multiselect__control-wrap");

    for (const node of path) {
      if (node === menu || node === controlWrap) {
        return true;
      }
    }

    if (event.clientX == null || event.clientY == null) {
      return false;
    }

    const hostRect = this.template.host.getBoundingClientRect();

    if (
      event.clientX >= hostRect.left &&
      event.clientX <= hostRect.right &&
      event.clientY >= hostRect.top &&
      event.clientY <= hostRect.bottom
    ) {
      return true;
    }

    if (!menu) {
      return false;
    }

    const menuRect = menu.getBoundingClientRect();

    return (
      event.clientX >= menuRect.left &&
      event.clientX <= menuRect.right &&
      event.clientY >= menuRect.top &&
      event.clientY <= menuRect.bottom
    );
  }

  renderedCallback() {
    if (this.isOpen && this._needsMenuPosition) {
      this.positionMenu();
      this._needsMenuPosition = false;
    }
  }

  openDropdown() {
    if (this.disabled) {
      return;
    }

    document.dispatchEvent(
      new CustomEvent("divmultiselectopen", {
        detail: { instanceId: this._instanceId },
        bubbles: true,
        composed: true
      })
    );

    this.isOpen = true;
    this._needsMenuPosition = true;
    this.bindMenuPositionListeners();
    this.focusInput();

    // Defer so the opening click does not immediately close the menu.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      if (this.isOpen) {
        this.bindOutsideListeners();
      }
    }, 0);
  }

  closeDropdown() {
    this.isOpen = false;
    this.searchTerm = "";
    this._menuStyle = "";
    this._menuOpensAbove = false;
    this.unbindOutsideListeners();
    this.unbindMenuPositionListeners();
  }

  bindMenuPositionListeners() {
    if (this._menuPositionBound) {
      return;
    }

    this._menuRepositionHandler = () => {
      if (this.isOpen) {
        this.positionMenu();
      }
    };

    window.addEventListener("scroll", this._menuRepositionHandler, true);
    window.addEventListener("resize", this._menuRepositionHandler);
    this._menuPositionBound = true;
  }

  unbindMenuPositionListeners() {
    if (!this._menuPositionBound) {
      return;
    }

    window.removeEventListener("scroll", this._menuRepositionHandler, true);
    window.removeEventListener("resize", this._menuRepositionHandler);
    this._menuPositionBound = false;
  }

  positionMenu() {
    const controlWrap = this.template.querySelector(".div-multiselect__control-wrap");
    if (!controlWrap) {
      return;
    }

    const controlRect = controlWrap.getBoundingClientRect();
    const spaceBelow =
      window.innerHeight - controlRect.bottom - MENU_VIEWPORT_PADDING_PX;
    const spaceAbove = controlRect.top - MENU_VIEWPORT_PADDING_PX;

    let maxHeight = Math.min(MENU_MAX_HEIGHT_PX, spaceBelow);
    let opensAbove = false;

    if (maxHeight < MENU_MIN_HEIGHT_PX && spaceAbove > spaceBelow) {
      maxHeight = Math.min(MENU_MAX_HEIGHT_PX, spaceAbove);
      opensAbove = true;
    }

    maxHeight = Math.max(Math.round(maxHeight), MENU_MIN_HEIGHT_PX);

    this._menuOpensAbove = opensAbove;
    this._menuStyle = `max-height:${maxHeight}px`;
  }

  focusInput() {
    const input = this.template.querySelector(".div-multiselect__input");
    if (input) {
      input.focus();
    }
  }

  dispatchChange() {
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: [...this._selectedValues] }
      })
    );
  }

  handleInput(event) {
    this.searchTerm = event.target.value;

    if (!this.isOpen) {
      this.openDropdown();
    }
  }

  handleInputClick(event) {
    event.stopPropagation();

    if (!this.isOpen) {
      this.openDropdown();
    }
  }

  handleInputKeydown(event) {
    if (
      event.key === "Backspace" &&
      !this.searchTerm &&
      this._selectedValues.length &&
      !this.isChipsBelow
    ) {
      event.preventDefault();
      this._selectedValues = this._selectedValues.slice(0, -1);
      this.dispatchChange();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      this.closeDropdown();
    }
  }

  handleToggleClick(event) {
    event.stopPropagation();

    if (this.disabled) {
      return;
    }

    if (this.isOpen) {
      this.closeDropdown();
      return;
    }

    this.openDropdown();
  }

  handleMenuMouseDown(event) {
    event.preventDefault();
    event.stopPropagation();
    this.markMenuInteraction();
  }

  handleOptionMouseDown(event) {
    event.preventDefault();
    event.stopPropagation();
    this.markMenuInteraction();
  }

  handleOptionClick(event) {
    event.stopPropagation();
    this.markMenuInteraction();

    const optionValue = event.currentTarget?.dataset?.value;
    if (!optionValue) {
      return;
    }

    if (this._selectedValues.includes(optionValue)) {
      this._selectedValues = this._selectedValues.filter((value) => value !== optionValue);
    } else {
      this._selectedValues = [...this._selectedValues, optionValue];
    }

    this.searchTerm = "";
    this.dispatchChange();
    this.focusInput();
  }

  handleChipRemove(event) {
    event.stopPropagation();

    const optionValue = event.currentTarget?.dataset?.value;
    if (!optionValue) {
      return;
    }

    this._selectedValues = this._selectedValues.filter((value) => value !== optionValue);
    this.dispatchChange();
    this.focusInput();
  }

  handleRootFocusOut = () => {
    this._focusOutHandler();
  };
}