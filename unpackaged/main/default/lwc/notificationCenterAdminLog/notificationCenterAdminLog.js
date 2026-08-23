/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 *
 * Standalone Salesforce tab shell for the admin notification delivery log.
 */
import { LightningElement, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import USER_PROFILE_NAME from "@salesforce/schema/User.Profile.Name";
import USER_ID from "@salesforce/user/Id";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

let diversifyStylesLoadPromise;

const SYSTEM_ADMINISTRATOR_PROFILE = "System Administrator";

const ensureDiversifyStyles = (host) => {
  if (!diversifyStylesLoadPromise) {
    diversifyStylesLoadPromise = loadStyle(host, diversifyStyles).catch((error) => {
      diversifyStylesLoadPromise = undefined;
      throw error;
    });
  }

  return diversifyStylesLoadPromise;
};

export default class NotificationCenterAdminLog extends LightningElement {
  userId = USER_ID;
  stylesLoaded = false;
  stylesLoadError = "";
  isViewLoading = true;

  connectedCallback() {
    if (this.stylesLoaded) {
      return;
    }

    ensureDiversifyStyles(this)
      .then(() => {
        this.stylesLoaded = true;
        this.stylesLoadError = "";
      })
      .catch((error) => {
        this.stylesLoadError =
          "Unable to load Notification Center styles. Refresh the page and try again.";
        // eslint-disable-next-line no-console
        console.error("[notificationCenterAdminLog] Failed to load diversifyStyles", error);
      });
  }

  @wire(getRecord, { recordId: "$userId", fields: [USER_PROFILE_NAME] })
  userRecord;

  get isAppReady() {
    return this.stylesLoaded && Boolean(this.userRecord?.data);
  }

  get showInitialSkeleton() {
    return !this.isAppReady && !this.stylesLoadError;
  }

  handleNotificationCenterViewReady = () => {
    this.isViewLoading = false;
  };

  get isSystemAdministrator() {
    return (
      getFieldValue(this.userRecord?.data, USER_PROFILE_NAME) ===
      SYSTEM_ADMINISTRATOR_PROFILE
    );
  }
}