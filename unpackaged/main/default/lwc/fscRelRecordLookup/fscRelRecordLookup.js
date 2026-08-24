/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 *
 * SLDS-style lookup with sharing-enforced Apex search and inline create action.
 */
import { LightningElement, api } from "lwc";
import getAccountName from "@salesforce/apex/FscRelHouseholdController.getAccountName";
import getContactName from "@salesforce/apex/FscRelHouseholdController.getContactName";
import getReciprocalRoleName from "@salesforce/apex/FscRelHouseholdController.getReciprocalRoleName";
import getRecordTypeByDeveloperName from "@salesforce/apex/FscRelHouseholdController.getRecordTypeByDeveloperName";
import getCreateableRecordTypes from "@salesforce/apex/FscRelHouseholdController.getCreateableRecordTypes";
import searchAccounts from "@salesforce/apex/FscRelHouseholdController.searchAccounts";
import searchAccountsByClassification from "@salesforce/apex/FscRelHouseholdController.searchAccountsByClassification";
import searchAccountsInScope from "@salesforce/apex/FscRelHouseholdController.searchAccountsInScope";
import getAccountsByIds from "@salesforce/apex/FscRelHouseholdController.getAccountsByIds";
import searchContacts from "@salesforce/apex/FscRelHouseholdController.searchContacts";
import searchReciprocalRoles from "@salesforce/apex/FscRelHouseholdController.searchReciprocalRoles";

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;
const DROPDOWN_MAX_HEIGHT_PX = 220;
const DROPDOWN_MIN_HEIGHT_PX = 80;
const DROPDOWN_FOOTER_HEIGHT_PX = 36;
const DROPDOWN_RECORD_TYPE_ROW_HEIGHT_PX = 32;
const DROPDOWN_VIEWPORT_PADDING_PX = 8;

export default class FscRelRecordLookup extends LightningElement {
  @api objectApiName;
  @api label;
  @api placeholder;
  @api variant;
  @api filter;
  @api matchingFields;
  @api allowedRecordIds = [];
  @api classificationSearchValue = "";
  @api recordTypeId;
  @api disabled;
  @api createEnabled;
  @api createButtonLabel;
  @api createModalLabel;

  _value = "";
  _recordLabel = "";
  _resolvedRecordTypeId = null;
  _resolvedIsPersonType = null;
  _recordTypeLoadStarted = false;
  _recordTypeDeveloperName = "";
  _instanceId = "";
  selectedLabel = "";
  searchTerm = "";
  searchResults = [];
  isOpen = false;
  isLoading = false;
  isEditing = false;

  _searchDebounceTimer;
  _outsideClickHandler;
  _globalOpenHandler;
  _globalCloseHandler;
  _dropdownRepositionHandler;
  _dropdownPositionBound = false;
  _needsDropdownPosition = false;
  _dropdownStyle = "";
  _dropdownOpensAbove = false;
  _isDropdownPointerDown = false;
  _createRecordTypeOptions = [];
  _createRecordTypesLoadPromise = null;
  isCreateRecordTypeMenuOpen = false;

  @api
  get value() {
    return this._value;
  }

  set value(recordId) {
    const normalized = recordId || "";
    if (normalized !== this._value) {
      this._value = normalized;
      this.syncSelectedLabel();
    }
  }

  @api
  get recordLabel() {
    return this._recordLabel;
  }

  set recordLabel(label) {
    const normalized = (label || "").trim();
    if (normalized === this._recordLabel) {
      return;
    }

    this._recordLabel = normalized;
    this.syncSelectedLabel();
  }

  @api
  applySelection(recordId, label) {
    const normalizedId = recordId || "";
    const normalizedLabel = (label || "").trim();

    this._value = normalizedId;
    this._recordLabel = normalizedLabel;
    this.selectedLabel = normalizedLabel;
    this.isEditing = false;
    this.closeDropdown();
  }

  syncSelectedLabel() {
    if (!this._value) {
      this.selectedLabel = "";
      return;
    }

    if (this._recordLabel) {
      this.selectedLabel = this._recordLabel;
      return;
    }

    this.loadSelectedLabel(this._value);
  }

  get isContactLookup() {
    return this.objectApiName === "Contact";
  }

  get isReciprocalRoleLookup() {
    return this.objectApiName === "Reciprocal_Role__c";
  }

