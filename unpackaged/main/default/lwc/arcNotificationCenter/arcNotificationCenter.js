import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { resolveCurrentQueryParams } from "c/arcNavTrailState";
import { NOTIFICATION_VIEW_REQUEST_EVENT } from "c/notificationCenterUtils";

/**
 * arcNotificationCenter
 *
 * ARC's Notifications page. This is a host, not a feature: it places the shared
 * c/notificationCenter — the same component the CRM tab Notification_Center
 * renders — onto the ARC site's /notifications route, so the left nav's
 * Notifications item lands on the real Notification Center instead of ARC's own
 * older inbox (c/arcNotifications).
 *
 * WHY A WRAPPER AND NOT c:notificationCenter DIRECTLY. c/notificationCenter
 * already declares lightningCommunity__Page, so the view could point straight at
 * it. It is deliberately not pointed straight at it: that bundle is shared with
 * the CRM tab and with Notification_Center_Test, so anything ARC needs that CRM
 * does not — page framing, a guest/permission fallback, an error boundary, ARC
 * spacing — would otherwise have to be added to a component three surfaces
 * render. This host is where ARC-only concerns go, leaving the shared bundle and
 * every one of its Apex controllers untouched.
 *
 * ADMIN SETTINGS ARE HIDDEN HERE. The template passes hide-admin-settings, so
 * the shared component drops its Admin Settings nav item and refuses to
 * navigate to that view. Requested 2026-08-27: org-wide notification
 * configuration belongs in CRM, not in the advisor-facing site. The flag
 * defaults to false, so the CRM tab and Notification_Center_Test keep the
 * behaviour they had. It suppresses rather than grants — a non-admin still
 * cannot reach the view on any surface.
 *
 * NO APEX. Nothing here imports an Apex method. The data is fetched by
 * c/notificationCenter's own children (dashboard, log, rules, settings) through
 * NotificationCenterController, which already exposes getInbox,
 * getNotificationLog, getDashboard, getUnreadCount, markAsRead and
 * markAllAsRead. No Apex class, and no Apex test class, is modified by this
 * change.
 *
 * NO HEADING OF ITS OWN. c/notificationCenter draws its own app shell — an h1
 * reading "Notification Center" and its own sidebar for Dashboard/Log/Rules/
 * Settings. Adding an ARC <h1> above that would put two competing titles on one
 * page, so pageTitle below names the region for assistive technology instead of
 * rendering a second visible title.
 *
 * STYLES. c/notificationCenter is the sole loader of the diversifyStyles static
 * resource for the whole Notification Center tree and injects it itself, so this
 * host must not load it again — a second loadStyle would duplicate the rules.
 *
 * Reverting is a one-line change: point the ARC Notifications view's component
 * definition back at c:arcNotifications. That bundle is intentionally left in
 * place rather than deleted, so the old page stays available as a fallback.
 */
/**
 * ARC never shows the Notification Center's Admin Settings view. Org-wide
 * notification configuration is administered from CRM (the Notification_Center
 * tab), so it is suppressed here for System Administrators too — an admin
 * browsing ARC is using it as an advisor would. Requested 2026-08-27.
 *
 * Flip to false to give ARC the CRM behaviour back (admins see the view,
 * everyone else does not). Nothing else needs changing.
 *
 * Passed to the child as an expression rather than as a valueless
 * `hide-admin-settings` attribute: a bare attribute can reach the property as
 * the empty string, which is falsy, and the view would quietly stay visible.
 */
const HIDE_ADMIN_SETTINGS = true;

/**
 * ARC gives the Notification Center the full width of the page. In CRM the
 * component sits inside Lightning's page chrome and its 1024px centred column
 * is right; in ARC the component *is* the page, so that cap wasted about 230px
 * on each side and clipped the wider tables. Requested 2026-08-27.
 */
const FULL_WIDTH = true;

/**
 * Query parameter naming the Notification Center view to open on. The header
 * bell's "View All" sets it to "notification-log" so it lands on the log rather
 * than the dashboard. c/notificationCenter validates the value and ignores
 * anything it does not recognise, so nothing here needs to.
 */
const VIEW_PARAM = "view";

export default class ArcNotificationCenter extends LightningElement {
  /**
   * Accessible name for the page region. Kept as a design property so the page
   * stays configurable in Experience Builder the way c/arcNotifications was, and
   * so an existing pageTitle attribute on the view does not become dead config.
   * Not rendered as visible text — see the note above.
   */
  @api pageTitle = "Notifications";

  get regionLabel() {
    return this.pageTitle || "Notifications";
  }

  /** Real boolean for c/notificationCenter's hideAdminSettings property. */
  get hideAdminSettings() {
    return HIDE_ADMIN_SETTINGS;
  }

  /** Real boolean for c/notificationCenter's fullWidth property. */
  get fullWidth() {
    return FULL_WIDTH;
  }

  /**
   * The page reference is wired for LWR's client-side routing, where a
   * navigation can change the query string without a document load.
   * resolveCurrentQueryParams also reads window.location.search, so the
   * parameter is available synchronously on a cold load too -- which matters,
   * because c/notificationCenter reads initialView in its connectedCallback.
   */
  @wire(CurrentPageReference)
  pageRef;

  /** View id from ?view=, or undefined to let the dashboard open as normal. */
  get initialView() {
    return resolveCurrentQueryParams(this.pageRef).get(VIEW_PARAM) || undefined;
  }

  /**
   * Handles a view request that arrives while this page is already on screen —
   * the header bell's "View All". initialView cannot serve this case: the
   * center reads it in connectedCallback, which does not run again, and the
   * navigation that carries ?view= is a no-op when the URL is already current.
   *
   * The event is listened for on window because the bell lives in the site
   * header, in a separate component tree, and window CustomEvents are how ARC
   * already crosses that boundary (see NAV_PATH_CHANGE_EVENT,
   * SIDEBAR_COLLAPSE_CHANGE_EVENT).
   *
   * The center validates the view id and ignores anything it does not
   * recognise, so nothing is checked here.
   */
  connectedCallback() {
    this._onViewRequest = (event) => {
      const view = event?.detail?.view;

      if (!view) {
        return;
      }

      // Optional-chained: an event can land before the first render, and on the
      // way out after the child is gone.
      this.refs?.center?.showView?.(view);
    };

    window.addEventListener(
      NOTIFICATION_VIEW_REQUEST_EVENT,
      this._onViewRequest
    );
  }

  disconnectedCallback() {
    if (!this._onViewRequest) {
      return;
    }

    window.removeEventListener(
      NOTIFICATION_VIEW_REQUEST_EVENT,
      this._onViewRequest
    );
    this._onViewRequest = null;
  }
}