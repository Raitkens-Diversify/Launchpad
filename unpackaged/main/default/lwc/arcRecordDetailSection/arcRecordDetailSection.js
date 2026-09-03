/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * Renders one metadata section as responsive label/control rows for arcRecordDetail.
 */
import { LightningElement, api } from "lwc";
import { formatFieldDisplayValue } from "c/envelopeFormSchema";
import { shouldAllowNativeRecordNavigation } from "c/recordNavigationUtils";
import ARC_ICONS from "@salesforce/resourceUrl/arcicon";

/**
 * Phosphor glyphs painted as CSS masks over currentColor. The URLs cannot live
 * in the stylesheet because the static-resource path is only known at runtime,
 * so they are published as custom properties on the host.
 */
const ICON_FILES = {
  pencil: "pencil-simple-bold",
  info: "info",
  lock: "lock"
};

export default class ArcRecordDetailSection extends LightningElement {
  @api section;
  @api isEditing = false;
  @api isSaving = false;
  @api hasChanges = false;
  @api isSubmitted = false;
  /**
   * Comma-separated field API names the home office controls. In edit mode they
   * render locked — label lock, "Regulated by Home Office" badge, and a
   * read-only value box — and the section shows the info alert explaining that
   * changing them needs an envelope (Figma 907:28922).
   */
  @api regulatedFields = "";
  /**
   * Renders the section as a summary only. The right-column Record card
   * (903:26684) is built from fields outside the Envelope_Field__mdt schema, so
   * the save path cannot accept them and it must not offer an Edit button.
   */
  @api readOnly = false;
  /**
   * Suppresses this section's own Cancel/Save while still rendering its fields
   * as editable. The record detail page saves a section at a time and wants
   * them; the create dialog saves the whole form at once, where a Save per
   * section would suggest each one commits on its own.
   */
  @api hideSectionActions = false;
  /** "rows" (Figma default) or "grid"; see arcRecordDetail.fieldLayout. */
  @api fieldLayout = "rows";

  connectedCallback() {
    this.applyIconVariables();
  }

  applyIconVariables() {
    Object.entries(ICON_FILES).forEach(([key, file]) => {
      this.style.setProperty(
        `--rds-icon-${key}`,
        `url('${ARC_ICONS}/${file}.svg')`
      );
    });
  }

  get label() {
    return this.section?.label || "";
  }

  get sectionKey() {
    return this.section?.key || "";
  }

  get showHeader() {
    return !this.section?.hideHeader;
  }

  get isReadonly() {
    return this.readOnly || this.isSubmitted || !this.isEditing;
  }

  get showEditButton() {
    return (
      !this.readOnly &&
      !this.isSubmitted &&
      !this.isEditing &&
      !this.everyFieldRegulated
    );
  }

  /**
   * A section whose every row is home-office controlled has nothing to offer an
   * editor: the button would open a form in which each field is locked, with the
   * "create an envelope" alert as the only way forward. Better to leave the
   * section read-only and let the header's Edit Regulated Fields action be the
   * single route to changing any of it.
   */
  get everyFieldRegulated() {
    const fields = this.fields || [];
    if (!fields.length) {
      return false;
    }
    if (this.regulatesEveryField) {
      return true;
    }
    const regulated = this.regulatedFieldNames;
    return fields.every((field) => regulated.includes(field.apiName));
  }

  get showSectionActions() {
    return (
      !this.readOnly &&
      !this.isSubmitted &&
      this.isEditing &&
      !this.hideSectionActions
    );
  }

  get fields() {
    return this.section?.fields || [];
  }

  get regulatedFieldNames() {
    return (this.regulatedFields || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean);
  }

  /**
   * `*` in the regulated list stands for "every field on this record", so a page
   * that is wholly home-office controlled does not have to enumerate its schema
   * and then drift out of date as fields are added.
   */
  get regulatesEveryField() {
    return this.regulatedFieldNames.includes("*");
  }

  get fieldRows() {
    const regulated = this.regulatedFieldNames;
    const all = this.regulatesEveryField;
    const editing = !this.isReadonly;

    return this.fields.map((field) => {
      const isRegulated = all || regulated.includes(field.apiName);
      const isLookup =
        String(field.type || "").toUpperCase() === "REFERENCE" &&
        Boolean(field.referenceTo);
      // Read mode prints the referenced record's name like any other value.
      // The picker is a form control and only belongs in the form: leaving it
      // rendered turned every read-only lookup into a greyed-out search box
      // sitting among plain text rows.
      const showControl = editing && !isRegulated;

      return {
        ...field,
        displayLabel: this.buildDisplayLabel(field, editing),
        displayValue: this.buildDisplayValue(field, isLookup),
        isRegulated,
        // Read mode keeps the lock on the label but not the badge: the frame
        // only draws "Regulated by Home Office" while editing (907:28922).
        showRegulatedBadge: isRegulated && editing,
        // Locked rows keep the read-only value box even while the rest of the
        // section is editable.
        showControl,
        showValue: !showControl,
        // A read-mode value whose field carries an href (the Record card's
        // Household, which opens the household's own page) renders as a link;
        // every other value stays plain text. The form never links -- a
        // control is what belongs there.
        showLink: !showControl && Boolean(field.href),
        showPlainValue: !showControl && !field.href,
        valueClass:
          isRegulated && editing
            ? "field-row__value field-row__value--locked"
            : "field-row__value",
        // A regulated row is 55px tall against a 36px control, and the frame
        // (907:28922) hangs the control off the top rather than centring it.
        rowClass:
          isRegulated && editing
            ? "field-row field-row--regulated"
            : "field-row"
      };
    });
  }

