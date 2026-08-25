/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api } from "lwc";
import { GROUP_BY_OPTIONS, VIEW_MODE_CHART, VIEW_MODE_TABLE } from "c/bookOfBusinessUtils";

const POPOVER_NONE = "none";
const POPOVER_GROUP_BY = "groupBy";
const POPOVER_SAVED_VIEWS = "savedViews";

export default class BookOfBusinessToolbar extends LightningElement {
  @api viewMode = VIEW_MODE_TABLE;
  @api groupBy = "none";
  @api savedViews = [];
  @api savedViewName = "";
  @api activeViewId = "";
  @api activeViewLabel = "";
  @api hasUnsavedViewChanges = false;

  get hasActiveViewLabel() {
    return Boolean((this.activeViewLabel || "").trim());
  }

  get savedViewsButtonLabel() {
    if (this.hasActiveViewLabel) {
      return this.activeViewLabel;
    }

    return "Saved views";
  }

  get savedViewsButtonAriaLabel() {
    if (this.hasActiveViewLabel) {
      const unsavedSuffix = this.hasUnsavedViewChanges ? ", unsaved changes" : "";
      return `Saved view, ${this.activeViewLabel}${unsavedSuffix}`;
    }

    return "Saved views";
  }

  activePopover = POPOVER_NONE;

  connectedCallback() {
    this._handleDocumentKeyDown = this.handleDocumentKeyDown.bind(this);
    window.addEventListener("keydown", this._handleDocumentKeyDown);
    window.addEventListener("mousedown", this.handleOutsideClick, true);
    window.addEventListener("touchstart", this.handleOutsideClick, true);
  }

  disconnectedCallback() {
    window.removeEventListener("keydown", this._handleDocumentKeyDown);
    window.removeEventListener("mousedown", this.handleOutsideClick, true);
    window.removeEventListener("touchstart", this.handleOutsideClick, true);
  }

  handleBackdropClick(event) {
    event.stopPropagation();
    this.handleClosePopovers();
  }

  handleOutsideClick = (event) => {
    if (!this.hasOpenPopover) {
      return;
    }

    if (this.isEventInsideActivePopover(event)) {
      return;
    }

    this.handleClosePopovers();
  };

  isEventInsideActivePopover(event) {
    const popoverRoot = this.template.querySelector(
      `[data-popover-root="${this.activePopover}"]`
    );

    if (!popoverRoot) {
      return false;
    }

    const path = event.composedPath();

    return path.some((node) => {
      if (node === popoverRoot) {
        return true;
      }

      if (!(node instanceof Node)) {
        return false;
      }

      return popoverRoot.contains(node);
    });
  }

  handleDocumentKeyDown(event) {
    if (event.key !== "Escape" || !this.hasOpenPopover) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.handleClosePopovers();
  }

  get hasOpenPopover() {
    return this.activePopover !== POPOVER_NONE;
  }

  get groupByOptions() {
    return GROUP_BY_OPTIONS.map((option) => ({
      key: option.value,
      label: option.label,
      value: option.value,
      isSelected: option.value === this.groupBy,
      buttonClass:
        option.value === this.groupBy
          ? "div-toolbar-popover__option div-toolbar-popover__option--active"
          : "div-toolbar-popover__option"
    }));
  }

  get groupByButtonLabel() {
    const selectedOption = GROUP_BY_OPTIONS.find((option) => option.value === this.groupBy);
    return selectedOption?.label || "None";
  }

  get groupByButtonAriaLabel() {
    return `Group by, ${this.groupByButtonLabel}`;
  }

  get isTableView() {
    return this.viewMode === VIEW_MODE_TABLE;
  }

  get isChartView() {
    return this.viewMode === VIEW_MODE_CHART;
  }

  get tableSegmentClass() {
    return this.isTableView
      ? "div-toolbar__segment div-toolbar__segment--active"
      : "div-toolbar__segment";
  }

  get chartSegmentClass() {
    return this.isChartView
      ? "div-toolbar__segment div-toolbar__segment--active"
      : "div-toolbar__segment";
  }

  get showGroupByPopover() {
    return this.activePopover === POPOVER_GROUP_BY;
  }

  get showSavedViewsPopover() {
    return this.activePopover === POPOVER_SAVED_VIEWS;
  }

  handleTogglePopover(event) {
    event.stopPropagation();
    const popoverName = event.currentTarget.dataset.popover;
    this.activePopover =
      this.activePopover === popoverName ? POPOVER_NONE : popoverName;
  }

  handleClosePopovers() {
    this.activePopover = POPOVER_NONE;
  }

  handleGroupBySelect(event) {
    this.dispatchEvent(
      new CustomEvent("groupbychange", {
        detail: {
          groupBy: event.currentTarget.dataset.value
        }
      })
    );
    this.activePopover = POPOVER_NONE;
  }

  handleViewModeChange(event) {
    const nextViewMode = event.currentTarget.dataset.mode;

    this.handleClosePopovers();
    this.dispatchEvent(
      new CustomEvent("viewmodechange", {
        detail: {
          viewMode: nextViewMode
        }
      })
    );
  }

  handleOpenConfigure() {
    this.dispatchEvent(new CustomEvent("configureopen"));
  }

  handleUpdateView(event) {
    this.dispatchEvent(
      new CustomEvent("updateview", {
        detail: event.detail
      })
    );
  }

  handleSaveView(event) {
    this.dispatchEvent(
      new CustomEvent("saveview", {
        detail: event.detail
      })
    );
  }

  handleApplyView(event) {
    this.dispatchEvent(
      new CustomEvent("applyview", {
        detail: event.detail
      })
    );
    this.activePopover = POPOVER_NONE;
  }

  handleDeleteView(event) {
    this.dispatchEvent(
      new CustomEvent("deleteview", {
        detail: event.detail
      })
    );
    this.activePopover = POPOVER_NONE;
  }

  handleRenameView(event) {
    this.dispatchEvent(
      new CustomEvent("renameview", {
        detail: event.detail
      })
    );
  }
}