/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 *
 * Shared helpers for FSC Relationship Tree LWCs.
 */
import { loadStyle } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import fscRelModalOverflow from "@salesforce/resourceUrl/fscRelModalOverflow";

export const FIDUCIARY_LEGAL_RECORD_TYPE = "Fiduciary_Legal";
export const HOUSEHOLD_AAR_RECORD_TYPE = "Household";

export const normalizeAccountRelationRecordTypeDeveloperName = (
  recordTypeDeveloperName
) => String(recordTypeDeveloperName || "").trim();

export const isExcludedMemberRelationshipRecordType = (
  recordTypeDeveloperName
) => {
  return (
    normalizeAccountRelationRecordTypeDeveloperName(recordTypeDeveloperName) ===
    HOUSEHOLD_AAR_RECORD_TYPE
  );
};

export const isReadOnlyMemberRelationshipRecordType = (
  recordTypeDeveloperName
) => {
  return (
    normalizeAccountRelationRecordTypeDeveloperName(recordTypeDeveloperName) ===
    FIDUCIARY_LEGAL_RECORD_TYPE
  );
};

export const MEMBER_RELATIONSHIP_GROUP_LABELS = Object.freeze({
  Personal_and_Family: "Family and Friends",
  COI_Referral: "COI / Referral",
  Service_Provider: "Service Provider",
  Business: "Business",
  Fiduciary_Legal: "Fiduciary / Regulatory",
  Other: "Other"
});

const formatMemberRelationshipRecordTypeLabel = (developerName = "") =>
  String(developerName || "")
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .trim();

export const resolveMemberRelationshipRecordTypeLabel = (
  recordTypeDeveloperName = "",
  recordTypeLabel = ""
) => {
  const developerName = normalizeAccountRelationRecordTypeDeveloperName(
    recordTypeDeveloperName
  );

  if (MEMBER_RELATIONSHIP_GROUP_LABELS[developerName]) {
    return MEMBER_RELATIONSHIP_GROUP_LABELS[developerName];
  }

  const label = String(recordTypeLabel || "").trim();
  if (label) {
    return label;
  }

  return formatMemberRelationshipRecordTypeLabel(developerName) || "Member";
};

export const resolveMemberRelationshipCollectionLabel = (
  recordTypeDeveloperName = ""
) =>
  isReadOnlyMemberRelationshipRecordType(recordTypeDeveloperName)
    ? "Related Parties"
    : "Contacts";

export const buildMemberRelationshipActionLabel = (recordType = {}) => {
  const developerName = normalizeAccountRelationRecordTypeDeveloperName(
    recordType.developerName
  );
  const label = resolveMemberRelationshipRecordTypeLabel(
    developerName,
    recordType.label
  );
  const collectionLabel =
    resolveMemberRelationshipCollectionLabel(developerName);
  const verb = isReadOnlyMemberRelationshipRecordType(developerName)
    ? "View"
    : "Manage";

  return `${verb} ${label} ${collectionLabel}`;
};

export const buildMemberRelationshipModalTitle = (
  recordTypeDeveloperName = "",
  recordTypeLabel = "",
  { isReadOnly = false } = {}
) => {
  const label = resolveMemberRelationshipRecordTypeLabel(
    recordTypeDeveloperName,
    recordTypeLabel
  );
  const collectionLabel = resolveMemberRelationshipCollectionLabel(
    recordTypeDeveloperName
  );
  const verb = isReadOnly ? "View" : "Manage";

  return `${verb} ${label} ${collectionLabel}`;
};

export const buildReadOnlyMemberRelationshipInstruction = (
  memberName = "This member",
  recordTypeDeveloperName = "",
  recordTypeLabel = ""
) => {
  const label = resolveMemberRelationshipRecordTypeLabel(
    recordTypeDeveloperName,
    recordTypeLabel
  );
  const collectionLabel = resolveMemberRelationshipCollectionLabel(
    recordTypeDeveloperName
  ).toLowerCase();

  return `Review ${memberName}'s ${label} relationships. These ${collectionLabel} cannot be changed here.`;
};

