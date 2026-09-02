/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { isValidSalesforceRecordId } from "c/recordNavigationUtils";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { loadStyle } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getNotificationRules from "@salesforce/apex/NotificationCenterController.getNotificationRules";
import getSystemDefaultRules from "@salesforce/apex/NotificationCenterController.getSystemDefaultRules";
import saveNotificationRule from "@salesforce/apex/NotificationCenterController.saveNotificationRule";
import saveSystemDefaultRule from "@salesforce/apex/NotificationCenterController.saveSystemDefaultRule";
import toggleNotificationRule from "@salesforce/apex/NotificationCenterController.toggleNotificationRule";
import deleteNotificationRule from "@salesforce/apex/NotificationCenterController.deleteNotificationRule";
import deleteSystemDefaultRule from "@salesforce/apex/NotificationCenterController.deleteSystemDefaultRule";
import getDigestTimezoneLabel from "@salesforce/apex/NotificationCenterController.getDigestTimezoneLabel";
import getChannelOptions from "@salesforce/apex/NotificationPreferenceController.getChannelOptions";
import ACCOUNT_OBJECT from "@salesforce/schema/Account";
import ACCOUNT_NAME_FIELD from "@salesforce/schema/Account.Name";
import ACCOUNT_RECORD_TYPE_FIELD from "@salesforce/schema/Account.RecordType.DeveloperName";
import {
  DEFAULT_RULE_FORM,
  DIGEST_FREQUENCY,
  buildDigestFrequencyHourOptions,
  DIGEST_FREQUENCY_OPTIONS,
  FREQUENCY,
  FREQUENCY_OPTIONS,
  buildHouseholdFilter,
  HOUSEHOLD_MATCHING_INFO,
  isHouseholdRecordType,
  resolveHouseholdRecordTypeIds,
  OBJECT_TYPE_OPTIONS,
  buildDefaultRuleName,
  DUPLICATE_RULE_CONFIRM,
  findDuplicateRules,
  getDuplicateRuleNames,
  buildChannelPills,
  getChannelIcon,
  getChannelIconWrapClass,
  getSelectTileClass,
  ICON,
  matchesRuleSearch,
  MODE_ICON,
  isDigestFrequency,
  isDailyDigestFrequency,
  isChannelSelectableForDeliveryMode,
  resolveImmediateDefaultChannels,
  resolveDigestDefaultChannels,
  sanitizeChannelsForDeliveryMode,
  reduceError,
  sortChannelOptions,
  dispatchNotificationCenterViewReady
} from "c/notificationCenterUtils";

const ACCOUNT_FIELDS = [ACCOUNT_NAME_FIELD, ACCOUNT_RECORD_TYPE_FIELD];

export default class NotificationCenterRules extends LightningElement {
  @api variant = "full";
  @api mode = "user";
  @api displayAsCard = false;
  @api embeddedInSection = false;
  @api cardTitle = "Notification Rules";

  _recordId;
  rawRules = [];
  ruleSearchTerm = "";
  isLoading = true;
  isSaving = false;
  isUpdatingRule = false;
  errorMessage = "";
  showModal = false;
  showDuplicateConfirm = false;
  duplicateRuleNames = [];
  pendingSavePayload = null;
  duplicateConfirmCopy = DUPLICATE_RULE_CONFIRM;
  formState = { ...DEFAULT_RULE_FORM };
  channelOptions = [];
  icons = ICON;
  modeIcons = MODE_ICON;
  householdName = "";
  recordTypeDeveloperName = "";
  householdRecordTypeIds = [];
  stylesLoaded = false;
  digestTimezoneLabel = "";
  _initialized = false;
  hasDispatchedViewReady = false;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    const normalized = isValidSalesforceRecordId(value) ? value : null;

    if (normalized === this._recordId) {
      return;
    }

    this._recordId = normalized;

