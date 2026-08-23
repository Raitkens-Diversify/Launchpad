/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 *
 * Settings gear menu for Experience Cloud with logout and reset password actions.
 * Logout follows LWR custom logout guidance:
 * https://developer.salesforce.com/docs/atlas.en-us.exp_cloud_lwr.meta/exp_cloud_lwr/advanced_custom_logout.htm
 */
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import isGuest from "@salesforce/user/isGuest";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import {
  HEADER_POPOVER_MENU_SETTING,
  isClickInsideHost,
  requestCloseHeaderPopover,
  requestOpenHeaderPopover,
  subscribeToHeaderPopover,
} from "c/arcHeaderPopoverCoordinator";

const GEAR_ICON = "gear.svg";
const DEFAULT_RESET_PASSWORD_PATH = "/reset-password";

const buildLogoutUrl = (basePath) => {
  const sitePrefix = (basePath || "").replace(/^\//, "").replace(/\/$/, "");

  if (!sitePrefix) {
    return "/secur/logout.jsp";
  }

  return `/${sitePrefix}/secur/logout.jsp`;
};

const buildSiteRelativeUrl = (basePath, configuredPath) => {
  const normalizedPath = configuredPath.startsWith("/")
    ? configuredPath
    : `/${configuredPath}`;
  const normalizedBasePath = (basePath || "").replace(/\/$/, "");

  return `${normalizedBasePath}${normalizedPath}`;
};

export default class ArcMenuSetting extends NavigationMixin(LightningElement) {
  /** Site-relative path for the Reset Password action (e.g. /reset-password). */
  @api resetPasswordPath = DEFAULT_RESET_PASSWORD_PATH;

  isMenuOpen = false;
  _stylesLoaded = false;
  _outsideClickHandler = null;
  _outsideClickTimeoutId = null;
  _unsubscribeHeaderPopover = null;

  connectedCallback() {
    if (isGuest) {
      return;
    }

    this._unsubscribeHeaderPopover = subscribeToHeaderPopover((activePopoverId) => {
      if (activePopoverId !== HEADER_POPOVER_MENU_SETTING && this.isMenuOpen) {
        this.closeMenu(false);
      }
    });

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
      if (!this.isMenuOpen) {
        return;
      }

      if (isClickInsideHost(event, this.template.host)) {
        return;
      }

      this.closeMenu();
    };

    // Defer so the opening click does not immediately close the menu.
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
    return `--icon-url: url('${NEXS_ICONS}/${GEAR_ICON}');`;
  }

  get triggerButtonClass() {
    const classes = ["menu-setting__trigger", "div-btn", "div-btn--icon"];

    if (this.isMenuOpen) {
      classes.push("menu-setting__trigger_active", "div-btn--active");
    }

    return classes.join(" ");
  }

  get menuId() {
    return "arc-menu-setting-panel";
  }

  get logoutUrl() {
    return buildLogoutUrl(communityBasePath);
  }

  get resetPasswordUrl() {
    const configuredPath = (this.resetPasswordPath || DEFAULT_RESET_PASSWORD_PATH).trim();

    return buildSiteRelativeUrl(communityBasePath, configuredPath);
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
        console.error("[arcMenuSetting] Failed to load diversifyStyles", error);
      });
  }

  handleTriggerClick(event) {
    event.stopPropagation();

    if (this.isMenuOpen) {
      this.closeMenu();
      return;
    }

    this.openMenu();
  }

  handleTriggerKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    if (this.isMenuOpen) {
      this.closeMenu();
      return;
    }

    this.openMenu();
  }

  openMenu() {
    requestOpenHeaderPopover(HEADER_POPOVER_MENU_SETTING);
    this.isMenuOpen = true;
    this._bindOutsideClickListener();
  }

  closeMenu(shouldNotifyCoordinator = true) {
    if (!this.isMenuOpen) {
      return;
    }

    this.isMenuOpen = false;
    this._unbindOutsideClickListener();

    if (shouldNotifyCoordinator) {
      requestCloseHeaderPopover(HEADER_POPOVER_MENU_SETTING);
    }
  }

  handleResetPasswordClick(event) {
    event.preventDefault();
    this.closeMenu();
    this.navigateToUrl(this.resetPasswordUrl);
  }

  handleResetPasswordKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleResetPasswordClick(event);
  }

  handleLogoutClick(event) {
    event.preventDefault();
    event.stopPropagation();
    this.closeMenu();
    window.location.assign(this.logoutUrl);
  }

  handleLogoutKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleLogoutClick(event);
  }

  navigateToUrl(url) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url },
    });
  }
}