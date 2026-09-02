/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 *
 * arcHomeHeader
 *
 * Dashboard welcome bar: greeting + today's date on the left, quick-action
 * buttons on the right. Typography follows Figma Titles/font-scale-4 (serif
 * title) and text-base (sans date).
 *
 * Greeting uses the running user's FirstName from @salesforce/user/Id context.
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import { getRecord } from "lightning/uiRecordApi";
import { loadStyle } from "lightning/platformResourceLoader";
import USER_ID from "@salesforce/user/Id";
import USER_FIRST_NAME from "@salesforce/schema/User.FirstName";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

const ACTION_ENVELOPE_WIZARD = "envelope-wizard";
const ACTION_NEW_CASE = "new-case";
const ACTION_CHECK_LOG = "check-log";

const SITE_BASE = (communityBasePath || "").replace(/\/$/, "");
const ENVELOPE_WIZARD_PATH = `${SITE_BASE}/envelope`;

/** Actions that only go somewhere, keyed by the action they answer to. */
const NAVIGATION_PATHS = Object.freeze({
  [ACTION_ENVELOPE_WIZARD]: ENVELOPE_WIZARD_PATH
});

const LOG_A_CHECK_DIALOG = Object.freeze({
  flowName: "ARC_Log_a_Check",
  title: "Log a Check",
  size: "large"
});

const ADVERTISING_REVIEW_DIALOG = Object.freeze({
  flowName: "ARC_Advertising_Review",
  title: "Advertising Review Request",
  size: "large"
});

const DEFAULT_ACTIONS = Object.freeze([
  { key: ACTION_ENVELOPE_WIZARD, label: "Envelope Wizard" },
  { key: ACTION_NEW_CASE, label: "New Advertising Request" },
  { key: ACTION_CHECK_LOG, label: "Check Log" }
]);

export default class ArcHomeHeader extends NavigationMixin(LightningElement) {
  /** Retained for Experience Builder page binding; not used for the greeting. */
  @api userName;

  userFirstName = "";
  _stylesLoaded = false;

  connectedCallback() {
    if (this._stylesLoaded) {
      return;
    }

    loadStyle(this, diversifyStyles)
      .then(() => {
        this._stylesLoaded = true;
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[arcHomeHeader] Failed to load diversifyStyles", error);
      });
  }

  @wire(getRecord, { recordId: USER_ID, fields: [USER_FIRST_NAME] })
  wiredUser({ data, error }) {
    if (data) {
      this.userFirstName = data.fields.FirstName.value || "";
      return;
    }

    if (error) {
      // eslint-disable-next-line no-console
      console.error("[arcHomeHeader] Failed to load user record", error);
    }
  }

  get welcomeTitle() {
    const name = (this.userFirstName || "there").trim();
    return `Welcome, ${name}`;
  }

  get formattedDate() {
    return new Intl.DateTimeFormat("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric"
    }).format(new Date());
  }

  get actionButtons() {
    return DEFAULT_ACTIONS;
  }

  flowModalMounted = false;
  _pendingFlowConfig = null;

  renderedCallback() {
    if (this._pendingFlowConfig && this.refs.homeFlowModal) {
      const config = this._pendingFlowConfig;
      this._pendingFlowConfig = null;
      this.refs.homeFlowModal.open(config);
    }
  }

  /**
   * Mount the flow dialog on demand and open it: the flow runtime injects
   * global styling hooks document-wide, so it stays unloaded until used. Once
   * mounted, open directly -- a pending flag alone re-renders nothing.
   */
  openFlowDialog(config) {
    if (this.flowModalMounted) {
      this.refs.homeFlowModal?.open(config);
      return;
    }
    this.flowModalMounted = true;
    this._pendingFlowConfig = config;
  }

  handleActionClick(event) {
    this.runAction(event.currentTarget.dataset.action);
  }

  handleActionKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.runAction(event.currentTarget.dataset.action);
  }

  runAction(action) {
    const path = NAVIGATION_PATHS[action];
    if (path) {
      this.navigateToPath(path);
      return;
    }

    // Both header actions run launchpad experiences as their ARC-site flow
    // copies: New Advertising Request is the Advertising_Review tab's flow,
    // Check Log is the Log a Check quick action's. The Check Log list stays
    // reachable from the sidebar's Check Log item.
    if (action === ACTION_NEW_CASE) {
      this.openFlowDialog(ADVERTISING_REVIEW_DIALOG);
      return;
    }

    if (action === ACTION_CHECK_LOG) {
      this.openFlowDialog(LOG_A_CHECK_DIALOG);
      return;
    }

    this.dispatchAction(action);
  }

  navigateToPath(url) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url }
    });
  }

  dispatchAction(action) {
    if (!action) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent("actionclick", {
        detail: { action },
        bubbles: true,
        composed: true
      })
    );
  }
}