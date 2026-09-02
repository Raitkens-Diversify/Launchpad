/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 */
import { api, wire } from "lwc";
import LightningModal from "lightning/modal";
import getAccountAccountRelationshipAssociationTypeOptions from "@salesforce/apex/FscRelHouseholdController.getAccountAccountRelationshipAssociationTypeOptions";
import saveAccountRelationship from "@salesforce/apex/FscRelHouseholdController.saveAccountRelationship";
import deleteAccountRelationships from "@salesforce/apex/FscRelHouseholdController.deleteAccountRelationships";
import getAccountName from "@salesforce/apex/FscRelHouseholdController.getAccountName";
import FscRelCreateRecordModal from "c/fscRelCreateRecordModal";
import { extractApexError, buildModalSaveMessage, buildModalSaveButtonLabel, ensureFscRelModalStyles } from "c/fscRelUtils";

const BUSINESS_ACCOUNT_RECORD_TYPE_DEVELOPER_NAME = "Business_Account";

const ACCOUNT_FILTER = Object.freeze({
  criteria: [
    {
      fieldPath: "IsPersonAccount",
      operator: "eq",
      value: false
    }
  ]
});

export default class FscRelAddAccountRelationshipModal extends LightningModal {
  @api rootAccountId;
  @api rootAccountName = "";

  _initialAccounts = [];
  accountRows = [];
  pendingDeleteRelationIds = [];
  nextRowId = 1;
  isSaving = false;
  bannerMessage = "";
  bannerVariant = "error";
  savedSinceOpen = false;

  _associationTypePicklistValues = [];

  @wire(getAccountAccountRelationshipAssociationTypeOptions)
  wiredAssociationTypePicklist({ data }) {
    if (Array.isArray(data)) {
      this._associationTypePicklistValues = data.map((option) => ({
        label: option.label,
        value: option.value
      }));
    }
  }

  @api
  get initialAccounts() {
    return this._initialAccounts;
  }
  set initialAccounts(value) {
    this._initialAccounts = Array.isArray(value) ? value : [];
    this.accountRows = this.buildInitialRows(this._initialAccounts);
  }

  connectedCallback() {
    ensureFscRelModalStyles(this);

    if (this.accountRows.length === 0) {
      this.accountRows = this.buildInitialRows(this._initialAccounts);
    }
  }

  get associationTypeOptions() {
    return this._associationTypePicklistValues || [];
  }

  get accountFilter() {
    return ACCOUNT_FILTER;
  }

  get businessAccountRecordTypeDeveloperName() {
    return BUSINESS_ACCOUNT_RECORD_TYPE_DEVELOPER_NAME;
  }

  get rowViewModels() {
    const rowCount = this.accountRows.length;

    return this.accountRows.map((row, index) => {
      const isExisting = Boolean(row.isExisting);
      const isPendingDelete = Boolean(row.isPendingDelete);
      const hasError = Boolean(row.errorMessage);
      const inputsDisabled = isPendingDelete;

      const rowWrapperClasses = ["modal-table__row-wrapper"];
      if (isPendingDelete) {
        rowWrapperClasses.push("modal-table__row-wrapper_pending-delete");
      }
      if (hasError && !isPendingDelete) {
        rowWrapperClasses.push("modal-table__row-wrapper_error");
      }

      return {
        ...row,
        rowNumber: index + 1,
        hasError,
        hasAccount: Boolean(row.accountId),
        canRemove: !isPendingDelete && (isExisting || rowCount > 1),
        isExisting,
        isPendingDelete,
        isAccountDisabled: isExisting || inputsDisabled,
        isFieldDisabled: inputsDisabled,
        rowWrapperClass: rowWrapperClasses.join(" ")
      };
    });
  }

  get readyCount() {
    return this.accountRows.filter((row) => Boolean(row.accountId)).length;
  }

  get saveButtonLabel() {
    return buildModalSaveButtonLabel(this.readyCount);
  }

  get cancelButtonLabel() {
    return this.savedSinceOpen ? "Close" : "Cancel";
  }

  get isSaveDisabled() {
    return this.isSaving;
  }

  get hasBanner() {
    return Boolean(this.bannerMessage);
  }

  get bannerClass() {
    const variant =
      this.bannerVariant === "success"
        ? "slds-theme_success"
        : this.bannerVariant === "warning"
          ? "slds-theme_warning"
          : "slds-theme_error";
    return `modal-banner slds-notify slds-notify_alert ${variant}`;
  }

