/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Shared Arc sidebar navigation trail for LWR Experience sites. Stores the
 * active list/root segment when the user clicks sidebar nav or lands on a
 * matching route, so c-arc-breadcrumb can render the correct parent crumb.
 */
import communityBasePath from "@salesforce/community/basePath";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";

export const NAV_PATH_CHANGE_EVENT = "arc-nav-pathchange";
export const NAV_TRAIL_CHANGE_EVENT = "arc-nav-trail-change";
const NAV_TRAIL_STORAGE_KEY = "arc-nav-trail";
export const ARC_NAV_HOME_ID = "arc-nav-home";

const HOME_LABEL = "Home";
const ACCOUNT_LIST_PATH = "/account/Account/Default";
const WORK_LIST_PATH = "/case/Case/Default";
const ISA_LIST_PATH = "/financial-account/Financial_Account__c/Default";
export const HELP_SITE_PATH = "/help";
export const MANUAL_CONTACTS_GROUP_ID = "arc-nav-contacts";
export const MANUAL_WORK_GROUP_ID = "arc-nav-work";
export const MANUAL_ISA_GROUP_ID = "arc-nav-isas";
export const ARC_NAV_ALL_CONTACTS_ID = "arc-nav-all-contacts";

const ROUTE_OBJECT_API_NAMES = Object.freeze({
  account: "Account",
  case: "Case",
  envelope: "Envelope__c",
  task: "Task",
  work: "Work__c",
  "financial-account": "FinServ__FinancialAccount__c",
});

const ROUTE_STATE_IGNORED_KEYS = new Set([
  "app",
  "view",
  "experienceId",
  "language",
  "recordId",
  "url",
  "pathname",
]);

const TAB_ID_PARAM_KEYS = ["c__tabId", "tabId"];
const TAB_NAME_PARAM_KEYS = ["c_tabName", "tabName", "c__tabName"];
const NAV_PARENT_PARAM_KEYS = ["c_navParent", "navParent"];
const LEGACY_C_PARAM_PREFIX = "c__";
const TAB_SELECTOR = '[role="tab"]';

const buildTabNameTarget = (path, tabName, navParent) => {
  const params = new URLSearchParams();

  if (navParent) {
    params.set("c_navParent", navParent);
  }

  params.set("c_tabName", tabName);
  return `${path}?${params.toString()}`;
};

const MANUAL_CONTACTS_GROUP = {
  id: MANUAL_CONTACTS_GROUP_ID,
  label: "Contacts",
  type: "MenuLabel",
  target: null,
  icon: "contact.svg",
  isCollapsible: true,
  subMenu: [
    {
      id: ARC_NAV_ALL_CONTACTS_ID,
      label: "All Contacts",
      type: "InternalLink",
      target: buildTabNameTarget(ACCOUNT_LIST_PATH, "All Contacts", "Contacts"),
      objectApiName: "Account",
    },
    {
      id: "arc-nav-households",
      label: "Households",
      type: "InternalLink",
      target: buildTabNameTarget(ACCOUNT_LIST_PATH, "Households", "Contacts"),
      objectApiName: "Account",
    },
    {
      id: "arc-nav-clients",
      label: "Clients",
      type: "InternalLink",
      target: buildTabNameTarget(ACCOUNT_LIST_PATH, "Clients", "Contacts"),
      objectApiName: "Account",
    },
  ],
};

const MANUAL_WORK_GROUP = {
  id: MANUAL_WORK_GROUP_ID,
  label: "Work",
  type: "MenuLabel",
  target: null,
  icon: "work.svg",
  isCollapsible: true,
  objectApiName: "Case",
  subMenu: [
    {
      id: "arc-nav-work",
      label: "All Work",
      type: "InternalLink",
      target: buildTabNameTarget(WORK_LIST_PATH, "All Work", "Work"),
      objectApiName: "Case",
    },
    {
      id: "arc-nav-cases",
      label: "Cases",
      type: "InternalLink",
      target: buildTabNameTarget(WORK_LIST_PATH, "Cases", "Work"),
      objectApiName: "Case",
    },
    {
      id: "arc-nav-tasks",
      label: "Tasks",
      type: "InternalLink",
      target: buildTabNameTarget(WORK_LIST_PATH, "Tasks", "Work"),
      objectApiName: "Task",
    },
    {
      id: "arc-nav-advertising-request",
      label: "Advertising Request",
      type: "InternalLink",
      target: buildTabNameTarget(
        WORK_LIST_PATH,
        "Advertising Request",
        "Work"
      ),
      objectApiName: "Advertising_Item__c",
    },
    {
      id: "arc-nav-check-log",
      label: "Check Log",
      type: "InternalLink",
      target: buildTabNameTarget(WORK_LIST_PATH, "Check Log", "Work"),
      objectApiName: "Check_Log__c",
    },
  ],
};

