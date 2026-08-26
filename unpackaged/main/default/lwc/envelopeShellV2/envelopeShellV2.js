import { LightningElement, api } from "lwc";
import LightningToast from "lightning/toast";
import getFormSchema from "@salesforce/apex/FieldDetailController.getFormSchema";
import getAllFormSchemas from "@salesforce/apex/FieldDetailController.getAllFormSchemas";
import getSectionLayouts from "@salesforce/apex/FieldDetailController.getSectionLayouts";
import getRecordValuesForType from "@salesforce/apex/FieldDetailController.getRecordValuesForType";
import getOriginalAccountValues from "@salesforce/apex/FieldDetailController.getOriginalAccountValues";
import getCaseValuesForAccounts from "@salesforce/apex/FieldDetailController.getCaseValuesForAccounts";
import getRelatedProductValuesForAccounts from "@salesforce/apex/FieldDetailController.getRelatedProductValuesForAccounts";
import getHouseholdMembersAndAccounts from "@salesforce/apex/WizardEnvelopeStateService.getHouseholdMembersAndAccounts";
import saveEntity from "@salesforce/apex/EnvelopeHouseholdMemberController.saveEntity";
import saveRelatedParties from "@salesforce/apex/EnvelopeHouseholdMemberController.saveRelatedParties";
import getRelatedParties from "@salesforce/apex/EnvelopeHouseholdMemberController.getRelatedParties";
import saveAccountRoles from "@salesforce/apex/EnvelopeHouseholdMemberController.saveAccountRoles";
import getAccountRoles from "@salesforce/apex/EnvelopeHouseholdMemberController.getAccountRoles";
import createOrUpdateFinancialAccountWithEnvelope from "@salesforce/apex/EnvelopeISAController.createOrUpdateFinancialAccountWithEnvelope";
import removeHouseholdMembers from "@salesforce/apex/WizardEnvelopeStateService.removeHouseholdMembers";
import removeFinancialAccounts from "@salesforce/apex/WizardEnvelopeStateService.removeFinancialAccounts";
import removeServices from "@salesforce/apex/WizardEnvelopeStateService.removeServices";
import getRepCodesRelatedToFAT from "@salesforce/apex/EnvelopeISAController.getRepCodesRelatedToFAT";
import getLookupOptions from "@salesforce/apex/EnvelopeLookupOptionController.getLookupOptions";
import getRegistrationTypeAttributes from "@salesforce/apex/EnvelopeISAController.getRegistrationTypeAttributes";
import saveEnvelopeState from "@salesforce/apex/WizardEnvelopeStateService.saveEnvelopeState";
import loadEnvelopeState from "@salesforce/apex/WizardEnvelopeStateService.loadEnvelopeState";
import createServiceAgreement from "@salesforce/apex/WizardEnvelopeStateService.createServiceAgreement";
import saveAccountInfo from "@salesforce/apex/WizardEnvelopeStateService.saveAccountInfo";
import saveAccountCaseInfo from "@salesforce/apex/WizardEnvelopeStateService.saveAccountCaseInfo";
import saveRelatedProduct from "@salesforce/apex/WizardEnvelopeStateService.saveRelatedProduct";
import saveServiceInfo from "@salesforce/apex/WizardEnvelopeStateService.saveServiceInfo";
import getUserPreferences from "@salesforce/apex/WizardEnvelopeStateService.getUserPreferences";
import saveProposedCase from "@salesforce/apex/WizardEnvelopeStateService.saveProposedCase";
import saveProposedCaseFields from "@salesforce/apex/WizardEnvelopeStateService.saveProposedCaseFields";
import saveAccountActionCase from "@salesforce/apex/EnvelopeActionCaseController.saveAccountActionCase";
import saveMemberActionCase from "@salesforce/apex/EnvelopeActionCaseController.saveMemberActionCase";
import deleteAccountActionCase from "@salesforce/apex/EnvelopeActionCaseController.deleteAccountActionCase";
import getStrategyOptions from "@salesforce/apex/TradeInstructionController.getStrategyOptions";
import getCurrentTradeInstructions from "@salesforce/apex/TradeInstructionController.getCurrentTradeInstructions";
import saveTradeInstructions from "@salesforce/apex/TradeInstructionController.saveTradeInstructions";
import getRequiredDocuments from "@salesforce/apex/DocumentService.getRequiredDocuments";

// Envelope submission endpoint. The backend method is in progress — replace the method name below
// (and its class, if the BE places it elsewhere) with the one that ships. `submitEnvelope(envelopeId)`
// is the contract in docs/wizard-page-architecture.md §6.5; confirm the Apex parameter name against
// the final signature (the call site passes { envelopeId }).
import submitEnvelope from "@salesforce/apex/WizardEnvelopeStateService.submitEnvelope";

import {
  RELATED_PARTIES_FIELD_KEY,
  GROUP_IDS,
  ACCOUNT_GROUP_IDS,
  RELATED_PARTY_MEMBER_TYPES,
  ACCOUNT_TYPE_TO_MDT,
  MEMBER_ACTION_TYPES,
  PROPOSED_CHANGES_MDT,
  isDmsPlatform,
  resolveSchemaKey,
  resolveActionCatalog,
  accountActionTypeFor,
  accountActionLabelFor,
  memberActionTypeFor,
  memberActionLabelFor,
  schemaCacheKey,
  applyLookupOptions,
  filterSectionsByAccountType,
  accountValuesToProposedDraft,
  draftValuesEqual,
  shapeVisibleFields,
  isFormatValid,
  resolveRelatedPartyRequirements,
  unmetRelatedPartyRequirements,
  waivedRelatedPartyKeys,
  partyAlternativesLabel,
  aarRoleForKey,
  managedAarRolesFor,
  requirementKeyForAarRole,
  accountRoleForKey,
  managedAccountRolesFor,
  requirementKeyForAccountRole,
  accountRoleLimits,
  partyRoleLabel,
  memberTypeForPartyTypes,
  persistedMemberTypeFor,
  derivePartyRoles,
  pendingPartyIds,
  missingInputsLabel,
  actionCompletion,
  selectMissingSections,
  sumMissingInputs,
  formatFieldDisplayValue,
  strategyTotals,
  normalizeStrategyRows,
  STRATEGY_BASIS
} from "c/envelopeFormSchema";

// The cases-group action types that carry Trade Instructions, and what each files. Change Management
// Style moves the account onto a managed platform and so establishes an account value (funded);
// editing existing instructions has no funded amount available, so nothing may be derived from one
// there. Mirrors the section gate in envelopeActionDetails.
const TRADE_CASE_REQUEST_TYPES = {
  updateDmsInstructions: {
    typeOfRequest: "Update DMS Instructions",
    funded: false
  },
  updateManagementStyle: {
    typeOfRequest: "New DMS Instructions",
    funded: true
  }
};

// Autosave timing. A named constant per phase so each is tuned in one place.
const AUTO_SAVE_INACTIVITY_MS = 6000; // idle window (no field edits) before a save fires
const SAVED_VISIBLE_MS = 2000; // how long "Saved" lingers before the indicator hides
const SAVE_RETRY_DELAY_MS = 15000; // wait before automatically re-attempting a failed save cycle
const MAX_SAVE_AUTO_RETRIES = 2; // automatic re-attempts per failure burst (reset on success)
const SAVE_FAILURE_ALERT_THRESHOLD = 3; // consecutive failures before the escalated warning shows

// Progressive save-status states for the interview form, surfaced as an indicator in the TOC.
const SAVE_STATUS = Object.freeze({
  IDLE: "idle",
  PENDING: "pending",
  SAVING: "saving",
  SAVED: "saved"
});

// DTO/wrapper keys that ride along in an entity's formData — seeded by mapHouseholdResponse's
// `formData: m` / `formData: a` (the whole server wrapper is used as the initial draft) — but are
// not persistable record fields. Dropped before any SObject write so they never reach the Apex
// applyFields / saveAccountInfo, which reject unknown keys (e.g. "These fields could not be saved:
// entityId, submitted"). Real form fields carry their SFDC API names, so none collide with these.
const NON_FIELD_FORM_KEYS = new Set([
  "id",
  "entityId",
  "recordTypeId",
  "accountType",
  "submitted",
  "isDpi",
  "registrationType",
  "custodian",
  "bdOrRia",
  "managedAccountPlatform",
  // Wrapper fields on WizardEnvelopeStateService's member DTO, in the same category as accountType
  // and recordTypeId above: they carry a value read off the record, under a name the record does not
  // have. None of the five exists on Account -- EntityType mirrors Account.Type, EntityJurisdiction
  // stands for Entity_Jurisdiction__c -- so any draft carrying one made applyFields reject the key
  // and abort the whole account write with "These fields could not be saved", losing every other
  // answer in the same save. Routed out here rather than renamed, because the DTO shape is what the
  // shell prefills a business or trust interview from.
  "EntityType",
  // The wrapper's camelCase carrier for the beneficial-owner affirmation. The value is re-seeded
  // under the field's own api name just below (see mapHouseholdResponse), so this key must never
  // reach a write itself.
  "noReportableBeneficialOwners",
  "EntityJurisdiction",
  "PrimaryTrustee",
  "TaxId",
  "FormationDate",
  "hasClientProfile",
  "linkedToEnvelope",
  "pendingEnvelopeName"
]);

// The object an account interview's product answer is stored on. It is a related record rather than a
// field on the account, so those answers are routed out of the account write — see
// _isRelatedProductField.
const RELATED_PRODUCT_OBJECT = "Financial_Account_Related_Product__c";

// Whether a draft key is a real record field, and so belongs in a write to the record. Excludes the
// composite section keys, whose value is a nested object the section owns rather than a field value
// (related parties, trade instructions), and the DTO/wrapper keys above. Single source for the test,
// shared by the record-update payload and the proposed-change payload so the two can't drift.
function isRecordFieldKey(name) {
  return (
    name !== RELATED_PARTIES_FIELD_KEY &&
    name !== "tradeInstructions" &&
    !NON_FIELD_FORM_KEYS.has(name)
  );
}

// Whether an action item edits a household member rather than a financial account. The `cases` group
// holds both, and they persist, prefill and resolve their schema differently, so every branch
// between them tests this one predicate.
function isMemberActionType(type) {
  return !!type && MEMBER_ACTION_TYPES.has(type);
}

// Build the saveEntity Account payload from the add-form data. The nickname is the only name
// captured at add time; the action interview collects the full field set later (saveEntity
// updates the record when an Id is included). The member type travels under the RecordTypeId
// key and is resolved to a real record type on the server — a member presented as a related-party
// role persists as a person account, so it resolves there first (see persistedMemberTypeFor).
// Returns null for member types the backend has no record-type mapping for — those adds stay
// local-only.
function buildMemberAccountPayload({ type, nickname }) {
  const recordType = persistedMemberTypeFor(type);
  if (!recordType) {
    return null;
  }
  const name = (nickname || "").trim();
  if (recordType === "client") {
    // Person accounts persist first/last name; treat the last word as the last name.
    const parts = name.split(/\s+/);
    const lastName = parts.pop() || name;
    return {
      FirstName: parts.join(" "),
      LastName: lastName,
      RecordTypeId: recordType
    };
  }
  return { Name: name, RecordTypeId: recordType };
}

// Seed an interview draft from the add form for the groups whose record name is the nickname
// (Financial Accounts, DPIs, Services all store it in `Name`), so the interview opens with the
// answer the user already gave rather than a blank field.
function buildNameFormData({ nickname }) {
  const name = (nickname || "").trim();
  return name ? { Name: name } : {};
}

// The member equivalent: reuse the create payload so the interview seeds exactly the fields the
// record was created with (FirstName/LastName for a person, Name for a business or trust).
// RecordTypeId is a server-side hint rather than a form field, so it is dropped.
function buildMemberFormData(detail) {
  const acc = buildMemberAccountPayload(detail);
  if (!acc) {
    return {};
  }
  const fields = { ...acc };
  delete fields.RecordTypeId;
  return fields;
}

// Per-group presentation used when an entity is added: the title of the entity's first
// action card plus two icon variants for the two icon vocabularies — `iconVariant` for the
// sidebar row (householdOutlineItem: 'member' | 'account') and `cardIconVariant` for the
// action card (envelopeActionCard: 'isa' → document icon, else member icon). `persist` is
// the group's Apex create call, resolving to the created record id (or null when the add
// cannot be persisted); `persistUpdate` writes a set of changed field values to the entity's
// persisted record — the per-group half of the selective save cycle (see
// _persistMissingItemEntities); `remove` is the group's Apex delete call (record + its envelope
// content links). Groups with null entries are in-memory until their method is wired.
// `initialFormData` seeds the interview draft from the add form. DPIs are Financial Accounts in the
// data model, so they share the FA create, update and delete.
const GROUPS = {
  householdMembers: {
    iconVariant: "member",
    cardIconVariant: "member",
    actionTitle: "Add Client",
    removeLabel: "Remove household member",
    persist: (detail, envelopeId) => {
      const acc = buildMemberAccountPayload(detail);
      return acc ? saveEntity({ acc, envelopeId }) : Promise.resolve(null);
    },
    // saveEntity upserts: with the record Id included it updates the member Account. The
    // member type travels under the RecordTypeId key, like the create call; types without a
    // record-type mapping stay in the envelope JSON only.
    persistUpdate: (entity, fields, envelopeId) => {
      const recordType = persistedMemberTypeFor(entity.type);
      if (!recordType) {
        return Promise.resolve(null);
      }
      return saveEntity({
        acc: { Id: entity.id, RecordTypeId: recordType, ...fields },
        envelopeId
      });
    },
    initialFormData: buildMemberFormData,
    remove: (id, envelopeId) =>
      removeHouseholdMembers({ memberIds: [id], envelopeId })
  },
  accounts: {
    iconVariant: "account",
    cardIconVariant: "isa",
    actionTitle: "Open Account",
    removeLabel: "Remove account",
    // Creates the Financial_Account__c and its envelope link; the household and advisor
    // team are resolved server-side from the envelope, so only the nickname is needed here.
    persist: (detail, envelopeId) =>
      createOrUpdateFinancialAccountWithEnvelope({
        envelopeId,
        accountNickname: (detail.nickname || "").trim(),
        existingAccountId: null,
        isDpi: false
      }),
    persistUpdate: (entity, fields) =>
      saveAccountInfo({ data: { Id: entity.id, ...fields } }),
    initialFormData: buildNameFormData,
    remove: (id, envelopeId) =>
      removeFinancialAccounts({ accountIds: [id], envelopeId })
  },
  dpisSponsor: {
    iconVariant: "account",
    cardIconVariant: "isa",
    actionTitle: "Add DPI",
    removeLabel: "Remove DPI",
    // Same create call as an account — a DPI is a Financial Account carrying the DPI flag.
    persist: (detail, envelopeId) =>
      createOrUpdateFinancialAccountWithEnvelope({
        envelopeId,
        accountNickname: (detail.nickname || "").trim(),
        existingAccountId: null,
        isDpi: true
      }),
    persistUpdate: (entity, fields) =>
      saveAccountInfo({ data: { Id: entity.id, ...fields } }),
    initialFormData: buildNameFormData,
    remove: (id, envelopeId) =>
      removeFinancialAccounts({ accountIds: [id], envelopeId })
  },
  serviceAgreements: {
    iconVariant: "account",
    cardIconVariant: "isa",
    actionTitle: "Open Service Agreement",
    removeLabel: "Remove service agreement",
    persist: (detail, envelopeId) =>
      createServiceAgreement({
        envelopeId,
        serviceNickname: (detail.nickname || "").trim()
      }),
    // Update a Service Agreement's interview fields on the real Service__c record — the accounts
    // entry's counterpart, so the selective save cycle (_persistDirtyAction) picks up services too.
    persistUpdate: (entity, fields) =>
      saveServiceInfo({ data: { Id: entity.id, ...fields } }),
    initialFormData: buildNameFormData,
    remove: (id, envelopeId) => removeServices({ serviceIds: [id], envelopeId })
  },
  cases: {
    iconVariant: "case",
    cardIconVariant: "isa",
    actionTitle: "Account Action Item",
    removeLabel: "Remove Account Action Item",
    // Two kinds of action item share this group and split here. An account action's answers are
    // real Case fields, so Apex routes them on the Envelope_Field__mdt Type__c (hence the
    // ACCOUNT_TYPE_TO_MDT translation) and writes them straight to the record. A member action's
    // answers are the review case's own Proposed_* fields, resolved through the 'Proposed
    // Changes' metadata; the accountId names the member whose current values the server diffs
    // the proposal against — and the record the case must stay linked to.
    persist: (detail, envelopeId) =>
      isMemberActionType(detail.type)
        ? saveMemberActionCase({
            accountId: detail.memberAccountId,
            envelopeId,
            sourceId: detail.type
          })
        : saveAccountActionCase({
            financialAccountId: detail.financialAccountId,
            formData: {},
            envelopeId,
            sourceId: ACCOUNT_TYPE_TO_MDT[detail.type] || detail.type
          }),
    persistUpdate: (entity, fields, envelopeId) =>
      isMemberActionType(entity.type)
        ? saveProposedCaseFields({
            caseId: entity.id,
            accountId: entity.memberAccountId,
            proposedValues: fields
          })
        : saveAccountActionCase({
            financialAccountId: entity.financialAccountId,
            formData: { Id: entity.id, ...fields },
            envelopeId,
            sourceId: ACCOUNT_TYPE_TO_MDT[entity.type] || entity.type || entity.sourceId
          }),
    // A member action opens showing what the member's record holds today — it records a change to an
    // existing person, so a blank form would be neither reviewable nor answerable. The values are the
    // parent member's own, translated to the case's Proposed_* keys in handleAddActionConfirm, so
    // the interview is populated on the first render rather than a round trip later.
    //
    // An Update DMS Instructions case edits the account's sleeve allocation, so its interview opens
    // seeded with the account's current instructions (also carried through the add detail).
    initialFormData: (detail) => {
      if (detail.memberValues) {
        return { ...detail.memberValues };
      }
      return detail.tradeInstructions
        ? { tradeInstructions: detail.tradeInstructions }
        : {};
    },
    remove: (id) => deleteAccountActionCase({ caseId: id })
  }
};

// Member wrapper list → outline group type/label. Each `list` names a property of the household
// wrapper, so the two have to stay in step.
const MEMBER_SOURCES = [
  { list: "clients", type: "client", typeLabel: "Client" },
  { list: "businesses", type: "business", typeLabel: "Client" },
  { list: "trusts", type: "trust", typeLabel: "Client" },
  {
    list: "retirementPlans",
    type: "retirementPlan",
    typeLabel: "Client"
  }
];

// Shape the getHouseholdMembersAndAccounts response into the four outline lists. A record's
// draft vs locked state is the inverse of its Submitted__c flag: an unsubmitted record is a
// still-editable draft (isNew + removable), a submitted one is existing and locked (neither).
// isNew drives that draft behavior and the "New" badge in both the outline and the content area:
// a record shows "New" until it is submitted. Only the fields the payload carries are populated;
// ordering and balance are absent (see gaps in the migration notes).
function mapHouseholdResponse(data) {
  const householdMembers = MEMBER_SOURCES.flatMap(({ list, type, typeLabel }) =>
    (data?.[list] || []).map((m) => {
      const isEnvelopeMember = m.submitted === true || m.accountType === "Active Client" || m.linkedToEnvelope === true;
      const isPendingElsewhere = !isEnvelopeMember && !!m.pendingEnvelopeName;
      const label = isEnvelopeMember
        ? typeLabel
        : isPendingElsewhere
          ? "Pending in Envelope " + m.pendingEnvelopeName
          : " ";
      return {
        id: m.id,
        groupId: "householdMembers",
        name:
          m.Name ||
          `${m.FirstName || ""} ${m.LastName || m.Lastname || ""}`.trim(),
        type,
        typeLabel: label,
        meta: buildMeta([label]),
        iconVariant: "member",
        isNew: isEnvelopeMember && !m.submitted,
        removable: isEnvelopeMember && !m.submitted,
        pendingElsewhere: isPendingElsewhere,
        hasClientProfile: m.hasClientProfile === true,
        actions: isEnvelopeMember
          ? [
              {
                id: `${m.id}-1`,
                iconVariant: GROUPS.householdMembers.cardIconVariant,
                title: GROUPS.householdMembers.actionTitle,
                statusLabel: "In Progress",
                formData:
                  typeof m.noReportableBeneficialOwners === "boolean"
                    ? {
                        ...m,
                        No_Reportable_Beneficial_Owners__c:
                          m.noReportableBeneficialOwners
                      }
                    : m
              }
            ]
          : []
      };
    })
  );
  // Accounts and DPIs share the Financial_Account__c list; the DPI flag decides the group.
  const allAccounts = (data?.accounts || []).map((a) => ({
    id: a.Id,
    groupId: a.isDpi ? "dpisSponsor" : "accounts",
    name: a.Name,
    meta: buildMeta([a.registrationType, a.custodian]),
    iconVariant: "account",
    isNew: !a.submitted,
    removable: !a.submitted,
    // Gate the conditional Add action item entries (Update Management Style / Update DMS
    // Instructions) for account rows; see resolveActionCatalog.
    bdOrRia: a.bdOrRia,
    managedAccountPlatform: a.managedAccountPlatform,
    actions: [
      {
        id: `${a.Id}-1`,
        iconVariant: GROUPS.accounts.cardIconVariant,
        title: GROUPS.accounts.actionTitle,
        statusLabel: "In Progress",
        formData: a
      }
    ]
  }));
  const accounts = allAccounts.filter((a) => a.groupId === "accounts");
  const dpisSponsor = allAccounts.filter((a) => a.groupId === "dpisSponsor");
  const serviceAgreements = (data?.services || []).map((s) => ({
    id: s.Id,
    groupId: "serviceAgreements",
    name: s.Name,
    type: s.Type__c,
    typeLabel: s.Type__c,
    meta: buildMeta([s.Type__c]),
    iconVariant: "account",
    isNew: !s.Submitted__c,
    removable: !s.Submitted__c,
    actions: [
      {
        id: `${s.Id}-1`,
        iconVariant: GROUPS.serviceAgreements.cardIconVariant,
        title: GROUPS.serviceAgreements.actionTitle,
        statusLabel: "In Progress",
        formData: s
      }
    ]
  }));
  // Account Action Items, rebuilt from the Cases the envelope links. The row names the record being
  // serviced and the card names the work, so the header carries the owning account's name and type
  // while the action's catalog label titles its card — derived here rather than stored, so a row
  // saved under an older labelling corrects itself on load.
  //
  // The Case stores its Type; the catalog token is what keys the interview schema and the "+"
  // dialog's already-added rows, so it is mapped back. A Case whose Type has no catalog entry is
  // dropped rather than rendered as an action nothing can open.
  const accountsById = new Map(allAccounts.map((a) => [a.id, a]));
  const membersById = new Map(householdMembers.map((m) => [m.id, m]));
  const cases = (data?.actionCases || [])
    .map((c) => {
      // An account action resolves first; a member action is the same group under a different
      // parent, so it falls through to its own catalog when the Type is not an account one.
      const accountType = accountActionTypeFor(c.caseType);
      const memberType = accountType ? null : memberActionTypeFor(c.caseType);
      const type = accountType || memberType;
      if (!type) {
        return null;
      }
      const label = memberType
        ? memberActionLabelFor(memberType)
        : accountActionLabelFor(type);
      // The parent lookup differs by kind: an account action services a Financial Account, a member
      // action a household member, and only the matching one carries a usable id.
      const owner = memberType
        ? membersById.get(c.accountId)
        : accountsById.get(c.financialAccountId);
      const ownerName = memberType ? c.accountName : c.financialAccountName;
      const typeLabel = memberType ? "Household Members" : "Accounts";
      return {
        id: c.id,
        groupId: "cases",
        name: owner?.name || ownerName || c.subject || label,
        type,
        typeLabel,
        meta: buildMeta([typeLabel]),
        iconVariant: GROUPS.cases.iconVariant,
        isNew: !c.submitted,
        removable: !c.submitted,
        financialAccountId: memberType ? null : c.financialAccountId,
        memberAccountId: memberType ? c.accountId : null,
        actions: [
          {
            id: `${c.id}-1`,
            iconVariant: GROUPS.cases.cardIconVariant,
            title: label,
            statusLabel: "In Progress",
            // The Case's own field values are overlaid on load by _applyCaseRecordValues; the
            // wrapper carries only the row's presentation, so the draft starts empty.
            formData: {}
          }
        ]
      };
    })
    .filter(Boolean);
  return { householdMembers, accounts, dpisSponsor, serviceAgreements, cases };
}