  get isAccountLookupWithScope() {
    return this.objectApiName === "Account" && this.hasAllowedRecordIds;
  }

  get isClassificationAccountSearch() {
    return (
      this.objectApiName === "Account" &&
      Boolean(String(this.classificationSearchValue || "").trim())
    );
  }

  get lookupIconName() {
    if (this.isContactLookup) {
      return "standard:contact";
    }

    if (this.isReciprocalRoleLookup) {
      return "custom:custom18";
    }

    return "standard:account";
  }

  get lookupObjectLabel() {
    if (this.isContactLookup) {
      return "Contact";
    }

    if (this.isReciprocalRoleLookup) {
      return "Reciprocal Role";
    }

    return "Account";
  }

  get emptyResultsMessage() {
    return `No ${this.lookupObjectLabel.toLowerCase()}s found`;
  }

  @api
  get recordTypeDeveloperName() {
    return this._recordTypeDeveloperName;
  }

  set recordTypeDeveloperName(developerName) {
    const normalized = (developerName || "").trim();
    if (normalized === this._recordTypeDeveloperName) {
      return;
    }

    this._recordTypeDeveloperName = normalized;
    this.resetRecordTypeResolution();
    this.loadRecordTypeId();

    if (this.isReciprocalRoleLookup) {
      this.searchResults = [];

      if (this.isOpen) {
        void this.runSearch();
      }
    }
  }

  connectedCallback() {
    this._instanceId = `lookup-${Math.random().toString(36).slice(2)}`;
    this.loadRecordTypeId();
    void this.loadCreateRecordTypes();
    if (this._value) {
      this.syncSelectedLabel();
    }

    this._globalOpenHandler = (event) => {
      if (event.detail?.instanceId !== this._instanceId && this.isOpen) {
        this.closeDropdown();
      }
    };

    this._globalCloseHandler = () => {
      if (this.isOpen) {
        this.closeDropdown();
      }
    };

    this._outsideClickHandler = (event) => {
      if (!this.isOpen) {
        return;
      }

      const path = event.composedPath();
      const dropdown = this.template.querySelector(".lookup__dropdown");
      const clickedInside = path.some((node) => {
        if (node === this.template.host) {
          return true;
        }

        if (node === dropdown) {
          return true;
        }

        return (
          node instanceof Node &&
          this.template.contains(node)
        );
      });

      if (!clickedInside) {
        this.closeDropdown();
      }
    };

    document.addEventListener("fscrellookupopen", this._globalOpenHandler);
    document.addEventListener("fscrellookupclose", this._globalCloseHandler);
    window.addEventListener("mousedown", this._outsideClickHandler, true);
    window.addEventListener("touchstart", this._outsideClickHandler, true);
  }

  disconnectedCallback() {
    if (this._globalOpenHandler) {
      document.removeEventListener("fscrellookupopen", this._globalOpenHandler);
    }

    if (this._globalCloseHandler) {
      document.removeEventListener("fscrellookupclose", this._globalCloseHandler);
    }

    if (this._outsideClickHandler) {
      window.removeEventListener("mousedown", this._outsideClickHandler, true);
      window.removeEventListener("touchstart", this._outsideClickHandler, true);
    }

    if (this._searchDebounceTimer) {
      clearTimeout(this._searchDebounceTimer);
    }

    this.unbindDropdownPositionListeners();
  }

  get isLabelHidden() {
    return this.variant === "label-hidden";
  }

  get displayLabel() {
    return this.label || "Account Name";
  }

  get inputPlaceholder() {
    return this.placeholder || "Search Accounts...";
  }

  get comboboxClass() {
    const classes = [
      "slds-combobox",
      "slds-dropdown-trigger",
      "slds-dropdown-trigger_click"
    ];

    if (this.isOpen) {
      classes.push("slds-is-open");
    }

    return classes.join(" ");
  }

  get dropdownClass() {
    const classes = ["slds-dropdown", "lookup__dropdown"];

    if (this.showCreateInDropdown) {
      classes.push("lookup__dropdown_with-footer");
    }

    if (this._dropdownOpensAbove) {
      classes.push("lookup__dropdown_above");
    }

    return classes.join(" ");
  }

  get dropdownStyle() {
    return this._dropdownStyle;
  }

