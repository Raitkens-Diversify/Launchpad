/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 *
 * Helpers for transforming FSC relationship tree data into map nodes.
 */
import {
  buildMemberViewModels,
  buildAccountViewModels,
  buildMemberAccountRelationshipViewModels,
  buildRoleLabels,
  buildMemberRelationshipActionLabel,
  CLIENT_ROLE_VALUE,
  computeInitials,
  isClientAccount,
  isHouseholdMapClientAccount,
  isClientRoleValue,
  isLeadProspectAccount,
  isExcludedMemberRelationshipRecordType,
  isReadOnlyMemberRelationshipRecordType,
  memberHasClientRole,
  normalizeAccountRelationRecordTypeDeveloperName,
  resolveMemberRelationshipRecordTypeLabel
} from "c/fscRelUtils";

export const MAP_KIND = Object.freeze({
  HOUSEHOLD: "household",
  PERSON: "person",
  TRUST: "trust",
  BUSINESS: "business",
  GROUP: "group",
  COI: "coi",
  FINACCT: "finacct"
});

export const MAP_NODE_TYPE = Object.freeze({
  ROOT: "root",
  GROUP: "group",
  MEMBER: "member",
  ACCOUNT: "account",
  RELATED_CONTACT: "relatedContact",
  RELATIONSHIP_GROUP: "relationshipGroup",
  ADD: "add"
});

export const GROUP_IDS = Object.freeze({
  INDIVIDUALS: "group-individuals",
  FAMILY: "group-family",
  LEAD_PROSPECT: "group-lead-prospect",
  NETWORK: "group-network",
  VENDORS: "group-vendors",
  UNCLASSIFIED: "group-unclassified",
  TRUSTS: "group-trusts",
  BUSINESSES: "group-businesses",
  HOUSEHOLDS: "group-households"
});

export const CLASSIFICATION_VALUES = Object.freeze({
  COI: "COI",
  VENDOR: "Vendor",
  UNCLASSIFIED: "Unclassified"
});

export const MANAGE_CLASSIFICATION_ACTION_PREFIX = "manageclassification:";

export const ALL_LAZY_GROUP_LOADED = Object.freeze({
  [GROUP_IDS.TRUSTS]: true,
  [GROUP_IDS.BUSINESSES]: true,
  [GROUP_IDS.HOUSEHOLDS]: true
});

export const mergeLoadedGroupIds = (loadedGroupIds = {}) => ({
  ...ALL_LAZY_GROUP_LOADED,
  ...loadedGroupIds
});

export const buildFullyLoadedMapTree = ({
  treeData,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  loadedGroupIds = {}
} = {}) => {
  return buildMapTree({
    treeData,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId,
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes,
    loadedGroupIds: mergeLoadedGroupIds(loadedGroupIds)
  });
};

const GROUP_DEFINITIONS = Object.freeze([
  {
    id: GROUP_IDS.INDIVIDUALS,
    label: "Client",
    iconName: "standard:people",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.FAMILY,
    label: "Family and Friends",
    iconName: "standard:groups",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.LEAD_PROSPECT,
    label: "Lead/Prospect",
    iconName: "standard:lead",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.NETWORK,
    label: "Professional Network",
    iconName: "standard:strategy",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.VENDORS,
    label: "Vendors",
    iconName: "standard:buyer_account",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.UNCLASSIFIED,
    label: "Unclassified",
    iconName: "standard:channel_programs",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.TRUSTS,
    label: "Trusts",
    iconName: "standard:contract",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.BUSINESSES,
    label: "Businesses",
    iconName: "standard:account",
    kind: MAP_KIND.GROUP
  },
  {
    id: GROUP_IDS.HOUSEHOLDS,
    label: "Related Households",
    iconName: "standard:household",
    kind: MAP_KIND.GROUP
  }
]);

const GROUP_SORT_PRIORITY = Object.freeze({
  [GROUP_IDS.INDIVIDUALS]: 0,
  [GROUP_IDS.FAMILY]: 1
});

const sortTopLevelGroupNodes = (groupNodes = []) =>
  [...groupNodes].sort((leftNode, rightNode) => {
    const leftPriority =
      GROUP_SORT_PRIORITY[leftNode.id] ?? Number.MAX_SAFE_INTEGER;
    const rightPriority =
      GROUP_SORT_PRIORITY[rightNode.id] ?? Number.MAX_SAFE_INTEGER;

    if (leftPriority !== rightPriority) {
      return leftPriority - rightPriority;
    }

    if (leftPriority < Number.MAX_SAFE_INTEGER) {
      return 0;
    }

    return String(leftNode.label || "").localeCompare(
      String(rightNode.label || ""),
      undefined,
      { sensitivity: "base" }
    );
  });

const DEFAULT_OPEN_IDS = new Set([GROUP_IDS.INDIVIDUALS]);

const PERMANENTLY_HIDDEN_GROUP_IDS = new Set([GROUP_IDS.TRUSTS]);

const LAZY_ACCOUNT_GROUP_IDS = new Set([
  GROUP_IDS.TRUSTS,
  GROUP_IDS.BUSINESSES,
  GROUP_IDS.HOUSEHOLDS
]);

const FAMILY_RELATIONSHIP_RECORD_TYPES = Object.freeze(
  new Set(["Personal_and_Family"])
);

const NETWORK_RELATIONSHIP_RECORD_TYPES = Object.freeze(
  new Set(["COI_Referral", "Service_Provider", "Business"])
);

const NETWORK_GROUP_RECORD_TYPES = Object.freeze([
  "COI_Referral",
  "Service_Provider",
  "Business"
]);

const CLASSIFICATION_GROUP_LABELS = Object.freeze({
  [CLASSIFICATION_VALUES.COI]: "COI",
  [CLASSIFICATION_VALUES.VENDOR]: "Vendor",
  [CLASSIFICATION_VALUES.UNCLASSIFIED]: "Unclassified"
});

const accountHasClassification = (account = {}, classificationValue = "") => {
  const normalizedValue = String(classificationValue || "").trim();

  if (!normalizedValue) {
    return false;
  }

  const classifications = Array.isArray(account.classifications)
    ? account.classifications
    : [];

  return classifications.some(
    (value) =>
      String(value || "")
        .trim()
        .toLowerCase() === normalizedValue.toLowerCase()
  );
};

export const filterAccountsByClassification = (
  accounts = [],
  classificationValue = ""
) => {
  return (accounts || []).filter((account) =>
    accountHasClassification(account, classificationValue)
  );
};

const countNetworkGroupRecords = (children = []) => {
  return (children || []).reduce((total, child) => {
    if (
      child?.isClassificationGroupNode ||
      child?.nodeType === MAP_NODE_TYPE.RELATIONSHIP_GROUP
    ) {
      return total + (child.childCount || child.children?.length || 0);
    }

    if (child?.nodeType === MAP_NODE_TYPE.RELATED_CONTACT) {
      return total + 1;
    }

    if (child?.isAccountNode) {
      return total + 1;
    }

    return total + 1;
  }, 0);
};


const buildClassificationGroupNode = (
  parentGroupId,
  classificationValue,
  accountNodes = []
) => ({
  id: `${parentGroupId}::classification-group::${classificationValue || "Other"}`,
  label:
    CLASSIFICATION_GROUP_LABELS[classificationValue] ||
    classificationValue ||
    "Other",
  sub: "",
  iconName: "standard:account",
  nodeType: MAP_NODE_TYPE.RELATIONSHIP_GROUP,
  isRelationshipGroupNode: true,
  isClassificationGroupNode: true,
  classificationValue: classificationValue || "Other",
  defaultOpen: false,
  children: accountNodes,
  childCount: accountNodes.length,
  recordCount: accountNodes.length
});

const buildClassificationPersonMemberNode = (
  account,
  parentGroupId,
  classificationValue,
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  const accountId = account.accountId || account.id || "";
  const memberNode = buildClientMemberNode(
    account,
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes
  );

  return {
    ...memberNode,
    id: `${parentGroupId}::classification-member::${classificationValue || "Other"}::${accountId}`,
    isClassificationAccountNode: true,
    classificationValue: classificationValue || ""
  };
};

const buildClassificationChildNode = (
  account,
  parentGroupId,
  classificationValue,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  if (isPersonAccountRecord(account)) {
    return buildClassificationPersonMemberNode(
      account,
      parentGroupId,
      classificationValue,
      nestedMemberRelationsByAccountId,
      nestedMemberRelationCountByAccountId,
      memberRelationshipRecordTypes
    );
  }

  return buildClassificationAccountNode(
    account,
    parentGroupId,
    classificationValue,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId,
    memberRelationshipRecordTypes,
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId
  );
};

const buildClassificationAccountNode = (
  account,
  parentGroupId,
  classificationValue,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {}
) => {
  const accountId = account.accountId || account.id || "";
  const memberRelationshipActions = buildMemberRelationshipActions(
    memberRelationshipRecordTypes
  );
  const supportsMemberRelations = memberRelationshipActions.length > 0;
  const presentation = resolveAccountPresentation(account);

  const baseNode = {
    id: `${parentGroupId}::classification-account::${classificationValue || "Other"}::${accountId}`,
    label: account.name || "",
    sub: presentation.sub,
    iconName: presentation.iconName,
    kind: presentation.kind,
    nodeType: MAP_NODE_TYPE.ACCOUNT,
    isAccountNode: true,
    isClassificationAccountNode: true,
    relationId: account.relationId || "",
    accountId,
    classificationValue: classificationValue || "",
    isLazyExpandable: true,
    accountMembersLoaded: false,
    showManageRelatedContacts: supportsMemberRelations,
    showManageMemberRelationships: supportsMemberRelations,
    memberRelationshipActions,
    defaultOpen: false,
    children: []
  };

  if (supportsMemberRelations) {
    return attachMemberRelationsToMemberNode(
      baseNode,
      nestedMemberRelationsByAccountId,
      nestedMemberRelationCountByAccountId,
      memberRelationshipRecordTypes
    );
  }

  return enrichLazyAccountNodeWithMembersOrCount(
    baseNode,
    accountId,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId
  );
};