// Present the person members that play a related-party role by that role rather than as plain
// individuals: the row's meta reads the role, and the member type resolves the role's own field set
// so its interview asks the role's questions (see resolveSchemaKey). A member holding more than one
// role lists them all in the label, and the first drives the form — the model carries one type per
// entity. A member with no role is returned untouched, which is what keeps the presentation
// self-correcting: a role removed since the last save reverts the row on the next fetch.
// A member with hasClientProfile (their own Required_Documents__c) is a primary Individual: they
// keep their client type and field set even when they also serve as a related party, and the
// party role appears in their outline meta so the sidebar reflects both.
function applyPartyRoles(members, roles) {
  return (members || []).map((entity) => {
    const held = (roles[entity.id] || []).filter(partyRoleLabel);
    if (entity.type !== "client" || !held.length) {
      return entity;
    }
    if (entity.hasClientProfile) {
      return {
        ...entity,
        meta: buildMeta([entity.typeLabel, ...held.map(partyRoleLabel)])
      };
    }
    const typeLabel = buildMeta(held.map(partyRoleLabel));
    return {
      ...entity,
      type: held[0],
      typeLabel,
      meta: buildMeta([typeLabel])
    };
  });
}

// True for a Salesforce record id (a persisted entity); locally-added entities carry
// `${groupId}-${n}` temp ids instead.
function isRecordId(id) {
  return /^[a-zA-Z0-9]{15,18}$/.test(id || "");
}

// True when an entity's related parties belong in records rather than only in memory: a business or
// trust member (Account_Account_Relationship__c) or a Financial Account (Financial_Account_Role__c).
// The two persist through different objects but share one value shape, so callers branch on
// holdsAccountRoleRecords rather than keeping two parallel paths.
function holdsRelatedPartyRecords(entity) {
  return holdsMemberPartyRecords(entity) || holdsAccountRoleRecords(entity);
}

// True for the members whose parties are Account_Account_Relationship__c rows.
function holdsMemberPartyRecords(entity) {
  return (
    entity?.groupId === "householdMembers" &&
    RELATED_PARTY_MEMBER_TYPES.has(entity.type)
  );
}

// True for the Financial Accounts whose ownership slots are Financial_Account_Role__c rows. DPIs are
// Financial Accounts too, so both account groups qualify.
function holdsAccountRoleRecords(entity) {
  return ACCOUNT_GROUP_IDS.has(entity?.groupId);
}

// True when an entity's related parties can be written now: they belong in records and its own
// record already exists. A just-added entity still waiting for its record id holds its parties in
// memory until the id lands.
function ownsRelatedPartyRecords(entity) {
  return holdsRelatedPartyRecords(entity) && isRecordId(entity.id);
}

// The model with every action's related-party value removed. Related parties are held as
// Account_Account_Relationship__c and Financial_Account_Role__c rows, so the envelope-state blob is
// not their store: it is stripped on the way out so the two can never disagree, and on the way in so
// a value written by an older build is never read back over the records. The value is rebuilt from
// the rows by _seedRelatedPartiesFromRecords on every household fetch.
function withoutRelatedParties(model) {
  const stripped = { ...model };
  GROUP_IDS.forEach((groupId) => {
    if (!Array.isArray(stripped[groupId])) {
      return;
    }
    stripped[groupId] = stripped[groupId].map((entity) => {
      if (!Array.isArray(entity?.actions)) {
        return entity;
      }
      return {
        ...entity,
        actions: entity.actions.map((action) => {
          if (
            !action?.formData ||
            !(RELATED_PARTIES_FIELD_KEY in action.formData)
          ) {
            return action;
          }
          const formData = { ...action.formData };
          delete formData[RELATED_PARTIES_FIELD_KEY];
          return { ...action, formData };
        })
      };
    });
  });
  return stripped;
}

// The outline groups whose entities are records, and so are read back from the server on every load
// (see mapHouseholdResponse). Still a named list rather than GROUP_IDS, because membership here is a
// claim that the household fetch returns the group: strip one it does not and every entity in it is
// deleted with nothing left to restore it. Add a group here only once its server read exists.
const RECORD_BACKED_GROUP_IDS = [
  "householdMembers",
  "accounts",
  "dpisSponsor",
  "serviceAgreements",
  "cases"
];

// The model with every persisted entity dropped from the record-backed lists. Which entities belong
// to an envelope is held in records — the Accounts, Financial Accounts and Services themselves,
// linked through Envelope_Content__c — so the envelope-state blob is not their store: they are
// stripped on the way out so the two can never disagree, and on the way in so a list written by an
// older build is never read back over the records. _fetchHouseholdMembersAndAccounts refills them on
// every load, which is what lets a removed entity stay removed instead of returning from the blob.
//
// Only entities carrying a record id are dropped. A member type with no record-type mapping never
// reaches a record and keeps a temporary id, so the blob is still its only store and emptying the
// list outright would lose it. A removed entity always held a record id, so filtering this way
// still strips it.
//
// One interview value on accounts/DPIs is carried only by the blob and is therefore lost on a reload
// before submit, which is accepted: `tradeInstructions`, written to Order_Ticket__c only by the
// submit handler and never read back (getCurrentTradeInstructions returns the account's existing
// allocation, not the draft). The Case-targeted fields of a mixed account interview are not in that
// category — they are written to the wizard Case and read back from it (_fetchAccountRecordValues).
function withoutRecordBackedEntities(model) {
  const stripped = { ...model };
  RECORD_BACKED_GROUP_IDS.forEach((groupId) => {
    stripped[groupId] = (
      Array.isArray(stripped[groupId]) ? stripped[groupId] : []
    ).filter((entity) => !isRecordId(entity?.id));
  });
  return stripped;
}

// The entity with the given accounts dropped from every requirement of its related-party value —
// used when those accounts are removed from the envelope, so an entity that held one as a party
// stops listing it. A requirement left with no parties loses its key rather than keeping an empty
// list, the same shape _updateActionRelatedParties maintains, so it reads as unmet again.
// Returns the entity unchanged (same reference) when it held none of them, leaving the reactive
// projections of every untouched row alone.
function withoutParties(entity, removedIds) {
  if (!Array.isArray(entity?.actions)) {
    return entity;
  }
  let entityChanged = false;
  const actions = entity.actions.map((action) => {
    const held = action?.formData?.[RELATED_PARTIES_FIELD_KEY];
    if (!held) {
      return action;
    }
    let changed = false;
    const parties = {};
    Object.keys(held).forEach((requirementKey) => {
      const kept = (held[requirementKey] || []).filter(
        (party) => !removedIds.has(party?.id)
      );
      if (kept.length !== (held[requirementKey] || []).length) {
        changed = true;
      }
      if (kept.length) {
        parties[requirementKey] = kept;
      }
    });
    if (!changed) {
      return action;
    }
    entityChanged = true;
    return {
      ...action,
      formData: { ...action.formData, [RELATED_PARTIES_FIELD_KEY]: parties }
    };
  });
  return entityChanged ? { ...entity, actions } : entity;
}

// Success-toast copy for an entity removal, keyed by the entity's group id.
const ENTITY_REMOVED_TOASTS = {
  householdMembers: {
    label: "Member removed",
    message: "Member has been removed successfully."
  },
  accounts: {
    label: "Account removed",
    message: "Account has been removed successfully."
  },
  dpisSponsor: {
    label: "DPI removed",
    message: "DPI has been removed successfully."
  },
  serviceAgreements: {
    label: "Service agreement removed",
    message: "Service agreement has been removed successfully."
  },
  default: { label: "Removed", message: "Removed from household." }
};

// The ISA form's type value → target group id. The form emits `dpi` while the outline/model
// id is `dpisSponsor`, so the two are reconciled here.
const ISA_TYPE_TO_GROUP = {
  accounts: "accounts",
  dpi: "dpisSponsor",
  serviceAgreements: "serviceAgreements"
};

// Compose a sidebar subtitle from the segments available for an entity, in the design's order
// (e.g. account: registration • owner • custodian • account #), dropping any not yet known. A
// freshly-added entity has only its type today; the create/interview flow enriches this as
// fields are captured. Returns '' when no segment is known.
function buildMeta(segments) {
  return segments.filter(Boolean).join(" • ");
}

// What an ISA row shows under its name, for all three ISA groups. The subtitle used to be frozen
// when the row was added, out of whatever display label the entry point handed over, and was never
// reconciled with the record — so a row sat blank when the record had nothing to describe it, or
// showed a destination group name as though it were a type.
//
// Neither add path can supply a real value. The rail's "+" asks for no type at all (handleAddClick
// passes an empty label). The content CTA's ISA form does ask, but its options name where the item
// should go — Accounts, DPIs - Sponsor Reported, Service Agreements — which is a group, not a field
// value any record holds. And the create calls carry only a nickname, so a newly added record has
// none of these fields set yet regardless.
//
// So the subtitle is resolved at render time from the live interview draft, falling back to what the
// record was loaded with, and finally to the row's own kind so it is always identifiable.

// The fields whose values describe each ISA kind, in the order the design reads them. These are the
// same fields the server projection builds its subtitle from, named as the interview holds them so
// the draft can be read directly.
const ISA_META_FIELDS = {
  accounts: ["Registration_Type__c", "Custodian__c"],
  // A DPI is a Financial Account too, but its 'ISA - DPI' schema does not carry registration type or
  // custodian, so its draft has nothing to read and it relies on the loaded value or the fallback.
  dpisSponsor: ["Registration_Type__c", "Custodian__c"],
  serviceAgreements: ["Type__c"]
};

// Shown when nothing describes the record yet. Singular, because it names one row.
const ISA_KIND_LABELS = {
  accounts: "Account",
  dpisSponsor: "DPI - Sponsor Reported",
  serviceAgreements: "Service Agreement"
};

// The group names the ISA form offers as its "type". None is a value any record holds, so none may
// survive into a subtitle.
const ISA_GROUP_LABELS = new Set([
  "Accounts",
  "DPIs - Sponsor Reported",
  "Service Agreements"
]);

function isaMeta(entity) {
  const kind = ISA_KIND_LABELS[entity?.groupId];
  if (!kind) {
    return entity?.meta || "";
  }
  const draft =
    (entity?.actions || []).reduce(
      (found, action) => found || action?.formData,
      null
    ) || {};
  const live = (ISA_META_FIELDS[entity.groupId] || [])
    .map((field) => draft[field])
    .filter(Boolean);
  if (live.length) {
    return buildMeta(live);
  }
  const loaded = ISA_GROUP_LABELS.has(entity?.meta) ? null : entity?.meta;
  return loaded || kind;
}

// Resolve either add entry point to a single target group id. The Household Outline "+"
// already carries the group id; the content CTA form carries a variant + type instead.
function resolveGroup({ group, variant, type }) {
  if (group) {
    return group;
  }
  if (variant === "member") {
    return "householdMembers";
  }
  return ISA_TYPE_TO_GROUP[type] || "accounts";
}

/**
 * Author: Mile Cacanovic
 *
 * envelopeShellV2 — v2 redesign of the single-envelope working page
 * (replaces envelopeShell / envelopeNavSidebar once the redesign is complete).
 *
 * Holds the whole envelope as one model object whose four lists back the Household Outline
 * groups; the sidebar rows and the content-area action cards are both projections of it. The
 * outline lists are seeded from getHouseholdMembersAndAccounts (see _loadModel) and mutated by
 * per-group add/remove (see GROUPS.persist); a single aggregate read (getEnvelopeModel) is the
 * eventual replacement for _loadModel.
 */
export default class EnvelopeShellV2 extends LightningElement {
  @api envelopeTitle = "";
  @api householdName = "";
  // The current Envelope__c id; carried on the model for later persistence.
  @api envelopeId = "";
  // Set only when the envelope was created against an existing household; drives whether the
  // outline rail is seeded with the existing-household entities.
  @api householdId = "";

  // The single envelope model: envelope meta plus the four outline groups as flat lists.
  // Seeded by _loadModel; mutated locally by add/remove.
  model = {
    id: "",
    name: "",
    householdName: "",
    householdMembers: [],
    accounts: [],
    dpisSponsor: [],
    serviceAgreements: [],
    cases: []
  };

  // Which content-area screen is shown: 'items' = the action-items region (default),
  // 'documents' = the Manage Documents screen, 'missingItems' / 'review' = the full-screen
  // review views. Set via deferred assignment (see handleHeaderAction).
  activeView = "items";

  // True while the envelope has at least one required document. Gates the header's Manage
  // Documents action, which would open an empty screen otherwise. Required documents are
  // created and deleted server-side, so the flag is re-read on load and after each mutation
  // that can change it (see _refreshRequiredDocuments).
  hasRequiredDocuments = false;

  isMissingItemsLoading = false;

  // True while the initial envelope load is in flight (persisted state plus the household
  // fetch that seeds the outline groups). The items region shows a spinner instead of
  // flashing the empty state before the fetched action items render.
  isItemsLoading = false;

  // The completed-envelope summary fed to the Review & Submit screen: one row per action across
  // every entity, built from the record-type schema plus the action's saved form data. Rebuilt
  // on each openReview() so it always reflects the current model (see _refreshReviewItems).
  reviewItems = [];

  // Last review-readiness value announced via `reviewablechange`; the guarded renderedCallback
  // compares against it so the event fires only when submittability actually flips.
  _lastNotifiedReviewable = undefined;

  // null = CTA at the top of the items region; 'member' | 'isa' = inline add-item
  // form rendered in the CTA's place, above any existing items (which stay visible).
  activeForm = null;

  // Bound to the inline add form's busy state. Local adds are synchronous, so this stays
  // false; it remains for when a persistence round-trip is wired up.
  isAddingItem = false;

  // In-flight guard for the final submit round-trip, so a repeated click on the Review & Submit
  // confirmation can't fire the submit endpoint twice.
  isSubmitting = false;

  // The pending removal driving the shared confirm dialog: 'action' (a content action
  // card) or 'entity' (a Household Outline row). _removeTarget selects the confirm
  // behavior; _pendingRemoveId targets what to remove; pendingRemoveName is the
  // emphasized text bound into the dialog copy; _removeLabel is the entity-type remove
  // label (e.g. "Remove account") used in the dialog copy for an outline row.
  _removeTarget = null;
  _pendingRemoveId = null;
  pendingRemoveName = "";
  _removeLabel = "";

  // True when an action removal cascades to its owning entity: a new member/ISA record can't
  // exist without an action, so removing its last action removes the record. Drives the dialog
  // copy that explains the cascade.
  _removeCascades = false;

  // The entity whose "+" was clicked: its id targets where confirmed actions are appended,
  // its name is bound into the Add action item dialog subtitle, and its already-added action
  // ids disable those rows in the dialog.
  _pendingAddId = null;
  pendingAddName = "";
  pendingAddedActionIds = [];

  // The pending related-party target from Review Missing Items, captured when the "Select
  // existing member" / "Create new" dialog opens. The action item key is the owning action's id
  // and the part key is the related-party requirement key, so a picked/created member lands in
  // that action's formData under the right requirement.
  _pendingOwnerActionItemKey = null;
  _pendingOwnerPart = null;

  // The Review Missing Items snapshot: taken when the screen opens (see _openMissingItemsView)
  // and kept for the whole visit, so items stay listed while the user fills them in. Re-opening
  // the screen takes a fresh snapshot.
  _missingItemsSnapshot = [];

  // Run counter for _openMissingItemsView. Closing the screen while its schemas are loading and
  // re-opening it starts a second run; the stale one drops its result instead of racing.
  _missingItemsRun = 0;

  // Field names changed on the Review Missing Items screen since their last successful persist,
  // keyed by action id. Drained by _persistMissingItemEntities, which routes each entity to its
  // group's update call; a failed persist keeps its entry so the next cycle retries.
  _missingItemsDirty = {};

  // Actions whose related parties changed since their last successful persist, keyed by action id.
  // Drained alongside _missingItemsDirty by _persistMissingItemEntities, which reconciles the
  // relationship records; a failed persist keeps its entry so the next cycle retries.
  _relatedPartiesDirty = {};

  // Serializes the related-party reconcile: a party change reconciles immediately, so without this
  // an eager run and the autosave cycle could each compute the links to write from the same database
  // state and insert them twice. Held on a container, like the dirty maps above, so replacing the
  // promise on each reconcile doesn't mark the component dirty.
  _reconcile = { queue: Promise.resolve(), draining: false };

  // Person Account ids created for related parties added through the "Create new" dialog, keyed by
  // `${actionId}|${requirementKey}|${pendingId}`. The dialog's temporary id can outlive the create
  // (an open interview keeps it in its own draft), so this memo — not the draft — is what guarantees
  // the person is created exactly once.
  _createdPartyIds = {};

  // The action-type catalog for the entity whose "+" is currently open, resolved per its type
  // when the Add action item dialog opens (see handleItemAdd). Host-owned; the dialog stays
  // presentational and renders whatever it is given.
  pendingAddActions = [];

  // Member Type options for the Review screen's "Create new" dialog: the party types the pending
  // action's entity needs, keyed like the interview's Related Parties dialog (requirement key /
  // title) so the preset type resolves to its label.
  get ownerMemberTypeOptions() {
    const found = this._findEntityByActionId(this._pendingOwnerActionItemKey);
    if (!found) {
      return [];
    }
    return resolveRelatedPartyRequirements(
      found.entity,
      found.action.formData || {},
      this._registrationAttributes
    ).map((requirement) => ({
      label: requirement.title,
      value: requirement.key
    }));
  }

  // Session-only: collapses the left rail to a narrow strip. Owned here because
  // the grid column width lives on this component (see .shell__grid).
  isNavCollapsed = false;

  // The opened action's interview context, or null for the default workspace view. The shell
  // owns this so it can later feed the interview its section config + form data from `model`.
  selectedAction = null;

  // The ordered form schema (sections + fields from Envelope_Field__mdt) for the open action's
  // entity type, propagated to the action-details page. Empty while none is open or when the
  // entity's type has no configured fields (the page then shows a graceful empty state).
  _rawActionSchema = [];

  // Query-backed options for lookup fields, keyed by field API name (see _fetchLookupOptions).
  _lookupOptions = {};

  // Registration_Type__mdt attributes keyed by Registration_Type__c value, prefetched once. The
  // registration picklist carries no grouping, so these flags are what select a Financial
  // Account's related-party requirements.
  _registrationAttributes = {};
  // Memoized _prefetchRegistrationAttributes promise; awaited wherever the attributes are required
  // rather than merely nice to have.
  _registrationAttributesReady = null;

  // Lookup options are merged in on read rather than at assignment, so options that arrive after
  // an interview is already open still reach the rendered form.
  get actionSchema() {
    // A lookup with one candidate is dropped rather than rendered — see
    // _applySingleOptionLookups for the value that goes to the record in its place.
    return this._withoutSingleOptionLookups(
      applyLookupOptions(this._rawActionSchema, this._lookupOptions)
    );
  }

  /**
   * The lookups that resolved to exactly one candidate, as { fieldApiName: value }.
   *
   * Read straight off _lookupOptions rather than off a flag the schema module could set, so this
   * component carries the whole feature. LWC bundles are versioned and cached independently: a
   * shell calling a helper that a still-cached envelopeFormSchema does not export yet throws inside
   * this getter and takes the entire interview down with it. Keeping it here means there is no
   * version to be out of step with.
   */
  _singleOptionLookupValues() {
    const values = {};
    Object.entries(this._lookupOptions || {}).forEach(([key, options]) => {
      if (!Array.isArray(options) || options.length !== 1) {
        return;
      }
      // Keys are either a bare field name or "Object|Field" — see applyLookupOptions.
      const fieldName = key.includes("|") ? key.split("|")[1] : key;
      values[fieldName] = options[0].value;
    });
    return values;
  }

  /**
   * Drop the single-candidate lookup fields, and any section left empty by that. Memoized on the
   * applied sections' identity plus the set of dropped names: the result binds into the template,
   * so a fresh array per read would rebuild the interview on every re-render.
   */
  _withoutSingleOptionLookups(sections) {
    if (!sections || !sections.length) {
      return sections;
    }
    const values = this._singleOptionLookupValues();
    const names = Object.keys(values);
    const signature = names.slice().sort().join(",");
    if (!names.length) {
      return sections;
    }
    const memo = this._singleOptionSchemaMemo;
    if (memo && memo.source === sections && memo.signature === signature) {
      return memo.result;
    }
    const dropped = new Set(names);
    const result = sections
      .map((section) => ({
        ...section,
        fields: (section.fields || []).filter(
          (field) => !dropped.has(field.fieldPath)
        )
      }))
      .filter((section) => (section.fields || []).length > 0);
    this._singleOptionSchemaMemo = { source: sections, signature, result };
    return result;
  }

  // Exposed to the action-details form, which resolves an account's related parties from the
  // registration selected in its own draft rather than from the shell's saved values.
  get registrationAttributes() {
    return this._registrationAttributes;
  }

  // The open action's section layout (parent groups from Section__mdt) for its Type__c, or null
  // when the type has no configured layout (the page then renders a single default group).
  actionSectionLayout = null;

  // Form schemas cached by `${objectName}|${type}` so reopening an action of a known type is
  // instant (lazy, fetched on first open).
  _schemaCache = {};

  // Section layouts (parent grouping/ordering) keyed by Type__c, prefetched once with the schemas.
  _sectionLayouts = {};

  // Interview autosave: the current progressive-save status, a concurrency guard, and the timers
  // for each phase (inactivity window → mock POST → "Saved" auto-hide).
  saveStatus = SAVE_STATUS.IDLE;
  isSaving = false;
  _autoSaveTimerId = null;
  _saveTimerId = null;
  _savedHideTimerId = null;

  // Recurrent-failure tracking across save cycles: consecutive failed attempts, the automatic
  // retries spent on the current burst, and whether the escalated warning has already shown.
  _consecutiveSaveFailures = 0;
  _saveRetryCount = 0;
  _saveFailureAlertShown = false;

  get isActionView() {
    return this.selectedAction !== null;
  }

  // The saved form values for the open action, prefilled into the interview form.
  get selectedActionFormData() {
    if (!this.selectedAction) {
      return {};
    }
    const found = this._findEntityByActionId(this.selectedAction.actionId);
    return found?.action?.formData || {};
  }

  // The member action items' frozen baselines, keyed by Case id then by field API name. Replaced
  // wholesale on every household fetch, so the interview picks the snapshot up as soon as the read
  // lands (it resolves after the first render).
  _caseOriginalValues = {};

  // The frozen baseline the open interview marks its changed fields against, keyed by field API
  // name. Only a member action item has one: it is raised against a member who already exists, so
  // its review case snapshots that member's values as the comparison point. Everything else —
  // a new record's interview, an account action item — returns null, which the interview reads as
  // "nothing to compare against" and renders unmarked.
  get selectedActionOriginalValues() {
    const action = this.selectedAction;
    if (
      !action ||
      action.entityGroupId !== "cases" ||
      !isMemberActionType(action.entityType)
    ) {
      return null;
    }
    return this._caseOriginalValues[action.entityId] || null;
  }

  // Monotonic counter for locally-added entity ids (kept stable and dependency-free).
  _seq = 0;

  // Running-user attributes for `$User.<field>` WHERE conditions in the metadata schema (e.g. a
  // field shown only when `$User.Relationship_to_Firm__c = 'Dual'`). Fetched once and passed to the
  // interview/review children; empty until it resolves, so such fields stay hidden until known.
  userContext = {};

  // Strategy__c options for Trade Instructions sleeves: [{ label, value }] with the record Id as
  // value. Prefetched once (cacheable read) and threaded to envelopeActionDetails.
  strategyOptions = [];

  connectedCallback() {
    this._loadModel();
    this._prefetchAllSchemas();
    this._prefetchRegistrationAttributes();
    this._prefetchUserContext();
    this._prefetchStrategyOptions();
    this._refreshRequiredDocuments();
  }

