/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 *
 * Experience Cloud notification bell with inbox preview dropdown.
 * Data is sourced from NotificationCenterController (custom notification logs).
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import isGuest from "@salesforce/user/isGuest";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getInbox from "@salesforce/apex/NotificationCenterController.getInbox";
import getUnreadCount from "@salesforce/apex/NotificationCenterController.getUnreadCount";
import markAsRead from "@salesforce/apex/NotificationCenterController.markAsRead";
import { buildRecordNavigationReference } from "c/recordNavigationCommunityUtils";
import {
  HEADER_POPOVER_NOTIFICATION_BELL,
  isClickInsideHost,
  requestCloseHeaderPopover,
  requestOpenHeaderPopover,
  subscribeToHeaderPopover,
} from "c/arcHeaderPopoverCoordinator";
import { reduceError } from "c/notificationCenterUtils";

const BELL_ICON = "bell.svg";
const INBOX_FILTER_UNREAD = "UNREAD";
const INBOX_PAGE_SIZE = 100;

const SOURCE_TYPE_TO_OBJECT = Object.freeze({
  Case: "Case",
  Task: "Task",
  Event: "Event",
});

const resolveTargetObjectApiName = (recordId, sourceType) => {
  if (!recordId) {
    return null;
  }

  const keyPrefix = recordId.substring(0, 3);

  if (keyPrefix === "001") {
    return "Account";
  }

  if (keyPrefix === "500") {
    return "Case";
  }

  if (keyPrefix === "00T") {
    return "Task";
  }

  if (keyPrefix === "00U") {
    return "Event";
  }

  return SOURCE_TYPE_TO_OBJECT[sourceType] || sourceType || null;
};

const formatBellRelativeTime = (value) => {
  if (!value) {
    return "";
  }

  const eventDate = new Date(value);
  const diffMs = Date.now() - eventDate.getTime();
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

  if (days === 1) {
    return "Yesterday";
  }

  if (days < 7) {
    return `${days}d ago`;
  }

  return eventDate.toLocaleDateString();
};

const buildSubtitle = (body, householdName) => {
  const parts = [body, householdName].filter((part) => Boolean(part && String(part).trim()));

  return parts.join(" • ");
};

const mapNotificationRow = (notification) => {
  const title = notification?.title || "Notification";

  return {
    id: notification.id,
    title,
    subtitle: buildSubtitle(notification?.body, notification?.householdName),
    relativeTime: formatBellRelativeTime(notification?.deliveredAt),
    rowClass: "notification-bell__row div-popover__row",
    statusDotClass:
      "notification-bell__status-dot notification-bell__status-dot_unread",
    targetRecordId: notification?.targetRecordId,
    targetObjectApiName: resolveTargetObjectApiName(
      notification?.targetRecordId,
      notification?.sourceType
    ),
    ariaLabel: `Unread notification: ${title}`,
  };
};

export default class ArcNotificationBell extends NavigationMixin(LightningElement) {
  /** @deprecated View All link removed from the bell dropdown. */
  @api viewAllPath;

  /** @deprecated Bell shows all unread notifications. */
  @api previewCount;

  isPanelOpen = false;
  isLoading = false;
  loadError = "";
  unreadCount = 0;
  notificationRows = [];
  _stylesLoaded = false;
  _outsideClickHandler = null;
  _outsideClickTimeoutId = null;
  _unsubscribeHeaderPopover = null;

  connectedCallback() {
    if (isGuest) {
      return;
    }

    this._unsubscribeHeaderPopover = subscribeToHeaderPopover((activePopoverId) => {
      if (activePopoverId !== HEADER_POPOVER_NOTIFICATION_BELL && this.isPanelOpen) {
        this.closePanel(false);
      }
    });

    this.loadUnreadCount();
    this.ensureStyles();
  }

  disconnectedCallback() {
    this._unbindOutsideClickListener();
    this._unsubscribeHeaderPopover?.();
    this._unsubscribeHeaderPopover = null;
  }