  buildInitialRows(initialAccounts) {
    const rows = [];

    (initialAccounts || []).forEach((account) => {
      const rowId = this.nextRowId;
      this.nextRowId += 1;

      rows.push({
        id: rowId,
        relationId: account.relationId || "",
        isExisting: Boolean(account.relationId),
        accountId: account.accountId || "",
        accountName: account.name || "",
        associationType: account.associationType || "",
        errorMessage: "",
        isPendingDelete: false
      });
    });

    rows.push(this.createEmptyRow(this.nextRowId));
    this.nextRowId += 1;

    return rows;
  }

  createEmptyRow(rowId) {
    return {
      id: rowId,
      relationId: "",
      isExisting: false,
      accountId: "",
      accountName: "",
      associationType: "",
      errorMessage: "",
      isPendingDelete: false
    };
  }

  handleAddRow() {
    this.accountRows = [...this.accountRows, this.createEmptyRow(this.nextRowId)];
    this.nextRowId += 1;
  }

  handleRemoveRow(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const target = this.accountRows.find((row) => row.id === rowId);
    if (!target) {
      return;
    }

    if (target.isExisting && target.relationId) {
      if (!this.pendingDeleteRelationIds.includes(target.relationId)) {
        this.pendingDeleteRelationIds = [
          ...this.pendingDeleteRelationIds,
          target.relationId
        ];
      }
      this.updateRow(rowId, { isPendingDelete: true });
      return;
    }

    if (this.accountRows.length <= 1) {
      return;
    }

    this.accountRows = this.accountRows.filter((row) => row.id !== rowId);
  }

  handleUndoRemoveRow(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const target = this.accountRows.find((row) => row.id === rowId);
    if (!target) {
      return;
    }

    if (target.relationId) {
      this.pendingDeleteRelationIds = this.pendingDeleteRelationIds.filter(
        (id) => id !== target.relationId
      );
    }
    this.updateRow(rowId, { isPendingDelete: false });
  }

  handleAccountChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const value = event.detail?.recordId || "";
    if (value && value === this.rootAccountId) {
      this.updateRow(rowId, {
        accountId: "",
        accountName: "",
        errorMessage: "The root account cannot be added as a related account."
      });
      return;
    }

