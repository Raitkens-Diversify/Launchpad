/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 *
 * Experience Cloud record URL and navigation helpers. Imports
 * @salesforce/community/basePath — only use from LWR site components, never
 * from the core Lightning app (see c/recordNavigationUtils).
 */
import communityBasePath from "@salesforce/community/basePath";
import { NavigationMixin } from "lightning/navigation";
import {
  buildRecordPageReference,
  isValidSalesforceRecordId,
  resolveRecordIdFromPageReference,
  shouldAllowNativeRecordNavigation,
} from "c/recordNavigationUtils";

export {
  buildRecordPageReference,
  isValidSalesforceRecordId,
  resolveRecordIdFromPageReference,
  shouldAllowNativeRecordNavigation,
};

const EXPERIENCE_RECORD_ROUTE_PREFIX = Object.freeze({
  Account: "account",
  Case: "case",
  Envelope__c: "envelope",
  Task: "task",
  "FinServ__FinancialAccount__c": "financial-account",
  Work__c: "work",
});

const QUERY_PARAM_OBJECT_API_NAMES = new Set(["Envelope__c"]);

const isSalesforceId = isValidSalesforceRecordId;

export const deriveExperienceRoutePrefix = (objectApiName) => {
  if (!objectApiName) {
    return "";
  }

  if (EXPERIENCE_RECORD_ROUTE_PREFIX[objectApiName]) {
    return EXPERIENCE_RECORD_ROUTE_PREFIX[objectApiName];
  }

  if (!objectApiName.includes("__")) {
    return objectApiName.toLowerCase();
  }

  let localName = objectApiName;
  if (localName.endsWith("__c")) {
    localName = localName.slice(0, -3);
  }

  const segments = localName.split("__");
  const objectLabel = segments[segments.length - 1];

  return objectLabel.replace(/_/g, "-").toLowerCase();
};

export const usesQueryParamRecordRoute = (objectApiName) =>
  QUERY_PARAM_OBJECT_API_NAMES.has(objectApiName);

const resolveExperienceRoutePrefix = (objectApiName) =>
  deriveExperienceRoutePrefix(objectApiName);

const getExperienceRecordRoutePrefixSet = () =>
  new Set(
    Object.values(EXPERIENCE_RECORD_ROUTE_PREFIX).map((prefix) =>
      prefix.toLowerCase()
    )
  );

const stripExperienceRouteFromPath = (path) => {
  if (!path) {
    return "";
  }

  let segments = String(path).replace(/\/$/, "").split("/").filter(Boolean);
  const routePrefixes = getExperienceRecordRoutePrefixSet();

  if (!segments.length) {
    return "";
  }

  if (segments.length >= 2) {
    const lastSegment = segments[segments.length - 1];
    const routeSegment = segments[segments.length - 2].toLowerCase();

    if (routePrefixes.has(routeSegment) && isSalesforceId(lastSegment)) {
      segments = segments.slice(0, -2);
    }
  }

  if (segments.length >= 3) {
    const routeSegment = segments[segments.length - 3].toLowerCase();
    const listTail = segments[segments.length - 1];

    if (routePrefixes.has(routeSegment) && listTail === "Default") {
      segments = segments.slice(0, -3);
    }
  }

  if (segments.length >= 1) {
    const routeSegment = segments[segments.length - 1].toLowerCase();

    if (routePrefixes.has(routeSegment)) {
      segments = segments.slice(0, -1);
    }
  }

  return segments.length ? `/${segments.join("/")}` : "";
};

export const resolveCommunityBasePath = () => {
  if (communityBasePath) {
    return stripExperienceRouteFromPath(
      communityBasePath.replace(/\/$/, "")
    );
  }

  // No configured site path prefix (e.g. a root-mapped custom domain) means
  // the base path is simply "". Deriving it from window.location.pathname
  // instead is wrong here: on any page whose path isn't itself a record
  // route (list pages, /notifications, etc.) there's nothing to strip, so
  // the current page's own path gets treated as the base and every record
  // link built from it nests under that page (e.g. "/notifications/task/{id}"
  // instead of "/task/{id}").
  return "";
};

export const buildExperienceRecordPath = (recordId, objectApiName, options = {}) => {
  const routePrefix = resolveExperienceRoutePrefix(objectApiName);

  if (!recordId || !routePrefix) {
    return "";
  }

  const basePath = resolveCommunityBasePath();
  const useQueryParam =
    options.useQueryParam ?? usesQueryParamRecordRoute(objectApiName);

  if (useQueryParam) {
    return `${basePath}/${routePrefix}?id=${encodeURIComponent(recordId)}`;
  }

  return `${basePath}/${routePrefix}/${recordId}`;
};

export const buildRecordNavigationReference = (
  recordId,
  objectApiName,
  options = {}
) => {
  const experienceUrl = buildExperienceRecordPath(
    recordId,
    objectApiName,
    options
  );

  if (experienceUrl) {
    return {
      type: "standard__webPage",
      attributes: { url: experienceUrl },
    };
  }

  if (options.useQueryParam) {
    return null;
  }

  return buildRecordPageReference(recordId, objectApiName);
};

export const resolveRecordUrl = async (
  navigationHost,
  recordId,
  objectApiName,
  options = {}
) => {
  if (!recordId) {
    return null;
  }

  if (options.useQueryParam ?? usesQueryParamRecordRoute(objectApiName)) {
    return buildExperienceRecordPath(recordId, objectApiName, options);
  }

  try {
    const generatedUrl = await navigationHost[NavigationMixin.GenerateUrl](
      buildRecordPageReference(recordId, objectApiName)
    );

    if (generatedUrl) {
      return generatedUrl;
    }
  } catch (error) {
    // GenerateUrl is unavailable or unsupported for this route in Experience Cloud.
  }

  return buildExperienceRecordPath(recordId, objectApiName, options);
};

export const buildEnvelopeWizardUrl = () => {
  const basePath = (communityBasePath || resolveCommunityBasePath()).replace(
    /\/$/,
    ""
  );
  return `${basePath}/envelope`;
};

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
    // Non-fatal: fall back to page reference checks.
  }

  try {
    if (pageRef?.state?.app === "commeditor" && window.self === window.top) {
      return true;
    }
  } catch {
    // Non-fatal: treat as non-preview when frame access is blocked.
  }

  return false;
};

export const isExperiencePreviewContext = (pageRef) => isPreviewContext(pageRef);

export const resolvePublishedSiteOrigin = () => {
  if (typeof window === "undefined") {
    return "";
  }

  try {
    const { protocol, hostname, port } = window.location;
    const publishedHostname = hostname.replace(/\.preview\./gi, ".");
    const portSuffix =
      port && port !== "80" && port !== "443" ? `:${port}` : "";

    return `${protocol}//${publishedHostname}${portSuffix}`;
  } catch {
    return window.location.origin;
  }
};

export const buildPublishedExperienceSiteUrl = (sitePath) => {
  if (!sitePath) {
    return "";
  }

  const normalizedPath = sitePath.startsWith("/") ? sitePath : `/${sitePath}`;
  return `${resolvePublishedSiteOrigin()}${normalizedPath}`;
};

export const isExperienceBuilderDesignMode = (pageRef) => {
  if (isPreviewContext(pageRef)) {
    return false;
  }

  if (pageRef?.state?.app === "commeditor") {
    try {
      return window.self !== window.top;
    } catch {
      return true;
    }
  }

  if (pageRef?.state?.app) {
    return false;
  }

  try {
    return window.self !== window.top;
  } catch {
    return false;
  }
};