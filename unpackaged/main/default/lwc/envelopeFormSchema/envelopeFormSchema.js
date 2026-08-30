/**
 * envelopeFormSchema — pure helpers for the V2 action-details interview form.
 *
 * Maps a Household Outline entity to its Envelope_Field__mdt schema key (Object__c + Type__c) and
 * evaluates the metadata's WHERE statements client-side. Kept dependency-free and side-effect-free
 * so it can be unit-tested directly and shared without coupling to any component.
 */

// The trust-held party roles are presented distinctly — Trustee and Grantor each keep their own
// label and subsection — but they ask the same questions, so both resolve to one
// Envelope_Field__mdt record set rather than one per role.
const TRUST_PARTY_MDT = 'Trust Related Party';

// The business-held party roles — authorized person, beneficial owner, control person — work the
// same way: distinct labels and subsections over one shared question set. They were previously
// mapped to a record set per role ('Authorized Person', 'Beneficial Owner', 'Control Person'), but
// no Section__mdt or Envelope_Field__mdt carries those Type__c values, so creating one from a
// business's Related Parties opened an interview reading "No fields configured for this type." The
// configured set is Business Related Party.
const BUSINESS_PARTY_MDT = 'Business Related Party';

// The retirement-plan-held party roles, like the trust ones, ask the same questions under distinct
// labels and so share a single Envelope_Field__mdt record set.
const RETIREMENT_PLAN_PARTY_MDT = 'Retirement Plan Related Party';

// The role an individual client names as their trusted contact. It stands alone rather than sharing a
// record set, since the questions it asks are its own.
const TRUSTED_CONTACT_MDT = 'Trusted Contact';

// Member (Account) record types: the Add-form's raw `type` token → Envelope_Field__mdt Type__c.
// Covers the household member types and the person types created from within a form (trustee,
// grantor, authorized person, beneficial owner), which resolve here like any other member. A token
// without a configured Type__c resolves to null (empty state).
const MEMBER_TYPE_TO_MDT = {
    client: 'Client - Individual',
    business: 'Client - Business',
    trust: 'Client - Trust',
    retirementPlan: 'Client - Retirement Plan',
    authorizedPerson: BUSINESS_PARTY_MDT,
    beneficialOwner: BUSINESS_PARTY_MDT,
    controlPerson: BUSINESS_PARTY_MDT,
    trustee: TRUST_PARTY_MDT,
    grantor: TRUST_PARTY_MDT,
    planTrustee: RETIREMENT_PLAN_PARTY_MDT,
    planAuthorizedPerson: RETIREMENT_PLAN_PARTY_MDT,
    trustedContact: TRUSTED_CONTACT_MDT
};

// The draft key the Related Parties section stores its whole value under: requirement key -> parties.
// Shared by the action-details page (which writes it) and the shell (which counts it toward an
// action's missing-inputs badge).
const RELATED_PARTIES_FIELD_KEY = 'relatedParties';

// The four Household Outline groups on the envelope model, in render order. The single source for
// iterating the model's entity lists in a stable order — the shell and the landing list both import
// it so their projections stay in lockstep.
const GROUP_IDS = ['householdMembers', 'accounts', 'dpisSponsor', 'serviceAgreements','cases'];

// Related parties a member must have, keyed by the outline's raw member type token and listed in
// render order. `type` is the party's Envelope_Field__mdt Type__c — the same vocabulary
// MEMBER_TYPE_TO_MDT resolves to — `min` the number of parties required, and `whereStatement` an
// optional condition in the metadata WHERE grammar, evaluated against the form draft so a
// subsection can depend on an answer given in the interview. A token absent here has no related
// parties. A `min` of zero is a slot the entity may fill but never owes: the subsection renders and
// takes parties like any other, and never counts against the entity's missing inputs.
//
// `aarRole` is the Account_Account_Relationship__c Role value each party persists as. It is held
// separately from the title because the relationship picklist does not necessarily name a role the
// way its subsection does. Every value here has to exist in the Role__c picklist, which is
// restricted.
//
// `types` narrows the existing-member picker (see memberRecordTypesFor). Every one of these roles is
// held by a person, so all of them accept an individual only — a corporate trustee cannot be picked.
//
// `group` is optional and names a shared minimum: rules carrying the same group are satisfied
// together, so their parties pool against one minimum and the group is owed once rather than per
// role. A retirement plan needs a Trustee or an Authorized Person, not one of each. Each role still
// keeps its own subsection, title and relationship role; only the requirement is shared. A rule
// without a group stands alone.
const GRANTOR_AAR_ROLE = 'Grantor';
const PERSON_PARTY_TYPES = ['Client - Individual'];

// The shared minimum a retirement plan's Trustee and Authorized Person roles both answer to.
const PLAN_FIDUCIARY_GROUP = 'planFiduciary';

const RELATED_PARTY_RULES = {
    client: [
        {
            key: 'trustedContact',
            title: 'Trusted Contact',
            type: TRUSTED_CONTACT_MDT,
            types: PERSON_PARTY_TYPES,
            aarRole: 'Trusted Contact',
            // Naming a trusted contact is the client's to decline, so the slot is offered rather
            // than owed and an individual without one is not short an input.
            min: 0,
            whereStatement: null
        }
    ],
    business: [
        {
            key: 'authorizedPerson',
            title: 'Authorized Person',
            type: 'Authorized Person',
            types: PERSON_PARTY_TYPES,
            aarRole: 'Authorized Person',
            min: 1,
            whereStatement: null
        },
        {
            key: 'beneficialOwner',
            title: 'Beneficial Owner',
            type: 'Beneficial Owner',
            types: PERSON_PARTY_TYPES,
            aarRole: 'Beneficial Owner',
            min: 1,
            // A business can legitimately have nobody meeting the reporting threshold, which is a
            // statement the user makes rather than a slot they fill — so the minimum is met by
            // either naming a beneficial owner or affirming there are none.
            //
            // The affirmation is a field on the account rather than wizard state on purpose: the
            // shell strips relatedParties out of Envelope_JSON__c on every save and re-reads the
            // parties from relationship records, and withoutRecordBackedEntities drops an existing
            // account's entity altogether, so a draft-only flag would be forgotten on reload and
            // the requirement would read as unmet again. isRecordFieldKey treats any unrecognised
            // draft key as a record field, so this one reaches the account write unaided.
            waiver: {
                field: 'No_Reportable_Beneficial_Owners__c',
                label: 'There are no reportable beneficial owners for this business.'
            },
            whereStatement: null
        },
        {
            key: 'controlPerson',
            title: 'Control Person',
            type: 'Control Person',
            types: PERSON_PARTY_TYPES,
            aarRole: 'Control Person',
            min: 1,
            whereStatement: null
        }
    ],
    trust: [
        {
            key: 'trustee',
            title: 'Trustee',
            type: TRUST_PARTY_MDT,
            types: PERSON_PARTY_TYPES,
            aarRole: 'Trustee',
            min: 1,
            whereStatement: null
        },
        {
            key: 'grantor',
            title: 'Grantor',
            type: TRUST_PARTY_MDT,
            types: PERSON_PARTY_TYPES,
            aarRole: GRANTOR_AAR_ROLE,
            min: 1,
            whereStatement: null
        }
    ],
    retirementPlan: [
        {
            key: 'planTrustee',
            title: 'Trustee',
            type: RETIREMENT_PLAN_PARTY_MDT,
            types: PERSON_PARTY_TYPES,
            aarRole: 'Trustee',
            min: 1,
            group: PLAN_FIDUCIARY_GROUP,
            whereStatement: null
        },
        {
            key: 'planAuthorizedPerson',
            title: 'Authorized Person',
            type: RETIREMENT_PLAN_PARTY_MDT,
            types: PERSON_PARTY_TYPES,
            aarRole: 'Authorized Person',
            min: 1,
            group: PLAN_FIDUCIARY_GROUP,
            whereStatement: null
        }
    ]
};

// Every related-party rule keyed by its requirement key, carrying the member type it belongs to.
// RELATED_PARTY_RULES is keyed by the parent member type and a key appears under exactly one parent,
// so this inversion is lossless. The keys are the same tokens MEMBER_TYPE_TO_MDT maps, so a member
// presented as one resolves its schema like any other member type.
const PARTY_RULE_BY_KEY = Object.entries(RELATED_PARTY_RULES).reduce(
    (map, [memberType, rules]) => {
        rules.forEach((rule) => {
            map[rule.key] = { ...rule, memberType };
        });
        return map;
    },
    {}
);

// Member types that carry related parties as relationship records — a business needs its
// authorized/beneficial/control persons, a trust its trustees and grantors, an individual may name a
// trusted contact.
const RELATED_PARTY_MEMBER_TYPES = new Set(Object.keys(RELATED_PARTY_RULES));

// The roles a person member may be presented as: the outline row reads the role rather than
// "Individual", and the interview opens the role's own field set. Every RELATED_PARTY_RULES key is
// presentable — a relationship in one of these roles is held for that role alone, so the label and
// the field set the key resolves to are the right ones. Kept as its own list rather than derived from
// the rules because it is the point where a role can be withheld from presentation: a role whose
// picklist value serves something else too must not put its label and form on a person who holds it
// for that other reason. The account-ownership slots in ACCOUNT_RELATED_PARTY_RULES are never
// presented — they are slots on an account, not roles on an entity.
const ROLE_PRESENTED_KEYS = new Set([
    'authorizedPerson',
    'beneficialOwner',
    'controlPerson',
    'trustee',
    'grantor',
    'planTrustee',
    'planAuthorizedPerson',
    'trustedContact'
]);

// The member types whose Account record persists through saveEntity, which resolves the type to a
// record type from this same set. Mirrors the Apex RECORD_TYPE_BY_MEMBER_TYPE keys.
const SAVEABLE_MEMBER_TYPES = new Set([
    'client',
    'business',
    'trust',
    'retirementPlan'
]);

// How each member type is named to the user. Kept beside the saveable set because the two are the
// same list seen twice: what can be created, and what it is called when offered.
const MEMBER_TYPE_LABELS = {
    client: 'Individual',
    business: 'Business',
    trust: 'Trust',
    retirementPlan: 'Retirement Plan'
};

// Prefix for the temporary id a related party carries between being created in the "Create new"
// dialog and its person Account existing. A party whose id is not a record id is still pending.
const PENDING_PARTY_ID_PREFIX = 'pending-';

const PENDING_PARTY_ID = new RegExp(`^${PENDING_PARTY_ID_PREFIX}(\\d+)$`);

// Outline groups whose entities are Financial Accounts, and so resolve their related parties from
// the selected registration rather than from a member type token. DPIs are Financial Accounts too.
const ACCOUNT_GROUP_IDS = new Set(['accounts', 'dpisSponsor']);

// The Financial_Account__c field whose value selects an account's related-party rules.
const REGISTRATION_TYPE_FIELD = 'Registration_Type__c';

// The Financial_Account_Role__c Role values the wizard owns. The picklist carries Custodian and
// Trusted Contact too; a row in one of those roles belongs to something else and is never
// reconciled away (see managedAccountRolesFor).
const PRIMARY_OWNER_FA_ROLE = 'Primary Owner';
const JOINT_OWNER_FA_ROLE = 'Joint Owner';
const BENEFICIARY_FA_ROLE = 'Beneficiary';

// Related parties a Financial Account must have, keyed by the registration group and listed in
// render order. Unlike RELATED_PARTY_RULES above, which keys on the outline's member type,
// accounts have no type token — their group is resolved from the selected Registration_Type__c
// via resolveRegistrationGroup. `types` lists the party record types a slot accepts (in the
// MEMBER_TYPE_TO_MDT vocabulary) and `max` its ceiling, null meaning unbounded. The owner's
// accepted type mirrors the registration: a person-owned account takes an Individual, a business
// account the Business entity, a trust account the Trust entity. Person-owned registrations hold
// exactly one Primary Owner; a joint registration adds a separate Joint Owner slot for the
// co-owners (one to four).
//
// `faRole` is the Financial_Account_Role__c Role value the slot persists as — the account-side
// counterpart of `aarRole` on the member rules. It is held separately from the title because a slot
// is titled for its registration ("Owner" on a business account) while the role vocabulary is fixed.
// Every value here has to exist in the Role__c picklist, which is restricted.
const ACCOUNT_OWNER_EXCLUSIVE = 'accountOwner';

const ACCOUNT_RELATED_PARTY_RULES = {
    individual: [
        {
            key: 'owner',
            title: 'Primary Owner',
            types: ['Client - Individual'],
            faRole: PRIMARY_OWNER_FA_ROLE,
            min: 1,
            max: 1,
            whereStatement: null
        }
    ],
    joint: [
        {
            key: 'owner',
            title: 'Primary Owner',
            types: ['Client - Individual'],
            faRole: PRIMARY_OWNER_FA_ROLE,
            min: 1,
            max: 1,
            exclusiveWith: ACCOUNT_OWNER_EXCLUSIVE,
            whereStatement: null
        },
        {
            key: 'jointOwner',
            title: 'Joint Owner',
            types: ['Client - Individual'],
            faRole: JOINT_OWNER_FA_ROLE,
            min: 1,
            max: 4,
            exclusiveWith: ACCOUNT_OWNER_EXCLUSIVE,
            whereStatement: null
        }
    ],
    business: [
        {
            key: 'owner',
            title: 'Owner',
            types: ['Client - Business'],
            faRole: PRIMARY_OWNER_FA_ROLE,
            min: 1,
            max: 1,
            whereStatement: null
        }
    ],
    trust: [
        {
            key: 'owner',
            title: 'Owner',
            types: ['Client - Trust'],
            faRole: PRIMARY_OWNER_FA_ROLE,
            min: 1,
            max: 1,
            whereStatement: null
        }
    ],
    beneficiary: [
        {
            key: 'owner',
            title: 'Owner',
            types: ['Client - Individual'],
            faRole: PRIMARY_OWNER_FA_ROLE,
            min: 1,
            max: null,
            whereStatement: null
        },
        {
            key: 'beneficiary',
            title: 'Beneficiary',
            types: ['Client - Individual'],
            faRole: BENEFICIARY_FA_ROLE,
            min: 1,
            max: null,
            whereStatement: null
        }
    ]
};

// The outline group whose entities are Service Agreements, and the Service__c field whose value
// selects their related-party rules. Services resolve their slots from the service type the
// interview itself asks for, the way an account resolves its own from the selected registration.
const SERVICE_GROUP_ID = 'serviceAgreements';
const SERVICE_TYPE_FIELD = 'Type__c';

// The party record types a service agreement's owner slots accept. Unlike every member-held role,
// which is held by a person, a service agreement can be owned by the household's Individual,
// Business or Trust entity — so all three are offered and the picker is narrowed to them rather
// than to one. Retirement plans are absent because getHouseholdRoster already excludes them from
// the roster an owner is picked from.
const SERVICE_OWNER_TYPES = [
    'Client - Individual',
    'Client - Business',
    'Client - Trust'
];

// The token the two owner slots share so neither may hold an entity the other holds. Held as a
// named group rather than a boolean because it reads at the call site as what it is — a set of
// slots that must name distinct entities — and because a third slot could join it later.
const SERVICE_OWNER_EXCLUSIVE = 'serviceOwner';