export const buildReadOnlyMemberRelationshipEmptyState = (
  recordTypeDeveloperName = "",
  recordTypeLabel = ""
) => {
  const label = resolveMemberRelationshipRecordTypeLabel(
    recordTypeDeveloperName,
    recordTypeLabel
  );
  const collectionLabel = resolveMemberRelationshipCollectionLabel(
    recordTypeDeveloperName
  ).toLowerCase();

  return `No ${label} ${collectionLabel} defined.`;
};

const CLIENT_RECORD_TYPE_LABELS = new Set([
  "Person Account",
  "Business",
  "Trust",
  "Retirement Plan"
]);

const CLIENT_RECORD_TYPE_DEVELOPER_NAMES = new Set([
  "PersonAccount",
  "Person_Account",
  "Business",
  "Business_Account",
  "IndustriesBusiness",
  "Trust",
  "IndustriesInstitution",
  "Retirement_Plan",
  "Retirement Plan"
]);

const CLIENT_ACCOUNT_TYPES = new Set(["Active Client", "Former Client"]);

const LEAD_PROSPECT_ACCOUNT_TYPES = new Set(["Lead", "Prospect"]);

export const isClientRecordType = (
  recordTypeLabel = "",
  recordTypeDeveloperName = ""
) => {
  const label = String(recordTypeLabel || "").trim();
  const developerName = String(recordTypeDeveloperName || "").trim();

  if (label && CLIENT_RECORD_TYPE_LABELS.has(label)) {
    return true;
  }

  if (developerName && CLIENT_RECORD_TYPE_DEVELOPER_NAMES.has(developerName)) {
    return true;
  }

  const normalizedDeveloperName = developerName.toLowerCase();

  return (
    normalizedDeveloperName.includes("retirement") &&
    normalizedDeveloperName.includes("plan")
  );
};

export const isClientAccountType = (accountType = "") => {
  return CLIENT_ACCOUNT_TYPES.has(String(accountType || "").trim());
};

export const isLeadProspectAccountType = (accountType = "") => {
  return LEAD_PROSPECT_ACCOUNT_TYPES.has(String(accountType || "").trim());
};

export const isClientAccount = (account = {}) => {
  return (
    isClientRecordType(
      account.recordTypeLabel,
      account.recordTypeDeveloperName
    ) && isClientAccountType(account.accountType || account.type)
  );
};

export const isHouseholdMembershipPersonAccount = (account = {}) => {
  return (
    account.isPersonAccount === true &&
    String(account.associationType || account.detail || "").trim() === "Member" &&
    Boolean(account.relationId)
  );
};

export const isHouseholdMapClientAccount = (account = {}) => {
  return isClientAccount(account) || isHouseholdMembershipPersonAccount(account);
};

export const isLeadProspectAccount = (account = {}) => {
  return (
    isClientRecordType(
      account.recordTypeLabel,
      account.recordTypeDeveloperName
    ) && isLeadProspectAccountType(account.accountType || account.type)
  );
};

let modalStylesPromise;

export const FSC_REL_MODAL_OVERFLOW_ARIA_MARKER = "fsc-rel-allow-overflow";

export const buildFscRelModalDescription = (label) => {
  if (!label) {
    return FSC_REL_MODAL_OVERFLOW_ARIA_MARKER;
  }

  return `${label} | ${FSC_REL_MODAL_OVERFLOW_ARIA_MARKER}`;
};

export const ensureFscRelModalStyles = (component) => {
  if (!modalStylesPromise) {
    modalStylesPromise = loadStyle(component, fscRelModalOverflow).catch((error) => {
      modalStylesPromise = undefined;
      // eslint-disable-next-line no-console
      console.error("[fscRelUtils] Failed to load fscRelModalOverflow", error);
    });
  }

  return modalStylesPromise;
};

