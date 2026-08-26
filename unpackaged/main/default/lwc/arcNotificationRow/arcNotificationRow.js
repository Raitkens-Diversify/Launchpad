import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import markAsRead from "@salesforce/apex/NotificationCenterController.markAsRead";
import { buildRecordNavigationReference } from "c/recordNavigationCommunityUtils";

const WARNING_ICON = "warning.svg";

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;

const startOfDay = (date) =>
  new Date(date.getFullYear(), date.getMonth(), date.getDate());

/**
 * Matches the Figma "Line Item" notification row exactly: same-day items
 * show elapsed minutes/hours, yesterday is called out by name, and older
 * items count days ago (e.g. "2h ago", "Yesterday", "3d ago").
 */
export function formatNotificationTime(value) {
  if (!value) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  const now = new Date();
  const dayDiff = Math.round(
    (startOfDay(now) - startOfDay(date)) / (24 * HOUR_MS)
  );

  if (dayDiff <= 0) {
    const elapsedMs = now - date;
    if (elapsedMs < MINUTE_MS) {
      return "Just now";
    }
    if (elapsedMs < HOUR_MS) {
      return `${Math.floor(elapsedMs / MINUTE_MS)}m ago`;
    }
    return `${Math.floor(elapsedMs / HOUR_MS)}h ago`;
  }

  if (dayDiff === 1) {
    return "Yesterday";
  }

  return `${dayDiff}d ago`;
}

/**
 * A single notification "Line Item" (Figma nodes 760:132514 and 781:25920):
 * unread dot + title (+ optional urgent-priority warning icon) + subtitle +
 * right-aligned relative time. Reused by both the header bell dropdown and
 * the full Notifications page so the row markup/behavior never drifts
 * between the two surfaces.
 */
export default class ArcNotificationRow extends NavigationMixin(
  LightningElement
) {
  /**
   * Expected shape (NotificationCenterModels.InboxItem):
   * { id, title, body, sourceType, householdName, deliveredAt, isRead,
   *   isUrgent, targetRecordId }
   */
  @api notification;

  get isUnread() {
    return !(this.notification && this.notification.isRead);
  }

  get dotClass() {
    return this.isUnread
      ? "arc-notification-row__dot arc-notification-row__dot--unread"
      : "arc-notification-row__dot";
  }

  get titleClass() {
    return this.isUnread
      ? "arc-notification-row__title arc-notification-row__title--unread"
      : "arc-notification-row__title";
  }

  get showWarning() {
    return Boolean(this.notification && this.notification.isUrgent);
  }

  get warningIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${WARNING_ICON}');`;
  }

  get subtitle() {
    const notification = this.notification || {};
    if (notification.householdName) {
      return notification.body
        ? `${notification.body} • ${notification.householdName}`
        : notification.householdName;
    }
    return notification.body || "";
  }

  get relativeTime() {
    return formatNotificationTime(
      this.notification && this.notification.deliveredAt
    );
  }

  handleClick() {
    const notification = this.notification;
    if (!notification) {
      return;
    }

    if (!notification.isRead && notification.id) {
      markAsRead({ notificationIds: [notification.id] }).catch(() => {
        // Non-fatal: the row still navigates even if the read receipt fails.
      });
    }

    this.dispatchEvent(
      new CustomEvent("select", {
        bubbles: true,
        detail: { id: notification.id }
      })
    );

    if (notification.targetRecordId) {
      const pageReference = buildRecordNavigationReference(
        notification.targetRecordId,
        notification.sourceType
      );
      if (pageReference) {
        this[NavigationMixin.Navigate](pageReference);
      }
    }
  }

  handleKeyDown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleClick();
    }
  }
}