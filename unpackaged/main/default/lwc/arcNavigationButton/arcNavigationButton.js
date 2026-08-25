import { LightningElement } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import {
  readSidebarCollapsed,
  toggleSidebarCollapsed,
  isSidebarTransitioning,
  SIDEBAR_COLLAPSE_CHANGE_EVENT,
  SIDEBAR_TRANSITION_MS
} from "c/arcNavSidebarState";

/** Hoang Long Vu To — Aug 12, 2026 */
const SIDEBAR_COLLAPSE_ICON = "sidebar-collapse.svg";

/**
 * Toggle button that collapses the Arc sidebar navigation to an icon-only rail.
 */
export default class ArcNavigationButton extends LightningElement {
  collapsed = false;
  isBusy = false;

  connectedCallback() {
    this.collapsed = readSidebarCollapsed();
    this._onSidebarCollapseChange = (event) => {
      this.collapsed = Boolean(event.detail?.collapsed);
    };
    window.addEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    // ⌘. on Mac / Ctrl+. elsewhere — matches the shortcut hint shown on the
    // "Open Sidebar" tooltip in Figma.
    this._onShortcutKeyDown = (event) => {
      if (event.key !== "." || !(event.metaKey || event.ctrlKey)) {
        return;
      }
      event.preventDefault();
      this.handleToggleClick();
    };
    window.addEventListener("keydown", this._onShortcutKeyDown);
  }

  disconnectedCallback() {
    window.removeEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    window.removeEventListener("keydown", this._onShortcutKeyDown);
    window.clearTimeout(this._busyUnlockId);
  }

  get iconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${SIDEBAR_COLLAPSE_ICON}');`;
  }

  /**
   * Collapsed, this button sits directly above the rail's column of nav icons,
   * and the two have to line up. Expanded there is nothing beneath it to line
   * up with — the rail indents its icons further in — so the offset is only
   * applied while collapsed. The arithmetic is in the stylesheet.
   */
  get wrapperClass() {
    return this.collapsed
      ? "nav-toggle-wrapper nav-toggle-wrapper--rail-aligned"
      : "nav-toggle-wrapper";
  }

  get toggleLabel() {
    return this.collapsed
      ? "Expand sidebar navigation"
      : "Collapse sidebar navigation";
  }

  get tooltipLabel() {
    return this.collapsed ? "Open Sidebar" : "Collapse Sidebar";
  }

  get showShortcutHint() {
    return this.collapsed;
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
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._busyUnlockId = window.setTimeout(() => {
      this.isBusy = false;
      this._busyUnlockId = null;
    }, SIDEBAR_TRANSITION_MS);
  }

  handleToggleKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleToggleClick();
  }
}