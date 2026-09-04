/**
 * Investments & Services tab content for arcHouseholdDetail: every ISA
 * (Financial_Account__c), Service (Service__c), and Approved Product
 * (Product__c) tied to this record -- see ArcAccountInvestmentsController --
 * as one Name + Type table. Self-contained, embedded only.
 *
 * A single, capped fetch rather than paginated (the controller's own cap is
 * generous), paginated entirely client-side by arcDataTable itself -- same
 * pattern workTable already uses for a similarly bounded, combined list.
 */
import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { resolveRecordIdFromPageReference } from "c/recordNavigationCommunityUtils";
import getInvestmentsAndServices from "@salesforce/apex/ArcAccountInvestmentsController.getInvestmentsAndServices";

const OBJECT_API_NAME = "Account";
const PAGE_SIZE = 10;

const COLUMNS = [
  { label: "Name", fieldName: "name", type: "text", sortable: true, sortType: "text", isLink: true },
  { label: "Type", fieldName: "typeLabel", type: "text", sortable: true, sortType: "text" }
];

export default class ArcAccountInvestmentsList extends LightningElement {
  columns = COLUMNS;
  pageSize = PAGE_SIZE;
  rows = [];
  isLoading = true;
  errorMessage = "";
  recordId;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const next = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
    if (next && next !== this.recordId) {
      this.recordId = next;
      this.load();
    }
  }

  load() {
    this.isLoading = true;
    getInvestmentsAndServices({ accountId: this.recordId })
      .then((rows) => {
        this.rows = (rows || []).map((row) => ({
          id: row.id,
          objectApiName: row.objectApiName,
          name: row.name,
          typeLabel: row.typeLabel
        }));
        this.errorMessage = "";
      })
      .catch((error) => {
        this.errorMessage =
          error?.body?.message || "Unable to load investments and services.";
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.errorMessage && !this.hasRows;
  }
}