// Related parties a Service Agreement must have, keyed by the Service__c.Type__c value and listed
// in render order. The third rule table alongside RELATED_PARTY_RULES (keyed on a member type) and
// ACCOUNT_RELATED_PARTY_RULES (keyed on a registration group): a service has no type token of its
// own, so its group is the service type answered in the interview.
//
// `serviceField` is the Service__c lookup the slot persists into — the service-side counterpart of
// `faRole` on the account rules and `aarRole` on the member rules. A service agreement holds
// exactly one primary and at most one secondary owner, with no dates and no unbounded role, so the
// two lookups are the whole store and no junction object stands behind them.
//
// `exclusiveWith` names slots that must not share an entity: the secondary owner cannot be the
// primary, and a joint account's joint owner cannot be the primary owner. Rules carrying the same
// token cross-exclude; rules without it (the remaining account and member registrations) keep
// their behavior.
const SERVICE_PRIMARY_OWNER_FIELD = 'Primary_Owner__c';
const SERVICE_SECONDARY_OWNER_FIELD = 'Secondary_Owner__c';

// Both service types take the same two slots. Held as one shared list rather than duplicated per
// type so the two services are provably identical, and keyed per type anyway so a third service
// type has to opt in rather than inheriting owners by default.
const SERVICE_OWNER_RULES = [
    {
        key: 'primaryOwner',
        title: 'Primary Owner',
        types: SERVICE_OWNER_TYPES,
        serviceField: SERVICE_PRIMARY_OWNER_FIELD,
        min: 1,
        max: 1,
        exclusiveWith: SERVICE_OWNER_EXCLUSIVE,
        whereStatement: null
    },
    {
        key: 'secondaryOwner',
        title: 'Secondary Owner',
        types: SERVICE_OWNER_TYPES,
        serviceField: SERVICE_SECONDARY_OWNER_FIELD,
        // Offered rather than owed: a service agreement with one owner is not short an input.
        min: 0,
        max: 1,
        exclusiveWith: SERVICE_OWNER_EXCLUSIVE,
        whereStatement: null
    }
];

const SERVICE_RELATED_PARTY_RULES = {
    'Financial Planning': SERVICE_OWNER_RULES,
    'Multi-Family Office': SERVICE_OWNER_RULES
};

// Custodian__c's own options narrow once its Financial Account has a BD or RIA answer: BD offers
// only RBC, RIA offers everything except RBC and Direct. Direct is therefore only ever offered
// while BD or RIA is still unanswered, which also leaves every option unfiltered — there's nothing
// yet to narrow by. Values are Custodian__c API names (picklist option `value`, not `label`).
const BD_OR_RIA_FIELD = 'BD_or_RIA__c';
const CUSTODIAN_FIELD = 'Custodian__c';
const CUSTODIAN_VALUES_BY_BD_OR_RIA = {
    BD: new Set(['RBC']),
    RIA: new Set(['SCHWAB', 'FIDELITY', 'American Funds F2', 'Outside Manager'])
};

// A field's picklist options, narrowed for Custodian__c by the draft's current BD or RIA answer.
// Every other field's options pass through untouched.
function optionsFor(apiName, options, draft) {
    if (apiName !== CUSTODIAN_FIELD) {
        return options;
    }
    const allowed = CUSTODIAN_VALUES_BY_BD_OR_RIA[draft[BD_OR_RIA_FIELD]];
    if (!allowed) {
        return options;
    }
    return (options || []).filter((option) => allowed.has(option.value));
}

// Custodian__c must always render as a dropdown, never the few-options radio-group look
// (envelopeFieldControl.isRadioPicklist) — its own option count now shrinks under the BD/RIA
// filter above (as low as 3), which would otherwise cross that heuristic on its own.
function inputTypeFor(apiName, inputType) {
    return apiName === CUSTODIAN_FIELD ? 'select' : inputType;
}

// A change to BD_or_RIA__c narrows Custodian__c's own options (see optionsFor), so any Custodian
// answer already held must be cleared — a value valid under the old BD/RIA must not silently
// survive as an answer the new option list no longer offers. Returns the draft unchanged for a
// change to any other field.
function clearDependentCustodian(field, draft) {
    if (field !== BD_OR_RIA_FIELD || !(CUSTODIAN_FIELD in draft)) {
        return draft;
    }
    return { ...draft, [CUSTODIAN_FIELD]: '' };
}

// Party record type → the Account RecordType DeveloperNames a member of that type can carry. The
// existing-member picker filters on RecordType DeveloperName (MemberView.recordType), not label, and
// one member type spans more than one DeveloperName across wizard-created and pre-existing FSC
// accounts (e.g. a trust is 'Trust' or 'IndustriesInstitution') — the same groupings
// WizardEnvelopeStateService.addMemberByRecordType buckets on.
const MDT_TYPE_TO_RECORD_TYPES = {
    'Client - Individual': ['PersonAccount', 'Individual'],
    'Client - Business': ['Business', 'IndustriesBusiness'],
    'Client - Trust': ['Trust', 'IndustriesInstitution'],
    'Client - Retirement Plan': ['Retirement_Plan']
};

// Account action token → the Envelope_Field__mdt Type__c the interview loads its schema from, which
// is also the vocabulary EnvelopeActionCaseController routes on. A type with no configured fields
// resolves to an empty metadata form, which is correct for the two DMS actions: their whole subject
// is the Trade Instructions section, a custom section that renders independently of the schema.
const ACCOUNT_TYPE_TO_MDT = {
    accountClosure: 'Account Closure',
    updateDmsInstructions: 'Manage DMS Instructions',
    updateManagementStyle: 'Change Management Style',
    additionalFunding: 'Additional Funding',
    purchaseAlts: 'Purchase Alternative Investments'
};

const ACCOUNT_ACTION_TYPES = new Set(Object.keys(ACCOUNT_TYPE_TO_MDT));

// Account action token → the Type the Case itself carries. A separate map from ACCOUNT_TYPE_TO_MDT
// because the two vocabularies are not interchangeable: the DMS action's interview is configured
// under 'Manage DMS Instructions', but its Case is an 'Update DMS Instructions' — the value the rest
// of the org keys on (the Case and Order Ticket record pages, Order_Ticket__c.Type_of_Request__c).
// Purchase Alternative Investments splits the same way: its Envelope_Field__mdt schema (and the
// Apex sourceId) is the plural 'Purchase Alternative Investments', but the Case it opens carries the
// singular 'Purchase Alternative Investment' Type. The remaining three happen to coincide.
const ACCOUNT_TYPE_TO_CASE_TYPE = {
    ...ACCOUNT_TYPE_TO_MDT,
    updateDmsInstructions: 'Update DMS Instructions',
    purchaseAlts: 'Purchase Alternative Investment'
};

// The inverse of ACCOUNT_TYPE_TO_CASE_TYPE, for reading an action item back from its Case: the
// record stores the Case Type, while the catalog token is what keys the interview schema, titles the
// card and drives the "+" dialog's already-added rows. Keyed on the Case Type — inverting the mdt
// map instead left a DMS instructions Case unresolvable, so it was dropped from the outline on load.
const CASE_TYPE_TO_ACCOUNT_TYPE = Object.fromEntries(
    Object.entries(ACCOUNT_TYPE_TO_CASE_TYPE).map(([token, caseType]) => [caseType, token])
);

// Member action token → the member type whose record the action edits. A submitted member is
// locked, so a change to it is raised as an action item whose Case carries the request for review;
// the interview is the 'Proposed Changes' Case schema (see resolveSchemaKey), so this map's role
// is the action-catalog vocabulary and MEMBER_ACTION_TYPES. Only the whole-entity edits appear
// here — the plural party actions edit relationship records, not Account fields, and are not
// wired yet.
const MEMBER_ACTION_TO_MEMBER_TYPE = {
    editIndividual: 'client',
    editBusiness: 'business',
    editTrust: 'trust',
    editRetirementPlan: 'retirementPlan'
};

const MEMBER_ACTION_TYPES = new Set(Object.keys(MEMBER_ACTION_TO_MEMBER_TYPE));

// The Envelope_Field__mdt Type__c that configures member change requests. One shared type for all
// member kinds, partitioned per field by Account_Type__c rather than by a type per kind.
const PROPOSED_CHANGES_MDT = 'Proposed Changes';

// Member action token → the Envelope_Field__mdt Account_Type__c value whose fields its interview
// shows. The vocabulary is that field's restricted picklist: Person covers individual members —
// and every related-party role, should a party-level edit action ever be wired (mirroring how
// persistedMemberTypeFor collapses party roles to 'client') — while the entity kinds match theirs.
const MEMBER_ACTION_TO_ACCOUNT_TYPE = {
    editIndividual: 'Person',
    editBusiness: 'Business',
    editTrust: 'Trust',
    editRetirementPlan: 'Retirement Plan'
};

// Member action token → the Type the Case itself carries, and the vocabulary
// EnvelopeActionCaseController routes on. Kept as its own map for the same reason the account pair
// is split: the Case Type is an org-wide picklist value and need not track the catalog token.
const MEMBER_ACTION_TO_CASE_TYPE = {
    editIndividual: 'Edit Individual',
    editBusiness: 'Edit Business',
    editTrust: 'Edit Trust',
    editRetirementPlan: 'Edit Retirement Plan'
};

// The inverse, for reading a member action item back from its Case. Keyed on the Case Type for the
// same reason CASE_TYPE_TO_ACCOUNT_TYPE is: the record stores the Type, and a Type that resolves to
// no token is dropped from the outline on load.
const CASE_TYPE_TO_MEMBER_ACTION = Object.fromEntries(
    Object.entries(MEMBER_ACTION_TO_CASE_TYPE).map(([token, caseType]) => [caseType, token])
);


/**
 * The Account RecordType DeveloperNames a requirement's accepted party types correspond to, for
 * narrowing the existing-member picker. Returns [] for a requirement that names no types — the
 * member rules — which callers read as "no restriction".
 * @param {Array<string>} types  a requirement's `types`
 * @returns {Array<string>}
 */
function memberRecordTypesFor(types) {
    return (types || []).flatMap((type) => MDT_TYPE_TO_RECORD_TYPES[type] || []);
}

// Resolve a registration's group from its Registration_Type__mdt Category. Joint, Beneficiary,
// Business and Trust registrations get their own party rules; the person-owned categories
// (Individual, Retirement, Giving) — and any registration with no metadata record or category —
// take the single-owner default. Business and Trust accounts need only their single owner here,
// restricted to the matching entity type; that owner (a Business/Trust member) carries its own
// parties via the member-type rules.
function resolveRegistrationGroup(attributes) {
    switch (attributes?.category) {
        case 'Joint':
            return 'joint';
        case 'Beneficiary':
            return 'beneficiary';
        case 'Business':
            return 'business';
        case 'Trust':
            return 'trust';
        default:
            return 'individual';
    }
}

// Normalize a registration label for tolerant matching: trim, collapse internal whitespace and
// lowercase, so a purely cosmetic difference in spacing or casing still compares equal.
function normalizeRegistrationKey(label) {
    return String(label || '')
        .trim()
        .replace(/\s+/g, ' ')
        .toLowerCase();
}

// Resolve a registration's Registration_Type__mdt attributes from the prefetched map. The map is
// keyed by MasterLabel while the account stores the picklist value under Registration_Type__c; the
// two are maintained separately, so match exactly first, then fall back to a normalized comparison
// so a cosmetic label difference still resolves to the right Category. Returns undefined for a blank
// selection (no registration chosen yet — the caller then applies the single-owner default) and for
// a non-empty value with no matching row. The latter is a metadata mismatch — the picklist value
// does not correspond to any MasterLabel — so it is logged rather than silently defaulted, since it
// would otherwise masquerade as a single-owner account.
function resolveRegistrationAttributes(registrationAttributes, registrationValue) {
    const value = (registrationValue || '').trim();
    if (!value) {
        return undefined;
    }
    const attributes = registrationAttributes || {};
    if (attributes[value]) {
        return attributes[value];
    }
    const normalized = normalizeRegistrationKey(value);
    const match = Object.keys(attributes).find(
        (key) => normalizeRegistrationKey(key) === normalized
    );
    if (match) {
        return attributes[match];
    }
    console.warn(
        `envelopeFormSchema: Registration_Type__c "${registrationValue}" matches no Registration_Type__mdt MasterLabel; ` +
            'related-party rules fall back to a single owner. Align the picklist value with a MasterLabel that carries the intended Category.'
    );
    return undefined;
}

// ISA groups: outline group id → { Object__c, Type__c }. Groups without configured fields are
// absent and resolve to null (empty state). DPIs are still Financial_Account__c records
// (distinguished on the record by DPI__c), but they carry their own 'ISA - DPI' field schema
// rather than sharing the account 'ISA - Fin Acct' one.
const ISA_GROUP_TO_KEY = {
    accounts: { objectName: 'Financial_Account__c', type: 'ISA - Fin Acct' },
    dpisSponsor: { objectName: 'Financial_Account__c', type: 'ISA - DPI' },
    serviceAgreements: { objectName: 'Service__c', type: 'ISA - Service Agreement' }
};

// A member presented as a related-party role offers the edit of its own role, the counterpart of the
// individual's 'Edit Individual'. Distinct from the plural entries below, which sit on the business or
// trust row and edit that entity's parties rather than a person's own record.
const PARTY_ACTION_CATALOG = Object.values(PARTY_RULE_BY_KEY)
    .filter((rule) => ROLE_PRESENTED_KEYS.has(rule.key))
    .reduce(
        (map, rule) => ({
            ...map,
            [rule.key]: [{ id: `edit_${rule.key}`, label: `Edit ${rule.title}` }]
        }),
        {}
    );

// Actions the "Add action item" dialog offers for an existing household member, keyed by the
// outline's raw member type token. Individuals expose only their own edit; the entity types that
// carry parties add an edit per related-party role (the same roles RELATED_PARTY_RULES models).
const MEMBER_ACTION_CATALOG = {
    client: [{ id: 'editIndividual', label: 'Edit Individual' }],
    business: [
        { id: 'editBusiness', label: 'Edit Business' },
        { id: 'editAuthorizedPersons', label: 'Edit Authorized Person(s)' },
        { id: 'editBeneficialOwners', label: 'Edit Beneficial Owner(s)' },
        { id: 'editControlPersons', label: 'Edit Control Person(s)' }
    ],
    trust: [
        { id: 'editTrust', label: 'Edit Trust' },
        { id: 'editTrustees', label: 'Edit Trustee(s)' },
        { id: 'editGrantors', label: 'Edit Grantor(s)' }
    ],
    retirementPlan: [
        { id: 'editRetirementPlan', label: 'Edit Retirement Plan' },
        { id: 'editPlanTrustees', label: 'Edit Trustee(s)' },
        { id: 'editPlanAuthorizedPersons', label: 'Edit Authorized Person(s)' }
    ],
    ...PARTY_ACTION_CATALOG
};

// Whether a Managed_Account_Platform__c value is a DMS platform (DMS or DMS (Wrap)) — the platforms
// that gate DMS-specific behavior (the Update DMS Instructions account action and the Trade
// Instructions interview section). Single source for this set.
function isDmsPlatform(value) {
    return value === 'DMS' || value === 'DMS (Wrap)';
}

function canPurchaseAlts(value) {
    return value === 'BD Exclusion' || value === 'AltMS' || value === 'DMS' || value === 'DMS (Wrap)';
}

// Actions the dialog offers for an existing Account, in design order. Two are conditional on the
// account's own fields (see `condition` below): Update Management Style shows only for RIA
// accounts, Update DMS Instructions only for the DMS platforms. The rest are always offered.
const ACCOUNT_ACTION_CATALOG = [
    { id: 'accountClosure', label: 'Account Closure' },
    {
        id: 'updateManagementStyle',
        label: 'Update Management Style',
        condition: (entity) => entity.bdOrRia === 'RIA'
    },
    {
        id: 'updateDmsInstructions',
        label: 'Update DMS Instructions',
        condition: (entity) => isDmsPlatform(entity.managedAccountPlatform)
    },
    { id: 'additionalFunding', label: 'Additional Funding' },
    {
        id: 'purchaseAlts',
        label: 'Purchase Alternative Investments',
        condition: (entity) => canPurchaseAlts(entity.managedAccountPlatform)
    }
];