  _bindOutsideClickListener() {
    this._unbindOutsideClickListener();

    this._outsideClickHandler = (event) => {
      if (!this.isPanelOpen) {
        return;
      }

      if (isClickInsideHost(event, this.template.host)) {
        return;
      }

      this.closePanel();
    };

    // Defer so the opening click does not immediately close the panel.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._outsideClickTimeoutId = setTimeout(() => {
      this._outsideClickTimeoutId = null;

      if (this._outsideClickHandler) {
        window.addEventListener("click", this._outsideClickHandler, true);
      }
    }, 0);
  }

  _unbindOutsideClickListener() {
    if (this._outsideClickTimeoutId != null) {
      clearTimeout(this._outsideClickTimeoutId);
      this._outsideClickTimeoutId = null;
    }

    if (this._outsideClickHandler) {
      window.removeEventListener("click", this._outsideClickHandler, true);
      this._outsideClickHandler = null;
    }
  }

  get isVisible() {
    return !isGuest;
  }

  get iconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${BELL_ICON}');`;
  }

  get bellButtonClass() {
    const classes = ["notification-bell__trigger", "div-btn", "div-btn--icon"];

    if (this.isPanelOpen) {
      classes.push("notification-bell__trigger_active", "div-btn--active");
    }

    return classes.join(" ");
  }

  get showUnreadBadge() {
    return this.unreadCount > 0;
  }

  get unreadBadgeLabel() {
    if (this.unreadCount > 99) {
      return "99+";
    }

    return String(this.unreadCount);
  }

  get unreadBadgeAriaLabel() {
    return `${this.unreadCount} unread notifications`;
  }

  get panelId() {
    return "arc-notification-bell-panel";
  }

  get hasNotifications() {
    return this.notificationRows.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.loadError && !this.hasNotifications;
  }

  ensureStyles() {
    if (this._stylesLoaded) {
      return;
    }

    loadStyle(this, diversifyStyles)
      .then(() => {
        this._stylesLoaded = true;
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[arcNotificationBell] Failed to load diversifyStyles", error);
      });
  }

  async loadUnreadCount() {
    try {
      const count = await getUnreadCount();
      this.unreadCount = Number(count) || 0;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcNotificationBell] Failed to load unread count", error);
    }
  }

  async loadUnreadNotifications() {
    this.isLoading = true;
    this.loadError = "";
    this.notificationRows = [];

    try {
      const allItems = [];
      let lastSeenId = null;
      let hasMore = true;
      let inboxStats = null;

      while (hasMore) {
        const result = await getInbox({
          filterName: INBOX_FILTER_UNREAD,
          searchTerm: null,
          pageSize: INBOX_PAGE_SIZE,
          lastSeenId,
          sortDirection: "newest",
        });

        const items = result?.items || [];
        inboxStats = result?.stats || inboxStats;
        allItems.push(...items);

        hasMore = result?.hasMore === true && items.length > 0;
        lastSeenId = items.length > 0 ? items[items.length - 1].id : null;
      }

      this.notificationRows = allItems.map(mapNotificationRow);
      this.unreadCount =
        Number(inboxStats?.unreadCount) || allItems.length || 0;
    } catch (error) {
      this.loadError = reduceError(error);
      this.notificationRows = [];
      // eslint-disable-next-line no-console
      console.error("[arcNotificationBell] Failed to load unread notifications", error);
    } finally {
      this.isLoading = false;
    }
  }

  handleBellClick(event) {
    event.stopPropagation();

    if (this.isPanelOpen) {
      this.closePanel();
      return;
    }

    this.openPanel();
  }

  handleBellKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    if (this.isPanelOpen) {
      this.closePanel();
      return;
    }

    this.openPanel();
  }

  openPanel() {
    requestOpenHeaderPopover(HEADER_POPOVER_NOTIFICATION_BELL);
    this.isPanelOpen = true;
    this._bindOutsideClickListener();
    this.loadUnreadNotifications();
  }

  closePanel(shouldNotifyCoordinator = true) {
    if (!this.isPanelOpen) {
      return;
    }

    this.isPanelOpen = false;
    this._unbindOutsideClickListener();

    if (shouldNotifyCoordinator) {
      requestCloseHeaderPopover(HEADER_POPOVER_NOTIFICATION_BELL);
    }
  }

  handleNotificationClick(event) {
    event.stopPropagation();

    const notificationId = event.currentTarget.dataset.id;
    const row = this.notificationRows.find((item) => item.id === notificationId);

    if (!row) {
      return;
    }

    this.markNotificationRead(notificationId);

    if (row.targetRecordId) {
      this.navigateToRecord(row.targetRecordId, row.targetObjectApiName);
    }

    this.closePanel();
  }

  handleNotificationKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleNotificationClick(event);
  }

  async markNotificationRead(notificationId) {
    try {
      await markAsRead({ notificationIds: [notificationId] });
      this.notificationRows = this.notificationRows.filter(
        (row) => row.id !== notificationId
      );
      this.unreadCount = Math.max(0, this.unreadCount - 1);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcNotificationBell] Failed to mark notification read", error);
    }
  }

  navigateToRecord(recordId, objectApiName) {
    const pageReference = buildRecordNavigationReference(recordId, objectApiName);

    if (!pageReference) {
      return;
    }

    this[NavigationMixin.Navigate](pageReference);
  }
}