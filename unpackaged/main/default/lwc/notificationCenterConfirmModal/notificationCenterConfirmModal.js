/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-08
 *
 * Reusable confirmation dialog for Notification Center surfaces.
 * Uses rule-modal styles from diversifyStyles.css.
 */
import { LightningElement, api } from "lwc";
import { ICON } from "c/notificationCenterUtils";

export default class NotificationCenterConfirmModal extends LightningElement {
  @api isOpen = false;
  @api title = "Confirm";
  @api message = "";
  @api confirmLabel = "Confirm";
  @api cancelLabel = "Cancel";
  @api listLabel = "";
  @api listItems = [];
  @api elevated = false;
  @api isBusy = false;

  closeIcon = ICON.CLOSE;

  get modalClass() {
    return this.elevated ? "rule-modal rule-modal--elevated" : "rule-modal";
  }

  get isConfirmDisabled() {
    return this.isBusy;
  }

  get isCancelDisabled() {
    return this.isBusy;
  }

  get decoratedListItems() {
    return (this.listItems || []).map((label, index) => ({
      id: `${index}-${label}`,
      label
    }));
  }

  get hasListItems() {
    return this.decoratedListItems.length > 0;
  }

  handleCancel = (event) => {
    if (this.isBusy) {
      return;
    }

    event?.preventDefault();
    event?.stopPropagation();
    this.dispatchEvent(new CustomEvent("cancel"));
  };

  handleConfirm = (event) => {
    if (this.isBusy) {
      return;
    }

    event?.preventDefault();
    event?.stopPropagation();
    this.dispatchEvent(new CustomEvent("confirm"));
  };

  handleBackdropClick = (event) => {
    if (this.isBusy) {
      return;
    }

    this.handleCancel(event);
  };

  handlePanelClick = (event) => {
    event.stopPropagation();
  };

  handleKeyDown = (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      this.handleCancel();
    }
  };
}