  /* Edit mode rules off every row (907:28922); read mode does not (903:26477). */
  get fieldsClass() {
    if (!this.isReadonly) {
      return "record-section__fields record-section__fields--editing";
    }
    // The grid only applies to reading. A form still wants one control per
    // line, where the eye can run straight down the inputs.
    return this.fieldLayout === "grid"
      ? "record-section__fields record-section__fields--grid"
      : "record-section__fields";
  }

  /** The alert only makes sense while editing a section that has locked rows. */
  get showRegulatedAlert() {
    return !this.isReadonly && this.fieldRows.some((row) => row.isRegulated);
  }

  handleCreateEnvelope() {
    this.dispatchEvent(
      new CustomEvent("createenvelope", {
        detail: { sectionKey: this.sectionKey },
        bubbles: true,
        composed: true
      })
    );
  }

  get isSaveDisabled() {
    return this.isSaving || !this.hasChanges;
  }

  get isCancelDisabled() {
    return this.isSaving;
  }

  get editAriaLabel() {
    return `Edit ${this.label}`;
  }

  /**
   * "(optional)" tells someone filling a form which rows they may skip, so it
   * only belongs while the section is being filled in. In read mode it said
   * nothing and, on a page where no field is required, said it against every
   * single row.
   */
  buildDisplayLabel(field, editing) {
    const label = field?.label || "";
    const isBoolean = field?.type === "BOOLEAN";
    if (!editing || field?.required || isBoolean) {
      return label;
    }
    return `${label} (optional)`;
  }

  buildDisplayValue(field, isLookup) {
    if (isLookup) {
      // The stored value is a record id; the name is resolved server-side.
      return field?.referenceLabel || "—";
    }
    const formatted = formatFieldDisplayValue(field);
    return formatted || "—";
  }

  handleEditClick() {
    this.dispatchEvent(
      new CustomEvent("edit", {
        detail: { sectionKey: this.sectionKey }
      })
    );
  }

  handleSaveClick() {
    this.dispatchEvent(
      new CustomEvent("save", {
        detail: { sectionKey: this.sectionKey }
      })
    );
  }

  /**
   * A linked value (see showLink) is an ordinary anchor, so middle-click and
   * cmd/ctrl-click open it in a new tab the way the browser normally would. A
   * plain click is handed to the parent as fieldlinkclick, which navigates in
   * place -- the parent knows which site or app it sits on; this section does
   * not.
   */
  handleLinkClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();

    const { fieldKey } = event.currentTarget.dataset;
    const field = this.fields.find((candidate) => candidate.key === fieldKey);

    this.dispatchEvent(
      new CustomEvent("fieldlinkclick", {
        detail: {
          sectionKey: this.sectionKey,
          fieldKey,
          href: field?.href || "",
          linkRecordId: field?.linkRecordId || "",
          linkObjectApiName: field?.linkObjectApiName || "",
          linkNavItemId: field?.linkNavItemId || ""
        }
      })
    );
  }

  handleCancelClick() {
    this.dispatchEvent(
      new CustomEvent("sectioncancel", {
        detail: { sectionKey: this.sectionKey },
        bubbles: true,
        composed: true
      })
    );
  }

  @api
  reportValidity() {
    let valid = true;
    this.template
      .querySelectorAll("c-arc-record-detail-field")
      .forEach((control) => {
        if (
          typeof control.reportValidity === "function" &&
          control.reportValidity() === false
        ) {
          valid = false;
        }
      });
    return valid;
  }

  @api
  checkValidity() {
    let valid = true;
    this.template
      .querySelectorAll("c-arc-record-detail-field")
      .forEach((control) => {
        if (
          typeof control.checkValidity === "function" &&
          control.checkValidity() === false
        ) {
          valid = false;
        }
      });
    return valid;
  }

  @api
  flushPendingEdits() {
    this.template
      .querySelectorAll("c-arc-record-detail-field")
      .forEach((control) => {
        if (typeof control.flushPendingEdits === "function") {
          control.flushPendingEdits();
        }
      });
  }

  @api
  resetField(apiName) {
    const control = this.template.querySelector(
      `c-arc-record-detail-field[data-field="${apiName}"]`
    );
    if (control && typeof control.resetValue === "function") {
      control.resetValue();
    }
  }

  @api
  resetAllFields() {
    this.template
      .querySelectorAll("c-arc-record-detail-field")
      .forEach((control) => {
        if (typeof control.resetValue === "function") {
          control.resetValue();
        }
      });
  }

  handleFieldChange(event) {
    const { field, value } = event.detail || {};
    this.dispatchEvent(
      new CustomEvent("valuechange", {
        detail: { sectionKey: this.sectionKey, field, value }
      })
    );
  }
}