import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { resolveRecordIdFromPageReference } from "c/recordNavigationUtils";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getFormSchema from "@salesforce/apex/FieldDetailController.getFormSchema";
import getRecordValuesForType from "@salesforce/apex/FieldDetailController.getRecordValuesForType";

/**
 * arcHouseholdDetail
 *
 * The Details tab of the Lightning household/person-account record page, redrawn
 * in ARC. Read-only.
 *
 * WHAT IT REPLICATES was taken from the live page, not guessed: the sections and
 * their field order were read off
 * /lightning/r/Account/<id>/view with the Details tab open. Four sections carry
 * fields there -- Personal Information, Address Information, Phone Numbers, KYC
 * Information. The page also shows AML Information, Employment Information,
 * Marketing Information and Years Experience as headings, but they render no
 * rows for this record type, so they are not reproduced as empty cards.
 *
 * ONE COMPONENT, BOTH RECORD TYPES. Individual and Household get the same screen
 * -- same layout, same styling, same behaviour -- with a different field set
 * each, because the two Lightning pages show different fields. The mapping is
 * SCHEMA_BY_RECORD_TYPE below.
 *
 * EXISTING APEX ONLY. It calls FieldDetailController.getFormSchema and
 * .getRecordValuesForType, both already @AuraEnabled. No Apex was written or
 * modified.
 *
 * WHY NOT ArcRecordDetailController.load. That was the first choice, but for
 * Account it ignores the schemaType it is passed and derives its own from a
 * private map inside the controller -- see the note on SCHEMA_BY_RECORD_TYPE.
 *
 * The field sets live in new Envelope_Field__mdt / Section__mdt rows under two
 * new types, "Individual Detail" and "Household Detail". The existing
 * "Client - Individual" rows are the ONBOARDING INTERVIEW questions and drive
 * the envelope wizard, so they were left alone rather than rewritten: not one
 * existing row was modified.
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
 * controller -- a private map that has no Household entry, so a Household falls
 * back to "Client - Business" and renders Business Information and Suitability.
 * That is the bug on the household screen.
 *
 * Correcting that map would mean editing Apex. FieldDetailController.getFormSchema
 * and getRecordValuesForType are both @AuraEnabled and both take an explicit
 * type, so the mapping can live here instead and no Apex is touched.
 *
 * IndustriesIndividual, Diversify_Related_Person and Prospect are listed because
 * they are unmapped in the controller too and only work there by accident of the
 * person-account fallback.
 */
const SCHEMA_BY_RECORD_TYPE = {
  PersonAccount: "Individual Detail",
  Individual: "Individual Detail",
  IndustriesIndividual: "Individual Detail",
  Diversify_Related_Person: "Individual Detail",
  Prospect: "Individual Detail",
  Household: "Household Detail",
  IndustriesHousehold: "Household Detail"
};

const RECORD_TYPE_FIELD = "Account.RecordType.DeveloperName";

export default class ArcHouseholdDetail extends LightningElement {
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

  recordId;
  sectionsRaw = [];
  values = {};
  errorMessage;
  isLoading = false;

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
  @wire(getRecord, { recordId: "$recordId", fields: [RECORD_TYPE_FIELD] })
  wiredRecordType({ data, error }) {
    if (data) {
      this.recordTypeName = getFieldValue(data, RECORD_TYPE_FIELD);
      this.loadSchema();
      return;
    }

    if (error) {
      this.errorMessage = "Unable to read this record's type.";
    }
  }

  recordTypeName;

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

    this.isLoading = true;

    Promise.all([
      getFormSchema({ objectName: this.objectApiName, type }),
      getRecordValuesForType({
        objectName: this.objectApiName,
        type,
        recordIds: [this.recordId]
      })
    ])
      .then(([schema, valuesById]) => {
        this.sectionsRaw = schema || [];
        this.values = (valuesById && valuesById[this.recordId]) || {};
        this.errorMessage = undefined;
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
        const fields = (section.fields || []).map((field, index) => {
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

  get showTitle() {
    return Boolean(this.cardTitle);
  }

  /** Genuinely empty, as opposed to still loading or failed. */
  get showEmpty() {
    return (
      Boolean(this.recordId) &&
      !this.isLoading &&
      !this.errorMessage &&
      !this.hasSections
    );
  }
}