const buildClassificationAccountChildren = (
  classifiedAccounts = [],
  classificationValue,
  parentGroupId = "",
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  const seenAccountIds = new Set();
  const children = [];

  filterAccountsByClassification(classifiedAccounts, classificationValue).forEach(
    (account) => {
      const accountId = account.accountId || account.id || "";

      if (!accountId || seenAccountIds.has(accountId)) {
        return;
      }

      seenAccountIds.add(accountId);
      children.push(
        buildClassificationChildNode(
          account,
          parentGroupId,
          classificationValue,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId,
          memberRelationshipRecordTypes
        )
      );
    }
  );

  return children;
};

const buildClassificationGroupChildren = (
  parentGroupId,
  classificationValue,
  classifiedAccounts = [],
  accountNodes = null,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  const classificationGroupId = `${parentGroupId}::classification-group::${classificationValue || "Other"}`;
  const children =
    accountNodes ||
    buildClassificationAccountChildren(
      classifiedAccounts,
      classificationValue,
      classificationGroupId,
      nestedMembersByAccountId,
      nestedAccountMemberCountByAccountId,
      nestedMemberRelationsByAccountId,
      nestedMemberRelationCountByAccountId,
      memberRelationshipRecordTypes
    );

  return [
    applyClassificationGroupAction(
      buildClassificationGroupNode(
        parentGroupId,
        classificationValue,
        children
      ),
      classificationValue
    )
  ];
};

export const buildClassificationGroupContactActions = (
  classificationValue
) => {
  const label =
    CLASSIFICATION_GROUP_LABELS[classificationValue] ||
    classificationValue ||
    "Account";

  return [
    {
      name: `${MANAGE_CLASSIFICATION_ACTION_PREFIX}${classificationValue}`,
      label: `Manage ${label}`,
      classificationValue
    }
  ];
};

const applyClassificationGroupAction = (node, classificationValue) => {
  const classificationGroupContactActions =
    buildClassificationGroupContactActions(classificationValue);

  return {
    ...node,
    showClassificationGroupAction: classificationGroupContactActions.length > 0,
    classificationGroupContactActions,
    classificationValue
  };
};

const buildCoiClassificationGroupChildren = (
  classifiedAccounts = [],
  clientAccountIds = new Set(),
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) =>
  buildClassificationGroupChildren(
    GROUP_IDS.NETWORK,
    CLASSIFICATION_VALUES.COI,
    filterAccountsByClassification(classifiedAccounts, CLASSIFICATION_VALUES.COI).filter(
      (account) => !clientAccountIds.has(account.accountId)
    ),
    null,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId,
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes
  );

const countCoiGroupRecords = (
  classifiedAccounts = [],
  clientAccountIds = new Set()
) =>
  filterAccountsByClassification(classifiedAccounts, CLASSIFICATION_VALUES.COI).filter(
    (account) => !clientAccountIds.has(account.accountId)
  ).length;

const buildClientAccountIdSet = (
  clientPersonAccounts = [],
  clientEntityAccounts = []
) =>
  new Set(
    [...clientPersonAccounts, ...clientEntityAccounts]
      .map((account) => account.accountId)
      .filter(Boolean)
  );

const excludeClientAccountNodes = (nodes = [], clientAccountIds = new Set()) =>
  (nodes || []).filter((node) => !clientAccountIds.has(node.accountId));

const buildHouseholdNetworkChildren = (
  clientPersonAccounts = [],
  clientEntityAccounts = [],
  nestedMemberRelationsByAccountId = {},
  classifiedAccounts = [],
  networkCardsLoaded = false,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  const clientAccountIds = buildClientAccountIdSet(
    clientPersonAccounts,
    clientEntityAccounts
  );
  const coiGroupNodes = buildCoiClassificationGroupChildren(
    classifiedAccounts,
    clientAccountIds,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId,
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes
  );
  const coiClassifiedIds = new Set(
    (coiGroupNodes[0]?.children || [])
      .map((accountNode) => accountNode.accountId)
      .filter(Boolean)
  );
  const members = [...clientPersonAccounts, ...clientEntityAccounts];
  const networkCards = excludeClientAccountNodes(
    networkCardsLoaded
      ? buildHouseholdNetworkCards(
          members,
          nestedMemberRelationsByAccountId
        ).filter((card) => !coiClassifiedIds.has(card.accountId))
      : [],
    clientAccountIds
  );

  return [...coiGroupNodes, ...networkCards];
};

const PERSONAL_AND_FAMILY_RECORD_TYPE = "Personal_and_Family";

export { normalizeAccountRelationRecordTypeDeveloperName } from "c/fscRelUtils";
export {
  isExcludedMemberRelationshipRecordType,
  isReadOnlyMemberRelationshipRecordType,
  MEMBER_RELATIONSHIP_GROUP_LABELS,
  resolveMemberRelationshipRecordTypeLabel,
  resolveMemberRelationshipCollectionLabel,
  buildMemberRelationshipActionLabel,
  buildMemberRelationshipModalTitle,
  buildReadOnlyMemberRelationshipInstruction,
  buildReadOnlyMemberRelationshipEmptyState
} from "c/fscRelUtils";

export const isFamilyRelationshipRecordType = (recordTypeDeveloperName) => {
  const developerName = normalizeAccountRelationRecordTypeDeveloperName(
    recordTypeDeveloperName
  );
  return FAMILY_RELATIONSHIP_RECORD_TYPES.has(developerName);
};

export const isNetworkRelationshipRecordType = (recordTypeDeveloperName) => {
  const developerName = normalizeAccountRelationRecordTypeDeveloperName(
    recordTypeDeveloperName
  );
  return NETWORK_RELATIONSHIP_RECORD_TYPES.has(developerName);
};

const shouldShowMemberRelatedToSubline = (
  recordTypeDeveloperName,
  parentMember = {},
  inverseRoleLabel = "",
  memberRoleLabel = ""
) => {
  const resolvedRecordType =
    normalizeAccountRelationRecordTypeDeveloperName(recordTypeDeveloperName) ||
    "";
  const parentAccountId = String(parentMember.accountId || "").trim();
  const parentName = String(parentMember.label || "").trim();

  return (
    (isFamilyRelationshipRecordType(resolvedRecordType) ||
      isNetworkRelationshipRecordType(resolvedRecordType)) &&
    Boolean(
      parentAccountId &&
        parentName &&
        (inverseRoleLabel || memberRoleLabel)
    )
  );
};

export const buildFamilyGroupContactActions = (
  memberRelationshipRecordTypes = []
) => {
  const recordType = (memberRelationshipRecordTypes || []).find(
    (entry) => entry?.developerName === PERSONAL_AND_FAMILY_RECORD_TYPE
  );

  if (!recordType) {
    return [];
  }

  return [
    {
      name: `manageaar:${recordType.developerName}`,
      label: buildMemberRelationshipActionLabel(recordType),
      recordTypeDeveloperName: recordType.developerName,
      recordTypeLabel: recordType.label,
      reciprocalRoleRecordTypeDeveloperName:
        recordType.reciprocalRoleRecordTypeDeveloperName ||
        recordType.developerName
    }
  ];
};

const applyFamilyGroupContactAction = (
  familyGroup,
  memberRelationshipRecordTypes = []
) => {
  const familyGroupContactActions = buildFamilyGroupContactActions(
    memberRelationshipRecordTypes
  );

  return {
    ...familyGroup,
    showFamilyGroupContactAction: familyGroupContactActions.length > 0,
    familyGroupContactActions
  };
};

export const buildNetworkGroupContactActions = (
  memberRelationshipRecordTypes = []
) => {
  return NETWORK_GROUP_RECORD_TYPES.map((developerName) => {
    const recordType = (memberRelationshipRecordTypes || []).find(
      (entry) => entry?.developerName === developerName
    );

    if (!recordType) {
      return null;
    }

    return {
      name: `manageaar:${recordType.developerName}`,
      label: buildMemberRelationshipActionLabel(recordType),
      recordTypeDeveloperName: recordType.developerName,
      recordTypeLabel: recordType.label,
      reciprocalRoleRecordTypeDeveloperName:
        recordType.reciprocalRoleRecordTypeDeveloperName ||
        recordType.developerName
    };
  }).filter(Boolean);
};

const applyNetworkGroupContactAction = (
  networkGroup,
  memberRelationshipRecordTypes = []
) => {
  const networkGroupContactActions = buildNetworkGroupContactActions(
    memberRelationshipRecordTypes
  );

  return {
    ...networkGroup,
    showNetworkGroupContactAction: networkGroupContactActions.length > 0,
    networkGroupContactActions
  };
};

const resolveRelationshipRole = (relationship = {}) =>
  relationship.inverseRoleLabel ||
  relationship.inverseRole ||
  relationship.roleLabel ||
  relationship.role ||
  "";

