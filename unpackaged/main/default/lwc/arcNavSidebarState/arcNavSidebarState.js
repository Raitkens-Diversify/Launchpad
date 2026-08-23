/** Hoang Long Vu To — Aug 12, 2026 */

export const SIDEBAR_COLLAPSED_STORAGE_KEY = "arc-nav-sidebar-collapsed";
export const SIDEBAR_COLLAPSE_CHANGE_EVENT = "arc-nav-sidebar-collapse-change";
export const SIDEBAR_TRANSITION_MS = 220;
export const SIDEBAR_NAV_PHASE_MS = SIDEBAR_TRANSITION_MS;
export const SIDEBAR_NAV_ANIMATION_MS = SIDEBAR_NAV_PHASE_MS * 2;

const LWR_LAYOUT_SELECTOR = "c-theme-layout-sidebar";
export const SIDEBAR_COLLAPSED_WIDTH = "56px";
export const SIDEBAR_LWR_EXPANDED_WIDTH = "280px";
export const SIDEBAR_AURA_EXPANDED_WIDTH = "240px";

const COLLAPSED_WIDTH = SIDEBAR_COLLAPSED_WIDTH;
const LWR_EXPANDED_WIDTH = SIDEBAR_LWR_EXPANDED_WIDTH;
const AURA_EXPANDED_WIDTH = SIDEBAR_AURA_EXPANDED_WIDTH;

let isTransitioning = false;
let transitionUnlockId = null;
let keyboardShortcutRegistered = false;

const TYPING_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

const LIGHTNING_INPUT_TAGS = new Set([
  "LIGHTNING-INPUT",
  "LIGHTNING-TEXTAREA",
  "LIGHTNING-COMBOBOX",
  "LIGHTNING-INPUT-FIELD",
  "LIGHTNING-RADIO-GROUP",
  "LIGHTNING-CHECKBOX-GROUP",
  "LIGHTNING-DUAL-LISTBOX",
  "LIGHTNING-FILE-UPLOAD",
]);

function isApplePlatform() {
  if (typeof navigator === "undefined") {
    return true;
  }

  const platform =
    navigator.userAgentData?.platform || navigator.platform || "";

  return /Mac|iPhone|iPad|iPod/i.test(platform);
}

function isPeriodKey(event) {
  return (
    event.code === "Period" ||
    event.code === "NumpadDecimal" ||
    event.key === "." ||
    event.key === "Period"
  );
}

function isTypingInField(event) {
  const path =
    typeof event.composedPath === "function" ? event.composedPath() : [];

  const nodes = path.length
    ? path
    : [event.target, document.activeElement].filter(Boolean);

  return nodes.some((node) => {
    if (!node || node.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }

    const tag = (node.tagName || "").toUpperCase();

    return (
      TYPING_TAGS.has(tag) ||
      LIGHTNING_INPUT_TAGS.has(tag) ||
      node.isContentEditable
    );
  });
}

export function getSidebarToggleShortcutLabel() {
  return isApplePlatform() ? "⌘." : "Ctrl+.";
}

export function isSidebarToggleKeyboardEvent(event) {
  if (!event || event.altKey || event.shiftKey || !isPeriodKey(event)) {
    return false;
  }

  if (isApplePlatform()) {
    return event.metaKey && !event.ctrlKey;
  }

  // Win+. opens the Windows emoji panel, so Ctrl+. is used on other platforms.
  return event.ctrlKey && !event.metaKey;
}

const handleSidebarToggleKeyboard = (event) => {
  if (!isSidebarToggleKeyboardEvent(event) || isTypingInField(event)) {
    return;
  }

  event.preventDefault();
  event.stopPropagation();
  toggleSidebarCollapsed();
};

export function registerSidebarToggleKeyboardShortcut() {
  if (keyboardShortcutRegistered || typeof document === "undefined") {
    return;
  }

  keyboardShortcutRegistered = true;
  document.addEventListener("keydown", handleSidebarToggleKeyboard, true);
}

export function isSidebarTransitioning() {
  return isTransitioning;
}

export function readSidebarCollapsed() {
  try {
    const storedValue = sessionStorage.getItem(SIDEBAR_COLLAPSED_STORAGE_KEY);

    if (storedValue === null) {
      return false;
    }

    return storedValue === "true";
  } catch (error) {
    return false;
  }
}

export function writeSidebarCollapsed(isCollapsed) {
  const serializedValue = isCollapsed ? "true" : "false";

  try {
    sessionStorage.setItem(SIDEBAR_COLLAPSED_STORAGE_KEY, serializedValue);
  } catch (error) {
    // sessionStorage may be unavailable
  }
}

function resolveExpandedWidth() {
  if (typeof document === "undefined") {
    return LWR_EXPANDED_WIDTH;
  }

  return document.querySelector(LWR_LAYOUT_SELECTOR)
    ? LWR_EXPANDED_WIDTH
    : AURA_EXPANDED_WIDTH;
}

function resolveWidth(isCollapsed) {
  return isCollapsed ? COLLAPSED_WIDTH : resolveExpandedWidth();
}

function beginTransition() {
  if (transitionUnlockId) {
    window.clearTimeout(transitionUnlockId);
  }

  isTransitioning = true;
  transitionUnlockId = window.setTimeout(() => {
    isTransitioning = false;
    transitionUnlockId = null;
  }, SIDEBAR_NAV_ANIMATION_MS);
}

function applyAuraSidebarTargets(isCollapsed) {
  document.querySelectorAll(".sidebar").forEach((sidebar) => {
    sidebar.classList.toggle("sidebar--collapsed", isCollapsed);
  });
}

export function applyLwrThemeLayoutHosts(isCollapsed, width = resolveWidth(isCollapsed)) {
  if (typeof document === "undefined") {
    return;
  }

  document.querySelectorAll(LWR_LAYOUT_SELECTOR).forEach((layout) => {
    layout.style.setProperty("--arc-sidebar-width", width);
    layout.classList.toggle("arc-sidebar-collapsed", isCollapsed);
  });
}

export function applySidebarShellCollapsed(isCollapsed) {
  if (typeof document === "undefined") {
    return;
  }

  const root = document.documentElement;
  const width = resolveWidth(isCollapsed);

  if (isCollapsed) {
    root.dataset.arcSidebarCollapsed = "true";
  } else {
    delete root.dataset.arcSidebarCollapsed;
  }

  root.style.setProperty("--arc-sidebar-width", width);
  applyAuraSidebarTargets(isCollapsed);
  applyLwrThemeLayoutHosts(isCollapsed, width);
}

export function bootstrapSidebarCollapsedState() {
  const isCollapsed = readSidebarCollapsed();
  applySidebarShellCollapsed(isCollapsed);
  registerSidebarToggleKeyboardShortcut();
  return isCollapsed;
}

export function notifySidebarCollapsedChange(isCollapsed) {
  applySidebarShellCollapsed(isCollapsed);
  window.dispatchEvent(
    new CustomEvent(SIDEBAR_COLLAPSE_CHANGE_EVENT, {
      detail: { collapsed: isCollapsed },
    })
  );
}

export function toggleSidebarCollapsed() {
  if (isTransitioning) {
    return readSidebarCollapsed();
  }

  beginTransition();

  const nextCollapsed = !readSidebarCollapsed();
  writeSidebarCollapsed(nextCollapsed);
  notifySidebarCollapsedChange(nextCollapsed);
  return nextCollapsed;
}

export function syncSidebarCollapsedState(isCollapsed) {
  if (isTransitioning) {
    return;
  }

  writeSidebarCollapsed(isCollapsed);
  notifySidebarCollapsedChange(isCollapsed);
}