import { LightningElement } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import {
  readSidebarCollapsed,
  toggleSidebarCollapsed,
  isSidebarTransitioning,
  registerSidebarToggleKeyboardShortcut,
  SIDEBAR_COLLAPSE_CHANGE_EVENT,
  SIDEBAR_NAV_ANIMATION_MS,
} from "c/arcNavSidebarState";

/** Hoang Long Vu To — Aug 13, 2026 */
const SIDEBAR_COLLAPSE_ICON = "sidebar-collapse.svg";

/**
 * Toggle button that collapses the Arc sidebar navigation to an icon-only rail.
 */
export default class ArcNavigationButton extends LightningElement {
  collapsed = false;
  isBusy = false;

  connectedCallback() {
    this.collapsed = readSidebarCollapsed();
    registerSidebarToggleKeyboardShortcut();
    this._onSidebarCollapseChange = (event) => {
      this.collapsed = Boolean(event.detail?.collapsed);
    };
    window.addEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
  }

  disconnectedCallback() {
    window.removeEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    window.clearTimeout(this._busyUnlockId);
  }

  get iconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${SIDEBAR_COLLAPSE_ICON}');`;
  }

  get toggleLabel() {
    return this.collapsed
      ? "Expand sidebar navigation"
      : "Collapse sidebar navigation";
  }

  get tooltipLabel() {
    return this.collapsed ? "Open Sidebar" : "Close Sidebar";
  }

  get isToggleDisabled() {
    return this.isBusy;
  }

  handleToggleClick() {
    if (this.isBusy || isSidebarTransitioning()) {
      return;
    }

    this.isBusy = true;
    this.collapsed = toggleSidebarCollapsed();
    this._busyUnlockId = window.setTimeout(() => {
      this.isBusy = false;
      this._busyUnlockId = null;
    }, SIDEBAR_NAV_ANIMATION_MS);
  }

  handleToggleKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleToggleClick();
  }
}