// Read-only display formatters for summary views (e.g. Review & Submit). en-US/USD literals
// match the design; cached once at module scope.
const CURRENCY_DISPLAY = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
});
const NUMBER_DISPLAY = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });
const DATETIME_DISPLAY = new Intl.DateTimeFormat('en-US', {
    month: '2-digit',
    day: '2-digit',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
});

/**
 * The account-action catalog token for an action item read back from its Case, derived from the
 * Case's own Type.
 * @param {string} caseType  a Case Type, e.g. 'Third Party Money Movement'
 * @returns {string|null} the catalog token, or null for a Type the catalog does not offer
 */
function accountActionTypeFor(caseType) {
    return CASE_TYPE_TO_ACCOUNT_TYPE[caseType] || null;
}

/**
 * The display label for an account-action token, as the "Add action item" dialog shows it. Falls
 * back to the token so an entry retired from the catalog still renders something readable.
 * @param {string} type  a catalog token, e.g. 'thirdPartyMoneyMovement'
 * @returns {string}
 */
function accountActionLabelFor(type) {
    const match = ACCOUNT_ACTION_CATALOG.find((action) => action.id === type);
    return match ? match.label : type || '';
}

/**
 * The member-action catalog token for an action item read back from its Case, derived from the
 * Case's own Type.
 * @param {string} caseType  a Case Type, e.g. 'Edit Individual'
 * @returns {string|null} the catalog token, or null for a Type the catalog does not offer
 */
function memberActionTypeFor(caseType) {
    return CASE_TYPE_TO_MEMBER_ACTION[caseType] || null;
}

/**
 * The display label for a member-action token, as the "Add action item" dialog shows it. The member
 * catalog is keyed by member type, so the token is matched across every type's entries. Falls back
 * to the token so an entry retired from the catalog still renders something readable.
 * @param {string} type  a catalog token, e.g. 'editIndividual'
 * @returns {string}
 */
function memberActionLabelFor(type) {
    const match = Object.values(MEMBER_ACTION_CATALOG)
        .flat()
        .find((action) => action.id === type);
    return match ? match.label : type || '';
}

/**
 * Resolve the Envelope_Field__mdt query key for an entity, or null when no schema is configured
 * for its type (caller renders a graceful empty state). A member action's key also carries the
 * accountType its interview filters by — it rides alongside the cache key (which stays
 * 'objectName|type') because all account types share one schema fetch and partition client-side.
 * @param {{groupId: string, type?: string}} entity
 * @returns {{objectName: string, type: string, accountType?: string} | null}
 */
function resolveSchemaKey(entity) {
    if (!entity || !entity.groupId) {
        return null;
    }
    if (entity.groupId === 'householdMembers') {
        const type = MEMBER_TYPE_TO_MDT[entity.type];
        return type ? { objectName: 'Account', type } : null;
    }
    // A member action item is a Case-backed entity whose interview records a change request: its
    // answers are the Case's own Proposed_* fields, configured under the shared 'Proposed Changes'
    // type and partitioned by Account_Type__c, so every member kind resolves to the same schema
    // and the accountType narrows it to the fields that kind shows.
    if (entity.groupId === 'cases' && MEMBER_ACTION_TYPES.has(entity.type)) {
        return {
            objectName: 'Case',
            type: PROPOSED_CHANGES_MDT,
            accountType: MEMBER_ACTION_TO_ACCOUNT_TYPE[entity.type]
        };
    }
     if (entity.groupId === 'cases' && ACCOUNT_ACTION_TYPES.has(entity.type)) {
        const type = ACCOUNT_TYPE_TO_MDT[entity.type];
        return {objectName: 'Case', type : type } ;
    }
    return ISA_GROUP_TO_KEY[entity.groupId] || null;
}

/**
 * Resolve the action-item types the "Add action item" dialog should offer for an existing
 * household entity. Members map by their type token; accounts return the account catalog with the
 * conditional actions filtered by the entity's own fields (bdOrRia, managedAccountPlatform). DPIs
 * and service agreements have no actions yet and resolve to an empty list, which the outline uses
 * to hide their "+".
 * @param {{groupId: string, type?: string, bdOrRia?: string, managedAccountPlatform?: string}} entity
 * @returns {Array<{id: string, label: string}>}
 */
function resolveActionCatalog(entity) {
    if (!entity?.groupId) {
        return [];
    }
    if (entity.groupId === 'householdMembers') {
        // Only the whole-entity edits are wired end to end. The plural party entries edit the
        // entity's related-party records rather than its own fields and are filtered out until
        // that path exists, so the dialog never offers an action that cannot be raised.
        return (MEMBER_ACTION_CATALOG[entity.type] || []).filter((action) =>
            MEMBER_ACTION_TYPES.has(action.id)
        );
    }
    if (entity.groupId === 'accounts') {
        return ACCOUNT_ACTION_CATALOG.filter(
            (action) => !action.condition || action.condition(entity)
        ).map(({ id, label }) => ({ id, label }));
    }
    return [];
}

/**
 * The schema-cache key for a resolved schema key: 'objectName|type'. Single source for this format,
 * shared by the shell's prefetch cache and the Apex getAllFormSchemas map so the two always align.
 * @param {{objectName: string, type: string} | null} key
 * @returns {string | null}
 */
function schemaCacheKey(key) {
    return key ? `${key.objectName}|${key.type}` : null;
}

// The left-hand token of a WHERE clause may reference the running user instead of the form draft:
// a `$User.<Field>` token (e.g. `$User.Relationship_to_Firm__c`) resolves against userContext, any
// other token against the draft. The user field name is matched case-insensitively, since the
// metadata casing (`Relationship_to_Firm__c`) can differ from the org field's (`Relationship_to_firm__c`).
const USER_TOKEN = /^\$User\.(\w+)$/i;
// A `$Party.<roleKey>.<Field>` token resolves against the related party occupying <roleKey> — the
// requirementKey (rule.key from RELATED_PARTY_RULES) the party was selected into — read from the
// reserved `$party` sub-object of the context bag (see derivePartyContext). Both segments are matched
// case-insensitively, like $User, since the metadata casing can differ from the org field's. An
// unselected role or an unknown field yields undefined, so a clause naming a party that has not been
// picked is simply unsatisfied: this is also how "is this person a related party?" is expressed.
const PARTY_TOKEN = /^\$Party\.(\w+)\.(\w+)$/i;

// Case-insensitive property read, shared by the $User and $Party operand branches.
function caseInsensitiveGet(obj, wanted) {
    if (!obj) {
        return undefined;
    }
    const want = String(wanted).toLowerCase();
    const key = Object.keys(obj).find((k) => k.toLowerCase() === want);
    return key === undefined ? undefined : obj[key];
}

function resolveOperand(token, draft, context) {
    const userMatch = token.match(USER_TOKEN);
    if (userMatch) {
        return caseInsensitiveGet(context, userMatch[1]);
    }
    const partyMatch = token.match(PARTY_TOKEN);
    if (partyMatch) {
        const role = caseInsensitiveGet(context && context.$party, partyMatch[1]);
        return caseInsensitiveGet(role, partyMatch[2]);
    }
    return draft[token];
}

// Convert a SQL LIKE pattern to a case-insensitive anchored RegExp: `%` matches any run of
// characters, `_` matches a single character, and every other character is matched literally.
// LIKE is case-insensitive.
function likePatternToRegExp(pattern) {
    const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const body = escaped.replace(/%/g, '.*').replace(/_/g, '.');
    return new RegExp(`^${body}$`, 'i');
}

// Whether a resolved operand satisfies a SQL LIKE pattern. A multi-select value (an array of the
// selected entries) matches when any entry matches the pattern; any other value is coerced to a
// string. A null/undefined value is treated as an empty string.
function valueMatchesLike(value, pattern) {
    const rx = likePatternToRegExp(pattern);
    if (Array.isArray(value)) {
        return value.some((entry) => rx.test(String(entry)));
    }
    return rx.test(String(value ?? ''));
}

// Whether a statement's outer parentheses enclose all of it. `(A AND B)` does; `(A) AND (B)` does not,
// and stripping that one would corrupt it into `A) AND (B`. Parentheses inside a quoted pattern are
// literal text, so quoted runs are skipped rather than counted.
function isWrappedInParens(statement) {
    if (!statement.startsWith('(') || !statement.endsWith(')')) {
        return false;
    }
    let depth = 0;
    let inQuote = false;
    for (let i = 0; i < statement.length; i += 1) {
        const character = statement[i];
        if (character === "'") {
            inQuote = !inQuote;
        } else if (!inQuote && character === '(') {
            depth += 1;
        } else if (!inQuote && character === ')') {
            depth -= 1;
            // The opening parenthesis closed before the end, so the pair wraps only part of it.
            if (depth === 0 && i < statement.length - 1) {
                return false;
            }
        }
    }
    return depth === 0;
}

// Split a WHERE statement on AND/OR only at top level (outside single-quoted literals). Without this,
// values such as 'Draft and Submit - Alt Investment' are split at the embedded " and " and each
// fragment fails open as visible.
function containsTopLevelWhereOperator(statement, operator) {
    const needle = ` ${operator} `;
    const lower = statement.toLowerCase();
    const needleLower = needle.toLowerCase();
    let inQuote = false;

    for (let index = 0; index <= statement.length - needle.length; index += 1) {
        const character = statement[index];
        if (character === "'") {
            inQuote = !inQuote;
            continue;
        }
        if (!inQuote && lower.slice(index, index + needle.length) === needleLower) {
            return true;
        }
    }

    return false;
}

function splitTopLevelWhereOperator(statement, operator) {
    const needle = ` ${operator} `;
    const lower = statement.toLowerCase();
    const needleLower = needle.toLowerCase();
    const parts = [];
    let inQuote = false;
    let start = 0;

    for (let index = 0; index <= statement.length - needle.length; index += 1) {
        const character = statement[index];
        if (character === "'") {
            inQuote = !inQuote;
            continue;
        }
        if (!inQuote && lower.slice(index, index + needle.length) === needleLower) {
            parts.push(statement.slice(start, index).trim());
            start = index + needle.length;
            index = start - 1;
        }
    }

    parts.push(statement.slice(start).trim());
    return parts;
}

/**
 * Evaluate a metadata WHERE statement (Shown/Required) against the current form draft and the
 * running user's attributes. Supports AND/OR composition; parenthesised grouping; a leading `NOT`
 * negating the rest of a clause; `=` / `!=` comparisons against quoted strings, booleans, and null;
 * and `LIKE` / `NOT LIKE` against a quoted pattern (`%` and `_` wildcards, case-insensitive). For a
 * multi-select value (stored as an array) a `LIKE` clause matches when any selected entry matches the
 * pattern, so it can test membership. A left-hand `$User.<Field>` token is resolved against
 * userContext rather than the draft, and a `$Party.<roleKey>.<Field>` token against the selected
 * related party in that role (userContext.$party — see derivePartyContext). Returns true for a
 * blank/unparseable statement (fail-open, matching the v1 form behavior).
 *
 * Note the AND/OR split runs before grouping is unwrapped, so it does not respect parentheses: a
 * statement mixing the two operators across groups (`(A AND B) OR C`) is split on AND first and will
 * not evaluate as written. Grouping a single clause — the form this was built for — is unaffected.
 * @param {string} statement
 * @param {object} draft  field apiName → value
 * @param {object} userContext  $User.<Field> → running-user value
 * @returns {boolean}
 */
function evaluateWhereStatement(statement, draft = {}, userContext = {}) {
    if (!statement) {
        return true;
    }

    // Grouping is unwrapped before the operator split so a grouped clause reaches the matchers, which
    // are all anchored on a field name and would otherwise fail to match the leading parenthesis.
    if (isWrappedInParens(statement)) {
        return evaluateWhereStatement(statement.slice(1, -1).trim(), draft, userContext);
    }

    if (containsTopLevelWhereOperator(statement, 'AND')) {
        return splitTopLevelWhereOperator(statement, 'AND')
            .every((clause) => evaluateWhereStatement(clause.trim(), draft, userContext));
    }
    if (containsTopLevelWhereOperator(statement, 'OR')) {
        return splitTopLevelWhereOperator(statement, 'OR')
            .some((clause) => evaluateWhereStatement(clause.trim(), draft, userContext));
    }

    // A leading `NOT` negates the clause that follows (e.g. `NOT Source_of_Funds__c LIKE '%X%'`).
    // Checked after the operator split so `NOT A AND B` reads as `(NOT A) AND B`, matching SOQL
    // precedence, rather than negating the whole conjunction.
    const notMatch = statement.match(/^NOT\s+(.+)$/i);
    if (notMatch) {
        return !evaluateWhereStatement(notMatch[1].trim(), draft, userContext);
    }

    // Every matcher below anchors its left operand on the same alternation:
    //   $User.<field>            — running-user attribute (userContext)
    //   $Party.<role>.<field>    — the selected related party in <role> (userContext.$party)
    //   <field>                  — a plain draft answer
    // resolveOperand routes each shape to the right source; keep the alternation in sync across the
    // matchers, or a token will silently fall through to the fail-open tail and read as always-shown.

    // `LIKE` / `NOT LIKE` against a quoted pattern (e.g. `Source_of_Funds__c LIKE '%Advisory Account%'`).
    // For a multi-select value the clause matches when any selected entry matches the pattern, so it
    // can test membership. NOT LIKE is checked first so it is not swallowed by the LIKE matcher.
    const notLikeMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s+NOT\s+LIKE\s+'([^']*)'$/i);
    if (notLikeMatch) {
        return !valueMatchesLike(
            resolveOperand(notLikeMatch[1], draft, userContext),
            notLikeMatch[2]
        );
    }

    const likeMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s+LIKE\s+'([^']*)'$/i);
    if (likeMatch) {
        return valueMatchesLike(
            resolveOperand(likeMatch[1], draft, userContext),
            likeMatch[2]
        );
    }

    const eqMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*=\s*'([^']*)'$/);
    if (eqMatch) {
        // Some statements quote a boolean literal (e.g. `Other__c = 'True'`) against a checkbox
        // value; compare boolean-wise in that case, otherwise a plain string compare.
        if (/^(true|false)$/i.test(eqMatch[2])) {
            const expected = eqMatch[2].toLowerCase() === 'true';
            const actual = resolveOperand(eqMatch[1], draft, userContext);
            return (actual === true || actual === 'true') === expected;
        }
        return String(resolveOperand(eqMatch[1], draft, userContext) ?? '') === eqMatch[2];
    }

    const neqMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*!=\s*'([^']*)'$/);
    if (neqMatch) {
        if (/^(true|false)$/i.test(neqMatch[2])) {
            const expected = neqMatch[2].toLowerCase() === 'true';
            const actual = resolveOperand(neqMatch[1], draft, userContext);
            return (actual === true || actual === 'true') !== expected;
        }
        return String(resolveOperand(neqMatch[1], draft, userContext) ?? '') !== neqMatch[2];
    }

    const eqBoolMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*=\s*(true|false)$/i);
    if (eqBoolMatch) {
        const expected = eqBoolMatch[2].toLowerCase() === 'true';
        const actual = resolveOperand(eqBoolMatch[1], draft, userContext);
        return (actual === true || actual === 'true') === expected;
    }

    const neqBoolMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*!=\s*(true|false)$/i);
    if (neqBoolMatch) {
        const expected = neqBoolMatch[2].toLowerCase() === 'true';
        const actual = resolveOperand(neqBoolMatch[1], draft, userContext);
        return (actual === true || actual === 'true') !== expected;
    }

    const eqNullMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*=\s*null$/i);
    if (eqNullMatch) {
        const v = resolveOperand(eqNullMatch[1], draft, userContext);
        return v === null || v === undefined || v === '';
    }

    const neqNullMatch = statement.match(/^(\$User\.\w+|\$Party\.\w+\.\w+|\w+)\s*!=\s*null$/i);
    if (neqNullMatch) {
        const v = resolveOperand(neqNullMatch[1], draft, userContext);
        return v !== null && v !== undefined && v !== '';
    }

    // Fail open, so a syntax this evaluator doesn't know can never hide a configured field. It does
    // silently drop the condition, though, which reads as "always shown" and is indistinguishable from
    // a field with no condition at all — so say which statement was skipped.
    console.warn(
        'envelopeFormSchema: WHERE statement not understood, treating as true:',
        statement
    );
    return true;
}