const MANUAL_ISA_GROUP = {
  id: MANUAL_ISA_GROUP_ID,
  label: "Investments & Services",
  type: "MenuLabel",
  target: null,
  icon: "isa.svg",
  isCollapsible: true,
  objectApiName: "FinServ__FinancialAccount__c",
  subMenu: [
    {
      id: "arc-nav-isa-all",
      label: "All",
      type: "InternalLink",
      target: buildTabNameTarget(
        ISA_LIST_PATH,
        "All",
        "Investments & Services"
      ),
      objectApiName: "FinServ__FinancialAccount__c",
    },
    {
      id: "arc-nav-producs",
      label: "Products",
      type: "InternalLink",
      target: buildTabNameTarget(
        ISA_LIST_PATH,
        "Products",
        "Investments & Services"
      ),
      objectApiName: "FinServ__FinancialAccount__c",
    },
  ],
};

export const STATIC_NAV_ITEMS = [
  {
    id: ARC_NAV_HOME_ID,
    label: HOME_LABEL,
    type: "InternalLink",
    target: "/",
    icon: "home.svg",
    subMenu: [],
  },
  MANUAL_CONTACTS_GROUP,
  MANUAL_WORK_GROUP,
  MANUAL_ISA_GROUP,
  {
    id: "arc-nav-intelligence",
    label: "Intelligence",
    type: "InternalLink",
    target: "/intelligence",
    icon: "intelligence.svg",
    comingSoon: true,
    subMenu: [],
  },
  {
    id: "arc-nav-compliance",
    label: "Compliance",
    type: "InternalLink",
    target: "/compliance",
    icon: "compliance.svg",
    comingSoon: true,
    subMenu: [],
  },
  {
    id: "arc-nav-learning",
    label: "Learning",
    type: "ExternalLink",
    target: HELP_SITE_PATH,
    opensInNewTab: true,
    icon: "learning.svg",
    subMenu: [],
  },
];

const flattenNavItems = (items = STATIC_NAV_ITEMS) => {
  const flattened = [];

  items.forEach((item) => {
    if (item.type === "Divider") {
      return;
    }

    if (item.target) {
      flattened.push(item);
    }

    (item.subMenu || []).forEach((child) => {
      flattened.push(child);
    });
  });

  return flattened;
};

const NAV_TARGETS = flattenNavItems();

export function readNavTrail() {
  try {
    const raw = sessionStorage.getItem(NAV_TRAIL_STORAGE_KEY);

    if (!raw) {
      return null;
    }

    const parsed = JSON.parse(raw);

    if (!parsed?.label || !parsed?.path) {
      return null;
    }

    return parsed;
  } catch (error) {
    return null;
  }
}

function writeNavTrail(trail) {
  if (!trail?.label || !trail?.path) {
    return;
  }

  const nextTrail = {
    label: trail.label,
    path: trail.path,
    objectApiName: trail.objectApiName || "",
    navItemId: trail.navItemId || "",
  };

  const currentTrail = readNavTrail();

  if (
    currentTrail &&
    currentTrail.label === nextTrail.label &&
    currentTrail.path === nextTrail.path &&
    currentTrail.objectApiName === nextTrail.objectApiName &&
    currentTrail.navItemId === nextTrail.navItemId
  ) {
    return;
  }

  try {
    sessionStorage.setItem(NAV_TRAIL_STORAGE_KEY, JSON.stringify(nextTrail));
  } catch (error) {
    // sessionStorage may be unavailable
  }

  window.dispatchEvent(
    new CustomEvent(NAV_TRAIL_CHANGE_EVENT, {
      detail: { trail: nextTrail },
    })
  );
}