  // Prefetch the selectable Strategy__c records the Trade Instructions sleeve pickers offer, each
  // carrying the funding basis its classification allows so the two lists can offer only what they
  // may hold. Runs once for the whole envelope. Non-fatal on failure: the pickers stay empty and the
  // section reads incomplete until a strategy can be picked.
  _prefetchStrategyOptions() {
    getStrategyOptions()
      .then((records) => {
        this.strategyOptions = (records || []).map((record) => ({
          label: record.strategyCode
            ? `${record.name} (${record.strategyCode})`
            : record.name,
          value: record.id,
          allowedBasis: record.allowedBasis,
          classification: record.classification
        }));
      })
      .catch(() => {
        // Non-fatal: sleeves can't pick a strategy until (if) this resolves.
      });
  }

  // Prefetch the running user's attributes that `$User.<field>` WHERE conditions read. Reassigns
  // userContext so the reactive projections (action-item badges, review summary) re-evaluate field
  // visibility once it lands. Non-fatal on failure: userContext stays empty and such fields remain
  // hidden.
  _prefetchUserContext() {
    getUserPreferences()
      .then((pref) => {
        this.userContext = {
          Relationship_to_Firm__c: pref?.relationshipToFirm ?? null
        };
      })
      .catch(() => {
        // Non-fatal: `$User.`-gated fields stay hidden until (if) this resolves.
      });
  }

  // Fetch — once for the whole envelope, since the metadata is the same for every account — the
  // registration attributes that select a Financial Account's related parties. The promise is
  // memoized and returned so a caller that cannot proceed without them can await it: reading an
  // account's role rows before they land would resolve every registration to the single-owner
  // default and drop the roles no such account has a slot for (see _fetchHouseholdMembersAndAccounts).
  _prefetchRegistrationAttributes() {
    if (!this._registrationAttributesReady) {
      this._registrationAttributesReady = getRegistrationTypeAttributes()
        .then((map) => {
          this._registrationAttributes = map || {};
        })
        .catch(() => {
          // Non-fatal: every registration then resolves to the single-owner default.
        });
    }
    return this._registrationAttributesReady;
  }

  // Prefetch every configured record type's form schema in one call and merge it into the schema
  // cache, so action cards can show real missing-input counts up front and every interview opens
  // from cache. Merges under any already-cached key (a lazy fetch that landed first wins). On
  // failure the cache stays as-is and _loadActionSchema falls back to its per-type lazy fetch.
  _prefetchAllSchemas() {
    getAllFormSchemas()
      .then((map) => {
        this._schemaCache = { ...(map || {}), ...this._schemaCache };
      })
      .catch(() => {
        // Non-fatal: lazy per-type loading remains as the fallback.
      });
    getSectionLayouts()
      .then((map) => {
        this._sectionLayouts = map || {};
      })
      .catch(() => {
        // Non-fatal: a type without a layout renders as a single default group.
      });
  }

  renderedCallback() {
    // Announce review-readiness to the host whenever it flips, so the top bar's
    // "Review and Submit" button enablement tracks the model through every mutation
    // path (add/remove entity or action, field edits, initial seed).
    const reviewable = this.isReviewable;
    if (reviewable !== this._lastNotifiedReviewable) {
      this._lastNotifiedReviewable = reviewable;
      this.dispatchEvent(
        new CustomEvent("reviewablechange", { detail: { reviewable } })
      );
    }
  }

  disconnectedCallback() {
    this._clearAllSaveTimers();
  }

  // Initialize the model with empty lists, then load real household data. A future
  // getEnvelopeModel(envelopeId) Apex aggregate is the eventual single read seam, returning the
  // same { id, name, householdName, <4 lists> } shape; today the lists are populated by the
  // getHouseholdMembersAndAccounts fetch below.
  async _loadModel() {
    this.isItemsLoading = true;
    try {
      if (this.envelopeId) {
        await this.loadEnvelopeStateFromServer();
      } else {
        this.resetEnvelopeState();
      }
      // Only the household is needed to resolve its advisor team's rep codes.
      if (this.householdId) {
        this._fetchLookupOptions();
      }
      this._fetchRegistryLookupOptions();
      // Real-data fetch, run whenever the envelope's household is known (create against an
      // existing household, or any reopen from the list). Both ids are required: the household
      // drives the query, the envelope receives the content links. Awaited so the items region
      // holds its loading state until the fetched entities are in the model.
      if (this.householdId && this.envelopeId) {
        await this._fetchHouseholdMembersAndAccounts();
      }
    } finally {
      this.isItemsLoading = false;
    }
  }

  async loadEnvelopeStateFromServer() {
    try {
      const result = await loadEnvelopeState({
        wizardEnvelopeId: this.envelopeId
      });

      if (result?.envelopeJson) {
        const parsed = JSON.parse(result.envelopeJson);
        // Envelopes saved before a newer outline group existed carry no key for it in their
        // persisted state; seed the missing lists so every consumer can rely on the full shape.
        GROUP_IDS.forEach((groupId) => {
          if (!Array.isArray(parsed[groupId])) {
            parsed[groupId] = [];
          }
        });
        // Related parties and the record-backed entity lists live in records, so anything an older
        // envelope still carries here is dropped rather than trusted: the household fetch that
        // follows refills the lists and _seedRelatedPartiesFromRecords rebuilds the party values
        // from the relationship and role rows. Stripping on load is also what corrects an envelope
        // already carrying an entity the server no longer returns, without a data fix.
        this.model = withoutRelatedParties(withoutRecordBackedEntities(parsed));
      } else {
        this.resetEnvelopeState();
      }
    } catch (error) {
      console.error("Failed to load envelope state", error);
      this.resetEnvelopeState();
    }
  }

  resetEnvelopeState() {
    this.model = {
      id: this.envelopeId || "",
      name: this.envelopeTitle || "",
      householdName: this.householdName || "",
      householdMembers: [],
      accounts: [],
      dpisSponsor: [],
      serviceAgreements: [],
      cases:[]
    };
  }

  // Load the candidate records for the form's lookup fields. Rep codes are scoped to the
  // household's advisor team server-side, so the whole org's codes are never offered.
  async _fetchLookupOptions() {
    try {
      const repCodes = await getRepCodesRelatedToFAT({
        householdId: this.householdId
      });
      this._lookupOptions = {
        ...this._lookupOptions,
        Rep_Code__c: (repCodes || []).map((code) => ({
          label: code.Name,
          value: code.Id
        }))
      };
      // The interview may already be open — the options resolve after it renders.
      this._applySingleOptionLookups();
    } catch (error) {
      // Non-fatal: the field falls back to its unsupported-type state rather than blocking
      // the rest of the interview.
      console.error("getRepCodesRelatedToFAT failed", error);
    }
  }

  /**
   * The values for the open action's single-candidate lookups. Read from the schema *with* options
   * applied, which is the only place the candidate count is known — the raw cached schema the
   * missing-inputs count reads has no options on it.
   */
  _singleOptionValuesForOpenAction() {
    if (!this.selectedAction) {
      return {};
    }
    // Only the ones this action's schema actually asks for — _lookupOptions is shared across every
    // entity type, and writing a field this record has no business holding would be a real bug.
    const values = this._singleOptionLookupValues();
    const present = new Set();
    applyLookupOptions(this._rawActionSchema, this._lookupOptions).forEach(
      (section) => {
        (section.fields || []).forEach((field) => present.add(field.fieldPath));
      }
    );
    const scoped = {};
    Object.keys(values).forEach((name) => {
      if (present.has(name)) {
        scoped[name] = values[name];
      }
    });
    return scoped;
  }

  /**
   * Write the single-candidate lookup values into the open action's form data.
   *
   * The field is never rendered, so the interview cannot collect it, and two things read form data
   * rather than the schema: the save, and the missing-inputs count. Seeding here keeps the count
   * honest the moment the interview opens rather than only after the first save.
   *
   * Runs after the schema resolves and again after the options land, since either can arrive first.
   * Idempotent — an already-answered field is left alone, so this never overwrites a value a
   * multi-candidate list collected before the team's codes were pruned to one.
   */
  _applySingleOptionLookups() {
    const action = this.selectedAction;
    if (!action) {
      return;
    }
    const values = this._singleOptionValuesForOpenAction();
    const names = Object.keys(values);
    if (!names.length) {
      return;
    }
    const found = this._findEntityByActionId(action.actionId);
    if (!found) {
      return;
    }
    const current = found.action.formData || {};
    const patch = {};
    names.forEach((name) => {
      const held = current[name];
      if (held === undefined || held === null || held === "") {
        patch[name] = values[name];
      }
    });
    if (!Object.keys(patch).length) {
      return;
    }
    this._updateEntity(found.entity.id, (entity) => ({
      ...entity,
      actions: entity.actions.map((entry) =>
        entry.id === action.actionId
          ? { ...entry, formData: { ...entry.formData, ...patch } }
          : entry
      )
    }));
    // The Review Missing Items write sends the dirty set rather than the whole form data, so a
    // value nobody typed has to be marked or it would sit in the model and never reach the record.
    const dirty = this._missingItemsDirty[action.actionId] || new Set();
    Object.keys(patch).forEach((name) => dirty.add(name));
    this._missingItemsDirty[action.actionId] = dirty;
    // And arm the autosave cycle. Nothing else will: the arming above hangs off a field edit, and
    // by design nobody edits this field — the whole point is that it is never shown. Without this
    // the value waits in memory for an unrelated edit to carry it, and an interview opened and
    // closed again would leave the record without the only rep code it could have had.
    this._clearSavedHideTimer();
    this.saveStatus = SAVE_STATUS.PENDING;
    this._resetAutoSaveTimer();
    // And write it now rather than waiting out the idle window. Backing out of an interview flushes
    // the draft into the model but does not run the record-persist cycle — that hangs off the timer
    // — so an interview opened and closed inside six seconds armed a save that teardown then threw
    // away, leaving the record without the only rep code it could have had. This value is not
    // typing: it is a discrete, already-final answer, so it is written immediately, the same way
    // _reconcileRelatedPartiesNow treats adding a party.
    this._persistOpenAccountFields().catch((error) => {
      // Non-fatal: the arming above leaves it pending, so the next cycle retries.
      console.error("[envelopeShellV2] single-option lookup write failed", error);
    });
  }

  // Load the candidate records for the lookup fields configured server-side, keyed by object and
  // field API name. Merged into the same map as the rep codes above by spreading the live property,
  // so the two fetches can complete in either order without discarding each other's results.
  async _fetchRegistryLookupOptions() {
    try {
      const options = await getLookupOptions({
        householdId: this.householdId || null,
        envelopeId: this.envelopeId || null
      });
      this._lookupOptions = { ...this._lookupOptions, ...(options || {}) };
    } catch (error) {
      // Non-fatal, as above: an unresolved source leaves its own field unsupported.
      console.error("getLookupOptions failed", error);
    }
  }

  // Loads the household's members and financial accounts, links them to this envelope, and merges
  // the mapped entities into the model so the outline renders real data.
  async _fetchHouseholdMembersAndAccounts() {
    try {
      const data = await getHouseholdMembersAndAccounts({
        householdId: this.householdId,
        envelopeId: this.envelopeId
      });
      // Serialize so the console shows plain data instead of LWC read-only proxies.
      console.log(
        "getHouseholdMembersAndAccounts →",
        JSON.parse(JSON.stringify(data))
      );
      const mapped = mapHouseholdResponse(data);
      // Required before the party rows are grouped, not merely useful: an account's role maps back
      // to a slot through its registration, so without the attributes every account would resolve to
      // the single-owner default and the roles it has no slot for would be dropped from the rebuild.
      // Memoized, so this is the same fetch connectedCallback already started.
      await this._prefetchRegistrationAttributes();
      // The related-party roles are resolved before anything reads a member's type: a role decides
      // which record type a person member is presented as, and that in turn selects the field set
      // read back below and the schema the interview opens. Both sources of members are considered —
      // the model's copies carry the interview form data (the saved state plus any unsaved
      // addition), the mapped ones the rows the server has just returned.
      const { memberRows, accountRows } =
        await this._fetchRelatedPartyRows(mapped);
      // Member rows only: a role here decides how a person is presented, and an account's ownership
      // slots are positions on the account rather than roles its owners carry.
      mapped.householdMembers = applyPartyRoles(
        mapped.householdMembers,
        derivePartyRoles(
          [...(this.model.householdMembers || []), ...mapped.householdMembers],
          memberRows
        )
      );
      // Person and account records carry only pure record fields, so the record is their source of
      // truth: read the full configured field set back so it — not the saved envelope-state blob —
      // drives the interview prefill (applied in _mergeServerEntities).
      const [memberValues, accountValues, serviceValues, caseRead] =
        await Promise.all([
          this._fetchMemberRecordValues(mapped),
          this._fetchAccountRecordValues(mapped),
          this._fetchServiceRecordValues(mapped),
          this._fetchActionCaseRecordValues(mapped)
        ]);
      this._caseOriginalValues = caseRead.originals;
      this._mergeServerEntities(
        mapped,
        memberValues,
        accountValues,
        serviceValues,
        caseRead.values
      );
      this._seedRelatedPartiesFromRecords(memberRows, accountRows);
    } catch (error) {
      console.error("getHouseholdMembersAndAccounts failed", error);
    }
  }

  // The party records of everything either source of the household knows about, read once per fetch:
  // the business/trust members' Account_Account_Relationship__c rows and the Financial Accounts'
  // Financial_Account_Role__c rows. Both are normalized to one flat row shape
  // ({ entityAccountId, relatedAccountId, name, role }) so the grouping below stays a single path.
  //
  // The two sets are returned apart rather than merged because they are not interchangeable: only
  // memberRows decide how a person is presented in the outline (derivePartyRoles), since an account
  // ownership slot is a position on an account, not a role a person carries. Each set is [] when
  // nothing can hold records yet and null when its read fails — callers treat "no rows" and
  // "unknown" differently, since only the former may clear a saved value.
  async _fetchRelatedPartyRows(mapped) {
    const idsFor = (groupIds, predicate) => [
      ...new Set(
        groupIds
          .flatMap((groupId) => [
            ...(this.model[groupId] || []),
            ...(mapped[groupId] || [])
          ])
          .filter(predicate)
          .map((entity) => entity.id)
      )
    ];
    const memberIds = idsFor(["householdMembers"], ownsRelatedPartyRecords);
    const accountIds = idsFor(
      [...ACCOUNT_GROUP_IDS],
      ownsRelatedPartyRecords
    );
    const [memberRows, accountRows] = await Promise.all([
      this._readMemberPartyRows(memberIds),
      this._readAccountRoleRows(accountIds)
    ]);
    return { memberRows, accountRows };
  }

  // Account_Account_Relationship__c rows for the given business/trust members.
  async _readMemberPartyRows(entityAccountIds) {
    if (!entityAccountIds.length) {
      return [];
    }
    try {
      return (await getRelatedParties({ entityAccountIds })) || [];
    } catch (error) {
      console.error("getRelatedParties failed", error);
      return null;
    }
  }

  // Financial_Account_Role__c rows for the given accounts/DPIs, mapped onto the member row shape so
  // both sets group through the same code.
  async _readAccountRoleRows(financialAccountIds) {
    if (!financialAccountIds.length) {
      return [];
    }
    try {
      const rows = (await getAccountRoles({ financialAccountIds })) || [];
      return rows.map((row) => ({
        entityAccountId: row.financialAccountId,
        relatedAccountId: row.accountId,
        name: row.name,
        role: row.role
      }));
    } catch (error) {
      console.error("getAccountRoles failed", error);
      return null;
    }
  }

  // Rebuild the Related Parties value of every entity that holds party records — a business/trust
  // member from its relationship rows, a Financial Account from its role rows — so the records are
  // what the section shows. The rebuild adds to the current value rather than replacing it: a party
  // no record confirms is kept and, when it already has a person record, its action is marked for
  // reconcile and the missing row is written before this returns. An action whose parties are still
  // waiting to persist is left alone so an unsaved change can't be read back over, and a failed read
  // leaves its own entities untouched (each set is skipped independently).
  _seedRelatedPartiesFromRecords(memberRows, accountRows) {
    const sources = [
      { groupIds: ["householdMembers"], rows: memberRows },
      { groupIds: [...ACCOUNT_GROUP_IDS], rows: accountRows }
    ];
    // Set when the rebuild finds a party whose record is missing, so the reconcile that repairs it
    // runs from here. The autosave cycle can't be relied on for it: its timer is only armed by a field
    // edit, so a party left unlinked by an earlier failure would otherwise stay unlinked for as long as
    // the user only ever opens the envelope.
    let hasUnreconciled = false;
    const rowsByEntity = new Map();
    const entities = [];
    sources.forEach((source) => {
      // A failed read is not an empty one: leave this source's entities as they are.
      if (!source.rows) {
        return;
      }
      source.groupIds.forEach((groupId) => {
        entities.push(
          ...(this.model[groupId] || []).filter(ownsRelatedPartyRecords)
        );
      });
      source.rows.forEach((row) => {
        const current = rowsByEntity.get(row.entityAccountId) || [];
        current.push(row);
        rowsByEntity.set(row.entityAccountId, current);
      });
    });
    if (!entities.length) {
      return;
    }
    entities.forEach((entity) => {
      const entityRows = rowsByEntity.get(entity.id) || [];
      // Grouped up front so the actions owing another reconcile pass are known before the write and
      // the model update stays a plain transform.
      const valueByAction = new Map();
      (entity.actions || []).forEach((action) => {
        if (this._relatedPartiesDirty[action.id]) {
          return;
        }
        const { value, hasUnlinked } = this._groupRelatedParties(
          entity,
          action.formData || {},
          entityRows
        );
        valueByAction.set(action.id, value);
        if (hasUnlinked) {
          this._relatedPartiesDirty[action.id] = true;
          hasUnreconciled = true;
        }
      });
      if (!valueByAction.size) {
        return;
      }
      this._updateEntity(entity.id, (target) => ({
        ...target,
        actions: (target.actions || []).map((action) => {
          if (!valueByAction.has(action.id)) {
            return action;
          }
          return {
            ...action,
            formData: {
              ...(action.formData || {}),
              [RELATED_PARTIES_FIELD_KEY]: valueByAction.get(action.id)
            }
          };
        })
      }));
    });
    // Skipped while a drain is running: that drain is already writing these relationships, and it
    // re-reads the household on success, which is what brought us back here.
    if (hasUnreconciled && !this._reconcile.draining) {
      this._reconcileRelatedPartiesNow();
    }
  }

  // Group an entity's party records into the Related Parties value shape
  // ({ [requirementKey]: [{ id, name }] }), reading the role through whichever vocabulary the entity
  // persists in. A role the entity has no requirement for — a record created outside the wizard — is
  // skipped. A party the current value holds that no row confirms is carried over rather than
  // dropped: it is either still waiting for its person record, or its own row has not been written
  // yet. The latter is reported back as `hasUnlinked` so the caller can have the save cycle
  // reconcile it, since dropping it would silently discard an addition the user made.
  // Returns { value, hasUnlinked }.
  _groupRelatedParties(entity, formData, rows) {
    const value = {};
    const keyForRole = (role) =>
      holdsAccountRoleRecords(entity)
        ? requirementKeyForAccountRole(
            entity,
            role,
            formData,
            this._registrationAttributes
          )
        : requirementKeyForAarRole(entity, role, formData);
    rows.forEach((row) => {
      const key = keyForRole(row.role);
      if (!key) {
        return;
      }
      value[key] = [
        ...(value[key] || []),
        { id: row.relatedAccountId, name: row.name }
      ];
    });
    const current = formData[RELATED_PARTIES_FIELD_KEY] || {};
    // Confirmed across every requirement rather than per requirement: a role can map back to a
    // different subsection than the party was added under, and the party must not then be carried
    // into both.
    const linked = new Set(
      Object.values(value).flatMap((parties) =>
        parties.map((party) => party.id)
      )
    );
    let hasUnlinked = false;
    Object.keys(current).forEach((key) => {
      const carried = (current[key] || []).filter(
        (party) => !linked.has(party.id)
      );
      if (!carried.length) {
        return;
      }
      if (carried.some((party) => isRecordId(party.id))) {
        hasUnlinked = true;
      }
      value[key] = [...(value[key] || []), ...carried];
    });
    return { value, hasUnlinked };
  }

  // Read the live Account field values for the persisted person members — the individuals and the
  // members presented as a related-party role — grouped by the record type each is presented as, so
  // the read set always matches the interview's own field set. One call per distinct record type;
  // a call that fails yields no values for its members rather than blanking the whole read. Business
  // and trust members are left out: they prefill from the envelope state. Returns a map of record
  // id → { fieldApiName: value }, or {} when there are no persisted person members (non-fatal:
  // prefill then falls back to the blob values already in the model).
  async _fetchMemberRecordValues(mapped) {
    const idsByType = new Map();
    (mapped.householdMembers || []).forEach((entity) => {
      const key = resolveSchemaKey(entity);
      if (
        !isRecordId(entity.id) ||
        !key ||
        persistedMemberTypeFor(entity.type) !== "client"
      ) {
        return;
      }
      idsByType.set(key.type, [...(idsByType.get(key.type) || []), entity.id]);
    });
    if (!idsByType.size) {
      return {};
    }
    const valuesByType = await Promise.all(
      [...idsByType.entries()].map(([type, recordIds]) =>
        getRecordValuesForType({
          objectName: "Account",
          type,
          recordIds
        }).catch((error) => {
          console.error("getRecordValuesForType failed", error);
          return {};
        })
      )
    );
    // Keyed by record id throughout, and a member is read under one type only, so the maps merge.
    return Object.assign({}, ...valuesByType);
  }

  // Read the live field values for the persisted accounts and DPIs so the record — not the blob —
  // drives interview prefill. Accounts and DPIs are the same object but carry different field
  // schemas ('ISA - Fin Acct' vs 'ISA - DPI'), so each group is read under its own type in a
  // separate call, mirroring _fetchMemberRecordValues' per-type reads.
  //
  // An account interview is mixed-object: some of its Envelope_Field__mdt rows target the account's
  // wizard Case rather than Financial_Account__c, and getRecordValuesForType filters on the object,
  // so those rows need their own read. It is keyed by Financial Account id as well, which is what
  // lets both halves of the form prefill from one value map.
  //
  // Returns a map of record id -> { fieldApiName: value }, or {} when there are none or the reads
  // fail (non-fatal: prefill then falls back to the blob values already in the model).
  async _fetchAccountRecordValues(mapped) {
    const idsFor = (list) =>
      (list || [])
        .filter((entity) => isRecordId(entity.id))
        .map((entity) => entity.id);
    const reads = [
      { type: "ISA - Fin Acct", recordIds: idsFor(mapped.accounts) },
      { type: "ISA - DPI", recordIds: idsFor(mapped.dpisSponsor) }
    ].filter((read) => read.recordIds.length);
    if (!reads.length) {
      return {};
    }
    const results = await Promise.all(
      reads.flatMap(({ type, recordIds }) => [
        getRecordValuesForType({
          objectName: "Financial_Account__c",
          type,
          recordIds
        }).catch((error) => {
          console.error("getRecordValuesForType failed", error);
          return {};
        }),
        // The Case half of the same interview. Null values come back too, deliberately: the record
        // is the source of truth, so a value cleared on the Case has to clear in the interview
        // rather than let the stale blob value show through the overlay.
        getCaseValuesForAccounts({
          type,
          financialAccountIds: recordIds
        }).catch((error) => {
          console.error("getCaseValuesForAccounts failed", error);
          return {};
        }),
        // The product the same interview selected. It is a related record, not a field on the
        // account, so the account read above never sees it. Nulls come back for the same reason the
        // Case read returns them.
        getRelatedProductValuesForAccounts({
          type,
          financialAccountIds: recordIds
        }).catch((error) => {
          console.error("getRelatedProductValuesForAccounts failed", error);
          return {};
        })
      ])
    );
    // Merged one level deep rather than by a plain Object.assign: each record belongs to exactly one
    // group, but its account, Case and product values arrive as separate maps under the same record
    // id, and a top-level assign would let a later one replace the first instead of combining them.
    // The field sets are disjoint (a schema row names one object), so the inner spread never has to
    // resolve a conflict.
    const merged = {};
    results.forEach((result) => {
      Object.entries(result || {}).forEach(([recordId, values]) => {
        merged[recordId] = { ...(merged[recordId] || {}), ...values };
      });
    });
    return merged;
  }