export const labelToValue = (label) => {
  if (!label) {
    return "";
  }

  return String(label).trim().toLowerCase().replace(/\s+/g, "_");
};

export const computeInitials = (name) => {
  if (!name) {
    return "";
  }

  const parts = String(name).trim().split(/\s+/);
  if (parts.length === 0) {
    return "";
  }

  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }

  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

export const sortMembersByPrimary = (members) => {
  return [...members].sort((first, second) => {
    const firstIsClient = memberHasClientRole(first) ? 1 : 0;
    const secondIsClient = memberHasClientRole(second) ? 1 : 0;

    if (secondIsClient !== firstIsClient) {
      return secondIsClient - firstIsClient;
    }

    const firstIsPrimary = first.isPrimaryMember ? 1 : 0;
    const secondIsPrimary = second.isPrimaryMember ? 1 : 0;

    if (secondIsPrimary !== firstIsPrimary) {
      return secondIsPrimary - firstIsPrimary;
    }

    return (first.name || "").localeCompare(second.name || "", undefined, {
      sensitivity: "base"
    });
  });
};

export const buildMemberViewModels = (rawMembers) => {
  return sortMembersByPrimary(rawMembers).map((member) => {
    const selectedRoles = (member.roles || [])
      .map(labelToValue)
      .filter(Boolean);
    const primaryRoleLabel = member.roles?.[0] || "";

    return {
      id: member.relationId || member.contactId || member.accountId,
      relationId: member.relationId,
      accountId: member.accountId || "",
      contactId: member.contactId || "",
      name: member.name || "",
      iconName: "standard:contact",
      role: primaryRoleLabel,
      roles: (member.roles || []).filter(Boolean),
      selectedRoles,
      detail: "",
      recordTypeDeveloperName: member.recordTypeDeveloperName || "",
      recordTypeLabel: member.recordTypeLabel || "",
      accountType: member.accountType || "",
      isPrimaryMember: Boolean(member.isPrimaryMember),
      isPrimaryGroup: Boolean(member.isPrimaryGroup),
      menuLabel: member.name
        ? `Open ${member.name} actions`
        : "Open member actions"
    };
  });
};

export const mapMembersForModal = (members) => {
  return sortMembersByPrimary(members || []).map((member) => ({
    relationId: member.relationId || "",
    accountId: member.accountId || "",
    name: member.name || "",
    selectedRoles: Array.isArray(member.selectedRoles)
      ? member.selectedRoles
      : [],
    role: member.role || "",
    isPrimaryMember: Boolean(member.isPrimaryMember),
    isPrimaryGroup: Boolean(member.isPrimaryGroup)
  }));
};

export const extractApexError = (error, fallbackMessage) => {
  return error?.body?.message || error?.message || fallbackMessage;
};

export const dispatchToast = (
  element,
  { title, message, variant = "info" }
) => {
  element.dispatchEvent(
    new ShowToastEvent({
      title,
      message,
      variant
    })
  );
};

export const buildModalSaveMessage = ({
  successCount = 0,
  deletedCount = 0,
  subject = ""
} = {}) => {
  if (successCount === 0 && deletedCount === 0) {
    return subject
      ? `Updated relationships for ${subject}.`
      : "Updated relationships.";
  }

  const parts = [];
  if (successCount > 0) {
    parts.push(
      `saved ${successCount} relationship${successCount === 1 ? "" : "s"}`
    );
  }
  if (deletedCount > 0) {
    parts.push(
      `removed ${deletedCount} relationship${deletedCount === 1 ? "" : "s"}`
    );
  }

  const summary = parts.join(" · ");
  if (subject) {
    return `${summary.charAt(0).toUpperCase()}${summary.slice(1)} for ${subject}.`;
  }

  return `${summary.charAt(0).toUpperCase()}${summary.slice(1)}.`;
};

export const buildModalSaveButtonLabel = (readyCount) => {
  if (!readyCount) {
    return "Save";
  }

  return `Save ${readyCount} relationship${readyCount === 1 ? "" : "s"}`;
};