const RECORD_TYPE_PRESENTATIONS = Object.freeze({
  Household: {
    iconName: "standard:household",
    kind: MAP_KIND.HOUSEHOLD,
    label: "Household",
    category: "households"
  },
  IndustriesHousehold: {
    iconName: "standard:household",
    kind: MAP_KIND.HOUSEHOLD,
    label: "Household",
    category: "households"
  },
  Business_Account: {
    iconName: "standard:account",
    kind: MAP_KIND.BUSINESS,
    label: "Business",
    category: "businesses"
  },
  PersonAccount: {
    iconName: "standard:contact",
    kind: MAP_KIND.PERSON,
    label: "Contact",
    category: "households"
  },
  Person_Account: {
    iconName: "standard:contact",
    kind: MAP_KIND.PERSON,
    label: "Contact",
    category: "households"
  }
});

const PERSON_ACCOUNT_RECORD_TYPE_DEVELOPER_NAMES = new Set([
  "PersonAccount",
  "Person_Account"
]);

const isPersonAccountRecord = (account = {}) => {
  if (account.isPersonAccount === true) {
    return true;
  }

  const developerName = String(account.recordTypeDeveloperName || "").trim();
  return PERSON_ACCOUNT_RECORD_TYPE_DEVELOPER_NAMES.has(developerName);
};

const formatRecordTypeLabel = (developerName) => {
  return String(developerName || "")
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .trim();
};

const resolveMemberRelationshipGroupLabel = (
  recordTypeDeveloperName,
  memberRelationshipRecordTypes = []
) => {
  const developerName = String(recordTypeDeveloperName || "").trim() || "Other";
  const matchedType = (memberRelationshipRecordTypes || []).find(
    (recordType) => recordType.developerName === developerName
  );

  return (
    resolveMemberRelationshipRecordTypeLabel(
      developerName,
      matchedType?.label
    ) || formatRecordTypeLabel(developerName)
  );
};

const resolveRelationshipGroupIconName = (recordTypeDeveloperName) => {
  if (isFamilyRelationshipRecordType(recordTypeDeveloperName)) {
    return "standard:groups";
  }

  return resolveRecordTypePresentation(recordTypeDeveloperName).iconName;
};

const resolveRelatedContactPresentation = (relationship = {}) => {
  const presentation = resolveRecordTypePresentation(
    relationship.relatedAccountRecordTypeDeveloperName
  );

  return {
    iconName: presentation.iconName,
    kind: presentation.kind
  };
};

const resolveRelatedContactSub = (relationship = {}, roleLabel = "") => {
  const relatedRecordType = String(
    relationship.relatedAccountRecordTypeDeveloperName || ""
  ).trim();

  if (
    !relatedRecordType ||
    PERSON_ACCOUNT_RECORD_TYPE_DEVELOPER_NAMES.has(relatedRecordType)
  ) {
    return roleLabel;
  }

  return (
    resolveRecordTypePresentation(relatedRecordType).label || roleLabel
  );
};

const buildRelationshipGroupNode = (
  memberNodeId,
  recordTypeDeveloperName,
  recordTypeLabel,
  contactNodes = []
) => ({
  id: `${memberNodeId}::relationship-group::${recordTypeDeveloperName || "Other"}`,
  label: recordTypeLabel,
  sub: "",
  iconName: resolveRelationshipGroupIconName(recordTypeDeveloperName),
  nodeType: MAP_NODE_TYPE.RELATIONSHIP_GROUP,
  isRelationshipGroupNode: true,
  recordTypeDeveloperName: recordTypeDeveloperName || "Other",
  defaultOpen: true,
  children: contactNodes,
  childCount: contactNodes.length
});

const dedupeRelationshipLinks = (links = []) => {
  const seenKeys = new Set();

  return (links || []).filter((link) => {
    const key =
      String(link.relationId || "").trim() ||
      `${link.relatedToAccountId}-${link.relatedToInverseRole}-${link.relationshipRole}`;

    if (seenKeys.has(key)) {
      return false;
    }

    seenKeys.add(key);
    return true;
  });
};

export const buildGroupedMemberRelationNodes = (
  rawRelationships = [],
  memberNode = {},
  memberRelationshipRecordTypes = []
) => {
  const memberNodeId = memberNode.id || "member";
  const viewModels = buildMemberAccountRelationshipViewModels(rawRelationships);
  if (!viewModels.length) {
    return [];
  }

  const contactsByRecordType = new Map();

  viewModels.forEach((relationship) => {
    const recordTypeDeveloperName =
      normalizeAccountRelationRecordTypeDeveloperName(
        relationship.recordTypeDeveloperName
      ) || "Other";

    if (isExcludedMemberRelationshipRecordType(recordTypeDeveloperName)) {
      return;
    }

    if (!contactsByRecordType.has(recordTypeDeveloperName)) {
      contactsByRecordType.set(recordTypeDeveloperName, []);
    }

    contactsByRecordType.get(recordTypeDeveloperName).push(
      buildContactRelationNode(
        relationship,
        memberNode,
        recordTypeDeveloperName,
        {
          showFamilyRelatedTo: false
        }
      )
    );
  });

  const orderedRecordTypes = [];
  const seenRecordTypes = new Set();

  (memberRelationshipRecordTypes || []).forEach((recordType) => {
    const developerName = recordType?.developerName;

    if (
      !developerName ||
      !contactsByRecordType.has(developerName) ||
      seenRecordTypes.has(developerName)
    ) {
      return;
    }

    seenRecordTypes.add(developerName);
    orderedRecordTypes.push(developerName);
  });

  [...contactsByRecordType.keys()]
    .sort((first, second) => first.localeCompare(second))
    .forEach((developerName) => {
      if (
        !seenRecordTypes.has(developerName) &&
        !isExcludedMemberRelationshipRecordType(developerName)
      ) {
        orderedRecordTypes.push(developerName);
      }
    });

  return orderedRecordTypes.map((recordTypeDeveloperName) => {
    const contacts = consolidateContactRelationNodes(
      contactsByRecordType.get(recordTypeDeveloperName) || []
    );

    return buildRelationshipGroupNode(
      memberNodeId,
      recordTypeDeveloperName,
      resolveMemberRelationshipGroupLabel(
        recordTypeDeveloperName,
        memberRelationshipRecordTypes
      ),
      contacts
    );
  });
};

const resolveRecordTypePresentation = (recordTypeDeveloperName) => {
  const developerName = String(recordTypeDeveloperName || "").trim();

  if (!developerName) {
    return {
      iconName: "standard:account",
      kind: MAP_KIND.HOUSEHOLD,
      label: "Account",
      category: "households"
    };
  }

  const exactMatch = RECORD_TYPE_PRESENTATIONS[developerName];
  if (exactMatch) {
    return exactMatch;
  }

  const normalizedDeveloperName = developerName.toLowerCase();

  if (normalizedDeveloperName.includes("trust")) {
    return {
      iconName: "standard:contract",
      kind: MAP_KIND.TRUST,
      label: "Trust",
      category: "trusts"
    };
  }

  if (normalizedDeveloperName.includes("business")) {
    return {
      iconName: "standard:account",
      kind: MAP_KIND.BUSINESS,
      label: "Business",
      category: "businesses"
    };
  }

  if (normalizedDeveloperName.includes("retirement")) {
    return {
      iconName: "standard:investment_account",
      kind: MAP_KIND.BUSINESS,
      label: "Retirement Plan",
      category: "businesses"
    };
  }

  if (normalizedDeveloperName.includes("household")) {
    return {
      iconName: "standard:household",
      kind: MAP_KIND.HOUSEHOLD,
      label: "Household",
      category: "households"
    };
  }

  return {
    iconName: "standard:account",
    kind: MAP_KIND.HOUSEHOLD,
    label: formatRecordTypeLabel(developerName),
    category: "households"
  };
};

const formatAccountSub = (account = {}, presentation = {}) => {
  const recordTypeLabel =
    String(account.recordTypeLabel || "").trim() || presentation.label || "";
  const roleLabels = (Array.isArray(account.roles) ? account.roles : [])
    .map((role) => String(role || "").trim())
    .filter(Boolean);

  if (!recordTypeLabel) {
    return roleLabels.join(" · ");
  }

  if (!roleLabels.length) {
    return recordTypeLabel;
  }

  return [recordTypeLabel, ...roleLabels].join(" · ");
};

const resolveRoleSubline = (account = {}) => {
  return (Array.isArray(account.roles) ? account.roles : [])
    .map((role) => String(role || "").trim())
    .filter(Boolean)
    .join(" · ");
};

const resolveAccountPresentation = (account = {}) => {
  if (isPersonAccountRecord(account)) {
    return {
      iconName: "standard:contact",
      kind: MAP_KIND.PERSON,
      sub: resolveRoleSubline(account)
    };
  }

  const presentation = resolveRecordTypePresentation(
    account.recordTypeDeveloperName
  );

  return {
    iconName: presentation.iconName,
    kind: presentation.kind,
    sub: formatAccountSub(account, presentation)
  };
};

const resolveCategoryKeyForGroup = (groupId) => {
  if (groupId === GROUP_IDS.TRUSTS) {
    return "trusts";
  }

  if (groupId === GROUP_IDS.BUSINESSES) {
    return "businesses";
  }

  if (groupId === GROUP_IDS.HOUSEHOLDS) {
    return "households";
  }

  return null;
};

