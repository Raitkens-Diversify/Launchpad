import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import {
  buildExperienceRecordPath,
  buildRecordNavigationReference,
  shouldAllowNativeRecordNavigation
} from "c/recordNavigationCommunityUtils";
import {
  HOUSEHOLDS_NAV_ITEM_ID,
  recordNavSelectionById
} from "c/arcNavTrailState";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getFormSchema from "@salesforce/apex/FieldDetailController.getFormSchema";
import getSectionLayouts from "@salesforce/apex/FieldDetailController.getSectionLayouts";
import getRecordValuesForType from "@salesforce/apex/FieldDetailController.getRecordValuesForType";
import getRelationships from "@salesforce/apex/ArcAccountRelationshipsController.getRelationships";
import { evaluateWhereStatement } from "c/envelopeFormSchema";

/**
 * arcHouseholdDetail
 *
 * The Details tab of the Lightning Account record page, redrawn in ARC.
 * Read-only. Serves EVERY Account record type, not just households — the name is
 * historical and kept because the deployed ARC page references it.
 *
 * WHAT IT REPLICATES was not guessed. Each field set comes from the flexipage the
 * CRM app actually assigns to that record type, and was then checked against
 * /lightning/r/Account/<id>/view with the Details tab open, on a real record of
 * that type. Section order, field order and section names all come from there.
 *
 * Sections gated OFF by component visibility are not reproduced: the household
 * page carries Review Meeting, Roth Conversions, Donation in Kind, Qualified
 * Charitable Distributions, Annual Funding and Recurring Trading, each shown only
 * when its own service flag is set, and none of them renders on an ordinary
 * household. Sections whose FIELDS are gated but whose heading still shows -- AML
 * Information, Employment Information, Marketing Information, Years Experience on
 * the individual page -- ARE reproduced, with their fields, because a blank field
 * renders as an em dash here and "empty" is more useful than "absent".
 *
 * ONE COMPONENT, EVERY RECORD TYPE. Individual, Household, Business, Trust and
 * Retirement Plan get the same screen -- same layout, styling and behaviour --
 * with a different field set each, because their Lightning pages show different
 * fields. The mapping is SCHEMA_BY_RECORD_TYPE below.
 *
 * EXISTING APEX ONLY. It calls FieldDetailController.getFormSchema,
 * .getSectionLayouts and .getRecordValuesForType, all already @AuraEnabled. No
 * Apex was written or modified. getSectionLayouts reorders getFormSchema's
 * sections by Section__mdt's parent/child order (see orderSectionsByLayout) --
 * the same reorder arcRecordDetail.js's buildSectionCards already applies for
 * every other object on the generic pipeline; this component skipped it only
 * because it calls FieldDetailController directly instead of going through
 * ArcRecordDetailController.load (see "WHY NOT ArcRecordDetailController.load"
 * below). Only "Client - Individual" (PersonAccount) actually reorders in
 * practice today -- the five *_Detail types' sections already happened to come
 * back in Section__mdt order.
 *
 * WHY NOT ArcRecordDetailController.load. That was the first choice, but for
 * Account it ignores the schemaType it is passed and derives its own from a
 * private map inside the controller -- see the note on SCHEMA_BY_RECORD_TYPE.
 *
 * The field sets live in new Envelope_Field__mdt / Section__mdt rows under five
 * new types: "Individual Detail", "Household Detail", "Business Detail",
 * "Trust Detail" and "Retirement Plan Detail". The existing "Client - *" rows
 * are the ONBOARDING INTERVIEW questions and drive the envelope wizard, so they
 * were left alone rather than rewritten: not one existing row was modified.
 *
 * NO LABELS ARE CONFIGURED. Every row leaves Label__c blank, so
 * FieldDetailController falls back to describe.getLabel() -- the field's real
 * label, which is what Lightning renders. Typing 164 labels by hand would have
 * been 164 chances to drift from the page this copies.
 *
 * DEVIATION WORTH KNOWING. Lightning renders each address as ONE compound row
 * ("Billing Address" showing street, city, state, postcode together). ARC's field
 * renderer has no ADDRESS type, so a compound field would come back blank --
 * each address is therefore split into its components. That is the one place
 * this is not visually identical, and it is a renderer limitation rather than a
 * choice.
 */
