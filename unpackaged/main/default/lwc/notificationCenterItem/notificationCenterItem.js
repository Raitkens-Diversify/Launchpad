/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { openRecordInNewTab } from "c/recordNavigationUtils";

export default class NotificationCenterItem extends NavigationMixin(
  LightningElement
) {
  @api notification;

  get cardClass() {
    const classes = ["notification-item", "slds-box", "slds-box_x-small"];

    if (!this.notification?.isRead) {
      classes.push("notification-item_unread");
    }

    return classes.join(" ");
  }

  get householdLabel() {
    return this.notification?.householdName || "Household unavailable";
  }

  get isUnread() {
    return this.notification && !this.notification.isRead;
  }

  get ariaLabel() {
    const readState = this.notification?.isRead ? "Read" : "Unread";
    return `${readState} notification: ${this.notification?.title || "Notification"}`;
  }

  get relativeTime() {
    if (!this.notification?.deliveredAt) {
      return "";
    }

    const delivered = new Date(this.notification.deliveredAt);
    const now = new Date();
    const diffMs = now.getTime() - delivered.getTime();
    const minutes = Math.floor(diffMs / 60000);

    if (minutes < 1) {
      return "Just now";
    }

    if (minutes < 60) {
      return `${minutes}m ago`;
    }

    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}h ago`;
    }

    const days = Math.floor(hours / 24);
    if (days < 7) {
      return `${days}d ago`;
    }

    return delivered.toLocaleDateString();
  }

  handleSelect = () => {
    this.dispatchEvent(
      new CustomEvent("select", {
        detail: { notificationId: this.notification?.id },
        bubbles: true,
        composed: true
      })
    );

    const targetRecordId = this.notification?.targetRecordId;
    if (!targetRecordId) {
      return;
    }

    openRecordInNewTab(this, targetRecordId);
  };

  handleKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleSelect();
  };
}