const enrichLazyAccountNodeWithMembersOrCount = (
  node,
  accountId,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {}
) => {
  const nestedMembers = nestedMembersByAccountId[accountId];

  if (Array.isArray(nestedMembers)) {
    return {
      ...node,
      children: buildNestedMemberNodes(nestedMembers),
      memberCount: nestedMembers.length,
      accountMembersLoaded: true,
      accountMemberCountLoaded: true
    };
  }

  const pendingCount = nestedAccountMemberCountByAccountId[accountId];
  if (pendingCount != null) {
    return {
      ...node,
      memberCount: pendingCount,
      accountMemberCountLoaded: true,
      accountMembersLoaded: false
    };
  }

  return node;
};

const buildLazyAccountNode = (
  account,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {}
) => {
  const node = buildAccountNode(account, { memberRelationshipRecordTypes });

  if (node.showManageMemberRelationships) {
    return attachMemberRelationsToMemberNode(
      node,
      nestedMemberRelationsByAccountId,
      nestedMemberRelationCountByAccountId,
      memberRelationshipRecordTypes
    );
  }

  return enrichLazyAccountNodeWithMembersOrCount(
    node,
    account.accountId,
    nestedMembersByAccountId,
    nestedAccountMemberCountByAccountId
  );
};

const buildAccountNodesForCategory = (
  accounts,
  nestedMembersByAccountId,
  nestedAccountMemberCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {}
) => {
  return accounts.map((account) =>
    buildLazyAccountNode(
      account,
      nestedMembersByAccountId,
      nestedAccountMemberCountByAccountId,
      memberRelationshipRecordTypes,
      nestedMemberRelationsByAccountId,
      nestedMemberRelationCountByAccountId
    )
  );
};

const mergeLeadProspectAccounts = (
  leadProspectAccounts = [],
  relatedAccounts = []
) => {
  const leadProspectByAccountId = new Map();

  leadProspectAccounts.forEach((account) => {
    if (account.accountId) {
      leadProspectByAccountId.set(account.accountId, account);
    }
  });

  relatedAccounts.forEach((account) => {
    if (!account.accountId || leadProspectByAccountId.has(account.accountId)) {
      return;
    }

    if (!isLeadProspectAccount(account)) {
      return;
    }

    leadProspectByAccountId.set(account.accountId, account);
  });

  return [...leadProspectByAccountId.values()];
};

const categorizeRelatedAccount = (account) => {
  const developerName = String(account.recordTypeDeveloperName || "").trim();

  if (developerName) {
    return resolveRecordTypePresentation(developerName).category;
  }

  const name = String(account.name || "").toLowerCase();

  if (name.includes("trust")) {
    return "trusts";
  }

  if (name.includes(" llc") || name.includes(" inc")) {
    return "businesses";
  }

  return "households";
};

const buildMemberRelationshipActions = (memberRelationshipRecordTypes = []) =>
  (memberRelationshipRecordTypes || [])
    .filter(
      (recordType) =>
        !isExcludedMemberRelationshipRecordType(recordType.developerName)
    )
    .map((recordType) => ({
      name: `manageaar:${recordType.developerName}`,
      label: buildMemberRelationshipActionLabel(recordType),
      recordTypeDeveloperName: recordType.developerName,
      recordTypeLabel: recordType.label,
      reciprocalRoleRecordTypeDeveloperName:
        recordType.reciprocalRoleRecordTypeDeveloperName ||
        recordType.developerName
    }));

const buildAccountNode = (
  account,
  { memberRelationshipRecordTypes = [] } = {}
) => {
  const presentation = resolveAccountPresentation(account);
  const memberRelationshipActions = buildMemberRelationshipActions(
    memberRelationshipRecordTypes
  );
  const supportsMemberRelations = memberRelationshipActions.length > 0;

  return {
    id: `account-${account.relationId || account.id}`,
    label: account.name || "",
    sub: presentation.sub,
    iconName: presentation.iconName,
    kind: presentation.kind,
    nodeType: MAP_NODE_TYPE.ACCOUNT,
    isAccountNode: true,
    relationId: account.relationId || "",
    accountId: account.accountId || "",
    isLazyExpandable: true,
    accountMembersLoaded: false,
    showManageRelatedContacts: supportsMemberRelations,
    showManageMemberRelationships: supportsMemberRelations,
    memberRelationshipActions,
    defaultOpen: false,
    children: []
  };
};
const buildMemberNode = (
  member,
  { supportsMemberRelations = true, memberRelationshipRecordTypes = [] } = {}
) => {
  const memberRelationshipActions = supportsMemberRelations
    ? buildMemberRelationshipActions(memberRelationshipRecordTypes)
    : [];

  return {
    id: `member-${member.relationId || member.id}`,
    label: member.name || "",
    sub: "",
    iconName: "standard:contact",
    kind: MAP_KIND.PERSON,
    nodeType: MAP_NODE_TYPE.MEMBER,
    isMemberNode: true,
    relationId: member.relationId || "",
    accountId: member.accountId || "",
    contactId: member.contactId || "",
    isPrimaryMember: Boolean(member.isPrimaryMember),
    isLazyExpandable: supportsMemberRelations,
    showManageRelatedContacts: supportsMemberRelations,
    showManageMemberRelationships: supportsMemberRelations,
    memberRelationshipActions,
    defaultOpen: false,
    children: []
  };
};

const resolveMemberRoleLabel = (relationship = {}) =>
  String(relationship.roleLabel || relationship.role || "").trim();

const resolveInverseRoleLabel = (relationship = {}) =>
  String(
    relationship.inverseRoleLabel || relationship.inverseRole || ""
  ).trim();

export const buildContactRelationNode = (
  relationship,
  parentMember = {},
  recordTypeDeveloperName = "",
  options = {}
) => {
  const { showFamilyRelatedTo = true } = options;
  const memberRoleLabel = resolveMemberRoleLabel(relationship);
  const inverseRoleLabel = resolveInverseRoleLabel(relationship);
  const roleLabel =
    inverseRoleLabel ||
    memberRoleLabel ||
    resolveRelationshipRole(relationship);
  const resolvedRecordType =
    recordTypeDeveloperName || relationship.recordTypeDeveloperName || "";
  const parentAccountId = String(parentMember.accountId || "").trim();
  const parentName = String(parentMember.label || "").trim();
  const useRelatedToSubline =
    showFamilyRelatedTo &&
    shouldShowMemberRelatedToSubline(
      resolvedRecordType,
      parentMember,
      inverseRoleLabel,
      memberRoleLabel
    );
  const relatedPresentation = resolveRelatedContactPresentation(relationship);
  const roleOrTypeSub = resolveRelatedContactSub(relationship, roleLabel);

  return {
    id: `related-account-${relationship.relationId || relationship.relatedAccountId || relationship.relatedContactId}`,
    label:
      relationship.relatedAccountName ||
      relationship.relatedContactName ||
      "Related person account",
    sub: useRelatedToSubline ? "" : roleOrTypeSub,
    iconName: relatedPresentation.iconName,
    kind: relatedPresentation.kind,
    nodeType: MAP_NODE_TYPE.RELATED_CONTACT,
    isRelatedContactNode: true,
    relationId: relationship.relationId || "",
    contactId: relationship.relatedContactId || "",
    accountId:
      relationship.relatedAccountId ||
      relationship.relatedContactAccountId ||
      "",
    showRelatedToSubline: useRelatedToSubline,
    relatedToAccountId: useRelatedToSubline ? parentAccountId : "",
    relatedToName: useRelatedToSubline ? parentName : "",
    relatedToInverseRole: useRelatedToSubline ? inverseRoleLabel : "",
    relationshipRole: useRelatedToSubline ? memberRoleLabel : "",
    defaultOpen: false,
    children: []
  };
};

const buildRelationshipLink = (node) => ({
  id:
    node.relationId ||
    `${node.relatedToAccountId}-${node.relatedToInverseRole}-${node.relationshipRole}`,
  relationId: node.relationId || "",
  relatedToAccountId: node.relatedToAccountId || "",
  relatedToName: node.relatedToName || "",
  relatedToInverseRole: node.relatedToInverseRole || "",
  relationshipRole: node.relationshipRole || ""
});

const collectUniqueRoleLabels = (nodes = []) =>
  [
    ...new Set(
      (nodes || [])
        .map((node) => String(node.sub || "").trim())
        .filter(Boolean)
    )
  ].sort((first, second) =>
    first.localeCompare(second, undefined, {
      sensitivity: "base"
    })
  );

const hasRelatedToSublineData = (node) =>
  Boolean(
    String(node?.relatedToName || "").trim() &&
    String(node?.relatedToAccountId || "").trim() &&
    (String(node?.relatedToInverseRole || "").trim() ||
      String(node?.relationshipRole || "").trim())
  );

export const countUniqueRelatedContactsFromRelationships = (
  rawRelationships = []
) => {
  const uniqueKeys = new Set();

  (rawRelationships || []).forEach((relationship) => {
    const key =
      String(relationship?.relatedAccountId || "").trim() ||
      String(relationship?.relatedContactAccountId || "").trim() ||
      String(relationship?.relatedContactId || "").trim();

    if (key) {
      uniqueKeys.add(key);
    }
  });

  return uniqueKeys.size;
};