/**
 * The type-appropriate "empty" value for a field's control: [] for multi-selects, false for
 * checkboxes/booleans, '' otherwise. Used both to seed a control and to detect a blank value.
 * @param {object} field  raw Envelope_Field__mdt field shape
 * @returns {[]|boolean|string}
 */
// One empty array per field, rather than a fresh one per call. shapeVisibleFields runs on every
// rebuild of the form, and LWC patches public props by identity — so a new [] handed to
// lightning-dual-listbox re-set the value of every untouched multi-select on every render of the page.
// Keyed on the raw field metadata (stable: it comes from the shell's schema cache) rather than shared
// globally, so an in-place mutation by one control can never leak into another field.
const EMPTY_MULTI_BY_FIELD = new WeakMap();

function emptyValueForField(field) {
    if (field.type === 'MULTIPICKLIST') {
        let empty = EMPTY_MULTI_BY_FIELD.get(field);
        if (!empty) {
            empty = [];
            EMPTY_MULTI_BY_FIELD.set(field, empty);
        }
        return empty;
    }
    if (field.inputType === 'checkbox' || field.type === 'BOOLEAN') {
        return false;
    }
    return '';
}

function isBooleanField(field) {
    return field.inputType === 'checkbox' || field.type === 'BOOLEAN';
}

/**
 * Whether a control value counts as blank (unfilled): an empty array, false, null/undefined, or a
 * blank string. A required checkbox is therefore "empty" until checked.
 * @param {[]|boolean|string|null|undefined} value
 * @returns {boolean}
 */
function isEmptyValue(value) {
    if (Array.isArray(value)) {
        return value.length === 0;
    }
    if (value === false || value === null || value === undefined) {
        return true;
    }
    return String(value).trim() === '';
}

/**
 * Whether two draft values are the same answer.
 *
 * This is the codebase's single definition of "nothing changed", and it is load-bearing rather than a
 * convenience. Every control on the interview page funnels its edits through one handler that replaces
 * the form draft and signals the shell that the user is editing; the shell reacts by flipping its
 * save status, which re-renders the page and re-sets every control's value. A control that re-fires
 * `change` when its value is assigned programmatically therefore closes a ring, and the only thing
 * that keeps that ring open is refusing to treat a value we already hold as an edit.
 *
 * Multi-selects compare by their joined form — the shape they persist in — because an untouched one is
 * handed a fresh empty array on every rebuild. Composite section values (tradeInstructions,
 * relatedParties) are plain nested data with no cycles, so they compare serialized.
 * null/undefined/'' all read as unset; `false` deliberately does not, because unchecking a saved
 * checkbox is a real change. Every branch errs toward "changed": a wrong "changed" costs one extra
 * draft write, a wrong "unchanged" silently drops the user's edit.
 * @param {*} a
 * @param {*} b
 * @returns {boolean}
 */
function draftValuesEqual(a, b) {
    if (a === b) {
        return true;
    }
    if (Array.isArray(a) || Array.isArray(b)) {
        return (Array.isArray(a) ? a : []).join(';') === (Array.isArray(b) ? b : []).join(';');
    }
    const aIsObject = typeof a === 'object' && a !== null;
    const bIsObject = typeof b === 'object' && b !== null;
    if (aIsObject || bIsObject) {
        return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
    }
    return (a ?? '') === (b ?? '');
}

/**
 * Whether two allocation row sets are the same set: identity first, then field by field.
 *
 * Both halves are load-bearing, for different callers. Inside the allocation table every handler
 * rebuilds the array with `map` and returns the *same object* for each row it did not touch, so the
 * identity fast-path settles an unchanged set immediately and stays cheap.
 *
 * Across a component boundary identity can never match, and this is the part that is easy to get
 * wrong: a parent's rows reach the table through LWC's read-only membrane, and the table normalizes
 * them into objects of its own before it emits anything. So the section comparing what the table
 * reported against what it handed down is comparing two disjoint sets of objects that describe the
 * same rows. An identity-only check there never fires once — a guard that looks present and does
 * nothing, which is worse than no guard at all.
 *
 * Compared field by field rather than by serializing, so key order cannot decide the answer.
 * @param {Array<object>} a
 * @param {Array<object>} b
 * @returns {boolean}
 */
function strategyRowsEqual(a, b) {
    const left = a || [];
    const right = b || [];
    if (left.length !== right.length) {
        return false;
    }
    return left.every((row, index) => {
        const other = right[index];
        if (row === other) {
            return true;
        }
        return (
            String(row?.id ?? '') === String(other?.id ?? '') &&
            (row?.strategy ?? '') === (other?.strategy ?? '') &&
            (row?.type ?? '') === (other?.type ?? '') &&
            (row?.fundingAmount ?? null) === (other?.fundingAmount ?? null) &&
            (row?.fundingPercent ?? null) === (other?.fundingPercent ?? null)
        );
    });
}

/**
 * How long a buffered edit sits before it commits on its own (see envelopeTradeInstructions).
 * Typing buffers locally and commits on blur; this idle window is the fallback so the section's
 * completion dot and the autosave cycle are not held hostage to a blur that may never come. Shared so
 * the trade section and its allocation table cannot drift apart.
 */
const COMMIT_IDLE_MS = 400;

/**
 * Resolve a picklist value to its option label; falls back to the raw value when the option is
 * no longer active in the metadata.
 * @param {Array<{label: string, value: string}>} options
 * @param {string} value
 * @returns {string}
 */
function optionLabel(options, value) {
    const match = (options || []).find((option) => option.value === value);
    return match ? match.label : String(value);
}

/**
 * Supply options for lookup (REFERENCE) fields, which — unlike picklists — carry no values of their
 * own: the describe yields only the target object, so the candidate records must be queried by the
 * host (e.g. rep codes scoped to the household's advisor team). Keys are either object-qualified
 * (`Object__c|Field_API__c`) or a bare field API name, the qualified form taking precedence. Return
 * a copy of `sections` with those fields turned into single-select picklists, which renders them via
 * the searchable combobox and lets summary views resolve the stored Id back to its label. A lookup
 * with no options configured here is left as-is and surfaces through the field control's
 * unsupported-type fallback — the signal that it still needs an option source.
 * Memoized per (sections, optionsByApiName) identity. Both inputs are only ever replaced wholesale —
 * the shell assigns `_rawActionSchema` from its schema cache and rebuilds `_lookupOptions` with a
 * spread — so identity keying is sound. Returning the same array for the same inputs is load-bearing:
 * the result is bound straight into envelopeActionDetails as `sections`, LWC patches public props by
 * identity, and a fresh array on every read rebuilt the entire interview — every section object and
 * every field object — on every unrelated re-render of the shell (four of them per autosave cycle, as
 * the save status walks pending → saving → saved → idle). That churn is what turned a single stray
 * change event into a sustained loop.
 * @param {Array} sections  raw schema sections (Envelope_Field__mdt shapes)
 * @param {object} optionsByApiName  'Object__c|Field_API__c' or field apiName -> [{label, value}]
 * @returns {Array} sections with lookup options applied
 */
const LOOKUP_OPTIONS_MEMO = new WeakMap();
const NO_SECTIONS = [];

function applyLookupOptions(sections, optionsByApiName = {}) {
    if (!sections) {
        return NO_SECTIONS;
    }
    if (!Object.keys(optionsByApiName || {}).length) {
        return sections;
    }
    let byOptions = LOOKUP_OPTIONS_MEMO.get(sections);
    if (!byOptions) {
        byOptions = new WeakMap();
        LOOKUP_OPTIONS_MEMO.set(sections, byOptions);
    }
    const cached = byOptions.get(optionsByApiName);
    if (cached) {
        return cached;
    }
    const applied = sections.map((section) => ({
        ...section,
        fields: (section.fields || []).map((field) => {
            // Object-qualified key first: a field API name can exist on more than one of a type's
            // objects, and each would need its own candidates. The bare name stays supported for
            // sources that are unambiguous across the whole form.
            const options =
                optionsByApiName[`${field.objectApiName}|${field.fieldPath}`] ??
                optionsByApiName[field.fieldPath];
            // An empty list is "no option source resolved", not "a picklist with nothing in it".
            // Converting on an empty list turned a required lookup into an unanswerable select — live
            // for Rep_Code__c on any household whose advisor team returns no rep codes, which left the
            // Financial Account interview permanently incompletable.
            if (!options || !options.length) {
                return field;
            }
            return {
                ...field,
                type: 'PICKLIST',
                inputType: 'select',
                picklistOptions: options
            };
        })
    }));
    byOptions.set(optionsByApiName, applied);
    return applied;
}

/**
 * Keep only the fields a given account type's interview shows, for schema types partitioned by
 * Envelope_Field__mdt.Account_Type__c (Proposed Changes). The server normalizes a blank row to
 * 'Person', so a present accountType is authoritative; a field with no accountType property at
 * all was served before the column existed and is kept — showing every field degrades better
 * than hiding ones the type may own. Sections left with no fields are dropped.
 *
 * Memoized per sections identity, same rationale as applyLookupOptions: the result is bound into
 * templates by identity, so a fresh array per read would rebuild the interview on every
 * re-render. Falsy inputs pass through unchanged — no accountType means an unpartitioned type
 * (every consumer but member actions), and an unloaded schema must stay falsy so "not loaded
 * yet" checks keep working.
 * @param {Array} sections  raw schema sections (Envelope_Field__mdt shapes)
 * @param {string} accountType  an Account_Type__c value ('Person' | 'Business' | ...)
 * @returns {Array} sections narrowed to the account type's fields
 */
const ACCOUNT_TYPE_FILTER_MEMO = new WeakMap();

function filterSectionsByAccountType(sections, accountType) {
    if (!sections || !accountType) {
        return sections;
    }
    let byType = ACCOUNT_TYPE_FILTER_MEMO.get(sections);
    if (!byType) {
        byType = new Map();
        ACCOUNT_TYPE_FILTER_MEMO.set(sections, byType);
    }
    const cached = byType.get(accountType);
    if (cached) {
        return cached;
    }
    const filtered = sections
        .map((section) => ({
            ...section,
            fields: (section.fields || []).filter(
                (field) => !field.accountType || field.accountType === accountType
            )
        }))
        .filter((section) => section.fields.length > 0);
    byType.set(accountType, filtered);
    return filtered;
}

/**
 * Translate a member's Account-keyed values into a change-request draft keyed by the proposing
 * Case field, through each schema field's originalAccountField mapping. Fields without a mapping
 * or without a source value contribute nothing, so a partial schema seeds a partial draft; the
 * first field to claim a key wins, matching the schema builder's tie-break.
 * @param {Array} sections  raw schema sections (change-request shapes)
 * @param {object} accountValues  Account field apiName -> value
 * @returns {object} proposing field apiName -> current value
 */
function accountValuesToProposedDraft(sections, accountValues = {}) {
    const draft = {};
    (sections || []).forEach((section) => {
        (section.fields || []).forEach((field) => {
            const source = field.originalAccountField;
            if (!source || draft[field.fieldPath] !== undefined) {
                return;
            }
            const value = accountValues[source];
            if (value !== undefined && value !== null) {
                draft[field.fieldPath] = value;
            }
        });
    });
    return draft;
}

/**
 * Keep only the currently-visible fields (Shown WHERE passes against the draft) and map each to the
 * shape envelopeFieldControl expects, seeding the value from the draft, then any field default, then
 * the type-appropriate empty value. Shared by the action interview and any other metadata-driven form.
 *
 * One field can be configured more than once for a type, each row visible under a different
 * condition. Those conditions are meant to be mutually exclusive, so at most one row should survive
 * the filter — but nothing enforces that, and two survivors would render the same question twice
 * under one key. The first visible one wins, matching how the schema builder resolves a tie.
 * @param {Array} fields  raw Envelope_Field__mdt field shapes
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @returns {Array} shaped, visible fields
 */
function shapeVisibleFields(fields, draft = {}, userContext = {}) {
    const seen = new Set();
    return (fields || [])
        .filter((field) => evaluateWhereStatement(field.shownWhereStatement, draft, userContext))
        .filter((field) => {
            if (seen.has(field.fieldPath)) {
                return false;
            }
            seen.add(field.fieldPath);
            return true;
        })
        .map((field) => {
            const apiName = field.fieldPath;
            return {
                key: apiName,
                apiName,
                fieldPath: apiName,
                objectApiName: field.objectApiName || null,
                // Target SObject for this field. A mixed interview type maps some fields onto a
                // related object (e.g. Case) rather than the primary record; the shell routes each
                // field's persistence by this. Null means the primary record.
                object: field.objectApiName || null,
                label: field.label,
                type: field.type,
                // Object a lookup points at. Kept even after an option source has re-typed the
                // field as a picklist, so it stays visible that the stored value is a record id.
                referenceTo: field.referenceTo || null,
                inputType: inputTypeFor(apiName, field.inputType),
                // Effective requiredness: a Required WHERE statement is evaluated against the draft
                // (so a field can be required only under certain answers); otherwise the static flag.
                required: field.requiredWhereStatement
                    ? evaluateWhereStatement(field.requiredWhereStatement, draft, userContext)
                    : !!field.required,
                maxLength: field.maxLength,
                maxSelections: field.maxSelections,
                scale: field.scale,
                precision: field.precision,
                format: field.format || null,
                pattern: field.pattern || null,
                patternError: field.patternError || null,
                minValue: field.minValue || null,
                maxValue: field.maxValue || null,
                addRecord: field.addRecord || false,
                addRecordType: field.addRecordType || null,
                keyDecision: field.keyDecision || false,
                picklistOptions: optionsFor(apiName, field.picklistOptions || [], draft),
                shownWhereStatement: field.shownWhereStatement || null,
                value: draft[apiName] ?? field.value ?? emptyValueForField(field)
            };
        });
}

/**
 * Clear the answers a change has just hidden: reset every field whose Shown WHERE no longer passes
 * but which still holds a value, so a rebuilt branch of a form doesn't save answers to questions it
 * has stopped asking. Runs until the set settles, since clearing a field can hide the fields that
 * depended on it in turn.
 *
 * Fields are reset to their type-appropriate empty value rather than dropped from the draft: a save
 * that merges (rather than replaces) the stored values only sees the keys the draft still carries, so
 * a removed key would silently keep its previously persisted answer.
 * @param {Array} fields  raw Envelope_Field__mdt field shapes the draft spans
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @returns {object} a new draft with the hidden fields cleared
 */
function clearHiddenAnswers(fields, draft = {}, userContext = {}) {
    const all = fields || [];
    const next = { ...draft };
    let cleared = true;

    while (cleared) {
        cleared = false;
        // One question can be configured as several rows sharing a field path, each asked under a
        // different condition. Such a question is only hidden when none of its rows is showing, so
        // visibility is resolved per path before anything is cleared — otherwise the row that happens
        // to be hidden would wipe the answer the visible one is collecting. Recomputed every pass,
        // since clearing one answer can change what the rest of the form asks.
        const visiblePaths = new Set();
        for (const field of all) {
            if (evaluateWhereStatement(field.shownWhereStatement, next, userContext)) {
                visiblePaths.add(field.fieldPath);
            }
        }
        for (const field of all) {
            const apiName = field.fieldPath;
            // The effective value, seeded the same way shapeVisibleFields seeds it — a draft the user
            // has not touched yet still displays (and would still save) the field's own value.
            const value = next[apiName] ?? field.value;
            if (isEmptyValue(value) || visiblePaths.has(apiName)) {
                continue;
            }
            next[apiName] = emptyValueForField(field);
            cleared = true;
        }
    }

    return next;
}