  renderedCallback() {
    if (this.isOpen && this._needsDropdownPosition) {
      this.positionDropdown();
      this._needsDropdownPosition = false;
    }
  }

  get showCreateInDropdown() {
    return this.createEnabled !== false && !this.disabled;
  }

  get hasAllowedRecordIds() {
    return Array.isArray(this.allowedRecordIds) && this.allowedRecordIds.length > 0;
  }

  get normalizedAllowedRecordIds() {
    if (!this.hasAllowedRecordIds) {
      return [];
    }

    return this.allowedRecordIds.filter(Boolean);
  }

  isAllowedRecordId(recordId) {
    if (!this.hasAllowedRecordIds) {
      return true;
    }

    return this.normalizedAllowedRecordIds.includes(recordId);
  }

  get createButtonText() {
    if (this.createButtonLabel) {
      return this.createButtonLabel;
    }

    if (this.isReciprocalRoleLookup) {
      return "New Role";
    }

    if (this.isContactLookup) {
      return "New Contact";
    }

    return "New Account";
  }

  get createNewOptionLabel() {
    return `+ ${this.createButtonText}`;
  }

  get hasMultipleCreateRecordTypes() {
    return this.effectiveCreateRecordTypeOptions.length > 1;
  }

  get effectiveCreateRecordTypeOptions() {
    if (this.recordTypeId) {
      return [
        {
          recordTypeId: this.recordTypeId,
          label: this.createButtonText.replace(/^New\s+/i, ""),
          isPersonType: this.resolveIsPersonAccount()
        }
      ];
    }

    if (this._recordTypeDeveloperName && this._resolvedRecordTypeId) {
      return [
        {
          recordTypeId: this._resolvedRecordTypeId,
          developerName: this._recordTypeDeveloperName,
          label: this.createButtonText.replace(/^New\s+/i, ""),
          isPersonType: this._resolvedIsPersonType === true
        }
      ];
    }

    return this._createRecordTypeOptions;
  }

  get createModalHeaderLabel() {
    return this.createModalLabel || "New Record";
  }

  get effectiveRecordTypeId() {
    return this.recordTypeId || this._resolvedRecordTypeId || undefined;
  }

  get hasValue() {
    return Boolean(this._value);
  }

  get showSelectionPill() {
    return this.hasValue && !this.isEditing;
  }

  get showSearchInput() {
    return !this.showSelectionPill;
  }

  get hasSearchResults() {
    return this.searchResults.length > 0;
  }

  get showEmptyResults() {
    if (this.isReciprocalRoleLookup) {
      return (
        this.isOpen &&
        !this.isLoading &&
        !this.hasSearchResults &&
        (this.searchTerm.trim().length === 0 ||
          this.searchTerm.trim().length >= MIN_SEARCH_LENGTH)
      );
    }

    return (
      this.isOpen &&
      !this.isLoading &&
      this.searchTerm.trim().length >= MIN_SEARCH_LENGTH &&
      !this.hasSearchResults
    );
  }

  resetRecordTypeResolution() {
    this._recordTypeLoadStarted = false;
    this._resolvedRecordTypeId = null;
    this._resolvedIsPersonType = null;
    this._createRecordTypeOptions = [];
    this._createRecordTypesLoadPromise = null;
    this.isCreateRecordTypeMenuOpen = false;
  }

  async loadCreateRecordTypes() {
    if (this.createEnabled === false || !this.objectApiName) {
      this._createRecordTypeOptions = [];
      return;
    }

    if (this.recordTypeId || this._recordTypeDeveloperName) {
      return;
    }

    if (this._createRecordTypesLoadPromise) {
      await this._createRecordTypesLoadPromise;
      return;
    }

    this._createRecordTypesLoadPromise = getCreateableRecordTypes({
      objectApiName: this.objectApiName
    })
      .then((options) => {
        this._createRecordTypeOptions = Array.isArray(options)
          ? [...options].sort((left, right) =>
              String(left?.label || "").localeCompare(String(right?.label || ""))
            )
          : [];
      })
      .catch(() => {
        this._createRecordTypeOptions = [];
      })
      .finally(() => {
        this._createRecordTypesLoadPromise = null;
        if (this.isOpen) {
          this._needsDropdownPosition = true;
        }
      });

    await this._createRecordTypesLoadPromise;
  }