    this.updateRow(rowId, {
      accountId: value,
      accountName: "",
      errorMessage: ""
    });
    this.fetchAccountNameForRow(rowId, value);
  }

  async handleRecordCreateRequest(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const detail = event.detail || {};
    const result = await FscRelCreateRecordModal.open({
      size: "large",
      objectApiName: detail.objectApiName || "Account",
      recordTypeId: detail.recordTypeId,
      headerLabel: detail.headerLabel || "New Account"
    });

    if (!result?.recordId) {
      return;
    }

    if (result.recordId === this.rootAccountId) {
      this.updateRow(rowId, {
        accountId: "",
        accountName: "",
        errorMessage: "The root account cannot be added as a related account."
      });
      return;
    }

    this.updateRow(rowId, {
      accountId: result.recordId,
      accountName: "",
      errorMessage: ""
    });
    this.fetchAccountNameForRow(rowId, result.recordId);
  }

  fetchAccountNameForRow(rowId, accountId) {
    if (!rowId || !accountId) {
      return;
    }

    getAccountName({ accountId })
      .then((name) => {
        if (!name) {
          return;
        }
        const current = this.accountRows.find((row) => row.id === rowId);
        if (current && current.accountId === accountId) {
          this.updateRow(rowId, { accountName: name });
        }
      })
      .catch(() => {
        // Non-fatal; account name is optional in the modal.
      });
  }

  handleAssociationTypeChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    this.updateRow(rowId, {
      associationType: event.detail?.value || "",
      errorMessage: ""
    });
  }

  updateRow(rowId, patch) {
    this.accountRows = this.accountRows.map((row) =>
      row.id === rowId ? { ...row, ...patch } : row
    );
  }

  resolveRowId(event) {
    const datasetSource =
      event.currentTarget?.dataset || event.target?.dataset || {};
    const rowId = Number(datasetSource.rowId);
    return Number.isFinite(rowId) ? rowId : null;
  }

  handleCancel() {
    this.closeAllRecordLookups();
    this.close({ confirmed: this.savedSinceOpen });
  }

  handleModalBodyClick(event) {
    if (!event.target.closest("c-fsc-rel-record-lookup")) {
      this.closeAllRecordLookups();
    }
  }

  closeAllRecordLookups() {
    document.dispatchEvent(
      new CustomEvent("fscrellookupclose", {
        bubbles: true,
        composed: true
      })
    );
  }

  handleDismissBanner() {
    this.bannerMessage = "";
  }

  async handleSave() {
    if (this.isSaving) {
      return;
    }

    this.bannerMessage = "";

    if (!this.rootAccountId) {
      this.bannerMessage =
        "No root account id was provided to the modal. Save aborted.";
      this.bannerVariant = "error";
      return;
    }

    const { validated: rowsToCommit, skippedCount } =
      this.collectCommittableRows();
    const rowsToDelete = [...this.pendingDeleteRelationIds];

    if (
      rowsToCommit.length === 0 &&
      rowsToDelete.length === 0 &&
      skippedCount === 0
    ) {
      this.close({
        confirmed: true,
        message: buildModalSaveMessage()
      });
      return;
    }

    if (skippedCount > 0) {
      this.bannerMessage = "Fix the highlighted rows before saving.";
      this.bannerVariant = "error";
      return;
    }

    this.isSaving = true;
    let successCount = 0;
    let saveFailedCount = 0;
    const updatedRows = [...this.accountRows];

    for (const row of rowsToCommit) {
      const targetIndex = updatedRows.findIndex(
        (candidate) => candidate.id === row.id
      );
      if (targetIndex === -1) {
        continue;
      }

      const payload = {
        relationId: row.relationId || "",
        accountId: row.accountId,
        associationType: row.associationType || ""
      };

      try {
        const result = await saveAccountRelationship({
          rootAccountId: this.rootAccountId,
          accountJson: JSON.stringify(payload)
        });

        if (result?.success) {
          successCount += 1;
          updatedRows[targetIndex] = {
            ...updatedRows[targetIndex],
            errorMessage: "",
            relationId:
              result.relationId || updatedRows[targetIndex].relationId || "",
            isExisting: Boolean(
              result.relationId || updatedRows[targetIndex].relationId
            )
          };
        } else {
          saveFailedCount += 1;
          updatedRows[targetIndex] = {
            ...updatedRows[targetIndex],
            errorMessage: result?.message || "Unknown error."
          };
        }
      } catch (error) {
        saveFailedCount += 1;
        updatedRows[targetIndex] = {
          ...updatedRows[targetIndex],
          errorMessage: extractApexError(
            error,
            "Unexpected error saving relationship."
          )
        };
      }
    }

    this.accountRows = updatedRows;

    let deletedCount = 0;
    let deleteFailedMessage = "";
    if (rowsToDelete.length > 0 && saveFailedCount === 0) {
      try {
        const deleteResult = await deleteAccountRelationships({
          relationIds: rowsToDelete
        });
        if (deleteResult?.success) {
          deletedCount = deleteResult.deletedCount || rowsToDelete.length;
          this.pendingDeleteRelationIds = [];
        } else {
          deleteFailedMessage =
            deleteResult?.message ||
            "Failed to delete one or more relationships.";
        }
      } catch (error) {
        deleteFailedMessage = extractApexError(
          error,
          "Unexpected error deleting relationship."
        );
      }
    }

    if (
      saveFailedCount === 0 &&
      !deleteFailedMessage &&
      skippedCount === 0 &&
      (successCount > 0 || deletedCount > 0)
    ) {
      const message = buildModalSaveMessage({
        successCount,
        deletedCount
      });

      this.close({ confirmed: true, message });
      return;
    }

    this.isSaving = false;
    this.savedSinceOpen = successCount > 0 || deletedCount > 0;

    if (deleteFailedMessage) {
      this.bannerMessage = deleteFailedMessage;
      this.bannerVariant = "error";
      return;
    }

    this.bannerMessage = `${successCount} saved, ${saveFailedCount} failed. See errors below each row.`;
    this.bannerVariant = "error";
  }

  isRowChanged(row) {
    if (!row.isExisting || !row.relationId) {
      return true;
    }

    const original = this._initialAccounts.find(
      (account) => account.relationId === row.relationId
    );
    if (!original) {
      return true;
    }

    return (row.associationType || "") !== (original.associationType || "");
  }

  collectCommittableRows() {
    const validated = [];
    const seenAccountIds = new Map();
    let skippedCount = 0;

    this.accountRows.forEach((row) => {
      if (row.isPendingDelete) {
        return;
      }

      const hasAnyData = row.accountId || row.associationType;
      if (!hasAnyData) {
        return;
      }

      if (!row.accountId) {
        this.updateRow(row.id, {
          errorMessage: "Select an account from the list."
        });
        skippedCount += 1;
        return;
      }

      if (row.accountId === this.rootAccountId) {
        this.updateRow(row.id, {
          errorMessage: "The root account cannot be added as a related account."
        });
        skippedCount += 1;
        return;
      }

      if (row.isExisting && row.relationId && !this.isRowChanged(row)) {
        return;
      }

      if (seenAccountIds.has(row.accountId)) {
        this.updateRow(row.id, {
          errorMessage:
            "This account is already related. Remove the duplicate row."
        });
        skippedCount += 1;
        return;
      }

      seenAccountIds.set(row.accountId, row.id);
      validated.push(row);
    });

    return { validated, skippedCount };
  }
}