/**
 * Whether `apiName` already carries a real answer in the draft — the trigger for the Key Point
 * confirmation.
 *
 * A first answer has nothing behind it to confirm. A change to an already-answered Key Point does,
 * because the questions ahead of it are about to be rebuilt either way — regardless of whether this
 * particular candidate answer happens to clear anything that is filled in right now. Keyed on the
 * draft alone, so it reads the same whether the draft came from a brand-new record or a reloaded one:
 * either way, "no prior answer" means the same thing, and "already answered" does too.
 * @param {object} draft  field apiName -> value
 * @param {string} apiName  the field being re-answered
 * @returns {boolean}
 */
function hasPriorAnswer(draft = {}, apiName) {
    return !isEmptyValue(draft[apiName]);
}

/**
 * Whether re-answering `apiName` with `nextValue` would wipe an answer the user has already given.
 *
 * The fields a change hides are reset by clearHiddenAnswers, so apply the candidate value and compare
 * what comes back against what the draft holds. The changed field itself is excluded — replacing its
 * own answer is the edit, not a loss.
 *
 * This gates the Key Point confirmation, whose whole subject is the answers a rebuilt branch
 * discards. A change that only reveals questions loses nothing and must not interrupt: a first
 * answer, another option ticked on a multi-select, or a Key Point no other field's Shown WHERE
 * depends on.
 * @param {Array} fields  raw Envelope_Field__mdt field shapes the draft spans
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @param {string} apiName  the field being re-answered
 * @param {*} nextValue  the candidate answer
 * @returns {boolean}
 */
function changeClearsAnswers(fields, draft = {}, userContext = {}, apiName, nextValue) {
    const next = { ...draft, [apiName]: nextValue };
    const cleared = clearHiddenAnswers(fields, next, userContext);
    return Object.keys(next).some(
        (key) => key !== apiName && !isEmptyValue(next[key]) && isEmptyValue(cleared[key])
    );
}

/**
 * Digits of a raw input, with separator-backspace handling: when the user deletes a mask separator
 * (a dash or paren the mask inserted), the digit count is unchanged but the string got shorter —
 * without dropping the trailing digit too, re-masking instantly re-inserts the separator and the
 * cursor feels stuck.
 */
function maskDigits(rawValue, previousValue, cap) {
    let digits = String(rawValue).replace(/\D+/g, '');
    const previousDigits = String(previousValue ?? '').replace(/\D+/g, '');
    if (
        String(rawValue).length < String(previousValue ?? '').length &&
        digits === previousDigits &&
        digits.length
    ) {
        digits = digits.slice(0, -1);
    }
    return digits.slice(0, cap);
}

// Progressive grouping: '123456789' with [3,2,4] and '-' → '123-45-6789'; '1234' → '123-4'.
function joinDigitGroups(digits, groups, separator) {
    if (!digits) {
        return '';
    }
    const parts = [];
    let index = 0;
    for (const size of groups) {
        if (index >= digits.length) {
            break;
        }
        parts.push(digits.slice(index, index + size));
        index += size;
    }
    return parts.join(separator);
}

/**
 * Input mask for a named Format__c: what the user's keystrokes are allowed to become. Letters never
 * survive in a zip/SSN/phone; digits auto-format progressively as they are typed. 'SSN or EIN'
 * deliberately does NOT auto-dash — the dash position is ambiguous until TIN_or_SSN__c is chosen,
 * so it only restricts the character set; the blur error reports the final shape.
 * @param {string} format  Envelope_Field__mdt.Format__c value
 * @param {*} rawValue  what the input currently holds
 * @param {*} previousValue  the field's last committed value (separator-backspace detection)
 * @returns {string} the masked value (rawValue untouched for unknown formats)
 */
function applyInputMask(format, rawValue, previousValue) {
    if (rawValue === null || rawValue === undefined) {
        return rawValue;
    }
    switch (format) {
        case 'SSN':
            return joinDigitGroups(maskDigits(rawValue, previousValue, 9), [3, 2, 4], '-');
        case 'EIN':
            return joinDigitGroups(maskDigits(rawValue, previousValue, 9), [2, 7], '-');
        case 'US ZIP':
            return joinDigitGroups(maskDigits(rawValue, previousValue, 9), [5, 4], '-');
        case 'SSN or EIN':
            return String(rawValue).replace(/[^0-9-]+/g, '').slice(0, 11);
        case 'US Phone': {
            let digits = maskDigits(rawValue, previousValue, 11);
            if (digits.length === 11 && digits.startsWith('1')) {
                digits = digits.slice(1);
            }
            digits = digits.slice(0, 10);
            if (digits.length <= 3) {
                return digits;
            }
            if (digits.length <= 6) {
                return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
            }
            return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
        }
        default:
            return rawValue;
    }
}

// Field types whose control carries the format rules, mirroring envelopeFieldControl: Pattern__c
// binds only on the text-family inputs, Min__c/Max__c only on the number and date inputs. A rule
// configured on any other type is not enforced by the control, so it must not be enforced here
// either — it would mark a field outstanding with no error the user can see or fix. A field shape
// with no `type` at all is checked unconditionally.
const PATTERN_TYPES = new Set(['STRING', 'EMAIL', 'PHONE', 'URL']);
const BOUNDED_TYPES = new Set(['DOUBLE', 'INTEGER', 'CURRENCY', 'PERCENT', 'DATE']);

/**
 * Client-side mirror of a field's format/bounds rules: the value passes when it fully matches
 * Pattern__c and sits inside Min__c/Max__c, each applied only to the types whose control enforces
 * it. Blank values always pass — requiredness is a separate concern, and partial drafts must stay
 * saveable. Gates record-write payloads and, through isFieldOutstanding, completion status.
 * @param {object} shapedField  output of shapeVisibleFields (pattern/minValue/maxValue populated)
 * @param {*} value  candidate value; defaults to the shaped field's own value
 * @returns {boolean}
 */
function isFormatValid(shapedField, value = shapedField?.value) {
    if (!shapedField || isEmptyValue(value)) {
        return true;
    }
    const { minValue, maxValue, type } = shapedField;
    if (shapedField.pattern && (!type || PATTERN_TYPES.has(type))) {
        let matches = true;
        try {
            matches = new RegExp(`^(?:${shapedField.pattern})$`).test(String(value));
        } catch {
            // A malformed configured regex must not brick saving; treat it as no rule.
        }
        if (!matches) {
            return false;
        }
    }
    if ((minValue || maxValue) && (!type || BOUNDED_TYPES.has(type))) {
        if (type === 'DATE') {
            // ISO date strings compare correctly as strings; Date-parsing shifts days across zones.
            const candidate = String(value);
            if (minValue && candidate < minValue) {
                return false;
            }
            if (maxValue && candidate > maxValue) {
                return false;
            }
        } else {
            const amount = Number(value);
            if (Number.isFinite(amount)) {
                if (minValue && amount < Number(minValue)) {
                    return false;
                }
                if (maxValue && amount > Number(maxValue)) {
                    return false;
                }
            }
        }
    }
    return true;
}

/**
 * Whether a field still owes input: a required field left blank, or any field holding a value that
 * violates its configured format rule. The single test behind every completion measure, so a
 * section's indicator, an action's badge and the missing-inputs count can never disagree — a value
 * the control rejects must not read as complete. A blank field is never reported through the
 * control; it shows only through the section's own status.
 * @param {object} shapedField  entry from shapeVisibleFields
 * @returns {boolean}
 */
function isFieldOutstanding(shapedField) {
    return (
        (shapedField.required && isEmptyValue(shapedField.value)) ||
        !isFormatValid(shapedField)
    );
}

/**
 * Completion status for a set of shaped fields: 'incomplete' while any field still owes input (see
 * isFieldOutstanding), otherwise 'complete'. Drives the Table-of-Contents progress indicator and the
 * section header's "Inputs missing" status.
 * @param {Array} shapedFields  output of shapeVisibleFields
 * @returns {'incomplete'|'complete'}
 */
function sectionStatus(shapedFields) {
    return (shapedFields || []).some(isFieldOutstanding) ? 'incomplete' : 'complete';
}

/**
 * Whether a field's current value still means what the baseline holds.
 *
 * draftValuesEqual settles everything but numbers, where it errs toward "changed" — the right call
 * for an echo guard, where the cost is one extra draft write. Here the cost is a marker left on a
 * field the request no longer changes: a number input reports its value as text ('500000') while
 * the baseline arrives typed (500000), so undoing an edit would clear the stored proposal while the
 * marker stayed. Numbers are therefore compared numerically, the same way the save path does.
 *
 * Only strings and numbers take that second pass, so a blank, a boolean or a list can never be
 * coerced into matching a zero.
 * @param {*} value
 * @param {*} baseline
 * @returns {boolean}
 */
function sameAsBaseline(value, baseline) {
    if (draftValuesEqual(value, baseline)) {
        return true;
    }
    const isNumericLike = (candidate) =>
        typeof candidate === 'number' ||
        (typeof candidate === 'string' && candidate.trim() !== '');
    if (!isNumericLike(value) || !isNumericLike(baseline)) {
        return false;
    }
    const left = Number(value);
    const right = Number(baseline);
    return Number.isFinite(left) && Number.isFinite(right) && left === right;
}

/**
 * Tag each shaped field with whether the interview has moved it off the value it started from,
 * which is what an action item's "Updated" markers render from.
 *
 * The baseline is the record's current values as of the last load, so a marker means the
 * interview has moved a field off what the record holds now, and it clears again if the record
 * catches up to the proposal. A field the baseline says nothing about is not part of the tracked
 * set and is never marked — which is different from one it holds as blank, where filling the
 * field in is a genuine change.
 *
 * A null baseline leaves the fields exactly as they came in, so an interview with nothing to
 * compare against renders no markers at all.
 * @param {Array} shapedFields  output of shapeVisibleFields
 * @param {object|null} baseline  field apiName -> value the request started from
 * @returns {Array} the shaped fields, each carrying an `updated` flag
 */
function markUpdatedFields(shapedFields, baseline) {
    if (!baseline) {
        return shapedFields || [];
    }
    return (shapedFields || []).map((field) => ({
        ...field,
        updated:
            Object.hasOwn(baseline, field.apiName) &&
            !sameAsBaseline(field.value, baseline[field.apiName])
    }));
}

/**
 * The related-party subsections an entity's form must show, in render order: every rule configured
 * for the entity whose condition passes against the current draft. Takes the same entity shape as
 * resolveSchemaKey. Household members resolve their rules from the member type token; Financial
 * Accounts, which carry no type token, resolve theirs from the registration selected in the draft.
 * Returns [] for an entity with no configured parties, so the caller renders no section at all.
 * @param {{groupId: string, type?: string}} entity
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {Array<{key: string, title: string, type?: string, types?: Array<string>, faRole?: string, min: number, max?: number, group?: string}>}
 */
function resolveRelatedPartyRequirements(
    entity,
    draft = {},
    registrationAttributes = {}
) {
    if (!entity) {
        return [];
    }

    let rules = [];
    if (entity.groupId === 'householdMembers') {
        rules = RELATED_PARTY_RULES[entity.type] || [];
    } else if (ACCOUNT_GROUP_IDS.has(entity.groupId)) {
        rules = accountRulesFor(entity, draft, registrationAttributes);
    } else if (entity.groupId === SERVICE_GROUP_ID) {
        rules = serviceRulesFor(entity, draft);
    }

    return rules
        .filter((rule) => evaluateWhereStatement(rule.whereStatement, draft))
        .map((rule) => ({
            key: rule.key,
            title: rule.title,
            type: rule.type,
            types: rule.types,
            faRole: rule.faRole,
            // The Service__c lookup a service agreement's owner slot persists into. Undefined on
            // every other rule table, which serviceOwnerFieldForKey reads as "not a service".
            serviceField: rule.serviceField,
            min: rule.min,
            max: rule.max,
            group: rule.group,
            // Slots that must name distinct entities (a joint account's owners, a service
            // agreement's two owners). Absent on rules where one person may fill sibling slots.
            exclusiveWith: rule.exclusiveWith,
            // Carried through so a role that can be satisfied by affirmation still says so to the
            // section body and to waivedRelatedPartyKeys. This projection is deliberately explicit,
            // so anything not named here is dropped.
            waiver: rule.waiver
        }));
}

/**
 * Build the `$party` evaluation context for one action from its selected related parties and a
 * person-attribute lookup, keyed by requirementKey (rule.key) so a metadata WHERE can read
 * `$Party.<roleKey>.<Field>`. Feeds the reserved `$party` slot of the context bag threaded into
 * evaluateWhereStatement / shapeVisibleFields.
 *
 * A role with several people selected uses the first occupant; a rule that needs "any of them" should
 * instead store the slot's people as an array and test membership with LIKE (see valueMatchesLike).
 * A role whose person has no attribute row is omitted, so the token resolves undefined — the same
 * fail-open the grammar already gives an unselected party.
 * @param {object} relatedParties  action.formData[RELATED_PARTIES_FIELD_KEY]: roleKey -> [{ id, ... }]
 * @param {object} attributesById  person Account Id -> { field: value } stored on the person
 * @returns {object} roleKey -> { field: value }
 */
function derivePartyContext(relatedParties = {}, attributesById = {}) {
    const out = {};
    Object.keys(relatedParties || {}).forEach((roleKey) => {
        const first = (relatedParties[roleKey] || [])[0];
        const attributes = first && attributesById && attributesById[first.id];
        if (attributes) {
            out[roleKey] = attributes;
        }
    });
    return out;
}

/**
 * The raw account rules a Financial Account's selected registration resolves to, unfiltered by
 * condition. The single place the registration is turned into a rule set, so the fragile
 * Registration_Type__c ↔ MasterLabel join is expressed once. Returns [] for a non-account entity.
 * @param {{groupId: string}} entity
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {Array<object>}
 */
function accountRulesFor(entity, draft = {}, registrationAttributes = {}) {
    if (!ACCOUNT_GROUP_IDS.has(entity?.groupId)) {
        return [];
    }
    const attributes = resolveRegistrationAttributes(
        registrationAttributes,
        draft[REGISTRATION_TYPE_FIELD]
    );
    return ACCOUNT_RELATED_PARTY_RULES[resolveRegistrationGroup(attributes)] || [];
}

/**
 * The raw owner rules a Service Agreement's selected service type resolves to, unfiltered by
 * condition. The single place Service__c.Type__c is turned into a rule set, so the type-to-slots
 * join is expressed once. Returns [] for a non-service entity, and for a service whose type is not
 * yet answered — the section is absent until the interview's first question has a value.
 * @param {{groupId: string}} entity
 * @param {object} draft  field apiName -> value
 * @returns {Array<object>}
 */
function serviceRulesFor(entity, draft = {}) {
    if (entity?.groupId !== SERVICE_GROUP_ID) {
        return [];
    }
    return SERVICE_RELATED_PARTY_RULES[draft[SERVICE_TYPE_FIELD]] || [];
}

/**
 * The Service__c lookup field a service agreement's owner slot persists into — the service-side
 * counterpart of accountRoleForKey and aarRoleForKey. Null for a slot with no configured field, and
 * for a requirement on anything that is not a Service Agreement.
 * @param {{groupId: string}} entity
 * @param {string} requirementKey
 * @param {object} draft  field apiName -> value
 * @returns {string|null}
 */