/**
 * Record type -> schema type.
 *
 * WHY THIS IS IN THE COMPONENT AND NOT IN APEX. ArcRecordDetailController.load
 * looked like the natural entry point, but for Account it IGNORES the schemaType
 * it is handed and derives its own from RECORD_TYPE_TO_SCHEMA_TYPE inside the
 * controller. FieldDetailController.getFormSchema and getRecordValuesForType are
 * both @AuraEnabled and both take an explicit type, so the mapping lives here
 * instead and no Apex is touched.
 *
 * WHICH LIGHTNING PAGE EACH ONE COPIES. Read out of the CRM app's own
 * flexipage assignments, not guessed, then checked against the rendered page:
 *
 *   Individual      Person_Account_Record_Page
 *   Household       Household_Lightning_Page
 *   Business        Business_Trust_Ret_Plan_Account_Record_Page, Business Details
 *   Trust           Business_Trust_Ret_Plan_Account_Record_Page, Trust Details
 *   Retirement Plan Business_Trust_Ret_Plan_Account_Record_Page, Plan Information
 *
 * The last three share ONE Lightning page that swaps its first section by record
 * type through component visibility, which is why they are three schema types
 * here rather than one.
 *
 * RECORD COUNTS, measured in the org on 2026-08-27, because they decide which
 * page is worth copying: PersonAccount 53,701 · Household 36,251 ·
 * Diversify_Related_Person 435 · Business 307 · Trust 160 · Prospect 139 ·
 * Retirement_Plan 118 · IndustriesBusiness 18 · IndustriesHousehold 13 ·
 * IndustriesIndividual 0.
 *
 * That last set of numbers matters: an earlier version of this file built the
 * household field set from an IndustriesHousehold record, which is 13 records out
 * of 36,264 households. Household is the record type that carries the data, and
 * it renders a different page with different sections.
 *
 * IndustriesBusiness is pointed at Business Detail even though it renders
 * Business_Account_Record_Page rather than the shared one — 18 records did not
 * justify a sixth field set.
 */
const SCHEMA_BY_RECORD_TYPE = {
  PersonAccount: "Client - Individual",
  IndustriesIndividual: "Individual Detail",
  Prospect: "Individual Detail",
  Diversify_Related_Person: "Individual Detail",

  Household: "Household Detail",
  IndustriesHousehold: "Household Detail",

  Business: "Business Detail",
  IndustriesBusiness: "Business Detail",

  Trust: "Trust Detail",
  IndustriesInstitution: "Trust Detail",

  Retirement_Plan: "Retirement Plan Detail"
};

const RECORD_TYPE_FIELD = "Account.RecordType.DeveloperName";

/**
 * A lookup's related-record NAME field, derived from the lookup's own API name.
 *
 * WHY THIS IS NEEDED. FieldDetailController.getRecordValuesForType returns raw
 * field values -- SELECT Household__c gives back an 18-character id, not
 * "Smith Household". Rendered straight, every lookup on these screens showed an
 * id: Household, Financial Advisor Team, Created By, Last Modified By, Account
 * Record Type. Lightning shows the name, so the name is fetched separately
 * through uiRecordApi and swapped in.
 *
 *   Household__c      -> Household__r.Name
 *   CreatedById       -> CreatedBy.Name
 *   RecordTypeId      -> RecordType.Name
 *
 * Returns null for anything that is not shaped like a lookup, which is then left
 * alone rather than guessed at.
 */
const relationshipFor = (fieldPath) => {
  if (!fieldPath) {
    return null;
  }
  if (fieldPath.endsWith("__c")) {
    return `${fieldPath.slice(0, -3)}__r`;
  }
  if (fieldPath.endsWith("Id") && fieldPath.length > 2) {
    return fieldPath.slice(0, -2);
  }
  return null;
};

const TYPE_REFERENCE = "REFERENCE";

/**
 * Lookup targets that render as a link on the Details tab. Only objects with an
 * ARC detail route of their own belong here: a Household lookup (Household__c ->
 * Account) can open the household's ARC page, but Created By (User) and
 * Financial Advisor Team have no ARC page, so those stay plain text rather than
 * linking to a page that does not exist.
 */
const LINKED_LOOKUP_OBJECTS = new Set(["Account"]);

