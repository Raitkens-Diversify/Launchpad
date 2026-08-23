/**
 * Hoang Long Vu To — Aug 13, 2026
 *
 * Activates LWR Experience Cloud tabs from URL query params such as
 * ?c__tabId=tab1, ?tabId=tab1, ?c_tabName=Cases, or legacy ?c__tabName=Cases.
 * Name-based params match tabs by aria-label, label attribute, or visible label
 * text. Native tabs-* params take precedence over c_tabName / c__tabName.
 * Tablists live in LWR shadow DOM, so this component retries deep DOM queries
 * until the tablist is available.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import {
  syncNavParamsOnTabClick,
  resolveTabLabelFromElement,
} from "c/arcNavTrailState";

const NAV_PATH_CHANGE_EVENTS = ["arc-nav-pathchange", "nexs-nav-pathchange"];
const TAB_ID_PARAM_KEYS = ["c__tabId", "tabId"];
const TAB_NAME_PARAM_KEYS = ["c_tabName", "tabName", "c__tabName"];
const RETRY_DELAYS_MS = [0, 150, 400, 800, 1500, 2500];
const TAB_SELECTOR = '[role="tab"]';

export default class LwrTabUrlHandler extends LightningElement {
  pageRef;
  lastAppliedTabKey = "";
  trackedPathname = "";
  runGeneration = 0;

  connectedCallback() {
    this._onLocationChange = () => {
      this.scheduleTabNavigation();
    };
    this._onDocumentClick = (event) => {
      this.handleTabClick(event);
    };

    window.addEventListener("popstate", this._onLocationChange);
    NAV_PATH_CHANGE_EVENTS.forEach((eventName) => {
      window.addEventListener(eventName, this._onLocationChange);
    });
    document.addEventListener("click", this._onDocumentClick, true);
  }

  disconnectedCallback() {
    window.removeEventListener("popstate", this._onLocationChange);
    NAV_PATH_CHANGE_EVENTS.forEach((eventName) => {
      window.removeEventListener(eventName, this._onLocationChange);
    });
    document.removeEventListener("click", this._onDocumentClick, true);
    this.runGeneration += 1;
  }

  @wire(CurrentPageReference)
  handlePageChange(pageRef) {
    const nextPathname = resolvePagePathname(pageRef);

    if (nextPathname !== this.trackedPathname) {
      this.trackedPathname = nextPathname;
      this.lastAppliedTabKey = "";
    }

    this.pageRef = pageRef;
    this.scheduleTabNavigation();
  }

  scheduleTabNavigation() {
    this.runGeneration += 1;
    const generation = this.runGeneration;

    RETRY_DELAYS_MS.forEach((delay) => {
      window.setTimeout(() => {
        if (generation !== this.runGeneration) {
          return;
        }

        this.processTabNavigation();
      }, delay);
    });
  }

  handleTabClick(event) {
    const tab = event.target?.closest?.(TAB_SELECTOR);

    if (!tab) {
      return;
    }

    const tabName = resolveTabLabel(tab);

    if (!tabName) {
      return;
    }

    this.lastAppliedTabKey = `name:${normalizeTabName(tabName)}`;
    syncNavParamsOnTabClick(tabName);
  }

  processTabNavigation() {
    const tabTarget = resolveTabTarget(this.pageRef);

    if (!tabTarget.key) {
      this.lastAppliedTabKey = "";
      return;
    }

    if (tabTarget.key === this.lastAppliedTabKey) {
      return;
    }

    const matchingTab = findMatchingTab(tabTarget);

    if (matchingTab?.getAttribute("aria-selected") === "true") {
      this.lastAppliedTabKey = tabTarget.key;
      return;
    }

    if (activateTabByDom(tabTarget)) {
      this.lastAppliedTabKey = tabTarget.key;
    }
  }
}

function resolvePagePathname(pageRef) {
  const windowPath = normalizePath(window.location.pathname);

  if (windowPath) {
    return windowPath;
  }

  const pageRefPath =
    pageRef?.attributes?.urlPath ||
    pageRef?.attributes?.url ||
    pageRef?.state?.url ||
    pageRef?.state?.pathname;

  return normalizePath(pageRefPath);
}

function normalizePath(pathname) {
  if (!pathname) {
    return "";
  }

  return String(pathname).split("?")[0].replace(/\/+$/, "") || "/";
}

function resolveTabTarget(pageRef) {
  const urlParams = getUrlSearchParams();

  if (urlHasTabId(urlParams)) {
    const tabId = resolveTabIdFromParams(urlParams, pageRef?.state || {});

    if (tabId) {
      return {
        mode: "id",
        value: tabId,
        key: `id:${tabId}`,
      };
    }
  }

  if (urlHasTabName(urlParams)) {
    const tabName = resolveTabNameFromParams(urlParams);

    if (tabName) {
      return {
        mode: "name",
        value: tabName,
        key: `name:${normalizeTabName(tabName)}`,
      };
    }
  }

  const state = pageRef?.state || {};

  if (stateHasNativeTabsParam(state) || hasTabIdInState(state)) {
    const tabId = resolveTabIdFromParams(urlParams, state);

    if (tabId) {
      return {
        mode: "id",
        value: tabId,
        key: `id:${tabId}`,
      };
    }
  }

  const tabName = resolveTabName(pageRef);

  if (tabName) {
    return {
      mode: "name",
      value: tabName,
      key: `name:${normalizeTabName(tabName)}`,
    };
  }

  const tabId = resolveTabId(pageRef);

  if (tabId) {
    return {
      mode: "id",
      value: tabId,
      key: `id:${tabId}`,
    };
  }

  return {
    mode: "",
    value: "",
    key: "",
  };
}

function getUrlSearchParams() {
  return new URLSearchParams(window.location.search || "");
}

function urlHasNativeTabsParam(params) {
  return [...params.keys()].some((key) => key.startsWith("tabs-"));
}

function stateHasNativeTabsParam(state = {}) {
  return Object.keys(state).some((key) => key.startsWith("tabs-"));
}

function hasTabIdInState(state = {}) {
  return TAB_ID_PARAM_KEYS.some((key) => state[key]);
}

function urlHasTabName(params) {
  if (urlHasNativeTabsParam(params)) {
    return false;
  }

  return TAB_NAME_PARAM_KEYS.some((key) => params.has(key));
}

function urlHasTabId(params) {
  return (
    TAB_ID_PARAM_KEYS.some((key) => params.has(key)) ||
    [...params.keys()].some((key) => key.startsWith("tabs-"))
  );
}

function resolveTabNameFromParams(params) {
  for (const key of TAB_NAME_PARAM_KEYS) {
    const value = params.get(key);

    if (value) {
      return decodeTabParam(value);
    }
  }

  return "";
}

function resolveTabIdFromParams(params, state = {}) {
  for (const key of TAB_ID_PARAM_KEYS) {
    const value = params.get(key);

    if (value) {
      return String(value);
    }
  }

  for (const [key, value] of params.entries()) {
    if (key.startsWith("tabs-") && value) {
      return String(value);
    }
  }

  for (const [key, value] of Object.entries(state)) {
    if (key.startsWith("tabs-") && value) {
      return String(value);
    }
  }

  return "";
}

function resolveTabName(pageRef) {
  const urlParams = getUrlSearchParams();

  if (urlHasNativeTabsParam(urlParams)) {
    return "";
  }

  for (const key of TAB_NAME_PARAM_KEYS) {
    const urlValue = urlParams.get(key);

    if (urlValue) {
      return decodeTabParam(urlValue);
    }
  }

  const state = pageRef?.state || {};

  if (stateHasNativeTabsParam(state)) {
    return "";
  }

  for (const key of TAB_NAME_PARAM_KEYS) {
    const stateValue = state[key];

    if (stateValue) {
      return decodeTabParam(String(stateValue));
    }
  }

  return "";
}

function resolveTabId(pageRef) {
  const urlParams = getUrlSearchParams();
  const tabIdFromUrl = resolveTabIdFromParams(urlParams, pageRef?.state || {});

  if (tabIdFromUrl) {
    return tabIdFromUrl;
  }

  const state = pageRef?.state || {};

  for (const key of TAB_ID_PARAM_KEYS) {
    const stateValue = state[key];

    if (stateValue) {
      return String(stateValue);
    }
  }

  return "";
}

function decodeTabParam(value) {
  if (!value) {
    return "";
  }

  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

function normalizeTabName(value) {
  return String(value).trim().toLowerCase().replace(/\s+/g, " ");
}

function resolveTabLabel(button) {
  return resolveTabLabelFromElement(button);
}

function resolveTabLabelCandidates(button) {
  if (!button) {
    return [];
  }

  return [
    button.getAttribute("aria-label"),
    button.getAttribute("label"),
    button.getAttribute("title"),
    button.querySelector("label")?.textContent,
    button.textContent,
  ]
    .filter(Boolean)
    .map((value) => normalizeTabName(value));
}

function notifyPathChange() {
  NAV_PATH_CHANGE_EVENTS.forEach((eventName) => {
    window.dispatchEvent(new Event(eventName));
  });
}

function findMatchingTab(tabTarget) {
  const tabs = querySelectorAllDeep(TAB_SELECTOR);

  return tabs.find((button) => matchesTabTarget(button, tabTarget)) || null;
}

function activateTabByDom(tabTarget) {
  const tabLists = querySelectorAllDeep('[role="tablist"]');

  if (tabLists.length > 0) {
    for (const tabList of tabLists) {
      if (activateTabInList(tabList, tabTarget)) {
        return true;
      }
    }
  }

  const looseTabs = querySelectorAllDeep(TAB_SELECTOR);

  if (looseTabs.length === 0) {
    return false;
  }

  return clickMatchingTab(looseTabs, tabTarget);
}

function activateTabInList(tabList, tabTarget) {
  const tabs = [...tabList.querySelectorAll(TAB_SELECTOR)];

  if (tabs.length === 0) {
    const deepTabs = querySelectorAllDeep(TAB_SELECTOR, tabList);
    return clickMatchingTab(deepTabs, tabTarget);
  }

  return clickMatchingTab(tabs, tabTarget);
}

function clickMatchingTab(tabButtons, tabTarget) {
  let targetButton = null;

  for (const button of tabButtons) {
    if (matchesTabTarget(button, tabTarget)) {
      targetButton = button;
      break;
    }
  }

  if (!targetButton && tabTarget.mode === "id") {
    const tabIndex = parseTabIndex(tabTarget.value);

    if (!Number.isNaN(tabIndex) && tabButtons[tabIndex]) {
      targetButton = tabButtons[tabIndex];
    }
  }

  if (!targetButton) {
    return false;
  }

  if (targetButton.getAttribute("aria-selected") === "true") {
    return true;
  }

  targetButton.click();
  notifyPathChange();
  return true;
}

function matchesTabTarget(button, tabTarget) {
  if (tabTarget.mode === "name") {
    const normalizedTarget = normalizeTabName(tabTarget.value);
    const candidates = resolveTabLabelCandidates(button);

    return candidates.some((candidate) => candidate === normalizedTarget);
  }

  const normalizedTarget = String(tabTarget.value).toLowerCase();
  const candidates = [
    button.id,
    button.getAttribute("data-value"),
    button.getAttribute("value"),
    button.getAttribute("name"),
    button.getAttribute("aria-label"),
    button.getAttribute("label"),
    button.textContent,
  ]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase().replace(/\s+/g, ""));

  return candidates.some(
    (candidate) =>
      candidate === normalizedTarget ||
      candidate.includes(normalizedTarget) ||
      candidate.replace(/\s/g, "") === normalizedTarget
  );
}

function parseTabIndex(targetTabId) {
  const numericSuffix = String(targetTabId).replace(/^\D+/g, "");

  if (!numericSuffix) {
    return Number.NaN;
  }

  return parseInt(numericSuffix, 10) - 1;
}

function querySelectorAllDeep(selector, root = document) {
  const matches = [];

  function traverse(node) {
    if (!node) {
      return;
    }

    if (node.querySelectorAll) {
      node.querySelectorAll(selector).forEach((element) => {
        matches.push(element);
      });
    }

    if (node.shadowRoot) {
      traverse(node.shadowRoot);
    }

    const childNodes = node.children ? [...node.children] : [];

    childNodes.forEach((child) => {
      traverse(child);
    });
  }

  traverse(root);
  return matches;
}