export const consolidateContactRelationNodes = (nodes = []) => {
  const groupedByContact = new Map();

  nodes.forEach((node) => {
    const key =
      String(node.accountId || "").trim() ||
      String(node.contactId || "").trim() ||
      node.id;

    if (!groupedByContact.has(key)) {
      groupedByContact.set(key, []);
    }

    groupedByContact.get(key).push(node);
  });

  return [...groupedByContact.values()]
    .map((group) => {
      if (group.length === 1) {
        const node = group[0];

        if (!hasRelatedToSublineData(node)) {
          return node;
        }

        return {
          ...node,
          showRelatedToSubline: false,
          showRelationshipLinks: true,
          relationshipLinks: [buildRelationshipLink(node)]
        };
      }

      const [primary] = group;
      const relationshipLinks = dedupeRelationshipLinks(
        group
          .filter(hasRelatedToSublineData)
          .map(buildRelationshipLink)
          .sort((first, second) =>
            (first.relatedToName || "").localeCompare(
              second.relatedToName || "",
              undefined,
              {
                sensitivity: "base"
              }
            )
          )
      );
      const roleLabels = collectUniqueRoleLabels(group);
      const accountId = String(primary.accountId || "").trim();

      return {
        ...primary,
        id: accountId ? `related-account-${accountId}` : primary.id,
        relationId: primary.relationId || "",
        showRelatedToSubline: false,
        showRelationshipLinks: relationshipLinks.length > 0,
        relationshipLinks,
        relatedToAccountId: "",
        relatedToName: "",
        relationshipRole: "",
        relatedToInverseRole: "",
        roleLabels:
          relationshipLinks.length || roleLabels.length <= 1
            ? undefined
            : roleLabels,
        sub: relationshipLinks.length
          ? ""
          : roleLabels.length === 1
            ? roleLabels[0]
            : roleLabels.length > 1
              ? ""
              : primary.sub
      };
    })
    .sort((first, second) =>
      (first.label || "").localeCompare(second.label || "", undefined, {
        sensitivity: "base"
      })
    );
};

const buildMemberRelationNodes = (rawRelationships = []) => {
  return buildMemberAccountRelationshipViewModels(rawRelationships).map(
    (relationship) =>
      buildContactRelationNode(
        relationship,
        {},
        relationship.recordTypeDeveloperName || ""
      )
  );
};

const buildParentMemberContext = (member = {}) => ({
  id: `member-${member.relationId || member.accountId || member.id || "member"}`,
  label: member.name || "",
  accountId: member.accountId || "",
  contactId: member.contactId || ""
});

export const buildHouseholdFamilyCards = (
  members = [],
  nestedMemberRelationsByAccountId = {}
) => {
  const cards = [];

  members.forEach((member) => {
    const accountId = member.accountId;

    if (!accountId) {
      return;
    }

    const relations = nestedMemberRelationsByAccountId[accountId];

    if (!Array.isArray(relations)) {
      return;
    }

    const parentMember = buildParentMemberContext(member);

    buildMemberAccountRelationshipViewModels(relations)
      .filter((relationship) =>
        isFamilyRelationshipRecordType(relationship.recordTypeDeveloperName)
      )
      .forEach((relationship) => {
        cards.push(
          buildContactRelationNode(
            relationship,
            parentMember,
            relationship.recordTypeDeveloperName
          )
        );
      });
  });

  return consolidateContactRelationNodes(cards);
};

export const buildHouseholdNetworkCards = (
  members = [],
  nestedMemberRelationsByAccountId = {}
) => {
  const cards = [];

  members.forEach((member) => {
    const accountId = member.accountId;

    if (!accountId) {
      return;
    }

    const relations = nestedMemberRelationsByAccountId[accountId];

    if (!Array.isArray(relations)) {
      return;
    }

    const parentMember = buildParentMemberContext(member);

    buildMemberAccountRelationshipViewModels(relations)
      .filter((relationship) =>
        isNetworkRelationshipRecordType(relationship.recordTypeDeveloperName)
      )
      .forEach((relationship) => {
        cards.push(
          buildContactRelationNode(
            relationship,
            parentMember,
            relationship.recordTypeDeveloperName
          )
        );
      });
  });

  return consolidateContactRelationNodes(cards);
};

const areAllMemberRelationsLoaded = (
  members = [],
  nestedMemberRelationsByAccountId = {}
) => {
  if (!members.length) {
    return false;
  }

  return members.every((member) => {
    const accountId = member.accountId;

    return (
      accountId && Array.isArray(nestedMemberRelationsByAccountId[accountId])
    );
  });
};

const attachMemberRelationsToMemberNode = (
  memberNode,
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = []
) => {
  const accountId = memberNode.accountId;
  if (!accountId) {
    return memberNode;
  }

  const relations = nestedMemberRelationsByAccountId[accountId];
  if (Array.isArray(relations)) {
    const relationGroups = buildGroupedMemberRelationNodes(
      relations,
      memberNode,
      memberRelationshipRecordTypes
    );
    const relatedContactCount = relationGroups.reduce(
      (total, group) => total + (group.children?.length || 0),
      0
    );

    return {
      ...memberNode,
      children: relationGroups,
      relatedContactCount,
      memberRelationsLoaded: true,
      memberRelationCountLoaded: true
    };
  }

  const relatedContactCount = nestedMemberRelationCountByAccountId[accountId];
  const memberRelationCountLoaded = relatedContactCount != null;

  return {
    ...memberNode,
    memberRelationsLoaded: false,
    memberRelationCountLoaded,
    relatedContactCount: memberRelationCountLoaded
      ? relatedContactCount
      : undefined
  };
};

const buildNestedMemberNodes = (
  rawMembers = [],
  memberRelationshipRecordTypes = []
) => {
  return buildMemberViewModels(rawMembers).map((member) =>
    buildMemberNode(member, {
      supportsMemberRelations: false,
      memberRelationshipRecordTypes
    })
  );
};

const buildGroupNode = (definition, children) => ({
  id: definition.id,
  label: definition.label,
  sub: "",
  iconName: definition.iconName,
  kind: definition.kind,
  nodeType: MAP_NODE_TYPE.GROUP,
  defaultOpen: DEFAULT_OPEN_IDS.has(definition.id),
  children
});

export const buildPersonCentricMapTree = ({
  personTreeData,
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  householdFamilyRecordCount = undefined
} = {}) => {
  if (!personTreeData?.members?.length) {
    return null;
  }

  const personMember = personTreeData.members[0];
  const memberViewModels = buildMemberViewModels([personMember]);
  const memberNode = attachMemberRelationsToMemberNode(
    buildMemberNode(personMember, {
      supportsMemberRelations: true,
      memberRelationshipRecordTypes
    }),
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes
  );
  const familyCardsLoaded = areAllMemberRelationsLoaded(
    memberViewModels,
    nestedMemberRelationsByAccountId
  );
  const familyCards = familyCardsLoaded
    ? buildHouseholdFamilyCards(
        memberViewModels,
        nestedMemberRelationsByAccountId
      )
    : [];
  const familyGroup = buildGroupNode(
    {
      id: `${memberNode.id}::${GROUP_IDS.FAMILY}`,
      label: "Family and Friends",
      iconName: "standard:groups",
      kind: MAP_KIND.GROUP
    },
    familyCards
  );

  familyGroup.isLazyFamilyGroup = true;
  familyGroup.familyCardsLoaded = familyCardsLoaded;
  familyGroup.recordCount = familyCardsLoaded
    ? familyCards.length
    : householdFamilyRecordCount;

  return {
    ...memberNode,
    defaultOpen: true,
    children: [
      applyFamilyGroupContactAction(familyGroup, memberRelationshipRecordTypes),
      ...(memberNode.children || [])
    ]
  };
};

const buildClientMemberNode = (
  account,
  nestedMemberRelationsByAccountId,
  nestedMemberRelationCountByAccountId,
  memberRelationshipRecordTypes
) =>
  attachMemberRelationsToMemberNode(
    buildMemberNode(
      {
        relationId: account.relationId || account.id,
        accountId: account.accountId,
        contactId: account.contactId,
        name: account.name,
        roles: account.roles || [],
        isPrimaryMember: Boolean(account.isPrimaryMember)
      },
      { memberRelationshipRecordTypes }
    ),
    nestedMemberRelationsByAccountId,
    nestedMemberRelationCountByAccountId,
    memberRelationshipRecordTypes
  );