/**
 * The sidebar entry a linked lookup's target lives under, recorded as the nav
 * trail before navigating so the breadcrumb on the target reads that list
 * (Contacts › Households › <household>) rather than the list this record was
 * reached from. A lookup not listed here leaves the trail alone.
 */
const NAV_ITEM_BY_LOOKUP_FIELD = {
  Household__c: HOUSEHOLDS_NAV_ITEM_ID
};

/**
 * Sections the ARC page leaves out of a type's field set even though the
 * Lightning page it copies still shows them, keyed by schema type. Dropped
 * here rather than by deleting their Envelope_Field__mdt rows, so the rows
 * stay the faithful copy of the Lightning page and this stays the one place
 * ARC deviates from it.
 *
 * Household: Financial Summary, Financial Statement and Suitability Information
 * were removed at the business's request (2026-09-03); the household's
 * Relationships (its members) fill the Details tab in their place.
 */
const HIDDEN_SECTIONS_BY_SCHEMA_TYPE = {
  "Household Detail": new Set([
    "Financial Summary",
    "Financial Statement",
    "Suitability Information"
  ])
};

/**
 * Sections that stay at the bottom of the Details tab, below Relationships --
 * on the Lightning page the audit fields sit under everything else, and a
 * household's members reading after Created By / Last Modified By would be
 * backwards.
 */
const TRAILING_SECTION_NAMES = new Set(["System Information"]);

/**
 * Orders a type's flat sections (as getFormSchema returns them -- first-seen order
 * while iterating Order__c-sorted FIELD rows, which says nothing about section
 * order) by Section__mdt's own parent/child layout, when one exists for that type.
 * Mirrors the same reorder arcRecordDetail.js's buildSectionCards already does for
 * every other object on this generic pipeline -- Account was the one type still
 * skipping it, because this component calls FieldDetailController directly instead
 * of going through ArcRecordDetailController.load.
 *
 * A section the layout doesn't mention -- an unconfigured extra, or a type with no
 * Section__mdt rows at all -- keeps its incoming relative order, appended after
 * every laid-out section. So this can only ever REORDER a section already being
 * shown, never drop one.
 */
const orderSectionsByLayout = (sections, layoutGroups) => {
  if (!layoutGroups || !layoutGroups.length) {
    return sections;
  }

  const byName = new Map(sections.map((section) => [section.name, section]));
  const ordered = [];

  layoutGroups.forEach((group) => {
    (group.childSections || []).forEach((childName) => {
      const section = byName.get(childName);
      if (section) {
        ordered.push(section);
        byName.delete(childName);
      }
    });
  });

  sections.forEach((section) => {
    if (byName.has(section.name)) {
      ordered.push(section);
    }
  });

  return ordered;
};

/**
 * Fixed top-level tabs: Details, Cases, Documents and Investments & Services,
 * in this order, for every record type. Relationships used to be a fifth tab
 * (gated by record type); it now renders inside Details as one of its
 * sections -- see detailBlocks -- so a household's members and a contact's
 * Trusted Contact sit with the record's fields rather than behind another
 * click.
 */
const DETAILS_TAB_KEY = "__details__";
const CASES_TAB_KEY = "__cases__";
const DOCUMENTS_TAB_KEY = "__documents__";
const INVESTMENTS_TAB_KEY = "__investments__";

/** Key of the Relationships block inside the Details tab (see detailBlocks). */
const RELATIONSHIPS_BLOCK_KEY = "__relationships__";