export function recordNavSelection({ id, label, path, objectApiName = "" }) {
  writeNavTrail({
    navItemId: id,
    label,
    path,
    objectApiName,
  });
}

export function findNavTargetById(navItemId) {
  if (!navItemId) {
    return null;
  }

  return NAV_TARGETS.find((item) => item.id === navItemId) || null;
}

function findActiveNavTarget(pathname, search, pageRef) {
  const currentPath = pathname || resolveCurrentPath(pageRef);
  const currentSearch = search || serializeSearch(resolveCurrentQueryParams(pageRef));

  let bestMatch = null;
  let bestScore = -1;

  NAV_TARGETS.forEach((item) => {
    if (!isItemActive(item, currentPath, currentSearch, pageRef)) {
      return;
    }

    const score = scoreNavTarget(item, currentPath, pageRef);

    if (score > bestScore) {
      bestScore = score;
      bestMatch = item;
    }
  });

  if (!bestMatch) {
    return null;
  }

  return toNavTrail(bestMatch);
}

export function syncNavTrailFromLocation(pathname, search, pageRef) {
  const activeTarget = findActiveNavTarget(pathname, search, pageRef);

  if (activeTarget) {
    writeNavTrail(activeTarget);
    return activeTarget;
  }

  return readNavTrail();
}

function toNavTrail(item) {
  return {
    navItemId: item.id,
    label: item.label,
    path: item.target,
    objectApiName: item.objectApiName || "",
  };
}

function scoreNavTarget(item, currentPath, pageRef) {
  let score = normalizeMenuTarget(item.target).length;

  if (item.target?.includes("?")) {
    score += 100;
  }

  if (isHomeItem(item)) {
    score -= 50;
  }

  if (resolveRecordIdFromPageReference(pageRef, item.objectApiName)) {
    score -= 10;
  }

  return score;
}

export function inferObjectApiNameFromPath(pathname) {
  const normalizedPath = stripSiteBase(normalizePath(pathname)).toLowerCase();
  const firstSegment = normalizedPath.split("/").filter(Boolean)[0];

  return ROUTE_OBJECT_API_NAMES[firstSegment] || "";
}

export function resolveCurrentPath(pageRef) {
  const windowPath = normalizePath(window.location.pathname);

  if (windowPath) {
    return windowPath;
  }

  const pageRefPath =
    pageRef?.attributes?.urlPath ||
    pageRef?.attributes?.url ||
    pageRef?.state?.url ||
    pageRef?.state?.pathname;

  if (pageRefPath) {
    return normalizePath(pageRefPath);
  }

  return "/";
}

export function resolveCurrentQueryParams(pageRef) {
  const params = new URLSearchParams(window.location.search || "");
  const state = pageRef?.state || {};
  const urlHasTabName = TAB_NAME_PARAM_KEYS.some((key) => params.has(key));
  const urlHasTabId =
    TAB_ID_PARAM_KEYS.some((key) => params.has(key)) ||
    urlHasNativeTabsParam(params);

  Object.entries(state).forEach(([key, value]) => {
    if (!isRoutableQueryParam(key, value) || params.has(key)) {
      return;
    }

    if (urlHasTabName && isLegacyTabParamKey(key)) {
      return;
    }

    if (urlHasTabId && isTabNameParamKey(key)) {
      return;
    }

    params.set(key, String(value));
  });

  if (TAB_NAME_PARAM_KEYS.some((key) => params.has(key))) {
    removeLegacyTabParams(params);
    return params;
  }

  if (
    TAB_ID_PARAM_KEYS.some((key) => params.has(key)) ||
    urlHasNativeTabsParam(params)
  ) {
    removeTabNameParams(params);
  }

  return params;
}

function urlHasNativeTabsParam(params) {
  return [...params.keys()].some((key) => key.startsWith("tabs-"));
}

function isLegacyTabParamKey(key) {
  return (
    key.startsWith(LEGACY_C_PARAM_PREFIX) ||
    TAB_ID_PARAM_KEYS.includes(key) ||
    key.startsWith("tabs-")
  );
}

