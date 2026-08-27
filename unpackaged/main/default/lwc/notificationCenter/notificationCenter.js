/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 *
 * Sole loader for diversifyStyles.css across the Notification Center app shell.
 * Child views inherit design tokens, buttons, div-callout, div-filter, and datatable styles
 * from the stylesheet injected here.
 */
import { LightningElement, api, wire } from "lwc";
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

  /**
   * Hides the Admin Settings view even for a System Administrator.
   *
   * Off by default, so every surface that does not set it keeps the behaviour
   * it has always had: Admin Settings appears for System Administrators and for
   * nobody else. The CRM tab (Notification_Center) and Notification_Center_Test
   * do not set it and are unaffected.
   *
   * ARC sets it, via c/arcNotificationCenter. Org-wide notification
   * configuration is administered from CRM, not from inside the advisor-facing
   * site, so the view is suppressed there for admins too — an admin browsing
   * ARC is using it as an advisor would.
   *
   * This suppresses, it does not grant: a non-admin can never reach the view
   * regardless of this flag. See showAdminSettings below, which both the nav
   * list and the navigation guard read, so hiding the item also closes the
   * direct-navigation route to it.
   */
  @api hideAdminSettings = false;

  /**
   * Lets the content area use the full width of the main panel.
   *
   * Off by default, so every surface that does not set it keeps the layout it
   * has always had: the inner column is capped by slds-container_large (1024px)
   * and centred, which is right for the CRM tab, where the Notification Center
   * sits inside Lightning's own page chrome.
   *
   * ARC sets it, via c/arcNotificationCenter. There the component is the whole
   * page, so the cap left roughly 230px of dead space on each side of the panel
   * and clipped the wider tables -- the Notification Log's Financial Advisor
   * column among them. Requested 2026-08-27.
   *
   * Only the cap and the centring are dropped; main-panel__inner keeps its
   * padding, so content never runs into the panel edge. The tables inside
   * already scroll horizontally within .div-table-scroll, so a table wider than
   * the panel still scrolls itself rather than stretching the page.
   */
  @api fullWidth = false;

  /**
   * View to open on instead of the dashboard, as a view id: "dashboard",
   * "notification-rules" or "notification-log".
   *
   * Applied once, in connectedCallback, so it seeds the starting view and then
   * gets out of the way -- navigating with the sidebar afterwards is never
   * overridden by the incoming value.
   *
   * ARC uses it to honour a ?view= query parameter, which is how the header
   * bell's "View All" lands straight on the Notification Log instead of making
   * the user arrive at the dashboard and click across. Requested 2026-08-27.
   *
   * Only BASE_NAV_ITEM_IDS are accepted. admin-settings is deliberately not
   * deep-linkable: whether it may be shown depends on isSystemAdministrator,
   * which arrives from a wire and is therefore still false at
   * connectedCallback, so honouring it here could not be gated correctly.
   * Refusing it keeps the guard in one place -- see showAdminSettings. An
   * unrecognised value is ignored and the dashboard opens as before.
   */
  @api initialView;

  connectedCallback() {
    this.applyInitialView();

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

  /**
   * Whether the Admin Settings view is available at all. Read by both the nav
   * list and handleNavigate, so the item cannot be hidden in one place and
   * still be reachable in the other.
   */
  /**
   * Classes for the inner content column. Built here rather than in the
   * template because the SLDS container cap has to come off as a pair --
   * dropping slds-container_large while leaving slds-container_center centres a
   * full-width block, which is a no-op that looks like a bug.
   */
  /**
   * Switches view from outside the component. Used when the page is already
   * open and something asks for a different view -- the header bell's
   * "View All", which cannot rely on navigation because navigating to the URL
   * already showing is a no-op and would not re-run connectedCallback.
   *
   * Returns true if the view changed, so a caller can tell "switched" from
   * "refused" rather than guessing.
   */
  @api
  showView(viewId) {
    return this.selectView(viewId);
  }

  /** Seeds activeView from initialView at mount. */
  applyInitialView() {
    this.selectView(this.initialView);
  }

  /**
   * The one place a view is chosen from outside handleNavigate. Silently
   * ignores anything that is not a base view id, so a stale ?view=, a
   * hand-edited URL or a bad event payload cannot blank the page or reach an
   * admin-only view.
   */
  selectView(viewId) {
    if (!viewId || viewId === this.activeView) {
      return false;
    }

    if (!BASE_NAV_ITEM_IDS.includes(viewId)) {
      return false;
    }

    this.activeView = viewId;
    this.isViewLoading = true;
    this.refreshActiveViewIfNeeded();

    return true;
  }

  get innerClass() {
    return this.fullWidth
      ? "main-panel__inner main-panel__inner_full"
      : "main-panel__inner slds-container_center slds-container_large";
  }

  get showAdminSettings() {
    return this.isSystemAdministrator && !this.hideAdminSettings;
  }

  get navItems() {
    const navItemIds = this.showAdminSettings
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

    if (!this.showAdminSettings && ADMIN_ONLY_VIEW_IDS.includes(viewId)) {
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