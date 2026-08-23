/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Record navigation helpers for the core Lightning app (Notification Center,
 * Book of Business, etc.). Safe to import anywhere — no Experience Cloud
 * modules. For LWR site URL building, use c/recordNavigationCommunityUtils.
 */
import { NavigationMixin } from "lightning/navigation";
import {
  getFocusedTabInfo,
  openSubtab,
  openTab,
} from "lightning/platformWorkspaceApi";

const SALESFORCE_ID_PATTERN = /^[a-zA-Z0-9]{15,18}$/;

const RECORD_ID_QUERY_KEYS = ["recordId", "id", "c__recordId"];

export const isValidSalesforceRecordId = (value) =>
  typeof value === "string" && SALESFORCE_ID_PATTERN.test(value);

const isSalesforceId = isValidSalesforceRecordId;

const resolveRecordIdFromPath = (pathname) => {
  const segments = (pathname || "").split("/").filter(Boolean);
  if (segments.length === 0) {
    return null;
  }

  const lastSegment = segments[segments.length - 1];
  return isSalesforceId(lastSegment) ? lastSegment : null;
};

/**
 * Resolve the current record Id from the page context: Lightning record-page
 * attributes, LWR page state, URL query params, or the final URL path segment.
 */
export const resolveRecordIdFromPageReference = (pageRef, objectApiName) => {
  const attributeRecordId = pageRef?.attributes?.recordId;
  if (isSalesforceId(attributeRecordId)) {
    return attributeRecordId;
  }

  const state = pageRef?.state || {};

  if (isSalesforceId(state.recordId)) {
    return state.recordId;
  }

  const params = new URLSearchParams(
    typeof window !== "undefined" ? window.location.search || "" : ""
  );

  for (const key of RECORD_ID_QUERY_KEYS) {
    const queryValue = params.get(key) || state[key];
    if (isSalesforceId(queryValue)) {
      return queryValue;
    }
  }

  if (typeof window !== "undefined") {
    return resolveRecordIdFromPath(window.location.pathname);
  }

  return null;
};

export const buildRecordPageReference = (recordId, objectApiName) => {
  const attributes = {
    recordId,
    actionName: "view",
  };

  if (objectApiName) {
    attributes.objectApiName = objectApiName;
  }

  return {
    type: "standard__recordPage",
    attributes,
  };
};

export const resolveRecordUrl = async (
  navigationHost,
  recordId,
  objectApiName
) => {
  if (!recordId) {
    return null;
  }

  try {
    const generatedUrl = await navigationHost[NavigationMixin.GenerateUrl](
      buildRecordPageReference(recordId, objectApiName)
    );

    if (generatedUrl) {
      return generatedUrl;
    }
  } catch (error) {
    // GenerateUrl is unavailable outside supported Lightning contexts.
  }

  return null;
};

export const shouldAllowNativeRecordNavigation = (event) => {
  if (!event) {
    return false;
  }

  return (
    event.button === 1 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey
  );
};

const openRecordInBrowserTab = (navigationHost, recordId) =>
  resolveRecordUrl(navigationHost, recordId).then((url) => {
    if (!url) {
      return;
    }

    window.open(url, "_blank", "noopener,noreferrer");
  });

const openRecordInWorkspace = async (pageReference) => {
  try {
    await openTab({
      pageReference,
      focus: true,
    });
    return true;
  } catch (openTabError) {
    // openTab is unavailable outside workspace-enabled apps.
  }

  try {
    const focusedTab = await getFocusedTabInfo();
    if (!focusedTab?.tabId) {
      return false;
    }

    await openSubtab(focusedTab.tabId, {
      pageReference,
      focus: true,
    });
    return true;
  } catch (openSubtabError) {
    return false;
  }
};

export const openRecordInNewTab = async (navigationHost, recordId) => {
  if (!recordId) {
    return;
  }

  const pageReference = buildRecordPageReference(recordId);
  const openedInWorkspace = await openRecordInWorkspace(pageReference);

  if (openedInWorkspace) {
    return;
  }

  if (navigationHost?.[NavigationMixin.Navigate]) {
    navigationHost[NavigationMixin.Navigate](pageReference);
    return;
  }

  await openRecordInBrowserTab(navigationHost, recordId);
};

export const attachRecordUrls = (
  navigationHost,
  items,
  recordIdField = "relatedRecordId"
) =>
  Promise.all(
    items.map(async (item) => {
      const recordId = item[recordIdField];

      if (!recordId) {
        return item;
      }

      const recordUrl = await resolveRecordUrl(navigationHost, recordId);
      return {
        ...item,
        recordUrl,
        hasRecordLink: Boolean(recordUrl),
      };
    })
  );

export const attachLogRecordUrls = (navigationHost, items) =>
  Promise.all(
    items.map(async (item) => {
      const [
        householdUrl,
        sourceRecordUrl,
        branchUrl,
        financialAdvisorTeamUrl,
      ] = await Promise.all([
        resolveRecordUrl(navigationHost, item.householdId),
        resolveRecordUrl(navigationHost, item.sourceRecordId),
        resolveRecordUrl(navigationHost, item.branchId),
        resolveRecordUrl(navigationHost, item.financialAdvisorTeamId),
      ]);

      return {
        ...item,
        householdUrl,
        hasHouseholdLink: Boolean(item.householdId && householdUrl),
        sourceRecordUrl,
        hasSourceRecordLink: Boolean(item.sourceRecordId && sourceRecordUrl),
        branchUrl,
        hasBranchLink: Boolean(item.branchId && branchUrl),
        financialAdvisorTeamUrl,
        hasFinancialAdvisorTeamLink: Boolean(
          item.financialAdvisorTeamId && financialAdvisorTeamUrl
        ),
      };
    })
  );