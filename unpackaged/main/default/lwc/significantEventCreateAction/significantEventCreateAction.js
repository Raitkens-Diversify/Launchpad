/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api, wire } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import SIGNIFICANT_EVENT_OBJECT from "@salesforce/schema/Significant_Event__c";
import EVENT_TYPE_FIELD from "@salesforce/schema/Significant_Event__c.Event_Type__c";
import getActionContext from "@salesforce/apex/SignificantEventActionController.getActionContext";
import getSuggestedLinkedContacts from "@salesforce/apex/SignificantEventActionController.getSuggestedLinkedContacts";
import searchNonHouseholdAccounts from "@salesforce/apex/SignificantEventActionController.searchNonHouseholdAccounts";
import createSignificantEvent from "@salesforce/apex/SignificantEventActionController.createSignificantEvent";
import updateSignificantEvent from "@salesforce/apex/SignificantEventActionController.updateSignificantEvent";
import LightningConfirm from "lightning/confirm";

const EVENT_TYPE_OTHER = "Other";
const DELETE_VIA_UPDATE_CONFIRM_MESSAGE =
  "You may either go back and cancel without saving your changes, or confirm to save your changes and delete this Significant Event.";
const DELETE_CONFIRM_MESSAGE =
  "Are you sure you want to delete this Significant Event and its linked contacts?";
const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;

const AVATAR_CLASSES = [
  "avatar--blue",
  "avatar--yellow",
  "avatar--pink",
  "avatar--green",
  "avatar--purple",
  "avatar--teal"
];

const buildInitials = (name) => {
  const words = (name || "").trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return "";
  }

  if (words.length === 1) {
    return words[0].slice(0, 2).toUpperCase();
  }

  return `${words[0][0]}${words[1][0]}`.toUpperCase();
};