export const buildRoleLabels = (member) => {
  const roles = Array.isArray(member.roles) ? member.roles : [];
  const labels = roles.map((role) => String(role || "").trim()).filter(Boolean);

  if (labels.length > 0) {
    return labels;
  }

  const fallbackRole = String(member.role || "").trim();
  return fallbackRole ? [fallbackRole] : [];
};

export const buildAccountViewModels = (rawAccounts) => {
  return [...(rawAccounts || [])]
    .sort((first, second) =>
      (first.name || "").localeCompare(second.name || "", undefined, {
        sensitivity: "base"
      })
    )
    .map((account) => {
      const roles = Array.isArray(account.roles)
        ? account.roles.map((role) => String(role || "").trim()).filter(Boolean)
        : [];
      const associationTypeLabel = String(account.associationType || "").trim();

      return {
        id: account.relationId || account.accountId,
        relationId: account.relationId,
        accountId: account.accountId || "",
        contactId: "",
        name: account.name || "",
        iconName: "standard:account",
        roles,
        selectedRoles: [...roles],
        detail: associationTypeLabel,
        associationType: associationTypeLabel,
        recordTypeDeveloperName: account.recordTypeDeveloperName || "",
        recordTypeLabel: account.recordTypeLabel || "",
        accountType: account.accountType || "",
        contactId: account.contactId || "",
        isPersonAccount: Boolean(account.isPersonAccount),
        classifications: Array.isArray(account.classifications)
          ? account.classifications
              .map((value) => String(value || "").trim())
              .filter(Boolean)
          : [],
        isPrimaryMember: false,
        isPrimaryGroup: false,
        menuLabel: account.name
          ? `Open ${account.name} actions`
          : "Open account actions"
      };
    });
};

export const mapAccountsForModal = (accounts) => {
  return (accounts || []).map((account) => ({
    relationId: account.relationId || "",
    accountId: account.accountId || "",
    name: account.name || "",
    selectedRoles: Array.isArray(account.selectedRoles)
      ? account.selectedRoles
      : Array.isArray(account.roles)
        ? account.roles
        : [],
    associationType: account.associationType || account.detail || "",
    recordTypeDeveloperName: account.recordTypeDeveloperName || "",
    recordTypeLabel: account.recordTypeLabel || ""
  }));
};

export const mapMemberAccountRelationshipsForModal = (relationships) => {
  return (relationships || []).map((relationship) => ({
    relationId: relationship.relationId || "",
    memberAccountId: relationship.memberAccountId || "",
    memberAccountName: relationship.memberAccountName || "",
    relatedAccountId: relationship.relatedAccountId || "",
    relatedAccountName: relationship.relatedAccountName || "",
    reciprocalRoleId: relationship.reciprocalRoleId || "",
    role: relationship.role || "",
    inverseReciprocalRoleId: relationship.inverseReciprocalRoleId || "",
    inverseRole: relationship.inverseRole || "",
    isActive: relationship.isActive !== false
  }));
};

export const mapContactRelationshipsForModal = (relationships) => {
  return (relationships || []).map((relationship) => ({
    relationId: relationship.relationId || "",
    relatedAccountId:
      relationship.relatedAccountId ||
      relationship.relatedContactAccountId ||
      "",
    relatedAccountName:
      relationship.relatedAccountName || relationship.relatedContactName || "",
    reciprocalRoleId: relationship.reciprocalRoleId || "",
    role: relationship.role || "",
    isActive: relationship.isActive !== false
  }));
};

