/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import USER_ID from "@salesforce/user/Id";
import USER_EMAIL from "@salesforce/schema/User.Email";
import getUserChannelSettings from "@salesforce/apex/NotificationPreferenceController.getUserChannelSettings";
import saveUserChannelSettings from "@salesforce/apex/NotificationPreferenceController.saveUserChannelSettings";
import {
  CHANNEL,
  ICON,
  MODE_ICON,
  getDeliveryBarStyle,
  reduceError
} from "c/notificationCenterUtils";

const DEFAULT_CHANNEL_CONFIG = Object.freeze({
  inApp: {
    immediate: true,
    digest: true
  },
  email: {
    enabled: true,
    immediate: true,
    digest: true,
    htmlFormatted: true
  },
  zoom: {
    enabled: false,
    immediate: false,
    digest: false,
    respectDnd: true,
    username: ""
  }
});

export default class NotificationCenterPreferences extends LightningElement {
  channelConfig = JSON.parse(JSON.stringify(DEFAULT_CHANNEL_CONFIG));
  savedChannelConfig = null;
  isDirty = false;
  icons = ICON;
  modeIcons = MODE_ICON;
  isLoading = true;
  isSaving = false;
  errorMessage = "";
  userId = USER_ID;
  boundBeforeUnloadHandler = this.handleBeforeUnload.bind(this);

  @wire(getRecord, { recordId: "$userId", fields: [USER_EMAIL] })
  userRecord;

  connectedCallback() {
    window.addEventListener("beforeunload", this.boundBeforeUnloadHandler);
    this.loadPreferences();
  }

  disconnectedCallback() {
    window.removeEventListener("beforeunload", this.boundBeforeUnloadHandler);
  }

  @api
  get hasUnsavedChanges() {
    return this.hasPendingChanges();
  }

  @api
  getUnsavedChanges() {
    return this.hasPendingChanges();
  }

  @api
  discardUnsavedChanges() {
    if (!this.savedChannelConfig) {
      this.isDirty = false;
      this.dispatchDirtyStateChange(false);
      return;
    }

    this.channelConfig = JSON.parse(JSON.stringify(this.savedChannelConfig));
    this.isDirty = false;
    this.dispatchDirtyStateChange(false);
  }

  hasPendingChanges() {
    if (this.isLoading) {
      return false;
    }

    if (this.isDirty) {
      return true;
    }

    if (!this.savedChannelConfig) {
      return false;
    }

    return (
      JSON.stringify(this.channelConfig) !== JSON.stringify(this.savedChannelConfig)
    );
  }

  dispatchDirtyStateChange(hasUnsavedChanges = this.hasPendingChanges()) {
    this.isDirty = hasUnsavedChanges;
    this.dispatchEvent(
      new CustomEvent("preferencesdirtychange", {
        bubbles: true,
        composed: true,
        detail: { hasUnsavedChanges }
      })
    );
  }

  get isSaveDisabled() {
    return this.isSaving || !this.hasUnsavedChanges;
  }

  get saveButtonLabel() {
    return this.isSaving ? "Saving..." : "Save Changes";
  }

  handleBeforeUnload(event) {
    if (!this.hasUnsavedChanges) {
      return;
    }

    event.preventDefault();
    event.returnValue = "";
  }

  get userEmail() {
    return getFieldValue(this.userRecord?.data, USER_EMAIL) || "";
  }

  get isEmailDeliveryDisabled() {
    return !this.channelConfig.email.enabled;
  }

  get isZoomDeliveryDisabled() {
    return !this.channelConfig.zoom.enabled;
  }

  get emailAddress() {
    return this.channelConfig.email.address || this.userEmail;
  }

  get inAppChannelMeta() {
    return getDeliveryBarStyle(CHANNEL.IN_APP);
  }

  get emailChannelMeta() {
    return getDeliveryBarStyle(CHANNEL.EMAIL);
  }

  get zoomChannelMeta() {
    return getDeliveryBarStyle(CHANNEL.ZOOM);
  }

  get zoomUsername() {
    return this.channelConfig.zoom.username || `@${this.userEmail.split("@")[0] || "user"}`;
  }

  get emailRowClass() {
    return this.channelConfig.email.enabled
      ? "delivery-row"
      : "delivery-row delivery-row_disabled";
  }

  get zoomRowClass() {
    return this.channelConfig.zoom.enabled
      ? "delivery-row"
      : "delivery-row delivery-row_disabled";
  }

  get inAppImmediateToggleClass() {
    return this.buildToggleClass(this.channelConfig.inApp.immediate);
  }

  get inAppDigestToggleClass() {
    return this.buildToggleClass(this.channelConfig.inApp.digest);
  }

  get emailEnabledToggleClass() {
    return this.buildToggleClass(this.channelConfig.email.enabled);
  }

  get emailImmediateToggleClass() {
    return this.buildToggleClass(
      this.channelConfig.email.immediate,
      this.isEmailDeliveryDisabled
    );
  }

  get emailDigestToggleClass() {
    return this.buildToggleClass(
      this.channelConfig.email.digest,
      this.isEmailDeliveryDisabled
    );
  }

  get zoomEnabledToggleClass() {
    return this.buildToggleClass(this.channelConfig.zoom.enabled);
  }

  get zoomImmediateToggleClass() {
    return this.buildToggleClass(
      this.channelConfig.zoom.immediate,
      this.isZoomDeliveryDisabled
    );
  }

  get zoomDigestToggleClass() {
    return this.buildToggleClass(
      this.channelConfig.zoom.digest,
      this.isZoomDeliveryDisabled
    );
  }

  buildToggleClass(isOn, isDisabled = false) {
    const classes = ["nc-toggle"];

    if (isOn) {
      classes.push("nc-toggle--on");
    } else {
      classes.push("nc-toggle--off");
    }

    if (isDisabled) {
      classes.push("nc-toggle--disabled");
    }

    return classes.join(" ");
  }