  loadRecordTypeId() {
    if (this.recordTypeId || this._recordTypeLoadStarted || !this.objectApiName) {
      return;
    }

    this._recordTypeLoadStarted = true;

    if (this._recordTypeDeveloperName) {
      getRecordTypeByDeveloperName({
        objectApiName: this.objectApiName,
        recordTypeDeveloperName: this._recordTypeDeveloperName
      })
        .then((recordTypeInfo) => {
          if (this.recordTypeId) {
            return;
          }

          if (recordTypeInfo?.recordTypeId) {
            this._resolvedRecordTypeId = recordTypeInfo.recordTypeId;
            this._resolvedIsPersonType = recordTypeInfo.isPersonType === true;
          }
        })
        .catch(() => {
          // Create can fall back to org default when record type is unavailable.
        });
      return;
    }

    if (this.objectApiName !== "Account") {
      return;
    }
  }

  resolveIsPersonAccount() {
    return this._resolvedIsPersonType === true;
  }

  async loadSelectedLabel(recordId) {
    if (!recordId) {
      return;
    }

    try {
      let name = "";

      if (this.isReciprocalRoleLookup) {
        name = await getReciprocalRoleName({ reciprocalRoleId: recordId });
      } else if (this.isContactLookup) {
        name = await getContactName({ contactId: recordId });
      } else {
        name = await getAccountName({ accountId: recordId });
      }

      if (name && this._value === recordId) {
        this.selectedLabel = name;
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[fscRelRecordLookup] failed to load record name", error);
    }
  }

  handleControlClick() {
    if (this.disabled) {
      return;
    }

    if (this.showSelectionPill) {
      this.beginEditing();
      return;
    }

    this.openDropdown();
    this.focusSearchInput();
  }

  handleInput(event) {
    this.searchTerm = event.target.value;
    this.openDropdown();
    this.scheduleSearch();
  }

  handleInputFocus() {
    if (this.disabled) {
      return;
    }

    this.openDropdown();
  }

  handleInputBlur() {
    window.setTimeout(() => {
      if (!this.isOpen) {
        return;
      }

      if (this._isDropdownPointerDown) {
        return;
      }

      if (!this.template.activeElement) {
        this.closeDropdown();
      }
    }, 150);
  }

  handleDropdownMouseDown(event) {
    this._isDropdownPointerDown = true;
    event.preventDefault();

    const handlePointerRelease = () => {
      this._isDropdownPointerDown = false;
      window.removeEventListener("mouseup", handlePointerRelease, true);
      window.removeEventListener("touchend", handlePointerRelease, true);
    };

    window.addEventListener("mouseup", handlePointerRelease, true);
    window.addEventListener("touchend", handlePointerRelease, true);
  }

  handleInputKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.closeDropdown();
    }
  }

  handleOptionSelect(event) {
    const recordId = event.currentTarget?.dataset?.recordId;
    if (!recordId) {
      return;
    }

    this.selectRecord(recordId, event.currentTarget?.dataset?.label || "");
  }

  handleClearSelection(event) {
    event.stopPropagation();
    this.clearSelection();
    this.beginEditing();
  }

  handleCreateClick(event) {
    event.stopPropagation();

    const createOptions = this.effectiveCreateRecordTypeOptions;

    if (createOptions.length === 0) {
      this.dispatchCreateRequest(null);
      return;
    }

    if (createOptions.length > 1) {
      this.isCreateRecordTypeMenuOpen = !this.isCreateRecordTypeMenuOpen;
      this._needsDropdownPosition = true;
      return;
    }

    this.dispatchCreateRequest(createOptions[0]);
  }

  handleCreateRecordTypeSelect(event) {
    event.stopPropagation();

    const recordTypeId = event.currentTarget?.dataset?.recordTypeId || "";
    const selectedOption =
      this.effectiveCreateRecordTypeOptions.find(
        (option) => option.recordTypeId === recordTypeId
      ) ||
      (recordTypeId
        ? {
            recordTypeId,
            label: event.currentTarget?.dataset?.label || "",
            isPersonType: event.currentTarget?.dataset?.isPersonType === "true"
          }
        : null);

    if (!selectedOption) {
      return;
    }

    this.dispatchCreateRequest(selectedOption);
  }

  dispatchCreateRequest(recordTypeOption) {
    this.closeDropdown();

    if (!this.objectApiName) {
      return;
    }

    const recordTypeLabel = String(recordTypeOption?.label || "").trim();
    const headerLabel = recordTypeLabel
      ? `New ${recordTypeLabel}`
      : this.createModalHeaderLabel;

    this.dispatchEvent(
      new CustomEvent("createrequest", {
        detail: {
          objectApiName: this.objectApiName,
          recordTypeId:
            recordTypeOption?.recordTypeId || this.effectiveRecordTypeId,
          headerLabel,
          isPersonAccount:
            recordTypeOption?.isPersonType === true ||
            this.resolveIsPersonAccount()
        },
        bubbles: true,
        composed: true
      })
    );
  }

  beginEditing() {
    this.isEditing = true;
    this.searchTerm = "";
    this.searchResults = [];
    this.openDropdown();
    window.setTimeout(() => this.focusSearchInput(), 0);
  }

  openDropdown() {
    this.isOpen = true;
    this._needsDropdownPosition = true;
    this.bindDropdownPositionListeners();
    this.template.host?.setAttribute("data-open", "true");
    void this.loadCreateRecordTypes();

    if (this.isReciprocalRoleLookup) {
      void this.runSearch();
    } else if (this.isAccountLookupWithScope) {
      void this.runSearch();
    }

    document.dispatchEvent(
      new CustomEvent("fscrellookupopen", {
        detail: { instanceId: this._instanceId },
        bubbles: true,
        composed: true
      })
    );
  }

  closeDropdown() {
    this.isOpen = false;
    this.isEditing = false;
    this.isLoading = false;
    this.isCreateRecordTypeMenuOpen = false;
    this.searchTerm = "";
    this.searchResults = [];
    this._dropdownStyle = "";
    this._dropdownOpensAbove = false;
    this.template.host?.removeAttribute("data-open");
    this.unbindDropdownPositionListeners();
  }

  bindDropdownPositionListeners() {
    if (this._dropdownPositionBound) {
      return;
    }

    this._dropdownRepositionHandler = () => {
      if (this.isOpen) {
        this.positionDropdown();
      }
    };

    window.addEventListener("scroll", this._dropdownRepositionHandler, true);
    window.addEventListener("resize", this._dropdownRepositionHandler);
    this._dropdownPositionBound = true;
  }

  unbindDropdownPositionListeners() {
    if (!this._dropdownPositionBound) {
      return;
    }

    window.removeEventListener("scroll", this._dropdownRepositionHandler, true);
    window.removeEventListener("resize", this._dropdownRepositionHandler);
    this._dropdownPositionBound = false;
  }

  positionDropdown() {
    const container = this.template.querySelector(".slds-combobox_container");
    if (!container) {
      return;
    }

    const containerRect = container.getBoundingClientRect();
    const spaceBelow =
      window.innerHeight - containerRect.bottom - DROPDOWN_VIEWPORT_PADDING_PX;
    const spaceAbove = containerRect.top - DROPDOWN_VIEWPORT_PADDING_PX;

    let maxHeight = Math.min(DROPDOWN_MAX_HEIGHT_PX, spaceBelow);
    let opensAbove = false;

    if (maxHeight < DROPDOWN_MIN_HEIGHT_PX && spaceAbove > spaceBelow) {
      maxHeight = Math.min(DROPDOWN_MAX_HEIGHT_PX, spaceAbove);
      opensAbove = true;
    }

    maxHeight = Math.max(Math.round(maxHeight), DROPDOWN_MIN_HEIGHT_PX);

    const footerReserve = this.showCreateInDropdown
      ? this.createFooterHeightPx
      : 0;
    const scrollMaxHeight = Math.max(
      maxHeight - footerReserve,
      DROPDOWN_MIN_HEIGHT_PX - footerReserve
    );

    this._dropdownOpensAbove = opensAbove;
    this._dropdownStyle = `max-height:${maxHeight}px;--lookup-scroll-max:${scrollMaxHeight}px`;
  }

  get createFooterHeightPx() {
    if (!this.showCreateInDropdown) {
      return 0;
    }

    let footerHeight = DROPDOWN_FOOTER_HEIGHT_PX;

    if (this.isCreateRecordTypeMenuOpen && this.hasMultipleCreateRecordTypes) {
      footerHeight +=
        this.effectiveCreateRecordTypeOptions.length *
        DROPDOWN_RECORD_TYPE_ROW_HEIGHT_PX;
    }

    return footerHeight;
  }

  clearSelection() {
    this._value = "";
    this._recordLabel = "";
    this.selectedLabel = "";
    this.dispatchChange("");
  }

  selectRecord(recordId, label) {
    if (!this.isAllowedRecordId(recordId)) {
      return;
    }

    this._value = recordId;
    this._recordLabel = (label || "").trim();
    this.selectedLabel = this._recordLabel;
    this.closeDropdown();
    this.dispatchChange(recordId);
  }

  dispatchChange(recordId) {
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: {
          recordId,
          recordLabel: this.selectedLabel || this._recordLabel || ""
        },
        bubbles: true,
        composed: true
      })
    );
  }

  scheduleSearch() {
    if (this._searchDebounceTimer) {
      clearTimeout(this._searchDebounceTimer);
    }

    this._searchDebounceTimer = window.setTimeout(() => {
      this.runSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  async runSearch() {
    const trimmedTerm = (this.searchTerm || "").trim();

    if (this.isReciprocalRoleLookup) {
      const shouldSearch =
        trimmedTerm.length === 0 ||
        trimmedTerm.length >= MIN_SEARCH_LENGTH;

      if (!shouldSearch) {
        this.searchResults = [];
        this.isLoading = false;
        return;
      }

      this.isLoading = true;

      try {
        const results = await searchReciprocalRoles({
          searchTerm: trimmedTerm,
          recordTypeDeveloperName: this._recordTypeDeveloperName || null
        });
        this.searchResults = Array.isArray(results) ? results : [];
      } catch (error) {
        this.searchResults = [];
        // eslint-disable-next-line no-console
        console.error("[fscRelRecordLookup] search failed", error);
      } finally {
        this.isLoading = false;
        this._needsDropdownPosition = true;
      }

      return;
    }

    if (trimmedTerm.length < MIN_SEARCH_LENGTH) {
      if (this.isAccountLookupWithScope) {
        this.isLoading = true;

        try {
          const results = await getAccountsByIds({
            accountIds: this.normalizedAllowedRecordIds
          });
          this.searchResults = Array.isArray(results) ? results : [];
        } catch (error) {
          this.searchResults = [];
          // eslint-disable-next-line no-console
          console.error("[fscRelRecordLookup] scoped account load failed", error);
        } finally {
          this.isLoading = false;
          this._needsDropdownPosition = true;
        }

        return;
      }

      this.searchResults = [];
      this.isLoading = false;
      return;
    }

    if (
      this.objectApiName !== "Account" &&
      this.objectApiName !== "Contact" &&
      this.objectApiName !== "Reciprocal_Role__c"
    ) {
      this.searchResults = [];
      this.isLoading = false;
      return;
    }

    this.isLoading = true;

    try {
      if (this.isContactLookup) {
        const results = await searchContacts({ searchTerm: trimmedTerm });
        this.searchResults = Array.isArray(results) ? results : [];
      } else if (this.isClassificationAccountSearch) {
        const results = await searchAccountsByClassification({
          searchTerm: trimmedTerm,
          classificationValue: this.classificationSearchValue
        });
        this.searchResults = Array.isArray(results) ? results : [];
      } else if (this.isAccountLookupWithScope) {
        const results = await searchAccountsInScope({
          searchTerm: trimmedTerm,
          personAccountsOnly: null,
          allowedAccountIds: this.normalizedAllowedRecordIds
        });
        this.searchResults = Array.isArray(results) ? results : [];
      } else {
        const results = await searchAccounts({
          searchTerm: trimmedTerm,
          personAccountsOnly: null
        });
        this.searchResults = Array.isArray(results) ? results : [];
      }
    } catch (error) {
      this.searchResults = [];
      // eslint-disable-next-line no-console
      console.error("[fscRelRecordLookup] search failed", error);
    } finally {
      this.isLoading = false;
    }
  }

  focusSearchInput() {
    const input = this.template.querySelector(".lookup__input");
    if (input) {
      input.focus();
    }
  }
}