export const buildMemberAccountRelationshipViewModels = (rawRelationships = []) => {
  return [...rawRelationships]
    .sort((first, second) =>
      (first.relatedAccountName || "").localeCompare(
        second.relatedAccountName || "",
        undefined,
        { sensitivity: "base" }
      )
    )
    .map((relationship) => {
      const roleLabel = String(relationship.role || "").trim();
      const inverseRoleLabel = String(relationship.inverseRole || "").trim();

      return {
        relationId: relationship.relationId || "",
        relatedAccountId: relationship.relatedAccountId || "",
        relatedAccountName: relationship.relatedAccountName || "",
        role: roleLabel,
        roleLabel,
        inverseRole: inverseRoleLabel,
        inverseRoleLabel,
        recordTypeDeveloperName: normalizeAccountRelationRecordTypeDeveloperName(
          relationship.recordTypeDeveloperName
        ) || '',
        isActive: relationship.isActive !== false
      };
    });
};

export const buildContactRelationshipViewModels = (rawRelationships = []) => {
  return [...rawRelationships]
    .sort((first, second) =>
      (
        first.relatedAccountName ||
        first.relatedContactName ||
        ""
      ).localeCompare(
        second.relatedAccountName || second.relatedContactName || "",
        undefined,
        { sensitivity: "base" }
      )
    )
    .map((relationship) => {
      const roleLabel = String(relationship.role || "").trim();
      const inverseRoleLabel = String(relationship.inverseRole || "").trim();
      const relatedAccountName =
        relationship.relatedAccountName ||
        relationship.relatedContactName ||
        "";
      const relatedAccountId =
        relationship.relatedAccountId ||
        relationship.relatedContactAccountId ||
        "";

      return {
        relationId: relationship.relationId || "",
        relatedAccountId,
        relatedAccountName,
        relatedContactId: relationship.relatedContactId || "",
        relatedContactName: relatedAccountName,
        role: roleLabel,
        roleLabel,
        inverseRole: inverseRoleLabel,
        inverseRoleLabel,
        isActive: relationship.isActive !== false
      };
    });
};

const HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAMES = new Set([
  "Household",
  "IndustriesHousehold"
]);

export const CLIENT_ROLE_VALUE = "Client";

export const isClientRoleValue = (roleValue) => {
  return (
    String(roleValue || "")
      .trim()
      .toLowerCase() === "client"
  );
};

export const isClientRoleOption = (option) => {
  const value = String(option?.value || "")
    .trim()
    .toLowerCase();
  const label = String(option?.label || "")
    .trim()
    .toLowerCase();

  return value === "client" || label === "client";
};

export const filterSelectableRoleOptions = (options = []) => {
  return (options || []).filter((option) => !isClientRoleOption(option));
};

export const resolveRolePicklistValue = (rawValue, allOptions = []) => {
  const trimmed = String(rawValue || "").trim();

  if (!trimmed) {
    return "";
  }

  if (isClientRoleValue(trimmed)) {
    return CLIENT_ROLE_VALUE;
  }

  if (!allOptions.length) {
    return trimmed;
  }

  const match = allOptions.find(
    (option) =>
      option.value === trimmed ||
      option.label === trimmed ||
      option.value.toLowerCase() === trimmed.toLowerCase() ||
      option.label.toLowerCase() === trimmed.toLowerCase()
  );

  return match ? match.value : "";
};

export const resolveRoleLabel = (roleValue, allOptions = []) => {
  const trimmed = String(roleValue || "").trim();

  if (!trimmed) {
    return "";
  }

  const match = (allOptions || []).find((option) => option.value === trimmed);

  if (match?.label) {
    return match.label;
  }

  if (isClientRoleValue(trimmed)) {
    return CLIENT_ROLE_VALUE;
  }

  return trimmed;
};

export const isHouseholdRecordType = (recordTypeDeveloperName) => {
  const developerName = String(recordTypeDeveloperName || "").trim();

  if (!developerName) {
    return false;
  }

  if (HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAMES.has(developerName)) {
    return true;
  }

  return developerName.toLowerCase().includes("household");
};

export const hasClientRole = (selectedRoles = [], roleOptions = []) => {
  return (selectedRoles || []).some((roleValue) =>
    isClientRoleValue(roleValue)
  );
};