function isTabNameParamKey(key) {
  return TAB_NAME_PARAM_KEYS.includes(key);
}

function removeLegacyTabParams(params) {
  const keysToRemove = [];

  params.forEach((_, key) => {
    if (isLegacyTabParamKey(key)) {
      keysToRemove.push(key);
    }
  });

  keysToRemove.forEach((key) => {
    params.delete(key);
  });

  params.delete("tabName");
}

function removeTabNameParams(params) {
  TAB_NAME_PARAM_KEYS.forEach((key) => {
    params.delete(key);
  });
}

export function serializeSearch(params) {
  const query = params.toString();
  return query ? `?${query}` : "";
}

function isRoutableQueryParam(key, value) {
  if (!key || value === null || value === undefined || value === "") {
    return false;
  }

  return !ROUTE_STATE_IGNORED_KEYS.has(key);
}

function isHomeItem(item) {
  if (!item?.label) {
    return false;
  }

  return item.label.trim().toLowerCase() === HOME_LABEL.toLowerCase();
}

export function isNavItemActive(item, currentPath, currentSearch, pageRef) {
  return isItemActive(item, currentPath, currentSearch, pageRef);
}

function isItemActive(item, currentPath, currentSearch, pageRef) {
  if (!item) {
    return false;
  }

  if (isHomeItem(item)) {
    return isOnSiteHomepage(currentPath);
  }

  if (item.target?.includes("?")) {
    return (
      isUrlMatch(item.target, currentPath, pageRef) ||
      isTrailItemActive(item, currentPath, pageRef)
    );
  }

  if (item.type === "SalesforceObject") {
    return (
      isSalesforceObjectPageActive(item, pageRef) ||
      isSalesforceObjectPathMatch(item.target, currentPath) ||
      isTrailItemActive(item, currentPath, pageRef)
    );
  }

  return (
    isPathMatch(item.target, currentPath) ||
    isTrailItemActive(item, currentPath, pageRef)
  );
}

function isTrailItemActive(item, currentPath, pageRef) {
  const trail = readNavTrail();

  if (!trail?.navItemId || trail.navItemId !== item.id) {
    return false;
  }

  const routeObjectApiName = inferObjectApiNameFromPath(currentPath);
  const itemObjectApiName = item.objectApiName || trail.objectApiName || "";

  if (!routeObjectApiName || !itemObjectApiName) {
    return false;
  }

  if (routeObjectApiName.toLowerCase() !== itemObjectApiName.toLowerCase()) {
    return false;
  }

  const recordId = resolveRecordIdFromPageReference(pageRef, itemObjectApiName);

  return Boolean(recordId);
}

function isUrlMatch(target, currentPath, pageRef) {
  const [targetPath, targetQuery = ""] = target.split("?");
  const pathMatches = isPathMatch(targetPath, currentPath);

  if (!pathMatches) {
    return false;
  }

  if (!targetQuery) {
    return true;
  }

  const targetParams = new URLSearchParams(targetQuery);
  const currentParams = resolveCurrentQueryParams(pageRef);
  const targetNavParent = resolveTargetNavParent(targetParams);
  const currentNavParent = resolveCurrentNavParent(currentParams, currentPath);

  if (targetNavParent) {
    if (
      !currentNavParent ||
      normalizeTabName(targetNavParent) !== normalizeTabName(currentNavParent)
    ) {
      return false;
    }
  }

  const targetTabName = resolveTargetTabName(targetParams);
  const currentTabName = resolveEffectiveTabName(currentParams);

  if (targetTabName) {
    if (!currentTabName) {
      return false;
    }

    return normalizeTabName(targetTabName) === normalizeTabName(currentTabName);
  }

  const targetTabId = resolveTargetTabId(targetParams);
  const currentTabId = resolveEffectiveTabId(currentParams);

  if (targetTabId === "tab1" && !currentTabId) {
    return true;
  }

  if (targetTabId) {
    return targetTabId === currentTabId;
  }

  for (const [key, value] of targetParams.entries()) {
    if (
      NAV_PARENT_PARAM_KEYS.includes(key) ||
      TAB_NAME_PARAM_KEYS.includes(key) ||
      TAB_ID_PARAM_KEYS.includes(key)
    ) {
      continue;
    }

    if (currentParams.get(key) !== value) {
      return false;
    }
  }

  return true;
}

