/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";

export default class BookOfBusinessSavedViews extends LightningElement {
  @api savedViews = [];
  @api activeViewId = "";
  @api hasUnsavedChanges = false;

  isSavePromptOpen = false;
  draftViewName = "";
  nameError = "";
  _pendingPromptName = "";
  _shouldFocusPromptInput = false;

  editingViewId = "";
  draftRenameName = "";
  renameError = "";
  _shouldFocusRenameInput = false;

  @api
  get viewName() {
    return this._pendingPromptName;
  }

  set viewName(value) {
    const nextValue = (value || "").trim();

    if (!nextValue) {
      this._pendingPromptName = "";
      return;
    }

    if (nextValue !== this._pendingPromptName) {
      this._pendingPromptName = nextValue;
      this.openSavePrompt(nextValue);
    }
  }

  get hasSavedViews() {
    return (this.savedViews || []).length > 0;
  }

  get showSaveChanges() {
    return Boolean(this.activeViewId && this.hasUnsavedChanges);
  }

  get saveNewViewLabel() {
    return this.activeViewId ? "Save as new view" : "Save current view";
  }

  get showSaveAsPrimary() {
    return !this.showSaveChanges;
  }

  get savePromptTitle() {
    return this.activeViewId ? "Save as new view" : "Save view";
  }

  get savePromptHint() {
    return this.activeViewId
      ? "Enter a unique name for a copy of the current configuration."
      : "Enter a unique name for this view.";
  }

  get saveAsNewButtonClass() {
    return this.showSaveAsPrimary
      ? "div-toolbar__button div-toolbar__button--primary"
      : "div-toolbar__button";
  }

  get hasNameError() {
    return Boolean(this.nameError);
  }

  get decoratedViews() {
    return (this.savedViews || []).map((view) => {
      const isEditing = view.id === this.editingViewId;
      const hasRenameError = isEditing && Boolean(this.renameError);

      return {
        key: view.id,
        id: view.id,
        name: view.name,
        isActive: view.id === this.activeViewId,
        isEditing,
        ariaCurrent: view.id === this.activeViewId ? "true" : undefined,
        itemClass:
          view.id === this.activeViewId
            ? "div-saved-views__item div-saved-views__item--active"
            : "div-saved-views__item",
        applyButtonClass:
          view.id === this.activeViewId
            ? "div-saved-views__apply div-saved-views__apply--active"
            : "div-saved-views__apply",
        showUnsavedIndicator:
          view.id === this.activeViewId && this.hasUnsavedChanges,
        showRenameButton: !isEditing,
        renameAriaLabel: `Rename ${view.name}`,
        deleteAriaLabel: `Delete ${view.name}`,
        hasRenameError,
        renameErrorId: `saved-view-rename-error-${view.id}`,
        renameInputClass: hasRenameError
          ? "div-saved-views__rename-input div-saved-views__rename-input--error"
          : "div-saved-views__rename-input"
      };
    });
  }

  renderedCallback() {
    if (this.isSavePromptOpen && this._shouldFocusPromptInput) {
      const input = this.template.querySelector("#saved-view-name");

      if (input) {
        input.focus();
        input.select();
      }

      this._shouldFocusPromptInput = false;
    }

    if (this.editingViewId && this._shouldFocusRenameInput) {
      const input = this.template.querySelector(
        `[data-view-id="${this.editingViewId}"]`
      );

      if (input) {
        input.focus();
        input.select();
      }

      this._shouldFocusRenameInput = false;
    }
  }

  openSavePrompt(initialName = "") {
    this.draftViewName = initialName;
    this.nameError = "";
    this.isSavePromptOpen = true;
    this._shouldFocusPromptInput = true;
  }

  closeSavePrompt() {
    this.isSavePromptOpen = false;
    this.draftViewName = "";
    this.nameError = "";
    this._pendingPromptName = "";
  }

  cancelRename() {
    this.editingViewId = "";
    this.draftRenameName = "";
    this.renameError = "";
    this._shouldFocusRenameInput = false;
  }

  isNameUnique(name, excludeViewId = "") {
    const normalizedName = name.trim().toLowerCase();

    return !(this.savedViews || []).some(
      (view) =>
        view.id !== excludeViewId &&
        (view.name || "").trim().toLowerCase() === normalizedName
    );
  }