export const memberHasClientRole = (member) => {
  if (!member) {
    return false;
  }

  if (
    Array.isArray(member.selectedRoles) &&
    hasClientRole(member.selectedRoles)
  ) {
    return true;
  }

  if (Array.isArray(member.roles)) {
    return member.roles.some((roleValue) => isClientRoleValue(roleValue));
  }

  return isClientRoleValue(member.role);
};

export const normalizeMemberRoles = (member) => {
  if (
    Array.isArray(member?.selectedRoles) &&
    member.selectedRoles.length > 0
  ) {
    return member.selectedRoles.filter(Boolean);
  }

  if (Array.isArray(member?.roles) && member.roles.length > 0) {
    return member.roles.filter(Boolean);
  }

  const role = (member?.role || "").trim();
  return role ? [role] : [];
};

export const extractSelectableRoles = (selectedRoles = []) => {
  return (selectedRoles || []).filter(
    (roleValue) => !isClientRoleValue(roleValue)
  );
};

export const preserveClientRoleOnChange = (
  previousRoles = [],
  nextSelectableRoles = []
) => {
  const selectableRoles = (nextSelectableRoles || []).filter(
    (roleValue) => !isClientRoleValue(roleValue)
  );

  if (!hasClientRole(previousRoles)) {
    return selectableRoles;
  }

  return [CLIENT_ROLE_VALUE, ...selectableRoles];
};

export const getLockedClientRoleValues = (selectedRoles = []) => {
  return hasClientRole(selectedRoles) ? [CLIENT_ROLE_VALUE] : [];
};

export const buildRolePickerOptions = (allOptions = [], selectedRoles = []) => {
  const selectableOptions = filterSelectableRoleOptions(allOptions);

  if (!hasClientRole(selectedRoles)) {
    return selectableOptions;
  }

  return [
    {
      label: resolveRoleLabel(CLIENT_ROLE_VALUE, allOptions),
      value: CLIENT_ROLE_VALUE
    },
    ...selectableOptions
  ];
};

export const PREVIEW_PANEL_OFFSET = Object.freeze({ x: 8, y: 0 });
export const PREVIEW_PANEL_WIDTH = 384;
export const PREVIEW_PANEL_HEIGHT = 320;

export const computePreviewPanelPosition = (
  canvasElement,
  anchorRect,
  offset = PREVIEW_PANEL_OFFSET,
  scrollElement = null
) => {
  if (!canvasElement || !anchorRect) {
    return { left: 24, top: 24 };
  }

  const canvasRect = canvasElement.getBoundingClientRect();
  const scroller = scrollElement || canvasElement;
  const scrollLeft = scroller?.scrollLeft || 0;
  const scrollTop = scroller?.scrollTop || 0;

  return {
    left: Math.max(
      8,
      anchorRect.right - canvasRect.left + scrollLeft + offset.x
    ),
    top: Math.max(
      8,
      anchorRect.top - canvasRect.top + scrollTop + offset.y
    )
  };
};

export const computePreviewPanelTopLeftPosition = (
  canvasElement,
  anchorRect,
  offset = PREVIEW_PANEL_OFFSET,
  scrollElement = null
) => {
  if (!canvasElement || !anchorRect) {
    return { left: 24, top: 24 };
  }

  const canvasRect = canvasElement.getBoundingClientRect();
  const scroller = scrollElement || canvasElement;
  const scrollLeft = scroller?.scrollLeft || 0;
  const scrollTop = scroller?.scrollTop || 0;

  return {
    left: Math.max(
      8,
      anchorRect.left - canvasRect.left + scrollLeft + offset.x
    ),
    top: Math.max(
      8,
      anchorRect.top - canvasRect.top + scrollTop + offset.y
    )
  };
};

