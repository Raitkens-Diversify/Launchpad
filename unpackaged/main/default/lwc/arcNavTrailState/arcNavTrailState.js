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
export const NAV_TRAIL_STORAGE_KEY = "arc-nav-trail";
export const UPGRADE_REQUESTED_EVENT = "arc-upgrade-requested";

const HOME_LABEL = "Home";
const ACCOUNT_LIST_PATH = "/account/Account/Default";
const WORK_LIST_PATH = "/case/Case/Default";
const TASK_LIST_PATH = "/task/Task/Default";
const CHECK_LOG_LIST_PATH = "/check-log/Check_Log__c/Default";
const ISA_LIST_PATH = "/financial-account/Financial_Account__c/Default";
const SERVICE_LIST_PATH = "/service/Service__c/Default";
const APPROVED_PRODUCTS_LIST_PATH = "/product/Product__c/Default";
/* Its own page rather than a tab on Cases: the advertising reviews are Cases,
   but nobody reaches them by browsing Cases — they come at it from Compliance. */
const ADVERTISING_REVIEWS_PATH = "/advertising-reviews";
export const UAT_TESTING_PATH = "/uat-testing";
export const MANUAL_CONTACTS_GROUP_ID = "arc-nav-contacts";

// Matches all three domains this sandbox is actually reached on --
// arc-launchpad.diversify.com, and the two default
// dfpginvestments--launchpad.sandbox.my.{site,salesforce-sites}.com hosts --
// without also matching arc.diversify.com, which this same org has
// registered too but isn't one of the domains UAT testing runs on (and reads
// like a placeholder for the eventual production domain, which must never
// match this check).
const LAUNCHPAD_HOSTNAME_MARKER = "launchpad";

/**
 * True only on the Launchpad sandbox's site domains. UAT Testing links to an
 * internal tester tool that only ever exists there -- gating on hostname
 * (same technique arcHeaderAvatar/themeLayoutSidebar/egnyteVfEmbed already
 * use for environment checks) keeps it out of every other org's nav without
 * needing a server round trip just to decide whether to show a nav entry.
 */
export const isLaunchpadEnvironment = () =>
  typeof window !== "undefined" &&
  window.location.hostname.toLowerCase().includes(LAUNCHPAD_HOSTNAME_MARKER);

const ROUTE_OBJECT_API_NAMES = Object.freeze({
  account: "Account",
  case: "Case",
  task: "Task",
  "check-log": "Check_Log__c",
  "financial-account": "FinServ__FinancialAccount__c",
  service: "Service__c",
  product: "Product__c"
});

const ROUTE_STATE_IGNORED_KEYS = new Set([
  "app",
  "view",
  "experienceId",
  "language",
  "recordId",
  "url",
  "pathname"
]);

/*
 * `hidden: true` keeps an entry defined but off the rail. Used for the Contacts
 * children that have nowhere to go yet — they were rendering as dead links.
 * Kept rather than deleted so restoring one is a single flag, and so the
 * intended information architecture stays visible in this file.
 */
const MANUAL_CONTACTS_GROUP = {
  id: MANUAL_CONTACTS_GROUP_ID,
  label: "Contacts",
  type: "MenuLabel",
  target: null,
  icon: "contact.svg",
  isCollapsible: true,
  subMenu: [
    /*
     * One entry per tab on the Account list page, in that page's own order —
     * c__tabId is positional, so a mismatch does not fail, it quietly sends
     * the wrong link to the wrong list. Keep this in step with the viewTabs
     * attribute on the Account_List page in Experience Builder.
     */
    {
      id: "arc-nav-all-contacts",
      label: "All Contacts",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab1`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-individuals",
      label: "Individuals",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab2`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-clients",
      label: "Clients",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab3`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-households",
      label: "Households",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab4`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-businesses",
      label: "Businesses",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab5`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-retirement-plans",
      label: "Retirement Plans",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab6`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-trusts-estates",
      label: "Trusts & Estates",
      type: "InternalLink",
      target: `${ACCOUNT_LIST_PATH}?c__tabId=tab7`,
      objectApiName: "Account"
    },
    {
      id: "arc-nav-related-parties",
      label: "Related Parties",
      type: "Placeholder",
      target: null,
      hidden: true
    },
    {
      id: "arc-nav-prospects",
      label: "Prospects",
      type: "Placeholder",
      target: null,
      hidden: true
    },
    {
      id: "arc-nav-leads",
      label: "Leads",
      type: "Placeholder",
      target: null,
      hidden: true
    },
    {
      id: "arc-nav-cois",
      label: "COIs",
      type: "Placeholder",
      target: null,
      hidden: true
    },
    {
      id: "arc-nav-vendors",
      label: "Vendors",
      type: "Placeholder",
      target: null,
      hidden: true
    }
  ]
};