function serviceOwnerFieldForKey(entity, requirementKey, draft = {}) {
    const rule = serviceRulesFor(entity, draft).find(
        (entry) => entry.key === requirementKey
    );
    return rule ? rule.serviceField || null : null;
}

/**
 * The owner slot a Service__c lookup field belongs to — the inverse of serviceOwnerFieldForKey,
 * used to group the persisted lookups back under the requirement that owns them when the section is
 * rebuilt from the record. Independent of the service type because both types share one slot list
 * and each field appears in exactly one slot. Null for a field no slot claims.
 * @param {string} fieldApiName  a Service__c field API name
 * @returns {string|null}
 */
function serviceOwnerKeyForField(fieldApiName) {
    const rule = SERVICE_OWNER_RULES.find(
        (entry) => entry.serviceField === fieldApiName
    );
    return rule ? rule.key : null;
}

/**
 * Every Service__c lookup the wizard owns for a service agreement's owner slots. This is the
 * reconcile scope: it is what the server is told it may clear, so a lookup outside it is never
 * touched. Independent of the service type, for the same reason as serviceOwnerKeyForField.
 * @returns {Array<string>}
 */
function managedServiceOwnerFields() {
    return SERVICE_OWNER_RULES.map((rule) => rule.serviceField).filter(Boolean);
}

/**
 * The Financial_Account_Role__c Role value an account's ownership slot persists as — the
 * account-side counterpart of aarRoleForKey. Null for a slot with no configured role, and for a
 * requirement on anything that is not a Financial Account.
 * @param {{groupId: string}} entity
 * @param {string} requirementKey
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {string|null}
 */
function accountRoleForKey(
    entity,
    requirementKey,
    draft = {},
    registrationAttributes = {}
) {
    const rule = accountRulesFor(entity, draft, registrationAttributes).find(
        (entry) => entry.key === requirementKey
    );
    return rule ? rule.faRole || null : null;
}

/**
 * The distinct Financial_Account_Role__c roles the wizard owns for an account's registration. This
 * is the reconcile scope: a role row outside it (a Custodian, a Trusted Contact, or a role belonging
 * to a different registration) is never removed. Empty for a non-account entity.
 * @param {{groupId: string}} entity
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {Array<string>}
 */
function managedAccountRolesFor(
    entity,
    draft = {},
    registrationAttributes = {}
) {
    const roles = accountRulesFor(entity, draft, registrationAttributes)
        .map((rule) => rule.faRole)
        .filter(Boolean);
    return [...new Set(roles)];
}

/**
 * The ownership slot a Financial_Account_Role__c role belongs to — the inverse of accountRoleForKey,
 * used to group persisted role rows back under the requirement that owns them. More than one slot
 * may share a role, so each candidate's own condition is evaluated against the draft; when none
 * matches the first candidate is returned, so the party is kept rather than reconciled away. Null
 * for a role the registration has no slot for (a row created outside the wizard).
 * @param {{groupId: string}} entity
 * @param {string} role  Financial_Account_Role__c Role value
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {string|null}
 */
function requirementKeyForAccountRole(
    entity,
    role,
    draft = {},
    registrationAttributes = {}
) {
    const candidates = accountRulesFor(
        entity,
        draft,
        registrationAttributes
    ).filter((rule) => rule.faRole === role);
    if (!candidates.length) {
        return null;
    }
    const match = candidates.find((rule) =>
        evaluateWhereStatement(rule.whereStatement, draft)
    );
    return (match || candidates[0]).key;
}

/**
 * The most rows each of an account's managed roles may hold, as role -> max. Sent to the server as
 * the backstop for a client path that does not check a ceiling itself (Review Missing Items has
 * none). A slot with no max is unbounded and is left out, which the server reads as no limit. Roles
 * sharing a value take the highest ceiling, since one role can serve more than one slot.
 * @param {{groupId: string}} entity
 * @param {object} draft  field apiName -> value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {object}  role -> max
 */
function accountRoleLimits(entity, draft = {}, registrationAttributes = {}) {
    return accountRulesFor(entity, draft, registrationAttributes).reduce(
        (limits, rule) => {
            if (!rule.faRole || typeof rule.max !== 'number') {
                return limits;
            }
            const held = limits[rule.faRole];
            return {
                ...limits,
                [rule.faRole]:
                    typeof held === 'number' ? Math.max(held, rule.max) : rule.max
            };
        },
        {}
    );
}

/**
 * The Account_Account_Relationship__c Role value a member's related-party requirement persists as.
 * Null for a requirement with no configured role — the Financial Account rules, whose owner and
 * beneficiary slots are account-ownership requirements rather than person roles on an entity.
 * @param {string} memberType  the outline's raw member type token ('client' | 'business' | 'trust')
 * @param {string} requirementKey
 * @returns {string|null}
 */
function aarRoleForKey(memberType, requirementKey) {
    const rule = (RELATED_PARTY_RULES[memberType] || []).find(
        (entry) => entry.key === requirementKey
    );
    return rule ? rule.aarRole || null : null;
}

/**
 * The distinct relationship roles the wizard owns for a member type. This is the reconcile scope: a
 * relationship carrying any other role belongs to something else and is never touched. Empty for a
 * member type with no related parties.
 * @param {string} memberType
 * @returns {Array<string>}
 */
function managedAarRolesFor(memberType) {
    const roles = (RELATED_PARTY_RULES[memberType] || [])
        .map((rule) => rule.aarRole)
        .filter(Boolean);
    return [...new Set(roles)];
}

/**
 * The requirement a relationship role belongs to — the inverse of aarRoleForKey. More than one
 * requirement may share a role, so each candidate rule's own condition is evaluated against the
 * draft to pick the one that applies; when no condition matches, the first candidate is returned so
 * the party is kept rather than reconciled away. Null for a role the entity has no requirement for
 * (a relationship created outside the wizard).
 * @param {{groupId?: string, type?: string}} entity
 * @param {string} role  Account_Account_Relationship__c Role value
 * @param {object} draft  field apiName -> value
 * @returns {string|null}
 */
function requirementKeyForAarRole(entity, role, draft = {}) {
    const candidates = (RELATED_PARTY_RULES[entity?.type] || []).filter(
        (rule) => rule.aarRole === role
    );
    if (!candidates.length) {
        return null;
    }
    const match = candidates.find((rule) =>
        evaluateWhereStatement(rule.whereStatement, draft)
    );
    return (match || candidates[0]).key;
}

/**
 * The display label a member presented as a related-party role carries, taken from the requirement's
 * own title so the outline row and the interview's subsection read the same. Null for a key that is
 * not a presented role, which callers read as "present this member as itself".
 * @param {string} requirementKey
 * @returns {string|null}
 */
function partyRoleLabel(requirementKey) {
    if (!ROLE_PRESENTED_KEYS.has(requirementKey)) {
        return null;
    }
    return PARTY_RULE_BY_KEY[requirementKey]?.title || null;
}

/**
 * The member type token a related-party slot creates its new members as, from the record types the
 * slot accepts. Every member-held role is held by a person, but an account's owner mirrors its
 * registration — a business account's owner is the Business entity, a trust account's the Trust — so
 * a slot cannot assume 'client'. Resolved from the slot's first accepted type by inverting
 * MEMBER_TYPE_TO_MDT, and defaults to 'client' for a slot with no types or an unmapped one.
 * @param {Array<string>} types  accepted record types, in the MEMBER_TYPE_TO_MDT vocabulary
 * @returns {string}  member type token saveEntity accepts
 */
function memberTypeForPartyTypes(types) {
    const accepted = (types || [])[0];
    if (!accepted) {
        return 'client';
    }
    const match = Object.keys(MEMBER_TYPE_TO_MDT).find(
        (memberType) =>
            SAVEABLE_MEMBER_TYPES.has(memberType) &&
            MEMBER_TYPE_TO_MDT[memberType] === accepted
    );
    return match || 'client';
}

/**
 * The entity types a slot accepts, as create-dialog options — { label, value } with the value being
 * the member type token saveEntity persists under. memberTypeForPartyTypes reads only the first
 * accepted type, which is all a single-type slot needs; a slot accepting several (a service
 * agreement's owner, which may be an Individual, a Business or a Trust) has to let the user say
 * which one they are creating, and this is the list they choose from.
 *
 * Labels match the Add Member card's own options so the same entity is named the same way wherever
 * it is created. A type with no saveable member token is dropped — nothing could create it.
 * @param {Array<string>} types  Envelope_Field__mdt Type__c values the slot accepts
 * @returns {Array<{label: string, value: string}>}
 */
function partyTypeChoices(types) {
    return (types || [])
        .map((accepted) =>
            Object.keys(MEMBER_TYPE_TO_MDT).find(
                (memberType) =>
                    SAVEABLE_MEMBER_TYPES.has(memberType) &&
                    MEMBER_TYPE_TO_MDT[memberType] === accepted
            )
        )
        .filter(Boolean)
        .map((memberType) => ({
            label: MEMBER_TYPE_LABELS[memberType] || memberType,
            value: memberType
        }));
}

/**
 * The member type an entity's Account record persists under — the value saveEntity accepts in the
 * RecordTypeId key, which it resolves to a real record type. The household member types persist as
 * themselves; a member presented as a related-party role is a person Account and so persists as a
 * client. Null for a type with no record-type mapping, which callers read as "this member cannot be
 * persisted".
 * @param {string} memberType  the outline's raw member type token
 * @returns {string|null}
 */
function persistedMemberTypeFor(memberType) {
    if (SAVEABLE_MEMBER_TYPES.has(memberType)) {
        return memberType;
    }
    return PARTY_RULE_BY_KEY[memberType] ? 'client' : null;
}

/**
 * The related-party roles each person Account plays across a set of household members: account id ->
 * requirement keys, in a stable order (members as given, and within a member the configured rule
 * order). Two sources are read and merged, so a role is recognized as early as possible:
 *   1. each business/trust member's own held Related Parties value, which already carries the
 *      requirement key — this covers a party restored from the saved envelope state and one just
 *      added, before any relationship record exists;
 *   2. the persisted relationship rows, whose Role value maps back to a requirement through the
 *      parent's own draft (see requirementKeyForAarRole).
 * Only the roles a member may be presented as are returned, and only for members that actually carry
 * related parties — a Financial Account's owner/beneficiary slots are account-ownership requirements
 * rather than person roles and never appear here.
 * @param {Array<{id: string, type?: string, actions?: Array<{formData?: object}>}>} members
 * @param {Array<{entityAccountId: string, relatedAccountId: string, role: string}>} rows
 * @returns {object}  account id -> Array<string>
 */
function derivePartyRoles(members, rows) {
    const roles = {};
    const add = (accountId, requirementKey) => {
        if (!accountId || !partyRoleLabel(requirementKey)) {
            return;
        }
        const held = roles[accountId] || [];
        if (!held.includes(requirementKey)) {
            roles[accountId] = [...held, requirementKey];
        }
    };
    const rowsByEntity = new Map();
    (rows || []).forEach((row) => {
        rowsByEntity.set(row.entityAccountId, [
            ...(rowsByEntity.get(row.entityAccountId) || []),
            row
        ]);
    });
    (members || [])
        .filter((member) => RELATED_PARTY_MEMBER_TYPES.has(member?.type))
        .forEach((member) => {
            (member.actions || []).forEach((action) => {
                const held = action.formData?.[RELATED_PARTIES_FIELD_KEY] || {};
                // Rule order rather than the value's own key order, so the role that drives the
                // schema is the configured first one however the value was assembled.
                RELATED_PARTY_RULES[member.type].forEach((rule) => {
                    (held[rule.key] || []).forEach((party) =>
                        add(party?.id, rule.key)
                    );
                });
            });
            // The parent's draft resolves the requirements that share one role; the first action is
            // the member's own interview, and any later one carries the same parent fields.
            const draft = (member.actions || [])[0]?.formData || {};
            (rowsByEntity.get(member.id) || []).forEach((row) => {
                add(
                    row.relatedAccountId,
                    requirementKeyForAarRole(member, row.role, draft)
                );
            });
        });
    return roles;
}

/**
 * Temporary ids for `count` parties being added to `parties`, continuing past the highest sequence
 * already in use. The dialogs are recreated every time they open, so a counter starting from zero
 * could hand out an id a party restored from the saved envelope state already carries.
 * @param {Array<{id: string}>} parties  the parties already held
 * @param {number} count
 * @returns {Array<string>}
 */
function pendingPartyIds(parties, count) {
    const used = (parties || []).map((party) => {
        const match = PENDING_PARTY_ID.exec(party?.id || '');
        return match ? Number(match[1]) : 0;
    });
    const start = Math.max(0, ...used) + 1;
    return Array.from(
        { length: count },
        (_, index) => `${PENDING_PARTY_ID_PREFIX}${start + index}`
    );
}

/**
 * The requirements still owed, in the order given: those holding fewer parties than their minimum.
 * Requirements sharing a `group` are owed together — their parties pool against the group's highest
 * minimum — so either every role of a short group is returned or none of them is. The single
 * measure of "unmet" behind both the missing-parties count and the Review screen's requirement
 * blocks, so the badge and the blocks can never disagree.
 * @param {Array<{key: string, min: number, group?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {object} value  requirement key -> parties
 * @returns {Array<object>}  the requirement objects still owed
 */
function unmetRelatedPartyRequirements(requirements, value = {}, waived = null) {
    const waivedKeys = waived instanceof Set ? waived : new Set(waived || []);
    const held = (key) => ((value || {})[key] || []).length;
    const groupTotals = new Map();
    // A waived role satisfies the whole group it shares a minimum with, the same way a party added
    // to any one of them does.
    const waivedGroups = new Set();
    (requirements || []).forEach((requirement) => {
        if (!requirement.group) {
            return;
        }
        if (waivedKeys.has(requirement.key)) {
            waivedGroups.add(requirement.group);
        }
        const running = groupTotals.get(requirement.group) || { held: 0, min: 0 };
        groupTotals.set(requirement.group, {
            held: running.held + held(requirement.key),
            min: Math.max(running.min, requirement.min)
        });
    });
    return (requirements || []).filter((requirement) => {
        if (waivedKeys.has(requirement.key)) {
            return false;
        }
        if (!requirement.group) {
            return held(requirement.key) < requirement.min;
        }
        if (waivedGroups.has(requirement.group)) {
            return false;
        }
        const total = groupTotals.get(requirement.group);
        return total.held < total.min;
    });
}

/**
 * The requirement keys a draft has waived: those whose `waiver.field` the draft answers true.
 * Keeps the storage detail in one place, so a caller passes a draft rather than knowing which field
 * stands in for which role. String 'true' is accepted because a checkbox answer that has been
 * through a round trip can arrive as text.
 * @param {Array<{key: string, waiver?: {field: string}}>} requirements  output of resolveRelatedPartyRequirements
 * @param {object} draft  field apiName -> value
 * @returns {Set<string>}  the requirement keys treated as met
 */
function waivedRelatedPartyKeys(requirements, draft = {}) {
    const waived = new Set();
    (requirements || []).forEach((requirement) => {
        const field = requirement.waiver?.field;
        if (!field) {
            return;
        }
        const answer = (draft || {})[field];
        if (answer === true || answer === 'true') {
            waived.add(requirement.key);
        }
    });
    return waived;
}

/**
 * How many related-party requirements an entity has not met yet. Counted alongside countMissingInputs
 * so an action's badge reflects both the metadata fields and the parties still to be added. A group
 * of roles sharing one minimum counts once however many roles it spans — a retirement plan owing a
 * fiduciary is one missing input, not one per role it could be satisfied with.
 * @param {Array<{key: string, min: number, group?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {object} value  requirement key -> parties
 * @returns {number}
 */