export const computePreviewPanelLeftOfAnchorPosition = (
  canvasElement,
  anchorRect,
  {
    offset = PREVIEW_PANEL_OFFSET,
    panelWidth = PREVIEW_PANEL_WIDTH,
    scrollElement = null
  } = {}
) => {
  if (!canvasElement || !anchorRect) {
    return { left: 24, top: 24 };
  }

  const canvasRect = canvasElement.getBoundingClientRect();
  const scroller = scrollElement || canvasElement;
  const scrollLeft = scroller?.scrollLeft || 0;
  const scrollTop = scroller?.scrollTop || 0;

  return {
    left: Math.max(
      8,
      anchorRect.left - canvasRect.left + scrollLeft - panelWidth - offset.x
    ),
    top: Math.max(
      8,
      anchorRect.top - canvasRect.top + scrollTop + offset.y
    )
  };
};

export const computePreviewPanelCenterPosition = (
  scrollElement,
  {
    panelWidth = PREVIEW_PANEL_WIDTH,
    panelHeight = PREVIEW_PANEL_HEIGHT,
    inset = 8,
    scrollRelative = false
  } = {}
) => {
  if (!scrollElement) {
    return { left: 24, top: 24 };
  }

  if (scrollRelative) {
    const scrollLeft = scrollElement.scrollLeft || 0;
    const scrollTop = scrollElement.scrollTop || 0;
    const centerLeft = scrollLeft + (scrollElement.clientWidth - panelWidth) / 2;
    const centerTop = scrollTop + (scrollElement.clientHeight - panelHeight) / 2;

    return clampPreviewPanelPosition(centerLeft, centerTop, {
      scrollRelative: true,
      scrollLeft,
      scrollTop,
      clientWidth: scrollElement.clientWidth,
      clientHeight: scrollElement.clientHeight
    }, {
      panelWidth,
      panelHeight,
      inset
    });
  }

  const viewportRect = scrollElement.getBoundingClientRect();
  const centerLeft = viewportRect.left + (viewportRect.width - panelWidth) / 2;
  const centerTop = viewportRect.top + (viewportRect.height - panelHeight) / 2;

  return clampPreviewPanelPosition(centerLeft, centerTop, viewportRect, {
    panelWidth,
    panelHeight,
    inset
  });
};

export const clampPreviewPanelPosition = (
  left,
  top,
  boundaryRect,
  {
    panelWidth = PREVIEW_PANEL_WIDTH,
    panelHeight = PREVIEW_PANEL_HEIGHT,
    inset = 8
  } = {}
) => {
  if (!boundaryRect) {
    return { left, top };
  }

  if (boundaryRect.scrollRelative) {
    const scrollLeft = boundaryRect.scrollLeft || 0;
    const scrollTop = boundaryRect.scrollTop || 0;
    const minLeft = scrollLeft + inset;
    const minTop = scrollTop + inset;
    const maxLeft = Math.max(
      minLeft,
      scrollLeft + boundaryRect.clientWidth - panelWidth - inset
    );
    const maxTop = Math.max(
      minTop,
      scrollTop + boundaryRect.clientHeight - panelHeight - inset
    );

    return {
      left: Math.min(Math.max(left, minLeft), maxLeft),
      top: Math.min(Math.max(top, minTop), maxTop)
    };
  }

  const minLeft = boundaryRect.left + inset;
  const minTop = boundaryRect.top + inset;
  const maxLeft = Math.max(minLeft, boundaryRect.right - panelWidth - inset);
  const maxTop = Math.max(minTop, boundaryRect.bottom - panelHeight - inset);

  return {
    left: Math.min(Math.max(left, minLeft), maxLeft),
    top: Math.min(Math.max(top, minTop), maxTop)
  };
};

export const buildRecordPageUrl = (recordId, objectApiName = "Account") => {
  const normalizedRecordId = String(recordId || "").trim();
  const normalizedObjectApiName = String(objectApiName || "Account").trim();

  if (!normalizedRecordId || !normalizedObjectApiName) {
    return "";
  }

  return `/lightning/r/${normalizedObjectApiName}/${normalizedRecordId}/view`;
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