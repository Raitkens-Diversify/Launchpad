/**
 * Relationships section for an Account (Individual/Trust/Estate/Business),
 * grouped by role -- Trusted Contact, Trustee, Grantor, Executor, Control
 * Person, Beneficial Owner, Authorized Person -- via
 * ArcAccountRelationshipsController, which is not scoped to any one
 * household. Renders nothing (not even an empty card) for account types
 * this tab doesn't cover, e.g. Household -- Apex signals that with an
 * empty `category`.
 *
 * Same visual language as c/arcHouseholdDetail (Manoj's Details section) --
 * a collapsible <details> card -- but its own component and its own CSS,
 * since shadow DOM means nothing can be shared across the two directly.
 */
import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import {
  resolveRecordIdFromPageReference,
  buildRecordNavigationReference
} from "c/recordNavigationCommunityUtils";
import getRelationships from "@salesforce/apex/ArcAccountRelationshipsController.getRelationships";

const OBJECT_API_NAME = "Account";
const PAGE_SIZE = 5;

export default class ArcAccountRelationships extends NavigationMixin(
  LightningElement
) {
  @api cardTitle = "Relationships";

  recordId;
  errorMessage;
  isLoading = true;
  category = "";

  _groups = [];
  _visibleCounts = {};

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const resolved = resolveRecordIdFromPageReference(pageRef, OBJECT_API_NAME);
    if (resolved && resolved !== this.recordId) {
      this.recordId = resolved;
    }
  }

  @wire(getRelationships, { accountId: "$recordId" })
  wiredRelationships({ data, error }) {
    this.isLoading = false;

    if (data) {
      this.category = data.category || "";
      this._groups = data.groups || [];
      const visibleCounts = {};
      this._groups.forEach((group) => {
        visibleCounts[group.label] = Math.min(PAGE_SIZE, group.rows.length);
      });
      this._visibleCounts = visibleCounts;
      this.errorMessage = undefined;
    } else if (error) {
      this.category = "";
      this._groups = [];
      this.errorMessage =
        error?.body?.message || "Unable to load relationships right now.";
    }
  }

  get showSection() {
    return Boolean(this.category);
  }

  get groupsView() {
    return this._groups.map((group) => {
      const visibleCount = this._visibleCounts[group.label] ?? PAGE_SIZE;
      const rows = group.rows.slice(0, visibleCount);
      return {
        key: group.label,
        label: group.label,
        countLabel: String(group.rows.length),
        hasRows: group.rows.length > 0,
        rows,
        hasMore: group.rows.length > visibleCount
      };
    });
  }

  handleLoadMore(event) {
    const label = event.currentTarget.dataset.group;
    const group = this._groups.find((candidate) => candidate.label === label);
    if (!group) {
      return;
    }

    this._visibleCounts = {
      ...this._visibleCounts,
      [label]: Math.min(
        (this._visibleCounts[label] || PAGE_SIZE) + PAGE_SIZE,
        group.rows.length
      )
    };
  }

  handleRowClick(event) {
    event.preventDefault();
    const relatedAccountId = event.currentTarget.dataset.recordId;
    if (!relatedAccountId) {
      return;
    }

    const reference = buildRecordNavigationReference(
      relatedAccountId,
      OBJECT_API_NAME
    );
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}