function countMissingRelatedParties(requirements, value = {}, waived = null) {
    const unmet = unmetRelatedPartyRequirements(requirements, value, waived);
    const groups = new Set(
        unmet.map((requirement) => requirement.group).filter(Boolean)
    );
    return unmet.filter((requirement) => !requirement.group).length + groups.size;
}

/**
 * The party ids held by the slots a requirement must name a distinct entity from — the siblings
 * sharing its `exclusiveWith` token, itself excluded. Empty for a requirement carrying no token, so
 * a caller can splice this into an exclusion list unconditionally and the account and member rules
 * keep their existing behavior (where one person may fill sibling slots).
 * @param {Array<{key: string, exclusiveWith?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {string} requirementKey
 * @param {object} value  requirement key -> parties
 * @returns {Array<string>}
 */
function exclusivePartyIds(requirements, requirementKey, value = {}) {
    const requirement = (requirements || []).find(
        (entry) => entry.key === requirementKey
    );
    if (!requirement || !requirement.exclusiveWith) {
        return [];
    }
    return (requirements || [])
        .filter(
            (entry) =>
                entry.exclusiveWith === requirement.exclusiveWith &&
                entry.key !== requirement.key
        )
        .flatMap((entry) => (value || {})[entry.key] || [])
        .map((party) => party.id)
        .filter(Boolean);
}

/**
 * A requirement together with the peers it shares a minimum with, in the order given — itself alone
 * when it stands on its own. Lets a caller judge one role's status without losing the either/or
 * relationship, which a single-requirement slice would silently drop.
 * @param {Array<{key: string, group?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {string} requirementKey
 * @returns {Array<object>}
 */
function relatedPartyPeers(requirements, requirementKey) {
    const requirement = (requirements || []).find(
        (entry) => entry.key === requirementKey
    );
    if (!requirement) {
        return [];
    }
    if (!requirement.group) {
        return [requirement];
    }
    return requirements.filter((entry) => entry.group === requirement.group);
}

/**
 * A related-party role's title as a noun phrase — 'Authorized Person' → 'an authorized person' — so
 * a prompt can name the role inside a sentence.
 * @param {string} title  a requirement's title
 * @returns {string}
 */
function partyNounPhrase(title) {
    const noun = String(title || 'related party').toLowerCase();
    return `${'aeiou'.includes(noun.charAt(0)) ? 'an' : 'a'} ${noun}`;
}

/**
 * The roles that would satisfy a requirement, written as prose: 'a trustee or an authorized person'
 * for one of a shared minimum, and just its own noun phrase for a requirement standing alone. Keeps
 * every surface that has to explain the either/or — the interview's note and the Review screen's
 * empty state — phrasing it the same way.
 * @param {Array<{key: string, title: string, group?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {string} requirementKey
 * @returns {string}
 */
function partyAlternativesLabel(requirements, requirementKey) {
    const nouns = relatedPartyPeers(requirements, requirementKey).map(
        (requirement) => partyNounPhrase(requirement.title)
    );
    if (nouns.length <= 2) {
        return nouns.join(' or ');
    }
    return `${nouns.slice(0, -1).join(', ')} or ${nouns[nouns.length - 1]}`;
}

/**
 * The related-party requirements holding more parties than their maximum. A requirement without a
 * max is unbounded and never counts, so member rules — none of which set one — are unaffected.
 * @param {Array<{key: string, max?: number}>} requirements  output of resolveRelatedPartyRequirements
 * @param {object} value  requirement key -> parties
 * @returns {number}
 */
function countExcessRelatedParties(requirements, value = {}) {
    return (requirements || []).filter(
        (requirement) =>
            typeof requirement.max === 'number' &&
            ((value || {})[requirement.key] || []).length > requirement.max
    ).length;
}

/**
 * Completion status for a Related Parties section: 'incomplete' until every requirement holds at
 * least its minimum number of parties and no more than its maximum. Mirrors sectionStatus, which
 * takes shaped fields and so cannot be reused for a section whose value is party lists.
 *
 * Pass the whole requirement set, or — to judge one role — that role together with its group peers
 * (see relatedPartyPeers): a grouped role sliced out on its own reads as unmet while a peer already
 * satisfies the shared minimum.
 * @param {Array<{key: string, min: number, max?: number, group?: string}>} requirements  output of resolveRelatedPartyRequirements
 * @param {object} value  requirement key -> parties
 * @returns {'incomplete'|'complete'}
 */
function relatedPartiesStatus(requirements, value = {}, waived = null) {
    const unmet =
        countMissingRelatedParties(requirements, value, waived) +
        countExcessRelatedParties(requirements, value);
    return unmet > 0 ? 'incomplete' : 'complete';
}

/**
 * Partition shaped fields into the bound form fields and the add-record controls (synthetic fields
 * that spawn a nested record rather than editing a value). Lets a consumer render the two differently
 * while still counting an unfilled required add-record slot as missing.
 * @param {Array} shapedFields  output of shapeVisibleFields
 * @returns {{formFields: Array, addRecordFields: Array}}
 */
function splitAddRecordFields(shapedFields) {
    const formFields = [];
    const addRecordFields = [];
    (shapedFields || []).forEach((field) => {
        if (field.addRecord) {
            addRecordFields.push(field);
        } else {
            formFields.push(field);
        }
    });
    return { formFields, addRecordFields };
}

/**
 * Count the inputs a schema's sections still owe for a given draft: shapes each section's visible
 * fields against the draft (so both conditional visibility and conditional requiredness apply) and
 * tallies the ones outstanding — required fields left blank plus values that fail their format rule
 * (see isFieldOutstanding). Add-record slots count too — an empty ref list is a blank value. Drives
 * the real "N inputs missing" label.
 * @param {Array<{fields: Array}>} sections  raw schema sections (Envelope_Field__mdt field shapes)
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @returns {number}
 */
function countMissingInputs(sections, draft = {}, userContext = {}) {
    return (sections || []).reduce((total, section) => {
        const shaped = shapeVisibleFields(section.fields, draft, userContext);
        return total + shaped.filter(isFieldOutstanding).length;
    }, 0);
}

/**
 * Whether a field's Shown/Required WHERE statement references a given field API name (word-boundary
 * match, so 'Employer__c' doesn't match 'Employer_City__c').
 * @param {string} statement
 * @param {string} apiName
 * @returns {boolean}
 */
function referencesField(statement, apiName) {
    if (!statement || !apiName) {
        return false;
    }
    return new RegExp(`\\b${apiName}\\b`).test(statement);
}

/**
 * Whether the schema has an unfilled Key Point field whose dependent fields are still hidden — i.e. a
 * visible, empty, required Key Point field that at least one other field's Shown WHERE depends on. Only
 * required Key Points count: an optional one leaves nothing owed, so it must not hold the action open (a
 * required one also reddens its section, keeping this measure and the section status in agreement). When
 * true, the missing-inputs count is a lower bound (answering the Key Point may reveal more required
 * fields), so its label is shown with a trailing '+'.
 * @param {Array<{fields: Array}>} sections  raw schema sections
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @returns {boolean}
 */
function hasUnfilledKeyPointDependents(sections, draft = {}, userContext = {}) {
    const allFields = (sections || []).flatMap((section) => section.fields || []);
    const emptyKeyPointNames = (sections || [])
        .flatMap((section) => shapeVisibleFields(section.fields, draft, userContext))
        .filter((field) => field.keyDecision && field.required && isEmptyValue(field.value) && !isBooleanField(field))
        .map((field) => field.apiName);
    if (emptyKeyPointNames.length === 0) {
        return false;
    }
    return allFields.some((field) =>
        emptyKeyPointNames.some((name) => referencesField(field.shownWhereStatement, name))
    );
}

/**
 * Display form of a missing-inputs count: the number, with a trailing '+' when an unfilled Key
 * Point gates additional unknown fields (see hasUnfilledKeyPointDependents) and the count is
 * therefore a lower bound. Shared so the wizard's focused header and the landing list's Missing
 * Items column render the same figure.
 * @param {number} count
 * @param {boolean} [hasPlus=false]
 * @returns {string}
 */
function missingInputsCountLabel(count, hasPlus = false) {
    return `${count}${hasPlus ? '+' : ''}`;
}

/**
 * Human label for a missing-inputs count: '' when nothing is missing, otherwise 'N input(s) missing',
 * with a trailing '+' when an unfilled Key Point gates additional unknown fields (see
 * hasUnfilledKeyPointDependents).
 * @param {number} count
 * @param {boolean} [hasPlus=false]
 * @returns {string}
 */
function missingInputsLabel(count, hasPlus = false) {
    if (!count) {
        return '';
    }
    return `${missingInputsCountLabel(count, hasPlus)} ${count === 1 ? 'input' : 'inputs'} missing`;
}

/**
 * An action's overall input completion, the single source of truth behind its status badge and
 * "N inputs missing" hint: the missing count spans the metadata fields still owed (blank required
 * ones and values failing their format rule alike) and the related parties, and the action is
 * complete only when that count is zero and no unfilled Key Point gates further unknown fields.
 * Never complete while the schema is absent (still loading).
 * @param {Array<{fields: Array}>} sections  raw schema sections (Envelope_Field__mdt field shapes)
 * @param {{groupId: string, type?: string}} entity  same shape resolveRelatedPartyRequirements takes
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @param {object} registrationAttributes  registration value -> Registration_Type__mdt attributes
 * @returns {{count: number, hasPlus: boolean, isComplete: boolean}}
 */
function actionCompletion(
    sections,
    entity,
    draft = {},
    userContext = {},
    registrationAttributes = {}
) {
    const requirements = resolveRelatedPartyRequirements(
        entity,
        draft,
        registrationAttributes
    );
    const count =
        countMissingInputs(sections, draft, userContext) +
        countMissingRelatedParties(
            requirements,
            draft[RELATED_PARTIES_FIELD_KEY],
            waivedRelatedPartyKeys(requirements, draft)
        );
    const hasPlus = hasUnfilledKeyPointDependents(sections, draft, userContext);
    const isComplete = (sections || []).length > 0 && count === 0 && !hasPlus;
    return { count, hasPlus, isComplete };
}

/**
 * Reduce a schema's sections to the fields an action still owes: visible required fields left
 * blank, visible fields whose value fails its format rule (whether required or not — an invalid
 * value blocks completion either way, so it has to be fixable from here), visible unfilled Key
 * Point fields (kept even when optional, since answering them can reveal further fields), and the
 * hidden fields those unfilled Key Points gate (returned so a consumer that re-filters by Shown
 * WHERE reveals them the moment the Key Point is answered). Fields keep their raw
 * Envelope_Field__mdt shape and schema order; sections left with no fields are dropped. Add-record
 * slots are excluded — they spawn nested records and need the full interview rather than a flat
 * field list.
 * @param {Array<{name: string, fields: Array}>} sections  raw schema sections
 * @param {object} draft  field apiName -> value
 * @param {object} userContext  $User.<Field> -> running-user value
 * @returns {Array<{name: string, fields: Array}>}
 */
function selectMissingSections(sections, draft = {}, userContext = {}) {
    const included = new Set();
    const emptyKeyPointNames = [];
    (sections || []).forEach((section) => {
        shapeVisibleFields(section.fields, draft, userContext).forEach((field) => {
            if (field.addRecord) {
                return;
            }
            const isBlank = isEmptyValue(field.value);
            const isInvalid = !isFormatValid(field);
            if (!isBlank && !isInvalid) {
                return;
            }
            // Only a blank Key Point gates hidden fields; one holding an invalid value is answered,
            // so its dependents already show. A boolean/checkbox Key Point is answered when unchecked
            // (false is a deliberate answer, not a missing one).
            const isKeyDecisionBlank = field.keyDecision && isBlank && !isBooleanField(field);
            if (isKeyDecisionBlank) {
                emptyKeyPointNames.push(field.apiName);
            }
            if (isInvalid || field.required || isKeyDecisionBlank) {
                included.add(field.apiName);
            }
        });
    });
    // Hidden fields gated by an unfilled Key Point are included one level deep; deeper chains
    // surface as the Key Points get answered and are covered by the count's trailing '+'.
    if (emptyKeyPointNames.length) {
        (sections || []).forEach((section) => {
            (section.fields || []).forEach((field) => {
                if (
                    field.addRecord ||
                    included.has(field.fieldPath) ||
                    !(field.required || field.requiredWhereStatement || field.keyDecision) ||
                    evaluateWhereStatement(field.shownWhereStatement, draft, userContext)
                ) {
                    return;
                }
                const gated = emptyKeyPointNames.some((name) =>
                    referencesField(field.shownWhereStatement, name)
                );
                if (gated) {
                    included.add(field.fieldPath);
                }
            });
        });
    }
    return (sections || [])
        .map((section) => ({
            ...section,
            fields: (section.fields || []).filter((field) => included.has(field.fieldPath))
        }))
        .filter((section) => section.fields.length > 0);
}

/**
 * Sum the missing inputs across a set of (entity, formData) pairs — the shared accumulator behind
 * both the wizard's focused-header count and the landing list's Missing Items column. Resolves each
 * entity's schema from the cache and delegates to actionCompletion so the per-action math
 * (outstanding fields + unmet related parties, plus the Key-Point '+') is identical everywhere. An
 * entity whose type has a schema key that hasn't loaded yet is skipped rather than under-counted;
 * a type with no schema key (e.g. an unmapped member) still contributes its related-party
 * requirements against an empty schema.
 * @param {Array<{entity: object, formData: object}>} items
 * @param {{schemaCache?: object, registrationAttributes?: object, userContext?: object}} context
 * @returns {{count: number, hasPlus: boolean}}
 */
function sumMissingInputs(items, context = {}) {
    const {
        schemaCache = {},
        registrationAttributes = {},
        userContext = {},
        // Person Account Id -> stored attributes. When supplied, each item's own selected related
        // parties are folded into a per-item `$party` context so a $Party-gated required field is
        // counted against the people that item actually named, not one global set.
        partyAttributes = null
    } = context;
    let count = 0;
    let hasPlus = false;
    (items || []).forEach(({ entity, formData }) => {
        const key = resolveSchemaKey(entity);
        const rawSchema = key ? schemaCache[schemaCacheKey(key)] : [];
        if (key && !rawSchema) {
            return;
        }
        // After the not-loaded check: the filter passes falsy through, but the count must only
        // ever run against the fields this entity's account type actually shows.
        const schema = key
            ? filterSectionsByAccountType(rawSchema, key.accountType)
            : rawSchema;
        const itemContext = partyAttributes
            ? {
                  ...userContext,
                  $party: derivePartyContext(
                      (formData || {})[RELATED_PARTIES_FIELD_KEY],
                      partyAttributes
                  )
              }
            : userContext;
        const { count: itemCount, hasPlus: itemPlus } = actionCompletion(
            schema || [],
            entity,
            formData || {},
            itemContext,
            registrationAttributes
        );
        count += itemCount;
        hasPlus = hasPlus || itemPlus;
    });
    return { count, hasPlus };
}

/**
 * Format a contents summary as the list's Action Items label, e.g. "5 members • 8 ISAs", with
 * singular/plural handling. Returned as a plain string (the list table renders text-only cells).
 * The counts are derived server-side (EnvelopeLandingApex) from the envelope's records.
 * @param {{members?: number, isas?: number}} summary  { members, isas } entity counts
 * @returns {string}
 */
function formatEnvelopeContentsLabel({ members = 0, isas = 0 } = {}) {
    const memberLabel = `${members} ${members === 1 ? 'member' : 'members'}`;
    const isaLabel = `${isas} ${isas === 1 ? 'ISA' : 'ISAs'}`;
    return `${memberLabel} • ${isaLabel}`;
}