    if (this._initialized) {
      this.loadRules();
    }
  }

  connectedCallback() {
    this.ensureStylesLoaded();
    this.loadRules();
    this._initialized = true;
  }

  get wiredAccountRecordId() {
    return isValidSalesforceRecordId(this._recordId) ? this._recordId : undefined;
  }

  @wire(getRecord, { recordId: "$wiredAccountRecordId", fields: ACCOUNT_FIELDS })
  handleAccountRecord({ data, error }) {
    if (data) {
      this.householdName = getFieldValue(data, ACCOUNT_NAME_FIELD) || "";
      this.recordTypeDeveloperName =
        getFieldValue(data, ACCOUNT_RECORD_TYPE_FIELD) || "";
      return;
    }

    if (error) {
      this.errorMessage = reduceError(error);
    }
  }

  @wire(getChannelOptions)
  handleChannelOptions({ data, error }) {
    if (data) {
      this.channelOptions = data;
    } else if (error) {
      this.errorMessage = reduceError(error);
    }
  }

  @wire(getDigestTimezoneLabel)
  handleDigestTimezoneLabel({ data }) {
    this.digestTimezoneLabel = data || "";
  }

  @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
  handleAccountObjectInfo({ data, error }) {
    if (data) {
      this.householdRecordTypeIds = resolveHouseholdRecordTypeIds(
        data.recordTypeInfos
      );
      return;
    }

    if (error) {
      this.householdRecordTypeIds = [];
    }
  }

  ensureStylesLoaded = () => {
    if (!this.isCompact || this.stylesLoaded) {
      return;
    }

    loadStyle(this, diversifyStyles)
      .then(() => {
        this.stylesLoaded = true;
      })
      .catch((error) => {
        console.error("[notificationCenterRules] Failed to load diversifyStyles", error);
      });
  };

  loadRules = async ({ silent = false } = {}) => {
    if (!silent) {
      this.isLoading = true;
    }

    this.errorMessage = "";

    try {
      this.rawRules = this.isAdminMode
        ? await getSystemDefaultRules()
        : await getNotificationRules({
            householdId: this.isHouseholdContext ? this.recordId : null
          });
    } catch (error) {
      if (!silent) {
        this.rawRules = [];
      }

      this.errorMessage = reduceError(error);
    } finally {
      if (!silent) {
        this.isLoading = false;
        this.dispatchViewReadyOnce();
      }
    }
  };

  dispatchViewReadyOnce() {
    if (this.hasDispatchedViewReady) {
      return;
    }

    this.hasDispatchedViewReady = true;
    dispatchNotificationCenterViewReady(this);
  }

  @api
  refresh() {
    return this.loadRules({ silent: true });
  }

  upsertRawRule = (savedRule) => {
    if (!savedRule?.id) {
      return;
    }

    const rules = [...this.rawRules];
    const index = rules.findIndex((rule) => rule.id === savedRule.id);

    if (index >= 0) {
      rules[index] = savedRule;
    } else {
      rules.push(savedRule);
    }

    this.rawRules = rules;
  };

  removeRawRule = (ruleId) => {
    if (!ruleId) {
      return;
    }

    this.rawRules = this.rawRules.filter((rule) => rule.id !== ruleId);
  };

  dispatchNotificationCenterChange = () => {
    this.dispatchEvent(
      new CustomEvent("notificationcenterchange", {
        bubbles: true,
        composed: true,
        detail: { source: "notification-rules" }
      })
    );
  };

  get isAdminMode() {
    return this.mode === "admin";
  }

  get isUserMode() {
    return !this.isAdminMode;
  }

  get effectiveCardTitle() {
    return this.isAdminMode ? "System Default Rules" : this.cardTitle;
  }

  get newRuleButtonLabel() {
    return this.isAdminMode ? "New System Default" : "New Rule";
  }

  get showHouseholdFields() {
    return this.isUserMode && !this.lockHousehold;
  }

  get showLockedHouseholdField() {
    return this.isUserMode && this.lockHousehold;
  }

  get isCompact() {
    return this.variant === "compact";
  }

  get isHouseholdContext() {
    return Boolean(this.recordId);
  }

  get lockHousehold() {
    return this.isHouseholdContext;
  }

  get viewClass() {
    const classes = this.isCompact
      ? ["rules-view", "rules-view--compact"]
      : ["rules-view"];

    if (this.displayAsCard) {
      classes.push("rules-view--in-card");
    }

    return classes.join(" ");
  }

  get shellClass() {
    return this.displayAsCard ? "slds-card rules-card" : "rules-shell";
  }

  get cardBodyClass() {
    return this.displayAsCard
      ? "slds-card__body slds-card__body_inner rules-card__body"
      : "";
  }

  get showCardHeader() {
    return this.displayAsCard && !this.embeddedInSection;
  }

  get showInlineTitle() {
    return this.isCompact && !this.displayAsCard;
  }

  get showHeaderNewRuleButton() {
    return !this.displayAsCard;
  }

  get showCompactHeader() {
    return this.isCompact && !this.displayAsCard && !this.embeddedInSection;
  }

  get compactHeaderClass() {
    return this.displayAsCard
      ? "rules-view__header rules-view__header--summary-only"
      : "rules-view__header";
  }

  get showFullToolbar() {
    return !this.isCompact && !this.displayAsCard && !this.embeddedInSection;
  }

  get showSummaryToolbar() {
    return !this.isCompact && this.displayAsCard && !this.embeddedInSection;
  }

  get showLegend() {
    return !this.isCompact;
  }

  get showHouseholdInRow() {
    return !this.isCompact;
  }

  get showNonHouseholdMessage() {
    return (
      this.isUserMode &&
      this.isHouseholdContext &&
      this.recordTypeDeveloperName &&
      !isHouseholdRecordType(this.recordTypeDeveloperName)
    );
  }

  get showRulesContent() {
    return !this.showNonHouseholdMessage;
  }

  get showInitialViewSkeleton() {
    return this.isLoading && !this.hasDispatchedViewReady;
  }

  get showRuleSearch() {
    return !this.isAdminMode;
  }

  get lockedHouseholdLabel() {
    return this.householdName || "This household";
  }

  get objectTypeOptions() {
    return OBJECT_TYPE_OPTIONS;
  }

  get frequencyOptions() {
    return FREQUENCY_OPTIONS;
  }

  get digestFrequencyOptions() {
    return DIGEST_FREQUENCY_OPTIONS;
  }

  get digestFrequencyHourOptions() {
    return buildDigestFrequencyHourOptions(this.formState.digestFrequencyHour);
  }

  get showDigestFrequencyField() {
    return isDigestFrequency(this.formState.frequency);
  }

  get showDigestFrequencyHourField() {
    return (
      isDigestFrequency(this.formState.frequency) &&
      isDailyDigestFrequency(this.formState.digestFrequency)
    );
  }

  get digestTimezoneHint() {
    if (!this.showDigestFrequencyField || !this.digestTimezoneLabel) {
      return "";
    }

    return `Digest schedules use the organization timezone: ${this.digestTimezoneLabel}.`;
  }

  get digestDeliveryHourHint() {
    if (!this.showDigestFrequencyHourField || !this.digestTimezoneLabel) {
      return "";
    }

    return `Delivery hour is based on ${this.digestTimezoneLabel}.`;
  }

  get channelSelectionHint() {
    return isDigestFrequency(this.formState.frequency)
      ? "Email digest rules are delivered via Email"
      : "Select one or more";
  }

  get modalTitle() {
    if (this.isAdminMode) {
      return this.formState.id ? "Edit System Default" : "New System Default";
    }

    return this.formState.id ? "Edit Rule" : "New Rule";
  }

  get modalSubtitle() {
    if (this.isAdminMode) {
      return this.formState.id
        ? "Update the org-wide default rule applied to all users."
        : "Create an org-wide default rule applied to all users.";
    }

    return this.formState.id
      ? "Update notification rule settings."
      : "Create a new notification rule.";
  }

  get defaultRuleNamePlaceholder() {
    return buildDefaultRuleName(this.formState.objectType, this.formState.frequency);
  }

  get activeCount() {
    return this.rawRules.filter((rule) => rule.isActive).length;
  }

  get headerSummary() {
    if (this.isCompact) {
      return `${this.activeCount}/${this.rawRules.length} active`;
    }

    return `${this.activeCount} of ${this.rawRules.length} active`;
  }

  get showToolbarSummary() {
    return !this.useGroupedRuleSections;
  }

  get userDefinedSectionSummary() {
    const userRules = this.getUserVisibleRules().filter(
      (rule) => rule.isSystemDefault !== true
    );
    const activeCount = userRules.filter((rule) =>
      this.resolveEffectiveRuleActive(rule)
    ).length;

    return `${activeCount} of ${userRules.length} active`;
  }

  get filteredRules() {
    const visibleRules = this.getUserVisibleRules();

    if (!this.hasActiveRuleSearch) {
      return this.applyRuleFilters(visibleRules);
    }

    const systemDefaults = this.applyRuleFilters(
      visibleRules.filter((rule) => rule.isSystemDefault === true),
      { applySearch: false }
    );
    const userRules = this.applyRuleFilters(
      visibleRules.filter((rule) => rule.isSystemDefault !== true)
    );

    return [...userRules, ...systemDefaults];
  }

  get filteredGlobalUserRules() {
    return this.applyRuleFilters(
      this.getUserVisibleRules().filter(
        (rule) => rule.isSystemDefault !== true && !rule.householdScoped
      )
    );
  }

  get filteredHouseholdRules() {
    return this.applyRuleFilters(
      this.getUserVisibleRules().filter((rule) => this.isHouseholdSpecificRule(rule))
    );
  }

  get filteredSystemDefaultRules() {
    return this.applyRuleFilters(
      this.getUserVisibleRules().filter((rule) => rule.isSystemDefault === true),
      { applySearch: false }
    );
  }

  getUserVisibleRules() {
    return this.rawRules || [];
  }

  isHouseholdSpecificRule(rule) {
    return rule?.isSystemDefault !== true && rule?.householdScoped === true;
  }

  resolveEffectiveRuleActive(rule) {
    return rule?.isActive === true;
  }

  get useGroupedRuleSections() {
    return this.isUserMode && !this.isHouseholdContext && !this.isCompact;
  }

  get ruleSections() {
    if (!this.useGroupedRuleSections) {
      return [
        {
          id: "all",
          showLabel: false,
          label: "",
          description: "",
          rules: this.filteredRules,
          hasRules: this.filteredRules.length > 0,
          emptyMessage: this.getRuleSectionEmptyMessage(
            "No notification rules yet. Create your first rule to get started."
          )
        }
      ];
    }

    return [
      {
        id: "user-defined",
        labelId: "rules-section-user-defined",
        sectionClass: "rules-section div-card div-card--nested",
        showLabel: true,
        label: "User Defined",
        description: "Personal and household rules you create and manage.",
        showActiveSummary: true,
        activeSummary: this.userDefinedSectionSummary,
        showSearchFilterIndicator: this.hasActiveRuleSearch,
        searchFilterTerm: this.trimmedRuleSearchTerm,
        contentBlocks: [
          {
            id: "global",
            blockClass: "rules-subsection",
            showBlockLabel: true,
            blockLabelId: "rules-subsection-global",
            label: "Global",
            description:
              "Personal rules that apply when no household-specific rule is configured.",
            rules: this.filteredGlobalUserRules,
            hasRules: this.filteredGlobalUserRules.length > 0,
            emptyClass: "rules-subsection__empty",
            emptyMessage: this.getRuleSectionEmptyMessage("No global rules yet.", {
              sectionId: "global"
            })
          },
          {
            id: "household",
            blockClass: "rules-subsection",
            showBlockLabel: true,
            blockLabelId: "rules-subsection-household",
            label: "Household",
            description:
              "Rules scoped to individual households. These override global defaults for the linked household.",
            rules: this.filteredHouseholdRules,
            hasRules: this.filteredHouseholdRules.length > 0,
            emptyClass: "rules-subsection__empty",
            emptyMessage: this.getRuleSectionEmptyMessage(
              "No household rules yet. Create a rule to override global defaults for a household.",
              { sectionId: "household" }
            )
          }
        ]
      },
      {
        id: "system-default",
        labelId: "rules-section-system-default",
        sectionClass: "rules-section div-card div-card--nested",
        showLabel: true,
        label: "System Default",
        description:
          "Org-wide defaults managed by your administrator. You can copy them, but not edit, delete, or change their active state.",
        contentBlocks: [
          {
            id: "system-default-rules",
            blockClass: "rules-subsection",
            showBlockLabel: false,
            rules: this.filteredSystemDefaultRules,
            hasRules: this.filteredSystemDefaultRules.length > 0,
            emptyClass: "rules-section__empty",
            emptyMessage: this.getRuleSectionEmptyMessage(
              "No org-wide system defaults are configured yet.",
              { applySearch: false }
            )
          }
        ]
      }
    ];
  }

  get hasActiveRuleSearch() {
    return Boolean(this.ruleSearchTerm?.trim());
  }

  get trimmedRuleSearchTerm() {
    return this.ruleSearchTerm?.trim() || "";
  }

  get rulesEmptyMessage() {
    const userRules = this.rawRules.filter((rule) => rule.isSystemDefault !== true);

    if (this.hasActiveRuleSearch && userRules.length > 0) {
      return `No user-defined rules match "${this.ruleSearchTerm.trim()}".`;
    }

    return "No notification rules yet. Create your first rule to get started.";
  }

  getRuleSectionEmptyMessage(defaultMessage, options = {}) {
    const { applySearch = true, sectionId = null } = options;

    if (!applySearch || !this.hasActiveRuleSearch) {
      return defaultMessage;
    }

    const searchTerm = this.trimmedRuleSearchTerm;

    if (sectionId === "household") {
      const householdRules = this.rawRules.filter((rule) =>
        this.isHouseholdSpecificRule(rule)
      );

      if (householdRules.length > 0) {
        return `No household rules match "${searchTerm}".`;
      }
    }

    if (sectionId === "global") {
      const personalRules = this.rawRules.filter(
        (rule) => rule.isSystemDefault !== true && !rule.householdScoped
      );

      if (personalRules.length > 0) {
        return `No global rules match "${searchTerm}".`;
      }
    }

    const userRules = this.rawRules.filter((rule) => rule.isSystemDefault !== true);

    if (userRules.length > 0) {
      return `No rules match "${searchTerm}".`;
    }

    return defaultMessage;
  }

  get hasRules() {
    if (this.useGroupedRuleSections) {
      return (
        this.filteredSystemDefaultRules.length > 0 ||
        this.filteredGlobalUserRules.length > 0 ||
        this.filteredHouseholdRules.length > 0
      );
    }

    return this.filteredRules.length > 0;
  }

  applyRuleFilters(rules, options = {}) {
    const { applySearch = true } = options;
    let sourceRules = rules;

    if (applySearch && this.hasActiveRuleSearch) {
      sourceRules = sourceRules.filter((rule) =>
        matchesRuleSearch(rule, this.ruleSearchTerm)
      );
    }

    return sourceRules.map((rule) => this.decorateRule(rule));
  }

  get channelToggleRows() {
    const selectedChannels = new Set(this.formState.channels || []);
    const frequency = this.formState.frequency;

    return sortChannelOptions(this.channelOptions || []).map((option) => {
      const isSelected = selectedChannels.has(option.value);
      const isDisabled = !isChannelSelectableForDeliveryMode(frequency, option.value);

      return {
        value: option.value,
        label: option.label,
        icon: getChannelIcon(option.value),
        isSelected,
        isDisabled,
        tileClass: getSelectTileClass(isSelected, isDisabled),
        iconWrapClass: getChannelIconWrapClass(option.value, isSelected),
        ariaPressed: String(isSelected),
        ariaDisabled: String(isDisabled),
        ariaLabel: isDisabled
          ? `${option.label} channel is not available for the selected delivery mode`
          : `${isSelected ? "Deselect" : "Select"} ${option.label} channel`
      };
    });
  }

  get activeToggleClass() {
    const stateClass = this.formState.isActive
      ? "div-toggle div-toggle--on"
      : "div-toggle div-toggle--off";
    const disabledClass = this.isActiveToggleDisabled ? "div-toggle--disabled" : "";

    return ["rule-modal__active-toggle", stateClass, disabledClass]
      .filter(Boolean)
      .join(" ");
  }

  get activeToggleAriaPressed() {
    return String(this.formState.isActive);
  }

  get isActiveToggleDisabled() {
    return false;
  }

  get householdFilter() {
    return buildHouseholdFilter(this.householdRecordTypeIds);
  }

  get householdMatchingInfo() {
    return HOUSEHOLD_MATCHING_INFO;
  }

  get isSaveDisabled() {
    if (
      this.isSaving ||
      this.isUpdatingRule ||
      !(this.formState.channels || []).length
    ) {
      return true;
    }

    if (
      this.showDigestFrequencyHourField &&
      !this.formState.digestFrequencyHour
    ) {
      return true;
    }

    return false;
  }

  get showSavingOverlay() {
    return this.isSaving || this.isUpdatingRule;
  }

  get showModalSavingOverlay() {
    return this.isSaving;
  }

  get showViewSavingOverlay() {
    return this.isUpdatingRule;
  }

  get savingOverlayMessage() {
    if (this.isSaving) {
      return "Saving rule...";
    }

    if (this.isUpdatingRule) {
      return "Updating rule...";
    }

    return "Saving...";
  }

  get saveRuleButtonLabel() {
    return this.isSaving ? "Saving..." : "Save Rule";
  }

  buildLockedHouseholdFormState = (overrides = {}) => ({
    ...DEFAULT_RULE_FORM,
    channels: this.defaultChannels(DEFAULT_RULE_FORM.frequency),
    householdId: this.recordId,
    ...overrides
  });

  handleRuleSearchChange = (event) => {
    this.ruleSearchTerm = event.target.value || "";
  };

  handleClearRuleSearch = () => {
    this.ruleSearchTerm = "";
  };

  handleOpenCreateModal = () => {
    if (this.showSavingOverlay) {
      return;
    }

    const frequency = DEFAULT_RULE_FORM.frequency;

    this.formState = this.lockHousehold
      ? this.buildLockedHouseholdFormState()
      : {
          ...DEFAULT_RULE_FORM,
          channels: this.defaultChannels(frequency)
        };
    this.showModal = true;
  };

  @api
  openCreateModal() {
    this.handleOpenCreateModal();
  }

  handleCloseModal = () => {
    if (this.isSaving) {
      return;
    }

    this.showModal = false;
    this.formState = {
      ...this.formState,
      clonedFromSystemDefaultId: null
    };
    this.handleDuplicateCancel();
  };

  handleEditRule = (event) => {
    const ruleId = event.currentTarget.dataset.ruleId;
    const rule = this.rawRules.find((item) => item.id === ruleId);

    if (!rule || rule.isReadOnly) {
      return;
    }

    this.formState = {
      id: rule.id,
      ruleName: rule.ruleName || "",
      category: rule.category,
      objectType: rule.objectType,
      frequency: rule.frequency,
      digestFrequency: rule.digestFrequency || DIGEST_FREQUENCY.DAILY,
      digestFrequencyHour: rule.digestFrequencyHour || null,
      channels: sanitizeChannelsForDeliveryMode(rule.frequency, rule.channels),
      isActive: rule.isActive,
      householdId: this.lockHousehold ? this.recordId : rule.householdId || null,
      clonedFromSystemDefaultId: null
    };
    this.showModal = true;
  };

  handleCloneRule = (event) => {
    const ruleId = event.currentTarget.dataset.ruleId;
    const rule = this.rawRules.find((item) => item.id === ruleId);

    if (!rule) {
      return;
    }

    const isCloningSystemDefault = rule.isSystemDefault === true;
    const clonedFromSystemDefaultId = isCloningSystemDefault ? rule.id : null;
    const suggestedRuleName =
      isCloningSystemDefault && rule.ruleName ? `Copy of ${rule.ruleName}` : "";

    this.formState = this.lockHousehold
      ? this.buildLockedHouseholdFormState({
          ruleName: suggestedRuleName,
          category: rule.category,
          objectType: rule.objectType,
          frequency: rule.frequency,
          digestFrequency: rule.digestFrequency || DIGEST_FREQUENCY.DAILY,
          digestFrequencyHour: rule.digestFrequencyHour || null,
          channels: sanitizeChannelsForDeliveryMode(rule.frequency, rule.channels),
          isActive: true,
          clonedFromSystemDefaultId
        })
      : {
          id: null,
          ruleName: suggestedRuleName,
          category: rule.category,
          objectType: rule.objectType,
          frequency: rule.frequency,
          digestFrequency: rule.digestFrequency || DIGEST_FREQUENCY.DAILY,
          digestFrequencyHour: rule.digestFrequencyHour || null,
          channels: sanitizeChannelsForDeliveryMode(rule.frequency, rule.channels),
          isActive: true,
          householdId: rule.householdId || null,
          clonedFromSystemDefaultId
        };
    this.showModal = true;
  };

  handleDeleteRule = async (event) => {
    const ruleId = event.currentTarget.dataset.ruleId;
    const rule = this.rawRules.find((item) => item.id === ruleId);

    if (!rule) {
      return;
    }

    const confirmed = window.confirm(
      `Delete "${rule.name}"? This action cannot be undone.`
    );

    if (!confirmed) {
      return;
    }

    try {
      if (this.isAdminMode) {
        await deleteSystemDefaultRule({ ruleId });
      } else {
        await deleteNotificationRule({ ruleId });
      }

      this.removeRawRule(ruleId);
      await this.loadRules({ silent: true });
      this.dispatchNotificationCenterChange();

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Rule deleted",
          variant: "success"
        })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to delete rule",
          message: reduceError(error),
          variant: "error"
        })
      );
    }
  };

  handleActiveToggleClick = () => {
    if (this.isActiveToggleDisabled) {
      return;
    }

    this.formState = {
      ...this.formState,
      isActive: !this.formState.isActive
    };
  };

  handleFormFieldChange = (event) => {
    const fieldName = event.currentTarget.dataset.field;
    const nextValue = event.detail.value;

    if (!fieldName) {
      return;
    }

    const nextFormState = {
      ...this.formState,
      [fieldName]: nextValue
    };

    if (fieldName === "frequency") {
      if (!isDigestFrequency(nextValue)) {
        nextFormState.digestFrequency = DIGEST_FREQUENCY.DAILY;
        nextFormState.digestFrequencyHour = null;
        nextFormState.channels = resolveImmediateDefaultChannels();
      } else {
        nextFormState.channels = resolveDigestDefaultChannels();
      }
    }

    if (
      fieldName === "digestFrequency" &&
      !isDailyDigestFrequency(nextValue)
    ) {
      nextFormState.digestFrequencyHour = null;
    }

    this.formState = nextFormState;
  };

  handleRuleNameChange = (event) => {
    this.formState = {
      ...this.formState,
      ruleName: event.target.value
    };
  };

  handleHouseholdChange = (event) => {
    if (this.lockHousehold) {
      return;
    }

    this.formState = {
      ...this.formState,
      householdId: event.detail.recordId || null
    };
  };

  handleChannelToggle = (event) => {
    const channel = event.currentTarget.dataset.channel;

    if (!isChannelSelectableForDeliveryMode(this.formState.frequency, channel)) {
      return;
    }

    const selectedChannels = new Set(this.formState.channels || []);

    if (selectedChannels.has(channel)) {
      if (selectedChannels.size === 1) {
        return;
      }

      selectedChannels.delete(channel);
    } else {
      selectedChannels.add(channel);
    }

    this.formState = {
      ...this.formState,
      channels: [...selectedChannels]
    };
  };

  handleRuleActiveToggle = async (event) => {
    if (this.showSavingOverlay) {
      return;
    }

    const ruleId = event.currentTarget.dataset.ruleId;
    const rule = this.rawRules.find((item) => item.id === ruleId);

    if (!rule || (rule.isReadOnly && rule.isSystemDefault !== true)) {
      return;
    }

    if (this.isUserMode && rule.isSystemDefault === true) {
      return;
    }

    const isActive = event.currentTarget.dataset.active === "true";
    this.isUpdatingRule = true;

    try {
      const updatedRule = await toggleNotificationRule({ ruleId, isActive: !isActive });
      this.upsertRawRule(updatedRule);
      await this.loadRules({ silent: true });
      this.dispatchNotificationCenterChange();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to update rule",
          message: reduceError(error),
          variant: "error"
        })
      );
    } finally {
      this.isUpdatingRule = false;
    }
  };

  handleSaveRule = async () => {
    const payload = this.buildSavePayload();

    if (this.formState.clonedFromSystemDefaultId) {
      await this.persistRule(payload);
      return;
    }

    const duplicates = findDuplicateRules(this.rawRules, payload, {
      excludeRuleId: this.formState.id
    });

    if (duplicates.length > 0) {
      this.duplicateRuleNames = getDuplicateRuleNames(duplicates);
      this.pendingSavePayload = payload;
      this.showDuplicateConfirm = true;
      return;
    }

    await this.persistRule(payload);
  };

  handleDuplicateConfirm = async () => {
    const payload = this.pendingSavePayload;
    this.pendingSavePayload = null;
    this.duplicateRuleNames = [];
    this.showDuplicateConfirm = false;

    if (!payload) {
      return;
    }

    await this.persistRule(payload);
  };

  handleDuplicateCancel = () => {
    this.showDuplicateConfirm = false;
    this.pendingSavePayload = null;
    this.duplicateRuleNames = [];
  };

  buildSavePayload() {
    return {
      id: this.formState.id,
      ruleName: this.formState.ruleName?.trim() || null,
      category: this.formState.category,
      objectType: this.formState.objectType,
      frequency: this.formState.frequency,
      digestFrequency: this.showDigestFrequencyField
        ? this.formState.digestFrequency
        : null,
      digestFrequencyHour: this.showDigestFrequencyHourField
        ? this.formState.digestFrequencyHour
        : null,
      channels: this.formState.channels,
      isActive: this.formState.isActive,
      householdId: this.isAdminMode
        ? null
        : this.lockHousehold
          ? this.recordId
          : this.formState.householdId || null
    };
  }

  persistRule = async (payload) => {
    this.isSaving = true;

    try {
      const savedRule = this.isAdminMode
        ? await saveSystemDefaultRule({ input: payload })
        : await saveNotificationRule({ input: payload });

      this.showModal = false;
      this.formState = {
        ...this.formState,
        clonedFromSystemDefaultId: null
      };
      this.upsertRawRule(savedRule);
      await this.loadRules({ silent: true });
      this.dispatchNotificationCenterChange();

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Rule saved",
          message: "Notification rule was saved successfully.",
          variant: "success"
        })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to save rule",
          message: reduceError(error),
          variant: "error"
        })
      );
    } finally {
      this.isSaving = false;
    }
  };

  decorateRule(rule) {
    const channelBadges = buildChannelPills(rule.channels || []);
    const isReadOnly = rule.isReadOnly === true;
    const isSystemDefaultLocked = this.isUserMode && rule.isSystemDefault === true;
    const isToggleDisabled =
      isSystemDefaultLocked || (isReadOnly && rule.isSystemDefault !== true);
    const displayIsActive = this.resolveEffectiveRuleActive(rule);
    const isDeletable = this.isAdminMode
      ? true
      : !rule.isSystemDefault && !isReadOnly;
    const isEditable = this.isAdminMode ? true : !isReadOnly;
    const toggleStateClass = displayIsActive
      ? "div-toggle div-toggle--on"
      : "div-toggle div-toggle--off";

    return {
      ...rule,
      isActive: displayIsActive,
      rowClass: displayIsActive ? "rule-card" : "rule-card rule-card--inactive",
      quietHoursLabel: rule.respectQuietHours
        ? "Respects quiet hours"
        : "Overrides quiet hours",
      quietHoursClass: rule.respectQuietHours
        ? "div-meta-strip__quiet-hours"
        : "div-meta-strip__quiet-hours div-meta-strip__quiet-hours--override",
      toggleClass: [toggleStateClass, isToggleDisabled ? "div-toggle--disabled" : ""]
        .filter(Boolean)
        .join(" "),
      toggleAriaPressed: String(displayIsActive),
      isToggleDisabled,
      channelBadges,
      isDeletable,
      isEditable,
      showHouseholdInMeta: this.showHouseholdInRow && rule.householdScoped,
      showSystemDefaultBadge:
        rule.isSystemDefault === true &&
        this.isUserMode &&
        (this.isHouseholdContext || this.isCompact)
    };
  }

  defaultChannels(frequency = this.formState?.frequency || FREQUENCY.IMMEDIATE) {
    if (isDigestFrequency(frequency)) {
      return resolveDigestDefaultChannels();
    }

    return resolveImmediateDefaultChannels();
  }
}