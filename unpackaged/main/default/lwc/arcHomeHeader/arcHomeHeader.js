/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import { getRecord } from "lightning/uiRecordApi";
import { loadStyle } from "lightning/platformResourceLoader";
import USER_ID from "@salesforce/user/Id";
import USER_FIRST_NAME from "@salesforce/schema/User.FirstName";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import { isValidSalesforceRecordId } from "c/recordNavigationUtils";

const ACTION_ENVELOPE_WIZARD = "envelope-wizard";
const ACTION_LOG_A_CHECK = "log-a-check";
const ACTION_ADVERTISING_REVIEW = "advertising-review";
const ENVELOPE_WIZARD_PATH = `${(communityBasePath || "").replace(/\/$/, "")}/envelope`;
const FLOW_ADVERTISING_REVIEW = "Advertising_Review";
const FLOW_LOG_A_CHECK = "Log_a_Check";
const FLOW_FINISHED_STATUSES = new Set(["FINISHED", "FINISHED_SCREEN"]);

const ACTION_HANDLERS = Object.freeze({
  NAVIGATION: "navigation",
  FLOW: "flow",
});

const ACTION_CONFIG = Object.freeze({
  [ACTION_ENVELOPE_WIZARD]: {
    label: "Envelope Wizard",
    handler: ACTION_HANDLERS.NAVIGATION,
    url: ENVELOPE_WIZARD_PATH,
  },
  [ACTION_LOG_A_CHECK]: {
    label: "Log a Check",
    handler: ACTION_HANDLERS.FLOW,
    flowName: FLOW_LOG_A_CHECK,
    title: "Log a Check",
  },
  [ACTION_ADVERTISING_REVIEW]: {
    label: "Advertising Review Request",
    handler: ACTION_HANDLERS.FLOW,
    flowName: FLOW_ADVERTISING_REVIEW,
    title: "Advertising Review Request",
  },
});

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

  get userRecordId() {
    return isValidSalesforceRecordId(USER_ID) ? USER_ID : undefined;
  }

  @wire(getRecord, { recordId: "$userRecordId", fields: [USER_FIRST_NAME] })
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
      year: "numeric",
    }).format(new Date());
  }

  get actionButtons() {
    return Object.entries(ACTION_CONFIG).map(([key, config]) => ({
      key,
      label: config.label,
    }));
  }

  handleActionClick(event) {
    this.executeAction(event.currentTarget.dataset.action);
  }

  handleActionKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.executeAction(event.currentTarget.dataset.action);
  }

  executeAction(action) {
    const config = ACTION_CONFIG[action];

    if (!config) {
      this.dispatchAction(action);
      return;
    }

    if (config.handler === ACTION_HANDLERS.NAVIGATION) {
      this.navigateToUrl(config.url);
      return;
    }

    if (config.handler === ACTION_HANDLERS.FLOW) {
      this.openFlowModal(config);
      return;
    }

    this.dispatchAction(action);
  }

  openFlowModal({ flowName, title, subtitle, params }) {
    this.refs.flowModal?.open({
      flowName,
      title,
      subtitle,
      params,
    });
  }

  handleFlowStatusChange(event) {
    const { status } = event.detail || {};

    if (!FLOW_FINISHED_STATUSES.has(status)) {
      return;
    }

    this.refs.flowModal?.close();
  }

  navigateToUrl(url) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url },
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
        composed: true,
      })
    );
  }
}