export default class ArcHouseholdDetail extends NavigationMixin(
  LightningElement
) {
  /** Object whose record page this sits on. */
  @api objectApiName = "Account";

  /**
   * Fallback schema type, used ONLY when the record's type is not in
   * SCHEMA_BY_RECORD_TYPE. Blank means render nothing rather than guess: showing
   * an Individual's field set on an unrecognised record type would be worse than
   * showing none.
   *
   * Named schemaType, and no longer the driver, because the platform refuses to
   * remove a design property that a deployed page references -- "You can't
   * remove the property tag(s) named 'schemaType' ... found in 1 Development
   * Instance(s)". Repurposing it beats orphaning the page to rename it.
   */
  @api schemaType = "";

  /** Optional heading above the sections. Blank renders none. */
  @api cardTitle = "";

  /** Egnyte domain for the Documents tab -- forwarded to c-egnyte-vf-embed,
   *  which moved here from its own page-level placement. */
  @api domain = "";

  recordId;
  sectionsRaw = [];
  values = {};
  errorMessage;
  isLoading = false;

  /**
   * Spanning field paths for the lookups on this schema, e.g.
   * "Account.Household__r.Name". Reactive: set once the schema is known, which
   * re-runs the wire below with the names it needs.
   */
  lookupFields = [];

  /** fieldPath -> resolved related-record name. */
  lookupNames = {};

  /** fieldPath -> the spanning path its name arrives on. */
  _lookupPathByField = {};

  /** Guards the schema load against the extra wire pass lookupFields causes. */
  _loadedKey;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const next =
      resolveRecordIdFromPageReference(pageRef, this.objectApiName) || undefined;

    if (next !== this.recordId) {
      this.recordId = next;
    }
  }

  /**
   * The record type decides the schema. Read through uiRecordApi rather than
   * Apex: it needs no server code of its own and is already cached by the
   * platform for a record the page is showing anyway.
   */
  @wire(getRecord, {
    recordId: "$recordId",
    fields: [RECORD_TYPE_FIELD],
    optionalFields: "$lookupFields"
  })
  wiredRecordType({ data, error }) {
    if (data) {
      this.recordTypeName = getFieldValue(data, RECORD_TYPE_FIELD);

      /*
       * optionalFields rather than fields, so a lookup the user cannot read, or
       * one whose relationship name does not resolve, leaves the rest of the
       * record intact instead of failing the whole read.
       */
      const names = {};
      Object.keys(this._lookupPathByField).forEach((fieldPath) => {
        const value = getFieldValue(data, this._lookupPathByField[fieldPath]);
        if (value) {
          names[fieldPath] = value;
        }
      });
      this.lookupNames = names;

      this.loadSchema();
      return;
    }

    if (error) {
      this.errorMessage = "Unable to read this record's type.";
    }
  }

  recordTypeName;

  /**
   * The Relationships section's own gate. ArcAccountRelationshipsController
   * returns a blank category for account types the Relationships section does
   * not cover (Retirement Plan) -- the same signal arcAccountRelationships uses
   * to render nothing -- so the section, and the separator above it, only
   * appear when this is non-blank. Wiring the same cacheable method the section
   * wires means one shared server call, not two, and the account-type rule
   * stays in Apex rather than being copied here.
   */
  _relationshipsCategory = "";

  @wire(getRelationships, { accountId: "$recordId" })
  wiredRelationships({ data }) {
    this._relationshipsCategory = data?.category || "";
  }

  /** Resolved schema type for this record, or undefined if its type is unmapped. */
  get resolvedSchemaType() {
    if (!this.recordTypeName) {
      return undefined;
    }

    return (
      SCHEMA_BY_RECORD_TYPE[this.recordTypeName] ||
      this.schemaType ||
      undefined
    );
  }

  /**
   * Two calls, both existing @AuraEnabled methods on FieldDetailController: the
   * schema (which sections and fields) and the values for this record. They are
   * separate methods server-side, so they are separate calls here; run together
   * so the page never paints half of a section.
   */
  loadSchema() {
    const type = this.resolvedSchemaType;

    if (!this.recordId || !type) {
      this.sectionsRaw = [];
      this.values = {};
      return;
    }

    /*
     * Setting lookupFields re-runs the wire above, which calls back in here. The
     * schema has not changed by then, so without this guard every record would
     * fetch its schema twice.
     */
    const key = `${this.recordId}|${type}`;
    if (this._loadedKey === key) {
      return;
    }
    this._loadedKey = key;

    this.isLoading = true;

    Promise.all([
      getFormSchema({ objectName: this.objectApiName, type }),
      getSectionLayouts(),
      getRecordValuesForType({
        objectName: this.objectApiName,
        type,
        recordIds: [this.recordId]
      })
    ])
      .then(([schema, layouts, valuesById]) => {
        const layoutGroups = (layouts && layouts[type]) || [];
        const hiddenSections = HIDDEN_SECTIONS_BY_SCHEMA_TYPE[type];
        this.sectionsRaw = orderSectionsByLayout(schema || [], layoutGroups).filter(
          (section) => !hiddenSections || !hiddenSections.has(section.name)
        );
        this.values = (valuesById && valuesById[this.recordId]) || {};
        this.errorMessage = undefined;
        this.collectLookupFields();
      })
      .catch((error) => {
        this.sectionsRaw = [];
        this.values = {};
        this.errorMessage =
          error?.body?.message || "Unable to load these details.";
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Works out which fields on this schema are lookups and asks the wire above for
   * their names. Called once per schema load; the paths are stable for a schema,
   * so the wire config settles after one extra pass.
   */
  collectLookupFields() {
    const pathByField = {};
    const paths = [];

    (this.sectionsRaw || []).forEach((section) => {
      (section.fields || []).forEach((field) => {
        if ((field.type || "").toUpperCase() !== TYPE_REFERENCE) {
          return;
        }
        const relationship = relationshipFor(field.fieldPath);
        if (!relationship) {
          return;
        }
        const path = `${this.objectApiName}.${relationship}.Name`;
        pathByField[field.fieldPath] = path;
        if (!paths.includes(path)) {
          paths.push(path);
        }
      });
    });

    this._lookupPathByField = pathByField;
    this.lookupFields = paths;
  }

  // ---- rendering ----------------------------------------------------------

  /**
   * Sections in the order the schema returns them, each field paired with its
   * value.
   *
   * A blank value renders as an em dash rather than being skipped: the Lightning
   * page lists every field on the layout whether or not it holds anything, and a
   * row that silently disappears makes the page look different per record.
   */
  get sections() {
    const values = this.values || {};

    return (this.sectionsRaw || [])
      .map((section) => {
        /*
         * Honor each field's Shown_WHERE_Statement__c against THIS record -- the
         * same conditions the onboarding wizard evaluates -- so a field the
         * Lightning page gates off is gated off here too: employer fields when
         * the client is not Employed, the mailing address when it matches the
         * permanent one, Officer/Symbol unless they are an officer, and so on.
         * The record's own values are the draft the condition reads (values is
         * already keyed by field API name, which is what the statements name).
         *
         * evaluateWhereStatement fails OPEN: a field with no condition, or one
         * whose statement this evaluator cannot parse, always shows. So this can
         * only ever HIDE a field a real condition rules out -- never drop a
         * plain field -- and an empty-but-applicable field still renders as an
         * em dash. A section whose every field is gated off ends up with no
         * fields and is dropped below, which is how a whole tab hides per
         * account.
         */
        const visibleFields = (section.fields || []).filter((field) =>
          evaluateWhereStatement(field.shownWhereStatement, values, {})
        );

        const fields = visibleFields.map((field, index) => {
          const raw = values[field.fieldPath];
          const type = (field.type || "").toUpperCase();

          /*
           * A checkbox is not blank when it is false -- Lightning draws an
           * unchecked box, and collapsing that to an em dash would say "no
           * value" where the record says "no". Rendered as a box glyph so the
           * two states are distinguishable at a glance without an input.
           */
          if (type === "BOOLEAN") {
            return {
              key: `${section.name}-${field.fieldPath}-${index}`,
              label: field.label || field.fieldPath,
              value: raw === true ? "\u2611" : "\u2610",
              valueClass: "arc-household-detail__value"
            };
          }

          /*
           * A compound address arrives as an object, so String() would print
           * "[object Object]". Formatted the way the Lightning page lays it
           * out: street, then "city, state postcode", then country, each on its
           * own line, skipping whatever is empty.
           */
          if (raw && typeof raw === "object") {
            const line2 = [
              raw.city,
              [raw.state || raw.stateCode, raw.postalCode].filter(Boolean).join(" ")
            ]
              .filter(Boolean)
              .join(", ");
            const lines = [raw.street, line2, raw.country].filter(Boolean);

            return {
              key: `${section.name}-${field.fieldPath}-${index}`,
              label: field.label || field.fieldPath,
              value: lines.length ? lines.join("\n") : "\u2014",
              valueClass: lines.length
                ? "arc-household-detail__value arc-household-detail__value--address"
                : "arc-household-detail__value arc-household-detail__value--blank"
            };
          }

          /*
           * A lookup renders its related record's NAME, never the id the server
           * returned. If the name has not arrived -- still in flight, or the user
           * cannot read the related record -- it renders as blank rather than as
           * a raw id, because an id on screen is worse than an empty row.
           *
           * A lookup whose related object has an ARC page of its own (the
           * Household) renders that name as a link to the page -- see
           * lookupHrefFor. The raw value is the related record's id.
           */
          if (type === TYPE_REFERENCE) {
            const name = this.lookupNames[field.fieldPath];
            const href = name ? this.lookupHrefFor(field, raw) : "";
            return {
              key: `${section.name}-${field.fieldPath}-${index}`,
              label: field.label || field.fieldPath,
              value: name || "\u2014",
              isLink: Boolean(href),
              href,
              recordId: raw,
              objectApiName: field.referenceTo,
              navItemId: NAV_ITEM_BY_LOOKUP_FIELD[field.fieldPath] || "",
              valueClass: name
                ? "arc-household-detail__value"
                : "arc-household-detail__value arc-household-detail__value--blank"
            };
          }

          const isBlank = raw === null || raw === undefined || raw === "";

          return {
            key: `${section.name}-${field.fieldPath}-${index}`,
            label: field.label || field.fieldPath,
            value: isBlank ? "—" : String(raw),
            // Computed here, not in the template: LWC cannot build a class
            // string from an expression, and a getter per row is not possible
            // inside for:each.
            valueClass: isBlank
              ? "arc-household-detail__value arc-household-detail__value--blank"
              : "arc-household-detail__value"
          };
        });

        return {
          key: section.name,
          name: section.name,
          fields,
          hasFields: fields.length > 0
        };
      })
      .filter((section) => section.hasFields);
  }

  get hasSections() {
    return this.sections.length > 0;
  }

  /**
   * Everything the Details tab stacks, in order: the field sections, then the
   * Relationships section (when this account's type has one), then any
   * trailing section (System Information) that belongs at the very bottom.
   * One list so the template renders them in a single loop and every block
   * gets the same separator; the Relationships entry is flagged so the loop
   * renders the card instead of a field grid.
   */
  get detailBlocks() {
    const sections = this.sections;
    const leading = sections.filter(
      (section) => !TRAILING_SECTION_NAMES.has(section.name)
    );
    const trailing = sections.filter((section) =>
      TRAILING_SECTION_NAMES.has(section.name)
    );
    const relationships = this.showRelationships
      ? [{ key: RELATIONSHIPS_BLOCK_KEY, isRelationships: true }]
      : [];

    return [...leading, ...relationships, ...trailing];
  }

  /** Whether the Relationships section applies to this account's type. */
  get showRelationships() {
    return Boolean(this._relationshipsCategory);
  }

  /** The tab strip itself no longer depends on Details having content --
   *  Cases/Documents/Investments & Services can be real even when the
   *  record's type carries no field sections at all. */
  get showTabs() {
    return Boolean(this.recordId);
  }

  // ---- lookup links -------------------------------------------------------

  /**
   * The ARC record URL for a lookup's related record, or "" when that object
   * has no ARC page (see LINKED_LOOKUP_OBJECTS). A real href rather than "#",
   * so middle-click and cmd/ctrl-click open the household in a new tab the way
   * the browser normally would; a plain click is routed through NavigationMixin
   * in handleLookupClick so it stays an in-site navigation.
   */
  lookupHrefFor(field, relatedId) {
    if (!relatedId || !LINKED_LOOKUP_OBJECTS.has(field.referenceTo)) {
      return "";
    }
    return buildExperienceRecordPath(relatedId, field.referenceTo);
  }

  handleLookupClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();

    const { recordId, objectApiName, navItemId } =
      event.currentTarget.dataset;
    const pageReference = buildRecordNavigationReference(
      recordId,
      objectApiName
    );

    if (!pageReference) {
      return;
    }

    if (navItemId) {
      recordNavSelectionById(navItemId);
    }

    this[NavigationMixin.Navigate](pageReference);
  }

  // ---- section tabs -------------------------------------------------------

  /**
   * The section whose tab is open. Held as a key rather than an index so it
   * survives the record switching underneath it: `sections` is rebuilt per
   * record, and a stored index would point at the wrong section (or off the
   * end) once the new record's section set is shorter or reordered.
   */
  _activeTabKey;

  /**
   * The key that is actually shown, resolved every render rather than stored.
   * Falls back to the first section when nothing is chosen yet, or when the
   * chosen section no longer exists after a record change -- so the panel is
   * never left blank pointing at a section that is gone.
   */
  get selectedTabKey() {
    const tabs = this.allTabs;
    if (!tabs.length) {
      return undefined;
    }
    const exists = tabs.some((tab) => tab.key === this._activeTabKey);
    return exists ? this._activeTabKey : tabs[0].key;
  }

  /**
   * Every tab in strip order, fixed regardless of record type. The single
   * source the tablist, the selected-key fallback and the arrow-key navigation
   * all read from, so they can never disagree on what the tabs are.
   */
  get allTabs() {
    return [
      { key: DETAILS_TAB_KEY, name: 'Details' },
      { key: CASES_TAB_KEY, name: 'Cases' },
      { key: DOCUMENTS_TAB_KEY, name: 'Documents' },
      { key: INVESTMENTS_TAB_KEY, name: 'Investments & Services' }
    ];
  }

  /** One entry per tab for the tablist, pre-decorated with its ARIA and class
   *  state so the template stays declarative (LWC cannot build a class string
   *  from an expression). */
  get tabItems() {
    const selected = this.selectedTabKey;
    return this.allTabs.map((tab) => {
      const active = tab.key === selected;
      return {
        key: tab.key,
        label: tab.name,
        ariaSelected: active ? 'true' : 'false',
        // Roving tabindex: only the active tab is in the tab order; the rest
        // are reached with the arrow keys, the way a tablist should behave.
        tabIndex: active ? '0' : '-1',
        cssClass: active
          ? 'arc-household-detail__tab arc-household-detail__tab--active'
          : 'arc-household-detail__tab'
      };
    });
  }

  /** True when the Details tab is the open one. All of `sections` render
   *  together here -- stacked, each under its own heading -- rather than one
   *  section at a time; there is no further tab beneath this one. */
  get isDetailsActive() {
    return this.selectedTabKey === DETAILS_TAB_KEY;
  }

  /** True when the Cases tab is the open one. */
  get isCasesActive() {
    return this.selectedTabKey === CASES_TAB_KEY;
  }

  /** True when the Documents tab is the open one. */
  get isDocumentsActive() {
    return this.selectedTabKey === DOCUMENTS_TAB_KEY;
  }

  /** True when the Investments & Services tab is the open one. */
  get isInvestmentsActive() {
    return this.selectedTabKey === INVESTMENTS_TAB_KEY;
  }

  handleTabClick(event) {
    this._activeTabKey = event.currentTarget.dataset.key;
  }

  /**
   * Arrow-key navigation across the strip: Left/Right wrap, Home/End jump.
   * Activation follows focus -- swapping the panel is a free client-side
   * re-render, so there is no reason to make the user press Enter as well.
   */
  handleTabKeydown(event) {
    const keys = this.allTabs.map((tab) => tab.key);
    if (!keys.length) {
      return;
    }
    const current = keys.indexOf(event.currentTarget.dataset.key);
    let next = -1;
    if (event.key === 'ArrowRight') {
      next = (current + 1) % keys.length;
    } else if (event.key === 'ArrowLeft') {
      next = (current - 1 + keys.length) % keys.length;
    } else if (event.key === 'Home') {
      next = 0;
    } else if (event.key === 'End') {
      next = keys.length - 1;
    }
    if (next === -1) {
      return;
    }
    event.preventDefault();
    this._activeTabKey = keys[next];
    const target = this.template.querySelector(`[data-key="${keys[next]}"]`);
    if (target) {
      target.focus();
    }
  }

  get showTitle() {
    return Boolean(this.cardTitle);
  }

  /**
   * Genuinely empty, as opposed to still loading or failed -- scoped to the
   * Details tab specifically: an unmapped record type carries no field
   * sections, but Cases/Documents/Investments & Services can still have
   * real content, so this no longer blocks the whole component.
   */
  get showDetailsEmpty() {
    return (
      Boolean(this.recordId) &&
      !this.isLoading &&
      !this.errorMessage &&
      !this.hasSections &&
      !this.showRelationships
    );
  }
}