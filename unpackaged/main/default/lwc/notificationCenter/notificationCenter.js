/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 *
 * Sole loader for diversifyStyles.css across the Notification Center app shell.
 * Child views inherit design tokens, buttons, div-callout, div-filter, and datatable styles
 * from the stylesheet injected here.
 */
import { LightningElement, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import USER_PROFILE_NAME from "@salesforce/schema/User.Profile.Name";
import USER_ID from "@salesforce/user/Id";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import { ICON, NAV_VIEW_ICONS } from "c/notificationCenterUtils";

let diversifyStylesLoadPromise;

const ensureDiversifyStyles = (host) => {
  if (!diversifyStylesLoadPromise) {
    diversifyStylesLoadPromise = loadStyle(host, diversifyStyles).catch((error) => {
      diversifyStylesLoadPromise = undefined;
      throw error;
    });
  }

  return diversifyStylesLoadPromise;
};

const VIEW_CONFIG = Object.freeze({
  dashboard: {
    title: "Dashboard",
    label: "Dashboard",
    subtitle: "Overview of notification activity across channels",
    icon: NAV_VIEW_ICONS.dashboard
  },
  "notification-rules": {
    title: "Notification Rules",
    label: "Notification Rules",
    subtitle: "Rules triggered by Task, Case, and Event changes on Household records",
    icon: NAV_VIEW_ICONS["notification-rules"]
  },
  "notification-log": {
    title: "Notification Log",
    label: "Notification Log",
    subtitle: "Delivery history with status, channel, and suppression reasons",
    icon: NAV_VIEW_ICONS["notification-log"]
  },
  "admin-settings": {
    title: "Admin Settings",
    label: "Admin Settings",
    subtitle: "Manage org-wide notification center configuration",
    icon: NAV_VIEW_ICONS["admin-settings"]
  }
});

const BASE_NAV_ITEM_IDS = Object.freeze([
  "dashboard",
  "notification-rules",
  "notification-log"
]);

const ADMIN_ONLY_VIEW_IDS = Object.freeze(["admin-settings"]);

const ADMIN_NAV_ITEM_IDS = Object.freeze(["admin-settings"]);

const SYSTEM_ADMINISTRATOR_PROFILE = "System Administrator";

export default class NotificationCenter extends LightningElement {
  activeView = "dashboard";
  userId = USER_ID;
  icons = ICON;
  stylesLoaded = false;
  stylesLoadError = "";
  isViewLoading = true;
  pendingViewRefresh = new Set();

  connectedCallback() {
    if (this.stylesLoaded) {
      return;
    }

    ensureDiversifyStyles(this)
      .then(() => {
        this.stylesLoaded = true;
        this.stylesLoadError = "";
      })
      .catch((error) => {
        this.stylesLoadError =
          "Unable to load Notification Center styles. Refresh the page and try again.";
        // eslint-disable-next-line no-console
        console.error("[notificationCenter] Failed to load diversifyStyles", error);
      });
  }

  get isAppReady() {
    return this.stylesLoaded;
  }

  get showInitialSkeleton() {
    return !this.stylesLoaded;
  }

  get skeletonLabel() {
    return "Loading Notification Center";
  }

  @wire(getRecord, { recordId: "$userId", fields: [USER_PROFILE_NAME] })
  userRecord;

  get isSystemAdministrator() {
    return (
      getFieldValue(this.userRecord?.data, USER_PROFILE_NAME) ===
      SYSTEM_ADMINISTRATOR_PROFILE
    );
  }

  get navItems() {
    const navItemIds = this.isSystemAdministrator
      ? [...BASE_NAV_ITEM_IDS, ...ADMIN_NAV_ITEM_IDS]
      : [...BASE_NAV_ITEM_IDS];

    return navItemIds.map((id) => {
      const config = VIEW_CONFIG[id];
      const isActive = id === this.activeView;

      return {
        id,
        label: config.label,
        icon: config.icon,
        buttonClass: isActive
          ? "sidebar__nav-button sidebar__nav-button_active"
          : "sidebar__nav-button",
        ariaCurrent: isActive ? "page" : "false"
      };
    });
  }

  get activeViewTitle() {
    return VIEW_CONFIG[this.activeView]?.title || VIEW_CONFIG.dashboard.title;
  }

  get crumbItems() {
    return [
      { label: "Notification Center", muted: true },
      { label: this.activeViewTitle, current: true }
    ];
  }

  get activeViewSubtitle() {
    return VIEW_CONFIG[this.activeView]?.subtitle || VIEW_CONFIG.dashboard.subtitle;
  }

  get activeViewFlags() {
    return {
      dashboard: this.activeView === "dashboard",
      notificationRules: this.activeView === "notification-rules",
      notificationLog: this.activeView === "notification-log",
      adminSettings: this.activeView === "admin-settings"
    };
  }

  handleNavigate = (event) => {
    const viewId =
      event.currentTarget.dataset.view ||
      event.currentTarget.getAttribute("data-view");
    if (!VIEW_CONFIG[viewId]) {
      return;
    }

    if (!this.isSystemAdministrator && ADMIN_ONLY_VIEW_IDS.includes(viewId)) {
      return;
    }

    this.activeView = viewId;
    this.isViewLoading = true;
    this.refreshActiveViewIfNeeded();
  };

  handleNotificationCenterViewReady = () => {
    this.isViewLoading = false;
  };

  handleNotificationCenterChange = (event) => {
    if (event.detail?.source === "notification-rules") {
      this.pendingViewRefresh.add("dashboard");
      this.pendingViewRefresh.add("notification-log");
    }
  };

  refreshActiveViewIfNeeded() {
    if (!this.pendingViewRefresh.has(this.activeView)) {
      return;
    }

    this.pendingViewRefresh.delete(this.activeView);

    requestAnimationFrame(() => {
      const viewComponent = this.template.querySelector(
        `[data-notification-view="${this.activeView}"]`
      );

      viewComponent?.refresh?.();
    });
  }

  handleNavigateKeyDown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleNavigate(event);
  };
}