  get emailSettingsClass() {
    return this.channelConfig.email.enabled
      ? "delivery-card"
      : "delivery-card delivery-card_disabled";
  }

  loadPreferences = async ({ silent = false } = {}) => {
    if (!silent) {
      this.isLoading = true;
    }

    this.errorMessage = "";

    try {
      const channelSettings = await getUserChannelSettings();
      this.applyChannelSettings(channelSettings);
    } catch (error) {
      this.errorMessage = reduceError(error);
    } finally {
      if (!silent) {
        this.isLoading = false;
      }
    }
  };

  @api
  refresh() {
    return this.loadPreferences({ silent: true });
  }

  updateChannelConfig(channelConfig) {
    this.channelConfig = channelConfig;
    this.isDirty = true;
    this.dispatchDirtyStateChange(true);
  }

  handleInAppImmediateChange = () => {
    this.updateChannelConfig({
      ...this.channelConfig,
      inApp: {
        ...this.channelConfig.inApp,
        immediate: !this.channelConfig.inApp.immediate
      }
    });
  };

  handleInAppDigestChange = () => {
    this.updateChannelConfig({
      ...this.channelConfig,
      inApp: {
        ...this.channelConfig.inApp,
        digest: !this.channelConfig.inApp.digest
      }
    });
  };

  handleEmailEnabledChange = () => {
    this.updateChannelConfig({
      ...this.channelConfig,
      email: {
        ...this.channelConfig.email,
        enabled: !this.channelConfig.email.enabled
      }
    });
  };

  handleEmailImmediateChange = () => {
    if (this.isEmailDeliveryDisabled) {
      return;
    }

    this.updateChannelConfig({
      ...this.channelConfig,
      email: {
        ...this.channelConfig.email,
        immediate: !this.channelConfig.email.immediate
      }
    });
  };

  handleEmailDigestChange = () => {
    if (this.isEmailDeliveryDisabled) {
      return;
    }

    this.updateChannelConfig({
      ...this.channelConfig,
      email: {
        ...this.channelConfig.email,
        digest: !this.channelConfig.email.digest
      }
    });
  };

  handleZoomEnabledChange = () => {
    this.updateChannelConfig({
      ...this.channelConfig,
      zoom: {
        ...this.channelConfig.zoom,
        enabled: !this.channelConfig.zoom.enabled
      }
    });
  };

  handleZoomImmediateChange = () => {
    if (this.isZoomDeliveryDisabled) {
      return;
    }

    this.updateChannelConfig({
      ...this.channelConfig,
      zoom: {
        ...this.channelConfig.zoom,
        immediate: !this.channelConfig.zoom.immediate
      }
    });
  };

  handleZoomDigestChange = () => {
    if (this.isZoomDeliveryDisabled) {
      return;
    }

    this.updateChannelConfig({
      ...this.channelConfig,
      zoom: {
        ...this.channelConfig.zoom,
        digest: !this.channelConfig.zoom.digest
      }
    });
  };

  applyChannelSettings(settings) {
    if (!settings) {
      return;
    }

    this.channelConfig = {
      inApp: {
        immediate: settings.inAppImmediate ?? true,
        digest: settings.inAppDigest ?? true
      },
      email: {
        enabled: settings.emailEnabled ?? true,
        immediate: settings.emailImmediate ?? true,
        digest: settings.emailDigest ?? true,
        address: settings.emailDeliveryAddress || "",
        htmlFormatted: settings.emailHtmlFormatted ?? true
      },
      zoom: {
        enabled: settings.zoomEnabled ?? false,
        immediate: settings.zoomImmediate ?? false,
        digest: settings.zoomDigest ?? false,
        username: settings.zoomUsername || "",
        respectDnd: settings.zoomRespectDnd ?? true
      }
    };
    this.snapshotSavedState();
  }

  snapshotSavedState() {
    this.savedChannelConfig = JSON.parse(JSON.stringify(this.channelConfig));
    this.isDirty = false;
    this.dispatchDirtyStateChange(false);
  }

  buildChannelSettingsPayload() {
    return {
      emailEnabled: this.channelConfig.email.enabled,
      emailImmediate: this.channelConfig.email.immediate,
      emailDigest: this.channelConfig.email.digest,
      zoomEnabled: this.channelConfig.zoom.enabled,
      zoomImmediate: this.channelConfig.zoom.immediate,
      zoomDigest: this.channelConfig.zoom.digest,
      inAppImmediate: this.channelConfig.inApp.immediate,
      inAppDigest: this.channelConfig.inApp.digest,
      emailDeliveryAddress: this.channelConfig.email.address || null,
      emailHtmlFormatted: this.channelConfig.email.htmlFormatted,
      zoomUsername: this.channelConfig.zoom.username || null,
      zoomRespectDnd: this.channelConfig.zoom.respectDnd
    };
  }

  handleSave = async () => {
    if (this.isSaving) {
      return;
    }

    this.isSaving = true;
    this.errorMessage = "";

    try {
      const savedSettings = await saveUserChannelSettings({
        settings: this.buildChannelSettingsPayload()
      });
      this.applyChannelSettings(savedSettings);
      this.dispatchEvent(
        new CustomEvent("notificationcenterchange", {
          bubbles: true,
          composed: true,
          detail: { source: "channel-preferences" }
        })
      );

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Preferences saved",
          message: "Your notification preferences were updated.",
          variant: "success"
        })
      );
    } catch (error) {
      this.errorMessage = reduceError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to save preferences",
          message: this.errorMessage,
          variant: "error"
        })
      );
    } finally {
      this.isSaving = false;
    }
  };
}