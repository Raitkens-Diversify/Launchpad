import { LightningElement } from "lwc";
import logoUrl from "@salesforce/resourceUrl/DiversifyLogoV2";
import { UPGRADE_REQUESTED_EVENT } from "c/arcNavTrailState";

/**
 * "Upgrade to Helios" informational modal. Always mounted in the theme
 * layout's footer region; opens itself when it hears the window-level
 * arc-upgrade-requested event (dispatched by arcNavigation.js when the user
 * clicks a nav item gated behind the Helios upgrade).
 */
export default class ArcUpgradeModal extends LightningElement {
  isOpen = false;
  logoUrl = logoUrl;

  connectedCallback() {
    this._onUpgradeRequested = () => {
      this.isOpen = true;
    };
    window.addEventListener(UPGRADE_REQUESTED_EVENT, this._onUpgradeRequested);
  }

  disconnectedCallback() {
    window.removeEventListener(
      UPGRADE_REQUESTED_EVENT,
      this._onUpgradeRequested
    );
  }

  handleClose(event) {
    event.stopPropagation();
    this.isOpen = false;
  }
}