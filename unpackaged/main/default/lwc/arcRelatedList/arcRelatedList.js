/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * Configurable related-record card for Experience Cloud record pages: the
 * children of the page's record shown as a compact table, each row linking to
 * the child record.
 *
 * The record id comes from the page context the way arcRecordDetail resolves
 * it, so the card only needs to be told what to show.
 */
import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import {
  resolveRecordIdFromPageReference,
  buildRecordNavigationReference
} from "c/recordNavigationUtils";
import getRelatedRecords from "@salesforce/apex/ArcRelatedListController.getRelatedRecords";

export default class ArcRelatedList extends NavigationMixin(LightningElement) {
  /** Card heading, e.g. "Check Deposits". */
  @api cardLabel = "Related";
  /** Child object API name, e.g. Check_Deposit__c. */
  @api relatedObjectApiName = "";
  /** The child's lookup back to this page's record, e.g. Check__c. */
  @api parentFieldApiName = "";
  /**
   * Ordered columns as `Label:FieldPath` pairs, e.g.
   * "Deposit:Name,Financial Account:Financial_Account__r.Name,Amount:Amount__c".
   * The first column is the one that links to the record.
   */
  @api columns = "";
  /**
   * The field holding the id a row opens, when that is not the row itself.
   * Files come back as ContentDocumentLink rows, whose own Id is the join
   * record; the file lives at ContentDocumentId.
   */
  @api linkFieldApiName = "";
  /** Object the link id belongs to; defaults to the queried object. */
  @api linkObjectApiName = "";
  /** Rows with nowhere useful to go — a field history, say — do not link. */
  @api disableRowLinks = false;

  /**
   * Show a caret that collapses the list, the way a related list collapses on a
   * Lightning record page. Off by default: the pages already using this
   * component do not expect a control in the header.
   */
  @api collapsible = false;

  _collapsed = false;

  _recordId;
  _loadedSignature = "";
  _stylesLoaded = false;

  rows = [];
  types = [];
  currencyCode = "USD";
  hasMore = false;
  isLoading = true;
  errorMessage = "";

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const resolved = resolveRecordIdFromPageReference(pageRef, null);
    if (resolved && resolved !== this._recordId) {
      this._recordId = resolved;
    }
  }

  /**
   * Everything the query depends on, as one string.
   *
   * The load used to be triggered from the recordId setter alone. LWC sets
   * public properties in no guaranteed order, so when this card is used inside
   * another component's template the id can arrive before the object and
   * columns do — loadRows then returned early and nothing ever called it
   * again, leaving a populated list showing zero rows. Watching the whole
   * config instead means the fetch happens once, whenever the last piece
   * lands, however the properties were ordered.
   */
  get loadSignature() {
    return [
      this._recordId,
      this.relatedObjectApiName,
      this.parentFieldApiName,
      this.linkFieldApiName,
      this.columns
    ].join("|");
  }

  renderedCallback() {
    const signature = this.loadSignature;
    if (signature === this._loadedSignature) {
      return;
    }
    if (!this._recordId || !this.relatedObjectApiName) {
      return;
    }
    this._loadedSignature = signature;
    this.loadRows();
  }

  get isExpanded() {
    return !this.collapsible || !this._collapsed;
  }

  get ariaExpanded() {
    return String(this.isExpanded);
  }

  get toggleClass() {
    return this._collapsed
      ? "related-list__toggle"
      : "related-list__toggle related-list__toggle--open";
  }

  get toggleLabel() {
    return `${this._collapsed ? "Expand" : "Collapse"} ${this.cardLabel}`;
  }

  handleToggle() {
    this._collapsed = !this._collapsed;
  }

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    if (!value || value === this._recordId) {
      return;
    }
    this._recordId = value;
  }

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch(() => {
        /* Non-fatal: the component's own stylesheet covers layout. */
      });
    }
  }

  /** `Label:FieldPath` pairs; a bare entry uses the path as its own label. */
  get columnDefs() {
    return (this.columns || "")
      .split(",")
      .map((entry) => entry.trim())
      .filter(Boolean)
      .map((entry) => {
        const separator = entry.indexOf(":");
        if (separator === -1) {
          return { label: entry, path: entry };
        }
        return {
          label: entry.slice(0, separator).trim(),
          path: entry.slice(separator + 1).trim()
        };
      })
      .filter((column) => Boolean(column.path));
  }

  get headers() {
    return this.columnDefs.map((column, index) => ({
      key: column.path,
      label: column.label,
      cssClass:
        index === 0
          ? "related-list__th related-list__th--first"
          : "related-list__th"
    }));
  }

  async loadRows() {
    const columns = this.columnDefs;
    if (!this._recordId || !this.relatedObjectApiName || !columns.length) {
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";

    try {
      const result = await getRelatedRecords({
        recordId: this._recordId,
        objectApiName: this.relatedObjectApiName,
        parentFieldApiName: this.parentFieldApiName,
        fieldApiNames: columns.map((column) => column.path),
        linkFieldApiName: this.linkFieldApiName || null
      });
      this.rows = result?.rows || [];
      this.types = result?.types || [];
      this.currencyCode = result?.currencyCode || "USD";
      this.hasMore = result?.hasMore === true;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcRelatedList] Failed to load related records", error);
      this.errorMessage =
        error?.body?.message || "Unable to load these records right now.";
      this.rows = [];
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Apex hands every cell over as a string, because a generic query cannot
   * know what it selected until it describes it. The type comes back
   * alongside so an amount reads as money and a date in the reader's locale
   * rather than as the raw 100.00 / 2026-07-22 the query returned.
   */
  formatCell(value, index) {
    if (value === null || value === undefined || value === "") {
      return "—";
    }

    const type = String(this.types[index] || "").toUpperCase();

    if (["CURRENCY", "DOUBLE", "PERCENT", "INTEGER"].includes(type)) {
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) {
        return value;
      }
      return new Intl.NumberFormat(undefined, {
        style: type === "CURRENCY" ? "currency" : "decimal",
        currency: type === "CURRENCY" ? this.currencyCode : undefined,
        maximumFractionDigits: type === "INTEGER" ? 0 : 2
      }).format(type === "PERCENT" ? numeric / 100 : numeric);
    }

    if (type === "DATE" || type === "DATETIME") {
      const parsed = new Date(value);
      if (Number.isNaN(parsed.getTime())) {
        return value;
      }
      return parsed.toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
        year: "numeric"
      });
    }

    return value;
  }

  get rowsView() {
    const linkable = !this.disableRowLinks;
    return this.rows.map((row) => ({
      id: row.id,
      linkId: row.linkId || row.id,
      rowClass: linkable
        ? "related-list__tr related-list__tr--link"
        : "related-list__tr",
      cells: (row.cells || []).map((value, index) => ({
        key: `${row.id}-${index}`,
        value: this.formatCell(value, index),
        isLink: index === 0,
        cssClass:
          index === 0
            ? "related-list__td related-list__td--first"
            : "related-list__td"
      }))
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get countLabel() {
    return this.hasMore ? `${this.rows.length}+` : String(this.rows.length);
  }

  get emptyMessage() {
    return `No ${this.cardLabel.toLowerCase()} yet.`;
  }

  handleRowClick(event) {
    if (this.disableRowLinks) {
      return;
    }
    const reference = buildRecordNavigationReference(
      event.currentTarget.dataset.link,
      this.linkObjectApiName || this.relatedObjectApiName
    );
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}