export const STATIC_NAV_ITEMS = [
  {
    id: "arc-nav-home",
    label: HOME_LABEL,
    type: "InternalLink",
    target: "/",
    icon: "home.svg",
    subMenu: []
  },
  MANUAL_CONTACTS_GROUP,
  {
    id: "arc-nav-work",
    label: "Work",
    type: "InternalLink",
    target: WORK_LIST_PATH,
    icon: "work.svg",
    objectApiName: "Case",
    isCollapsible: true,
    subMenu: [
      {
        id: "arc-nav-work-cases",
        label: "Cases",
        type: "InternalLink",
        target: WORK_LIST_PATH,
        objectApiName: "Case"
      },
      {
        id: "arc-nav-work-tasks",
        label: "Tasks",
        type: "InternalLink",
        target: TASK_LIST_PATH,
        objectApiName: "Task"
      },
      {
        id: "arc-nav-work-check-log",
        label: "Check Log",
        type: "InternalLink",
        target: CHECK_LOG_LIST_PATH,
        objectApiName: "Check_Log__c"
      },
      {
        id: "arc-nav-work-cadences",
        label: "Cadences",
        type: "Placeholder",
        target: null,
        // Nothing in the org backs this yet: Sales Engagement is off, so
        // there is no ActionCadence, and no Cadence__c exists. Every
        // "cadence" in Apex is the word meaning frequency
        // (Review_Cadence__c, the digest scheduler's hourly/daily/weekly).
        // Hidden rather than left as a dead link until it has a home.
        hidden: true
      }
    ]
  },
  {
    id: "arc-nav-isas",
    label: "Investments & Services",
    type: "InternalLink",
    target: ISA_LIST_PATH,
    icon: "isa.svg",
    objectApiName: "FinServ__FinancialAccount__c",
    isCollapsible: true,
    subMenu: [
      /*
       * Each a standalone page/route now, not a shared tabset -- DFPG_
       * Financial_Account_List, Service_List, and Product_List are each
       * flat single-purpose pages (same "own page, not a builder tab"
       * pattern as Task_List/Check_Log_List under Work). DPIs was removed
       * entirely (nav + tab) rather than given its own page.
       */
      {
        id: "arc-nav-isas-accounts",
        label: "Accounts",
        type: "InternalLink",
        target: ISA_LIST_PATH,
        objectApiName: "FinServ__FinancialAccount__c"
      },
      {
        id: "arc-nav-isas-services",
        label: "Services",
        type: "InternalLink",
        target: SERVICE_LIST_PATH,
        objectApiName: "Service__c"
      },
      {
        id: "arc-nav-isas-approved-products",
        label: "Approved Products",
        type: "InternalLink",
        target: APPROVED_PRODUCTS_LIST_PATH,
        objectApiName: "Product__c"
      }
    ]
  },
  {
    id: "arc-nav-compliance",
    label: "Compliance",
    type: "InternalLink",
    target: ADVERTISING_REVIEWS_PATH,
    icon: "compliance.svg",
    isCollapsible: true,
    subMenu: [
      {
        id: "arc-nav-compliance-advertising-reviews",
        label: "Advertising Reviews",
        type: "InternalLink",
        target: ADVERTISING_REVIEWS_PATH,
        objectApiName: "Case"
      }
    ]
  },
  {
    id: "arc-nav-learning",
    label: "Resource",
    type: "InternalLink",
    target: "/learning",
    icon: "learning.svg"
  },
  {
    id: "arc-nav-notifications",
    label: "Notifications",
    type: "InternalLink",
    target: "/notifications",
    icon: "bell.svg"
  }
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

    /*
     * Breadcrumbs need a 3rd, top-level "group" segment (e.g. "Work" above
     * "Cases"), which the flat list otherwise loses once children are
     * spread in alongside their parent. Every labelled group tags its
     * children, including the Contacts MenuLabel: it used to be skipped for
     * having no target of its own, so an account read "All Contacts › Reyes"
     * while a case read "Work › Cases › …". The crumb links to the group's
     * own target when it has one ("Work" → the Cases list) and otherwise to
     * its first visible child ("Contacts" → All Contacts), so it is never
     * dead text.
     */
    const groupPath = resolveGroupPath(item);

    (item.subMenu || []).forEach((child) => {
      flattened.push(
        item.label ? { ...child, groupLabel: item.label, groupPath } : child
      );
    });
  });

  return flattened;
};