/**
 * Basis tokens a strategy allocation row carries as `type`. A fixed-dollar row is a carve-out that
 * must not float as the account value changes; a fixed-percentage row describes the actively traded
 * remainder left once every fixed-dollar row is taken out of the Expected Account Value, so the
 * percentage rows total 100 across a complete allocation. Rows persisted before the basis existed
 * have no `type` — normalizeStrategyRows coalesces them to percentage, the legacy reading of every
 * pre-basis row.
 *
 * A row's basis follows the strategy's configured Allowed Funding Basis (see ALLOWED_BASIS and
 * basisForOption): fixed by the rule for Dollar Only / Percent Only strategies, advisor-chosen only
 * where the rule allows either. It is snapshotted onto Order__c.Funding_Basis__c at submit.
 * Reclassifying a strategy therefore applies to new submissions only — a historical row's basis must
 * never be re-derived from the strategy's current setting.
 */
const STRATEGY_BASIS = {
    DOLLAR: 'fixed-dollar',
    PERCENT: 'fixed-percentage'
};

/**
 * Coalesce each row's basis: anything not explicitly fixed-dollar is a percentage row. A row that
 * reaches here without an `id` is given one, because the allocation table keys its `for:each` on it
 * and resolves every edit through `data-id` — an undefined key degrades to positional matching, which
 * remounts rows when one is removed from the middle (losing focus and re-setting every control's
 * value). Rows are always produced with an id today; this is the guarantee, not a workaround.
 *
 * Memoized per input-array identity. The result is bound into envelopeStrategyList as `strategies`,
 * and the section reads it — directly and through strategyTotals — fifteen to twenty times per render,
 * so a fresh array per read re-rendered the whole table on every parent render and multiplied the
 * arithmetic by the number of read sites. The returned array must be treated as immutable; every
 * caller already copies before changing anything.
 * @param {Array<object>} strategies
 * @returns {Array<object>}  rows without a recognized type gain type: fixed-percentage
 */
const NORMALIZED_ROWS = new WeakMap();
const NO_ROWS = [];

function normalizeStrategyRows(strategies) {
    if (!strategies) {
        return NO_ROWS;
    }
    const cached = NORMALIZED_ROWS.get(strategies);
    if (cached) {
        return cached;
    }
    const rows = strategies.map((row, index) => ({
        ...row,
        id: row?.id ?? `row-${index + 1}`,
        type: row?.type === STRATEGY_BASIS.DOLLAR ? STRATEGY_BASIS.DOLLAR : STRATEGY_BASIS.PERCENT
    }));
    NORMALIZED_ROWS.set(strategies, rows);
    return rows;
}

/**
 * The Allowed Funding Basis values configured on Sleeve_Basis_Rule__mdt, which decide which sleeve
 * list a strategy may be funded from. Mirror of TradeInstructionController.BASIS_* — the Apex side
 * resolves the same rule table so a stale client cannot post a row the rule forbids.
 */
const ALLOWED_BASIS = {
    DOLLAR_ONLY: 'Dollar Only',
    PERCENT_ONLY: 'Percent Only',
    EITHER: 'Either'
};

/**
 * The funding unit a strategy's configured Allowed Funding Basis dictates for an allocation row.
 * Dollar Only and Percent Only lock the row to that unit — the advisor may only type into the cell
 * for that unit, and the counterpart cell is a calculated read-out — while Either leaves the unit to
 * the advisor (`unit: null`, meaning keep whatever the row already carries) and makes both cells
 * live. An option with no resolved rule reads as Either: a missing rule is an absence of
 * configuration, not a restriction, so a sleeve is locked to one unit only where someone has
 * said so. Mirrors TradeInstructionController.allowedBasisFor.
 *
 * `allowed` is returned alongside so the allocation table can decide per-cell editability without
 * re-deriving the rule; callers that only need the unit read `unit`/`locked` as before.
 * @param {{allowedBasis}} [option]  a shaped strategy option from the shell
 * @returns {{unit: string|null, locked: boolean, allowed: string}}  unit is a STRATEGY_BASIS token
 *          when locked; allowed is an ALLOWED_BASIS value
 */
function basisForOption(option) {
    const allowed = option?.allowedBasis || ALLOWED_BASIS.EITHER;
    if (allowed === ALLOWED_BASIS.EITHER) {
        return { unit: null, locked: false, allowed };
    }
    return {
        unit: allowed === ALLOWED_BASIS.DOLLAR_ONLY ? STRATEGY_BASIS.DOLLAR : STRATEGY_BASIS.PERCENT,
        locked: true,
        allowed
    };
}

/**
 * The dollar equivalent of a percentage allocation row: its share of the *modeled pool*, which is
 * the Expected Account Value less every fixed-dollar carve-out (`strategyTotals().remainder`).
 *
 * Null — never a fictional $0 — whenever the pool is unknown or the percentage is not a positive
 * number, so a row with nothing to say renders an em dash rather than an arithmetic claim.
 *
 * There is deliberately no helper going the other way. A fixed-dollar sleeve is carved out before
 * the pool exists, so it holds no weight in the allocation at all — `strategyTotals` excludes it
 * from the percentage total and `Order__c.Funding_Basis_Matches_Value` forbids it from even storing
 * a percentage. A dollar row's weight is absent, not calculable.
 * @param {number|string} percent  percentage points
 * @param {number|string} pool     the modeled pool in dollars
 * @returns {number|null}
 */
function dollarsForPercentRow(percent, pool) {
    const pct = Number(percent);
    const base = Number(pool);
    if (!Number.isFinite(pct) || pct <= 0) {
        return null;
    }
    if (pool === null || pool === undefined || !Number.isFinite(base) || base < 0) {
        return null;
    }
    return (base * pct) / 100;
}

/**
 * The account value the Trade Instructions section derives from: what the advisor typed, or — only
 * where nothing has been typed — a value captured elsewhere in the interview (the Financial
 * Account's Source of Funds Amount, or the current allocation seeded from Apex).
 *
 * The fallback is never written back into the draft, so the section keeps tracking its source if
 * that source later changes. Resolved here rather than at each call site so the section body, the
 * completeness badge and the submit payload cannot disagree about which number is in play.
 * @param {number|string} typed     the Expected Account Value as entered
 * @param {number|string} fallback  the value to stand in when nothing was entered
 * @returns {number|null}  null when neither is a positive number
 */
function resolveExpectedValue(typed, fallback) {
    const entered = Number(typed);
    if (typed !== null && typed !== undefined && typed !== '' && Number.isFinite(entered) && entered > 0) {
        return entered;
    }
    const spare = Number(fallback);
    if (
        fallback !== null &&
        fallback !== undefined &&
        fallback !== '' &&
        Number.isFinite(spare) &&
        spare > 0
    ) {
        return spare;
    }
    return null;
}

/**
 * Total a strategy allocation list under the two-basis model, and judge it against the submission
 * rules. Dollar rows sum in dollars; percentage rows sum in points. Rows still missing a strategy or
 * a positive value are reported through `incompleteRows` and excluded from both sums, so a
 * half-typed row never skews the arithmetic shown for the finished ones. Kept here so the allocation
 * table, the Trade Instructions section, and the action page total — and judge completeness —
 * identically.
 *
 * Completeness follows the ticket's validation story: every row carries a strategy and a value
 * greater than zero, and — only when percentage rows are present — those rows sum to 100%, with
 * dollar sleeves excluded from that sum. Dollar sleeves are deliberately NOT required to reconcile
 * to the Expected Account Value: a submission is valid when the percentage rows total 100% and every
 * dollar row has a valid amount. Exceeding the expected value is surfaced as `isOverFunded`, a
 * warning the section shows without blocking, mirroring how the legacy screens ask for an
 * expected-value reason rather than refusing the entry.
 *
 * `expectedValue` is optional. Every entry point captures one now (see resolveExpectedValue), but it
 * can still be unknown — nothing typed and no fallback to stand in — and nothing may be derived from
 * a number we don't have: `remainder`, `allocatedAmount` and `isOverFunded` come back null/false and
 * completeness is judged on the rows alone. Completeness never reads it either way.
 *
 * @param {Array<{type, strategy, fundingAmount, fundingPercent}>} strategies
 * @param {number} [expectedValue]  the Expected Account Value, once one is known
 * @returns {{fixedDollarSum: number, percentSum: number, remainder: number|null,
 *            allocatedAmount: number|null, hasPercentRows: boolean, hasDollarRows: boolean,
 *            isOverFunded: boolean, isComplete: boolean, incompleteRows: Array<object>}}
 */
const TOTALS_MEMO = new WeakMap();

function strategyTotals(strategies, expectedValue) {
    const rows = normalizeStrategyRows(strategies);
    // Memoized per (normalized rows, expectedValue). The section's footer ledger, all four status
    // getters, both messages and envelopeActionDetails._tradeSection each call this with the same
    // inputs inside a single render — fifteen to twenty full passes over the rows, every one of which
    // also allocated a normalized copy. Keyed on the normalized rows rather than the raw array so the
    // memo lines up with normalizeStrategyRows' own cache.
    let byExpected = TOTALS_MEMO.get(rows);
    if (!byExpected) {
        byExpected = new Map();
        TOTALS_MEMO.set(rows, byExpected);
    }
    const memoKey = String(expectedValue);
    const cached = byExpected.get(memoKey);
    if (cached) {
        return cached;
    }
    const incompleteRows = [];
    let fixedDollarSum = 0;
    let percentSum = 0;
    let hasPercentRows = false;
    let hasDollarRows = false;
    for (const row of rows) {
        const isDollar = row.type === STRATEGY_BASIS.DOLLAR;
        const value = Number(isDollar ? row.fundingAmount : row.fundingPercent);
        if (isDollar) {
            hasDollarRows = true;
        } else {
            hasPercentRows = true;
        }
        // A blank strategy or a non-positive value leaves the row outstanding. Outstanding rows are
        // named to the advisor and kept out of the sums, so a half-typed row never skews the math
        // shown for the finished ones.
        if (!row.strategy || !Number.isFinite(value) || value <= 0) {
            incompleteRows.push(row);
            continue;
        }
        if (isDollar) {
            fixedDollarSum += value;
        } else {
            percentSum += value;
        }
    }
    const expected = Number(expectedValue);
    const hasExpected = Number.isFinite(expected) && expected > 0;
    const remainder = hasExpected ? expected - fixedDollarSum : null;
    const allocatedAmount = hasExpected ? fixedDollarSum + (remainder * percentSum) / 100 : null;
    const cents = (value) => Math.round(value * 100);
    const isOverFunded = hasExpected && cents(fixedDollarSum) > cents(expected);
    const isComplete =
        rows.length > 0 &&
        incompleteRows.length === 0 &&
        (!hasPercentRows || cents(percentSum) === cents(100));
    const totals = {
        fixedDollarSum,
        percentSum,
        remainder,
        allocatedAmount,
        hasPercentRows,
        hasDollarRows,
        isOverFunded,
        isComplete,
        incompleteRows
    };
    byExpected.set(memoKey, totals);
    return totals;
}

/**
 * Format a shaped field's value (output of shapeVisibleFields) as a read-only display string for
 * summary views: picklist values resolve to their labels, multi-select labels join with ', ',
 * booleans render Yes/No, currency/number/percent/date values format for display, and other types
 * pass through as strings. Returns '' for a blank value (except BOOLEAN, where an unchecked box
 * is a meaningful "No").
 * @param {object} shapedField  entry from shapeVisibleFields
 * @returns {string}
 */
function formatFieldDisplayValue(shapedField) {
    const { type, value, picklistOptions } = shapedField || {};
    if (type === 'BOOLEAN') {
        return value === true || value === 'true' ? 'Yes' : 'No';
    }
    if (isEmptyValue(value)) {
        return '';
    }
    if (type === 'MULTIPICKLIST') {
        return Array.isArray(value)
            ? value.map((entry) => optionLabel(picklistOptions, entry)).join(', ')
            : String(value);
    }
    if (type === 'PICKLIST' || type === 'REFERENCE') {
        return optionLabel(picklistOptions, value);
    }
    if (type === 'CURRENCY') {
        const amount = Number(value);
        return Number.isFinite(amount) ? CURRENCY_DISPLAY.format(amount) : String(value);
    }
    if (type === 'PERCENT') {
        const amount = Number(value);
        return Number.isFinite(amount) ? `${NUMBER_DISPLAY.format(amount)}%` : String(value);
    }
    if (type === 'DOUBLE' || type === 'INTEGER') {
        const amount = Number(value);
        return Number.isFinite(amount) ? NUMBER_DISPLAY.format(amount) : String(value);
    }
    if (type === 'DATE') {
        // Pure string transform ('YYYY-MM-DD' → 'MM/DD/YYYY'): Date-parsing a date-only ISO
        // string is UTC-based and can shift a day in negative-offset time zones.
        const parts = String(value).split('-');
        return parts.length === 3 ? `${parts[1]}/${parts[2]}/${parts[0]}` : String(value);
    }
    if (type === 'DATETIME') {
        const parsed = new Date(value);
        return Number.isNaN(parsed.getTime()) ? String(value) : DATETIME_DISPLAY.format(parsed);
    }
    return String(value);
}

export {
    RELATED_PARTIES_FIELD_KEY,
    GROUP_IDS,
    ACCOUNT_GROUP_IDS,
    RELATED_PARTY_MEMBER_TYPES,
    ACCOUNT_ACTION_TYPES,
    ACCOUNT_TYPE_TO_MDT,
    ACCOUNT_TYPE_TO_CASE_TYPE,
    MEMBER_ACTION_TYPES,
    MEMBER_ACTION_TO_CASE_TYPE,
    PROPOSED_CHANGES_MDT,
    isDmsPlatform,
    resolveSchemaKey,
    resolveActionCatalog,
    accountActionTypeFor,
    accountActionLabelFor,
    memberActionTypeFor,
    memberActionLabelFor,
    schemaCacheKey,
    evaluateWhereStatement,
    applyLookupOptions,
    filterSectionsByAccountType,
    accountValuesToProposedDraft,
    shapeVisibleFields,
    clearHiddenAnswers,
    clearDependentCustodian,
    hasPriorAnswer,
    changeClearsAnswers,
    isEmptyValue,
    draftValuesEqual,
    strategyRowsEqual,
    COMMIT_IDLE_MS,
    isFormatValid,
    applyInputMask,
    isBooleanField,
    isFieldOutstanding,
    sectionStatus,
    markUpdatedFields,
    resolveRelatedPartyRequirements,
    derivePartyContext,
    resolveRegistrationGroup,
    memberRecordTypesFor,
    aarRoleForKey,
    managedAarRolesFor,
    requirementKeyForAarRole,
    accountRoleForKey,
    managedAccountRolesFor,
    requirementKeyForAccountRole,
    accountRoleLimits,
    serviceOwnerFieldForKey,
    serviceOwnerKeyForField,
    managedServiceOwnerFields,
    exclusivePartyIds,
    partyRoleLabel,
    memberTypeForPartyTypes,
    partyTypeChoices,
    persistedMemberTypeFor,
    derivePartyRoles,
    pendingPartyIds,
    unmetRelatedPartyRequirements,
    waivedRelatedPartyKeys,
    relatedPartyPeers,
    partyAlternativesLabel,
    countMissingRelatedParties,
    countExcessRelatedParties,
    relatedPartiesStatus,
    splitAddRecordFields,
    countMissingInputs,
    hasUnfilledKeyPointDependents,
    missingInputsCountLabel,
    missingInputsLabel,
    actionCompletion,
    selectMissingSections,
    sumMissingInputs,
    formatEnvelopeContentsLabel,
    strategyTotals,
    STRATEGY_BASIS,
    ALLOWED_BASIS,
    normalizeStrategyRows,
    basisForOption,
    dollarsForPercentRow,
    resolveExpectedValue,
    formatFieldDisplayValue
};