function resolveTargetTabId(params) {
  return params.get("c__tabId") || params.get("tabId") || "";
}

function resolveTargetTabName(params) {
  return decodeTabParam(
    params.get("c_tabName") ||
      params.get("tabName") ||
      params.get("c__tabName") ||
      ""
  );
}

function resolveNavTabId(params) {
  for (const [key, value] of params.entries()) {
    if (key.startsWith("tabs-") && value) {
      return value;
    }
  }

  return params.get("c__tabId") || params.get("tabId") || "";
}

function resolveNavTabName(params) {
  return decodeTabParam(
    params.get("c_tabName") ||
      params.get("tabName") ||
      params.get("c__tabName") ||
      ""
  );
}

function parseTargetParams(target) {
  const queryIndex = target?.indexOf("?") ?? -1;

  if (queryIndex < 0) {
    return new URLSearchParams();
  }

  return new URLSearchParams(target.slice(queryIndex + 1));
}

export function resolveNavParent(params) {
  return resolveTargetNavParent(params);
}

function resolveTargetNavParent(params) {
  for (const key of NAV_PARENT_PARAM_KEYS) {
    const value = params.get(key);

    if (value) {
      return decodeTabParam(value);
    }
  }

  return "";
}

function resolveCurrentNavParent(params, currentPath) {
  const fromParams = resolveNavParent(params);

  if (fromParams) {
    return fromParams;
  }

  return inferNavParentFromPath(currentPath);
}

function inferNavParentFromPath(pathname) {
  if (isPathMatch(ACCOUNT_LIST_PATH, pathname)) {
    return MANUAL_CONTACTS_GROUP.label;
  }

  if (isPathMatch(WORK_LIST_PATH, pathname)) {
    return MANUAL_WORK_GROUP.label;
  }

  if (isPathMatch(ISA_LIST_PATH, pathname)) {
    return MANUAL_ISA_GROUP.label;
  }

  return "";
}