  // Read the live Service__c field values for the persisted service agreements, driven by the
  // 'ISA - Service Agreement' form schema so the read set always matches the interview fields.
  // Returns a map of record id -> { fieldApiName: value }, or {} when there are none or the read
  // fails (non-fatal: prefill then falls back to the blob values already in the model).
  async _fetchServiceRecordValues(mapped) {
    const serviceIds = (mapped.serviceAgreements || [])
      .filter((entity) => isRecordId(entity.id))
      .map((entity) => entity.id);
    if (!serviceIds.length) {
      return {};
    }
    try {
      return await getRecordValuesForType({
        objectName: "Service__c",
        type: "ISA - Service Agreement",
        recordIds: serviceIds
      });
    } catch (error) {
      console.error("getRecordValuesForType failed", error);
      return {};
    }
  }

  // Read the live Case field values for the persisted Account Action Items, so their interviews
  // prefill from the record rather than only from the envelope-state blob. Each action type is its
  // own interview schema ('Additional Funding', 'Third Party Money Movement', …), so the entities are
  // grouped by type and read one call per type — the same per-type shape as _fetchMemberRecordValues.
  //
  // A member action item is read twice: once for the values its interview prefills from, and once
  // for the frozen baseline those values are compared against, which is what the interview marks
  // its changed fields from. The two are returned apart because only the first is prefill — the
  // baseline must never be overlaid onto form data.
  //
  // Returns { values, originals }, each a map of Case id -> { fieldApiName: value } and each {} when
  // there are none or the read fails (non-fatal: prefill then falls back to whatever the model
  // already holds, and an absent baseline simply means no change markers).
  async _fetchActionCaseRecordValues(mapped) {
    const idsByType = {};
    // A member action's interview is the review case's own 'Proposed Changes' form, so its
    // proposed values read generically by schema type like any other case's. Its baseline — the
    // member's CURRENT Account values, keyed by the proposing Case field — has its own
    // metadata-driven read, keyed by member and re-keyed to the case below (two actions on one
    // member share the member's baseline).
    const memberActionPairs = [];
    (mapped.cases || []).forEach((entity) => {
      if (!isRecordId(entity.id)) {
        return;
      }
      const type = resolveSchemaKey(entity)?.type;
      if (!type) {
        return;
      }
      if (isMemberActionType(entity.type)) {
        memberActionPairs.push({
          caseId: entity.id,
          accountId: entity.memberAccountId
        });
      }
      (idsByType[type] = idsByType[type] || []).push(entity.id);
    });
    const reads = Object.entries(idsByType);
    if (!reads.length) {
      return { values: {}, originals: {} };
    }
    const accountIds = [
      ...new Set(memberActionPairs.map((pair) => pair.accountId).filter(Boolean))
    ];
    const [originalsByAccount, ...results] = await Promise.all([
      accountIds.length
        ? getOriginalAccountValues({
            type: PROPOSED_CHANGES_MDT,
            accountIds
          }).catch((error) => {
            console.error("getOriginalAccountValues failed", error);
            return {};
          })
        : {},
      ...reads.map(([type, recordIds]) =>
        getRecordValuesForType({
          objectName: "Case",
          type,
          recordIds
        }).catch((error) => {
          console.error("getRecordValuesForType failed", error);
          return {};
        })
      )
    ]);
    const originals = {};
    memberActionPairs.forEach(({ caseId, accountId }) => {
      if (originalsByAccount[accountId]) {
        originals[caseId] = originalsByAccount[accountId];
      }
    });
    // Keyed by Case id, and each Case is read under exactly one type, so the maps merge cleanly.
    // A member action's prefill is its baseline with the stored proposals on top: the interview
    // opens showing the member's current data, and only genuinely proposed fields differ from it.
    const values = Object.assign({}, ...results);
    Object.keys(originals).forEach((caseId) => {
      values[caseId] = { ...originals[caseId], ...(values[caseId] || {}) };
    });
    return { values, originals };
  }

  // Reconcile the mapped server entities into the model: append any server entity not already
  // present, refresh the ones that are, and drop the record-backed ones the server no longer returns.
  // Idempotent across the initial load and the post-persist re-fetch.
  //
  // Reconciling downward matters because an entity can now leave the envelope without this client
  // asking: the related-party reconcile unlinks a party that lost its last role. A reload reflects
  // that for free — the record-backed lists are stripped from the envelope state and rebuilt from the
  // server — so the merge has to reach the same result in-session. See the filter below for the rows
  // that are deliberately exempt.
  //
  // For an entity already present (restored from the persisted envelope-state blob), refresh the
  // server-authoritative fields from the fresh server version: the display label (name, meta) and the
  // submitted-derived flags (isNew, removable), so a record renamed or submitted since the last save
  // no longer shows a stale label or a still-editable draft. Only those server-derived fields are
  // refreshed; local state — chiefly the entity's `actions` and their in-progress interview form
  // data, plus the `addedInEnvelope` badge flag only this client sets — is preserved.
  //
  // Person members, Financial Accounts (accounts / DPIs) and Service Agreements are the exception:
  // because their record is the source of truth, the passed `memberValues` / `accountValues` /
  // `serviceValues` and `caseValues` (live record field values, keyed by record id) are overlaid onto
  // each matching action's form data so the record — not the blob — drives prefill. Blob-only keys
  // survive (record values win only for the keys they carry). See _applyMemberRecordValues /
  // _applyAccountRecordValues / _applyServiceRecordValues / _applyCaseRecordValues.
  _mergeServerEntities(
    mapped,
    memberValues = {},
    accountValues = {},
    serviceValues = {},
    caseValues = {}
  ) {
    const next = { ...this.model };
    // The record-driven overlays, composed; each is group-guarded, so applying all to every entity
    // is safe (a no-op for the groups it doesn't own).
    const withRecordValues = (entity) =>
      this._applyCaseRecordValues(
        this._applyServiceRecordValues(
          this._applyAccountRecordValues(
            this._applyMemberRecordValues(entity, memberValues),
            accountValues
          ),
          serviceValues
        ),
        caseValues
      );
    GROUP_IDS.forEach((groupId) => {
      const current = this.model[groupId];
      const mappedById = new Map(
        (mapped[groupId] || []).map((entity) => [entity.id, entity])
      );
      const reconciled = current
        .filter((entity) => {
          // A record-backed entity the server no longer returns has left this envelope — unlinked by
          // the related-party reconcile when it lost its last role, or removed from another screen —
          // so it goes from the model too. Without this the outline keeps showing it until a reload,
          // which rebuilds the record-backed lists from the server and so drops it by construction.
          //
          // Rows the response says nothing about are never pruned: those in a group the household
          // fetch does not return, and those the server has no record for — a member type with no
          // record-type mapping, or an addition whose record id has not landed yet.
          // `addedInEnvelope` marks a row this session created and still owns, which a response that
          // started before the create would otherwise remove.
          if (
            !RECORD_BACKED_GROUP_IDS.includes(groupId) ||
            !isRecordId(entity.id) ||
            entity.addedInEnvelope
          ) {
            return true;
          }
          return mappedById.has(entity.id);
        })
        .map((entity) => {
          const server = mappedById.get(entity.id);
          if (!server) {
            // No server counterpart to refresh the label from, but the record overlays still apply:
            // an Account Action Item is never in the household response, so this is the only path
            // its Case values reach it by. A no-op for the rows that genuinely have no record —
            // their ids are absent from every values map.
            return withRecordValues(entity);
          }
          const merged = {
            ...entity,
            // Refresh the server-derived display label from the record: the blob carries the
            // name/meta as of the last save, which go stale if the record is renamed (e.g. its Name
            // edited in the interview) between visits.
            name: server.name,
            meta: server.meta,
            isNew: server.isNew,
            removable: server.removable,
            // A member's type is re-derived on every fetch from its record type plus the
            // related-party roles it plays (see applyPartyRoles), so a role gained or lost is
            // reflected and a stale token from the blob is never inherited. Members only: an
            // account's type comes from its add form and is absent from the server projection, so
            // copying it would erase it.
            ...(groupId === "householdMembers"
              ? {
                  type: server.type,
                  typeLabel: server.typeLabel,
                  hasClientProfile: server.hasClientProfile,
                  pendingElsewhere: server.pendingElsewhere
                }
              : {})
          };
          return withRecordValues(merged);
        });
      const existingIds = new Set(current.map((entity) => entity.id));
      const additions = (mapped[groupId] || [])
        .filter((entity) => !existingIds.has(entity.id))
        .map((entity) => withRecordValues(entity));
      next[groupId] = [...reconciled, ...additions];
    });
    this.model = next;
  }

  // Overlay a person member's live Account field values onto each of its action's form data, so the
  // record drives prefill. Blob values are spread first, then the record values, so the record wins
  // for the keys it carries while any blob-only keys are kept. Entities that are not person members
  // (and person members with no fetched values) are returned unchanged.
  _applyMemberRecordValues(entity, memberValues) {
    if (
      entity.groupId !== "householdMembers" ||
      persistedMemberTypeFor(entity.type) !== "client" ||
      !memberValues[entity.id]
    ) {
      return entity;
    }
    const recordValues = memberValues[entity.id];
    return {
      ...entity,
      actions: (entity.actions || []).map((action) => ({
        ...action,
        formData: { ...(action.formData || {}), ...recordValues }
      }))
    };
  }

  // Overlay an account/DPI entity's live Financial_Account__c field values onto each of its action's
  // form data, so the record drives prefill. Blob values are spread first, then the record values, so
  // the record wins for the keys it carries while any blob-only keys are kept. Non-account entities
  // (and accounts with no fetched values) are returned unchanged.
  _applyAccountRecordValues(entity, accountValues) {
    if (!ACCOUNT_GROUP_IDS.has(entity.groupId) || !accountValues[entity.id]) {
      return entity;
    }
    const recordValues = accountValues[entity.id];
    return {
      ...entity,
      actions: (entity.actions || []).map((action) => ({
        ...action,
        formData: { ...(action.formData || {}), ...recordValues }
      }))
    };
  }

  // Overlay a service-agreement entity's live Service__c field values onto each of its action's form
  // data, so the record drives prefill. Blob values are spread first, then the record values, so the
  // record wins for the keys it carries while any blob-only keys are kept. Non-service entities (and
  // services with no fetched values) are returned unchanged.
  _applyServiceRecordValues(entity, serviceValues) {
    if (entity.groupId !== "serviceAgreements" || !serviceValues[entity.id]) {
      return entity;
    }
    const recordValues = serviceValues[entity.id];
    return {
      ...entity,
      actions: (entity.actions || []).map((action) => ({
        ...action,
        formData: { ...(action.formData || {}), ...recordValues }
      }))
    };
  }

  // Overlay an Account Action Item's live Case field values onto each of its action's form data, so
  // the record drives prefill. Blob values are spread first, then the record values, so the record
  // wins for the keys it carries while blob-only keys (the DMS actions' trade instructions) are kept.
  // Non-case entities (and cases with no fetched values) are returned unchanged.
  _applyCaseRecordValues(entity, caseValues) {
    if (entity.groupId !== "cases" || !caseValues[entity.id]) {
      return entity;
    }
    const recordValues = caseValues[entity.id];
    return {
      ...entity,
      actions: (entity.actions || []).map((action) => ({
        ...action,
        formData: { ...(action.formData || {}), ...recordValues }
      }))
    };
  }

  // Entities shown in the outline rail, keyed by group id. Each group is the model list with
  // newly added rows sorted to the top. Outline items read { id, name, meta, amount,
  // iconVariant, isNew, addedInEnvelope }, all carried on the model entry. `canAddActions`
  // tells the row whether its type has any Add action item entries — false hides the "+"
  // (e.g. DPIs, services).
  // `isComplete` drives the row's progress indicator (green check vs. in-progress dot).
  get householdData() {
    const data = {};
    GROUP_IDS.forEach((groupId) => {
      data[groupId] = this._orderGroup(this.model[groupId], groupId).map(
        (entity) => ({
          ...entity,
          canAddActions: resolveActionCatalog(entity).length > 0,
          isComplete: this._entityActionsComplete(entity),
          // Resolved here rather than carried on the model entry so the row picks up its describing
          // fields the moment the interview captures them, instead of keeping whatever its add path
          // happened to pass. See isaMeta.
          ...(ISA_KIND_LABELS[groupId] ? { meta: isaMeta(entity) } : {})
        })
      );
    });
    return data;
  }

  // Content-area Action Items: a flat (ungrouped) list of the entities that carry action
  // cards (added this session, or given an action via the Add action item dialog). Ordered
  // like the sidebar reads top-to-bottom — members first, then the account-like groups — with
  // each group ordered by the shared _orderGroup rule so the list mirrors the sidebar.
  get sortedItems() {
    const items = [];
    GROUP_IDS.forEach((groupId) => {
      // Only unsubmitted (draft) entities are outstanding action items; a submitted record is
      // existing and locked, so it stays in the outline rail but drops out of the workspace.
      const withActions = this.model[groupId].filter(
        (entity) => entity.actions && entity.actions.length && entity.isNew
      );
      this._orderGroup(withActions, groupId).forEach((entity) => {
        // A new record's single action card removes the whole record on confirm, so its
        // overflow menu mirrors the sidebar's entity-remove label (e.g. "Remove household
        // member"); every other card just removes its action.
        const cascades = entity.isNew && entity.actions.length <= 1;
        const removeMenuLabel = cascades
          ? GROUPS[groupId]?.removeLabel || "Remove action"
          : "Remove action";
        // Real "N inputs missing" per action from the prefetched schema and the action's saved
        // form data; empty while the schema is still loading (never a placeholder number). A
        // trailing '+' shows when an unfilled Key Point gates additional unknown fields.
        // Related parties the entity still owes count alongside the metadata fields, as do
        // values that fail their format rule, since all of them are inputs the action needs
        // before it can be submitted. The same completion measure flips the card's status badge
        // to Completed once nothing is outstanding.
        const schema = this._schemaForEntity(entity);
        const actions = entity.actions.map((action) => {
          const formData = action.formData || {};
          const { count, hasPlus, isComplete } = actionCompletion(
            schema,
            entity,
            formData,
            this.userContext,
            this._registrationAttributes
          );
          return {
            ...action,
            removeMenuLabel,
            missingLabel: schema ? missingInputsLabel(count, hasPlus) : "",
            isComplete,
            statusLabel: isComplete ? "Completed" : action.statusLabel
          };
        });
        items.push({
          ...entity,
          actions,
          // Keeps the card's type text in step with the sidebar subtitle (see isaMeta); without it
          // the same record reads one way in the rail and another in the workspace.
          ...(ISA_KIND_LABELS[groupId] ? { typeLabel: isaMeta(entity) } : {})
        });
      });
    });
    return items;
  }

  get hasItems() {
    return this.sortedItems.length > 0;
  }

  // True once the envelope is ready to review: it has at least one action item and none of them
  // still owes inputs — blank or invalid (same per-action completion the cards and submit gate use).
  get isReviewable() {
    const items = this.sortedItems;
    return (
      items.length > 0 &&
      items.every((item) => item.actions.every((action) => action.isComplete))
    );
  }

  // True while at least one action still owes inputs — the same projection the Review
  // Missing Items screen renders from, so the header button is disabled exactly when
  // the screen would be empty.
  get hasMissingItems() {
    return this._buildMissingItems().length > 0;
  }

  // True when the items region should render: there are items to show, or the
  // inline add form is open (which replaces the CTA at the top of the region).
  get hasItemsRegion() {
    return this.hasItems || this.activeForm !== null;
  }

  // The action items still missing inputs, fed to the Review Missing Items screen. Maps the
  // snapshot taken when the screen opened (see _openMissingItemsView), so items stay listed
  // while the user fills them in. The Related Parties part reads its members live from the owning
  // action's formData: a satisfied requirement renders its member cards and clears the
  // "Inputs missing" status, but the requirement block itself stays for the rest of the visit.
  get missingActionItems() {
    return (this._missingItemsSnapshot || []).map((actionItem) => {
      const found = this._findEntityByActionId(actionItem.key);
      const parties =
        found?.action?.formData?.[RELATED_PARTIES_FIELD_KEY] || {};
      return {
        ...actionItem,
        sections: (actionItem.sections || []).map((section) => ({
          ...section,
          parts: (section.parts || []).map((part) => {
            if (!part.requirements) {
              return part;
            }
            return {
              ...part,
              requirements: part.requirements.map((requirement) => {
                const owners = parties[requirement.key];
                return owners && owners.length
                  ? { ...requirement, owners, statusLabel: null }
                  : requirement;
              })
            };
          })
        }))
      };
    });
  }

  get gridClass() {
    return this.isNavCollapsed
      ? "shell__grid shell__grid--nav-collapsed"
      : "shell__grid";
  }

  // Confirm-dialog copy follows the pending target: an outline row uses its entity-type
  // remove label (e.g. "Remove account"); an action card keeps the generic "action" wording.
  get removeDialogTitle() {
    return this._removeTarget === "entity" && this._removeLabel
      ? `${this._removeLabel}?`
      : "Remove action?";
  }

  get removeDialogConfirmLabel() {
    return this._removeTarget === "entity" && this._removeLabel
      ? this._removeLabel
      : "Remove action";
  }

  get removeDialogMessageBefore() {
    return this._removeTarget === "entity"
      ? "This will permanently remove "
      : "This will permanently remove action ";
  }

  // A cascading removal (a new record's last action) spells out why the record itself goes; the
  // other cases just warn that the saved interview data is lost.
  get removeDialogMessageAfter() {
    return this._removeCascades
      ? " from the household, since a new record can't exist without an action. All of the interview's saved data will be lost."
      : ". All of the interview's saved data will be lost.";
  }

  get isItemsView() {
    return this.activeView === "items";
  }

  get isDocumentsView() {
    return this.activeView === "documents";
  }

  get isMissingItemsView() {
    return this.activeView === "missingItems";
  }

  get isReviewView() {
    return this.activeView === "review";
  }

  handleNavToggle() {
    this.isNavCollapsed = !this.isNavCollapsed;
  }

  // Inline add from the Household Outline rail: the event already carries the target group id.
  async handleAddEntity(event) {
    const detail = event.detail || {};
    await this._addEntity(resolveGroup(detail), detail);
    this.refs.outline?.clearAdd();
  }

  handleAddAction(event) {
    const variant = event?.detail?.action === "addIsa" ? "isa" : "member";
    Promise.resolve().then(() => {
      this.activeForm = variant;
    });
  }

  handleFormCancel() {
    Promise.resolve().then(() => {
      this.activeForm = null;
    });
  }

  // Content-area add form submit: the variant + selected type resolve to the target group.
  // The form closes only after a successful add, so a failed save keeps the input intact.
  async handleAddItem(event) {
    const detail = event.detail || {};
    const added = await this._addEntity(resolveGroup(detail), detail);
    if (added) {
      this.activeForm = null;
    }
  }

  // Add a new entity to its group's list and render it as an Action Item. When the group has
  // a persistence call and the envelope is known, the record is created first and its id
  // becomes the entity id; groups without one stay local with a temporary id. Returns false
  // when persistence fails (nothing is added). The status/missing labels are placeholders
  // until real progress data is wired up.
  async _addEntity(groupId, detail) {
    const cfg = GROUPS[groupId];
    if (!cfg) {
      return false;
    }
    let persistedId = null;
    if (cfg.persist && this.envelopeId) {
      try {
        this.isAddingItem = true;
        persistedId = await cfg.persist(detail, this.envelopeId);
        // Re-run the aggregate load so the logged server state reflects the new record.
        if (persistedId && this.householdId) {
          this._fetchHouseholdMembersAndAccounts();
        }
        // The persist may have created the entity's required documents.
        if (persistedId) {
          this._refreshRequiredDocuments();
        }
      } catch (error) {
        console.error(`persist ${groupId} failed`, error);
        this._showToast(
          "Error",
          error?.body?.message || "Unable to save the new item.",
          "error"
        );
        return false;
      } finally {
        this.isAddingItem = false;
      }
      // A persist that ran but returned no id created no record — an action type with no server
      // routing does this. Adding the entity anyway would leave a card backed by nothing, which
      // looks saved until the next load drops it, so surface the failure instead.
      if (!persistedId) {
        this._showToast(
          "Error",
          "Unable to save the new item.",
          "error"
        );
        return false;
      }
    }
    const id = persistedId || `${groupId}-${this._seq++}`;
    const typeLabel = detail.typeLabel || "";
    const entity = {
      id,
      groupId,
      name: (detail.nickname || "").trim(),
      // Raw type token (e.g. 'trust') — maps to the Envelope_Field__mdt schema for the
      // action-details form; typeLabel is the display string built into the subtitle.
      type: detail.type || "",
      typeLabel,
      // Sidebar subtitle from the data we have so far (just the type); the interview flow
      // enriches it (owner/custodian/account #) via buildMeta later. No value is shown
      // until a real amount exists.
      meta: buildMeta([typeLabel]),
      iconVariant: cfg.iconVariant,
      isNew: true,
      // Session-added entities can be removed; existing (mock-seeded) ones cannot.
      removable: true,
      // Marks an entity created through this envelope — the only place this flag is set. It
      // round-trips through the envelope-state blob and drives new-rows-first ordering; the "New"
      // badge is driven by `isNew` (unsubmitted), not this flag. Server-loaded rows never carry it.
      addedInEnvelope: true,
      // The action item's parent. Only one of the two is ever set — see _actionParentId.
      financialAccountId : detail.financialAccountId,
      memberAccountId: detail.memberAccountId,
      actions: [
        {
          id: `${id}-1`,
          iconVariant: cfg.cardIconVariant,
          // The group's title names the work for a group whose entities all do the same thing
          // ("Open Account"). An entity whose add detail names its own action — an Account Action
          // Item, where the card is the action — titles the card with that instead.
          title: detail.actionLabel || cfg.actionTitle,
          statusLabel: "In Progress",
          // Carry the add form's answers into the interview so they open prefilled and
          // aren't counted as missing inputs.
          formData: cfg.initialFormData ? cfg.initialFormData(detail) : {}
        }
      ]
    };
    this.model = {
      ...this.model,
      [groupId]: [...this.model[groupId], entity]
    };
    return true;
  }

  // Rename/Delete open the shared dialogs imperatively (no is-open flag); the
  // remaining actions are still placeholders until their behavior is wired up.
  handleHeaderAction(event) {
    const action = event?.detail?.action;
    if (action === "rename") {
      this.refs.renameModal.open();
      return;
    }
    if (action === "delete") {
      this.refs.deleteModal.open();
      return;
    }
    if (action === "manageDocuments") {
      this._openDocumentsView();
      return;
    }
    if (action === "reviewMissingItems") {
      this._openMissingItemsView();
      return;
    }
    this._showToast("Action", "Coming soon", "info");
  }

  // Return from a content sub-view (Manage Documents, Review Missing Items, Review & Submit)
  // to the action-items view and clear its breadcrumb/header. Flush first so a pending
  // Review-Missing-Items edit isn't lost on the way out (no-ops when nothing is pending).
  handleSubViewBack() {
    this._flushPendingSave();
    this.isMissingItemsLoading = false;
    Promise.resolve().then(() => {
      this.activeView = "items";
    });
    this._dispatchCrumb(null);
  }

  // "Manage Documents" from the Review & Submit documents card: same transition as the
  // content-header action.
  handleReviewManageDocuments() {
    this._openDocumentsView();
  }

  // Edit on a Review & Submit summary row: the row key is the action id, so route into that
  // action's interview. activeView intentionally stays 'review' (the interview template takes
  // precedence over it), which handleActionBack uses to return here afterwards.
  handleReviewEdit(event) {
    this._openAction(event?.detail?.key);
  }

