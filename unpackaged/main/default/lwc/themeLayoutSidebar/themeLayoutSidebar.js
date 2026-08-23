import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import {
  readSidebarCollapsed,
  bootstrapSidebarCollapsedState,
  SIDEBAR_COLLAPSE_CHANGE_EVENT,
  SIDEBAR_COLLAPSED_WIDTH,
  SIDEBAR_LWR_EXPANDED_WIDTH,
} from "c/arcNavSidebarState";

/** Hoang Long Vu To — Aug 12, 2026 */

/**
 * Custom LWR theme layout with a persistent sidebar region alongside the
 * standard header/footer regions and the default main-content slot.
 *
 * @slot header
 * @slot sidebar
 * @slot footer
 */
export default class ThemeLayoutSidebar extends LightningElement {
  _collapsed = null;
  _pageRef;

  connectedCallback() {
    this.syncRuntimeShellClass();
    bootstrapSidebarCollapsedState();
    this.syncSidebarWidth(readSidebarCollapsed(), { force: true });
    this._onSidebarCollapseChange = (event) => {
      this.syncSidebarWidth(Boolean(event.detail?.collapsed));
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
  }

  @wire(CurrentPageReference)
  handlePageRef(pageRef) {
    this._pageRef = pageRef;
    this.syncRuntimeShellClass();
  }

  syncRuntimeShellClass() {
    const inDesignMode = isExperienceBuilderDesignMode(this._pageRef);
    this.classList.toggle("arc-runtime-shell", !inDesignMode);
    this.classList.toggle("arc-design-mode", inDesignMode);
  }

  syncSidebarWidth(isCollapsed, { force = false } = {}) {
    if (!force && this._collapsed === isCollapsed) {
      return;
    }

    this._collapsed = isCollapsed;

    const width = isCollapsed
      ? SIDEBAR_COLLAPSED_WIDTH
      : SIDEBAR_LWR_EXPANDED_WIDTH;

    this.style.setProperty("--arc-sidebar-width", width);
    this.classList.toggle("arc-sidebar-collapsed", isCollapsed);
  }
}

const isPreviewContext = (pageRef) => {
  if (pageRef?.state?.view === "preview") {
    return true;
  }

  try {
    const { hostname, search } = window.location;
    if (hostname.includes(".preview.")) {
      return true;
    }

    const params = new URLSearchParams(search);
    if (params.has("live-preview") || params.get("preview") === "true") {
      return true;
    }
  } catch {
    // ignore
  }

  try {
    if (pageRef?.state?.app === "commeditor" && window.self === window.top) {
      return true;
    }
  } catch {
    // ignore
  }

  return false;
};

const isExperienceBuilderDesignMode = (pageRef) => {
  if (isPreviewContext(pageRef)) {
    return false;
  }

  if (pageRef?.state?.app === "commeditor") {
    try {
      // Edit canvas is embedded in the builder iframe; preview opens top-level.
      return window.self !== window.top;
    } catch {
      return true;
    }
  }

  if (pageRef?.state?.app) {
    return false;
  }

  // pageRef not wired yet — infer from frame context until navigation resolves.
  try {
    return window.self !== window.top;
  } catch {
    return false;
  }
};