export default class SignificantEventCreateAction extends NavigationMixin(
  LightningElement
) {
  _recordId;
  _initializedRecordId;
  isEditModeFromContext = false;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this._recordId = value;
    if (value && value !== this._initializedRecordId) {
      this.initializeForm();
    }
  }

  @api editMode = false;
  @api suppressPostSaveNavigation = false;

  eventName = "";
  eventType = "";
  otherEventType = "";
  startDate = "";
  endDate = "";
  approximateDate = false;
  description = "";

  significantEventId = "";
  householdId = "";
  contextAccountId = "";
  isHouseholdLaunch = false;

  contactSearchTerm = "";
  isContactPickerExpanded = false;
  isSaving = false;
  isLoading = true;
  isDeletingEvent = false;

  selectedContacts = [];
  suggestedContactGroups = [];
  removedContactCandidates = [];
  searchResults = [];

  eventNameError = "";
  eventTypeError = "";
  otherEventTypeError = "";
  startDateError = "";
  linkedContactsError = "";

  searchDebounceTimeout;

  @wire(getObjectInfo, { objectApiName: SIGNIFICANT_EVENT_OBJECT })
  significantEventObjectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$defaultRecordTypeId",
    fieldApiName: EVENT_TYPE_FIELD
  })
  eventTypePicklist;

  get defaultRecordTypeId() {
    return this.significantEventObjectInfo?.data?.defaultRecordTypeId;
  }

  get isEditMode() {
    return this.editMode === true || this.isEditModeFromContext;
  }

  get isCreateMode() {
    return !this.isEditMode;
  }

  get pageTitle() {
    return this.isEditMode ? "Edit Significant Event" : "New Significant Event";
  }

  get saveButtonLabel() {
    return this.isEditMode ? "Update" : "Create Event";
  }

  get showDeleteButton() {
    return this.isEditMode;
  }

  get isUpdateDisabled() {
    if (this.isSaving) {
      return true;
    }

    if (this.isEditMode) {
      return false;
    }

    if (this.isLoading) {
      return true;
    }

    if (!this.eventName.trim()) {
      return true;
    }

    if (!this.eventType) {
      return true;
    }

    if (this.showOtherEventType && !this.otherEventType.trim()) {
      return true;
    }

    if (!this.startDate) {
      return true;
    }

    if (!this.hasSelectedContacts) {
      return true;
    }

    return false;
  }

  get isDeleteDisabled() {
    return this.isSaving;
  }

  get isDeleteViaUpdate() {
    return this.isEditMode && !this.hasSelectedContacts;
  }

  get eventTypeOptions() {
    const values = this.eventTypePicklist?.data?.values || [];
    return values.map((entry) => ({
      label: entry.label,
      value: entry.value
    }));
  }

  get showOtherEventType() {
    return this.eventType === EVENT_TYPE_OTHER;
  }

  get hasSelectedContacts() {
    return this.activeSelectedContacts.length > 0;
  }

  get hasDisplayedSelectedContacts() {
    return this.selectedContacts.length > 0;
  }

  get activeSelectedContacts() {
    return this.selectedContacts.filter((contact) => !contact.isPendingRemoval);
  }

  get showLinkedContactsBody() {
    return this.isContactPickerExpanded;
  }

  get isLinkedContactsCollapsed() {
    return !this.isContactPickerExpanded;
  }

  get showCloseContactPickerButton() {
    return this.isContactPickerExpanded && this.hasDisplayedSelectedContacts;
  }

  get showAddContactButton() {
    return !this.isContactPickerExpanded;
  }

  get linkedContactsSectionClass() {
    return this.isLinkedContactsCollapsed
      ? "section-card section-card--linked-contacts section-card--collapsed"
      : "section-card section-card--linked-contacts";
  }

  get linkedContactsBodyWrapperClass() {
    return this.isLinkedContactsCollapsed
      ? "section-card__body-wrapper section-card__body-wrapper--collapsed"
      : "section-card__body-wrapper";
  }

  get isLinkedContactsBodyHidden() {
    return !this.isContactPickerExpanded;
  }

  get showSelectedContactsPanel() {
    return this.hasDisplayedSelectedContacts;
  }

  get selectedContactCountLabel() {
    const count = this.activeSelectedContacts.length;
    return count === 1 ? "1 contact" : `${count} contacts`;
  }

  get selectedContactViewModels() {
    return this.selectedContacts.map((contact) => {
      const isPendingRemoval = contact.isPendingRemoval === true;
      const isPendingAddition =
        this.isEditMode &&
        !isPendingRemoval &&
        contact.isExistingOnRecord !== true;

      let rowClass = "selected-contact-row";
      let avatarClassList = `row-avatar ${contact.avatarClass}`;
      let nameClassList = "selected-contact-row__name";

      if (isPendingRemoval) {
        rowClass = "selected-contact-row selected-contact-row--removed";
        avatarClassList = "row-avatar row-avatar--removed";
        nameClassList =
          "selected-contact-row__name selected-contact-row__name--removed";
      } else if (isPendingAddition) {
        rowClass = "selected-contact-row selected-contact-row--added";
        avatarClassList = `row-avatar row-avatar--added ${contact.avatarClass}`;
        nameClassList =
          "selected-contact-row__name selected-contact-row__name--added";
      }

      return {
        ...contact,
        isPendingAddition,
        avatarClassList,
        nameClassList,
        rowClass,
        showUndo:
          this.isEditMode &&
          contact.isExistingOnRecord === true &&
          isPendingRemoval,
        showRemove: !isPendingRemoval,
        initials: contact.initials || buildInitials(contact.name)
      };
    });
  }

  get selectedAccountIds() {
    return this.activeSelectedContacts.map((contact) => contact.id);
  }

  get allSelectedAccountIds() {
    return this.selectedContacts.map((contact) => contact.id);
  }

  get visibleSuggestedContacts() {
    const seenIds = new Set();
    const selectedIds = new Set(this.allSelectedAccountIds);
    const contacts = [];
    let index = 0;

    for (const group of this.suggestedContactGroups || []) {
      for (const contact of group.contacts || []) {
        if (
          !contact?.accountId ||
          seenIds.has(contact.accountId) ||
          selectedIds.has(contact.accountId)
        ) {
          continue;
        }

        seenIds.add(contact.accountId);
        contacts.push(this.buildContactViewModel(contact, index));
        index += 1;
      }
    }

    for (const contact of this.removedContactCandidates || []) {
      if (
        !contact?.accountId ||
        seenIds.has(contact.accountId) ||
        selectedIds.has(contact.accountId)
      ) {
        continue;
      }

      seenIds.add(contact.accountId);
      contacts.push(this.buildContactViewModel(contact, index));
      index += 1;
    }

    return contacts;
  }

  get hasVisibleSuggestions() {
    return this.visibleSuggestedContacts.length > 0;
  }

  get filteredSearchResults() {
    const selectedIds = new Set(this.allSelectedAccountIds);
    return (this.searchResults || [])
      .filter((contact) => !selectedIds.has(contact.accountId))
      .map((contact, index) => this.buildContactViewModel(contact, index));
  }

  get hasSearchResults() {
    return this.filteredSearchResults.length > 0;
  }

  get showNoSearchResults() {
    const normalizedTerm = this.contactSearchTerm.trim();
    return (
      this.isContactPickerExpanded &&
      normalizedTerm.length >= MIN_SEARCH_LENGTH &&
      !this.hasSearchResults
    );
  }

  connectedCallback() {
    if (this.recordId) {
      this.initializeForm();
    } else {
      this.isLoading = false;
    }
  }

  disconnectedCallback() {
    if (this.searchDebounceTimeout) {
      clearTimeout(this.searchDebounceTimeout);
    }
  }

  async initializeForm() {
    if (!this.recordId) {
      this.isLoading = false;
      return;
    }

    this.isLoading = true;

    try {
      const context = await getActionContext({ recordId: this.recordId });
      this._initializedRecordId = this.recordId;
      this.isEditModeFromContext = context.isEditMode === true;
      this.applyContext(context);

      if (context.isEditMode) {
        this.applyFormData(context.eventData);
        this.isContactPickerExpanded = true;
      } else {
        this.isContactPickerExpanded = !this.hasSelectedContacts;
      }

      await this.refreshSuggestions();
    } catch (error) {
      this.showLoadErrorToast(this.reduceError(error));
    } finally {
      this.isLoading = false;
    }
  }

  applyContext(context) {
    this.householdId = context.householdId || "";
    this.contextAccountId = context.contextAccountId || "";
    this.isHouseholdLaunch = context.isHouseholdLaunch === true;
    this.selectedContacts = (context.defaultSelectedAccounts || []).map(
      (contact, index) => this.buildContactViewModel(contact, index)
    );
  }

  applyFormData(formData) {
    if (!formData) {
      return;
    }

    this.significantEventId = formData.significantEventId || "";
    this.eventName = formData.eventName || "";
    this.eventType = formData.eventType || "";
    this.otherEventType = formData.otherEventType || "";
    this.startDate = formData.startDate || "";
    this.endDate = formData.endDate || "";
    this.approximateDate = formData.approximateDate === true;
    this.description = formData.description || "";
    this.selectedContacts = (formData.selectedAccounts || []).map(
      (contact, index) =>
        this.buildContactViewModel(
          {
            ...contact,
            isExistingOnRecord: true
          },
          index
        )
    );
  }

  async refreshSuggestions() {
    if (!this.householdId && !this.contextAccountId) {
      this.suggestedContactGroups = [];
      return;
    }

    try {
      this.suggestedContactGroups = await getSuggestedLinkedContacts({
        householdId: this.householdId || null,
        contextAccountId: this.contextAccountId || null,
        isHouseholdLaunch: this.isHouseholdLaunch,
        selectedAccountIds: this.allSelectedAccountIds
      });
    } catch (error) {
      this.suggestedContactGroups = [];
      this.showErrorToast(this.reduceError(error));
    }
  }

  buildContactViewModel(contact, index = 0) {
    return {
      id: contact.accountId,
      name: contact.name,
      initials: buildInitials(contact.name),
      avatarClass: AVATAR_CLASSES[index % AVATAR_CLASSES.length],
      isHouseholdRelated: contact.isHouseholdRelated === true,
      isExistingOnRecord: contact.isExistingOnRecord === true,
      isPendingRemoval: contact.isPendingRemoval === true
    };
  }

  handleEventNameChange(event) {
    this.eventName = event.detail.value;
    this.eventNameError = "";
  }

  handleEventTypeChange(event) {
    this.eventType = event.detail.value;
    this.eventTypeError = "";

    if (this.eventType !== EVENT_TYPE_OTHER) {
      this.otherEventType = "";
      this.otherEventTypeError = "";
    }
  }

  handleOtherEventTypeChange(event) {
    this.otherEventType = event.detail.value;
    this.otherEventTypeError = "";
  }

  handleStartDateChange(event) {
    this.startDate = event.detail.value;
    this.startDateError = "";
  }

  handleEndDateChange(event) {
    this.endDate = event.detail.value;
  }

  handleApproximateDateChange(event) {
    this.approximateDate = event.detail.checked;
  }

  handleDescriptionChange(event) {
    this.description = event.detail.value;
  }

  handleContactSearchChange(event) {
    this.contactSearchTerm = event.detail.value;

    if (this.searchDebounceTimeout) {
      clearTimeout(this.searchDebounceTimeout);
    }

    const normalizedTerm = this.contactSearchTerm.trim();
    if (normalizedTerm.length < MIN_SEARCH_LENGTH) {
      this.searchResults = [];
      return;
    }

    this.searchDebounceTimeout = setTimeout(() => {
      this.executeContactSearch(normalizedTerm);
    }, SEARCH_DEBOUNCE_MS);
  }

  async executeContactSearch(searchTerm) {
    try {
      this.searchResults = await searchNonHouseholdAccounts({
        searchTerm
      });
    } catch (error) {
      this.searchResults = [];
      this.showErrorToast(this.reduceError(error));
    }
  }

  handleExpandContactPicker() {
    this.isContactPickerExpanded = true;
    this.linkedContactsError = "";
  }

  handleCollapseContactPicker() {
    this.isContactPickerExpanded = false;
    this.contactSearchTerm = "";
    this.searchResults = [];
  }

  async handleAddContact(event) {
    const contactId = event.currentTarget.dataset.contactId;
    const contact = this.findContactCandidate(contactId);

    if (
      !contact ||
      this.selectedContacts.some(
        (entry) => entry.id === contactId && entry.isPendingRemoval !== true
      )
    ) {
      return;
    }

    const existingPendingContact = this.selectedContacts.find(
      (entry) => entry.id === contactId && entry.isPendingRemoval === true
    );

    if (existingPendingContact) {
      this.selectedContacts = this.selectedContacts.map((entry) =>
        entry.id === contactId ? { ...entry, isPendingRemoval: false } : entry
      );
      this.removedContactCandidates = this.removedContactCandidates.filter(
        (entry) => entry.accountId !== contactId
      );
      this.linkedContactsError = "";
      this.isContactPickerExpanded = true;
      await this.refreshSuggestions();
      return;
    }

    this.selectedContacts = [
      ...this.selectedContacts,
      this.buildContactViewModel(contact, this.selectedContacts.length)
    ];
    this.removedContactCandidates = this.removedContactCandidates.filter(
      (entry) => entry.accountId !== contactId
    );
    this.linkedContactsError = "";
    this.isContactPickerExpanded = true;
    await this.refreshSuggestions();
  }

  async handleRemoveContact(event) {
    const contactId = event.currentTarget.dataset.contactId;
    const contact = this.selectedContacts.find(
      (entry) => entry.id === contactId
    );

    if (!contact || contact.isPendingRemoval) {
      return;
    }

    if (this.isEditMode && contact.isExistingOnRecord) {
      this.selectedContacts = this.selectedContacts.map((entry) =>
        entry.id === contactId ? { ...entry, isPendingRemoval: true } : entry
      );
      this.linkedContactsError = "";
      this.isContactPickerExpanded = true;
      await this.refreshSuggestions();
      return;
    }

    this.selectedContacts = this.selectedContacts.filter(
      (entry) => entry.id !== contactId
    );

    this.removedContactCandidates = [
      ...this.removedContactCandidates.filter(
        (entry) => entry.accountId !== contactId
      ),
      {
        accountId: contact.id,
        name: contact.name,
        isHouseholdRelated: contact.isHouseholdRelated === true
      }
    ];

    this.isContactPickerExpanded = true;
    await this.refreshSuggestions();
  }

  async handleUndoRemoveContact(event) {
    const contactId = event.currentTarget.dataset.contactId;

    this.selectedContacts = this.selectedContacts.map((entry) =>
      entry.id === contactId ? { ...entry, isPendingRemoval: false } : entry
    );
    this.linkedContactsError = "";
    await this.refreshSuggestions();
  }

  findContactCandidate(contactId) {
    const removedMatch = (this.removedContactCandidates || []).find(
      (contact) => contact.accountId === contactId
    );
    if (removedMatch) {
      return removedMatch;
    }

    for (const group of this.suggestedContactGroups || []) {
      const match = (group.contacts || []).find(
        (contact) => contact.accountId === contactId
      );
      if (match) {
        return match;
      }
    }

    return (this.searchResults || []).find(
      (contact) => contact.accountId === contactId
    );
  }

  handleCancel() {
    this.dispatchActionClose({ reason: "cancel" });
  }

  dispatchActionClose(detail = {}) {
    this.dispatchEvent(
      new CustomEvent("actionclose", {
        detail,
        bubbles: true,
        composed: true
      })
    );
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handleSaveEvent() {
    if (!this.validateForm()) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required information missing",
          message: "Enter the required information to proceed.",
          variant: "error"
        })
      );
      return;
    }

    if (this.isDeleteViaUpdate) {
      const confirmed = await LightningConfirm.open({
        label: "Delete Significant Event",
        message: DELETE_VIA_UPDATE_CONFIRM_MESSAGE,
        theme: "warning",
        variant: "header"
      });

      if (!confirmed) {
        return;
      }
    }

    await this.persistEvent();
  }

  async handleDeleteEvent() {
    if (!this.isEditMode || this.isSaving) {
      return;
    }

    const confirmed = await LightningConfirm.open({
      label: "Delete Significant Event",
      message: DELETE_CONFIRM_MESSAGE,
      theme: "warning",
      variant: "header"
    });

    if (!confirmed) {
      return;
    }

    await this.deleteEvent();
  }

  async deleteEvent() {
    this.isSaving = true;
    this.isDeletingEvent = true;

    try {
      const request = {
        significantEventId: this.significantEventId,
        linkedAccountIds: []
      };

      const saveResult = await updateSignificantEvent({
        requestJson: JSON.stringify(request)
      });

      this.dispatchActionClose({ reason: "delete", saveResult });
      await this.reloadRecordView(saveResult);
    } catch (error) {
      this.showErrorToast(this.reduceError(error));
    } finally {
      this.isSaving = false;
      this.isDeletingEvent = false;
    }
  }

  async persistEvent() {
    this.isSaving = true;

    if (this.isDeleteViaUpdate) {
      this.isDeletingEvent = true;
    }

    try {
      const request = {
        significantEventId: this.significantEventId,
        eventName: this.eventName.trim(),
        eventType: this.eventType,
        otherEventType: this.showOtherEventType
          ? this.otherEventType.trim()
          : null,
        startDate: this.startDate,
        endDate: this.endDate || null,
        approximateDate: this.approximateDate,
        description: this.description,
        contextAccountId: this.contextAccountId,
        householdId: this.householdId,
        linkedAccountIds: this.selectedAccountIds
      };

      const saveResult = this.isEditMode
        ? await updateSignificantEvent({
            requestJson: JSON.stringify(request)
          })
        : await createSignificantEvent({
            requestJson: JSON.stringify(request)
          });

      if (this.isCreateMode) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Save Successful",
            message: saveResult.message,
            variant: "success"
          })
        );
      }

      this.dispatchActionClose({
        reason: this.isDeleteViaUpdate ? "delete" : "save",
        saveResult
      });

      if (this.isEditMode) {
        await this.reloadRecordView(saveResult);
      }
    } catch (error) {
      this.showErrorToast(this.reduceError(error));
    } finally {
      this.isSaving = false;
      this.isDeletingEvent = false;
    }
  }

  async reloadRecordView(saveResult) {
    if (this.suppressPostSaveNavigation) {
      return;
    }

    const viewRecordId = this.resolveRefreshRecordId(saveResult);

    if (!viewRecordId) {
      window.location.reload();
      return;
    }

    this[NavigationMixin.Navigate](
      {
        type: "standard__recordPage",
        attributes: {
          recordId: viewRecordId,
          actionName: "view"
        }
      },
      true
    );
  }

  resolveRefreshRecordId(saveResult) {
    if (this.isDeletingEvent) {
      return this.householdId || this.contextAccountId || null;
    }

    if (this.isEditMode) {
      return saveResult?.significantEventId || this.recordId;
    }

    return this.contextAccountId || this.recordId;
  }

  validateForm() {
    let isValid = true;

    this.eventNameError = "";
    this.eventTypeError = "";
    this.otherEventTypeError = "";
    this.startDateError = "";
    this.linkedContactsError = "";

    if (!this.eventName.trim()) {
      this.eventNameError = "Event Name is required.";
      isValid = false;
    }

    if (!this.eventType) {
      this.eventTypeError = "Event Type is required.";
      isValid = false;
    }

    if (this.showOtherEventType && !this.otherEventType.trim()) {
      this.otherEventTypeError = "Other Event Type is required.";
      isValid = false;
    }

    if (!this.startDate) {
      this.startDateError = "Start Date is required.";
      isValid = false;
    }

    if (this.isCreateMode && !this.hasSelectedContacts) {
      this.linkedContactsError = "Add at least one linked contact.";
      isValid = false;
    }

    return isValid;
  }

  showLoadErrorToast(message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Unable to load Significant Event",
        message,
        variant: "error"
      })
    );
  }

  showErrorToast(message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Unable to save Significant Event",
        message,
        variant: "error"
      })
    );
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((entry) => entry.message).join(", ");
    }

    if (typeof error?.body?.message === "string") {
      return error.body.message;
    }

    if (typeof error?.message === "string") {
      return error.message;
    }

    return "An unexpected error occurred.";
  }
}