  // Submit from the Review & Submit confirmation, gated on the envelope actually being ready:
  // every action must clear the same completion measure the cards show, and no drafted value may
  // violate its configured format rule. Once the gate passes, hand the envelope to the backend
  // submit endpoint; on success the host leaves the workspace (the envelope is locked afterward).
  async handleSubmitEnvelope() {
    const blockers = this._collectSubmitBlockers();
    if (blockers.length) {
      this._showToast(
        "Envelope isn't ready to submit",
        blockers.join(" "),
        "error"
      );
      return;
    }
    // Submitting is final; guard against a second round-trip from a repeated click.
    if (this.isSubmitting) {
      return;
    }
    this.isSubmitting = true;
    try {
      // Trade instructions write through to Order_Ticket__c/Order__c first — the ticket is the
      // request of record, so a failure here aborts the submit.
      await this._persistTradeInstructions();
      await submitEnvelope({ envelopeId: this.envelopeId });
      this._showToast(
        "Envelope submitted",
        "The envelope was sent to the home office.",
        "success"
      );
      // The envelope is locked after submission — let the host return to the list.
      this.dispatchEvent(
        new CustomEvent("envelopesubmitted", {
          detail: { envelopeId: this.envelopeId }
        })
      );
    } catch (error) {
      this._showToast(
        "Error",
        error?.body?.message || "Unable to submit the envelope.",
        "error"
      );
    } finally {
      this.isSubmitting = false;
    }
  }

  // Submit blockers across the whole envelope: entities whose actions still miss required inputs,
  // and drafted values that fail their configured format rule. Checked from the draft data — the
  // interview DOM isn't rendered on the review screen, so reportValidity can't run here.
  _collectSubmitBlockers() {
    const incomplete = [];
    const invalid = [];
    for (const groupId of GROUP_IDS) {
      for (const entity of this.model[groupId] || []) {
        // Only this envelope's own action items owe inputs — the same set the workspace
        // (sortedItems) and the Missing Items count (_missingItemsTotalForSave) already use.
        // The household fetch hands every member, account, DPI and service agreement a
        // synthetic action, so testing actions.length alone swept in every record in the
        // household: opening an envelope on a 149-account household made submit report
        // missing inputs for records the envelope never touched. A submitted record is
        // locked and owes nothing; adding an action item to one raises a new unsubmitted
        // entity, which is caught here on its own merits.
        if (!entity.actions?.length || !entity.isNew) {
          continue;
        }
        const actions = entity.actions;
        let invalidCount = 0;
        for (const action of actions) {
          const formData = action.formData || {};
          for (const key of Object.keys(formData)) {
            const rule = this._fieldRuleFor(entity, key);
            if (rule && !isFormatValid(rule, formData[key])) {
              invalidCount += 1;
              invalid.push(`${entity.name} — ${rule.label || key}`);
            }
          }
        }
        // An invalid value also holds the entity short of complete, so name it under "missing"
        // only when nothing of its own is invalid — the invalid list already names the exact field.
        if (!invalidCount && !this._entityActionsComplete(entity)) {
          incomplete.push(entity.name);
        }
      }
    }
    // Trade instructions enforce their own completeness rule (fixed-$ within the expected value,
    // percentage rows covering 100% of the remainder) — actionCompletion only measures the
    // metadata-driven fields, so the basis rules are checked here explicitly.
    const tradeIncomplete = this._collectTradeSources()
      // A submitted account's trade instructions are locked history, not an outstanding input
      // of this envelope, so they cannot block its submit.
      .filter((source) => source.isActionItem)
      .filter(
        (source) =>
          !strategyTotals(
            source.trade.strategies,
            source.funded ? source.trade.expectedAccountValue : null
          ).isComplete
      )
      .map((source) => source.entityName);
    const blockers = [];
    if (incomplete.length) {
      blockers.push(`Inputs are still missing for: ${incomplete.join(", ")}.`);
    }
    if (invalid.length) {
      blockers.push(`Fix invalid values: ${invalid.join(", ")}.`);
    }
    if (tradeIncomplete.length) {
      blockers.push(
        `Trade Instructions are incomplete for: ${tradeIncomplete.join(", ")}.`
      );
    }
    return blockers;
  }

  // Every interview carrying trade instructions to persist: DMS accounts/DPIs file a New DMS
  // Instructions ticket against the account; Update DMS Instructions cases file an Update ticket
  // against their Case. Entities without a persisted record id are skipped — their trade value
  // can't anchor to a ticket (and, accounts persisting at add time, shouldn't reach submit).
  _collectTradeSources() {
    const sources = [];
    for (const groupId of ACCOUNT_GROUP_IDS) {
      for (const entity of this.model[groupId] || []) {
        const formData = (entity.actions || [])[0]?.formData || {};
        const trade = formData.tradeInstructions;
        if (
          !trade ||
          !isDmsPlatform(formData.Managed_Account_Platform__c) ||
          !this._isRecordId(entity.id)
        ) {
          continue;
        }
        sources.push({
          entityName: entity.name,
          // Carried so submit validation can ignore rows that are not this envelope's action
          // items; persistence deliberately still writes every source it finds.
          isActionItem: Boolean(entity.isNew),
          trade,
          financialAccountId: entity.id,
          caseId: null,
          typeOfRequest: "New DMS Instructions",
          funded: true
        });
      }
    }
    for (const entity of this.model.cases || []) {
      const trade = (entity.actions || [])[0]?.formData?.tradeInstructions;
      const caseType = TRADE_CASE_REQUEST_TYPES[entity.type];
      if (!caseType || !trade || !this._isRecordId(entity.financialAccountId)) {
        continue;
      }
      sources.push({
        entityName: entity.name,
        isActionItem: Boolean(entity.isNew),
        trade,
        financialAccountId: entity.financialAccountId,
        caseId: this._isRecordId(entity.id) ? entity.id : null,
        typeOfRequest: caseType.typeOfRequest,
        funded: caseType.funded
      });
    }
    return sources;
  }

  // Write every collected trade-instruction interview through to Order_Ticket__c/Order__c.
  // saveTradeInstructions is idempotent per (envelope, account, case), so a retried submit
  // updates the same New ticket instead of stacking a duplicate request.
  async _persistTradeInstructions() {
    for (const source of this._collectTradeSources()) {
      const rows = normalizeStrategyRows(source.trade.strategies)
        .filter((row) => row.strategy)
        .map((row) => ({
          strategyId: row.strategy,
          basis: row.type,
          value:
            row.type === STRATEGY_BASIS.DOLLAR
              ? row.fundingAmount
              : row.fundingPercent
        }));
      if (!rows.length) {
        continue;
      }
      await saveTradeInstructions({
        payload: {
          envelopeId: this.envelopeId,
          financialAccountId: source.financialAccountId,
          caseId: source.caseId,
          typeOfRequest: source.typeOfRequest,
          expectedAccountValue: source.trade.expectedAccountValue,
          advisorNotes: source.trade.advisorNotes || "",
          strategies: rows
        }
      });
    }
  }

  // The account's current sleeve allocation, shaped as a Trade Instructions section value to seed
  // an Update DMS Instructions interview. Rows gain client ids; a fetch failure or an account with
  // no history seeds nothing (the section opens on its default single row).
  async _fetchCurrentTradeInstructions(financialAccountId) {
    if (!this._isRecordId(financialAccountId)) {
      return null;
    }
    try {
      const current = await getCurrentTradeInstructions({ financialAccountId });
      // The synthetic id is applied after the spread, so a DTO that later gains an `id` of its own
      // cannot silently overwrite it — the allocation table keys its rows on this and routes every
      // edit through it, so a duplicated or missing id mis-targets edits rather than failing loudly.
      const strategies = (current?.strategies || []).map((row, index) => ({
        ...row,
        id: `seed-${index + 1}`
      }));
      return strategies.length
        ? {
            expectedAccountValue: current.expectedAccountValue ?? null,
            strategies,
            advisorNotes: ""
          }
        : null;
    } catch (error) {
      // Non-fatal: the interview opens unseeded.
      return null;
    }
  }

  // Locally-added entities carry synthetic ids like "accounts-3"; only real record ids may cross
  // to Apex.
  _isRecordId(value) {
    return typeof value === "string" && /^[a-zA-Z0-9]{15,18}$/.test(value);
  }

  // Card overflow menu: open the shared removal dialog for the selected action card. Also serves
  // the action-details header's overflow menu, which emits the same `cardmenu` event for the open
  // action.
  handleCardMenu(event) {
    const { action, id, title } = event.detail || {};
    if (action === "remove") {
      this._openRemove("action", id, title);
    }
  }

  // Outline row overflow menu: open the shared removal dialog or add an existing
  // household member to the envelope as a client.
  handleItemMenu(event) {
    const { action, id, name, removeLabel } = event.detail || {};
    if (action === "remove") {
      this._openRemove("entity", id, name, removeLabel);
    } else if (action === "addclient") {
      this._addExistingMemberToEnvelope(id);
    }
  }

  async _addExistingMemberToEnvelope(entityId) {
    const entity = this._findEntity(entityId);
    if (!entity) {
      return;
    }
    const recordType = persistedMemberTypeFor(entity.type);
    if (!recordType) {
      return;
    }
    try {
      await saveEntity({
        acc: { Id: entity.id, RecordTypeId: recordType },
        envelopeId: this.envelopeId
      });
      this._updateEntity(entityId, (e) => ({
        ...e,
        typeLabel: "Client",
        meta: buildMeta(["Client"]),
        actions: [
          {
            id: `${e.id}-1`,
            iconVariant: GROUPS.householdMembers.cardIconVariant,
            title: GROUPS.householdMembers.actionTitle,
            statusLabel: "In Progress",
            formData: e.actions?.[0]?.formData || {}
          }
        ]
      }));
      if (this.householdId) {
        this._fetchHouseholdMembersAndAccounts();
      }
      this._refreshRequiredDocuments();
    } catch (error) {
      console.error("addclient failed", error);
      this._showToast(
        "Error",
        error?.body?.message || "Unable to add client to envelope.",
        "error"
      );
    }
  }

  // The outline row an action item was raised against. The `cases` group holds items parented to a
  // financial account and items parented to a household member, and each carries only its own
  // lookup, so the two are read through one accessor wherever the parent is what matters.
  _actionParentId(caseEntity) {
    return caseEntity?.financialAccountId || caseEntity?.memberAccountId || null;
  }

  // A member's current field values, used to seed an action item raised to change them. The member's
  // interview already holds the record's values (the household fetch reads them back for every
  // persisted member, submitted or not), so the action opens populated without waiting on a read of
  // its own. Only real record fields are carried: the composite section keys and the wrapper's DTO
  // keys are not proposable changes and must not reach the review case.
  _memberFormValues(entity) {
    const formData = entity?.actions?.[0]?.formData || {};
    return Object.keys(formData).reduce((values, field) => {
      if (isRecordFieldKey(field)) {
        values[field] = formData[field];
      }
      return values;
    }, {});
  }

  // Outline row "+": remember the target entity (and its already-added action ids, which
  // disable those rows in the dialog), resolve the action catalog for its type, and open the
  // Add action item dialog.
  handleItemAdd(event) {
    const entity = this._findEntity(event?.detail?.id);
    this._pendingAddId = entity?.id || null;
    this.pendingAddName = entity?.name || event?.detail?.name || "";
    this.pendingAddedActionIds = entity
    ? (this.model["cases"] || [])
          .filter(caseEntity => this._actionParentId(caseEntity) === entity.id)
          .map(caseEntity => caseEntity.type)
          .filter(Boolean)
    : [];
    this.pendingAddActions = resolveActionCatalog(entity);
    this.refs.addActionModal.open();
  }

  // Append the selected action types to the target entity's action list. Each becomes an
  // action card under the entity in the content area; a type already on the entity is
  // skipped. Local-only, like the rest of this version.
  // handleAddActionConfirm(event) {
  //   const selectedIds = event?.detail?.selectedIds || [];
  //   const entity = this._findEntity(this._pendingAddId);
  //   if (entity && selectedIds.length) {
  //     const cardIcon = GROUPS[entity.groupId]?.cardIconVariant || "member";
  //     const existing = new Set(entity.actions.map((action) => action.sourceId));
  //     const added = selectedIds
  //       .filter((sourceId) => !existing.has(sourceId))
  //       .map((sourceId) => {
  //         const catalogItem = this.pendingAddActions.find(
  //           (item) => item.id === sourceId
  //         );
  //         return {
  //           id: `${entity.id}-${this._seq++}`,
  //           sourceId,
  //           iconVariant: cardIcon,
  //           title: catalogItem ? catalogItem.label : sourceId,
  //           statusLabel: "In Progress"
  //         };
  //       });
  //     if (added.length) {
  //       this._updateEntity(entity.id, (target) => ({
  //         ...target,
  //         actions: [...target.actions, ...added]
  //       }));
  //       this._showToast(
  //         "Action item added",
  //         "Action item has been added to the envelope.",
  //         "success"
  //       );
  //     }
  //   }
  //   this.refs.addActionModal.close();
  // }

  async handleAddActionConfirm(event) {
    const selectedIds = event?.detail?.selectedIds || [];
    const entity = this._findEntity(this._pendingAddId);

    if (entity && selectedIds.length) {
        // The dialog already disables the types this row carries (pendingAddedActionIds), so this
        // guards only against a stale selection racing a reload.
        const existing = new Set(
            (this.model["cases"] || [])
                .filter(caseEntity => this._actionParentId(caseEntity) === this._pendingAddId)
                .map(caseEntity => caseEntity.type)
                .filter(Boolean)
        );

        const newSourceIds = selectedIds.filter(
            sourceId => !existing.has(sourceId)
        );

        let addedCount = 0;
        for (const sourceId of newSourceIds) {
            // The row names the record being serviced and the card names the work, so the serviced
            // record's own name and type go on the entity while the action's catalog label titles
            // its card. The group label follows the row the action was raised against: an account
            // action hangs off a financial account, a member action off a household member.
            const catalogItem = this.pendingAddActions.find(
                (item) => item.id === sourceId
            );
            const isMemberAction = entity.groupId === "householdMembers";
            const detail = {
                type: sourceId,
                typeLabel: isMemberAction ? "Household Members" : "Accounts",
                nickname: entity.name,
                actionLabel: catalogItem ? catalogItem.label : "",
                sourceId
            };
            if (isMemberAction) {
                detail.memberAccountId = this._pendingAddId;
                // The interview's draft is keyed by the case's Proposed_* fields, so the member's
                // own Account-keyed values are translated through the schema's source-field
                // mapping before they seed it. An unloaded schema seeds nothing — the household
                // reload the add triggers prefills the interview from the records instead.
                detail.memberValues = accountValuesToProposedDraft(
                    this._schemaForEntity({ groupId: "cases", type: sourceId }),
                    this._memberFormValues(entity)
                );
            } else {
                detail.financialAccountId = this._pendingAddId;
            }
            // Both trade-instruction actions edit an account that may already have an allocation, so
            // the interview opens seeded with it rather than on an empty grid.
            if (TRADE_CASE_REQUEST_TYPES[sourceId]) {
                detail.tradeInstructions =
                    await this._fetchCurrentTradeInstructions(this._pendingAddId);
            }
            if (await this._addEntity("cases", detail)) {
                addedCount++;
            }
        }

        if (addedCount) {
            this._showToast(
                "Action item added",
                "Action item has been added to the envelope.",
                "success"
            );
        }
    }

    this.refs.addActionModal.close();
}

  handleAddActionClose() {
    this.refs.addActionModal.close();
  }

  // Account Owner empty-state action from Review Missing Items. Both actions target the same
  // pending Account Owner slot, so remember which action item/part asked (to correlate the
  // result) before opening the matching dialog: "Create New" opens the create-member dialog on
  // the requirement's type locked and capped to the slots it has left (same as the interview's
  // subsections), "Select Existing" opens the member picker.
  handleOwnerAction(event) {
    const { action, part, actionItemKey } = event.detail || {};
    this._pendingOwnerActionItemKey = actionItemKey || null;
    this._pendingOwnerPart = part || null;
    if (action === "createNew") {
      this.refs.createMemberModal.open(
        this._pendingOwnerPart,
        this._remainingOwnerSlotsFor(
          this._pendingOwnerActionItemKey,
          this._pendingOwnerPart
        )
      );
    } else {
      this.refs.selectMemberModal.open();
    }
  }

  // A member was picked in the "Select existing member" dialog: append it to the pending
  // requirement's party list in the owning action's form data (deduped by id — same semantics as
  // the interview's Related Parties section), arm the autosave, and refresh the header count.
  handleMemberSelected(event) {
    const { id, name } = event.detail || {};
    if (!id || !this._pendingOwnerPart) {
      return;
    }
    this._updateActionRelatedParties(
      this._pendingOwnerActionItemKey,
      this._pendingOwnerPart,
      (parties) => {
        if (parties.some((party) => party.id === id)) {
          return parties;
        }
        return [...parties, { id, name }];
      }
    );
  }

  handleSelectMemberClose() {
    this.refs.selectMemberModal.close();
  }

  // Pending member(s) were created in the "Create new" dialog: append them to the pending
  // requirement's party list as new members, arm the autosave, and refresh the header count.
  // Each gets a temporary id, sequenced past the ids the action already holds; the person Account
  // behind it is created when the change persists (see _resolvePendingParties).
  handleMembersCreated(event) {
    const members = event.detail?.members || [];
    if (!members.length || !this._pendingOwnerPart) {
      return;
    }
    const found = this._findEntityByActionId(this._pendingOwnerActionItemKey);
    const held = Object.values(
      found?.action?.formData?.[RELATED_PARTIES_FIELD_KEY] || {}
    ).flat();
    const ids = pendingPartyIds(held, members.length);
    const created = members.map((member, index) => ({
      id: ids[index],
      name: member.name,
      isNew: true,
      missingLabel: member.missingLabel
    }));
    this._updateActionRelatedParties(
      this._pendingOwnerActionItemKey,
      this._pendingOwnerPart,
      (parties) => [...parties, ...created]
    );
  }

  handleCreateMemberClose() {
    this.refs.createMemberModal.close();
  }

  // An account owner card's Remove action: drop that member from its requirement's party list so
  // the Review screen falls back to the empty state, arm the autosave, and refresh the header
  // count. The card carries the part (requirement key) / item (action id) context.
  handleOwnerRemove(event) {
    const { actionItemKey, part, id } = event.detail || {};
    if (!part) {
      return;
    }
    this._updateActionRelatedParties(actionItemKey, part, (parties) =>
      parties.filter((party) => party.id !== id)
    );
  }

  // Write a related-party requirement's transformed party list into the owning action's form
  // data — the same place (and shape) the interview's Related Parties section holds it, so the
  // Review screen and the interview read one value. The action is also marked so the save cycle
  // reconciles it into records, which is what persists it (see _persistDirtyAction). Arms the
  // autosave like any field edit, which also keeps the header count fresh (see handleFormActivity).
  _updateActionRelatedParties(actionId, requirementKey, transform) {
    const found = this._findEntityByActionId(actionId);
    if (!found) {
      return;
    }
    const formData = found.action.formData || {};
    const parties = { ...(formData[RELATED_PARTIES_FIELD_KEY] || {}) };
    const next = transform(parties[requirementKey] || []);
    if (next.length) {
      parties[requirementKey] = next;
    } else {
      delete parties[requirementKey];
    }
    this._updateEntity(found.entity.id, (entity) => ({
      ...entity,
      actions: entity.actions.map((action) => {
        return action.id === found.action.id
          ? {
              ...action,
              formData: {
                ...formData,
                [RELATED_PARTIES_FIELD_KEY]: parties
              }
            }
          : action;
      })
    }));
    if (holdsRelatedPartyRecords(found.entity)) {
      this._relatedPartiesDirty[actionId] = true;
      this._reconcileRelatedPartiesNow();
    }
    this.handleFormActivity();
  }

  // How many more parties the requirement can still take, or null when it is unbounded — the same
  // per-slot cap the interview's Related Parties section applies (envelopeRelatedParties).
  _remainingOwnerSlotsFor(actionItemKey, requirementKey) {
    const found = this._findEntityByActionId(actionItemKey);
    if (!found) {
      return null;
    }
    const formData = found.action.formData || {};
    const requirement = resolveRelatedPartyRequirements(
      found.entity,
      formData,
      this._registrationAttributes
    ).find((entry) => entry.key === requirementKey);
    if (!requirement || typeof requirement.max !== "number") {
      return null;
    }
    const count = (formData[RELATED_PARTIES_FIELD_KEY]?.[requirementKey] || [])
      .length;
    return Math.max(requirement.max - count, 0);
  }

  handleOpenItem(event) {
    this._openAction(event?.detail?.id);
  }

  // Resolve the entity's Envelope_Field__mdt schema key and load the form sections (cache-first).
  // An entity type with no configured fields resolves to null → empty schema (empty state).
  _loadActionSchema(entity) {
    const key = resolveSchemaKey(entity);
    if (!key) {
      this._rawActionSchema = [];
      this.actionSectionLayout = null;
      return;
    }
    this.actionSectionLayout = this._sectionLayouts[key.type] || null;
    const cacheKey = schemaCacheKey(key);
    if (this._schemaCache[cacheKey]) {
      this._rawActionSchema = filterSectionsByAccountType(
        this._schemaCache[cacheKey],
        key.accountType
      );
      this._applySingleOptionLookups();
      return;
    }
    getFormSchema({ objectName: key.objectName, type: key.type })
      .then((sections) => {
        const resolved = sections || [];
        // Cache the unfiltered sections: one entry serves every account type sharing the
        // schema, and only what binds to the open interview is narrowed.
        this._schemaCache[cacheKey] = resolved;
        // Ignore a stale response if the user has since closed/switched the action.
        if (this.selectedAction && this.selectedAction.entityId === entity.id) {
          this._rawActionSchema = filterSectionsByAccountType(
            resolved,
            key.accountType
          );
          this._applySingleOptionLookups();
        }
      })
      .catch((error) => {
        this._rawActionSchema = [];
        this._showToast(
          "Form",
          error?.body?.message || "Could not load the form fields",
          "error"
        );
      });
  }

  // Back from the interview. When the interview was opened from Review & Submit (activeView is
  // still 'review'), return there via openReview(), which flushes the pending edit, rebuilds the
  // summary from the updated model, and restores the focused top bar. (The envelope breadcrumb
  // therefore steps back one level per click: interview → review → workspace.) Otherwise flush
  // any pending edit into the model, restore the workspace, and clear the breadcrumb crumb.
  handleActionBack() {
    if (this.activeView === "review") {
      this.openReview();
      return;
    }
    this._flushPendingSave();
    this.selectedAction = null;
    this._rawActionSchema = [];
    this._dispatchCrumb(null);
  }

  // The interview signalled a field edit: enter "save pending" and (re)arm the inactivity timer, so
  // a save fires only once the user pauses. A fresh edit supersedes a just-shown "Saved". On the
  // Review Missing Items screen the header count re-computes on every edit — the screen records the
  // change in its draft before dispatching, so the count reads the fresh value.
  handleFormActivity() {
    // Read before anything merges the draft into the model: both the proposed-case branch and the
    // save below merge, and the comparison has to be against the pre-merge model.
    const partiesChanged = this._openInterviewPartiesChanged();
    if (this._handleProposedCase()) {
      // A submitted member's field edits route to an approval case, but its related parties are
      // relationship records like any other member's. They reconcile here because the return below
      // skips the autosave cycle that would otherwise write them (_handleProposedCase has already
      // merged the draft, so the change is in the model).
      if (partiesChanged) {
        this._reconcileRelatedPartiesNow();
      }
      return;
    }
    this._clearSavedHideTimer();
    this.saveStatus = SAVE_STATUS.PENDING;
    this._resetAutoSaveTimer();
    if (this.isMissingItemsView) {
      this._refreshMissingItemsCrumb();
    }
    // A related party added or removed in the interview is a discrete action rather than typing, so
    // it reconciles now: waiting out the inactivity window risks a reload in between, which would
    // lose the relationship record. Field edits stay debounced.
    if (partiesChanged) {
      this._saveNow();
      this._reconcileRelatedPartiesNow();
    }
  }

  // Whether the open interview's draft holds a related-party change the model hasn't taken yet, for
  // an entity whose parties belong in relationship records. False on every other view and for an
  // ordinary field edit.
  _openInterviewPartiesChanged() {
    if (!this.isActionView) {
      return false;
    }
    const details = this.refs.actionDetails;
    if (!details || typeof details.getFormData !== "function") {
      return false;
    }
    const { actionId, values } = details.getFormData();
    const found = actionId ? this._findEntityByActionId(actionId) : null;
    return (
      !!found &&
      holdsRelatedPartyRecords(found.entity) &&
      this._relatedPartiesChanged(
        found.action.formData?.[RELATED_PARTIES_FIELD_KEY],
        values[RELATED_PARTIES_FIELD_KEY]
      )
    );
  }

