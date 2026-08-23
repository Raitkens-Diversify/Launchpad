/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { NavigationMixin } from "lightning/navigation";
import {
  getFocusedTabInfo,
  openSubtab,
  openTab
} from "lightning/platformWorkspaceApi";

export const buildRecordPageReference = (recordId) => ({
  type: "standard__recordPage",
  attributes: {
    recordId,
    actionName: "view"
  }
});

export const resolveRecordUrl = (navigationHost, recordId) => {
  if (!recordId) {
    return Promise.resolve(null);
  }

  return navigationHost[NavigationMixin.GenerateUrl](
    buildRecordPageReference(recordId)
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
      focus: true
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
      focus: true
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

export const attachRecordUrls = (navigationHost, items, recordIdField = "relatedRecordId") =>
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
        hasRecordLink: Boolean(recordUrl)
      };
    })
  );

export const attachLogRecordUrls = (navigationHost, items) =>
  Promise.all(
    items.map(async (item) => {
      const [householdUrl, sourceRecordUrl, branchUrl, financialAdvisorTeamUrl] =
        await Promise.all([
          resolveRecordUrl(navigationHost, item.householdId),
          resolveRecordUrl(navigationHost, item.sourceRecordId),
          resolveRecordUrl(navigationHost, item.branchId),
          resolveRecordUrl(navigationHost, item.financialAdvisorTeamId)
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
        )
      };
    })
  );