export const buildMapTree = ({
  treeData,
  nestedMembersByAccountId = {},
  nestedAccountMemberCountByAccountId = {},
  nestedMemberRelationsByAccountId = {},
  nestedMemberRelationCountByAccountId = {},
  memberRelationshipRecordTypes = [],
  loadedGroupIds = {},
  householdFamilyRecordCount = undefined,
  householdNetworkRecordCount = undefined
} = {}) => {
  if (!treeData) {
    return null;
  }

  const relatedAccounts = buildAccountViewModels(
    treeData.relatedAccounts || []
  );
  const clientAccounts = buildAccountViewModels(treeData.clientAccounts || []).filter(
    (account) => isHouseholdMapClientAccount(account)
  );
  const clientPersonAccounts = clientAccounts.filter(
    (account) => account.isPersonAccount
  );
  const clientEntityAccounts = clientAccounts.filter(
    (account) => !account.isPersonAccount
  );
  const classifiedAccounts = buildAccountViewModels(
    treeData.classifiedAccounts || []
  );
  const leadProspectAccounts = mergeLeadProspectAccounts(
    buildAccountViewModels(treeData.leadProspectAccounts || []).filter((account) =>
      isLeadProspectAccount(account)
    ),
    relatedAccounts
  );
  const leadProspectAccountIds = new Set(
    leadProspectAccounts.map((account) => account.accountId).filter(Boolean)
  );
  const classifiedAccountIds = new Set(
    classifiedAccounts.map((account) => account.accountId).filter(Boolean)
  );
  const categorizedAccounts = {
    trusts: [],
    businesses: [],
    households: []
  };

  relatedAccounts.forEach((account) => {
    if (classifiedAccountIds.has(account.accountId)) {
      return;
    }

    if (leadProspectAccountIds.has(account.accountId)) {
      return;
    }

    if (isPersonAccountRecord(account)) {
      return;
    }

    const category = categorizeRelatedAccount(account);
    categorizedAccounts[category].push(account);
  });

  const groupNodes = GROUP_DEFINITIONS.map((definition) => {
    if (definition.id === GROUP_IDS.INDIVIDUALS) {
      const clientMemberNodes = clientPersonAccounts.map((account) =>
        buildClientMemberNode(
          account,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId,
          memberRelationshipRecordTypes
        )
      );

      const clientAccountNodes = clientEntityAccounts.map((account) =>
        buildLazyAccountNode(
          account,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          memberRelationshipRecordTypes,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId
        )
      );

      return buildGroupNode(definition, [
        ...clientMemberNodes,
        ...clientAccountNodes
      ]);
    }

    if (definition.id === GROUP_IDS.FAMILY) {
      const familyCardsLoaded = areAllMemberRelationsLoaded(
        clientPersonAccounts,
        nestedMemberRelationsByAccountId
      );
      const familyCards = familyCardsLoaded
        ? buildHouseholdFamilyCards(
            clientPersonAccounts,
            nestedMemberRelationsByAccountId
          )
        : [];
      const groupNode = buildGroupNode(definition, familyCards);

      groupNode.isLazyFamilyGroup = true;
      groupNode.familyCardsLoaded = familyCardsLoaded;
      groupNode.recordCount = familyCardsLoaded
        ? familyCards.length
        : householdFamilyRecordCount;

      return applyFamilyGroupContactAction(
        groupNode,
        memberRelationshipRecordTypes
      );
    }

    if (definition.id === GROUP_IDS.LEAD_PROSPECT) {
      const leadProspectPersonAccounts = leadProspectAccounts.filter(
        (account) => account.isPersonAccount
      );
      const leadProspectEntityAccounts = leadProspectAccounts.filter(
        (account) => !account.isPersonAccount
      );
      const leadProspectMemberNodes = leadProspectPersonAccounts.map((account) =>
        buildClientMemberNode(
          account,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId,
          memberRelationshipRecordTypes
        )
      );
      const leadProspectAccountNodes = leadProspectEntityAccounts.map((account) =>
        buildLazyAccountNode(
          account,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          memberRelationshipRecordTypes,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId
        )
      );

      const groupNode = buildGroupNode(definition, [
        ...leadProspectMemberNodes,
        ...leadProspectAccountNodes
      ]);

      groupNode.recordCount = leadProspectAccounts.length;
      groupNode.isLeadProspectGroup = true;
      return groupNode;
    }

    if (definition.id === GROUP_IDS.NETWORK) {
      const networkClientAccounts = [
        ...clientPersonAccounts,
        ...clientEntityAccounts
      ];
      const clientAccountIds = buildClientAccountIdSet(
        clientPersonAccounts,
        clientEntityAccounts
      );
      const networkCardsLoaded = areAllMemberRelationsLoaded(
        networkClientAccounts,
        nestedMemberRelationsByAccountId
      );
      const networkChildren = buildHouseholdNetworkChildren(
        clientPersonAccounts,
        clientEntityAccounts,
        nestedMemberRelationsByAccountId,
        classifiedAccounts,
        networkCardsLoaded,
        nestedMembersByAccountId,
        nestedAccountMemberCountByAccountId,
        nestedMemberRelationCountByAccountId,
        memberRelationshipRecordTypes
      );
      const groupNode = buildGroupNode(definition, networkChildren);

      groupNode.isLazyNetworkGroup = true;
      groupNode.networkCardsLoaded = networkCardsLoaded;
      groupNode.recordCount = networkCardsLoaded
        ? countNetworkGroupRecords(networkChildren)
        : (householdNetworkRecordCount ?? 0) +
          countCoiGroupRecords(classifiedAccounts, clientAccountIds);

      return applyNetworkGroupContactAction(
        groupNode,
        memberRelationshipRecordTypes
      );
    }

    if (definition.id === GROUP_IDS.VENDORS) {
      const vendorAccounts = filterAccountsByClassification(
        classifiedAccounts,
        CLASSIFICATION_VALUES.VENDOR
      );
      const groupNode = buildGroupNode(
        definition,
        buildClassificationAccountChildren(
          classifiedAccounts,
          CLASSIFICATION_VALUES.VENDOR,
          GROUP_IDS.VENDORS,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId,
          memberRelationshipRecordTypes
        )
      );

      groupNode.recordCount = vendorAccounts.length;
      groupNode.isClassificationTopLevelGroup = true;
      return applyClassificationGroupAction(
        groupNode,
        CLASSIFICATION_VALUES.VENDOR
      );
    }

    if (definition.id === GROUP_IDS.UNCLASSIFIED) {
      const unclassifiedAccounts = filterAccountsByClassification(
        classifiedAccounts,
        CLASSIFICATION_VALUES.UNCLASSIFIED
      );
      const groupNode = buildGroupNode(
        definition,
        buildClassificationAccountChildren(
          classifiedAccounts,
          CLASSIFICATION_VALUES.UNCLASSIFIED,
          GROUP_IDS.UNCLASSIFIED,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId,
          memberRelationshipRecordTypes
        )
      );

      groupNode.recordCount = unclassifiedAccounts.length;
      groupNode.isClassificationTopLevelGroup = true;
      return applyClassificationGroupAction(
        groupNode,
        CLASSIFICATION_VALUES.UNCLASSIFIED
      );
    }

    const categoryKey = resolveCategoryKeyForGroup(definition.id);
    if (!categoryKey) {
      return buildGroupNode(definition, []);
    }

    const accounts = categorizedAccounts[categoryKey];
    const recordCount = accounts.length;
    const isGroupLoaded = loadedGroupIds[definition.id] === true;
    const accountNodes = isGroupLoaded
      ? buildAccountNodesForCategory(
          accounts,
          nestedMembersByAccountId,
          nestedAccountMemberCountByAccountId,
          memberRelationshipRecordTypes,
          nestedMemberRelationsByAccountId,
          nestedMemberRelationCountByAccountId
        )
      : [];
    const groupNode = buildGroupNode(definition, accountNodes);
    groupNode.recordCount = recordCount;
    groupNode.isLazyGroup = LAZY_ACCOUNT_GROUP_IDS.has(definition.id);
    groupNode.groupLoaded = isGroupLoaded;
    return groupNode;
  }).filter((groupNode) => {
    if (PERMANENTLY_HIDDEN_GROUP_IDS.has(groupNode.id)) {
      return false;
    }

    if (groupNode.id === GROUP_IDS.FAMILY) {
      return clientPersonAccounts.length > 0;
    }

    if (groupNode.id === GROUP_IDS.NETWORK) {
      return true;
    }

    if (
      groupNode.id === GROUP_IDS.VENDORS ||
      groupNode.id === GROUP_IDS.UNCLASSIFIED ||
      groupNode.id === GROUP_IDS.LEAD_PROSPECT
    ) {
      return true;
    }

    if (groupNode.isLazyGroup) {
      return (groupNode.recordCount || 0) > 0;
    }

    return (groupNode.children || []).length > 0;
  });

  const sortedGroupNodes = sortTopLevelGroupNodes(groupNodes);

  const rootPresentation = resolveAccountPresentation({
    recordTypeDeveloperName: treeData.recordTypeDeveloperName,
    recordTypeLabel: treeData.recordTypeLabel
  });

  return {
    id: `root-${treeData.rootAccountId || "household"}`,
    label: treeData.name || "Household",
    sub: rootPresentation.sub,
    iconName: rootPresentation.iconName,
    kind: rootPresentation.kind,
    nodeType: MAP_NODE_TYPE.ROOT,
    accountId: treeData.rootAccountId || "",
    defaultOpen: true,
    children: sortedGroupNodes
  };
};

export const collectNodeIds = (node, includeRoot = true) => {
  if (!node) {
    return [];
  }

  const ids = includeRoot ? [node.id] : [];

  (node.children || []).forEach((child) => {
    ids.push(...collectNodeIds(child, true));
  });

  return ids;
};

export const collectLazyExpandableMemberAccountIds = (
  node,
  accountIds = []
) => {
  if (!node) {
    return accountIds;
  }

  if (
    (node.nodeType === MAP_NODE_TYPE.MEMBER ||
      (node.nodeType === MAP_NODE_TYPE.ACCOUNT &&
        node.showManageMemberRelationships)) &&
    node.isLazyExpandable &&
    node.accountId
  ) {
    accountIds.push(node.accountId);
  }

  (node.children || []).forEach((child) => {
    collectLazyExpandableMemberAccountIds(child, accountIds);
  });

  return accountIds;
};

const LAZY_GROUP_ID_BY_CATEGORY = Object.freeze({
  trusts: GROUP_IDS.TRUSTS,
  businesses: GROUP_IDS.BUSINESSES,
  households: GROUP_IDS.HOUSEHOLDS
});