  validateDraftViewName() {
    const trimmedName = (this.draftViewName || "").trim();

    if (!trimmedName) {
      this.nameError = "Enter a view name.";
      return null;
    }

    if (!this.isNameUnique(trimmedName)) {
      this.nameError = "A view with this name already exists. Choose a unique name.";
      return null;
    }

    this.nameError = "";
    return trimmedName;
  }

  validateDraftRenameName(viewId) {
    const trimmedName = (this.draftRenameName || "").trim();
    const sourceView = (this.savedViews || []).find((view) => view.id === viewId);

    if (!trimmedName) {
      this.renameError = "";
      return null;
    }

    if (trimmedName === (sourceView?.name || "").trim()) {
      this.renameError = "";
      return null;
    }

    if (!this.isNameUnique(trimmedName, viewId)) {
      this.renameError = "A view with this name already exists.";
      return null;
    }

    this.renameError = "";
    return trimmedName;
  }

  handleUpdateView() {
    this.dispatchEvent(new CustomEvent("updateview"));
  }

  handleOpenSavePrompt() {
    this.openSavePrompt("");
  }

  handleDraftViewNameChange(event) {
    this.draftViewName = event.target.value;

    if (this.nameError) {
      this.nameError = "";
    }
  }

  handlePromptKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.handleConfirmSaveView();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      this.handleCancelSavePrompt();
    }
  }

  handleCancelSavePrompt() {
    this.closeSavePrompt();
    this.dispatchEvent(new CustomEvent("savepromptclose"));
  }

  handleConfirmSaveView() {
    const trimmedName = this.validateDraftViewName();

    if (!trimmedName) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent("saveview", {
        detail: {
          name: trimmedName
        }
      })
    );
    this.closeSavePrompt();
  }

  handleSaveView() {
    this.handleOpenSavePrompt();
  }

  async handleApplyView(event) {
    const viewId = event.currentTarget.dataset.id;

    if (!viewId || viewId === this.activeViewId) {
      return;
    }

    if (this.hasUnsavedChanges && this.activeViewId) {
      const activeView = (this.savedViews || []).find(
        (savedView) => savedView.id === this.activeViewId
      );
      const targetView = (this.savedViews || []).find((savedView) => savedView.id === viewId);
      const confirmed = await LightningConfirm.open({
        label: "Unsaved changes",
        message: `You have unsaved changes to "${activeView?.name || "this view"}". Switch to "${targetView?.name || "the selected view"}" without saving?`,
        theme: "warning",
        variant: "header"
      });

      if (!confirmed) {
        return;
      }
    }

    this.dispatchEvent(
      new CustomEvent("applyview", {
        detail: {
          viewId
        }
      })
    );
  }

  handleStartRename(event) {
    event.stopPropagation();

    const viewId = event.currentTarget.dataset.id;
    const view = (this.savedViews || []).find((savedView) => savedView.id === viewId);

    if (!view) {
      return;
    }

    if (this.editingViewId && this.editingViewId !== viewId) {
      this.cancelRename();
    }

    this.editingViewId = viewId;
    this.draftRenameName = view.name || "";
    this.renameError = "";
    this._shouldFocusRenameInput = true;
  }

  handleRenameInput(event) {
    this.draftRenameName = event.target.value;

    if (this.renameError) {
      this.renameError = "";
    }
  }

  handleRenameKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.currentTarget.blur();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      this.cancelRename();
    }
  }

  handleRenameBlur() {
    if (!this.editingViewId) {
      return;
    }

    const viewId = this.editingViewId;
    const trimmedName = this.validateDraftRenameName(viewId);

    if (!trimmedName) {
      if (this.renameError) {
        this._shouldFocusRenameInput = true;
        return;
      }

      this.cancelRename();
      return;
    }

    this.dispatchEvent(
      new CustomEvent("renameview", {
        detail: {
          viewId,
          name: trimmedName
        }
      })
    );
    this.cancelRename();
  }

  async handleDeleteView(event) {
    const viewId = event.currentTarget.dataset.id;
    const view = (this.savedViews || []).find((savedView) => savedView.id === viewId);

    if (!view) {
      return;
    }

    const confirmed = await LightningConfirm.open({
      label: "Delete saved view",
      message: `Delete "${view.name}"? This action cannot be undone.`,
      theme: "warning",
      variant: "header"
    });

    if (!confirmed) {
      return;
    }

    if (this.editingViewId === viewId) {
      this.cancelRename();
    }

    this.dispatchEvent(
      new CustomEvent("deleteview", {
        detail: {
          viewId
        }
      })
    );
  }
}