function resolveGroupPath(item) {
  if (item.target) {
    return item.target;
  }

  const firstNavigableChild = (item.subMenu || []).find(
    (child) => child.target && !child.hidden
  );

  return firstNavigableChild?.target || "";
}

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
  } catch {
    return null;
  }
}

export function writeNavTrail(trail) {
  if (!trail?.label || !trail?.path) {
    return;
  }

  const nextTrail = {
    label: trail.label,
    path: trail.path,
    objectApiName: trail.objectApiName || "",
    navItemId: trail.navItemId || "",
    groupLabel: trail.groupLabel || "",
    groupPath: trail.groupPath || ""
  };

  const currentTrail = readNavTrail();

  if (
    currentTrail &&
    currentTrail.label === nextTrail.label &&
    currentTrail.path === nextTrail.path &&
    currentTrail.objectApiName === nextTrail.objectApiName &&
    currentTrail.navItemId === nextTrail.navItemId &&
    currentTrail.groupLabel === nextTrail.groupLabel &&
    currentTrail.groupPath === nextTrail.groupPath
  ) {
    return;
  }

  try {
    sessionStorage.setItem(NAV_TRAIL_STORAGE_KEY, JSON.stringify(nextTrail));
  } catch {
    // sessionStorage may be unavailable
  }

  window.dispatchEvent(
    new CustomEvent(NAV_TRAIL_CHANGE_EVENT, {
      detail: { trail: nextTrail }
    })
  );
}

export function recordNavSelection({
  id,
  label,
  path,
  objectApiName = "",
  groupLabel = "",
  groupPath = ""
}) {
  writeNavTrail({
    navItemId: id,
    label,
    path,
    objectApiName,
    groupLabel,
    groupPath
  });
}

export function findNavTargetById(navItemId) {
  if (!navItemId) {
    return null;
  }

  return NAV_TARGETS.find((item) => item.id === navItemId) || null;
}