export const collectMemberRelationCountAccountIds = (
  node,
  { treeData, loadedGroupIds = {} } = {}
) => {
  const accountIds = new Set(collectLazyExpandableMemberAccountIds(node));

  if (!treeData) {
    return [...accountIds];
  }

  buildAccountViewModels(treeData.clientAccounts || [])
    .filter((account) => account.accountId && !isPersonAccountRecord(account))
    .forEach((account) => accountIds.add(account.accountId));

  if (!treeData.relatedAccounts?.length) {
    return [...accountIds];
  }

  const classifiedAccountIds = new Set(
    buildAccountViewModels(treeData.classifiedAccounts || [])
      .map((account) => account.accountId)
      .filter(Boolean)
  );
  const leadProspectAccountIds = new Set(
    mergeLeadProspectAccounts(
      buildAccountViewModels(treeData.leadProspectAccounts || []).filter(
        (account) => isLeadProspectAccount(account)
      ),
      buildAccountViewModels(treeData.relatedAccounts || [])
    )
      .map((account) => account.accountId)
      .filter(Boolean)
  );

  buildAccountViewModels(treeData.relatedAccounts).forEach((account) => {
    const accountId = account.accountId;

    if (!accountId || isPersonAccountRecord(account)) {
      return;
    }

    if (
      classifiedAccountIds.has(accountId) ||
      leadProspectAccountIds.has(accountId)
    ) {
      return;
    }

    const groupId = LAZY_GROUP_ID_BY_CATEGORY[categorizeRelatedAccount(account)];

    if (groupId && loadedGroupIds[groupId] === true) {
      accountIds.add(accountId);
    }
  });

  return [...accountIds];
};

export const collectLazyExpandableAccountIds = (node, accountIds = []) => {
  if (!node) {
    return accountIds;
  }

  if (
    node.nodeType === MAP_NODE_TYPE.ACCOUNT &&
    node.isLazyExpandable &&
    node.accountId &&
    !node.showManageMemberRelationships
  ) {
    accountIds.push(node.accountId);
  }

  (node.children || []).forEach((child) => {
    collectLazyExpandableAccountIds(child, accountIds);
  });

  return accountIds;
};

export const collectLazyExpandableMemberContactIds = (
  node,
  contactIds = []
) => {
  if (!node) {
    return contactIds;
  }

  if (
    node.nodeType === MAP_NODE_TYPE.MEMBER &&
    node.isLazyExpandable &&
    node.contactId
  ) {
    contactIds.push(node.contactId);
  }

  (node.children || []).forEach((child) => {
    collectLazyExpandableMemberContactIds(child, contactIds);
  });

  return contactIds;
};

export const collectMemberContactIds = (node, contactIds = []) => {
  if (!node) {
    return contactIds;
  }

  if (node.nodeType === MAP_NODE_TYPE.MEMBER && node.contactId) {
    contactIds.push(node.contactId);
  }

  (node.children || []).forEach((child) => {
    collectMemberContactIds(child, contactIds);
  });

  return contactIds;
};

export const createInitialOpenState = (rootNode) => {
  const openState = {};

  collectNodeIds(rootNode).forEach((nodeId) => {
    openState[nodeId] = false;
  });

  const applyDefaults = (node) => {
    if (node.defaultOpen) {
      openState[node.id] = true;
    }

    (node.children || []).forEach((child) => applyDefaults(child));
  };

  applyDefaults(rootNode);
  openState[rootNode.id] = true;
  return openState;
};

const sumRootChildRecordCounts = (childNodes = []) =>
  childNodes.reduce((total, child) => {
    if (child?.nodeType === MAP_NODE_TYPE.GROUP) {
      return total + (child.recordCount ?? child.childCount ?? 0);
    }

    return total + (child.childCount ?? 0);
  }, 0);

export const applyOpenState = (node, openState) => {
  if (!node) {
    return null;
  }

  if (node.nodeType === MAP_NODE_TYPE.RELATIONSHIP_GROUP) {
    if (node.isClassificationGroupNode) {
      const isRequestedOpen =
        openState[node.id] === true ||
        (openState[node.id] !== false && Boolean(node.defaultOpen));
      const children = (node.children || []).map((child) =>
        applyOpenState(child, openState)
      );
      const childCount = children.length;
      const displayCount = node.recordCount ?? childCount;
      const isOpen = isRequestedOpen;

      return {
        ...node,
        isOpen,
        isRequestedOpen,
        children,
        childCount: displayCount,
        childNodeKind: "classificationGroup",
        hasExpandableContent: true,
        showBadge: true,
        badgeLabel:
          displayCount == null
            ? isOpen
              ? "‹"
              : "›"
            : `${displayCount}${isOpen ? " ‹" : " ›"}`,
        chevronIcon: isOpen ? "utility:chevronleft" : "utility:chevronright"
      };
    }

    const children = (node.children || []).map((child) =>
      applyOpenState(child, openState)
    );

    return {
      ...node,
      isOpen: true,
      isRequestedOpen: true,
      children,
      childCount: children.length,
      hasExpandableContent: children.length > 0,
      showBadge: children.length > 0,
      badgeLabel:
        children.length > 0
          ? `${children.length} ›`
          : "",
      chevronIcon: children.length > 0 ? "utility:chevronright" : undefined
    };
  }

  const isRequestedOpen =
    openState[node.id] === true ||
    (openState[node.id] !== false && Boolean(node.defaultOpen));
  const isRootNode = node.nodeType === MAP_NODE_TYPE.ROOT;
  const isAccountNode = node.nodeType === MAP_NODE_TYPE.ACCOUNT;
  const isMemberNode = node.nodeType === MAP_NODE_TYPE.MEMBER;
  const isLazyGroup = Boolean(node.isLazyGroup);
  const isLazyFamilyGroup = Boolean(node.isLazyFamilyGroup);
  const isLazyNetworkGroup = Boolean(node.isLazyNetworkGroup);
  const isClassificationTopLevelGroup = Boolean(node.isClassificationTopLevelGroup);
  const isLeadProspectGroup = Boolean(node.isLeadProspectGroup);
  const isClassificationAccountNode = Boolean(node.isClassificationAccountNode);
  const familyCardsLoaded = node.familyCardsLoaded === true;
  const networkCardsLoaded = node.networkCardsLoaded === true;
  const isLazyExpandable = Boolean(node.isLazyExpandable);
  const isLazyAccountRelations =
    isAccountNode && isLazyExpandable && Boolean(node.showManageMemberRelationships);
  const isLazyAccountMembers =
    isAccountNode && isLazyExpandable && !node.showManageMemberRelationships;
  const isLazyMember = isMemberNode && isLazyExpandable;
  const isLazyAccount = isLazyAccountMembers;
  const isLazyMemberOrAccountRelations = isLazyMember || isLazyAccountRelations;
  const memberRelationsLoaded = node.memberRelationsLoaded === true;
  const memberRelationCountLoaded = node.memberRelationCountLoaded === true;
  const accountMembersLoaded = node.accountMembersLoaded === true;
  const accountMemberCountLoaded = node.accountMemberCountLoaded === true;
  const hasNoMemberRelations =
    memberRelationCountLoaded && (node.relatedContactCount ?? 0) === 0;
  const hasNoAccountMembers =
    accountMembersLoaded && (node.memberCount ?? 0) === 0;
  const isLazyMemberPendingOpen =
    isLazyMemberOrAccountRelations &&
    isRequestedOpen &&
    !memberRelationsLoaded &&
    !hasNoMemberRelations;
  const isLazyAccountPendingOpen =
    isLazyAccount &&
    isRequestedOpen &&
    !accountMembersLoaded &&
    !hasNoAccountMembers;
  const isOpen =
    isLazyMemberOrAccountRelations && isRequestedOpen
      ? memberRelationsLoaded || hasNoMemberRelations || isLazyMemberPendingOpen
      : isLazyAccount && isRequestedOpen
        ? accountMembersLoaded || hasNoAccountMembers || isLazyAccountPendingOpen
        : isRequestedOpen;
  const children = (node.children || []).map((child) =>
    applyOpenState(child, openState)
  );
  const childCount = children.length;
  const accountMemberCount =
    isAccountNode && node.memberCount != null ? node.memberCount : childCount;
  const memberRelatedContactCount = memberRelationsLoaded
    ? (node.relatedContactCount ?? childCount)
    : memberRelationCountLoaded
      ? (node.relatedContactCount ?? 0)
      : null;
  const displayCount = isRootNode
    ? sumRootChildRecordCounts(children)
    : isLazyGroup
    ? node.recordCount || 0
    : isLazyFamilyGroup
      ? familyCardsLoaded
        ? childCount
        : (node.recordCount ?? null)
      : isLazyNetworkGroup
        ? networkCardsLoaded
          ? childCount
          : (node.recordCount ?? null)
        : isClassificationTopLevelGroup
          ? (node.recordCount ?? childCount)
          : isLeadProspectGroup
            ? (node.recordCount ?? childCount)
        : isLazyAccountRelations
          ? memberRelatedContactCount
          : isLazyAccount
            ? accountMembersLoaded
              ? accountMemberCount
              : accountMemberCountLoaded
                ? (node.memberCount ?? 0)
                : null
            : isAccountNode
              ? accountMemberCount
              : isLazyMember
                ? memberRelatedContactCount
                : childCount;
  const hasExpandableContent =
    childCount > 0 ||
    isAccountNode ||
    isLazyExpandable ||
    isLazyGroup ||
    isLazyFamilyGroup ||
    isLazyNetworkGroup ||
    isClassificationTopLevelGroup ||
    isLeadProspectGroup;
  const resolvedSub = node.sub;
  const badgeLabel =
    displayCount == null
      ? isRequestedOpen
        ? "‹"
        : "›"
      : `${displayCount}${isOpen ? " ‹" : " ›"}`;

  return {
    ...node,
    isOpen,
    isRequestedOpen,
    children,
    childCount: displayCount ?? 0,
    hasExpandableContent,
    showManageRelatedContacts: Boolean(node.showManageRelatedContacts),
    sub: resolvedSub,
    badgeLabel,
    showBadge:
      hasExpandableContent &&
      (displayCount != null ||
        isLazyGroup ||
        isLazyFamilyGroup ||
        isLazyNetworkGroup ||
        isClassificationTopLevelGroup ||
        isLeadProspectGroup ||
        (isLazyAccount && !accountMembersLoaded) ||
        (isLazyAccountRelations &&
          !memberRelationCountLoaded &&
          !memberRelationsLoaded) ||
        (isLazyMember && !memberRelationCountLoaded && !memberRelationsLoaded)),
    chevronIcon: isOpen ? "utility:chevronleft" : "utility:chevronright"
  };
};

