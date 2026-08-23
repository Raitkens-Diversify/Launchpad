import { LightningElement, api } from "lwc";

// Overflow menu options — mirror the envelopes list row menu (envelopeListV2).
const MENU_ACTIONS = [
  { label: "Rename", name: "rename", iconName: "utility:edit" },
  { label: "Delete", name: "delete", iconName: "utility:delete" }
];

/**
 * Author: Mile Cacanovic
 *
 * envelopeContentHeaderV2 — presentational content-area header for envelopeShellV2.
 * Renders the envelope title + household subtitle and the header actions
 * (Review Missing Items, Manage Documents, overflow menu)
 */
export default class EnvelopeContentHeaderV2 extends LightningElement {
  @api title = "";
  @api subtitle = "";
  // True while at least one action still owes inputs; the shell drives this from
  // its missing-items projection.
  @api hasMissingItems = false;
  // True while the envelope has at least one required document; the shell drives this
  // from its DocumentService read. Gates the Manage Documents action.
  @api hasRequiredDocuments = false;

  menuActions = MENU_ACTIONS;

  // "Review Missing Items" is meaningful only while something is actually missing —
  // when everything is complete the screen would be empty, so the button is disabled.
  get reviewDisabled() {
    return !this.hasMissingItems;
  }

  // Manage Documents is meaningful only while the envelope requires documents — with
  // none required the screen would be empty, so the button stays disabled until then.
  get manageDocumentsDisabled() {
    return !this.hasRequiredDocuments;
  }

  handleActionClick(event) {
    const action = event.currentTarget.dataset.action;
    this.dispatchEvent(new CustomEvent("headeraction", { detail: { action } }));
  }

  handleMenuSelect(event) {
    const action = event.detail.value;
    this.dispatchEvent(new CustomEvent("headeraction", { detail: { action } }));
  }
}