export function findActiveNavTarget(pathname, search, pageRef) {
  const currentPath = pathname || resolveCurrentPath(pageRef);
  const currentSearch =
    search || serializeSearch(resolveCurrentQueryParams(pageRef));

  let bestMatch = null;
  let bestScore = -1;

  NAV_TARGETS.forEach((item) => {
    if (!isItemActive(item, currentPath, currentSearch, pageRef)) {
      return;
    }

    const score = scoreNavTarget(item, currentPath, currentSearch, pageRef);

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

  const recordId = resolveRecordIdFromPageReference(
    pageRef,
    inferObjectApiNameFromPath(pathname)
  );
  const routeObjectApiName = inferObjectApiNameFromPath(pathname);

  if (!recordId || !routeObjectApiName) {
    return readNavTrail();
  }

  const existingTrail = readNavTrail();

  if (existingTrail?.objectApiName === routeObjectApiName) {
    return existingTrail;
  }

  const fallbackTarget = findDefaultListTrail(routeObjectApiName);

  if (fallbackTarget) {
    writeNavTrail(fallbackTarget);
    return fallbackTarget;
  }

  return existingTrail;
}

/**
 * True when a route is neither a sidebar destination nor a record page, so no
 * stored trail describes it.
 *
 * syncNavTrailFromLocation hands back the trail as it stands for these routes,
 * which is right for keeping a selection across a record view but wrong for the
 * breadcrumb: Settings sits behind the gear icon rather than in the sidebar, so
 * opening it from a case left the crumb reading "Work > Cases" over a page that
 * is under neither. Callers that describe the current location use this to show
 * nothing instead of something stale.
 */
export function isOffNavRoute(pathname, search, pageRef) {
  if (findActiveNavTarget(pathname, search, pageRef)) {
    return false;
  }

  const objectApiName = inferObjectApiNameFromPath(pathname);
  const recordId = resolveRecordIdFromPageReference(pageRef, objectApiName);

  return !recordId || !objectApiName;
}

function toNavTrail(item) {
  return {
    navItemId: item.id,
    label: item.label,
    path: item.target,
    objectApiName: item.objectApiName || "",
    groupLabel: item.groupLabel || "",
    groupPath: item.groupPath || ""
  };
}

/**
 * The nav entry that owns an object's list.
 *
 * A child entry wins over the group it hangs under. "Work" is a group whose
 * first child is "Cases", and both carry objectApiName Case and the same
 * target — so a plain first-match returned the group, and a case's trail read
 * "Work" where it should read "Work › Cases". Preferring the child also keeps
 * the group as its own crumb, because a child carries groupLabel and a group
 * does not.
 */
export function findDefaultListTrail(objectApiName) {
  const normalizedObjectApiName = (objectApiName || "").toLowerCase();
  const matches = NAV_TARGETS.filter(
    (item) =>
      (item.objectApiName || "").toLowerCase() === normalizedObjectApiName
  );

  const match = matches.find((item) => item.groupLabel) || matches[0];

  return match ? toNavTrail(match) : null;
}

function scoreNavTarget(item, currentPath, currentSearch, pageRef) {
  let score = normalizeMenuTarget(item.target).length;

  if (item.target?.includes("?")) {
    score += 100;
  }

  /*
   * A child beats the group it sits under when both point at the same place.
   * "Work" and its "Cases" child share /case/Case/Default and so score
   * identically on length alone, and the group — listed first — won, which is
   * why a case read "Work" rather than "Work › Cases".
   */
  if (item.groupLabel) {
    score += 1;
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

  Object.entries(state).forEach(([key, value]) => {
    if (!isRoutableQueryParam(key, value)) {
      return;
    }

    if (params.has(key)) {
      return;
    }

    params.set(key, String(value));
  });

  return params;
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
    return isUrlMatch(item.target, currentPath, pageRef);
  }

  if (item.type === "SalesforceObject") {
    return (
      isSalesforceObjectPageActive(item, pageRef) ||
      isSalesforceObjectPathMatch(item.target, currentPath)
    );
  }

  return isPathMatch(item.target, currentPath);
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
  const targetTabId = resolveTargetTabId(targetParams);
  const currentTabId = resolveNavTabId(currentParams);

  if (targetTabId === "tab1" && !currentTabId) {
    return true;
  }

  if (targetTabId) {
    return targetTabId === currentTabId;
  }

  for (const [key, value] of targetParams.entries()) {
    if (currentParams.get(key) !== value) {
      return false;
    }
  }

  return true;
}

function resolveTargetTabId(params) {
  return params.get("c__tabId") || params.get("tabId") || "";
}

function resolveNavTabId(params) {
  for (const [key, value] of params.entries()) {
    if (key.startsWith("tabs-") && value) {
      return value;
    }
  }

  return params.get("c__tabId") || params.get("tabId") || "";
}

function resolveObjectApiNameFromPageRef(pageRef) {
  return (
    pageRef?.attributes?.objectApiName || pageRef?.state?.objectApiName || ""
  );
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

  const escapedObjectApiName = objectApiName.replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&"
  );
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

  const normalizedTarget = normalizePathForComparison(
    normalizeMenuTarget(target)
  );

  if (normalizedTarget === "/") {
    return isOnSiteHomepage(currentPath);
  }

  const targetCandidates = new Set([
    normalizedTarget,
    normalizePathForComparison(normalizePath(target)),
    normalizePathForComparison(toSitePath(target)),
    normalizePathForComparison(stripSiteBase(normalizePath(target)))
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

function resolveSiteBasePath() {
  if (communityBasePath) {
    return normalizePath(communityBasePath);
  }

  if (globalThis?.LWR?.env?.basePath) {
    return normalizePath(globalThis.LWR.env.basePath);
  }

  /*
   * No configured prefix means the site is root-mapped (the published
   * custom domain) and the base path is simply "". Guessing it from the
   * first path segment instead treated "/case" as the site base on
   * /case/{id}/{slug}: stripSiteBase then ate the route segment,
   * inferObjectApiNameFromPath returned "", and isOffNavRoute hid the
   * breadcrumb on every record page — only on the published domain, since
   * the /ARC-prefixed hosts get a real communityBasePath. Same reasoning
   * as resolveCommunityBasePath in c/recordNavigationCommunityUtils.
   */
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
  } catch {
    // fall through for relative paths
  }

  return path.replace(/\/$/, "") || "/";
}

/**
 * Best available label for a builder-tabset tab button -- aria-label, then
 * the `label` attribute, then title, then a nested <label>, then the
 * button's own text. Used by lwrTabUrlHandler to identify which tab a click
 * landed on; raw (un-normalized) so it round-trips cleanly through a URL
 * param and back through resolveTabTarget's own name-matching, which
 * normalizes on both sides.
 */
export function resolveTabLabelFromElement(button) {
  if (!button) {
    return "";
  }

  const candidates = [
    button.getAttribute("aria-label"),
    button.getAttribute("label"),
    button.getAttribute("title"),
    button.querySelector("label")?.textContent,
    button.textContent
  ]
    .map((value) => (value || "").trim())
    .filter(Boolean);

  return candidates[0] || "";
}

/**
 * Writes the clicked builder tab's label into the URL as a name-based
 * ?c__tabName= param, so a reload or a shared link reopens the same tab --
 * lwrTabUrlHandler's own processTabNavigation already knows how to read
 * this param back on load (see resolveTabTarget/urlHasTabName). Clears any
 * stale id-based param first: resolveTabTarget checks id-mode before
 * name-mode, so a leftover ?c__tabId= from an earlier nav-driven visit
 * would otherwise silently win over the tab the user just actually clicked.
 */
export function syncNavParamsOnTabClick(tabName) {
  if (typeof window === "undefined" || !tabName) {
    return;
  }

  const url = new URL(window.location.href);

  if (url.searchParams.get("c__tabName") === tabName) {
    return;
  }

  url.searchParams.delete("c__tabId");
  url.searchParams.delete("tabId");
  url.searchParams.set("c__tabName", tabName);
  window.history.replaceState(window.history.state, "", url.toString());
}

export function patchHistoryForNavigation() {
  if (window.__arcNavHistoryPatched) {
    return;
  }

  window.__arcNavHistoryPatched = true;

  const notifyPathChange = () => {
    window.dispatchEvent(new CustomEvent(NAV_PATH_CHANGE_EVENT));
  };

  const { pushState, replaceState } = window.history;
  window.history.pushState = function pushStatePatched(...args) {
    const result = pushState.apply(this, args);
    notifyPathChange();
    return result;
  };
  window.history.replaceState = function replaceStatePatched(...args) {
    const result = replaceState.apply(this, args);
    notifyPathChange();
    return result;
  };
}