export const collectWireBusGroups = (node, groups = []) => {
  if (!node || !node.isOpen) {
    return groups;
  }

  (node.children || []).forEach((child) => {
    groups.push({
      parentId: node.id,
      childIds: [child.id],
      dashedChildIds: []
    });

    if (child.nodeType === MAP_NODE_TYPE.RELATIONSHIP_GROUP && !child.isClassificationGroupNode) {
      return;
    }

    collectWireBusGroups(child, groups);
  });

  return groups;
};

export const collectWirePairs = (node, pairs = [], parentId = null) => {
  if (!node) {
    return pairs;
  }

  if (parentId) {
    pairs.push({
      parentId,
      childId: node.id,
      dashed: false
    });
  }

  if (!node.isOpen) {
    return pairs;
  }

  (node.children || []).forEach((child) => {
    collectWirePairs(child, pairs, node.id);
  });

  if (node.showAddTile) {
    pairs.push({
      parentId: node.id,
      childId: node.addTileId,
      dashed: true
    });
  }

  return pairs;
};

export const buildWirePath = ({ x1, y1, x2, y2 }) => {
  const midX = Math.round((x1 + x2) / 2);
  return `M ${x1} ${y1} H ${midX} V ${y2} H ${x2}`;
};

const rectCenterY = (rect) => rect.top + rect.height / 2;

export const buildBusWireSegments = (parentRect, childEntries) => {
  if (!parentRect || !childEntries.length) {
    return [];
  }

  const parentX = Math.round(parentRect.right);
  const parentY = Math.round(rectCenterY(parentRect));

  const childPoints = childEntries
    .map(({ rect, dashed }) => {
      if (!rect) {
        return null;
      }

      return {
        x: Math.round(rect.left),
        y: Math.round(rectCenterY(rect)),
        dashed: Boolean(dashed)
      };
    })
    .filter(Boolean);

  if (!childPoints.length) {
    return [];
  }

  const minChildX = Math.min(...childPoints.map((point) => point.x));
  const busX = Math.round(parentX + (minChildX - parentX) / 2);
  const childYs = childPoints.map((point) => point.y);
  const trunkTop = Math.min(parentY, ...childYs);
  const trunkBottom = Math.max(parentY, ...childYs);

  const segments = [];

  if (childPoints.length === 1) {
    const child = childPoints[0];
    const midX = Math.round(parentX + (child.x - parentX) / 2);
    segments.push({
      d: `M ${parentX} ${parentY} H ${midX} V ${child.y} H ${child.x}`,
      dashed: child.dashed,
      dot: !child.dashed,
      dotX: child.x,
      dotY: child.y
    });
    return segments;
  }

  segments.push({
    d: `M ${parentX} ${parentY} H ${busX}`,
    dashed: false
  });

  if (trunkBottom > trunkTop) {
    segments.push({
      d: `M ${busX} ${trunkTop} V ${trunkBottom}`,
      dashed: false
    });
  }

  childPoints.forEach((child) => {
    segments.push({
      d: `M ${busX} ${child.y} H ${child.x}`,
      dashed: child.dashed,
      dot: !child.dashed,
      dotX: child.x,
      dotY: child.y
    });
  });

  return segments;
};

export const toCanvasRect = (rect, canvasRect) => {
  if (!rect || !canvasRect) {
    return null;
  }

  return {
    top: rect.top - canvasRect.top,
    left: rect.left - canvasRect.left,
    right: rect.right - canvasRect.left,
    bottom: rect.bottom - canvasRect.top,
    width: rect.width,
    height: rect.height
  };
};

export const cloneDomRect = (rect) => {
  if (!rect) {
    return null;
  }

  return {
    top: rect.top,
    left: rect.left,
    right: rect.right,
    bottom: rect.bottom,
    width: rect.width,
    height: rect.height
  };
};

export const findMapNode = (node, nodeId) => {
  if (!node || !nodeId) {
    return null;
  }

  if (node.id === nodeId) {
    return node;
  }

  for (const child of node.children || []) {
    const match = findMapNode(child, nodeId);
    if (match) {
      return match;
    }
  }

  return null;
};

export const findMemberNodeByAccountId = (node, accountId) => {
  if (!node || !accountId) {
    return null;
  }

  if (
    node.accountId === accountId &&
    (node.nodeType === MAP_NODE_TYPE.MEMBER ||
      (node.nodeType === MAP_NODE_TYPE.ACCOUNT &&
        node.showManageMemberRelationships))
  ) {
    return node;
  }

  for (const child of node.children || []) {
    const match = findMemberNodeByAccountId(child, accountId);
    if (match) {
      return match;
    }
  }

  return null;
};

export const findMemberNodeByContactId = (node, contactId) => {
  if (!node || !contactId) {
    return null;
  }

  if (node.nodeType === MAP_NODE_TYPE.MEMBER && node.contactId === contactId) {
    return node;
  }

  for (const child of node.children || []) {
    const match = findMemberNodeByContactId(child, contactId);
    if (match) {
      return match;
    }
  }

  return null;
};

export const MAP_LAYOUT = Object.freeze({
  CARD_WIDTH: 250,
  COLUMN_GAP: 30,
  HORIZONTAL_BUFFER: 32
});

export const computeVisibleMapColumnCount = (node, depth = 1) => {
  if (!node) {
    return 1;
  }

  let maxDepth = depth;

  if (!node.isOpen) {
    return maxDepth;
  }

  (node.children || []).forEach((child) => {
    maxDepth = Math.max(
      maxDepth,
      computeVisibleMapColumnCount(child, depth + 1)
    );
  });

  return maxDepth;
};

export const computeMapCanvasMinWidth = (
  node,
  {
    cardWidth = MAP_LAYOUT.CARD_WIDTH,
    columnGap = MAP_LAYOUT.COLUMN_GAP,
    horizontalBuffer = MAP_LAYOUT.HORIZONTAL_BUFFER
  } = {}
) => {
  const columnCount = computeVisibleMapColumnCount(node);
  const columnsWidth =
    columnCount * cardWidth + Math.max(columnCount - 1, 0) * columnGap;

  return columnsWidth + horizontalBuffer;
};

const ACCOUNT_TYPE_DISPLAY_LABELS = Object.freeze({
  PersonAccount: "Individual",
  Individual: "Individual",
  Business: "Business",
  IndustriesBusiness: "Business",
  Business_Account: "Business",
  Trust: "Trust",
  IndustriesInstitution: "Trust",
  Retirement_Plan: "Retirement Plan",
  Household: "Household",
  IndustriesHousehold: "Household"
});

/**
 * Maps an Account record type to the member-type label used across the relationship map
 * and envelope wizard (e.g. PersonAccount → Individual).
 */
export const resolveAccountTypeDisplayLabel = (
  recordTypeDeveloperName = "",
  recordTypeLabel = ""
) => {
  const developerName = String(recordTypeDeveloperName || "").trim();

  if (developerName && ACCOUNT_TYPE_DISPLAY_LABELS[developerName]) {
    return ACCOUNT_TYPE_DISPLAY_LABELS[developerName];
  }

  const presentation = resolveRecordTypePresentation(developerName);
  if (presentation?.label && presentation.label !== "Account") {
    return presentation.label;
  }

  const label = String(recordTypeLabel || "").trim();
  if (label) {
    return label;
  }

  return formatRecordTypeLabel(developerName) || "Account";
};

/**
 * Builds the account header view model (name, avatar, primary type badge, secondary badges)
 * using the same client/type rules as the relationship map.
 */
export const buildAccountHeaderViewModel = (account = {}) => {
  const name = String(account.name || "").trim();
  const typeLabel = resolveAccountTypeDisplayLabel(
    account.recordTypeDeveloperName,
    account.recordTypeLabel
  );
  const secondaryBadges = [];
  const seen = new Set();

  const addBadge = (label, variant = "outline") => {
    const normalized = String(label || "").trim();
    const key = normalized.toLowerCase();

    if (!normalized || seen.has(key)) {
      return;
    }

    seen.add(key);
    secondaryBadges.push({
      key: `badge-${secondaryBadges.length}`,
      label: normalized,
      variant
    });
  };

  if (isClientAccount(account) || memberHasClientRole(account)) {
    addBadge(CLIENT_ROLE_VALUE);
  }

  if (isLeadProspectAccount(account)) {
    const accountType = String(account.accountType || account.type || "").trim();
    if (accountType) {
      addBadge(accountType);
    }
  }

  buildRoleLabels(account).forEach((role) => {
    if (!isClientRoleValue(role)) {
      addBadge(role);
    }
  });

  const photoUrl = String(account.photoUrl || "").trim();

  return {
    name,
    photoUrl,
    initials: computeInitials(name),
    showPhoto: Boolean(photoUrl),
    primaryTypeLabel: typeLabel,
    secondaryBadges
  };
};