  // Edits to a submitted (locked) member don't autosave to the person record — they route to an
  // Account Servicing approval case instead (saveProposedCase upserts the original/proposed field
  // pairs). Draft members and non-member entities return false and keep the normal autosave path.
  _handleProposedCase() {
    const details = this.refs.actionDetails;
    if (!details || typeof details.getFormData !== "function") {
      return false;
    }
    const { actionId, values } = details.getFormData();
    const found = actionId ? this._findEntityByActionId(actionId) : null;
    if (!found) {
      return false;
    }
    if (found.entity.groupId !== "householdMembers" || found.entity.isNew) {
      return false;
    }
    const formData = found.action.formData || {};
    const changedValues = Object.keys(values).reduce((obj, field) => {
      // Only real record fields can be proposed as a change; a composite section value is not one,
      // and comparing it here would report a change on every edit (objects never compare equal).
      if (!isRecordFieldKey(field)) {
        return obj;
      }
      if (!this._valuesEqual(values[field], formData[field])) {
        // A format-invalid proposed value never reaches the approval case; it stays in the draft
        // with the control's inline error until corrected.
        if (
          isFormatValid(this._fieldRuleFor(found.entity, field), values[field])
        ) {
          obj[field] = values[field];
        }
      }
      return obj;
    }, {});
    if (Object.keys(changedValues).length) {
      saveProposedCase({
        originalvalues: formData,
        proposedValue: changedValues,
        accountId: found.entity.id
      }).catch((error) =>
        console.error("[envelopeShellV2] saveProposedCase failed", error)
      );
    }
    // Merge the edit into the in-memory model so the next diff is against the latest values; the
    // early return in handleFormActivity keeps the server autosave cycle off for this entity.
    this._saveNow();
    return true;
  }

  _resetAutoSaveTimer(delayMs = AUTO_SAVE_INACTIVITY_MS) {
    this._clearAutoSaveTimer();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._autoSaveTimerId = setTimeout(() => this._performAutoSave(), delayMs);
  }

