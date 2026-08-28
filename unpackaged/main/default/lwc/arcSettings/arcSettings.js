/**
 * Author: Claude
 *
 * Settings / My Details (Figma 758:116625). Reads and writes the running user
 * through the UI API, so the screen needs no Apex of its own.
 */
import { LightningElement, api, track, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { getRecord, getFieldValue, updateRecord } from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import LightningToast from "lightning/toast";
import USER_ID from "@salesforce/user/Id";
import USER_OBJECT from "@salesforce/schema/User";
import COUNTRY_CODE_FIELD from "@salesforce/schema/User.CountryCode";
import ARC_ICONS from "@salesforce/resourceUrl/arcicon";
import loadNotificationPreferences from "@salesforce/apex/ArcSettingsController.loadNotificationPreferences";
import saveNotificationPreferences from "@salesforce/apex/ArcSettingsController.saveNotificationPreferences";

/* Written long-hand so the wire's field list is statically analysable. */
const FIELDS = [
  "User.FirstName",
  "User.LastName",
  "User.Email",
  "User.Title",
  "User.CountryCode",
  "User.AboutMe",
  "User.FullPhotoUrl"
];

/** The editable fields, in the order the form draws them. */
const EDITABLE = [
  "FirstName",
  "LastName",
  "Email",
  "Title",
  "CountryCode",
  "AboutMe"
];

/**
 * Phosphor glyphs painted as CSS masks over currentColor. The static-resource
 * path is only known at runtime, so the URLs are published as custom properties
 * on the host rather than hard-coded in the stylesheet.
 */
const ICON_FILES = {
  envelope: "envelope",
  caret: "caret-down"
};

/* The frame draws "320 characters left" against an empty box (758:116684). */
const BIO_LIMIT = 320;

/* User has no record types; the UI API answers CountryCode on the master id. */
const MASTER_RECORD_TYPE_ID = "012000000000000AAA";

/* The four segments of 758:116751, and the only channels Apex will store. */
const CHANNELS = [
  { value: "all", label: "All" },
  { value: "email", label: "Email" },
  { value: "in-app", label: "In App" },
  { value: "none", label: "None" }
];

/* The frame draws every segment unselected, so a row with nothing stored shows
   no choice rather than assuming one on the user's behalf. */
const DEFAULT_CHANNEL = "";

/** The two groups of 758:116742, in the order the frame draws them. */
const NOTIFICATION_GROUPS = [
  {
    key: "general",
    label: "General notifications",
    help: "General notifications keep you updated on key account events and activities.",
    rows: [
      { key: "new-messages", label: "New messages" },
      { key: "account-activity", label: "Account activity" },
      { key: "mentions-in-discussions", label: "Mentions in discussions" },
      { key: "application-updates", label: "Application updates" }
    ]
  },
  {
    key: "summary",
    label: "Summary notifications",
    help: "Summary notifications provide a concise overview of your recent activities and updates.",
    rows: [
      { key: "daily-activity-summary", label: "Daily activity summary" },
      { key: "weekly-progress-report", label: "Weekly progress report" },
      { key: "monthly-billing-summary", label: "Monthly billing summary" },
      { key: "event-reminder-summary", label: "Event reminder summary" }
    ]
  }
];

export default class ArcSettings extends LightningElement {
  @api title = "Settings";
  @api tagline = "Additional info text goes here.";
  @api uploadHint = "SVG, PNG, JPG or GIF (max. 800×400px)";

  @track draft = {};
  savedDraft = {};
  activeTab = "my-details";
  _tabAppliedFromUrl = false;

  @wire(CurrentPageReference)
  wiredPageRef(pageRef) {
    if (this._tabAppliedFromUrl) {
      return;
    }
    const requested = pageRef?.state?.c__tab;
    if (requested && this.tabs.some((tab) => tab.value === requested)) {
      this.activeTab = requested;
    }
    this._tabAppliedFromUrl = true;
  }

  isSaving = false;
  isDragging = false;
  errorMessage = "";
  /** Notification key to channel, as stored on User_Preference__c. */
  @track channels = {};
  notificationError = "";

  /*
   * Profile, Billing and Email are deliberately absent. Profile duplicated My
   * Details, and Billing and Email were never built — each only ever rendered
   * the "not been built yet" placeholder. Plan is now Version, which describes
   * which edition of the app the user is on.
   */
  tabs = [
    { value: "my-details", label: "My Details" },
    { value: "password", label: "Password" },
    { value: "team", label: "Team" },
    { value: "version", label: "Version" },
    { value: "notifications", label: "Notifications" }
  ];

  connectedCallback() {
    this.applyIconVariables();
  }

  applyIconVariables() {
    Object.entries(ICON_FILES).forEach(([key, file]) => {
      this.style.setProperty(
        `--set-icon-${key}`,
        `url('${ARC_ICONS}/${file}.svg')`
      );
    });
  }

  @wire(getRecord, { recordId: USER_ID, fields: FIELDS })
  wiredUser(result) {
    this.wiredUserResult = result;
    const { data, error } = result;
    if (data) {
      const values = {};
      EDITABLE.forEach((name) => {
        values[name] = getFieldValue(data, `User.${name}`) ?? "";
      });
      this.draft = { ...values };
      this.savedDraft = { ...values };
      this.errorMessage = "";
    } else if (error) {
      this.errorMessage = this.readError(error, "Unable to load your details.");
    }
  }

  @wire(getObjectInfo, { objectApiName: USER_OBJECT })
  userObjectInfo;

  /**
   * User carries no record types, so getObjectInfo returns no default and the
   * picklist wire would never configure. The master id stands in, which is what
   * the UI API answers CountryCode on.
   */
  get countryRecordTypeId() {
    return (
      this.userObjectInfo?.data?.defaultRecordTypeId || MASTER_RECORD_TYPE_ID
    );
  }

  @wire(getPicklistValues, {
    recordTypeId: "$countryRecordTypeId",
    fieldApiName: COUNTRY_CODE_FIELD
  })
  countryPicklist;

  get countryOptions() {
    const values = this.countryPicklist?.data?.values || [];
    return values.map((entry) => ({
      label: entry.label,
      value: entry.value,
      isSelected: entry.value === this.draft.CountryCode
    }));
  }

  get photoUrl() {
    return getFieldValue(this.wiredUserResult?.data, "User.FullPhotoUrl") || "";
  }

  get initials() {
    return [this.draft.FirstName, this.draft.LastName]
      .filter(Boolean)
      .map((part) => String(part).trim().charAt(0).toUpperCase())
      .join("");
  }

  get bioLimit() {
    return BIO_LIMIT;
  }

  get charactersLeftLabel() {
    const used = (this.draft.AboutMe || "").length;
    return `${Math.max(BIO_LIMIT - used, 0)} characters left`;
  }

  get isMyDetails() {
    return this.activeTab === "my-details";
  }

  /* ---- Notifications (758:116730) ---------------------------------------- */

  get isTeam() {
    return this.activeTab === "team";
  }

  get isPassword() {
    return this.activeTab === "password";
  }

  get isVersion() {
    return this.activeTab === "version";
  }

  get isNotifications() {
    return this.activeTab === "notifications";
  }

  get notificationGroups() {
    return NOTIFICATION_GROUPS.map((group) => ({
      ...group,
      rows: group.rows.map((row) => {
        const selected = this.channels[row.key] || DEFAULT_CHANNEL;
        return {
          ...row,
          choices: CHANNELS.map((channel) => ({
            ...channel,
            isSelected: channel.value === selected,
            cssClass:
              channel.value === selected
                ? "settings-segment__button settings-segment__button--active"
                : "settings-segment__button"
          }))
        };
      })
    }));
  }

  @wire(loadNotificationPreferences)
  wiredPreferences({ data, error }) {
    if (data) {
      try {
        this.channels = { ...JSON.parse(data) };
        this.notificationError = "";
      } catch {
        this.notificationError =
          "Saved notification preferences could not be read.";
      }
    } else if (error) {
      this.notificationError = this.readError(
        error,
        "Unable to load your notification preferences."
      );
    }
  }

  /**
   * The frame gives this tab no Save button, so a choice is written as soon as
   * it is made. The row is repainted first and rolled back only if Apex refuses,
   * so the segment never lags the click.
   */
  async handleChannelClick(event) {
    const { row, channel } = event.currentTarget.dataset;
    if (!row || !channel || this.channels[row] === channel) {
      return;
    }

    const previous = { ...this.channels };
    this.channels = { ...this.channels, [row]: channel };
    this.notificationError = "";

    try {
      await saveNotificationPreferences({
        state: JSON.stringify(this.channels)
      });
    } catch (error) {
      this.channels = previous;
      this.notificationError = this.readError(
        error,
        "Unable to save your notification preferences."
      );
    }
  }

  get activeTabLabel() {
    return this.tabs.find((tab) => tab.value === this.activeTab)?.label || "";
  }

  get dropZoneClass() {
    return this.isDragging
      ? "settings-upload settings-upload--dragging"
      : "settings-upload";
  }

  get hasChanges() {
    return EDITABLE.some(
      (name) => (this.draft[name] || "") !== (this.savedDraft[name] || "")
    );
  }

  get isSaveDisabled() {
    return this.isSaving || !this.hasChanges;
  }

  handleTabChange(event) {
    const value = event.detail?.value ?? event.detail;
    if (value) {
      this.activeTab = value;
    }
  }

  /**
   * My Details' "Change password" and the avatar menu's item lead to the same
   * place: the Password tab. Switched locally instead of navigating to
   * /settings?c__tab=password, because this component already owns that tab —
   * a reload would throw away an unsaved My Details draft to arrive exactly
   * where setting activeTab gets us. ds-tabs takes selected={activeTab}, so
   * the tab strip follows on its own.
   */
  handleChangePassword() {
    this.activeTab = "password";
  }

  handleInput(event) {
    const field = event.target.dataset.field;
    if (field) {
      this.draft = { ...this.draft, [field]: event.target.value };
    }
  }

  /* Keeps the remaining-characters count live while typing. */
  handleBioInput(event) {
    this.draft = { ...this.draft, AboutMe: event.target.value };
  }

  handleBrowseClick() {
    this.template.querySelector(".settings-upload__input")?.click();
  }

  handleDragOver(event) {
    event.preventDefault();
    this.isDragging = true;
  }

  handleDragLeave() {
    this.isDragging = false;
  }

  handleDrop(event) {
    event.preventDefault();
    this.isDragging = false;
    this.reportPhoto(event.dataTransfer?.files?.[0]);
  }

  handleFileChange(event) {
    this.reportPhoto(event.target.files?.[0]);
  }

  /**
   * Setting a Chatter profile photo goes through ConnectApi, which needs Apex
   * this component does not have. The file is announced so the surface can take
   * it, and the user is told rather than left with a dead control.
   */
  reportPhoto(file) {
    if (!file) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("photoselected", {
        detail: { name: file.name, size: file.size, type: file.type },
        bubbles: true,
        composed: true
      })
    );
    this.showToast(
      "Photo not saved",
      `${file.name} selected. Uploading a profile photo is not wired up yet.`,
      "info"
    );
  }

  handleCancel() {
    this.draft = { ...this.savedDraft };
    this.errorMessage = "";
  }

  async handleSave() {
    if (this.isSaveDisabled) {
      return;
    }

    this.isSaving = true;
    this.errorMessage = "";

    const fields = { Id: USER_ID };
    EDITABLE.forEach((name) => {
      fields[name] = this.draft[name] || null;
    });

    try {
      await updateRecord({ fields });
      this.savedDraft = { ...this.draft };
      this.showToast(
        "Details saved",
        "Your personal info has been updated.",
        "success"
      );
    } catch (error) {
      this.errorMessage = this.readError(error, "Unable to save your details.");
      this.showToast("Save failed", this.errorMessage, "error");
    } finally {
      this.isSaving = false;
    }
  }

  readError(error, fallback) {
    return (
      error?.body?.message ||
      error?.body?.output?.errors?.[0]?.message ||
      error?.message ||
      fallback
    );
  }

  showToast(label, message, variant) {
    LightningToast.show({ label, message, variant }, this);
  }
}