export function resolveTabLabelFromElement(button) {
  if (!button) {
    return "";
  }

  const candidates = [
    button.getAttribute("aria-label"),
    button.getAttribute("label"),
    button.getAttribute("title"),
    button.querySelector("label")?.textContent,
    button.textContent,
  ];

  for (const candidate of candidates) {
    const normalized = normalizeTabName(candidate);

    if (normalized) {
      return String(candidate).trim();
    }
  }

  return "";
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

export function resolveSelectedTabLabelFromDom() {
  const tabs = querySelectorAllDeep(TAB_SELECTOR);
  const selectedTab = tabs.find(
    (tab) => tab.getAttribute("aria-selected") === "true"
  );

  if (!selectedTab) {
    return "";
  }

  return resolveTabLabelFromElement(selectedTab);
}

export function findNavChildByParentAndLabel(navParentLabel, childLabel) {
  if (!navParentLabel || !childLabel) {
    return null;
  }

  const normalizedParent = normalizeTabName(navParentLabel);
  const normalizedChild = normalizeTabName(childLabel);

  for (const group of STATIC_NAV_ITEMS) {
    if (!group.subMenu?.length) {
      continue;
    }

    if (normalizeTabName(group.label) !== normalizedParent) {
      continue;
    }

    const child = group.subMenu.find((item) => {
      if (normalizeTabName(item.label) === normalizedChild) {
        return true;
      }

      if (!item.target) {
        return false;
      }

      const targetTabName = resolveTargetTabName(parseTargetParams(item.target));

      return normalizeTabName(targetTabName) === normalizedChild;
    });

    if (child) {
      return child;
    }
  }

  return null;
}

export function resolveEffectiveTabName(params) {
  const fromUrl = resolveNavTabName(params);

  if (fromUrl) {
    return fromUrl;
  }

  return resolveSelectedTabLabelFromDom();
}

export function resolveEffectiveTabId(params) {
  const fromUrl = resolveNavTabId(params);

  if (params.get("c__tabId") || params.get("tabId") || urlHasNativeTabsParam(params)) {
    if (fromUrl) {
      return fromUrl;
    }
  }

  const navParent =
    resolveNavParent(params) || inferNavParentFromPath(window.location.pathname);
  const tabLabel = resolveSelectedTabLabelFromDom();

  if (navParent && tabLabel) {
    const child = findNavChildByParentAndLabel(navParent, tabLabel);

    if (child?.target) {
      return resolveTargetTabId(parseTargetParams(child.target));
    }
  }

  return fromUrl;
}

export function syncNavParamsOnTabClick(tabLabel) {
  if (!tabLabel || typeof window === "undefined") {
    return;
  }

  const params = new URLSearchParams(window.location.search || "");
  let navParent = resolveNavParent(params);

  if (!navParent) {
    navParent = inferNavParentFromPath(window.location.pathname);
  }

  if (!navParent) {
    const trail = readNavTrail();

    if (trail?.navItemId) {
      const parentGroup = STATIC_NAV_ITEMS.find((item) =>
        (item.subMenu || []).some((child) => child.id === trail.navItemId)
      );

      navParent = parentGroup?.label || "";
    }
  }

  if (!navParent) {
    notifyNavPathChange();
    return;
  }

  params.set("c_navParent", navParent);

  const child = findNavChildByParentAndLabel(navParent, tabLabel);

  if (child?.target) {
    const childParams = parseTargetParams(child.target);
    const targetTabName = resolveTargetTabName(childParams);
    const targetTabId = resolveTargetTabId(childParams);

    if (targetTabName) {
      params.set("c_tabName", targetTabName);
    } else {
      removeTabNameParams(params);
    }

    if (targetTabId) {
      params.set("c__tabId", targetTabId);
      params.delete("tabId");
    }
  } else {
    params.set("c_tabName", tabLabel);
  }

  const nextSearch = params.toString();
  const nextUrl = `${window.location.pathname}${
    nextSearch ? `?${nextSearch}` : ""
  }${window.location.hash || ""}`;
  const currentUrl = `${window.location.pathname}${
    window.location.search || ""
  }${window.location.hash || ""}`;

  if (nextUrl !== currentUrl) {
    window.history.replaceState(window.history.state, {}, nextUrl);
  }

  notifyNavPathChange();
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

function resolveObjectApiNameFromPageRef(pageRef) {
  return pageRef?.attributes?.objectApiName || pageRef?.state?.objectApiName || "";
}

function isSalesforceObjectPageActive(item, pageRef) {
  if (item?.type !== "SalesforceObject" || !item?.target || !pageRef) {
    return false;
  }

  const pageObjectApiName = resolveObjectApiNameFromPageRef(pageRef);

  if (!pageObjectApiName) {
    return false;
  }

  return pageObjectApiName.toLowerCase() === item.target.toLowerCase();
}

function isSalesforceObjectPathMatch(objectApiName, currentPath) {
  if (!objectApiName || !currentPath) {
    return false;
  }

  const escapedObjectApiName = objectApiName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const objectPathPattern = new RegExp(
    `/[^/]+/${escapedObjectApiName}(/|$)`,
    "i"
  );

  return pathCandidates(currentPath).some((candidate) =>
    objectPathPattern.test(normalizePath(candidate))
  );
}

function isAccountListPath(currentPath) {
  const accountListPath = normalizePathForComparison(ACCOUNT_LIST_PATH);

  return pathCandidates(currentPath).some(
    (candidate) => normalizePathForComparison(candidate) === accountListPath
  );
}

function isOnSiteHomepage(currentPath) {
  if (isAccountListPath(currentPath)) {
    return false;
  }

  const normalizedPath = normalizePath(currentPath);

  if (!normalizedPath || normalizedPath === "/") {
    return true;
  }

  const siteBase = resolveSiteBasePath();

  if (siteBase && normalizedPath === siteBase) {
    return true;
  }

  const strippedPath = stripSiteBase(normalizedPath);
  return strippedPath === "/" || strippedPath === "";
}

function isPathMatch(target, currentPath) {
  if (!target || !currentPath) {
    return false;
  }

  const normalizedTarget = normalizePathForComparison(normalizeMenuTarget(target));

  if (normalizedTarget === "/") {
    return isOnSiteHomepage(currentPath);
  }

  const targetCandidates = new Set([
    normalizedTarget,
    normalizePathForComparison(normalizePath(target)),
    normalizePathForComparison(toSitePath(target)),
    normalizePathForComparison(stripSiteBase(normalizePath(target))),
  ]);

  return pathCandidates(currentPath).some((candidate) => {
    const normalizedCandidate = normalizePathForComparison(candidate);

    return [...targetCandidates].some((targetCandidate) => {
      if (!targetCandidate) {
        return false;
      }

      if (normalizedCandidate === targetCandidate) {
        return true;
      }

      return normalizedCandidate.startsWith(`${targetCandidate}/`);
    });
  });
}

function normalizePathForComparison(path) {
  return normalizeMenuTarget(path).toLowerCase();
}

function resolveSiteBasePath(path = window.location.pathname) {
  if (communityBasePath) {
    return normalizePath(communityBasePath);
  }

  if (globalThis?.LWR?.env?.basePath) {
    return normalizePath(globalThis.LWR.env.basePath);
  }

  const normalizedPath = normalizePath(path);
  const segments = normalizedPath.split("/").filter(Boolean);

  if (segments.length >= 1) {
    return `/${segments[0]}`;
  }

  return "";
}

function stripSiteBase(path) {
  const normalizedPath = normalizePath(path);
  const siteBase = resolveSiteBasePath();

  if (!siteBase) {
    return normalizedPath;
  }

  if (normalizedPath === siteBase) {
    return "/";
  }

  if (normalizedPath.startsWith(`${siteBase}/`)) {
    return normalizedPath.slice(siteBase.length) || "/";
  }

  return normalizedPath;
}

function toSitePath(path) {
  const normalizedPath = normalizePath(path);
  const siteBase = resolveSiteBasePath();

  if (!normalizedPath || normalizedPath === "/") {
    return siteBase || "/";
  }

  if (siteBase && normalizedPath.startsWith(siteBase)) {
    return normalizedPath;
  }

  const relativePath = normalizedPath.startsWith("/")
    ? normalizedPath
    : `/${normalizedPath}`;

  return siteBase ? `${siteBase}${relativePath}` : relativePath;
}

function normalizeMenuTarget(target) {
  const normalizedTarget = normalizePath(target);
  const withLeadingSlash = normalizedTarget.startsWith("/")
    ? normalizedTarget
    : `/${normalizedTarget}`;

  return stripSiteBase(withLeadingSlash);
}

function pathCandidates(path) {
  const normalizedPath = normalizePath(path);
  const strippedPath = stripSiteBase(normalizedPath);
  const siteBase = resolveSiteBasePath();
  const candidates = new Set();

  [normalizedPath, strippedPath].forEach((candidatePath) => {
    if (!candidatePath) {
      return;
    }

    candidates.add(candidatePath);

    const segments = candidatePath.split("/").filter(Boolean);
    for (let index = 1; index < segments.length; index += 1) {
      candidates.add(`/${segments.slice(index).join("/")}`);
    }
  });

  if (siteBase) {
    candidates.add(siteBase);

    [...candidates].forEach((candidatePath) => {
      if (!candidatePath || candidatePath === siteBase) {
        return;
      }

      if (candidatePath.startsWith("/")) {
        candidates.add(toSitePath(candidatePath));
      }
    });
  }

  return [...candidates];
}

function normalizePath(path) {
  if (!path) {
    return "";
  }

  try {
    if (path.startsWith("http")) {
      return new URL(path).pathname.replace(/\/$/, "") || "/";
    }
  } catch (error) {
    // fall through for relative paths
  }

  return path.replace(/\/$/, "") || "/";
}

export function notifyNavPathChange() {
  window.dispatchEvent(new Event(NAV_PATH_CHANGE_EVENT));
}

/**
 * @deprecated Do not monkey-patch history in LWR — Browser Locker rejects it.
 * Navigation sync uses CurrentPageReference, popstate, and notifyNavPathChange().
 */
export function patchHistoryForNavigation() {
  // Intentionally no-op.
}