  // The inactivity window elapsed: run the save cycle — SAVING while the persistence round-trips
  // are in flight, then SAVED briefly, then back to IDLE (indicator hidden). On failure the edit
  // stays in the in-memory model, the error is surfaced as a toast, and the cycle re-arms itself
  // for a bounded number of automatic retries (status stays PENDING); once the retry budget is
  // spent, only a fresh edit re-arms it. Consecutive failures escalate via _recordSaveFailure.
  async _performAutoSave() {
    this._clearAutoSaveTimer();
    if (this.saveStatus !== SAVE_STATUS.PENDING || this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.saveStatus = SAVE_STATUS.SAVING;
    try {
      this._saveNow();
      const missingItems = this._missingItemsTotalForSave();
      await saveEnvelopeState({
        wizardEnvelopeId: this.model?.id,
        envelopeJson: JSON.stringify(
          withoutRelatedParties(withoutRecordBackedEntities(this.model || {}))
        ),
        envelopeName: this.model?.name,
        householdName: this.model?.householdName,
        // The list's Missing Items column reads these back; null leaves the stored pair untouched.
        missingItemsCount: missingItems ? missingItems.count : null,
        missingItemsHasPlus: missingItems ? missingItems.hasPlus : null
      });
      // The record-level persists below write to different records, so each runs even when an earlier
      // one failed — otherwise one bad field would keep skipping the steps after it, cycle after
      // cycle. The first error rethrows once they have all run, so the cycle's failure semantics are
      // unchanged. Sequential rather than concurrent: two steps can target the same record.
      const failures = [];
      const run = async (step) => {
        try {
          await step();
        } catch (error) {
          failures.push(error);
        }
      };
      // Write an open account/DPI interview's fields to the real Financial_Account__c record, so
      // answers land on the SObject and not only in the envelope-state blob.
      await run(() => this._persistOpenAccountFields());
      // Same for an open member interview: an unsubmitted member's answers land on the person
      // Account record. (Submitted members never reach this cycle — their edits route to a
      // proposed-change case in _handleProposedCase.)
      await run(() => this._persistOpenMemberFields());
      // Same for an open service-agreement interview: its answers land on the Service__c record.
      await run(() => this._persistOpenServiceFields());
      // And for an open Account Action Item: its answers land on the Case the action opened.
      await run(() => this._persistOpenCaseFields());
      // And write the Review Missing Items changes to their records, each entity through its
      // group's own update call (only the entities actually edited are touched), plus the
      // related-party reconcile.
      await run(() => this._queueReconcile());
      if (failures.length) {
        throw failures[0];
      }
      this.saveStatus = SAVE_STATUS.SAVED;
      this._recordSaveSuccess();
    } catch (error) {
      console.error(error);
      this._recordSaveFailure({
        title: "Save failed",
        message: error?.body?.message || "We couldn't save your latest changes."
      });
      if (this._saveRetryCount < MAX_SAVE_AUTO_RETRIES) {
        // Re-arm the cycle for an automatic retry: the edit is still in the model, so the same
        // save can be re-attempted without user input. PENDING satisfies the entry guard above.
        this._saveRetryCount += 1;
        this.saveStatus = SAVE_STATUS.PENDING;
        this._resetAutoSaveTimer(SAVE_RETRY_DELAY_MS);
      } else {
        // Retry budget spent: hide the TOC indicator rather than leaving it on "pending". The
        // edit remains in the model, so the next field change arms a fresh save cycle.
        this.saveStatus = SAVE_STATUS.IDLE;
      }
    } finally {
      this.isSaving = false;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._savedHideTimerId = setTimeout(() => {
      this._savedHideTimerId = null;
      if (this.saveStatus === SAVE_STATUS.SAVED) {
        this.saveStatus = SAVE_STATUS.IDLE;
      }
    }, SAVED_VISIBLE_MS);
  }

  // Write an open account/DPI interview's field answers to their records (update-only, keyed by real
  // field API names — the interview draft already uses them). Runs only for a persisted account/DPI
  // entity; members and services persist elsewhere. The composite draft keys (related parties, trade
  // instructions) are not record fields, so they are dropped; multi-select values are joined so they
  // put cleanly into a MULTIPICKLIST field. A no-op for any other open view, so it is safe to await
  // unconditionally in the autosave cycle.
  //
  // The interview is mixed-object, so the payload splits by the object each field's schema row names:
  // Financial_Account__c answers go to saveAccountInfo, Case answers to saveAccountCaseInfo. The
  // latter resolves the account's wizard Case, opening one for an account that predates the envelope
  // and linking it to the envelope — which is what envelopeId is for.
  async _persistOpenAccountFields() {
    if (!this.isActionView) {
      return;
    }
    const found = this._findEntityByActionId(this.selectedAction?.actionId);
    if (!found) {
      return;
    }
    const { entity, action } = found;
    const isAccount =
      entity.groupId === "accounts" || entity.groupId === "dpisSponsor";
    if (!isAccount || !isRecordId(entity.id)) {
      return;
    }
    const values = action.formData || {};
    const data = { Id: entity.id };
    const caseData = { Id: entity.id };
    // Tracked separately from the value: a cleared product is a meaningful answer (it removes the
    // row), so "answered with nothing" has to be distinguishable from "not asked".
    let productId = null;
    let hasProductAnswer = false;

    Object.keys(values).forEach((key) => {
      if (
        key === RELATED_PARTIES_FIELD_KEY ||
        key === "tradeInstructions" ||
        NON_FIELD_FORM_KEYS.has(key)
      ) {
        return;
      }
      const value = values[key];
      // Format-invalid values stay in the draft (with the inline error) and skip the record write.
      if (!isFormatValid(this._fieldRuleFor(entity, key), value)) {
        return;
      }
      const wireValue = Array.isArray(value) ? value.join(";") : value;
      // Each answer belongs to exactly one record. Routing on the schema's object is what keeps a
      // field API name that exists on more than one of them from being written to several.
      const fieldObject = this._fieldObjectFor(entity, key);
      if (fieldObject === "Case") {
        caseData[key] = wireValue;
      } else if (fieldObject === RELATED_PRODUCT_OBJECT) {
        // A record of its own rather than a field, so it is passed as a value, not a field map.
        productId = wireValue || null;
        hasProductAnswer = true;
      } else {
        data[key] = wireValue;
      }
    });
    await saveAccountInfo({ data });
    await saveAccountCaseInfo({ caseData, envelopeId: this.envelopeId });
    // Guarded, unlike the two above: the load path seeds a null product on every account, so an
    // unguarded call would look for a related-product row on every autosave of every interview.
    if (hasProductAnswer) {
      await saveRelatedProduct({ productId, financialAccountId: entity.id });
    }
  }

  // Write an open service-agreement interview's field answers to its real Service__c record via
  // saveServiceInfo (update-only, keyed by real Service__c field API names — the interview draft
  // already uses them). Runs only for a persisted service entity; members and accounts persist
  // elsewhere. Composite draft keys (related parties, trade instructions) are dropped; multi-select
  // values are joined for a MULTIPICKLIST field. A no-op for any other open view, so it is safe to
  // await unconditionally in the autosave cycle.
  async _persistOpenServiceFields() {
    if (!this.isActionView) {
      return;
    }
    const found = this._findEntityByActionId(this.selectedAction?.actionId);
    if (!found) {
      return;
    }
    const { entity, action } = found;
    if (entity.groupId !== "serviceAgreements" || !isRecordId(entity.id)) {
      return;
    }
    const values = action.formData || {};
    const data = { Id: entity.id };
    Object.keys(values).forEach((key) => {
      if (
        key === RELATED_PARTIES_FIELD_KEY ||
        key === "tradeInstructions" ||
        NON_FIELD_FORM_KEYS.has(key)
      ) {
        return;
      }
      const value = values[key];
      // Format-invalid values stay in the draft (with the inline error) and skip the record write.
      if (!isFormatValid(this._fieldRuleFor(entity, key), value)) {
        return;
      }
      data[key] = Array.isArray(value) ? value.join(";") : value;
    });
    await saveServiceInfo({ data });
  }

  // Write an open Account Action Item interview's field answers to its own Case, so they reach the
  // record as they are edited rather than sitting in the envelope-state blob. The accounts and
  // services counterpart for the cases group.
  //
  // The Case here is the interview's primary record, not a related one, so it is addressed by its own
  // id: saveAccountActionCase treats a payload carrying an Id as an update and applies the fields
  // generically, leaving its per-type create branches untouched. Composite draft keys (the DMS
  // actions' trade instructions) are dropped and multi-selects joined, as the siblings do. A no-op
  // for any other open view, so it is safe to await unconditionally in the autosave cycle.
  //
  // A member action item's answers are the review case's Proposed_* fields ('Proposed Changes'
  // metadata), so they take the proposed-values write instead; the Case is still addressed by its
  // own id, and the member rides along for the server's current-value diff and record link.
  async _persistOpenCaseFields() {
    if (!this.isActionView) {
      return;
    }
    const found = this._findEntityByActionId(this.selectedAction?.actionId);
    if (!found) {
      return;
    }
    const { entity, action } = found;
    if (entity.groupId !== "cases" || !isRecordId(entity.id)) {
      return;
    }
    const values = action.formData || {};
    const fields = this._buildFieldUpdateMap(
      values,
      Object.keys(values),
      entity
    );
    if (!Object.keys(fields).length) {
      return;
    }
    if (isMemberActionType(entity.type)) {
      await saveProposedCaseFields({
        caseId: entity.id,
        accountId: entity.memberAccountId,
        proposedValues: fields
      });
      return;
    }
    await saveAccountActionCase({
      financialAccountId: entity.financialAccountId,
      formData: { Id: entity.id, ...fields },
      envelopeId: this.envelopeId,
      sourceId: ACCOUNT_TYPE_TO_MDT[entity.type] || entity.type
    });
  }

  // Write an open member interview's answers to the person Account via the group's saveEntity
  // update call, so an unsubmitted member's details reach the record as they are edited — not
  // only the envelope-state blob. Runs only for a persisted (real-id), unsubmitted member of a
  // type saveEntity can update; the payload is the form's own field keys (Account API names from
  // the Envelope_Field__mdt schema), so wrapper metadata never leaks into the record write.
  async _persistOpenMemberFields() {
    if (!this.isActionView) {
      return;
    }
    const details = this.refs.actionDetails;
    if (!details || typeof details.getFormData !== "function") {
      return;
    }
    const { actionId, values } = details.getFormData();
    const found = actionId ? this._findEntityByActionId(actionId) : null;
    if (!found) {
      return;
    }
    const { entity } = found;
    if (
      entity.groupId !== "householdMembers" ||
      !entity.isNew ||
      !isRecordId(entity.id)
    ) {
      return;
    }
    const fields = this._buildFieldUpdateMap(
      values || {},
      Object.keys(values || {}),
      entity
    );
    if (!Object.keys(fields).length) {
      return;
    }
    await GROUPS.householdMembers.persistUpdate(
      entity,
      fields,
      this.envelopeId
    );
  }

  // Persist the currently-editing view's values (the persistence step of the autosave cycle).
  // Synchronous so it can also run on teardown/flush without losing data. The two editable views
  // share the shell's autosave machine, so route to whichever one is active.
  _saveNow() {
    if (this.isActionView) {
      this._saveActionInterview();
    } else if (this.isMissingItemsView) {
      this._saveMissingItems();
    }
  }

  // Merge the interview's current values into the model's action. Mock: the model is in-memory
  // today; the real saveEnvelopeState round-trip is a later slice.
  _saveActionInterview() {
    const details = this.refs.actionDetails;
    if (!details || typeof details.getFormData !== "function") {
      return;
    }
    const { actionId, values } = details.getFormData();
    const found = actionId ? this._findEntityByActionId(actionId) : null;
    if (!found) {
      return;
    }
    // A related-party change made in the interview reaches the model through this same merge, so
    // mark it here for the relationship reconcile the save cycle runs.
    if (
      holdsRelatedPartyRecords(found.entity) &&
      this._relatedPartiesChanged(
        found.action.formData?.[RELATED_PARTIES_FIELD_KEY],
        values[RELATED_PARTIES_FIELD_KEY]
      )
    ) {
      this._relatedPartiesDirty[actionId] = true;
    }
    // This assignment replaces the action's form data with the interview's draft, and the draft
    // cannot carry a field the interview never rendered. Re-apply them here or the first autosave
    // drops the value seeded when the action opened.
    const merged = { ...values, ...this._singleOptionValuesForOpenAction() };
    this._updateEntity(found.entity.id, (entity) => ({
      ...entity,
      actions: entity.actions.map((action) => {
        return action.id === actionId
          ? { ...action, formData: merged }
          : action;
      })
    }));
  }

  // Merge the Review Missing Items draft into the model, one action at a time. The draft comes
  // grouped by action id; only values that actually differ from the action's saved form data are
  // merged (a merge, not a replacement — the screen draft is seeded from the saved values and
  // spans only schema field paths, never composite keys like relatedParties, so the diff keeps
  // untouched seeded values out of the merge and the dirty set), and the changed field names are
  // marked dirty so _persistMissingItemEntities routes each affected entity to its group's update
  // call. Synchronous, so the exit flush can run it on teardown.
  _saveMissingItems() {
    const missing = this.refs.missingItems;
    if (!missing || typeof missing.getFormData !== "function") {
      return;
    }
    const { valuesByAction } = missing.getFormData() || {};
    Object.entries(valuesByAction || {}).forEach(([actionId, values]) => {
      const found = this._findEntityByActionId(actionId);
      if (!found) {
        return;
      }
      const formData = found.action.formData || {};
      const changed = Object.keys(values).filter(
        (name) => !this._valuesEqual(values[name], formData[name])
      );
      if (!changed.length) {
        return;
      }
      this._updateEntity(found.entity.id, (entity) => ({
        ...entity,
        actions: entity.actions.map((action) => {
          return action.id === actionId
            ? { ...action, formData: { ...action.formData, ...values } }
            : action;
        })
      }));
      const dirty = this._missingItemsDirty[actionId] || new Set();
      changed.forEach((name) => dirty.add(name));
      this._missingItemsDirty[actionId] = dirty;
    });
  }

  // Whether two draft values are the same once normalized: multi-select arrays compare by their
  // joined form (the shape they persist in), and null/undefined/'' all count as unset — while
  // false does not, so unchecking a saved checkbox still registers as a change.
  // One definition of "the same answer", shared with the interview's echo guards (see
  // envelopeFormSchema.draftValuesEqual). Kept as a thin pass-through rather than a second
  // implementation: the shell decides what to persist and the interview decides what to accept, and
  // those two must not be able to disagree about whether a value changed.
  _valuesEqual(a, b) {
    return draftValuesEqual(a, b);
  }

  // The field's configured format rule (Pattern__c / Min__c / Max__c) from the entity's prefetched
  // schema; null when the field has no schema row (composite draft keys) or no rule configured.
  _fieldRuleFor(entity, fieldName) {
    const schema = this._schemaForEntity(entity);
    for (const section of Array.isArray(schema) ? schema : []) {
      const match = (section.fields || []).find(
        (field) => field.fieldPath === fieldName
      );
      if (match) {
        return match;
      }
    }
    return null;
  }

  // The target SObject for a field, from the entity's prefetched schema — e.g. 'Case', the primary
  // record's object, or null when the field has no schema row. Used to route each answer of a mixed
  // interview type to the record its schema row names, so a related-object answer never reaches the
  // primary record and vice versa.
  _fieldObjectFor(entity, fieldName) {
    const match = this._fieldRuleFor(entity, fieldName);
    return match ? match.objectApiName || null : null;
  }

  // Whether a field belongs to a Case *related to* the entity rather than to the entity's own record.
  // True only for the account groups, whose interview is mixed-object and whose Case-targeted answers
  // go through saveAccountCaseInfo. For an Account Action Item the Case IS the primary record, so its
  // fields must take the normal path — without this scope every one of them would be filtered out of
  // the update map and the action item could never save anything.
  _isRelatedCaseField(entity, fieldName) {
    return (
      ACCOUNT_GROUP_IDS.has(entity?.groupId) &&
      this._fieldObjectFor(entity, fieldName) === "Case"
    );
  }

  // Whether a field's answer is a related product record rather than a value on the entity's own
  // record. Those go through saveRelatedProduct, so they are routed out of both the primary-record
  // and the related-Case writes.
  _isRelatedProductField(entity, fieldName) {
    return (
      ACCOUNT_GROUP_IDS.has(entity?.groupId) &&
      this._fieldObjectFor(entity, fieldName) === RELATED_PRODUCT_OBJECT
    );
  }

  // The product answer among a set of changed field names, as { productId, hasAnswer }. Kept separate
  // from the field-map builders because the answer is a record, not a field on one — a cleared value
  // deletes the row, so "answered with nothing" must stay distinct from "not among the changes".
  _relatedProductChange(formData, fieldNames, entity) {
    const name = fieldNames.find(
      (candidate) =>
        isRecordFieldKey(candidate) &&
        this._isRelatedProductField(entity, candidate)
    );
    return name
      ? { productId: formData[name] || null, hasAnswer: true }
      : { productId: null, hasAnswer: false };
  }

  // The Apex field map for a set of changed field names, read from the action's current form data
  // at drain time (so a retried persist never sends stale values). Composite draft keys (related
  // parties, trade instructions) are not record fields and are dropped; multi-select arrays join
  // to the MULTIPICKLIST wire format (same rules as _persistOpenAccountFields). Format-invalid
  // values are skipped from the record write — they stay in the draft blob with the control's
  // inline error showing, and reach the record once corrected.
  _buildFieldUpdateMap(formData, fieldNames, entity) {
    const data = {};
    fieldNames.forEach((name) => {
      if (!isRecordFieldKey(name)) {
        return;
      }
      // Answers targeting a *related* Case or a related product record go there instead, through
      // their own writes — see _buildRelatedCaseFieldUpdateMap and _relatedProductChange. Skip them
      // here so nothing is written twice. An action item's own Case fields are not related fields,
      // so they stay.
      if (
        this._isRelatedCaseField(entity, name) ||
        this._isRelatedProductField(entity, name)
      ) {
        return;
      }
      // Name is system-generated (read-only) on a person account, so it can't be written for any
      // member that persists as one — an individual or a member presented as a related-party role;
      // those forms capture FirstName/LastName. A stray Name here comes from the server-wrapper
      // formData seed and would fail the person-account DML. Business/trust keep Name (it's a real,
      // writeable field on those record types).
      if (
        name === "Name" &&
        persistedMemberTypeFor(entity?.type) === "client"
      ) {
        return;
      }
      const value = formData[name];
      if (!isFormatValid(this._fieldRuleFor(entity, name), value)) {
        return;
      }
      data[name] = Array.isArray(value) ? value.join(";") : value;
    });
    return data;
  }

  // _buildFieldUpdateMap's counterpart for the other half of a mixed account interview: the same
  // changed field names filtered down to the ones targeting the account's wizard Case, under the
  // same composite-key and format rules. The two builders partition the names between them, so every
  // valid answer reaches exactly one record. Empty for any entity whose interview is single-object.
  _buildRelatedCaseFieldUpdateMap(formData, fieldNames, entity) {
    const data = {};
    fieldNames.forEach((name) => {
      if (!isRecordFieldKey(name) || !this._isRelatedCaseField(entity, name)) {
        return;
      }
      const value = formData[name];
      if (!isFormatValid(this._fieldRuleFor(entity, name), value)) {
        return;
      }
      data[name] = Array.isArray(value) ? value.join(";") : value;
    });
    return data;
  }

  // Queue a drain behind whatever drain is already running, so two of them never write the same
  // relationship set at once. Resolves (or rejects) with this drain's own outcome; an earlier
  // failure doesn't stop the chain, since its entries stay dirty and are retried here. Every caller
  // goes through this rather than calling the drain directly.
  // `draining` is raised for as long as a drain is running. A successful related-party write re-reads the
  // household, which re-runs the Related Parties rebuild, which can itself ask for a reconcile — the flag
  // is what stops that from recursing. An entry the rebuild marks during a drain stays dirty and is
  // picked up by the next drain.
  _queueReconcile() {
    this._reconcile.queue = this._reconcile.queue
      .catch(() => {})
      .then(async () => {
        this._reconcile.draining = true;
        try {
          await this._persistMissingItemEntities();
        } finally {
          this._reconcile.draining = false;
        }
      });
    return this._reconcile.queue;
  }

  // Reconcile a related-party change now instead of waiting out the inactivity window: adding or
  // removing a party is a discrete action, and a reload before the debounced cycle fires would lose
  // the relationship record entirely. A failure is surfaced rather than only logged — the party is
  // visibly in the list, so silence reads as "saved" — and the entry stays dirty for the next retry.
  // Failures count toward the recurrent-failure escalation, but success never resets it: a drain
  // resolves trivially when nothing is dirty, which would read as a false recovery.
  _reconcileRelatedPartiesNow() {
    this._queueReconcile().catch((error) => {
      console.error("[envelopeShellV2] related-party reconcile failed", error);
      this._recordSaveFailure({
        title: "Related parties not saved",
        message:
          error?.body?.message ||
          "We couldn't save the related party. It will be retried."
      });
    });
  }

  // Drain the dirty maps: write each affected entity's changed fields to its record via the group's
  // update call — members through saveEntity, accounts/DPIs through saveAccountInfo — and reconcile
  // the related parties of every entity whose party list changed. The per-entity persists are
  // independent, so they run concurrently; if any failed, the first error rethrows after all settle,
  // keeping the autosave cycle's failure semantics (status back to pending, failed entries retried
  // next cycle).
  async _persistMissingItemEntities() {
    const actionIds = [
      ...new Set([
        ...Object.keys(this._missingItemsDirty),
        ...Object.keys(this._relatedPartiesDirty)
      ])
    ];
    if (!actionIds.length) {
      return;
    }
    const failures = await Promise.all(
      actionIds.map((actionId) => this._persistDirtyAction(actionId))
    );
    const firstError = failures.find(Boolean);
    if (firstError) {
      throw firstError;
    }
  }

  // Persist one dirty action: its changed fields to the entity's record, then its related parties to
  // relationship records. Groups without an update call (services) and entities that only exist
  // locally (temp id) keep their values in the envelope-state JSON, so their entries just clear.
  // Resolves to null when everything written succeeded, and to the first error otherwise — whichever
  // part failed stays dirty for the next cycle's retry.
  async _persistDirtyAction(actionId) {
    const found = this._findEntityByActionId(actionId);
    if (!found || !isRecordId(found.entity.id)) {
      if (!found) {
        // The action went away between the edit and this drain (its entity was removed, or the model
        // was rebuilt). Logged because the pending change is discarded here with nothing else to show.
        console.warn(
          "[envelopeShellV2] dropping pending changes for a missing action",
          actionId
        );
      }
      delete this._missingItemsDirty[actionId];
      delete this._relatedPartiesDirty[actionId];
      return null;
    }
    let firstError = null;
    const persistUpdate = GROUPS[found.entity.groupId]?.persistUpdate;
    const formData = found.action.formData || {};
    const dirtyNames = [...(this._missingItemsDirty[actionId] || [])];
    const fields = persistUpdate
      ? this._buildFieldUpdateMap(formData, dirtyNames, found.entity)
      : {};
    // The other halves of a mixed account interview, each written through its own call. Every write
    // has to land before the entry clears, or a failure in one would discard the changes the others
    // never sent — hence the single clear below rather than one per write.
    const caseFields = ACCOUNT_GROUP_IDS.has(found.entity.groupId)
      ? this._buildRelatedCaseFieldUpdateMap(formData, dirtyNames, found.entity)
      : {};
    const productChange = this._relatedProductChange(
      formData,
      dirtyNames,
      found.entity
    );
    if (Object.keys(fields).length) {
      try {
        await persistUpdate(found.entity, fields, this.envelopeId);
      } catch (error) {
        firstError = error;
      }
    }
    if (Object.keys(caseFields).length) {
      try {
        await saveAccountCaseInfo({
          caseData: { Id: found.entity.id, ...caseFields },
          envelopeId: this.envelopeId
        });
      } catch (error) {
        firstError = firstError || error;
      }
    }
    if (productChange.hasAnswer) {
      try {
        await saveRelatedProduct({
          productId: productChange.productId,
          financialAccountId: found.entity.id
        });
      } catch (error) {
        firstError = firstError || error;
      }
    }
    if (!firstError) {
      delete this._missingItemsDirty[actionId];
    }
    if (this._relatedPartiesDirty[actionId]) {
      const error = await this._persistRelatedParties(
        found.entity,
        found.action
      );
      if (error) {
        firstError = firstError || error;
      } else {
        delete this._relatedPartiesDirty[actionId];
      }
    }
    return firstError;
  }

  // Reconcile one action's related parties into records: create the Account behind any party added
  // through the "Create new" dialog, then send the whole set for the entity's roles (the Apex call
  // links what is new and drops the links the wizard no longer holds). A member's parties become
  // Account_Account_Relationship__c rows and an account's ownership slots Financial_Account_Role__c
  // rows; the two calls take the same reconcile shape, so only the role vocabulary and the party
  // field name differ. The parties are linked to the envelope server-side, so the household is
  // re-read afterwards for the outline to list them. Resolves to null on success or skip, and to the
  // error on failure, matching _persistDirtyAction.
  //
  // A record that could not be created does not block the rest: its party keeps its temporary id and
  // is left out of the write, which still links every party that does have a record. The create
  // error is returned afterwards, so the action stays dirty and the create is retried.
  //
  // A role the server rejected as unknown is reported but not returned as an error: the role table
  // here and the object's picklist have drifted apart, which no retry can fix, so keeping the action
  // dirty would only repeat the toast on every cycle.
  async _persistRelatedParties(entity, action) {
    if (!ownsRelatedPartyRecords(entity)) {
      return null;
    }
    try {
      const { parties, createError } = await this._resolvePendingParties(
        entity,
        action
      );
      const isAccount = holdsAccountRoleRecords(entity);
      const draft = action.formData || {};
      // Each side names the party field its own object uses, but the pairs are otherwise identical.
      const roleFor = (requirementKey) =>
        isAccount
          ? accountRoleForKey(
              entity,
              requirementKey,
              draft,
              this._registrationAttributes
            )
          : aarRoleForKey(entity.type, requirementKey);
      const payload = [];
      Object.keys(parties).forEach((requirementKey) => {
        const role = roleFor(requirementKey);
        if (!role) {
          return;
        }
        (parties[requirementKey] || []).forEach((party) => {
          if (isRecordId(party.id)) {
            payload.push(
              isAccount
                ? { accountId: party.id, role }
                : { relatedAccountId: party.id, role }
            );
          }
        });
      });
      // Serialized rather than sent as an array of objects: an Apex class used as a method parameter
      // arrives from an LWC call with its properties unset, so the server deserializes the JSON itself.
      const partiesJson = JSON.stringify(payload);
      const rejectedRoles = isAccount
        ? await saveAccountRoles({
            financialAccountId: entity.id,
            managedRoles: managedAccountRolesFor(
              entity,
              draft,
              this._registrationAttributes
            ),
            rolesJson: partiesJson,
            // The registration's own ceilings, sent as the server-side backstop for a client path
            // that applies none of its own (Review Missing Items).
            roleLimitsJson: JSON.stringify(
              accountRoleLimits(entity, draft, this._registrationAttributes)
            ),
            envelopeId: this.envelopeId
          })
        : await saveRelatedParties({
            entityAccountId: entity.id,
            managedRoles: managedAarRolesFor(entity.type),
            partiesJson,
            envelopeId: this.envelopeId
          });
      this._reportRejectedRoles(rejectedRoles);
      if (this.householdId && this.envelopeId) {
        await this._fetchHouseholdMembersAndAccounts();
      }
      return createError;
    } catch (error) {
      return error;
    }
  }

  // Give every related party added through the "Create new" dialog a real person Account: saveEntity
  // creates the person, links it to the household and the envelope, and makes it a signee on the
  // entity's required documents. Returns { parties, createError }: the party value with the temporary
  // ids replaced by record ids (written back so the resolve happens once), plus the first create
  // failure. Each create is independent — one that fails leaves its party on its temporary id, out of
  // the relationship write, rather than taking the whole set down with it. A member type saveEntity
  // can't create keeps its temporary id too.
  async _resolvePendingParties(entity, action) {
    const parties = action.formData?.[RELATED_PARTIES_FIELD_KEY] || {};
    // Flatten to the parties that have no person record yet, so their creates round-trip together
    // rather than one after another.
    const pending = Object.keys(parties).flatMap((requirementKey) =>
      (parties[requirementKey] || [])
        .filter((party) => !isRecordId(party.id))
        .map((party) => ({ requirementKey, party }))
    );
    if (!pending.length) {
      return { parties, createError: null };
    }
    let createError = null;
    const created = await Promise.all(
      pending.map((entry) =>
        this._createPartyAccount(
          entity,
          action,
          entry.requirementKey,
          entry.party
        ).catch((error) => {
          createError = createError || error;
          return null;
        })
      )
    );
    const recordIdByParty = new Map();
    pending.forEach((entry, index) => {
      if (created[index]) {
        recordIdByParty.set(
          `${entry.requirementKey}|${entry.party.id}`,
          created[index]
        );
      }
    });
    if (!recordIdByParty.size) {
      return { parties, createError };
    }
    // saveEntity can create required documents for the new people.
    this._refreshRequiredDocuments();
    const resolved = {};
    Object.keys(parties).forEach((requirementKey) => {
      resolved[requirementKey] = (parties[requirementKey] || []).map(
        (party) => {
          const recordId = recordIdByParty.get(`${requirementKey}|${party.id}`);
          return recordId ? { ...party, id: recordId } : party;
        }
      );
    });
    this._writeRelatedParties(entity.id, action.id, resolved);
    return { parties: resolved, createError };
  }

  // Create — once — the Account for a party that has no record yet, returning its id. The temporary
  // id can survive the create in an open interview's own draft, so the created id is memoized per
  // action + requirement + temporary id and reused instead of creating a second record.
  //
  // The record type comes from the slot rather than being assumed: every member-held role is held by
  // a person, but an account's owner mirrors its registration, so a business account's owner is
  // created as a Business and a trust account's as a Trust.
  async _createPartyAccount(entity, action, requirementKey, party) {
    const memoKey = `${action.id}|${requirementKey}|${party.id}`;
    if (this._createdPartyIds[memoKey]) {
      return this._createdPartyIds[memoKey];
    }
    const requirement = resolveRelatedPartyRequirements(
      entity,
      action.formData || {},
      this._registrationAttributes
    ).find((entry) => entry.key === requirementKey);
    const acc = buildMemberAccountPayload({
      type: memberTypeForPartyTypes(requirement?.types),
      nickname: party.name
    });
    if (!acc) {
      return null;
    }
    const recordId = await saveEntity({
      acc,
      envelopeId: this.envelopeId,
      // The entity the new person is a party of, which saveEntity reads as an Account to find the
      // documents it must sign. Only a member entity is one: a Financial Account's id would not
      // resolve, and its owners are made signees by saveAccountRoles instead.
      relatedAccountId: holdsAccountRoleRecords(entity) ? null : entity.id
    });
    if (recordId) {
      this._createdPartyIds[memoKey] = recordId;
    }
    return recordId;
  }

  // Write a resolved related-party value into the model and, when that action's interview is open,
  // into its draft too — the draft still holds the pre-resolve temporary ids and would otherwise
  // write them back over the record ids on the next save.
  _writeRelatedParties(entityId, actionId, value) {
    this._updateEntity(entityId, (entity) => ({
      ...entity,
      actions: (entity.actions || []).map((action) => {
        if (action.id !== actionId) {
          return action;
        }
        return {
          ...action,
          formData: {
            ...(action.formData || {}),
            [RELATED_PARTIES_FIELD_KEY]: value
          }
        };
      })
    }));
    const details = this.refs.actionDetails;
    if (details && typeof details.applyResolvedValue === "function") {
      details.applyResolvedValue(actionId, RELATED_PARTIES_FIELD_KEY, value);
    }
  }

  // Whether an action's related-party value changed, so its relationship records need reconciling.
  // Compared as serialized JSON: the value is a plain nested object of ids and names, and a false
  // positive only costs one reconcile that writes nothing.
  _relatedPartiesChanged(before, after) {
    return !draftValuesEqual(before || {}, after || {});
  }

  // Flush a pending/in-flight edit immediately (e.g. before leaving the interview) so nothing is
  // lost, then stop all timers and reset the indicator. Leaving the Review Missing Items screen
  // also runs the Apex persists right away — its debounced cycle may never fire again once the
  // view unmounts, unlike the interview, whose account fields persist on the next cycle.
  _flushPendingSave() {
    // Commit the open screen's buffered keystrokes before deciding whether anything is pending. The
    // Trade Instructions section and text-family Key Point fields hold a typed value until blur or a
    // short idle window, and an edit that has not committed yet has not armed the save cycle either —
    // so reading saveStatus first would conclude there was nothing to flush and lose the last thing
    // the user typed.
    this.refs.actionDetails?.flushPendingEdits?.();
    this.refs.missingItems?.flushPendingEdits?.();
    const hadPending =
      this.saveStatus === SAVE_STATUS.PENDING ||
      this.saveStatus === SAVE_STATUS.SAVING;
    // Captured before the reset below: when a save cycle is in flight, its own persists still
    // drain the dirty map after this flush's merge, so no extra round-trip is started.
    const wasSaving = this.isSaving;
    // The open interview's action id, captured before _saveNow merges its values and the view is
    // torn down, so the deferred persist can write the record from the model even after the
    // interview DOM is gone. Null when leaving a non-interview sub-view (e.g. Review Missing Items).
    const openActionId = this.isActionView
      ? this.selectedAction?.actionId
      : null;
    if (hadPending) {
      this._saveNow();
    }
    this._clearAllSaveTimers();
    this.isSaving = false;
    this.saveStatus = SAVE_STATUS.IDLE;
    if (hadPending && !wasSaving) {
      this._persistFlushedState(openActionId);
    }
  }

  // Persist the just-flushed model in the background while the view is torn down: the same
  // envelope-state write the autosave cycle runs, plus the selective entity update for whatever was
  // being edited — the open interview's record when leaving an interview, else the Review Missing
  // Items entities. Runs without the status indicator (there is no screen left to show it), and
  // reads from the model rather than the (now unmounting) interview DOM. Failures log without a
  // toast, but still count toward the recurrent-failure escalation.
  async _persistFlushedState(openActionId) {
    try {
      const missingItems = this._missingItemsTotalForSave();
      await saveEnvelopeState({
        wizardEnvelopeId: this.model?.id,
        envelopeJson: JSON.stringify(
          withoutRelatedParties(withoutRecordBackedEntities(this.model || {}))
        ),
        envelopeName: this.model?.name,
        householdName: this.model?.householdName,
        // The list's Missing Items column reads these back; null leaves the stored pair untouched.
        missingItemsCount: missingItems ? missingItems.count : null,
        missingItemsHasPlus: missingItems ? missingItems.hasPlus : null
      });
      if (openActionId) {
        // Leaving an open interview: write its just-flushed field values to the backing record, so
        // edits made inside the last inactivity window aren't lost — there is no next autosave cycle
        // once the interview is closed.
        const found = this._findEntityByActionId(openActionId);
        if (found) {
          await this._persistEntityFields(found.entity, found.action);
        }
      }
      // Drain the selective save cycle either way: it carries the Review Missing Items edits and the
      // related-party reconcile, which an interview can arm too.
      await this._queueReconcile();
      this._recordSaveSuccess();
    } catch (error) {
      console.error(error);
      this._recordSaveFailure();
    }
  }

  // Persist an entity's current in-model form data to its backing record(s), routed by group: an
  // account/DPI writes to Financial_Account__c (saveAccountInfo) plus its wizard Case for the
  // Case-targeted half of the interview (saveAccountCaseInfo), an Account Action Item to its own
  // Case, an unsubmitted member to the person Account (both via the group's persistUpdate). Reads
  // from the model — not the interview DOM — so it is safe to call after the interview has been torn
  // down (see _persistFlushedState). Uses the same field filters as the autosave cycle, so
  // composite/format-invalid keys are dropped identically. A no-op for a record without a real id or
  // a group with no update path.
  async _persistEntityFields(entity, action) {
    if (!entity || !action || !isRecordId(entity.id)) {
      return;
    }
    const formData = action.formData || {};
    const fieldNames = Object.keys(formData);
    const fields = this._buildFieldUpdateMap(formData, fieldNames, entity);
    if (entity.groupId === "accounts" || entity.groupId === "dpisSponsor") {
      const caseFields = this._buildRelatedCaseFieldUpdateMap(
        formData,
        fieldNames,
        entity
      );
      const productChange = this._relatedProductChange(
        formData,
        fieldNames,
        entity
      );
      await saveAccountInfo({ data: { Id: entity.id, ...fields } });
      await saveAccountCaseInfo({
        caseData: { Id: entity.id, ...caseFields },
        envelopeId: this.envelopeId
      });
      // Guarded like the autosave path: the load path seeds a null product on every account, so an
      // unguarded call would look for a related-product row on every account flush.
      if (productChange.hasAnswer) {
        await saveRelatedProduct({
          productId: productChange.productId,
          financialAccountId: entity.id
        });
      }
      return;
    }
    // An Account Action Item's answers live only on its own Case — the cases group is stripped from
    // envelope state — so skipping it here would drop whatever was typed inside the autosave idle
    // window. The timed counterpart is _persistOpenCaseFields; both share the group's update call.
    if (entity.groupId === "cases" && Object.keys(fields).length) {
      await GROUPS.cases.persistUpdate(entity, fields, this.envelopeId);
      return;
    }
    // Submitted members route edits to a proposed-change case (handled in _handleProposedCase),
    // never a direct write, so only unsubmitted members persist here.
    if (
      entity.groupId === "householdMembers" &&
      entity.isNew &&
      Object.keys(fields).length
    ) {
      await GROUPS.householdMembers.persistUpdate(
        entity,
        fields,
        this.envelopeId
      );
    }
  }

  // Reset the status to idle when an action opens.
  _resetSaveStatus() {
    this._clearAllSaveTimers();
    this.isSaving = false;
    this.saveStatus = SAVE_STATUS.IDLE;
  }

  _clearAutoSaveTimer() {
    if (this._autoSaveTimerId) {
      clearTimeout(this._autoSaveTimerId);
      this._autoSaveTimerId = null;
    }
  }

  _clearSavedHideTimer() {
    if (this._savedHideTimerId) {
      clearTimeout(this._savedHideTimerId);
      this._savedHideTimerId = null;
    }
  }

  _clearAllSaveTimers() {
    this._clearAutoSaveTimer();
    this._clearSavedHideTimer();
    if (this._saveTimerId) {
      clearTimeout(this._saveTimerId);
      this._saveTimerId = null;
    }
  }

  // Close the active sub-view from outside (the app calls this when the envelope breadcrumb
  // crumb is clicked while a sub-view is open). Routes to whichever sub-view is showing.
  @api
  closeSubView() {
    if (this.selectedAction) {
      this.handleActionBack();
    } else if (
      this.activeView === "documents" ||
      this.activeView === "missingItems" ||
      this.activeView === "review"
    ) {
      this.handleSubViewBack();
    }
  }

  // Open the full-screen Review & Submit view (the top bar's "Review and Submit" action).
  // Callable from any workspace state: an open interview's pending edit is flushed first so
  // nothing is lost, and the summary is rebuilt after the flush so it reflects the latest
  // saved form data. showReview is off in the focused header — the bar must not offer
  // Review on the Review screen itself.
  @api
  openReview() {
    this._flushPendingSave();
    this.selectedAction = null;
    this._rawActionSchema = [];
    Promise.resolve().then(() => {
      this.activeView = "review";
    });
    this._dispatchCrumb("Review and Submit", {
      mode: "focused",
      showReview: false,
      statusText: ""
    });
    this._refreshReviewItems();
  }

  handleRemoveClose() {
    this.refs.removeModal.close();
  }

  // Confirm the pending removal. An action card removes just that action from its owning
  // entity (an entity can hold several); an outline row removes the whole entity — deleting
  // the persisted record first, so the model only drops rows the server actually removed.
  async handleRemoveConfirm() {
    const id = this._pendingRemoveId;
    // Whether the pending removal is the action/entity currently open in the interview — if so
    // we return to the workspace once it's gone, since its details page would render stale.
    // (_openRemove already re-points a cascading action removal to its entity, so the entity
    // branch covers that case.)
    const viewingRemoved =
      this.selectedAction &&
      ((this._removeTarget === "entity" &&
        this.selectedAction.entityId === id) ||
        (this._removeTarget === "action" &&
          this.selectedAction.actionId === id));
    let removed = false;
    // Whether the server may have taken related parties out with the entity (see below).
    let mayHaveStrandedParties = false;
    if (this._removeTarget === "entity") {
      const alsoRemoved = await this._deletePersistedEntity(id);
      if (alsoRemoved) {
        const groupId = this._findEntity(id)?.groupId;
        // The row itself plus every related party the server reported taking with it. Those parties
        // are entities in their own right, so nothing else in this pass would reach them, and a row
        // left behind for a deleted record can be clicked again — which is what made a second removal
        // fail on a record that was already gone.
        this._removeEntity(
          (entity) => entity.id === id || alsoRemoved.includes(entity.id)
        );
        const toast =
          ENTITY_REMOVED_TOASTS[groupId] || ENTITY_REMOVED_TOASTS.default;
        this._showToast(toast.label, toast.message, "success");
        removed = true;
        // Only a member can hold related parties: an account or service id matches neither side of
        // Account_Account_Relationship__c, so the server takes nothing else out with those.
        mayHaveStrandedParties = groupId === "householdMembers";
        // The removal may have deleted the entity's required documents.
        this._refreshRequiredDocuments();
      }
    } else {
      this._removeAction(id);
      this._showToast(
        "Action removed",
        "Action has been removed successfully.",
        "success"
      );
      removed = true;
    }
    this.refs.removeModal.close();
    if (removed) {
      // A removal changes the model like any field edit, so it arms the same save cycle. The
      // record-backed groups are no longer carried in the envelope state and need no write, but
      // Account Action Items are, and so is an action removed from an entity.
      this.handleFormActivity();
    }
    if (removed && viewingRemoved) {
      this.handleActionBack();
    }
    // Rows the removal changed without taking away: a party that held two roles keeps its place but
    // is now labelled by the one that survived, and that label comes from the relationship records.
    // The rows that went are already gone (see the removal above) — this only refreshes what stayed.
    // Left until after the dialog closes so the round-trip does not hold it open.
    if (mayHaveStrandedParties && this.householdId && this.envelopeId) {
      await this._fetchHouseholdMembersAndAccounts();
    }
  }

  // Take an outline entity out of this envelope via its group's remove call, which unlinks it here
  // and deletes the record only when nothing else still uses it. The envelope is passed so the
  // removal stays scoped to it — the same record can belong to other envelopes.
  //
  // Resolves to the ids of the *other* entities the server took out with it — the related parties
  // left without the role that put them in this envelope — so the caller can drop those rows too.
  // Entities that only exist locally (temp id, or no remove call wired) resolve to an empty list so
  // the in-memory removal proceeds. A server failure resolves to null, which surfaces a toast and
  // keeps the row.
  async _deletePersistedEntity(id) {
    const entity = this._findEntityById(id);
    const removeCall = GROUPS[entity?.groupId]?.remove;
    if (!removeCall || !isRecordId(id)) {
      return [];
    }
    try {
      // A group whose remove call reports nothing (an Account Action Item) resolves undefined.
      const alsoRemoved = (await removeCall(id, this.envelopeId)) || [];
      console.log(`remove ${entity.groupId} →`, id, alsoRemoved);
      return alsoRemoved;
    } catch (error) {
      console.error(`remove ${entity.groupId} failed`, error);
      this._showToast(
        "Error",
        error?.body?.message || "Unable to remove the item.",
        "error"
      );
      return null;
    }
  }

  // Find an entity by id across all four group lists.
  _findEntityById(id) {
    for (const groupId of GROUP_IDS) {
      const entity = this.model[groupId].find((item) => item.id === id);
      if (entity) {
        return entity;
      }
    }
    return null;
  }

  handleRenameClose() {
    this.refs.renameModal.close();
  }

  handleDeleteClose() {
    this.refs.deleteModal.close();
  }

  // On rename, close the dialog and bubble the new name up so the app stays the
  // single source of truth for the title (it re-flows into the header + breadcrumb).
  handleRenamed(event) {
    this.refs.renameModal.close();
    this.dispatchEvent(
      new CustomEvent("enveloperenamed", {
        detail: { name: event.detail.name }
      })
    );
  }

  // On delete, the envelope no longer exists — let the app navigate back to the list.
  handleDeleted() {
    this.dispatchEvent(new CustomEvent("envelopedeleted"));
  }

  // Set the pending removal and open the shared confirm dialog. target: 'action' | 'entity'.
  // label is the entity-type remove text for an outline row; omitted for an action card.
  //
  // A new member/ISA record can't exist without an action: removing its last action from a
  // content card cascades to the whole record. We detect that here and re-point the removal at
  // the owning entity, so the existing entity-removal path and dialog copy apply, plus a note
  // explaining the cascade.
  _openRemove(target, id, name, label) {
    this._removeCascades = false;
    if (target === "action") {
      const found = this._findEntityByActionId(id);
      if (
        found &&
        found.entity.isNew &&
        (found.entity.actions?.length || 0) <= 1
      ) {
        target = "entity";
        id = found.entity.id;
        name = found.entity.name;
        label = GROUPS[found.entity.groupId]?.removeLabel || "";
        this._removeCascades = true;
      }
    }
    this._removeTarget = target;
    this._pendingRemoveId = id;
    this.pendingRemoveName = name;
    this._removeLabel = label || "";
    this.refs.removeModal.open();
  }

  // Drop every entity matching `predicate` from all four lists, reassigning the model so the
  // projections recompute. A removed entity is also dropped from the related-party value of every
  // entity that held it as a party: its relationship records are already gone (see
  // deleteRelatedPartyLinks), and a reference left behind here would keep rendering a party that no
  // longer exists and, on the next save, write its relationship back. No reconcile is armed for the
  // entities that change — the server already holds the state this is catching up to.
  _removeEntity(predicate) {
    const removedIds = new Set();
    const next = { ...this.model };
    GROUP_IDS.forEach((groupId) => {
      next[groupId] = (this.model[groupId] || []).filter((entity) => {
        if (!predicate(entity)) {
          return true;
        }
        removedIds.add(entity.id);
        return false;
      });
    });
    if (removedIds.size) {
      GROUP_IDS.forEach((groupId) => {
        next[groupId] = next[groupId].map((entity) =>
          withoutParties(entity, removedIds)
        );
      });
    }
    this.model = next;
  }

  // Remove a single action card (by action id) from whichever entity owns it. The entity
  // stays; it just drops out of the content area if that was its last action.
  _removeAction(actionId) {
    const next = { ...this.model };
    GROUP_IDS.forEach((groupId) => {
      next[groupId] = this.model[groupId].map((entity) => {
        return entity.actions?.some((action) => action.id === actionId)
          ? {
              ...entity,
              actions: entity.actions.filter((action) => action.id !== actionId)
            }
          : entity;
      });
    });
    this.model = next;
  }

  // Find the entity owning the action with the given id, returning { entity, action }.
  _findEntityByActionId(actionId) {
    for (const groupId of GROUP_IDS) {
      for (const entity of this.model[groupId]) {
        const action = entity.actions?.find((item) => item.id === actionId);
        if (action) {
          return { entity, action };
        }
      }
    }
    return null;
  }

  // Notify the app of the active sub-view's breadcrumb crumb (a label while open, null on back).
  // `header` optionally describes a focused top-bar variant (e.g. Review Missing Items); when
  // omitted, the sub-view keeps the default logo + breadcrumb bar (action interview, documents).
  _dispatchCrumb(crumb, header = null) {
    this.dispatchEvent(
      new CustomEvent("subviewchange", { detail: { crumb, header } })
    );
  }

  // Find an entity by id across the four lists.
  _findEntity(id) {
    for (const groupId of GROUP_IDS) {
      const match = this.model[groupId].find((entity) => entity.id === id);
      if (match) {
        return match;
      }
    }
    return null;
  }

  // Replace the entity with the given id via `transform(entity)`, reassigning the model and
  // its group list so the projections recompute.
  _updateEntity(id, transform) {
    const next = { ...this.model };
    GROUP_IDS.forEach((groupId) => {
      next[groupId] = this.model[groupId].map((entity) => {
        return entity.id === id ? transform(entity) : entity;
      });
    });
    this.model = next;
  }

  // Open the Review Missing Items screen. Preparing it means resolving a form schema for every
  // in-progress action — some of which may still need fetching — and projecting each action's
  // outstanding inputs, which on a large envelope takes long enough to need a loading state. The
  // view (and its focused top bar) swaps in immediately over a spinner, and the screen renders
  // once its snapshot is complete, so the user never sees a partially-populated list.
  async _openMissingItemsView() {
    const run = ++this._missingItemsRun;
    this._resetSaveStatus();
    this._missingItemsSnapshot = [];
    this.isMissingItemsLoading = true;
    // Defer the view swap off the content header's click handler, which is mid-dispatch.
    await Promise.resolve();
    this.activeView = "missingItems";
    // The count isn't known yet, so the focused bar opens without its status text; the crumb is
    // re-dispatched with the real count once the snapshot lands.
    this._dispatchCrumb("Review Missing Items", {
      mode: "focused",
      showReview: true
    });
    // Get the spinner on screen before the synchronous projection below blocks the frame.
    await this._nextPaint();

    const failed = await this._loadMissingItemsSchemas();
    // A newer open superseded this one, or the user left the screen while it was loading.
    if (run !== this._missingItemsRun || this.activeView !== "missingItems") {
      return;
    }
    // Snapshot every in-progress action (sortedItems already filters to unsubmitted entities)
    // that still owes required fields, unfilled Key Points, or related parties. Held for the
    // whole visit, so completing an item updates its status but never drops it from the list.
    this._missingItemsSnapshot = this._buildMissingItems();
    this.isMissingItemsLoading = false;
    this._refreshMissingItemsCrumb();
    if (failed) {
      this._showToast(
        "Missing Items",
        "Some details could not be loaded",
        "error"
      );
    }
  }

  // Fetch a form schema for every in-progress action whose type isn't cached yet, so the missing
  // items can be projected in one pass. Resolves to true when any fetch failed; failures are not
  // cached, so the next open retries them.
  async _loadMissingItemsSchemas() {
    const missing = new Map();
    this.sortedItems.forEach((entity) => {
      const key = resolveSchemaKey(entity);
      if (!key) {
        return;
      }
      const cacheKey = schemaCacheKey(key);
      if (!this._schemaCache[cacheKey]) {
        missing.set(cacheKey, key);
      }
    });
    if (missing.size === 0) {
      return false;
    }
    let failed = false;
    await Promise.all(
      [...missing.entries()].map(([cacheKey, key]) =>
        getFormSchema({ objectName: key.objectName, type: key.type })
          .then((sections) => {
            this._schemaCache[cacheKey] = sections || [];
          })
          .catch(() => {
            failed = true;
          })
      )
    );
    return failed;
  }

  // Project the model into missing action items, one per action still owing inputs, from the
  // schemas currently cached. An entity whose schema is still loading is skipped — the snapshot
  // is rebuilt once the fetch lands.
  _buildMissingItems() {
    const items = [];
    this.sortedItems.forEach((entity) => {
      const key = resolveSchemaKey(entity);
      const schema = key ? this._schemaForEntity(entity) : [];
      if (key && !schema) {
        return;
      }
      const layout = key ? this._sectionLayouts[key.type] || null : null;
      entity.actions.forEach((action) => {
        const item = this._buildMissingActionItem(
          entity,
          action,
          schema,
          layout
        );
        if (item) {
          items.push(item);
        }
      });
    });
    return items;
  }

  // Shape one action into the Review Missing Items contract, or null when it owes nothing. The
  // schema is reduced to the fields still missing (see selectMissingSections), each carrying the
  // action's saved value so an already-answered gated field re-appears prefilled. The item also
  // carries the full schema fields (allFields — the screen's hidden-answer-clearing scope) and
  // the saved values filtered to schema field paths (values — the screen's draft seed, so Shown
  // WHERE conditions evaluate against the interview's answers). Sections group
  // under the type's Section__mdt layout parents exactly like the interview (unclaimed sections
  // fall into a trailing "Other" group); each schema section renders as one card part. Related-
  // party requirements the action has not met yet form a standalone "Related Parties" group ahead
  // of "Other" (mirroring the interview), holding one part whose requirement blocks are keyed by
  // the requirement key — the correlation the owner dialogs use to write the pick back into formData.
  _buildMissingActionItem(entity, action, schema, layout) {
    const formData = action.formData || {};
    const schemaSections = applyLookupOptions(schema || [], this._lookupOptions);
    const missingSections = selectMissingSections(
      schemaSections,
      formData,
      this.userContext
    );
    const partByName = new Map();
    const partsInOrder = missingSections.map((section, index) => {
      const part = {
        key: `sec-${index}`,
        title: section.name,
        statusLabel: "Inputs missing",
        fields: section.fields.map((field) => ({
          ...field,
          value: formData[field.fieldPath] ?? field.value
        }))
      };
      partByName.set(section.name, part);
      return part;
    });
    // Related Parties is its own group ahead of "Other"; the group title names it, so the part drops
    // its own title/status to avoid a duplicate heading (the per-role requirement blocks keep theirs).
    const relatedPartiesPart = this._buildRelatedPartiesPart(entity, formData);
    const relatedPartiesGroup = relatedPartiesPart
      ? {
          key: "grp-related-parties",
          title: "Related Parties",
          parts: [{ ...relatedPartiesPart, title: null, statusLabel: null }]
        }
      : null;
    // Group keys are namespaced by producer, never by running position — the same rule as
    // envelopeActionDetails._buildGroups, and for the same reason. Keying the trailing group off
    // `sections.length` collided with a layout parent's index key whenever an earlier parent
    // contributed no visible parts, which is routine here: this screen only builds parts for the
    // sections that still owe input.
    const sections = [];
    if (layout && layout.length) {
      const used = new Set();
      layout.forEach((parent, index) => {
        const children = (parent.childSections || [])
          .map((name) => partByName.get(name))
          .filter(Boolean);
        children.forEach((part) => used.add(part.title));
        if (children.length) {
          sections.push({
            key: `grp-p${index}`,
            title: parent.parentName,
            parts: children
          });
        }
      });
      if (relatedPartiesGroup) {
        sections.push(relatedPartiesGroup);
      }
      const leftover = partsInOrder.filter((part) => !used.has(part.title));
      if (leftover.length) {
        sections.push({
          key: "grp-other",
          title: "Other",
          parts: leftover
        });
      }
    } else {
      if (relatedPartiesGroup) {
        sections.push(relatedPartiesGroup);
      }
      if (partsInOrder.length) {
        sections.push({
          key: "grp-other",
          title: "Other",
          parts: partsInOrder
        });
      }
    }
    if (!sections.length) {
      return null;
    }
    // Full-schema scope for the screen's hidden-answer clearing (mirrors the interview's
    // _allFields), and the saved values the screen seeds its draft from — restricted to schema
    // field paths so composite keys (e.g. relatedParties), which the shell keeps writing into
    // formData while the screen is open, never enter the draft and can't be merged back stale
    // by _saveMissingItems.
    const allFields = schemaSections.flatMap((section) => section.fields || []);
    const values = {};
    allFields.forEach((field) => {
      const value = formData[field.fieldPath];
      if (value !== undefined) {
        values[field.fieldPath] = value;
      }
    });
    return {
      key: action.id,
      title: [entity.name, action.title].filter(Boolean).join(" - "),
      allFields,
      values,
      sections
    };
  }

  // The "Related Parties" card part for a missing action item, or null when every requirement is
  // already met: one requirement block per party type still owed, each carrying the empty-state
  // prompt the Review screen renders until an owner is picked. Roles sharing a minimum are owed
  // together, so they appear and clear as a set and say so in their prompt.
  _buildRelatedPartiesPart(entity, formData) {
    const requirements = resolveRelatedPartyRequirements(
      entity,
      formData,
      this._registrationAttributes
    );
    const unmet = unmetRelatedPartyRequirements(
      requirements,
      formData[RELATED_PARTIES_FIELD_KEY] || {},
      waivedRelatedPartyKeys(requirements, formData)
    );
    if (!unmet.length) {
      return null;
    }
    return {
      key: "relatedParties",
      title: "Related Parties",
      statusLabel: "Inputs missing",
      requirements: unmet.map((requirement) => ({
        key: requirement.key,
        title: requirement.title,
        max: requirement.max,
        group: requirement.group,
        statusLabel: "Inputs missing",
        emptyState: {
          title: `No ${(requirement.title || "related party").toLowerCase()} yet`,
          message: `Adding ${partyAlternativesLabel(
            requirements,
            requirement.key
          )} is required.`,
          actions: [
            { key: "selectExisting", label: "Select Existing" },
            { key: "createNew", label: "Create New" }
          ]
        }
      }))
    };
  }

  // Missing-inputs total across the snapshot's actions for the focused top bar's status text —
  // the same computation as the workspace action cards (see sortedItems): outstanding inputs
  // plus unmet related-party requirements, evaluated against each action's saved form data
  // overlaid with the screen's unsaved draft so the count tracks typing live. `hasPlus` marks the
  // count as a lower bound: an unfilled Key Point gates further fields, shown as a trailing '+'.
  _missingItemsCountState() {
    const draftByAction =
      this.refs.missingItems?.getFormData?.()?.valuesByAction || {};
    // Each snapshot action counts against its saved form data overlaid with the screen's live
    // unsaved draft, so the header tracks typing. The per-action math (schema resolution,
    // outstanding fields, unmet related parties, and the Key-Point '+') is shared with the landing
    // list's Missing Items column via sumMissingInputs.
    const items = (this._missingItemsSnapshot || [])
      .map((item) => {
        const found = this._findEntityByActionId(item.key);
        if (!found) {
          return null;
        }
        return {
          entity: found.entity,
          formData: {
            ...(found.action.formData || {}),
            ...(draftByAction[item.key] || {})
          }
        };
      })
      .filter(Boolean);
    return sumMissingInputs(items, {
      schemaCache: this._schemaCache,
      registrationAttributes: this._registrationAttributes,
      userContext: this.userContext
    });
  }

  // The envelope's whole outstanding-input total, persisted with the envelope state so the landing
  // list's Missing Items column can render a real number.
  //
  // The list cannot compute this itself any more. Its answers live on the records now — the
  // Accounts, Financial Accounts, Services and action-item Cases — and withoutRecordBackedEntities
  // strips every record-backed entity out of the saved blob, so a reader of the blob sees almost
  // nothing and counts zero. Here the whole model is in hand, already overlaid with the record
  // values, so the number is the same one the workspace cards and the Review Missing Items header
  // show (see sortedItems and _missingItemsCountState): outstanding fields plus unmet related-party
  // requirements, over every action of every unsubmitted entity.
  //
  // Returns null when any counted entity's schema has not loaded — sumMissingInputs skips such an
  // item, and a total silently short by one entity's worth is worse than the last stored one, which
  // saveEnvelopeState keeps when the count arrives null.
  _missingItemsTotalForSave() {
    const items = [];
    let unresolved = false;
    GROUP_IDS.forEach((groupId) => {
      // The same set the workspace treats as outstanding: unsubmitted entities carrying actions.
      // A submitted record is locked and owes nothing.
      (this.model?.[groupId] || [])
        .filter((entity) => entity.actions?.length && entity.isNew)
        .forEach((entity) => {
          const key = resolveSchemaKey(entity);
          if (key && !this._schemaCache[schemaCacheKey(key)]) {
            unresolved = true;
            return;
          }
          entity.actions.forEach((action) => {
            items.push({ entity, formData: action.formData || {} });
          });
        });
    });
    if (unresolved) {
      return null;
    }
    return sumMissingInputs(items, {
      schemaCache: this._schemaCache,
      registrationAttributes: this._registrationAttributes,
      userContext: this.userContext
    });
  }

  // Re-dispatch the Review Missing Items focused top-bar crumb with the current missing-inputs
  // count, so field edits and owner changes keep the header count in sync.
  _refreshMissingItemsCrumb() {
    const { count, hasPlus } = this._missingItemsCountState();
    this._dispatchCrumb("Review Missing Items", {
      mode: "focused",
      showReview: true,
      statusText: missingInputsLabel(count, hasPlus)
    });
  }

  // Swap the content area to the Manage Documents screen (from the content header or the
  // Review & Submit documents card) and set its breadcrumb crumb.
  _openDocumentsView() {
    Promise.resolve().then(() => {
      this.activeView = "documents";
    });
    this._dispatchCrumb("Manage Documents");
  }

  // Re-read whether the envelope has any required documents. They only change server-side
  // (entity persists create them, entity removals delete them), so this runs on load and
  // after each mutation that can affect them. Non-fatal on failure: the flag keeps its
  // last known value.
  async _refreshRequiredDocuments() {
    if (!this.envelopeId) {
      this.hasRequiredDocuments = false;
      return;
    }
    try {
      const docs = await getRequiredDocuments({ envelopeId: this.envelopeId });
      this.hasRequiredDocuments = (docs || []).length > 0;
    } catch (error) {
      console.error("required documents refresh failed", error);
    }
  }

  // Open an action's interview from either entry point (a workspace action card or a Review &
  // Submit row): resolve the action and its owning entity, switch the shell to the
  // action-details view, and tell the app to add the interview breadcrumb crumb.
  _openAction(actionId) {
    const found = this._findEntityByActionId(actionId);
    if (!found) {
      return;
    }
    const { entity, action } = found;
    // Same contextual remove label the workspace card shows (see sortedItems): a new record's
    // single action removes the whole record on confirm, so the interview's overflow menu uses
    // the entity-remove wording; every other action just removes itself.
    const cascades = entity.isNew && (entity.actions?.length || 0) <= 1;
    const removeMenuLabel = cascades
      ? GROUPS[entity.groupId]?.removeLabel || "Remove action"
      : "Remove action";
    this.selectedAction = {
      actionId: action.id,
      entityId: entity.id,
      entityName: entity.name,
      entityType: entity.type,
      entityGroupId: entity.groupId,
      actionTitle: action.title,
      statusLabel: action.statusLabel,
      removeMenuLabel
    };
    
    this._loadActionSchema(entity);
    this._resetSaveStatus();
    this._dispatchCrumb(
      [entity.name, action.title].filter(Boolean).join(" - ")
    );
  }

  // Rebuild the Review & Submit summary, fetching any record-type schemas not yet cached. The
  // summary is assigned immediately from the cache (rows render at once; rows whose schema is
  // still loading show only their type section) and reassigned once the missing schemas land.
  // A late reassignment after the user left the view is harmless — re-entering rebuilds anyway —
  // but the failure toast is suppressed then. Failed fetches are not cached, so the next entry
  // retries them.
  _refreshReviewItems() {
    const missing = new Map();
    this.sortedItems.forEach((entity) => {
      const key = resolveSchemaKey(entity);
      if (!key) {
        return;
      }
      const cacheKey = schemaCacheKey(key);
      if (!this._schemaCache[cacheKey]) {
        missing.set(cacheKey, key);
      }
    });
    this.reviewItems = this._buildReviewItems();
    if (missing.size === 0) {
      return;
    }
    let failed = false;
    Promise.all(
      [...missing.entries()].map(([cacheKey, key]) =>
        getFormSchema({ objectName: key.objectName, type: key.type })
          .then((sections) => {
            this._schemaCache[cacheKey] = sections || [];
          })
          .catch(() => {
            failed = true;
          })
      )
    ).then(() => {
      this.reviewItems = this._buildReviewItems();
      if (failed && this.activeView === "review") {
        this._showToast("Review", "Some details could not be loaded", "error");
      }
    });
  }

  // Project the model into Review & Submit rows: one row per action, in sortedItems order. Each
  // row leads with a synthetic type section (Household Member Type for members, Investment &
  // Service Agreement Type for account-like rows), followed by the entity type's metadata
  // sections shaped against the action's saved form data — the same visible-field set as the
  // interview, keeping only fields that have a value (blank fields and the sections they empty
  // are dropped). The bespoke Trade Instructions section is interview-only and omitted here.
  _buildReviewItems() {
    const items = [];
    this.sortedItems.forEach((entity) => {
      const key = resolveSchemaKey(entity);
      // Lookup options are applied here too, so a stored record Id renders as its label in the
      // summary rather than the raw Id.
      const schema = key
        ? applyLookupOptions(this._schemaForEntity(entity), this._lookupOptions)
        : null;
      const isMember = entity.groupId === "householdMembers";
      entity.actions.forEach((action) => {
        const sections = [];
        if (isMember && entity.typeLabel) {
          sections.push({
            key: "type",
            title: "Household Member Type",
            fields: [
              {
                key: "memberType",
                label: "Member Type",
                value: entity.typeLabel
              }
            ]
          });
        } else if (!isMember) {
          sections.push({
            key: "type",
            title: "Investment & Service Agreement Type",
            fields: [{ key: "isaType", label: "ISA Type", value: action.title }]
          });
        }
        const draft = action.formData || {};
        (schema || []).forEach((section, index) => {
          const fields = shapeVisibleFields(
            section.fields,
            draft,
            this.userContext
          )
            .map((field) => ({
              key: field.apiName,
              label: field.label,
              value: formatFieldDisplayValue(field)
            }))
            .filter((field) => field.value !== "");
          if (fields.length) {
            sections.push({ key: `sec-${index}`, title: section.name, fields });
          }
        });
        items.push({
          key: action.id,
          icon: entity.iconVariant,
          title: action.title,
          subtitle: entity.name,
          expanded: true,
          sections
        });
      });
    });
    return items;
  }

  _showToast(title, message, variant, mode) {
    LightningToast.show({ label: title, message, variant, mode }, this);
  }

  // Reset the recurrent-failure tracking after a successful server save: the failure burst is
  // over, so the retry budget and the escalated warning re-arm.
  _recordSaveSuccess() {
    this._consecutiveSaveFailures = 0;
    this._saveRetryCount = 0;
    this._saveFailureAlertShown = false;
  }

  // Single choke point for recurring-save failures (autosave, flush-on-navigate, eager
  // related-party reconcile — not one-off actions, which keep their own immediate toasts).
  // Below the threshold the call site's own error toast shows (when provided); at the threshold
  // a sticky escalated toast replaces the per-failure noise until a save succeeds again.
  _recordSaveFailure(toast) {
    this._consecutiveSaveFailures += 1;
    if (this._consecutiveSaveFailures >= SAVE_FAILURE_ALERT_THRESHOLD) {
      if (!this._saveFailureAlertShown) {
        this._saveFailureAlertShown = true;
        this._showToast(
          "Changes not saved",
          "We're having trouble saving your changes. Please refresh the page and try again. " +
            "If the problem persists, contact Home Office Operations.",
          "error",
          "sticky"
        );
      }
      return;
    }
    if (toast) {
      this._showToast(toast.title, toast.message, "error");
    }
  }

  // Report the roles the server could not write because the relationship picklist has no such value.
  // The parties in every other role were saved, so this is a warning rather than an error: it names
  // the roles that need reconciling between the wizard's role table and the picklist.
  _reportRejectedRoles(rejectedRoles) {
    if (!rejectedRoles?.length) {
      return;
    }
    const roles = rejectedRoles.join(", ");
    console.warn(
      "[envelopeShellV2] related-party roles missing from the Role picklist",
      rejectedRoles
    );
    this._showToast(
      "Some related parties were not saved",
      `These roles are not available on relationship records: ${roles}. The other related parties were saved.`,
      "warning"
    );
  }

  // Order a group's rows for display: rows added through this envelope first, then existing rows
  // by oldest createdDate. Members show new rows newest-first; account-like groups keep new rows in
  // addition order and break existing-date ties by balance, highest first. Existing rows carry
  // createdDate (and account-like rows a numeric balance) from the model; new rows order by
  // insertion.
  _orderGroup(rows, groupId) {
    const isMembers = groupId === "householdMembers";
    const isNewRow = (row) => row.addedInEnvelope || row.isNew;
    const news = rows.filter((row) => isNewRow(row));
    const existing = rows.filter((row) => !isNewRow(row));
    const newSection = isMembers ? [...news].reverse() : [...news];
    const existingSection = [...existing].sort((a, b) => {
      const byDate = (a.createdDate || "").localeCompare(b.createdDate || "");
      if (byDate !== 0) {
        return byDate;
      }
      return isMembers ? 0 : (b.balance || 0) - (a.balance || 0);
    });
    return [...newSection, ...existingSection];
  }

  // True when the entity carries action items and none of them still owes inputs — the same
  // completion measure the action cards use (actionCompletion), so the sidebar indicator and the
  // workspace badges always agree. False for entities without actions.
  _entityActionsComplete(entity) {
    const actions = entity.actions || [];
    if (!actions.length) {
      return false;
    }
    const schema = this._schemaForEntity(entity);
    return actions.every(
      (action) =>
        actionCompletion(
          schema,
          entity,
          action.formData || {},
          this.userContext,
          this._registrationAttributes
        ).isComplete
    );
  }

  // The entity's prefetched schema, narrowed to the fields its interview actually shows (member
  // actions partition the shared 'Proposed Changes' schema by account type). The one lookup every
  // consumer goes through — cards, field rules, missing items, review, completion — so none of
  // them can disagree on the visible field set. Falsy while the schema is still loading, exactly
  // like the raw cache read it wraps.
  _schemaForEntity(entity) {
    const key = entity ? resolveSchemaKey(entity) : null;
    if (!key) {
      return null;
    }
    return filterSectionsByAccountType(
      this._schemaCache[schemaCacheKey(key)],
      key.accountType
    );
  }

  // Resolve once the browser has painted the pending DOM. The first animation frame runs just
  // before the frame carrying that DOM is drawn, so the second one runs after it is on screen —
  // long enough for a loading spinner to appear before heavy synchronous work blocks the thread.
  _nextPaint() {
    return new Promise((resolve) => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(resolve);
      });
    });
  }
}