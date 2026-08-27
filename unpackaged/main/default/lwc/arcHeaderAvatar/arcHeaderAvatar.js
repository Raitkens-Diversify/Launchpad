import { LightningElement, wire } from "lwc";
import basePath from "@salesforce/community/basePath";
import { getRecord } from "lightning/uiRecordApi";
import USER_ID from "@salesforce/user/Id";
import USER_FIRST_NAME from "@salesforce/schema/User.FirstName";
import USER_LAST_NAME from "@salesforce/schema/User.LastName";
import USER_USERNAME from "@salesforce/schema/User.Username";

/** Hostname fragment of the Experience Builder preview renderer. */
const PREVIEW_HOST = "live-preview.salesforce-experience.com";

/**
 * Logout on the preview host, without the site prefix.
 *
 * `${basePath}/secur/logout.jsp` returns the site's Invalid Page there, and the
 * prefix-less path is the one that host actually serves. It ignores retUrl and
 * lands on the Salesforce login screen, which is less tidy than the site's own
 * login page — but it genuinely ends the session, and that is the point.
 *
 * An earlier version sent preview to `${basePath}/login` instead, keeping the
 * session alive. That looked better and was wrong: the login page rendered while
 * the user was still signed in, so the nav in the header still worked and it
 * appeared that the app could be browsed without logging in.
 */
const PREVIEW_LOGOUT_PATH = "/secur/logout.jsp";

/**
 * Header avatar showing the running user's initials in a circle, per the
 * ARC1 header redesign spec.
 */
export default class ArcHeaderAvatar extends LightningElement {
  userFirstName = "";
  userLastName = "";
  username = "";
  isMenuOpen = false;
  isLogoutConfirmOpen = false;

  @wire(getRecord, {
    recordId: USER_ID,
    fields: [USER_FIRST_NAME, USER_LAST_NAME, USER_USERNAME]
  })
  wiredUser({ data, error }) {
    if (data) {
      this.userFirstName = data.fields.FirstName.value || "";
      this.userLastName = data.fields.LastName.value || "";
      this.username = data.fields.Username.value || "";
      return;
    }

    if (error) {
      // eslint-disable-next-line no-console
      console.error("[arcHeaderAvatar] Failed to load user record", error);
    }
  }

  get initials() {
    const first = this.userFirstName.trim().charAt(0);
    const last = this.userLastName.trim().charAt(0);
    return `${first}${last}`.toUpperCase() || "?";
  }

  get fullName() {
    return `${this.userFirstName} ${this.userLastName}`.trim();
  }

  get menuAriaLabel() {
    return this.fullName ? `Profile menu for ${this.fullName}` : "Profile menu";
  }

  handleToggleMenu() {
    this.isMenuOpen = !this.isMenuOpen;
  }

  handleCloseMenu() {
    this.isMenuOpen = false;
  }

  /**
   * Built from basePath rather than through comm__loginPage.
   *
   * comm__loginPage looks like the right abstraction and resolves to the same
   * secur/logout.jsp, but it builds the path from the Network's UrlPathPrefix,
   * which on this site is "NexSvforcesite" while the site is actually served
   * at /ARC — so it produced /NexSvforcesite/secur/logout.jsp and landed on the
   * site's Error page. basePath is the path the site is really served under.
   *
   * retUrl names where to land afterwards, so ending the session leaves the
   * user on the site's own login page instead of wherever the platform would
   * otherwise send them.
   */
  get loginPath() {
    return `${basePath}/login`;
  }

  /**
   * True on the Experience Builder preview renderer.
   *
   * That host serves the site's draft but not raw platform servlet paths:
   * `/ARC/secur/logout.jsp` returns the site's Invalid Page there while working
   * correctly on the published domain, so preview needs a different target —
   * see PREVIEW_LOGOUT_PATH.
   *
   * Worth knowing when testing: the preview host bounces unauthenticated
   * visitors to the Salesforce login, so guest-facing behaviour cannot be
   * observed there at all. Logging out in preview therefore also means leaving
   * Experience Builder, which is the honest cost of a real logout.
   */
  get isPreviewHost() {
    return window.location.hostname.includes(PREVIEW_HOST);
  }

  /**
   * "Log out" used to end the session immediately on click — one accidental
   * click on the wrong menu item and the user was signed out with nothing to
   * undo. It now opens a confirm dialog instead; only handleConfirmLogout
   * actually ends the session.
   */
  handleLogout() {
    this.isMenuOpen = false;
    this.isLogoutConfirmOpen = true;
  }

  handleCloseLogoutConfirm() {
    this.isLogoutConfirmOpen = false;
  }

  handleConfirmLogout() {
    this.isLogoutConfirmOpen = false;

    // Preview needs the site-prefix-less servlet — see isPreviewHost.
    if (this.isPreviewHost) {
      window.location.assign(PREVIEW_LOGOUT_PATH);
      return;
    }

    const retUrl = encodeURIComponent(this.loginPath);
    window.location.assign(`${basePath}/secur/logout.jsp?retUrl=${retUrl}`);
  }
}